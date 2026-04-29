import { createHash } from "crypto";
import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { RtcRole, RtcTokenBuilder } from "agora-access-token";
import {
  getTokensForUids,
  sendChunked,
  cleanupInvalidTokens,
} from "./utils/fcm";

function getDb() {
  return admin.firestore();
}

const AGORA_APP_ID = process.env.AGORA_APP_ID ?? "";
const AGORA_APP_CERTIFICATE = process.env.AGORA_APP_CERTIFICATE ?? "";
const VOICE_CALL_MAX_PARTICIPANTS = 8;
const VOICE_CALL_MAX_GROUP_MEMBERS = 20;
const VOICE_CALL_COOLDOWN_MS = 60 * 1000;
const VOICE_CALL_MAX_DURATION_MS = 3 * 60 * 60 * 1000;
const VOICE_CALL_DAILY_START_LIMIT = 20;
const VOICE_CALL_HEARTBEAT_STALE_MS = 30 * 1000;
const VOICE_CALL_TOKEN_TTL_SECONDS = 60 * 60;

type RoomData = {
  type?: string;
  ref_group_id?: string | null;
  member_ids?: string[];
  name?: string;
  active_call_id?: string | null;
  group_name?: string;
  group_profile_image?: string;
};

type GroupMemberData = {
  role?: string;
  permissions?: Record<string, unknown>;
};

function ensureAgoraConfigured() {
  if (!AGORA_APP_ID || !AGORA_APP_CERTIFICATE) {
    throw new HttpsError(
      "failed-precondition",
      "Agora environment variables are not configured."
    );
  }
}

function toAgoraUid(uid: string) {
  const hash = createHash("sha256").update(uid).digest();
  return hash.readUInt32BE(0) & 0x7fffffff;
}

function buildAgoraToken(channelName: string, agoraUid: number) {
  ensureAgoraConfigured();
  const now = Math.floor(Date.now() / 1000);
  const privilegeExpiredTs = now + VOICE_CALL_TOKEN_TTL_SECONDS;
  return RtcTokenBuilder.buildTokenWithUid(
    AGORA_APP_ID,
    AGORA_APP_CERTIFICATE,
    channelName,
    agoraUid,
    RtcRole.PUBLISHER,
    privilegeExpiredTs
  );
}

async function getRoomOrThrow(roomId: string, uid: string) {
  const roomDoc = await getDb().collection("chat_rooms").doc(roomId).get();
  if (!roomDoc.exists) {
    throw new HttpsError("not-found", "Chat room not found.");
  }

  const room = roomDoc.data() as RoomData;
  const memberIds = room.member_ids ?? [];
  if (!memberIds.includes(uid)) {
    throw new HttpsError("permission-denied", "Not a room member.");
  }

  return { roomDoc, room, memberIds };
}

async function assertStartPermission(room: RoomData, uid: string) {
  const roomType = room.type ?? "";
  if (roomType === "direct" || roomType === "group_direct") {
    return;
  }

  if (roomType !== "group_all" && roomType !== "group_sub") {
    throw new HttpsError(
      "failed-precondition",
      "Voice calls are not supported for this room type."
    );
  }

  if (!room.ref_group_id) {
    throw new HttpsError("failed-precondition", "Group reference is missing.");
  }

  const [groupDoc, memberDoc] = await Promise.all([
    getDb().collection("groups").doc(room.ref_group_id).get(),
    getDb()
      .collection("groups")
      .doc(room.ref_group_id)
      .collection("members")
      .doc(uid)
      .get(),
  ]);

  if (!groupDoc.exists || !memberDoc.exists) {
    throw new HttpsError("permission-denied", "Group membership is invalid.");
  }

  const group = groupDoc.data() ?? {};
  const member = memberDoc.data() as GroupMemberData;
  const memberCount = (group.member_count as number | undefined) ?? 0;
  if (memberCount > VOICE_CALL_MAX_GROUP_MEMBERS) {
    throw new HttpsError(
      "failed-precondition",
      `Voice calls are allowed only for groups with up to ${VOICE_CALL_MAX_GROUP_MEMBERS} members.`
    );
  }

  const role = member.role ?? "member";
  const canStart =
    role === "owner" ||
    (role === "manager" &&
      member.permissions?.can_start_voice_call === true);

  if (!canStart) {
    throw new HttpsError(
      "permission-denied",
      "You do not have permission to start a voice call."
    );
  }
}

