import { randomBytes } from "crypto";
import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";

function getDb() {
  return admin.firestore();
}

function isPaidPlan(plan: string | undefined) {
  return plan === "plus" || plan === "pro";
}

async function getGroupContext(groupId: string, uid: string) {
  const db = getDb();
  const [groupDoc, memberDoc] = await Promise.all([
    db.collection("groups").doc(groupId).get(),
    db.collection("groups").doc(groupId).collection("members").doc(uid).get(),
  ]);

  if (!groupDoc.exists) {
    throw new HttpsError("not-found", "Group not found.");
  }
  if (!memberDoc.exists) {
    throw new HttpsError("permission-denied", "Not a group member.");
  }

  const group = groupDoc.data() ?? {};
  const member = memberDoc.data() ?? {};
  const canManageQr =
    group.owner_id === uid ||
    member.permissions?.can_edit_group_info === true ||
    member.permissions?.can_manage_permissions === true;

  if (!canManageQr) {
    throw new HttpsError(
      "permission-denied",
      "You do not have permission to manage the group QR."
    );
  }

  return { db, groupDoc, group };
}

async function createUniqueInviteToken() {
  const db = getDb();

  for (let i = 0; i < 5; i += 1) {
    const token = randomBytes(18).toString("base64url");
    const existing = await db
      .collection("groups")
      .where("invite_token", "==", token)
      .limit(1)
      .get();

    if (existing.empty) return token;
  }

  throw new HttpsError("internal", "Failed to generate a unique QR token.");
}

export const regenerateGroupQr = onCall(
  { region: "asia-northeast3" },
  async (request) => {
    const uid = request.auth?.uid;
    const groupId = request.data?.groupId as string | undefined;

    if (!uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }
    if (!groupId) {
      throw new HttpsError("invalid-argument", "groupId is required.");
    }

    const { groupDoc, group } = await getGroupContext(groupId, uid);
    if (!isPaidPlan(group.plan as string | undefined)) {
      throw new HttpsError(
        "failed-precondition",
        "QR is available for Plus or Pro plans only."
      );
    }

    const token = await createUniqueInviteToken();
    await groupDoc.ref.update({
      invite_token: token,
      qr_enabled: true,
      invite_token_updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { token, qrEnabled: true };
  }
);

export const setGroupQrEnabled = onCall(
  { region: "asia-northeast3" },
  async (request) => {
    const uid = request.auth?.uid;
    const groupId = request.data?.groupId as string | undefined;
    const enabled = request.data?.enabled as boolean | undefined;

    if (!uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }
    if (!groupId || enabled == null) {
      throw new HttpsError(
        "invalid-argument",
        "groupId and enabled are required."
      );
    }

    const { groupDoc, group } = await getGroupContext(groupId, uid);
    if (!isPaidPlan(group.plan as string | undefined)) {
      throw new HttpsError(
        "failed-precondition",
        "QR is available for Plus or Pro plans only."
      );
    }

    let token = group.invite_token as string | undefined;
    if (enabled && !token) {
      token = await createUniqueInviteToken();
    }

    const updateData: Record<string, unknown> = {
      qr_enabled: enabled,
    };
    if (token) {
      updateData.invite_token = token;
    }

    await groupDoc.ref.update(updateData);

    return { token: token ?? "", qrEnabled: enabled };
  }
);

export const joinGroupByQr = onCall(
  { region: "asia-northeast3" },
  async (request) => {
    const uid = request.auth?.uid;
    const token = request.data?.token as string | undefined;

    if (!uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }
    if (!token) {
      throw new HttpsError("invalid-argument", "token is required.");
    }

    const db = getDb();
    const groupSnap = await db
      .collection("groups")
      .where("invite_token", "==", token)
      .limit(1)
      .get();

    if (groupSnap.empty) {
      return { status: "invalid" };
    }

    const groupDoc = groupSnap.docs[0];
    const groupId = groupDoc.id;
    const group = groupDoc.data();

    if (!isPaidPlan(group.plan as string | undefined)) {
      return { status: "disabled" };
    }
    if ((group.qr_enabled as boolean | undefined) !== true) {
      return { status: "disabled" };
    }

    const [memberDoc, bannedDoc, userDoc] = await Promise.all([
      db.collection("groups").doc(groupId).collection("members").doc(uid).get(),
      db.collection("groups").doc(groupId).collection("banned").doc(uid).get(),
      db.collection("users").doc(uid).get(),
    ]);

    if (memberDoc.exists) {
      return { status: "already_member", groupId };
    }
    if (bannedDoc.exists) {
      return { status: "banned" };
    }

    const memberCount = (group.member_count as number | undefined) ?? 0;
    const memberLimit = (group.member_limit as number | undefined) ?? 50;
    if (memberCount >= memberLimit) {
      return { status: "full" };
    }

    const user = userDoc.data() ?? {};
    const displayName = (user.name as string | undefined) ?? "Unknown";
    const phoneNumber = (user.phone_number as string | undefined) ?? "";
    const profileImage = (user.profile_image as string | undefined) ?? "";

    if (group.require_approval === true) {
      const requestRef = db
        .collection("groups")
        .doc(groupId)
        .collection("join_requests")
        .doc(uid);
      const pending = await requestRef.get();

      if (!pending.exists) {
        await requestRef.set({
          user_id: uid,
          display_name: displayName,
          phone_number: phoneNumber,
          profile_image: profileImage,
          requested_at: admin.firestore.FieldValue.serverTimestamp(),
          status: "pending",
        });
      }

      return {
        status: "requested",
        groupId,
        groupName: (group.name as string | undefined) ?? "",
      };
    }

    const batch = db.batch();
    batch.set(
      db.collection("groups").doc(groupId).collection("members").doc(uid),
      {
        user_id: uid,
        display_name: displayName,
        profile_image: profileImage,
        joined_at: admin.firestore.FieldValue.serverTimestamp(),
        role: "member",
        permissions: {
          can_post_schedule: false,
          can_create_sub_chat: false,
          can_write_post: true,
          can_edit_group_info: false,
          can_manage_permissions: false,
        },
      }
    );
    batch.update(db.collection("groups").doc(groupId), {
      member_count: admin.firestore.FieldValue.increment(1),
    });
    batch.set(
      db.collection("users").doc(uid).collection("joined_groups").doc(groupId),
      {
        joined_at: admin.firestore.FieldValue.serverTimestamp(),
        name: (group.name as string | undefined) ?? "",
        type: (group.type as string | undefined) ?? "",
        category: (group.category as string | undefined) ?? "",
        member_count: memberCount + 1,
      }
    );

    const chatSnap = await db
      .collection("chat_rooms")
      .where("ref_group_id", "==", groupId)
      .where("type", "==", "group_all")
      .limit(1)
      .get();

    if (!chatSnap.empty) {
      const chatRef = chatSnap.docs[0].ref;
      batch.update(chatRef, {
        member_ids: admin.firestore.FieldValue.arrayUnion(uid),
        [`unread_counts.${uid}`]: 0,
      });
      batch.set(chatRef.collection("room_members").doc(uid), {
        uid,
        display_name: displayName,
        role: "member",
        joined_at: admin.firestore.FieldValue.serverTimestamp(),
        last_read_time: admin.firestore.FieldValue.serverTimestamp(),
        unread_cnt: 0,
      });
    }

    await batch.commit();

    return {
      status: "joined",
      groupId,
      groupName: (group.name as string | undefined) ?? "",
    };
  }
);
