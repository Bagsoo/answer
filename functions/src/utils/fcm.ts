import * as admin from "firebase-admin";

function getDb() {
  return admin.firestore();
}

function getMessaging() {
  return admin.messaging();
}

// ── 유틸: uid 배열로 FCM 토큰 배열 조회 ──────────────────────────────────────
export async function getTokensForUids(uids: string[]): Promise<string[]> {
  if (uids.length === 0) return [];
  const db = getDb();
  const snaps = await Promise.all(
    uids.map((uid) =>
      db.collection("users").doc(uid).collection("fcm_tokens").get()
    )
  );
  return snaps.flatMap((s) => s.docs.map((d) => d.data().token as string));
}

// ── 유틸: uid 배열로 FCM 토큰 맵 조회 { [uid]: string[] } ────────────────────
// downgradeExpiredGroups처럼 uid별로 토큰을 추적해야 할 때 사용
export async function getTokenMapForUids(
  uids: string[]
): Promise<Record<string, string[]>> {
  if (uids.length === 0) return {};
  const db = getDb();
  const tokenMap: Record<string, string[]> = {};
  await Promise.all(
    uids.map(async (uid) => {
      const snap = await db
        .collection("users")
        .doc(uid)
        .collection("fcm_tokens")
        .get();
      tokenMap[uid] = snap.docs
        .map((d) => d.data()?.token as string)
        .filter(Boolean);
    })
  );
  return tokenMap;
}

// ── 유틸: 토큰 배열을 500개씩 청크로 나눠 FCM 전송 ──────────────────────────
export async function sendChunked(
  tokens: string[],
  payload: Omit<admin.messaging.MulticastMessage, "tokens">
): Promise<string[]> {
  const messaging = getMessaging();
  const chunkSize = 500;
  const invalidTokens: string[] = [];

  for (let i = 0; i < tokens.length; i += chunkSize) {
    const chunk = tokens.slice(i, i + chunkSize);
    const response = await messaging.sendEachForMulticast({
      ...payload,
      tokens: chunk,
    });

    // 상세 로그
    response.responses.forEach((res, idx) => {
      if (res.success) return;
      console.error(
        `[FCM response] token: ${chunk[idx].substring(0, 20)}, ` +
        `error: ${res.error?.code ?? "unknown"}, ` +
        `message: ${res.error?.message ?? "none"}`
      );
    });

    // 무효 토큰 수집
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
export async function cleanupInvalidTokens(
  invalidTokens: string[]
): Promise<void> {
  if (invalidTokens.length === 0) return;
  const db = getDb();

  // Firestore "in" 쿼리는 최대 30개 — 청크 처리
  const CHUNK_SIZE = 30;
  for (let i = 0; i < invalidTokens.length; i += CHUNK_SIZE) {
    const chunk = invalidTokens.slice(i, i + CHUNK_SIZE);
    const snap = await db
      .collectionGroup("fcm_tokens")
      .where("token", "in", chunk)
      .get();

    if (snap.empty) continue;

    const batch = db.batch();
    snap.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }
}
