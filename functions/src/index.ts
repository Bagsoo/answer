import {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import * as admin from "firebase-admin";

admin.initializeApp();

console.log("[init] admin.app().options.projectId:", admin.app().options.projectId);
console.log("[init] GCLOUD_PROJECT:", process.env.GCLOUD_PROJECT);
console.log("[init] FIREBASE_CONFIG:", process.env.FIREBASE_CONFIG);
void fetch(
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email",
  {
    headers: {"Metadata-Flavor": "Google"},
  }
)
  .then(async (res) => {
    const email = await res.text();
    console.log("[init] runtime service account:", email);
  })
  .catch((error: unknown) => {
    console.log("[init] runtime service account lookup failed:", error);
  });
const db = admin.firestore();
const messaging = admin.messaging();

setGlobalOptions({
  region: "asia-northeast3",
});

// ── 유틸: uid 배열로 FCM 토큰 배열 조회 ──────────────────────────────────────
async function getTokensForUids(uids: string[]): Promise<string[]> {
  if (uids.length === 0) return [];
  const snaps = await Promise.all(
    uids.map((uid) =>
      db.collection("users").doc(uid).collection("fcm_tokens").get()
    )
  );
  return snaps.flatMap((s) => s.docs.map((d) => d.data().token as string));
}

// ── 유틸: 토큰 배열을 500개씩 청크로 나눠 FCM 전송 ──────────────────────────
async function sendChunked(
  tokens: string[],
  payload: admin.messaging.MulticastMessage
) {
  const chunkSize = 500;
  const invalidTokens: string[] = [];

  for (let i = 0; i < tokens.length; i += chunkSize) {
    const chunk = tokens.slice(i, i + chunkSize);
    const response = await messaging.sendEachForMulticast({
      ...payload,
      tokens: chunk,
    });

    // ← 추가
    response.responses.forEach((res, idx) => {
      const error = res.error as
        | ({code?: string; message?: string; details?: unknown; stack?: string})
        | undefined;
      console.log(
        "[FCM response]",
        JSON.stringify({
          tokenPrefix: chunk[idx].substring(0, 20),
          success: res.success,
          messageId: res.messageId ?? "none",
          errorCode: error?.code ?? "none",
          errorMessage: error?.message ?? "none",
          errorDetails: error?.details ?? null,
          errorStack: error?.stack ?? null,
        })
      );
    });

    response.responses.forEach((res, idx) => {
      if (!res.success) {
        const code = res.error?.code ?? "";
        if (
          code === "messaging/invalid-registration-token" ||
          code === "messaging/registration-token-not-registered"
        ) {
          invalidTokens.push(chunk[idx]);
        }
      }
    });
  }

  return invalidTokens;
}

// ── 유틸: 유효하지 않은 토큰 DB에서 삭제 ────────────────────────────────────
async function cleanupInvalidTokens(invalidTokens: string[]) {
  if (invalidTokens.length === 0) return;

  // Firestore "in" 쿼리는 최대 10개이므로 슬라이스
  const tokenDocs = await db
    .collectionGroup("fcm_tokens")
    .where("token", "in", invalidTokens.slice(0, 10))
    .get();

  const batch = db.batch();
  tokenDocs.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
}

// ── 1. 채팅 메시지 알림 ───────────────────────────────────────────────────────
export const onMessageSentV2 = onDocumentCreated(
  "chat_rooms/{roomId}/messages/{messageId}",
  async (event) => {
    const roomId = event.params.roomId;
    const snap = event.data;
    if (!snap) return null;
    const message = snap.data();

    if (message.is_system) return null;

    const senderId = message.sender_id as string;
    const senderName = message.sender_name as string;
    const text = message.text as string;
    const type = message.type as string;

    const body =
      type === "image" ?
        "📷 사진을 보냈습니다" :
        type === "video" ?
          "🎥 동영상을 보냈습니다" :
          text;

    const roomDoc = await db.collection("chat_rooms").doc(roomId).get();
    const roomData = roomDoc.data();
    if (!roomData) return null;

    const roomName = roomData.name as string | undefined;
    const activeFcmTokens = (roomData.active_fcm_tokens as string[]) ?? [];

    console.log(`[onMessageSentV2] roomId: ${roomId}`);
    console.log(
      `[onMessageSentV2] active_fcm_tokens count: ${activeFcmTokens.length}`
    );

    const senderTokensSnap = await db
      .collection("users")
      .doc(senderId)
      .collection("fcm_tokens")
      .get();
    const senderTokens = senderTokensSnap.docs.map(
      (d) => d.data().token as string
    );
    const targets = activeFcmTokens.filter((t) => !senderTokens.includes(t));

    console.log(`[onMessageSentV2] sender tokens: ${senderTokens.length}`);
    console.log(`[onMessageSentV2] target tokens: ${targets.length}`);

    if (targets.length === 0) {
      console.log("[onMessageSentV2] No targets, skipping FCM send");
      return null;
    }

    const payload: admin.messaging.MulticastMessage = {
      tokens: targets,
      notification: {
        title: roomName ?? senderName,
        body: `${senderName}: ${body}`,
      },
      data: { type: "chat", roomId },
      android: {
        collapseKey: roomId,
        notification: { channelId: "chat_channel", priority: "high" },
      },
      apns: {
        headers: { "apns-collapse-id": roomId },
        payload: { aps: { sound: "default", badge: 1 } },
      },
    };

    const invalidTokens = await sendChunked(targets, payload);
    console.log(`[onMessageSentV2] invalidTokens: ${invalidTokens.length}`);
    await cleanupInvalidTokens(invalidTokens);
    return null;
  }
);

// ── 2. 가입 요청 알림 ─────────────────────────────────────────────────────────
export const onJoinRequestV2 = onDocumentCreated(
  "groups/{groupId}/join_requests/{requestId}",
  async (event) => {
    const groupId = event.params.groupId;
    const snap = event.data;
    if (!snap) return null;
    const request = snap.data();
    const requesterName = (request.name as string) ?? "누군가";

    const membersSnap = await db
      .collection("groups")
      .doc(groupId)
      .collection("members")
      .where("permissions.can_manage_permissions", "==", true)
      .get();

    if (membersSnap.empty) return null;

    const adminUids = membersSnap.docs.map((d) => d.id);
    const tokens = await getTokensForUids(adminUids);
    if (tokens.length === 0) return null;

    const groupDoc = await db.collection("groups").doc(groupId).get();
    const groupName = (groupDoc.data()?.name as string) ?? "그룹";

    const payload: admin.messaging.MulticastMessage = {
      tokens,
      notification: {
        title: groupName,
        body: `${requesterName}님이 가입을 요청했습니다`,
      },
      data: { type: "join_request", groupId },
      android: {
        notification: { channelId: "join_request_channel" },
      },
    };

    const invalidTokens = await sendChunked(tokens, payload);
    await cleanupInvalidTokens(invalidTokens);
    return null;
  }
);

// ── 3. 그룹 일정 알림 ─────────────────────────────────────────────────────────
export const onScheduleAddedV2 = onDocumentCreated(
  "groups/{groupId}/schedules/{scheduleId}",
  async (event) => {
    const groupId = event.params.groupId;
    const snap = event.data;
    if (!snap) return null;
    const schedule = snap.data();
    const title = (schedule.title as string) ?? "새 일정";

    const groupDoc = await db.collection("groups").doc(groupId).get();
    const groupData = groupDoc.data();
    if (!groupData) return null;

    const groupName = (groupData.name as string) ?? "그룹";
    const activeFcmTokens = (groupData.active_fcm_tokens as string[]) ?? [];

    const membersSnap = await db
      .collection("groups")
      .doc(groupId)
      .collection("members")
      .get();

    const memberUids = membersSnap.docs.map((d) => d.id);
    const settingsSnaps = await Promise.all(
      memberUids.map((uid) =>
        db
          .collection("users")
          .doc(uid)
          .collection("group_notification_settings")
          .doc(groupId)
          .get()
      )
    );

    const mutedUids = settingsSnaps
      .filter((s) => s.exists && s.data()?.enabled === false)
      .map((s) => s.ref.parent.parent!.id);

    const mutedTokens = await getTokensForUids(mutedUids);
    const targets = activeFcmTokens.filter((t) => !mutedTokens.includes(t));
    if (targets.length === 0) return null;

    const payload: admin.messaging.MulticastMessage = {
      tokens: targets,
      notification: {
        title: groupName,
        body: `새 일정이 추가됐습니다: ${title}`,
      },
      data: { type: "schedule", groupId },
      android: {
        notification: { channelId: "schedule_channel" },
      },
    };

    const invalidTokens = await sendChunked(targets, payload);
    await cleanupInvalidTokens(invalidTokens);
    return null;
  }
);

// ── 4. FCM 토큰 변경 시 active_fcm_tokens Fan-out ────────────────────────────
// 토큰이 갱신(onTokenRefresh)되거나 로그아웃으로 삭제될 때 모든 방/그룹에 반영
export const onUserTokenChangedV2 = onDocumentWritten(
  "users/{uid}/fcm_tokens/{tokenId}",
  async (event) => {
    const uid = event.params.uid;
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    // 실제 토큰 값의 변화가 없으면 스킵 (updated_at만 변경된 경우)
    if (before?.token === after?.token) return null;

    const [chatRoomsSnap, groupsSnap] = await Promise.all([
      db
        .collection("chat_rooms")
        .where("member_ids", "array-contains", uid)
        .get(),
      db.collection("users").doc(uid).collection("joined_groups").get(),
    ]);
    const groupIds = groupsSnap.docs.map((d) => d.id);

    const batch = db.batch();

    if (!after && before?.token) {
      // 토큰 삭제 (로그아웃 / 만료)
      const oldToken = before.token;
      chatRoomsSnap.docs.forEach((doc) => {
        batch.update(doc.ref, {
          active_fcm_tokens: admin.firestore.FieldValue.arrayRemove(oldToken),
        });
      });
      groupIds.forEach((id) => {
        batch.update(db.collection("groups").doc(id), {
          active_fcm_tokens: admin.firestore.FieldValue.arrayRemove(oldToken),
        });
      });
    } else if (after?.token && !before) {
      // 신규 토큰 등록 (로그인 / 앱 최초 실행)
      const newToken = after.token;
      chatRoomsSnap.docs.forEach((doc) => {
        batch.set(
          doc.ref,
          { active_fcm_tokens: admin.firestore.FieldValue.arrayUnion(newToken) },
          { merge: true }
        );
      });
      groupIds.forEach((id) => {
        batch.set(
          db.collection("groups").doc(id),
          { active_fcm_tokens: admin.firestore.FieldValue.arrayUnion(newToken) },
          { merge: true }
        );
      });
    } else if (before?.token && after?.token && before.token !== after.token) {
      // 토큰 교체 (onTokenRefresh)
      const oldToken = before.token;
      const newToken = after.token;
      chatRoomsSnap.docs.forEach((doc) => {
        batch.update(doc.ref, {
          active_fcm_tokens: admin.firestore.FieldValue.arrayRemove(oldToken),
        });
        batch.update(doc.ref, {
          active_fcm_tokens: admin.firestore.FieldValue.arrayUnion(newToken),
        });
      });
      groupIds.forEach((id) => {
        batch.update(db.collection("groups").doc(id), {
          active_fcm_tokens: admin.firestore.FieldValue.arrayRemove(oldToken),
        });
        batch.update(db.collection("groups").doc(id), {
          active_fcm_tokens: admin.firestore.FieldValue.arrayUnion(newToken),
        });
      });
    }

    await batch.commit();
    return null;
  }
);

// ── 6. 채팅방 멤버 입장 시 토큰 추가 ─────────────────────────────────────────
// room_members/{uid} 문서가 새로 생길 때 해당 유저의 토큰을 arrayUnion
export const onChatRoomMemberJoinedV2 = onDocumentCreated(
  "chat_rooms/{roomId}/room_members/{uid}",
  async (event) => {
    const { roomId, uid } = event.params;

    const tokensSnap = await db
      .collection("users")
      .doc(uid)
      .collection("fcm_tokens")
      .get();

    const tokens = tokensSnap.docs.map((d) => d.data().token as string);
    if (tokens.length === 0) return null;

    await db
      .collection("chat_rooms")
      .doc(roomId)
      .set(
        { active_fcm_tokens: admin.firestore.FieldValue.arrayUnion(...tokens) },
        { merge: true }
      );

    console.log(
      `[onChatRoomMemberJoinedV2] roomId: ${roomId}, uid: ${uid}, tokens: ${tokens.length}`
    );
    return null;
  }
);

// ── 7. 채팅방 멤버 퇴장 시 토큰 제거 ─────────────────────────────────────────
// room_members/{uid} 문서가 삭제될 때 해당 유저의 토큰을 arrayRemove
export const onChatRoomMemberLeftV2 = onDocumentDeleted(
  "chat_rooms/{roomId}/room_members/{uid}",
  async (event) => {
    const { roomId, uid } = event.params;

    const tokensSnap = await db
      .collection("users")
      .doc(uid)
      .collection("fcm_tokens")
      .get();

    const tokens = tokensSnap.docs.map((d) => d.data().token as string);
    if (tokens.length === 0) return null;

    await db
      .collection("chat_rooms")
      .doc(roomId)
      .update({
        active_fcm_tokens: admin.firestore.FieldValue.arrayRemove(...tokens),
      });

    console.log(
      `[onChatRoomMemberLeftV2] roomId: ${roomId}, uid: ${uid}, tokens removed: ${tokens.length}`
    );
    return null;
  }
);
