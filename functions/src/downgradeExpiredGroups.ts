import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";
import {
  getTokenMapForUids,
  sendChunked,
  cleanupInvalidTokens,
} from "./utils/fcm";

function getDb() {
  return admin.firestore();
}

/**
 * 매일 KST 자정(00:00)에 실행
 * expires_at이 지난 그룹을 free 플랜으로 다운그레이드하고
 * owner + payer(있는 경우)에게 FCM 푸시 알림을 발송합니다.
 *
 * groups 필드 전제:
 *   plan: 'free' | 'plus' | 'pro'
 *   expires_at: Timestamp | null
 *   owner_id: string
 *   payer_uid: string | null   -- 결제 시스템 설정 시 존재, 수동 설정 시 null
 *   payment_id: string | null
 *   user_payment_expires_at: Timestamp | null   -- 별도 user_payment 상품 만기
 */
export const downgradeExpiredGroups = onSchedule(
  {
    schedule: "0 0 * * *",
    timeZone: "Asia/Seoul",
    timeoutSeconds: 540,
    memory: "256MiB",
    region: "asia-northeast3",
  },
  async () => {
    const now = admin.firestore.Timestamp.now();
    const db = getDb();

    // ── 1. 만료된 유료 그룹 조회 ──────────────────────────────────────────────
    const expiredSnap = await db
      .collection("groups")
      .where("plan", "!=", "free")
      .where("expires_at", "<=", now)
      .get();

    if (expiredSnap.empty) {
      logger.info("[downgrade] 만료된 그룹 없음");
      return;
    }

    logger.info(`[downgrade] 만료된 그룹 ${expiredSnap.size}개 처리 시작`);

    // ── 2. 알림 대상 UID 수집 후 토큰 일괄 조회 ───────────────────────────────
    const allUids = new Set<string>();
    for (const groupDoc of expiredSnap.docs) {
      const g = groupDoc.data();
      if (g.owner_id) allUids.add(g.owner_id);
      if (g.payer_uid) allUids.add(g.payer_uid);
    }
    const tokenMap = await getTokenMapForUids([...allUids]);

    // ── 3. 각 그룹 처리 ───────────────────────────────────────────────────────
    let batch = db.batch();
    let batchCount = 0;
    const tasks: Promise<void>[] = [];

    for (const groupDoc of expiredSnap.docs) {
      const group = groupDoc.data();
      const groupId = groupDoc.id;
      const prevPlan = group.plan as string;

      // 3-1. groups 문서 다운그레이드
      batch.update(groupDoc.ref, {
        plan: "free",
        qr_enabled: false,
        expires_at: null,
        payment_id: null,
        payer_uid: null,
        downgraded_at: now,
        downgraded_reason: "subscription_expired",
      });
      batchCount++;

      if (batchCount === 500) {
        await batch.commit();
        batch = db.batch();
        batchCount = 0;
      }

      // 3-2. group_payment subscription_status → expired
      tasks.push(updateGroupPaymentStatus(groupId, now));

      // 3-3. FCM 발송 대상 결정
      //   수동 설정 (payer_uid = null) → owner에게만
      //   결제 시스템 설정 (payer_uid 있음) → owner + payer
      //   owner === payer인 경우 Set이 자동 중복 제거
      const targetUids = new Set<string>();
      if (group.owner_id) targetUids.add(group.owner_id);
      if (group.payer_uid) targetUids.add(group.payer_uid);

      const tokens = [...targetUids].flatMap((uid) => tokenMap[uid] ?? []);

      if (tokens.length > 0) {
        tasks.push(sendExpiryPush(tokens, group.name, prevPlan, groupId));
      } else {
        logger.warn(
          `[downgrade] 그룹 ${groupId} (${group.name}): FCM 토큰 없음, 푸시 생략`
        );
      }
    }

    if (batchCount > 0) await batch.commit();

    const results = await Promise.allSettled(tasks);
    const failed = results.filter((r) => r.status === "rejected");
    if (failed.length > 0) {
      logger.error(`[downgrade] ${failed.length}개 작업 실패`, failed);
    }

    logger.info(`[downgrade] 완료: ${expiredSnap.size}개 그룹 다운그레이드`);
  }
);

// ── Helpers ───────────────────────────────────────────────────────────────────

