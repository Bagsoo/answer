import {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
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
export { submitGroupPurchaseV1 } from "./billing";

admin.initializeApp();
const db = admin.firestore();

setGlobalOptions({
  region: "asia-northeast3",
});

export const acceptInviteV2 = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Unauthenticated");
  const { notiId, groupId } = request.data;
  return await db.runTransaction(async (tx) => {
    // 1. Reads
    const userRef = db.collection("users").doc(uid);
    const userSnap = await tx.get(userRef);
    const userData = userSnap.data();
    if (!userData) {
      throw new HttpsError("not-found", "User not found");
    }

    const groupRef = db.collection("groups").doc(groupId);
    const groupSnap = await tx.get(groupRef);
    const groupData = groupSnap.data();
    if (!groupData) {
      throw new HttpsError("not-found", "Group not found");
    }

    const query = db.collection("chat_rooms").where("ref_group_id", "==", groupId).where("type", "==", "group_all").limit(1);
    const chatSnap = await tx.get(query);

    const memberRef = db.collection("groups").doc(groupId).collection("members").doc(uid);
    const memberSnap = await tx.get(memberRef);
    if (memberSnap.exists) {
      throw new HttpsError("already-exists", "User is already a member of this group");
    }

    const notiRef = db.collection("users").doc(uid).collection("notifications").doc(notiId);
    const notiSnap = await tx.get(notiRef);
    if (!notiSnap.exists) {
      throw new HttpsError("not-found", "Invite not found or already processed");
    }

    // 2. Writes
    const displayName = userData.name ?? "알 수 없음";
    const profileImage = userData.profile_image ?? "";

    tx.set(memberRef, {
      uid: uid,
      user_id: uid,
      display_name: displayName,
      profile_image: profileImage,
      role: "member",
      joined_at: admin.firestore.FieldValue.serverTimestamp(),
      permissions: {
        can_post_schedule: false,
        can_create_sub_chat: false,
        can_write_post: true,
        can_edit_group_info: false,
        can_manage_permissions: false,
      },
    });

    const joinedGroupRef = db.collection("users").doc(uid).collection("joined_groups").doc(groupId);
    tx.set(joinedGroupRef, {
      group_id: groupId,
      joined_at: admin.firestore.FieldValue.serverTimestamp(),
      name: groupData.name ?? "그룹",
    });

    tx.delete(notiRef);

    tx.update(groupRef, { member_count: admin.firestore.FieldValue.increment(1) });

    if (!chatSnap.empty) {
      const chatDoc = chatSnap.docs[0];
      tx.update(chatDoc.ref, {
        member_ids: admin.firestore.FieldValue.arrayUnion(uid),
        [`unread_counts.${uid}`]: 0,
      });
      tx.set(chatDoc.ref.collection("room_members").doc(uid), {
        uid: uid,
        display_name: displayName,
        role: "member",
        joined_at: admin.firestore.FieldValue.serverTimestamp(),
        last_read_time: admin.firestore.FieldValue.serverTimestamp(),
        unread_cnt: 0,
      });
    }

    return { status: "success" };
  });
});

