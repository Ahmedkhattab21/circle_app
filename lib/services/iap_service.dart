import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

const iapProductsUrl = 'https://cirgm.com/wp-json/app-iap/v1/products';

typedef IapJavascriptBridge =
    Future<void> Function(String functionName, Map<String, dynamic> data);

class IapPurchaseRequest {
  const IapPurchaseRequest({
    required this.intentId,
    required this.websiteProductId,
    required this.appleProductId,
    required this.iapType,
  });

  final String intentId;
  final int websiteProductId;
  final String appleProductId;
  final String iapType;
}

class _PendingTransaction {
  const _PendingTransaction({
    required this.transactionId,
    required this.intentId,
    required this.websiteProductId,
    required this.appleProductId,
  });

  factory _PendingTransaction.fromJson(Map<String, dynamic> json) {
    return _PendingTransaction(
      transactionId: json['transaction_id'] as String? ?? '',
      intentId: json['intent_id'] as String? ?? '',
      websiteProductId: (json['website_product_id'] as num?)?.toInt() ?? 0,
      appleProductId: json['apple_product_id'] as String? ?? '',
    );
  }

  final String transactionId;
  final String intentId;
  final int websiteProductId;
  final String appleProductId;

  Map<String, dynamic> toJson() => {
    'transaction_id': transactionId,
    'intent_id': intentId,
    'website_product_id': websiteProductId,
    'apple_product_id': appleProductId,
  };
}

class IapService {
  IapService({InAppPurchase? store}) : _store = store ?? InAppPurchase.instance;

  static const _pendingStorageKey = 'circle_iap_pending_transactions';

  final InAppPurchase _store;
  final Map<String, IapPurchaseRequest> _requestsByProductId = {};
  final Map<String, PurchaseDetails> _purchasesByTransactionId = {};
  final Set<String> _blockedTransactions = {};

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  SharedPreferences? _preferences;
  IapJavascriptBridge? _bridge;
  VoidCallback? _onTransactionFinished;
  bool _isIos = false;
  bool _isReady = false;

  bool get isSupported => _isIos;

  Future<void> initialize({
    required IapJavascriptBridge bridge,
    VoidCallback? onTransactionFinished,
  }) async {
    _bridge = bridge;
    _onTransactionFinished = onTransactionFinished;
    _isIos = defaultTargetPlatform == TargetPlatform.iOS;

    if (!_isIos) return;

    _preferences = await SharedPreferences.getInstance();
    _purchaseSubscription = _store.purchaseStream.listen(
      _handlePurchases,
      onError: (Object error) {
        unawaited(_sendStatus('error', error.toString()));
      },
    );

    final available = await _store.isAvailable().timeout(
      const Duration(seconds: 10),
    );
    if (!available) {
      throw StateError('Apple In-App Purchase is unavailable.');
    }

    await _loadProductsAllowList();
  }

  Future<void> _loadProductsAllowList() async {
    final response = await http
        .get(Uri.parse(iapProductsUrl))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw StateError('Unable to load Apple product mapping.');
    }

    final body = jsonDecode(response.body);
    final products = body is Map<String, dynamic> ? body['data'] : null;
    if (body is! Map<String, dynamic> ||
        body['success'] != true ||
        products is! List) {
      throw StateError('Invalid Apple product mapping response.');
    }