async function hasBlockedRelationship(uid: string, otherUid: string) {
  const [a, b] = await Promise.all([
    getDb()
      .collection("users")
      .doc(uid)
      .collection("blocked")
      .doc(otherUid)
      .get(),
    getDb()
      .collection("users")
      .doc(otherUid)
      .collection("blocked")
      .doc(uid)
      .get(),
  ]);
  return a.exists || b.exists;
}

async function assertNoBlockedRelationship(uid: string, memberIds: string[]) {
  const others = memberIds.filter((memberId) => memberId !== uid);
  for (const otherUid of others) {
    if (await hasBlockedRelationship(uid, otherUid)) {
      throw new HttpsError(
        "permission-denied",
        "Voice calls are unavailable due to a blocked user relationship."
      );
    }
  }
}

function getKstDayBounds() {
  const now = new Date();
  const utcMs = now.getTime() + now.getTimezoneOffset() * 60 * 1000;
  const kstNow = new Date(utcMs + 9 * 60 * 60 * 1000);
  const start = new Date(
    Date.UTC(
      kstNow.getUTCFullYear(),
      kstNow.getUTCMonth(),
      kstNow.getUTCDate(),
      -9,
      0,
      0,
      0
    )
  );
  const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
  return {
    start: admin.firestore.Timestamp.fromDate(start),
    end: admin.firestore.Timestamp.fromDate(end),
  };
}

async function assertStartRateLimits(roomId: string, uid: string) {
  const db = getDb();
  const recentSnap = await db
    .collection("chat_rooms")
    .doc(roomId)
    .collection("calls")
    .orderBy("started_at", "desc")
    .limit(1)
    .get();

  if (!recentSnap.empty) {
    const recent = recentSnap.docs[0].data();
    const startedAt = recent.started_at as admin.firestore.Timestamp | undefined;
    if (startedAt && Date.now() - startedAt.toDate().getTime() < VOICE_CALL_COOLDOWN_MS) {
      throw new HttpsError(
        "resource-exhausted",
        "Voice call cooldown is active for this room."
      );
    }
  }

  const day = getKstDayBounds();
  const dailySnap = await db
    .collectionGroup("calls")
    .where("started_by", "==", uid)
    .where("type", "==", "voice")
    .where("started_at", ">=", day.start)
    .where("started_at", "<", day.end)
    .get();

  if (dailySnap.size >= VOICE_CALL_DAILY_START_LIMIT) {
    throw new HttpsError(
      "resource-exhausted",
      "Daily voice call start limit exceeded."
    );
  }
}

async function notifyVoiceCallStarted(
  roomId: string,
  callerUid: string,
  callId: string,
  channelName: string,
  room: RoomData,
  memberIds: string[]
) {
  const receiverIds: string[] = [];
  for (const uid of memberIds) {
    if (uid === callerUid) continue;
    if (await hasBlockedRelationship(uid, callerUid)) continue;
    receiverIds.push(uid);
  }

  if (receiverIds.length === 0) return;

  const tokens = await getTokensForUids(receiverIds);
  if (tokens.length === 0) return;

  const roomName = room.name ?? room.group_name ?? "Voice Call";
  const payload: Omit<admin.messaging.MulticastMessage, "tokens"> = {
    notification: {
      title: roomName,
      body: "음성통화가 시작되었습니다.",
    },
    data: {
      type: "voice_call",
      roomId,
      callId,
      channelName,
      notificationTitle: roomName,
      notificationBody: "음성통화가 시작되었습니다.",
      avatarUrl: room.group_profile_image ?? "",
    },
    android: {
      priority: "high",
      collapseKey: `voice_call_${roomId}`,
      notification: {
        channelId: "chat_channel",
      },
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
          badge: 1,
          contentAvailable: true,
        },
      },
    },
  };

  const invalidTokens = await sendChunked(tokens, payload);
  await cleanupInvalidTokens(invalidTokens);
}