export const onMessageSentV2 = onDocumentCreated("chat_rooms/{roomId}/messages/{messageId}", async (event) => {
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
  if (type === "image") body = "📷 사진을 보냈습니다";
  else if (type === "video") body = "🎥 동영상을 보냈습니다";
  else if (type === "audio") body = "🎤 음성 메시지를 보냈습니다";
  else if (type === "file") body = "📎 파일을 보냈습니다";
  else if (type === "contact") body = "👤 연락처를 보냈습니다";
  const roomDoc = await db.collection("chat_rooms").doc(roomId).get();
  const roomData = roomDoc.data();
  if (!roomData) return null;
  const roomName = roomData.name as string | undefined;
  const roomType = roomData.type as string | undefined;
  const groupProfileImage = (roomData.group_profile_image as string | undefined) ?? "";
  let avatarUrl = groupProfileImage;
  if (roomType === "direct") {
    const senderDoc = await db.collection("users").doc(senderId).get();
    avatarUrl = (senderDoc.data()?.profile_image as string | undefined) ?? "";
  }
  const memberIds = (roomData.member_ids as string[]) ?? [];
  const receiverIds = memberIds.filter((uid) => uid !== senderId);

  const filteredReceiverIds: string[] = [];
  const userDocs = await Promise.all(receiverIds.map((uid) => db.collection("users").doc(uid).get()));
  for (const doc of userDocs) {
    if (!doc.exists) continue;
    const data = doc.data();
    if (data?.active_room_id === roomId) continue;
    filteredReceiverIds.push(doc.id);
  }

  if (filteredReceiverIds.length === 0) return null;

  const targets = await getTokensForUids(filteredReceiverIds);
  if (targets.length === 0) return null;

  const payload: Omit<admin.messaging.MulticastMessage, "tokens"> = {
    notification: {
      title: roomName ?? senderName,
      body: `${senderName}: ${body}`,
    },
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
      notification: {
        channelId: "chat_channel",
      },
    },
    apns: {
      headers: { "apns-collapse-id": roomId },
      payload: { aps: { sound: "default", badge: 1, contentAvailable: true } },
    },
  };
  const invalidTokens = await sendChunked(targets, payload);
  await cleanupInvalidTokens(invalidTokens);
  return null;
});

export const onJoinRequestV2 = onDocumentCreated("groups/{groupId}/join_requests/{requestId}", async (event) => {
  const groupId = event.params.groupId;
  const snap = event.data;
  if (!snap) return null;
  const request = snap.data();
  const requesterName = (request.display_name as string | undefined) ?? (request.name as string | undefined) ?? "누군가";
  const membersSnap = await db.collection("groups").doc(groupId).collection("members").where("permissions.can_manage_permissions", "==", true).get();
  if (membersSnap.empty) return null;
  const adminUids = membersSnap.docs.map((d) => d.id);
  const tokens = await getTokensForUids(adminUids);
  if (tokens.length === 0) return null;
  const groupDoc = await db.collection("groups").doc(groupId).get();
  const groupData = groupDoc.data() ?? {};
  const groupName = (groupData.name as string | undefined) ?? "그룹";
  const groupProfileImage = (groupData.group_profile_image as string | undefined) ?? "";
  const payload: Omit<admin.messaging.MulticastMessage, "tokens"> = {
    notification: {
      title: groupName,
      body: `${requesterName}님이 가입을 요청했습니다`,
    },
    data: {
      type: "join_request",
      groupId,
      notificationTitle: groupName,
      notificationBody: `${requesterName}님이 가입을 요청했습니다`,
      avatarUrl: groupProfileImage,
    },
    android: {
      priority: "high",
      notification: { channelId: "join_request_channel" },
    },
    apns: { payload: { aps: { sound: "default", badge: 1, contentAvailable: true } } },
  };
  const invalidTokens = await sendChunked(tokens, payload);
  await cleanupInvalidTokens(invalidTokens);
  return null;
});

export const onGroupNoticeCreatedV2 = onDocumentCreated("groups/{groupId}/notices/{noticeId}", async (event) => {
  const groupId = event.params.groupId;
  const snap = event.data;
  if (!snap) return null;
  const notice = snap.data();
  const authorUid = (notice.author_uid as string | undefined) ?? "";
  const text = (notice.text as string | undefined) ?? "";
  const groupDoc = await db.collection("groups").doc(groupId).get();
  const groupData = groupDoc.data();
  if (!groupData || groupData.plan !== "pro") return null;
  const groupName = (groupData.name as string | undefined) ?? "그룹";
  const groupProfileImage = (groupData.group_profile_image as string | undefined) ?? "";
  const activeFcmTokens = (groupData.active_fcm_tokens as string[]) ?? [];
  if (activeFcmTokens.length === 0) return null;
  const membersSnap = await db.collection("groups").doc(groupId).collection("members").get();
  const memberUids = membersSnap.docs.map((d) => d.id).filter((uid) => uid !== authorUid);
  if (memberUids.length === 0) return null;
  const authorTokensSnap = authorUid ? await db.collection("users").doc(authorUid).collection("fcm_tokens").get() : null;
  const settingsSnaps = await Promise.all(memberUids.map((uid) => db.collection("users").doc(uid).collection("group_notification_settings").doc(groupId).get()));
  const authorTokens = authorTokensSnap?.docs.map((d) => d.data().token as string) ?? [];
  const mutedUids = settingsSnaps.filter((s) => s.exists && s.data()?.enabled === false).map((s) => s.ref.parent.parent!.id);
  const mutedTokens = await getTokensForUids(mutedUids);
  const targets = activeFcmTokens.filter((token) => !authorTokens.includes(token) && !mutedTokens.includes(token));
  if (targets.length === 0) return null;
  const summary = text.length > 80 ? `${text.slice(0, 77)}...` : text;
  const payload: Omit<admin.messaging.MulticastMessage, "tokens"> = {
    notification: {
      title: groupName,
      body: `공지: ${summary}`,
    },
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
      notification: { channelId: "chat_channel" },
    },
    apns: { payload: { aps: { sound: "default", badge: 1, contentAvailable: true } } },
  };
  const invalidTokens = await sendChunked(targets, payload);
  await cleanupInvalidTokens(invalidTokens);
  return null;
});