    for (final item in products) {
      if (item is! Map<String, dynamic>) continue;
      final appleId = item['apple_product_id'] as String?;
      final websiteId = (item['website_product_id'] as num?)?.toInt();
      final type = item['iap_type'] as String?;
      if (appleId == null || websiteId == null || type == null) continue;

      _requestsByProductId[appleId] = IapPurchaseRequest(
        intentId: '',
        websiteProductId: websiteId,
        appleProductId: appleId,
        iapType: type,
      );
    }
  }

  Future<void> handlePageMessage(String rawMessage) async {
    if (!_isIos) return;

    dynamic decoded;
    try {
      decoded = jsonDecode(rawMessage);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;

    switch (decoded['type']) {
      case 'ready':
        _isReady = true;
        await _deliverPendingTransactions();
      case 'purchase':
        await _startPurchase(decoded);
      case 'backend_result':
        await _handleBackendResult(decoded);
    }
  }

  Future<void> _startPurchase(Map<String, dynamic> data) async {
    final intentId = data['intent_id'] as String? ?? '';
    final appleProductId = data['apple_product_id'] as String? ?? '';
    final websiteProductId = (data['website_product_id'] as num?)?.toInt();
    final iapType = data['iap_type'] as String? ?? '';
    final allowListed = _requestsByProductId[appleProductId];

    if (intentId.isEmpty || websiteProductId == null || allowListed == null) {
      await _sendStatus('error', 'Invalid Apple product or purchase intent.');
      return;
    }

    if (allowListed.websiteProductId != websiteProductId ||
        allowListed.iapType != iapType) {
      await _sendStatus('error', 'Apple product mapping does not match.');
      return;
    }

    _requestsByProductId[appleProductId] = IapPurchaseRequest(
      intentId: intentId,
      websiteProductId: websiteProductId,
      appleProductId: appleProductId,
      iapType: iapType,
    );

    final response = await _store.queryProductDetails({appleProductId});
    if (response.notFoundIDs.contains(appleProductId) ||
        response.productDetails.isEmpty) {
      await _sendStatus('error', 'Apple product is not available in StoreKit.');
      return;
    }

    final product = response.productDetails.firstWhere(
      (item) => item.id == appleProductId,
    );
    final purchaseParam = PurchaseParam(
      productDetails: product,
      applicationUserName: intentId,
    );

    await _sendStatus('pending', '');
    final started = iapType == 'consumable'
        ? await _store.buyConsumable(
            purchaseParam: purchaseParam,
            autoConsume: false,
          )
        : await _store.buyNonConsumable(purchaseParam: purchaseParam);

    if (!started) {
      await _sendStatus('error', 'Unable to start Apple purchase.');
    }
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        await _sendStatus('pending', '');
        continue;
      }
      if (purchase.status == PurchaseStatus.canceled) {
        await _sendStatus('canceled', '');
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        await _sendStatus(
          'error',
          purchase.error?.message ?? 'Purchase failed.',
        );
        continue;
      }

      final transactionId = purchase.purchaseID;
      if (transactionId == null || transactionId.isEmpty) continue;

      final request = _requestsByProductId[purchase.productID];
      if (request == null) {
        await _sendStatus('error', 'Unknown Apple product.');
        continue;
      }

      final pending = _PendingTransaction(
        transactionId: transactionId,
        intentId: request.intentId,
        websiteProductId: request.websiteProductId,
        appleProductId: purchase.productID,
      );
      await _savePending(pending);
      _purchasesByTransactionId[transactionId] = purchase;

      if (_isReady) {
        await _deliverPendingTransaction(pending);
      }
    }
  }

  Future<void> _deliverPendingTransactions() async {
    for (final pending in await _readPending()) {
      await _deliverPendingTransaction(pending);
    }
  }

  Future<void> _deliverPendingTransaction(_PendingTransaction pending) async {
    if (_blockedTransactions.contains(pending.transactionId)) return;

    await _bridge?.call('onCircleIAPPurchaseCompleted', {
      'intent_id': pending.intentId,
      'website_product_id': pending.websiteProductId,
      'apple_product_id': pending.appleProductId,
      'transaction_id': pending.transactionId,
      'verification_data': _purchasesByTransactionId[pending.transactionId]
          ?.verificationData
          .serverVerificationData,
    });
  }

  Future<void> _handleBackendResult(Map<String, dynamic> result) async {
    final transactionId = result['transaction_id'] as String? ?? '';
    if (transactionId.isEmpty) return;

    final finish = result['finish_transaction'] == true;
    final retryable = result['retryable'] == true;
    if (finish) {
      final purchase = _purchasesByTransactionId[transactionId];
      if (purchase != null && purchase.pendingCompletePurchase) {
        await _store.completePurchase(purchase);
      }
      await _removePending(transactionId);
      _purchasesByTransactionId.remove(transactionId);
      _onTransactionFinished?.call();
    } else if (!retryable) {
      _blockedTransactions.add(transactionId);
      await _sendStatus(
        'error',
        result['message'] as String? ?? 'Purchase could not be verified.',
      );
    }
  }

  Future<void> _sendStatus(String status, String message) async {
    final data = <String, dynamic>{'status': status};
    if (message.isNotEmpty) data['message'] = message;
    await _bridge?.call('onCircleIAPStatus', data);
  }

  Future<List<_PendingTransaction>> _readPending() async {
    final values = _preferences?.getStringList(_pendingStorageKey) ?? [];
    return values
        .map(
          (value) => _PendingTransaction.fromJson(
            jsonDecode(value) as Map<String, dynamic>,
          ),
        )
        .where((item) => item.transactionId.isNotEmpty)
        .toList();
  }

  Future<void> _savePending(_PendingTransaction pending) async {
    final all = await _readPending();
    final updated = [
      ...all.where((item) => item.transactionId != pending.transactionId),
      pending,
    ];
    await _preferences?.setStringList(
      _pendingStorageKey,
      updated.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  Future<void> _removePending(String transactionId) async {
    final all = await _readPending();
    await _preferences?.setStringList(
      _pendingStorageKey,
      all
          .where((item) => item.transactionId != transactionId)
          .map((item) => jsonEncode(item.toJson()))
          .toList(),
    );
  }

  Future<void> dispose() async {
    await _purchaseSubscription?.cancel();
    _bridge = null;
  }
}
