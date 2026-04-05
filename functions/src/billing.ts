import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { GoogleAuth } from "google-auth-library";
import {
  AppStoreServerAPIClient,
  Environment,
  ReceiptUtility,
} from "@apple/app-store-server-library";

function getDb() {
  return admin.firestore();
}

type PurchaseValidationResult = {
  transactionId: string;
  originalTransactionId: string;
  purchasedAt: admin.firestore.Timestamp;
  expiresAt: admin.firestore.Timestamp;
  amount?: number;
  currency?: string;
};

type SupportedPlan = "plus" | "pro";
type BillingCycle = "monthly" | "yearly";

const PLAN_LIMITS: Record<SupportedPlan | "free", number> = {
  free: 50,
  plus: 300,
  pro: 1000,
};

const PRODUCT_CONFIG: Record<
  string,
  { plan: SupportedPlan; billingCycle: BillingCycle; pricingKey: string }
> = {
  "plus-monthly": {
    plan: "plus",
    billingCycle: "monthly",
    pricingKey: "plus_monthly",
  },
  "plus-yearly": {
    plan: "plus",
    billingCycle: "yearly",
    pricingKey: "plus_yearly",
  },
  "pro-monthly": {
    plan: "pro",
    billingCycle: "monthly",
    pricingKey: "pro_monthly",
  },
  "pro-yearly": {
    plan: "pro",
    billingCycle: "yearly",
    pricingKey: "pro_yearly",
  },
};

const FALLBACK_PRICES: Record<string, number> = {
  "plus-monthly": 4.99,
  "plus-yearly": 49.99,
  "pro-monthly": 7.99,
  "pro-yearly": 85.99,
};

async function getPricingData(productId: string) {
  const db = getDb();
  const config = PRODUCT_CONFIG[productId];
  const pricingDoc = await db.collection("_config").doc("pricing").get();
  const pricing = pricingDoc.data() ?? {};
  const amount =
    (pricing[config.pricingKey] as number | undefined) ??
    FALLBACK_PRICES[productId];
  const currency = (pricing.currency as string | undefined) ?? "USD";

  return { amount, currency };
}

function getRequiredEnv(name: string) {
  const value = process.env[name];
  if (!value || value.trim().length === 0) {
    throw new HttpsError(
      "failed-precondition",
      `Missing required billing environment variable: ${name}`
    );
  }
  return value;
}

function parseRfc3339Timestamp(value: string | undefined, fallback: Date) {
  if (!value) return admin.firestore.Timestamp.fromDate(fallback);
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return admin.firestore.Timestamp.fromDate(fallback);
  }
  return admin.firestore.Timestamp.fromDate(parsed);
}

function decodeJwsPayload<T>(token: string): T {
  const parts = token.split(".");
  if (parts.length < 2) {
    throw new HttpsError("invalid-argument", "Invalid Apple signed payload.");
  }
  const payload = Buffer.from(parts[1], "base64url").toString("utf8");
  return JSON.parse(payload) as T;
}

async function validateGooglePurchase(input: {
  logicalProductId: string;
  storeProductId: string;
  purchaseToken: string;
}): Promise<PurchaseValidationResult> {
  const packageName =
    process.env.GOOGLE_PLAY_PACKAGE_NAME?.trim() || "com.answer.app";
  const auth = new GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
  });
  const client = await auth.getClient();

  const encodedPackageName = encodeURIComponent(packageName);
  const encodedToken = encodeURIComponent(input.purchaseToken);
  const url =
    "https://androidpublisher.googleapis.com/androidpublisher/v3/" +
    `applications/${encodedPackageName}/purchases/subscriptionsv2/tokens/${encodedToken}`;

  const response = await client.request<{
    subscriptionState?: string;
    lineItems?: Array<{
      productId?: string;
      expiryTime?: string;
      latestSuccessfulOrderId?: string;
      startTime?: string;
      offerDetails?: {
        basePlanId?: string;
        offerId?: string;
      };
    }>;
  }>({url, method: "GET"});

  const data = response.data;
  const allowedStates = new Set<string>([
    "SUBSCRIPTION_STATE_ACTIVE",
    "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
    "SUBSCRIPTION_STATE_ON_HOLD",
  ]);
  if (!data.subscriptionState || !allowedStates.has(data.subscriptionState)) {
    throw new HttpsError(
      "failed-precondition",
      `Google Play subscription is not active: ${data.subscriptionState ?? "unknown"}`
    );
  }

  const lineItems = data.lineItems ?? [];
  const matchedLineItem = lineItems.find((lineItem) => {
    return lineItem.offerDetails?.basePlanId === input.logicalProductId ||
      lineItem.offerDetails?.offerId === input.logicalProductId ||
      lineItem.productId === input.logicalProductId;
  });

  if (!matchedLineItem) {
    throw new HttpsError(
      "failed-precondition",
      "Google Play purchase does not match the selected subscription plan."
    );
  }

  const now = new Date();
  const purchasedAt = parseRfc3339Timestamp(matchedLineItem.startTime, now);
  const expiresAt = parseRfc3339Timestamp(matchedLineItem.expiryTime, now);
  const transactionId =
    matchedLineItem.latestSuccessfulOrderId ?? input.purchaseToken;

  return {
    transactionId,
    originalTransactionId: input.purchaseToken,
    purchasedAt,
    expiresAt,
  };
}