async function endCallIfEmpty(roomId: string, callId: string) {
  const db = getDb();
  await db.runTransaction(async (tx) => {
    const roomRef = db.collection("chat_rooms").doc(roomId);
    const callRef = roomRef.collection("calls").doc(callId);
    const [roomSnap, callSnap] = await Promise.all([tx.get(roomRef), tx.get(callRef)]);

    if (!callSnap.exists) return;
    const call = callSnap.data() ?? {};
    if (call.status !== "active") return;

    const participantsSnap = await tx.get(
      callRef.collection("participants").where("left_at", "==", null)
    );
    const activeCount = participantsSnap.size;

    const updates: Record<string, unknown> = {
      participant_count: activeCount,
      last_activity_at: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (activeCount <= 0) {
      updates.status = "ended";
      updates.ended_at = admin.firestore.FieldValue.serverTimestamp();
      tx.update(roomRef, {
        active_call_id: admin.firestore.FieldValue.delete(),
        active_call_type: admin.firestore.FieldValue.delete(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    tx.update(callRef, updates);

    const room = roomSnap.data() as RoomData | undefined;
    if (room?.active_call_id === callId && activeCount <= 0) {
      tx.set(
        db.collection("call_logs").doc(callId),
        {
          room_id: roomId,
          call_id: callId,
          type: "voice",
          ended_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }
  });
}

export const startVoiceCall = onCall(
  { region: "asia-northeast3" },
  async (request) => {
    const uid = request.auth?.uid;
    const roomId = request.data?.roomId as string | undefined;

    if (!uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }
    if (!roomId) {
      throw new HttpsError("invalid-argument", "roomId is required.");
    }

    const db = getDb();
    const { roomDoc, room, memberIds } = await getRoomOrThrow(roomId, uid);
    await assertStartPermission(room, uid);
    await assertNoBlockedRelationship(uid, memberIds);
    await assertStartRateLimits(roomId, uid);

    const roomData = roomDoc.data() as RoomData;
    if (roomData.active_call_id) {
      throw new HttpsError(
        "already-exists",
        "An active voice call already exists in this room."
      );
    }

    const callRef = roomDoc.ref.collection("calls").doc();
    const channelName = `${roomId}_${Date.now()}`;

    await db.runTransaction(async (tx) => {
      const freshRoomSnap = await tx.get(roomDoc.ref);
      const freshRoom = freshRoomSnap.data() as RoomData | undefined;
      if (!freshRoom) {
        throw new HttpsError("not-found", "Chat room not found.");
      }
      if (freshRoom.active_call_id) {
        throw new HttpsError(
          "already-exists",
          "An active voice call already exists in this room."
        );
      }

      tx.set(callRef, {
        type: "voice",
        status: "active",
        started_by: uid,
        started_at: admin.firestore.FieldValue.serverTimestamp(),
        ended_at: null,
        channel_name: channelName,
        participant_count: 0,
        max_participants: VOICE_CALL_MAX_PARTICIPANTS,
        last_activity_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      tx.update(roomDoc.ref, {
        active_call_id: callRef.id,
        active_call_type: "voice",
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      tx.set(
        db.collection("call_logs").doc(callRef.id),
        {
          room_id: roomId,
          call_id: callRef.id,
          type: "voice",
          started_by: uid,
          started_at: admin.firestore.FieldValue.serverTimestamp(),
          channel_name: channelName,
        },
        { merge: true }
      );
    });

    await notifyVoiceCallStarted(
      roomId,
      uid,
      callRef.id,
      channelName,
      room,
      memberIds
    );

    return {
      success: true,
      callId: callRef.id,
    };
  }
);

export const joinVoiceCall = onCall(
  { region: "asia-northeast3" },
  async (request) => {
    const uid = request.auth?.uid;
    const roomId = request.data?.roomId as string | undefined;
    const callId = request.data?.callId as string | undefined;
    const device = request.data?.device as string | undefined;

    if (!uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }
    if (!roomId || !callId) {
      throw new HttpsError("invalid-argument", "roomId and callId are required.");
    }

    const db = getDb();
    const { roomDoc, room, memberIds } = await getRoomOrThrow(roomId, uid);
    await assertNoBlockedRelationship(uid, memberIds);

    const callRef = roomDoc.ref.collection("calls").doc(callId);
    const participantRef = callRef.collection("participants").doc(uid);
    const agoraUid = toAgoraUid(uid);

    const result = await db.runTransaction(async (tx) => {
      const [roomSnap, callSnap, participantSnap] = await Promise.all([
        tx.get(roomDoc.ref),
        tx.get(callRef),
        tx.get(participantRef),
      ]);

      const freshRoom = roomSnap.data() as RoomData | undefined;
      if (!freshRoom || freshRoom.active_call_id !== callId) {
        throw new HttpsError("failed-precondition", "This call is no longer active.");
      }
      if (!callSnap.exists) {
        throw new HttpsError("not-found", "Call not found.");
      }

      const call = callSnap.data() ?? {};
      if (call.status !== "active") {
        throw new HttpsError("failed-precondition", "Call already ended.");
      }

      const participantCount =
        (call.participant_count as number | undefined) ?? 0;
      const wasActiveParticipant =
        participantSnap.exists && participantSnap.data()?.left_at == null;

      if (!wasActiveParticipant && participantCount >= VOICE_CALL_MAX_PARTICIPANTS) {
        throw new HttpsError("resource-exhausted", "Voice call is full.");
      }

      tx.set(
        participantRef,
        {
          uid,
          joined_at:
            participantSnap.exists && participantSnap.data()?.joined_at
              ? participantSnap.data()?.joined_at
              : admin.firestore.FieldValue.serverTimestamp(),
          left_at: null,
          is_muted: false,
          is_speaking: false,
          role: "member",
          device: device ?? "unknown",
          last_seen: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      if (!wasActiveParticipant) {
        tx.update(callRef, {
          participant_count: admin.firestore.FieldValue.increment(1),
          last_activity_at: admin.firestore.FieldValue.serverTimestamp(),
        });
      } else {
        tx.update(callRef, {
          last_activity_at: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      tx.set(
        db.collection("call_logs").doc(callId).collection("participants").doc(uid),
        {
          uid,
          joined_at: admin.firestore.FieldValue.serverTimestamp(),
          device: device ?? "unknown",
        },
        { merge: true }
      );

      return {
        channelName: call.channel_name as string,
      };
    });

    const token = buildAgoraToken(result.channelName, agoraUid);
    return {
      token,
      appId: AGORA_APP_ID,
      channelName: result.channelName,
      uid: agoraUid,
      expiresInSeconds: VOICE_CALL_TOKEN_TTL_SECONDS,
    };
  }
);

export const leaveVoiceCall = onCall(
  { region: "asia-northeast3" },
  async (request) => {
    const uid = request.auth?.uid;
    const roomId = request.data?.roomId as string | undefined;
    const callId = request.data?.callId as string | undefined;

    if (!uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }
    if (!roomId || !callId) {
      throw new HttpsError("invalid-argument", "roomId and callId are required.");
    }

    const db = getDb();
    const roomRef = db.collection("chat_rooms").doc(roomId);
    const callRef = roomRef.collection("calls").doc(callId);
    const participantRef = callRef.collection("participants").doc(uid);

    await db.runTransaction(async (tx) => {
      const [callSnap, participantSnap] = await Promise.all([
        tx.get(callRef),
        tx.get(participantRef),
      ]);

      if (!callSnap.exists) {
        throw new HttpsError("not-found", "Call not found.");
      }
      if (!participantSnap.exists || participantSnap.data()?.left_at != null) {
        return;
      }

      tx.update(participantRef, {
        left_at: admin.firestore.FieldValue.serverTimestamp(),
        last_seen: admin.firestore.FieldValue.serverTimestamp(),
        is_speaking: false,
      });
      tx.update(callRef, {
        participant_count: admin.firestore.FieldValue.increment(-1),
        last_activity_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      tx.set(
        db.collection("call_logs").doc(callId).collection("participants").doc(uid),
        {
          left_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    });

    await endCallIfEmpty(roomId, callId);
    return { success: true };
  }
);

export const refreshVoiceToken = onCall(
  { region: "asia-northeast3" },
  async (request) => {
    const uid = request.auth?.uid;
    const roomId = request.data?.roomId as string | undefined;
    const callId = request.data?.callId as string | undefined;

    if (!uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }
    if (!roomId || !callId) {
      throw new HttpsError("invalid-argument", "roomId and callId are required.");
    }

    const db = getDb();
    const roomRef = db.collection("chat_rooms").doc(roomId);
    const callRef = roomRef.collection("calls").doc(callId);
    const participantRef = callRef.collection("participants").doc(uid);

    const [callSnap, participantSnap] = await Promise.all([
      callRef.get(),
      participantRef.get(),
    ]);

    if (!callSnap.exists) {
      throw new HttpsError("not-found", "Call not found.");
    }
    if (!participantSnap.exists || participantSnap.data()?.left_at != null) {
      throw new HttpsError(
        "permission-denied",
        "You are not an active participant in this call."
      );
    }

    const call = callSnap.data() ?? {};
    if (call.status !== "active") {
      throw new HttpsError("failed-precondition", "Call already ended.");
    }

    const agoraUid = toAgoraUid(uid);
    const channelName = call.channel_name as string;
    const token = buildAgoraToken(channelName, agoraUid);

    await participantRef.set(
      {
        last_seen: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return {
      token,
      appId: AGORA_APP_ID,
      channelName,
      uid: agoraUid,
      expiresInSeconds: VOICE_CALL_TOKEN_TTL_SECONDS,
    };
  }
);

export const cleanupVoiceCalls = onSchedule(
  {
    schedule: "every 1 minutes",
    timeZone: "Asia/Seoul",
    timeoutSeconds: 540,
    memory: "256MiB",
    region: "asia-northeast3",
  },
  async () => {
    const db = getDb();
    const now = Date.now();
    const activeCallsSnap = await db
      .collectionGroup("calls")
      .where("status", "==", "active")
      .get();

    for (const callDoc of activeCallsSnap.docs) {
      const call = callDoc.data();
      const startedAt = call.started_at as admin.firestore.Timestamp | undefined;
      const participantsSnap = await callDoc.ref
        .collection("participants")
        .where("left_at", "==", null)
        .get();

      const staleParticipants = participantsSnap.docs.filter((doc) => {
        const lastSeen = doc.data().last_seen as admin.firestore.Timestamp | undefined;
        if (!lastSeen) return true;
        return now - lastSeen.toDate().getTime() > VOICE_CALL_HEARTBEAT_STALE_MS;
      });

      if (staleParticipants.length > 0) {
        const batch = db.batch();
        for (const participantDoc of staleParticipants) {
          batch.update(participantDoc.ref, {
            left_at: admin.firestore.FieldValue.serverTimestamp(),
            is_speaking: false,
          });
          batch.set(
            db
              .collection("call_logs")
              .doc(callDoc.id)
              .collection("participants")
              .doc(participantDoc.id),
            {
              left_at: admin.firestore.FieldValue.serverTimestamp(),
              cleanup_reason: "heartbeat_timeout",
            },
            { merge: true }
          );
        }
        await batch.commit();
      }

      const callPath = callDoc.ref.path.split("/");
      const roomId = callPath[1];
      const callId = callDoc.id;

      if (
        startedAt &&
        now - startedAt.toDate().getTime() > VOICE_CALL_MAX_DURATION_MS
      ) {
        await db.runTransaction(async (tx) => {
          const roomRef = db.collection("chat_rooms").doc(roomId);
          tx.update(callDoc.ref, {
            status: "ended",
            ended_at: admin.firestore.FieldValue.serverTimestamp(),
            participant_count: 0,
            last_activity_at: admin.firestore.FieldValue.serverTimestamp(),
          });
          tx.update(roomRef, {
            active_call_id: admin.firestore.FieldValue.delete(),
            active_call_type: admin.firestore.FieldValue.delete(),
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          });
          tx.set(
            db.collection("call_logs").doc(callId),
            {
              ended_at: admin.firestore.FieldValue.serverTimestamp(),
              ended_reason: "max_duration",
            },
            { merge: true }
          );
        });
        continue;
      }

      await endCallIfEmpty(roomId, callId);
    }
  }
);
