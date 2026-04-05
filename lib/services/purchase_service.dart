import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

class PurchaseCatalog {
  final bool storeAvailable;
  final List<PurchaseCatalogItem> items;
  final Set<String> notFoundIds;

  const PurchaseCatalog({
    required this.storeAvailable,
    required this.items,
    this.notFoundIds = const <String>{},
  });
}

class PurchaseCatalogItem {
  final String logicalProductId;
  final String storeProductId;
  final ProductDetails productDetails;
  final String title;
  final String description;
  final String price;

  const PurchaseCatalogItem({
    required this.logicalProductId,
    required this.storeProductId,
    required this.productDetails,
    required this.title,
    required this.description,
    required this.price,
  });
}

class GroupPurchaseService {
  GroupPurchaseService._();

  static final GroupPurchaseService instance = GroupPurchaseService._();

  static const String androidSubscriptionId = 'group_plan';
  static const String plusMonthly = 'plus-monthly';
  static const String plusYearly = 'plus-yearly';
  static const String proMonthly = 'pro-monthly';
  static const String proYearly = 'pro-yearly';

  static const Set<String> logicalProductIds = <String>{
    plusMonthly,
    plusYearly,
    proMonthly,
    proYearly,
  };

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');
  final FirebaseAuth _auth = FirebaseAuth.instance;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  bool _initialized = false;
  _PendingPurchaseContext? _activePurchase;