async function validateApplePurchase(input: {
  logicalProductId: string;
  receiptData: string;
}): Promise<PurchaseValidationResult> {
  const issuerId = getRequiredEnv("APPLE_ISSUER_ID");
  const keyId = getRequiredEnv("APPLE_KEY_ID");
  const privateKey = getRequiredEnv("APPLE_PRIVATE_KEY").replace(/\\n/g, "\n");
  const bundleId = process.env.APPLE_BUNDLE_ID?.trim() || "com.answer.app";
  const environmentValue =
    process.env.APPLE_ENVIRONMENT?.trim().toUpperCase() || "SANDBOX";
  const environment = environmentValue === "PRODUCTION" ?
    Environment.PRODUCTION :
    Environment.SANDBOX;

  const receiptUtility = new ReceiptUtility();
  const transactionId =
    receiptUtility.extractTransactionIdFromAppReceipt(input.receiptData);
  if (!transactionId) {
    throw new HttpsError(
      "invalid-argument",
      "Could not extract a transaction ID from the App Store receipt."
    );
  }

  const client = new AppStoreServerAPIClient(
    privateKey,
    keyId,
    issuerId,
    bundleId,
    environment
  );

  const transactionInfo = await client.getTransactionInfo(transactionId);
  const signedTransaction = transactionInfo.signedTransactionInfo;
  if (!signedTransaction) {
    throw new HttpsError(
      "failed-precondition",
      "App Store transaction response did not include signed data."
    );
  }

  const payload = decodeJwsPayload<{
    bundleId?: string;
    productId?: string;
    transactionId?: string;
    originalTransactionId?: string;
    purchaseDate?: number;
    expiresDate?: number;
    currency?: string;
    price?: number;
    revocationDate?: number;
  }>(signedTransaction);

  if (payload.bundleId != null && payload.bundleId !== bundleId) {
    throw new HttpsError(
      "failed-precondition",
      "App Store receipt bundle ID mismatch."
    );
  }
  if (payload.productId !== input.logicalProductId) {
    throw new HttpsError(
      "failed-precondition",
      "App Store purchase does not match the selected subscription plan."
    );
  }
  if (payload.revocationDate != null) {
    throw new HttpsError(
      "failed-precondition",
      "This App Store transaction has been revoked."
    );
  }

  const purchaseDateMs = payload.purchaseDate ?? Date.now();
  const expiresDateMs = payload.expiresDate ?? purchaseDateMs;

  return {
    transactionId: payload.transactionId ?? transactionId,
    originalTransactionId:
      payload.originalTransactionId ?? payload.transactionId ?? transactionId,
    purchasedAt: admin.firestore.Timestamp.fromMillis(purchaseDateMs),
    expiresAt: admin.firestore.Timestamp.fromMillis(expiresDateMs),
    currency: payload.currency,
    amount: payload.price != null ? payload.price / 1000 : undefined,
  };
}

function normalizeTransactionId(data: {
  purchaseId?: string;
  transactionDate?: string;
  productId: string;
}) {
  const purchaseId = data.purchaseId?.trim();
  if (purchaseId) return purchaseId;

  const transactionDate = data.transactionDate?.trim();
  if (transactionDate) {
    return `${data.productId}_${transactionDate}`;
  }

  throw new HttpsError(
    "invalid-argument",
    "Missing transaction identifier from the purchase result."
  );
}