export const onScheduleAddedV2 = onDocumentCreated("groups/{groupId}/schedules/{scheduleId}", async (event) => {
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
  const membersSnap = await db.collection("groups").doc(groupId).collection("members").get();
  const memberUids = membersSnap.docs.map((d) => d.id);
  const settingsSnaps = await Promise.all(memberUids.map((uid) => db.collection("users").doc(uid).collection("group_notification_settings").doc(groupId).get()));
  const mutedUids = settingsSnaps.filter((s) => s.exists && s.data()?.enabled === false).map((s) => s.ref.parent.parent!.id);
  const mutedTokens = await getTokensForUids(mutedUids);
  const targets = activeFcmTokens.filter((t) => !mutedTokens.includes(t));
  if (targets.length === 0) return null;
  const payload: Omit<admin.messaging.MulticastMessage, "tokens"> = {
    notification: { title: groupName, body: `새 일정이 추가됐습니다: ${title}` },
    data: { type: "schedule", groupId },
    android: {
      priority: "high",
      notification: { channelId: "schedule_channel" },
    },
    apns: { payload: { aps: { sound: "default", badge: 1, contentAvailable: true } } },
  };
  const invalidTokens = await sendChunked(targets, payload);
  await cleanupInvalidTokens(invalidTokens);
  return null;
});

export const onUserTokenChangedV2 = onDocumentWritten("users/{uid}/fcm_tokens/{tokenId}", async (event) => {
  const uid = event.params.uid;
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (before?.token === after?.token) return null;
  const [chatRoomsSnap, groupsSnap] = await Promise.all([
    db.collection("chat_rooms").where("member_ids", "array-contains", uid).get(),
    db.collection("users").doc(uid).collection("joined_groups").get(),
  ]);
  const groupIds = groupsSnap.docs.map((d) => d.id);
  const batch = db.batch();
  if (!after && before?.token) {
    const oldToken = before.token;
    chatRoomsSnap.docs.forEach((doc) => batch.update(doc.ref, { active_fcm_tokens: admin.firestore.FieldValue.arrayRemove(oldToken) }));
    groupIds.forEach((id) => batch.update(db.collection("groups").doc(id), { active_fcm_tokens: admin.firestore.FieldValue.arrayRemove(oldToken) }));
  } else if (after?.token && !before) {
    const newToken = after.token;
    chatRoomsSnap.docs.forEach((doc) => batch.set(doc.ref, { active_fcm_tokens: admin.firestore.FieldValue.arrayUnion(newToken) }, { merge: true }));
    groupIds.forEach((id) => batch.set(db.collection("groups").doc(id), { active_fcm_tokens: admin.firestore.FieldValue.arrayUnion(newToken) }, { merge: true }));
  } else if (before?.token && after?.token && before.token !== after.token) {
    const oldToken = before.token;
    const newToken = after.token;
    chatRoomsSnap.docs.forEach((doc) => {
      batch.update(doc.ref, { active_fcm_tokens: admin.firestore.FieldValue.arrayRemove(oldToken) });
      batch.update(doc.ref, { active_fcm_tokens: admin.firestore.FieldValue.arrayUnion(newToken) });
    });
    groupIds.forEach((id) => {
      batch.update(db.collection("groups").doc(id), { active_fcm_tokens: admin.firestore.FieldValue.arrayRemove(oldToken) });
      batch.update(db.collection("groups").doc(id), { active_fcm_tokens: admin.firestore.FieldValue.arrayUnion(newToken) });
    });
  }
  await batch.commit();
  return null;
});

