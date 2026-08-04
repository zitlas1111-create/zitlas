import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'wallet_repository.dart';

/// How a checkout attempt ended.
enum CheckoutOutcome { success, cancelled, failed }

/// The result of opening Razorpay's native sheet.
@immutable
class CheckoutResult {
  const CheckoutResult._(this.outcome, {this.orderId, this.paymentId, this.signature, this.message});

  const CheckoutResult.success({
    required String orderId,
    required String paymentId,
    required String signature,
  }) : this._(CheckoutOutcome.success,
            orderId: orderId, paymentId: paymentId, signature: signature);

  const CheckoutResult.cancelled() : this._(CheckoutOutcome.cancelled);

  const CheckoutResult.failed(String message)
      : this._(CheckoutOutcome.failed, message: message);

  final CheckoutOutcome outcome;
  final String? orderId, paymentId, signature, message;

  bool get isSuccess => outcome == CheckoutOutcome.success;
}

/// Opens Razorpay's native checkout and resolves to a single [CheckoutResult].
///
/// Wraps the SDK's three-callback API into one awaitable call so the caller
/// can't accidentally handle "success" and "cancelled" as separate,
/// independently-firing paths — the bug class where a dismissed sheet still
/// runs the credit branch.
///
/// NO KEY IS COMPILED INTO THE APP. The `key_id` arrives per-order from
/// `POST /api/payment/create-order`, and the payment is only worth anything
/// after the backend verifies its HMAC signature — a forged success callback
/// credits nothing.
class RazorpayCheckout {
  RazorpayCheckout({Razorpay? razorpay}) : _razorpay = razorpay ?? Razorpay();

  final Razorpay _razorpay;

  Future<CheckoutResult> open({
    required WalletOrder order,
    required String description,
    String? email,
    String? contact,
  }) {
    final completer = Completer<CheckoutResult>();

    // Every handler resolves through here, so whichever callback fires first
    // wins and the rest are ignored. Razorpay can emit more than one on some
    // dismiss paths.
    void settle(CheckoutResult result) {
      _razorpay.clear();
      if (!completer.isCompleted) completer.complete(result);
    }

    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      if (kDebugMode) debugPrint('[WALLET] razorpay success payment=${r.paymentId}');
      final orderId = r.orderId ?? order.orderId;
      final paymentId = r.paymentId;
      final signature = r.signature;
      if (paymentId == null || signature == null) {
        // Without both, the backend cannot verify. Better to report a failure
        // the athlete can escalate than to send an unverifiable request.
        settle(const CheckoutResult.failed(
          'The payment app returned an incomplete confirmation. If money was '
          'deducted, contact support — it has not been lost.',
        ));
        return;
      }
      settle(CheckoutResult.success(
        orderId: orderId,
        paymentId: paymentId,
        signature: signature,
      ));
    });

    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      if (kDebugMode) debugPrint('[WALLET] razorpay error code=${r.code} msg=${r.message}');
      // Code 2 is Razorpay's "payment cancelled by user" — not a failure worth
      // showing an error for.
      if (r.code == Razorpay.PAYMENT_CANCELLED) {
        settle(const CheckoutResult.cancelled());
        return;
      }
      settle(CheckoutResult.failed(
        _cleanMessage(r.message) ?? 'The payment could not be completed. Please try again.',
      ));
    });

    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {
      // The athlete left for an external wallet app. Nothing is confirmed yet,
      // and there is no callback when they come back, so this ends the attempt
      // rather than leaving a spinner running forever. The order stays valid
      // server-side and a completed payment is picked up by the live wallet
      // stream.
      if (kDebugMode) debugPrint('[WALLET] external wallet: ${r.walletName}');
      settle(const CheckoutResult.cancelled());
    });

    try {
      _razorpay.open({
        'key': order.keyId,
        'order_id': order.orderId,
        'amount': order.amountPaise,
        'currency': order.currency,
        'name': 'ZITLAS',
        'description': description,
        'theme': {'color': '#FF9800'},
        if (email != null || contact != null)
          'prefill': {'email': ?email, 'contact': ?contact},
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[WALLET] razorpay open threw: $e');
      settle(const CheckoutResult.failed(
        "Couldn't open the payment screen. Please try again.",
      ));
    }

    return completer.future;
  }

  void dispose() => _razorpay.clear();

  /// Razorpay messages are sometimes a raw JSON blob rather than prose.
  static String? _cleanMessage(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.startsWith('{')) return null;
    return trimmed;
  }
}
