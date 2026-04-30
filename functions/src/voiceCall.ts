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

const VOICE_CALL_MAX_PARTICIPANTS = 8;
const VIDEO_CALL_MAX_PARTICIPANTS = 4; // 초기에 4명으로 제한
const VOICE_CALL_MAX_GROUP_MEMBERS = 20;
const VIDEO_CALL_MAX_GROUP_MEMBERS = 20;
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

function toAgoraUid(uid: string) {
  const hash = createHash("sha256").update(uid).digest();
  return hash.readUInt32BE(0) & 0x7fffffff;
}

function buildAgoraToken(channelName: string, agoraUid: number) {
  const appId = process.env.AGORA_APP_ID;
  const appCertificate = process.env.AGORA_APP_CERTIFICATE;

  if (!appId || !appCertificate) {
    throw new HttpsError(
      "failed-precondition",
      "Agora Keys Missing. Check Secret Manager."
    );
  }

  try {
    const now = Math.floor(Date.now() / 1000);
    const privilegeExpiredTs = now + VOICE_CALL_TOKEN_TTL_SECONDS;
    return RtcTokenBuilder.buildTokenWithUid(
      appId,
      appCertificate,
      channelName,
      agoraUid,
      RtcRole.PUBLISHER,
      privilegeExpiredTs
    );
  } catch (err: any) {
    console.error("Agora RtcTokenBuilder Error:", err);
    throw new HttpsError("internal", `Agora Token Generation Failed: ${err.message}`);
  }
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

async function assertStartPermission(room: RoomData, uid: string, type: string) {
  const roomType = room.type ?? "";
  if (roomType === "direct" || roomType === "group_direct") {
    return;
  }

  if (roomType !== "group_all" && roomType !== "group_sub") {
    throw new HttpsError("failed-precondition", "Unsupported room type.");
  }

  if (!room.ref_group_id) {
    throw new HttpsError("failed-precondition", "Group reference missing.");
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
    throw new HttpsError("permission-denied", "Invalid group membership.");
  }

  const group = groupDoc.data() ?? {};
  const member = memberDoc.data() as GroupMemberData;
  const memberCount = (group.member_count as number | undefined) ?? 0;
  
  const maxGroupLimit = type === "video" ? VIDEO_CALL_MAX_GROUP_MEMBERS : VOICE_CALL_MAX_GROUP_MEMBERS;
  if (memberCount > maxGroupLimit) {
    throw new HttpsError("failed-precondition", "Group too large for this call type.");
  }

  const role = member.role ?? "member";
  const canStart = role === "owner" || (role === "manager" && member.permissions?.can_start_voice_call === true);

  if (!canStart) {
    throw new HttpsError("permission-denied", "No permission to start call.");
  }
}

async function hasBlockedRelationship(uid: string, otherUid: string) {
  const [a, b] = await Promise.all([
    getDb().collection("users").doc(uid).collection("blocked").doc(otherUid).get(),
    getDb().collection("users").doc(otherUid).collection("blocked").doc(uid).get(),
  ]);
  return a.exists || b.exists;
}

async function assertNoBlockedRelationship(uid: string, memberIds: string[]) {
  const others = memberIds.filter((id) => id !== uid);
  for (const otherUid of others) {
    if (await hasBlockedRelationship(uid, otherUid)) {
      throw new HttpsError("permission-denied", "Blocked relationship exists.");
    }
  }
}

function getKstDayBounds() {
  const now = new Date();
  const utcMs = now.getTime() + now.getTimezoneOffset() * 60 * 1000;
  const kstNow = new Date(utcMs + 9 * 60 * 60 * 1000);
  const start = new Date(Date.UTC(kstNow.getUTCFullYear(), kstNow.getUTCMonth(), kstNow.getUTCDate(), -9, 0, 0, 0));
  return {
    start: admin.firestore.Timestamp.fromDate(start),
    end: admin.firestore.Timestamp.fromDate(new Date(start.getTime() + 24 * 60 * 60 * 1000)),
  };
}

async function assertStartRateLimits(roomId: string, uid: string, type: string) {
  const db = getDb();
  const recentSnap = await db.collection("chat_rooms").doc(roomId).collection("calls")
    .where("type", "==", type)
    .orderBy("started_at", "desc").limit(1).get();

  if (!recentSnap.empty) {
    const recent = recentSnap.docs[0].data();
    const startedAt = recent.started_at as admin.firestore.Timestamp | undefined;
    if (startedAt && Date.now() - startedAt.toDate().getTime() < VOICE_CALL_COOLDOWN_MS) {
      throw new HttpsError("resource-exhausted", "Cooldown active.");
    }
  }

  const day = getKstDayBounds();
  const dailySnap = await db.collectionGroup("calls").where("started_by", "==", uid).where("type", "==", type).where("started_at", ">=", day.start)
    .where("started_at", "<", day.end).get();

  if (dailySnap.size >= VOICE_CALL_DAILY_START_LIMIT) {
    throw new HttpsError("resource-exhausted", "Daily limit exceeded.");
  }
}

async function notifyCallStarted(roomId: string, callerUid: string, callId: string, channelName: string, room: RoomData, memberIds: string[], type: string) {
  const receiverIds = memberIds.filter((id) => id !== callerUid);
  if (receiverIds.length === 0) return;

  const tokens = await getTokensForUids(receiverIds);
  if (tokens.length === 0) return;

  const roomName = room.name ?? room.group_name ?? (type === "video" ? "Video Call" : "Voice Call");
  const bodyText = type === "video" ? "영상통화가 시작되었습니다." : "음성통화가 시작되었습니다.";
  
  const payload = {
    notification: { title: roomName, body: bodyText },
    data: { 
      type: "voice_call", // 클라이언트 앱의 기존 리스너 구조 유지
      callType: type,
      roomId, 
      callId, 
      channelName, 
      notificationTitle: roomName, 
      notificationBody: bodyText, 
      avatarUrl: room.group_profile_image ?? "" 
    },
    android: { priority: "high" as const, collapseKey: `${type}_call_${roomId}`, notification: { channelId: "chat_channel" } },
    apns: { payload: { aps: { sound: "default", badge: 1, contentAvailable: true } } },
  };

  try {
    const invalidTokens = await sendChunked(tokens, payload);
    await cleanupInvalidTokens(invalidTokens);
  } catch (err) {
    console.error("Notification Error:", err);
  }
}

async function endCallIfEmpty(roomId: string, callId: string) {
  const db = getDb();
  await db.runTransaction(async (tx) => {
    const roomRef = db.collection("chat_rooms").doc(roomId);
    const callRef = roomRef.collection("calls").doc(callId);
    const [, callSnap] = await Promise.all([tx.get(roomRef), tx.get(callRef)]);
    if (!callSnap.exists) return;
    const call = callSnap.data() ?? {};
    if (call.status !== "active") return;

    const participantsSnap = await tx.get(callRef.collection("participants").where("left_at", "==", null));
    const activeCount = participantsSnap.size;
    const updates: any = { participant_count: activeCount, last_activity_at: admin.firestore.FieldValue.serverTimestamp() };

    if (activeCount <= 0) {
      updates.status = "ended";
      updates.ended_at = admin.firestore.FieldValue.serverTimestamp();
      tx.update(roomRef, { active_call_id: admin.firestore.FieldValue.delete(), active_call_type: admin.firestore.FieldValue.delete() });
    }
    tx.update(callRef, updates);
  });
}

// 기존 음성통화/영상통화 통합 시작 함수
export const startVoiceCall = onCall({ region: "asia-northeast3", secrets: ["AGORA_APP_ID", "AGORA_APP_CERTIFICATE"] }, async (request) => {
  const uid = request.auth?.uid;
  const roomId = request.data?.roomId as string | undefined;
  const callType = (request.data?.type as string) || "voice"; // "voice" or "video"

  if (!uid) throw new HttpsError("unauthenticated", "Login required.");
  if (!roomId) throw new HttpsError("invalid-argument", "roomId required.");

  try {
    const { roomDoc, room, memberIds } = await getRoomOrThrow(roomId, uid);
    await assertStartPermission(room, uid, callType);
    await assertNoBlockedRelationship(uid, memberIds);
    await assertStartRateLimits(roomId, uid, callType);

    if (roomDoc.data()?.active_call_id) throw new HttpsError("already-exists", "Call already exists in this room.");

    const callRef = roomDoc.ref.collection("calls").doc();
    const channelName = `${roomId}_${Date.now()}`;

    await getDb().runTransaction(async (tx) => {
      tx.set(callRef, { 
        type: callType, 
        status: "active", 
        started_by: uid, 
        started_at: admin.firestore.FieldValue.serverTimestamp(), 
        channel_name: channelName, 
        participant_count: 0,
        max_participants: callType === "video" ? VIDEO_CALL_MAX_PARTICIPANTS : VOICE_CALL_MAX_PARTICIPANTS
      });
      tx.update(roomDoc.ref, { 
        active_call_id: callRef.id, 
        active_call_type: callType, 
        updated_at: admin.firestore.FieldValue.serverTimestamp() 
      });
    });

    await notifyCallStarted(roomId, uid, callRef.id, channelName, room, memberIds, callType);
    return { success: true, callId: callRef.id };
  } catch (err: any) {
    console.error("startCall Error:", err);
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", err.message || "Unknown error");
  }
});

export const joinVoiceCall = onCall({ region: "asia-northeast3", secrets: ["AGORA_APP_ID", "AGORA_APP_CERTIFICATE"] }, async (request) => {
  const uid = request.auth?.uid;
  const { roomId, callId, device, isVideoEnabled } = request.data;
  if (!uid) throw new HttpsError("unauthenticated", "Login required.");
  if (!roomId || !callId) throw new HttpsError("invalid-argument", "Missing IDs.");

  try {
    const { roomDoc, memberIds } = await getRoomOrThrow(roomId, uid);
    await assertNoBlockedRelationship(uid, memberIds);

    const callRef = roomDoc.ref.collection("calls").doc(callId);
    const participantRef = callRef.collection("participants").doc(uid);

    const result = await getDb().runTransaction(async (tx) => {
      const [callSnap, pSnap] = await Promise.all([tx.get(callRef), tx.get(participantRef)]);
      if (!callSnap.exists || callSnap.data()?.status !== "active") throw new HttpsError("failed-precondition", "Call not active.");
      
      const callData = callSnap.data() ?? {};
      const participantCount = (callData.participant_count as number | undefined) ?? 0;
      const wasActive = pSnap.exists && pSnap.data()?.left_at == null;

      const maxLimit = callData.type === "video" ? VIDEO_CALL_MAX_PARTICIPANTS : VOICE_CALL_MAX_PARTICIPANTS;

      if (!wasActive && participantCount >= maxLimit) {
        throw new HttpsError("resource-exhausted", "Call room is full.");
      }

      tx.set(participantRef, { 
        uid, 
        joined_at: wasActive ? pSnap.data()?.joined_at : admin.firestore.FieldValue.serverTimestamp(), 
        left_at: null, 
        is_muted: false, 
        is_video_enabled: isVideoEnabled ?? (callData.type === "video"),
        device: device ?? "unknown", 
        last_seen: admin.firestore.FieldValue.serverTimestamp() 
      }, { merge: true });
      
      if (!wasActive) tx.update(callRef, { participant_count: admin.firestore.FieldValue.increment(1) });
      
      return { channelName: callData.channel_name as string };
    });

    const agoraUid = toAgoraUid(uid);
    const token = buildAgoraToken(result.channelName, agoraUid);
    return { 
      token, 
      appId: process.env.AGORA_APP_ID, 
      channelName: result.channelName, 
      uid: agoraUid, 
      expiresInSeconds: VOICE_CALL_TOKEN_TTL_SECONDS 
    };
  } catch (err: any) {
    console.error("joinCall Error:", err);
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", err.message || "Unknown error");
  }
});

export const leaveVoiceCall = onCall({ region: "asia-northeast3" }, async (request) => {
  const uid = request.auth?.uid;
  const { roomId, callId } = request.data;
  if (!uid || !roomId || !callId) throw new HttpsError("invalid-argument", "Missing args.");

  try {
    const callRef = getDb().collection("chat_rooms").doc(roomId).collection("calls").doc(callId);
    const pRef = callRef.collection("participants").doc(uid);

    await getDb().runTransaction(async (tx) => {
      const [cSnap, pSnap] = await Promise.all([tx.get(callRef), tx.get(pRef)]);
      if (!cSnap.exists || !pSnap.exists || pSnap.data()?.left_at != null) return;
      tx.update(pRef, { left_at: admin.firestore.FieldValue.serverTimestamp() });
      tx.update(callRef, { participant_count: admin.firestore.FieldValue.increment(-1) });
    });

    await endCallIfEmpty(roomId, callId);
    return { success: true };
  } catch (err: any) {
    throw new HttpsError("internal", err.message);
  }
});

export const refreshVoiceToken = onCall({ region: "asia-northeast3", secrets: ["AGORA_APP_ID", "AGORA_APP_CERTIFICATE"] }, async (request) => {
  const uid = request.auth?.uid;
  const { roomId, callId } = request.data;
  if (!uid || !roomId || !callId) throw new HttpsError("invalid-argument", "Missing args.");

  try {
    const callRef = getDb().collection("chat_rooms").doc(roomId).collection("calls").doc(callId);
    const callSnap = await callRef.get();
    if (!callSnap.exists || callSnap.data()?.status !== "active") throw new HttpsError("failed-precondition", "Call not active.");

    const agoraUid = toAgoraUid(uid);
    const channelName = callSnap.data()?.channel_name as string;
    const token = buildAgoraToken(channelName, agoraUid);
    return { token, appId: process.env.AGORA_APP_ID, channelName, uid: agoraUid, expiresInSeconds: VOICE_CALL_TOKEN_TTL_SECONDS };
  } catch (err: any) {
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", err.message);
  }
});

export const cleanupVoiceCalls = onSchedule({ schedule: "every 1 minutes", region: "asia-northeast3" }, async () => {
  const db = getDb();
  const now = Date.now();
  const activeCallsSnap = await db.collectionGroup("calls").where("status", "==", "active").get();

  for (const callDoc of activeCallsSnap.docs) {
    const call = callDoc.data();
    const startedAt = call.started_at as admin.firestore.Timestamp | undefined;
    const participantsSnap = await callDoc.ref.collection("participants").where("left_at", "==", null).get();

    const staleParticipants = participantsSnap.docs.filter((doc) => {
      const lastSeen = doc.data().last_seen as admin.firestore.Timestamp | undefined;
      return !lastSeen || now - lastSeen.toDate().getTime() > VOICE_CALL_HEARTBEAT_STALE_MS;
    });

    if (staleParticipants.length > 0) {
      const batch = db.batch();
      for (const p of staleParticipants) {
        batch.update(p.ref, { left_at: admin.firestore.FieldValue.serverTimestamp() });
      }
      await batch.commit();
    }

    if (startedAt && now - startedAt.toDate().getTime() > VOICE_CALL_MAX_DURATION_MS) {
      await callDoc.ref.update({ status: "ended", ended_at: admin.firestore.FieldValue.serverTimestamp() });
    }
  }
});