  Future<void> initialize() async {
    if (_initialized) return;
    _purchaseSub = _inAppPurchase.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: _handlePurchaseStreamError,
    );
    _initialized = true;
  }

  Future<PurchaseCatalog> loadCatalog() async {
    await initialize();

    final available = await _inAppPurchase.isAvailable();
    if (!available) {
      return const PurchaseCatalog(storeAvailable: false, items: <PurchaseCatalogItem>[]);
    }

    final ids = defaultTargetPlatform == TargetPlatform.android
        ? <String>{androidSubscriptionId}
        : logicalProductIds;

    final response = await _inAppPurchase.queryProductDetails(ids);
    final items = defaultTargetPlatform == TargetPlatform.android
        ? _buildAndroidCatalog(response.productDetails)
        : _buildDefaultCatalog(response.productDetails);

    items.sort((a, b) =>
        _sortIndex(a.logicalProductId).compareTo(_sortIndex(b.logicalProductId)));

    return PurchaseCatalog(
      storeAvailable: true,
      items: items,
      notFoundIds: response.notFoundIDs.toSet(),
    );
  }

  Future<void> purchaseGroupPlan({
    required String groupId,
    required PurchaseCatalogItem item,
  }) async {
    await initialize();

    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw Exception('Login required.');
    }
    if (_activePurchase != null) {
      throw Exception('Another purchase is already in progress.');
    }

    final completer = Completer<void>();
    _activePurchase = _PendingPurchaseContext(
      groupId: groupId,
      logicalProductId: item.logicalProductId,
      storeProductId: item.storeProductId,
      completer: completer,
    );

    final launched = await _inAppPurchase.buyNonConsumable(
      purchaseParam: PurchaseParam(
        productDetails: item.productDetails,
        applicationUserName: uid,
      ),
    );

    if (!launched) {
      _activePurchase = null;
      throw Exception('Could not start the purchase flow.');
    }

    await completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        _activePurchase = null;
        throw TimeoutException('Purchase verification timed out.');
      },
    );
  }

  String planForProduct(String logicalProductId) =>
      logicalProductId.startsWith('pro-') ? 'pro' : 'plus';

  bool isYearlyProduct(String logicalProductId) =>
      logicalProductId.endsWith('yearly');

  List<PurchaseCatalogItem> _buildDefaultCatalog(List<ProductDetails> products) {
    return products
        .where((product) => logicalProductIds.contains(product.id))
        .map(
          (product) => PurchaseCatalogItem(
            logicalProductId: product.id,
            storeProductId: product.id,
            productDetails: product,
            title: product.title.trim(),
            description: product.description.trim(),
            price: product.price,
          ),
        )
        .toList();
  }

  List<PurchaseCatalogItem> _buildAndroidCatalog(List<ProductDetails> products) {
    final items = <PurchaseCatalogItem>[];

    for (final product in products) {
      if (product is! GooglePlayProductDetails) continue;
      final index = product.subscriptionIndex;
      if (index == null) continue;

      final offerDetails = product.productDetails.subscriptionOfferDetails;
      if (offerDetails == null || index >= offerDetails.length) continue;

      final basePlanId = offerDetails[index].basePlanId;
      if (!logicalProductIds.contains(basePlanId)) continue;

      items.add(
        PurchaseCatalogItem(
          logicalProductId: basePlanId,
          storeProductId: product.id,
          productDetails: product,
          title: _androidTitle(basePlanId),
          description: product.description.trim(),
          price: product.price,
        ),
      );
    }

    return items;
  }

  String _androidTitle(String logicalProductId) {
    switch (logicalProductId) {
      case plusMonthly:
        return 'PLUS Monthly';
      case plusYearly:
        return 'PLUS Yearly';
      case proMonthly:
        return 'PRO Monthly';
      case proYearly:
        return 'PRO Yearly';
      default:
        return logicalProductId;
    }
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    final activePurchase = _activePurchase;
    if (activePurchase == null) {
      for (final purchase in purchases) {
        if (purchase.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchase);
        }
      }
      return;
    }

    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        continue;
      }

      if (purchase.status == PurchaseStatus.canceled) {
        await _finishActivePurchase(
          purchase,
          error: Exception('Purchase cancelled.'),
        );
        continue;
      }

      if (purchase.status == PurchaseStatus.error) {
        await _finishActivePurchase(
          purchase,
          error: Exception(purchase.error?.message ?? 'Purchase failed.'),
        );
        continue;
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        try {
          await _submitPurchaseToServer(
            context: activePurchase,
            purchase: purchase,
          );
          await _finishActivePurchase(purchase);
        } catch (error) {
          await _finishActivePurchase(purchase, error: error);
        }
      }
    }
  }

  void _handlePurchaseStreamError(Object error) {
    final activePurchase = _activePurchase;
    _activePurchase = null;
    final completer = activePurchase?.completer;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
    }
  }

  Future<void> _submitPurchaseToServer({
    required _PendingPurchaseContext context,
    required PurchaseDetails purchase,
  }) async {
    final callable = _functions.httpsCallable('submitGroupPurchaseV1');
    await callable.call(<String, dynamic>{
      'groupId': context.groupId,
      'productId': context.logicalProductId,
      'storeProductId': context.storeProductId,
      'purchaseId': purchase.purchaseID,
      'transactionDate': purchase.transactionDate,
      'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'apple' : 'google',
      'verificationData': <String, dynamic>{
        'localVerificationData': purchase.verificationData.localVerificationData,
        'serverVerificationData': purchase.verificationData.serverVerificationData,
        'source': purchase.verificationData.source,
      },
    });
  }

  Future<void> _finishActivePurchase(
    PurchaseDetails purchase, {
    Object? error,
  }) async {
    if (purchase.pendingCompletePurchase) {
      await _inAppPurchase.completePurchase(purchase);
    }

    final activePurchase = _activePurchase;
    _activePurchase = null;

    final completer = activePurchase?.completer;
    if (completer == null || completer.isCompleted) return;

    if (error != null) {
      completer.completeError(error);
    } else {
      completer.complete();
    }
  }

  int _sortIndex(String logicalProductId) {
    switch (logicalProductId) {
      case plusMonthly:
        return 0;
      case plusYearly:
        return 1;
      case proMonthly:
        return 2;
      case proYearly:
        return 3;
      default:
        return 100;
    }
  }

  void dispose() {
    _purchaseSub?.cancel();
    _purchaseSub = null;
    _initialized = false;
    _activePurchase = null;
  }
}

class _PendingPurchaseContext {
  final String groupId;
  final String logicalProductId;
  final String storeProductId;
  final Completer<void> completer;

  const _PendingPurchaseContext({
    required this.groupId,
    required this.logicalProductId,
    required this.storeProductId,
    required this.completer,
  });
}
