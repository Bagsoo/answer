import {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import * as admin from "firebase-admin";
import {
  getTokensForUids,
  sendChunked,
  cleanupInvalidTokens,
} from "./utils/fcm";
export {
  regenerateGroupQr,
  setGroupQrEnabled,
  joinGroupByQr,
} from "./groupQr";

admin.initializeApp();
const db = admin.firestore();

setGlobalOptions({
  region: "asia-northeast3",
});

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

    let body = text;
    if (type === "image") {
      body = "📷 사진을 보냈습니다";
    } else if (type === "video") {
      body = "🎥 동영상을 보냈습니다";
    } else if (type === "file") {
      body = "📎 파일을 보냈습니다";
    } else if (type === "contact") {
      body = "👤 연락처를 보냈습니다";
    }

    const roomDoc = await db.collection("chat_rooms").doc(roomId).get();
    const roomData = roomDoc.data();
    if (!roomData) return null;

    const roomName = roomData.name as string | undefined;
    const roomType = roomData.type as string | undefined;
    const groupProfileImage =
      (roomData.group_profile_image as string | undefined) ?? "";
    const activeFcmTokens = (roomData.active_fcm_tokens as string[]) ?? [];

    let avatarUrl = groupProfileImage;
    if (roomType === "direct") {
      const senderDoc = await db.collection("users").doc(senderId).get();
      avatarUrl =
        (senderDoc.data()?.profile_image as string | undefined) ?? "";
    }

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

    const payload: Omit<admin.messaging.MulticastMessage, "tokens"> = {
      data: {
        type: "chat",
        roomId,
        notificationTitle: roomName ?? senderName,
        notificationBody: `${senderName}: ${body}`,
        avatarUrl,
      },
      android: {
        priority: "high",
        collapseKey: roomId,
      },
      apns: {
        headers: { "apns-collapse-id": roomId },
        payload: {
          aps: {
            sound: "default",
            badge: 1,
            contentAvailable: true,
          },
        },
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
    const requesterName =
      (request.display_name as string | undefined) ??
      (request.name as string | undefined) ??
      "누군가";

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
    const groupData = groupDoc.data() ?? {};
    const groupName = (groupData.name as string | undefined) ?? "그룹";
    const groupProfileImage =
      (groupData.group_profile_image as string | undefined) ?? "";

    const payload: Omit<admin.messaging.MulticastMessage, "tokens"> = {
      data: {
        type: "join_request",
        groupId,
        notificationTitle: groupName,
        notificationBody: `${requesterName}님이 가입을 요청했습니다`,
        avatarUrl: groupProfileImage,
      },
      android: {
        priority: "high",
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
    return null;
  }
);

export const onGroupNoticeCreatedV2 = onDocumentCreated(
  "groups/{groupId}/notices/{noticeId}",
  async (event) => {
    const groupId = event.params.groupId;
    const snap = event.data;
    if (!snap) return null;

    const notice = snap.data();
    const authorUid = (notice.author_uid as string | undefined) ?? "";
    const text = (notice.text as string | undefined) ?? "";

    const groupDoc = await db.collection("groups").doc(groupId).get();
    const groupData = groupDoc.data();
    if (!groupData) return null;

    const groupName = (groupData.name as string | undefined) ?? "그룹";
    const groupProfileImage =
      (groupData.group_profile_image as string | undefined) ?? "";
    const activeFcmTokens = (groupData.active_fcm_tokens as string[]) ?? [];
    if (activeFcmTokens.length === 0) return null;

    const membersSnap = await db
      .collection("groups")
      .doc(groupId)
      .collection("members")
      .get();
    const memberUids = membersSnap.docs
      .map((d) => d.id)
      .filter((uid) => uid !== authorUid);
    if (memberUids.length === 0) return null;

    let authorTokensPromise: Promise<
      FirebaseFirestore.QuerySnapshot<FirebaseFirestore.DocumentData> | null
    >;
    if (authorUid) {
      authorTokensPromise = db
        .collection("users")
        .doc(authorUid)
        .collection("fcm_tokens")
        .get();
    } else {
      authorTokensPromise = Promise.resolve(null);
    }

    const [authorTokensSnap, settingsSnaps] = await Promise.all([
      authorTokensPromise,
      Promise.all(
        memberUids.map((uid) =>
          db
            .collection("users")
            .doc(uid)
            .collection("group_notification_settings")
            .doc(groupId)
            .get()
        )
      ),
    ]);

    const authorTokens =
      authorTokensSnap?.docs.map((d) => d.data().token as string) ?? [];
    const mutedUids = settingsSnaps
      .filter((s) => s.exists && s.data()?.enabled === false)
      .map((s) => s.ref.parent.parent!.id);
    const mutedTokens = await getTokensForUids(mutedUids);
    const targets = activeFcmTokens.filter(
      (token) => !authorTokens.includes(token) && !mutedTokens.includes(token)
    );
    if (targets.length === 0) return null;

    const summary = text.length > 80 ? `${text.slice(0, 77)}...` : text;
    const payload: Omit<admin.messaging.MulticastMessage, "tokens"> = {
      data: {
        type: "group_notice",
        groupId,
        groupName,
        notificationTitle: groupName,
        notificationBody: `공지: ${summary}`,
        avatarUrl: groupProfileImage,
      },
      android: {
        priority: "high",
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

    const invalidTokens = await sendChunked(targets, payload);
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

    const payload: Omit<admin.messaging.MulticastMessage, "tokens"> = {
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
export const onUserTokenChangedV2 = onDocumentWritten(
  "users/{uid}/fcm_tokens/{tokenId}",
  async (event) => {
    const uid = event.params.uid;
    const before = event.data?.before.data();
    const after = event.data?.after.data();

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

// ── 5. 채팅방 멤버 입장 시 토큰 추가 ─────────────────────────────────────────
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

// ── 6. 채팅방 멤버 퇴장 시 토큰 제거 ─────────────────────────────────────────
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

// ── 6-1. 그룹 멤버 입장 시 그룹 토큰 추가 ────────────────────────────────────
export const onGroupMemberJoinedV2 = onDocumentCreated(
  "groups/{groupId}/members/{uid}",
  async (event) => {
    const { groupId, uid } = event.params;

    const tokensSnap = await db
      .collection("users")
      .doc(uid)
      .collection("fcm_tokens")
      .get();
    const tokens = tokensSnap.docs.map((d) => d.data().token as string);
    if (tokens.length === 0) return null;

    await db
      .collection("groups")
      .doc(groupId)
      .set(
        { active_fcm_tokens: admin.firestore.FieldValue.arrayUnion(...tokens) },
        { merge: true }
      );

    return null;
  }
);

// ── 6-2. 그룹 멤버 퇴장 시 그룹 토큰 제거 ────────────────────────────────────
export const onGroupMemberLeftV2 = onDocumentDeleted(
  "groups/{groupId}/members/{uid}",
  async (event) => {
    const { groupId, uid } = event.params;

    const tokensSnap = await db
      .collection("users")
      .doc(uid)
      .collection("fcm_tokens")
      .get();
    const tokens = tokensSnap.docs.map((d) => d.data().token as string);
    if (tokens.length === 0) return null;

    await db
      .collection("groups")
      .doc(groupId)
      .set(
        {
          active_fcm_tokens: admin.firestore.FieldValue.arrayRemove(...tokens),
        },
        { merge: true }
      );

    return null;
  }
);

// ── 7. 플랜 만료 그룹 자동 다운그레이드 / user_payment 만료 처리 ────────────
export {
  downgradeExpiredGroups,
  expireUserPayments,
} from "./downgradeExpiredGroups";