async function updateGroupPaymentStatus(
  groupId: string,
  now: admin.firestore.Timestamp
): Promise<void> {
  const db = getDb();
  const groupPaymentSnap = await db
    .collection("payments")
    .where("group_id", "==", groupId)
    .where("type", "==", "group_payment")
    .where("subscription_status", "==", "active")
    .get();

  if (groupPaymentSnap.empty) return;

  const batch = db.batch();
  for (const payDoc of groupPaymentSnap.docs) {
    batch.update(payDoc.ref, {
      subscription_status: "expired",
      expired_at: now,
    });
  }
  await batch.commit();

  logger.info(
    `[downgrade] 그룹 ${groupId}: group_payment ${groupPaymentSnap.size}건 expired 처리`
  );
}

async function sendExpiryPush(
  tokens: string[],
  groupName: string,
  prevPlan: string,
  groupId: string
): Promise<void> {
  const payload: Omit<admin.messaging.MulticastMessage, "tokens"> = {
    notification: {
      title: "그룹 플랜이 만료되었습니다",
      body: `${groupName} 그룹의 ${prevPlan.toUpperCase()} 플랜이 만료되어 Free로 변경되었습니다.`,
    },
    data: {
      type: "group_plan_expired",
      group_id: groupId,
      prev_plan: prevPlan,
    },
    apns: {
      payload: { aps: { sound: "default", badge: 1 } },
    },
    android: {
      priority: "normal",
    },
  };

  const invalidTokens = await sendChunked(tokens, payload);
  await cleanupInvalidTokens(invalidTokens);

  logger.info(
    `[downgrade] 그룹 ${groupId} FCM 완료 (토큰 ${tokens.length}개, 무효 ${invalidTokens.length}개)`
  );
}

/**
 * 매일 KST 00:05에 실행
 * user_payment_expires_at이 지난 user_payment 상품을 expired 처리하고
 * owner에게 만기 알림을 발송합니다.
 *
 * payments 필드 전제:
 *   type: "user_payment"
 *   owner_uid: string
 *   subscription_status: "active" | "expired"
 *   user_payment_expires_at: Timestamp | null
 */
export const expireUserPayments = onSchedule(
  {
    schedule: "5 0 * * *",
    timeZone: "Asia/Seoul",
    timeoutSeconds: 540,
    memory: "256MiB",
    region: "asia-northeast3",
  },
  async () => {
    const now = admin.firestore.Timestamp.now();
    const db = getDb();
    const expiredSnap = await db
      .collection("payments")
      .where("type", "==", "user_payment")
      .where("subscription_status", "==", "active")
      .where("user_payment_expires_at", "<=", now)
      .get();

    if (expiredSnap.empty) {
      logger.info("[user_payment] 만료된 user_payment 없음");
      return;
    }

    const ownerUids = [
      ...new Set(
        expiredSnap.docs
          .map((doc) => doc.data().owner_uid as string | undefined)
          .filter((uid): uid is string => Boolean(uid))
      ),
    ];
    const tokenMap = await getTokenMapForUids(ownerUids);

    let batch = db.batch();
    let batchCount = 0;
    const tasks: Promise<void>[] = [];

    for (const paymentDoc of expiredSnap.docs) {
      const payment = paymentDoc.data();
      const ownerUid = payment.owner_uid as string | undefined;

      batch.update(paymentDoc.ref, {
        subscription_status: "expired",
        expired_at: now,
      });
      batchCount++;

      if (batchCount === 500) {
        await batch.commit();
        batch = db.batch();
        batchCount = 0;
      }

      if (!ownerUid) continue;

      const tokens = tokenMap[ownerUid] ?? [];
      if (tokens.length === 0) continue;

      tasks.push(
        sendUserPaymentExpiryPush(
          tokens,
          (payment.product_name as string | undefined) ?? "개별 상품"
        )
      );
    }

    if (batchCount > 0) await batch.commit();

    const results = await Promise.allSettled(tasks);
    const failed = results.filter((r) => r.status === "rejected");
    if (failed.length > 0) {
      logger.error(`[user_payment] ${failed.length}개 작업 실패`, failed);
    }

    logger.info(`[user_payment] 완료: ${expiredSnap.size}건 expired 처리`);
  }
);

async function sendUserPaymentExpiryPush(
  tokens: string[],
  productName: string
): Promise<void> {
  const payload: Omit<admin.messaging.MulticastMessage, "tokens"> = {
    notification: {
      title: "상품 이용 기간이 만료되었습니다",
      body: `${productName}의 이용 기간이 만료되었습니다.`,
    },
    data: {
      type: "user_payment_expired",
      product_name: productName,
    },
    apns: {
      payload: { aps: { sound: "default", badge: 1 } },
    },
    android: {
      priority: "normal",
    },
  };

  const invalidTokens = await sendChunked(tokens, payload);
  await cleanupInvalidTokens(invalidTokens);
}