export const submitGroupPurchaseV1 = onCall(
  { region: "asia-northeast3" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const groupId = request.data?.groupId as string | undefined;
    const productId = request.data?.productId as string | undefined;
    const storeProductId = request.data?.storeProductId as string | undefined;
    const platform = request.data?.platform as string | undefined;
    const purchaseId = request.data?.purchaseId as string | undefined;
    const transactionDate = request.data?.transactionDate as
      | string
      | undefined;
    const verificationData = request.data?.verificationData as
      | Record<string, unknown>
      | undefined;

    if (!groupId || !productId || !platform || !storeProductId) {
      throw new HttpsError(
        "invalid-argument",
        "groupId, productId, storeProductId, and platform are required."
      );
    }

    const config = PRODUCT_CONFIG[productId];
    if (!config) {
      throw new HttpsError("invalid-argument", "Unsupported productId.");
    }

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
    const canManagePlan =
      group.owner_id === uid ||
      member.permissions?.can_edit_group_info === true ||
      member.permissions?.can_manage_permissions === true;

    if (!canManagePlan) {
      throw new HttpsError(
        "permission-denied",
        "You do not have permission to manage this group plan."
      );
    }

    const verificationPayload = verificationData ?? {};
    const serverVerificationData =
      (verificationPayload["serverVerificationData"] as string | undefined) ?? "";

    let validationResult: PurchaseValidationResult;
    if (platform === "google") {
      if (serverVerificationData.length === 0) {
        throw new HttpsError(
          "invalid-argument",
          "Missing Google Play purchase token."
        );
      }
      validationResult = await validateGooglePurchase({
        logicalProductId: productId,
        storeProductId,
        purchaseToken: serverVerificationData,
      });
    } else if (platform === "apple") {
      if (serverVerificationData.length === 0) {
        throw new HttpsError(
          "invalid-argument",
          "Missing App Store receipt data."
        );
      }
      validationResult = await validateApplePurchase({
        logicalProductId: productId,
        receiptData: serverVerificationData,
      });
    } else {
      throw new HttpsError("invalid-argument", "Unsupported platform.");
    }

    const transactionId = validationResult.transactionId ||
      normalizeTransactionId({
        purchaseId,
        transactionDate,
        productId,
      });

    const duplicateSnap = await db
      .collection("payments")
      .where("transaction_id", "==", transactionId)
      .limit(1)
      .get();

    if (!duplicateSnap.empty) {
      const existing = duplicateSnap.docs[0].data() ?? {};
      return {
        status: "duplicate",
        paymentId: duplicateSnap.docs[0].id,
        plan: existing.plan ?? config.plan,
      };
    }

    const now = admin.firestore.Timestamp.now();
    const purchasedAt = validationResult.purchasedAt;
    const expiresAt = validationResult.expiresAt;

    const ownerUid = (group.owner_id as string | undefined) ?? uid;
    const groupName = (group.name as string | undefined) ?? "";
    const currentMemberLimit =
      (group.member_limit as number | undefined) ?? PLAN_LIMITS.free;
    const nextMaxLimit = PLAN_LIMITS[config.plan];
    const nextMemberLimit =
      currentMemberLimit > nextMaxLimit ? nextMaxLimit : currentMemberLimit;
    const configuredPricing = await getPricingData(productId);
    const amount = validationResult.amount ?? configuredPricing.amount;
    const currency = validationResult.currency ?? configuredPricing.currency;

    const paymentRef = db.collection("payments").doc();
    const batch = db.batch();

    batch.set(paymentRef, {
      type: "group_payment",
      payer_uid: uid,
      owner_uid: ownerUid,
      group_id: groupId,
      group_name: groupName,
      platform,
      product_id: productId,
      plan: config.plan,
      billing_cycle: config.billingCycle,
      amount,
      currency,
      payment_status: "paid",
      subscription_status: "active",
      transaction_id: transactionId,
      original_transaction_id: validationResult.originalTransactionId,
      receipt_validated: true,
      receipt_validation_mode: platform,
      receipt_payload: {
        verification_source: verificationData?.["source"] ?? "",
        store_product_id: storeProductId,
        server_verification_data:
          verificationData?.["serverVerificationData"] ?? "",
      },
      purchased_at: purchasedAt,
      expires_at: expiresAt,
      created_at: now,
      updated_at: now,
    });

    batch.update(groupDoc.ref, {
      plan: config.plan,
      max_member_limit: nextMaxLimit,
      member_limit: nextMemberLimit,
      expires_at: expiresAt,
      payment_id: paymentRef.id,
      payer_uid: uid,
      updated_at: now,
    });

    await batch.commit();

    return {
      status: "ok",
      paymentId: paymentRef.id,
      plan: config.plan,
      expiresAt: expiresAt.toMillis(),
    };
  }
);