export const onChatRoomMemberJoinedV2 = onDocumentCreated("chat_rooms/{roomId}/room_members/{uid}", async (event) => {
  const { roomId, uid } = event.params;
  const tokensSnap = await db.collection("users").doc(uid).collection("fcm_tokens").get();
  const tokens = tokensSnap.docs.map((d) => d.data().token as string);
  if (tokens.length === 0) return null;
  await db.collection("chat_rooms").doc(roomId).set({ active_fcm_tokens: admin.firestore.FieldValue.arrayUnion(...tokens) }, { merge: true });
  return null;
});

export const onChatRoomMemberLeftV2 = onDocumentDeleted("chat_rooms/{roomId}/room_members/{uid}", async (event) => {
  const { roomId, uid } = event.params;
  const tokensSnap = await db.collection("users").doc(uid).collection("fcm_tokens").get();
  const tokens = tokensSnap.docs.map((d) => d.data().token as string);
  if (tokens.length === 0) return null;
  await db.collection("chat_rooms").doc(roomId).update({ active_fcm_tokens: admin.firestore.FieldValue.arrayRemove(...tokens) });
  return null;
});

export const onGroupMemberJoinedV2 = onDocumentCreated("groups/{groupId}/members/{uid}", async (event) => {
  const { groupId, uid } = event.params;
  const tokensSnap = await db.collection("users").doc(uid).collection("fcm_tokens").get();
  const tokens = tokensSnap.docs.map((d) => d.data().token as string);
  if (tokens.length === 0) return null;
  await db.collection("groups").doc(groupId).set({ active_fcm_tokens: admin.firestore.FieldValue.arrayUnion(...tokens) }, { merge: true });
  return null;
});

export const onGroupMemberLeftV2 = onDocumentDeleted("groups/{groupId}/members/{uid}", async (event) => {
  const { groupId, uid } = event.params;
  const tokensSnap = await db.collection("users").doc(uid).collection("fcm_tokens").get();
  const tokens = tokensSnap.docs.map((d) => d.data().token as string);
  if (tokens.length === 0) return null;
  await db.collection("groups").doc(groupId).set({ active_fcm_tokens: admin.firestore.FieldValue.arrayRemove(...tokens) }, { merge: true });
  return null;
});

export const onUserNotificationCreatedV2 = onDocumentWritten("users/{uid}/notifications/{notiId}", async (event) => {
  const { uid } = event.params;
  const before = event.data?.before.data();
  const after = event.data?.after.data();

  if (!after) return null; // document was deleted

  const isNew = !before;
  const isUpdated = before && after.updated_at && before.updated_at?.toMillis() !== after.updated_at?.toMillis();

  if (!isNew && !isUpdated) return null;

  const noti = after;
  const title = (noti.title as string) ?? "새 알림";
  const body = (noti.body as string) ?? "";
  const type = (noti.type as string) ?? "system";
  const avatarUrl = (noti.data?.group_photo_url as string) ?? "";
  const tokens = await getTokensForUids([uid]);
  if (tokens.length === 0) return null;
  const payload: Omit<admin.messaging.MulticastMessage, "tokens"> = {
    notification: { title: title, body: body },
    data: { type: "notification", notiType: type, avatarUrl: avatarUrl, click_action: "FLUTTER_NOTIFICATION_CLICK" },
    android: { priority: "high", notification: { channelId: "high_importance_channel", clickAction: "FLUTTER_NOTIFICATION_CLICK" } },
    apns: { payload: { aps: { sound: "default", badge: 1, contentAvailable: true } } },
  };
  const invalidTokens = await sendChunked(tokens, payload);
  await cleanupInvalidTokens(invalidTokens);
  return null;
});

export { downgradeExpiredGroups, expireUserPayments } from "./downgradeExpiredGroups";
