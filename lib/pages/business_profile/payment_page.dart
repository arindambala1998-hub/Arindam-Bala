// lib/pages/business_profile/payment_page.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PaymentPage extends StatefulWidget {
  /// Total payable (₹)
  final double totalAmount;

  /// Order payload from Checkout / Booking page
  final Map<String, dynamic> orderData;

  /// Optional Bearer token
  final String? authToken;

  const PaymentPage({
    super.key,
    required this.totalAmount,
    required this.orderData,
    this.authToken,
  });

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  // Troonky gradient
  static const Color _g1 = Color(0xFFFF00CC);
  static const Color _g2 = Color(0xFF333399);

  // API base
  static const String _apiBase = "https://adminapi.troonky.in";

  // Use dart-define in prod:
  // flutter run --dart-define=RAZORPAY_KEY_ID=rzp_live_xxx
  static const String _razorpayKeyId = String.fromEnvironment(
    "RAZORPAY_KEY_ID",
    defaultValue: "rzp_test_RoGVhNOsgQgo9L",
  );

  late final Razorpay _razorpay;

  String _selectedMethod = "razorpay"; // "razorpay" | "cod"
  bool _agreeOpenBox = false; // only for product COD
  bool _loading = false;

  int? _localOrderId; // DB orders.id (product only)
  double? _serverTotal; // server computed total_amount (product only)
  String? _lastRzpOrderId; // for retry UX

  String? _token; // resolved token (authToken or prefs)
  Future<void>? _tokenFuture;

  // ---------- helpers ----------
  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  int _asInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  double _asDouble(dynamic v, {double fallback = 0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  String _asString(dynamic v, {String fallback = ""}) => v == null ? fallback : v.toString();

  Map<String, dynamic> _safeJson(String raw) {
    try {
      final d = jsonDecode(raw);
      if (d is Map<String, dynamic>) return d;
      if (d is Map) return Map<String, dynamic>.from(d);
      return {"data": d};
    } catch (_) {
      return {"raw": raw};
    }
  }

  int? _toIntAny(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final s = v.toString().trim();
    return int.tryParse(s);
  }

  String _toStrAny(dynamic v) => (v ?? "").toString().trim();

  Future<void> _initToken() async {
    final w = (widget.authToken ?? "").trim();
    if (w.isNotEmpty) {
      _token = w;
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final candidates = <String?>[
      prefs.getString("token"),
      prefs.getString("auth_token"),
      prefs.getString("access_token"),
      prefs.getString("jwt"),
      prefs.getString("user_token"),
    ];

    for (final t in candidates) {
      final v = (t ?? "").trim();
      if (v.isNotEmpty) {
        _token = v;
        return;
      }
    }
  }

  Future<void> _ensureToken() {
    _tokenFuture ??= _initToken();
    return _tokenFuture!;
  }

  // ✅ include x-access-token for backend compatibility
  Map<String, String> get _headers {
    final h = <String, String>{
      "Content-Type": "application/json",
      "Accept": "application/json",
    };
    final t = (_token ?? "").trim();
    if (t.isNotEmpty) {
      h["Authorization"] = "Bearer $t";
      h["x-access-token"] = t;
    }
    return h;
  }

  // -------- detect type --------
  bool get _isServiceBooking {
    final t = _asString(widget.orderData["type"]).trim().toLowerCase();
    if (t == "service_booking") return true;

    if (widget.orderData.containsKey("service_id") || widget.orderData.containsKey("serviceId")) return true;

    return false;
  }

  bool get _isProductOrder => !_isServiceBooking;

  bool get _needsOpenBoxAgreement => _isProductOrder && _selectedMethod == "cod";

  bool get _canPay => !_loading && _selectedMethod.isNotEmpty && (!_needsOpenBoxAgreement || _agreeOpenBox);

  Color _alpha(Color c, double opacity01) {
    final a = (opacity01.clamp(0.0, 1.0) * 255).round();
    return c.withAlpha(a);
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.deepPurple,
      ),
    );
  }

  Future<void> _showDialogOnly(String title, String msg) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<void> _finishAndPop({
    required String title,
    required String msg,
    required Map<String, dynamic> result,
  }) async {
    await _showDialogOnly(title, msg);
    if (!mounted) return;
    Navigator.pop(context, result);
  }

  // =========================================================
  // PRODUCT FLOW HELPERS
  // =========================================================

  /// sanitize items to match backend:
  List<Map<String, dynamic>> _sanitizeItems(dynamic raw) {
    final List items = (raw is List) ? raw : [];

    final businessId = _asInt(
      widget.orderData["business_id"] ?? widget.orderData["shop_id"] ?? widget.orderData["businessId"] ?? widget.orderData["shopId"],
      fallback: 0,
    );

    final out = <Map<String, dynamic>>[];

    for (final e in items) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);

      final pid = _asInt(m["product_id"] ?? m["id"] ?? m["_id"] ?? m["productId"], fallback: 0);
      final qty = _asInt(m["qty"] ?? m["quantity"], fallback: 1);

      final selectedColor = _asString(m["selected_color"] ?? m["color"]).trim();
      final selectedSize = _asString(m["selected_size"] ?? m["size"]).trim();

      final shopId = _asInt(
        m["shop_id"] ?? m["business_id"] ?? m["shopId"] ?? m["businessId"] ?? businessId,
        fallback: 0,
      );

      if (pid <= 0 || shopId <= 0) continue;

      final one = <String, dynamic>{
        "shop_id": shopId,
        "business_id": shopId,
        "product_id": pid,
        "id": pid,
        "qty": qty <= 0 ? 1 : qty,
        "quantity": qty <= 0 ? 1 : qty,
        "name": _asString(m["name"]),
      };

      if (m.containsKey("unit_price")) one["unit_price"] = m["unit_price"];
      if (m.containsKey("price")) one["price"] = m["price"];

      if (selectedColor.isNotEmpty) one["selected_color"] = selectedColor;
      if (selectedSize.isNotEmpty) one["selected_size"] = selectedSize;

      out.add(one);
    }

    return out;
  }

  int? _extractOrderId(Map<String, dynamic> decoded) {
    final direct = _toIntAny(decoded["order_id"] ?? decoded["id"]);
    if (direct != null && direct > 0) return direct;

    final order = decoded["order"];
    if (order is Map) {
      final id2 = _toIntAny(order["id"] ?? order["order_id"]);
      if (id2 != null && id2 > 0) return id2;
    }

    final data = decoded["data"];
    if (data is Map) {
      final id3 = _toIntAny(data["id"] ?? data["order_id"]);
      if (id3 != null && id3 > 0) return id3;
    }

    return null;
  }

  double? _extractTotal(Map<String, dynamic> decoded) {
    final t = _asDouble(decoded["total_amount"] ?? decoded["total"] ?? decoded["amount"], fallback: 0);
    if (t > 0) return t;

    final order = decoded["order"];
    if (order is Map) {
      final t2 = _asDouble(order["total_amount"] ?? order["total"] ?? order["amount"], fallback: 0);
      if (t2 > 0) return t2;
    }

    final data = decoded["data"];
    if (data is Map) {
      final t3 = _asDouble(data["total_amount"] ?? data["total"] ?? data["amount"], fallback: 0);
      if (t3 > 0) return t3;
    }
    return null;
  }

  bool _isSuccess(Map<String, dynamic> decoded) {
    final s = decoded["success"];
    if (s == true) return true;
    final err = decoded["error"];
    if (err == false) return true;

    final status = _toStrAny(decoded["status"]).toLowerCase();
    if (status == "success" || status == "ok") return true;

    return false;
  }

  // 1) CREATE LOCAL ORDER (DB) - retry safe: if already created, reuse it
  Future<int?> _createLocalOrder({required String paymentMode}) async {
    if (_localOrderId != null && _localOrderId! > 0) return _localOrderId;

    await _ensureToken();

    final businessId = _asInt(
      widget.orderData["business_id"] ?? widget.orderData["shop_id"] ?? widget.orderData["businessId"] ?? widget.orderData["shopId"],
      fallback: 0,
    );

    final customerName = _asString(
      widget.orderData["customer_name"] ?? widget.orderData["name"] ?? widget.orderData["customerName"],
    ).trim();

    final items = _sanitizeItems(widget.orderData["items"]);

    final mode = (paymentMode.toLowerCase().trim() == "online") ? "online" : "cod";

    final body = <String, dynamic>{
      "type": "product_order",
      "order_type": "product",
      "business_id": businessId,
      "shop_id": businessId,
      "customer_id": widget.orderData["customer_id"] ?? widget.orderData["user_id"],
      "customer_name": customerName,
      "phone": _asString(widget.orderData["phone"]).trim(),
      "address": _asString(widget.orderData["address"]).trim(),
      "pincode": _asString(widget.orderData["pincode"]).trim(),
      "payment_mode": mode,
      "payment_method": mode,
      "payment_status": mode == "cod" ? "unpaid" : "pending",
      "total_amount": widget.totalAmount,
      "amount": widget.totalAmount,
      "items": items,
      "products": items,
    };

    if (businessId <= 0) return null;
    if (customerName.isEmpty) return null;
    if (items.isEmpty) return null;

    final endpoints = <String>[
      "$_apiBase/api/orders/create",
      "$_apiBase/api/orders/add",
      "$_apiBase/api/orders/new",
      "$_apiBase/api/orders/place",
      "$_apiBase/api/order/create",
      "$_apiBase/api/orders",
    ];

    for (final ep in endpoints) {
      try {
        final res = await http.post(Uri.parse(ep), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 30));
        final decoded = _safeJson(res.body);

        if (kDebugMode) {
          debugPrint("🟦 CREATE ORDER -> ${res.statusCode} $ep");
          debugPrint(res.body);
        }

        if (res.statusCode == 200 || res.statusCode == 201) {
          if (!_isSuccess(decoded)) continue;

          final id = _extractOrderId(decoded);
          final total = _extractTotal(decoded);

          if (id != null && id > 0) {
            _localOrderId = id;
            if (total != null && total > 0) _serverTotal = total;
            return id;
          }
        }
      } catch (_) {}
    }

    _snack("Order create failed (no endpoint worked)", error: true);
    return null;
  }

  // 2) CREATE RAZORPAY ORDER (Gateway)
  Future<String?> _createRazorpayOrder({
    required String receipt,
    required double amountRupees,
    Map<String, dynamic>? notes,
  }) async {
    await _ensureToken();

    final endpoints = <String>[
      "$_apiBase/api/orders/pay",
      "$_apiBase/api/payment/pay",
      "$_apiBase/api/pay",
      "$_apiBase/api/razorpay/order",
      "$_apiBase/api/orders/razorpay",
    ];

    final payloadRupees = {"amount": amountRupees, "currency": "INR", "receipt": receipt, "notes": notes ?? {}};
    final payloadPaise = {"amount": (amountRupees * 100).round(), "currency": "INR", "receipt": receipt, "notes": notes ?? {}};

    for (final ep in endpoints) {
      for (final body in [payloadRupees, payloadPaise]) {
        try {
          final res = await http.post(Uri.parse(ep), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 30));
          final decoded = _safeJson(res.body);

          if (kDebugMode) {
            debugPrint("🟪 RZP PAY -> ${res.statusCode} $ep");
            debugPrint(res.body);
          }

          if (res.statusCode == 200 || res.statusCode == 201) {
            if (!_isSuccess(decoded)) continue;

            final order = decoded["order"];
            String id = "";

            if (order is Map) {
              id = _toStrAny(order["id"] ?? order["order_id"]);
            }
            if (id.isEmpty) {
              id = _toStrAny(decoded["id"] ?? decoded["order_id"] ?? decoded["rzp_order_id"]);
            }

            if (id.isNotEmpty) return id;
          }
        } catch (_) {}
      }
    }

    _snack("Failed to create Razorpay order", error: true);
    return null;
  }

  // 3) VERIFY PAYMENT SIGNATURE (product only)
  Future<bool> _verifyPayment({
    required int localOrderId,
    required PaymentSuccessResponse resp,
  }) async {
    await _ensureToken();

    final endpoints = <String>[
      "$_apiBase/api/orders/verify",
      "$_apiBase/api/orders/verify-payment",
      "$_apiBase/api/payment/verify",
      "$_apiBase/api/orders/payment/verify",
    ];

    final body = {
      "razorpay_order_id": resp.orderId,
      "razorpay_payment_id": resp.paymentId,
      "razorpay_signature": resp.signature,
      "order_id": localOrderId,
      "local_order_id": localOrderId,
    };

    for (final ep in endpoints) {
      try {
        final res = await http.post(Uri.parse(ep), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 30));
        final decoded = _safeJson(res.body);

        if (kDebugMode) {
          debugPrint("🟩 VERIFY -> ${res.statusCode} $ep");
          debugPrint(res.body);
        }

        if (res.statusCode == 200 || res.statusCode == 201) {
          if (_isSuccess(decoded)) return true;

          final verified = decoded["verified"] == true;
          if (verified) return true;
        }
      } catch (_) {}
    }

    return false;
  }

  // =========================================================
  // START PAYMENT (UNIFIED)
  // =========================================================
  Future<void> _startRazorpayFlow() async {
    if (widget.totalAmount <= 0) {
      _snack("Invalid amount", error: true);
      return;
    }

    if (_isProductOrder) {
      await _startRazorpayFlowProduct();
    } else {
      await _startRazorpayFlowService();
    }
  }

  /// PRODUCT: create local order -> create razorpay order -> open
  Future<void> _startRazorpayFlowProduct() async {
    _safeSetState(() => _loading = true);

    final localId = await _createLocalOrder(paymentMode: "online");
    if (!mounted) return;

    if (localId == null) {
      _safeSetState(() => _loading = false);
      await _showDialogOnly("Order Error", "Order create failed.\nCheck business_id, customer name, items(product_id, qty).");
      return;
    }

    final rupees = (_serverTotal != null && _serverTotal! > 0) ? _serverTotal! : widget.totalAmount;

    final rzpOrderId = await _createRazorpayOrder(
      receipt: "troonky_${localId}_${DateTime.now().millisecondsSinceEpoch}",
      amountRupees: rupees,
      notes: {
        "type": "product_order",
        "local_order_id": localId.toString(),
        "business_id": _toStrAny(widget.orderData["business_id"] ?? widget.orderData["shop_id"]),
        "customer_id": _toStrAny(widget.orderData["customer_id"]),
      },
    );

    if (!mounted) return;
    _safeSetState(() {
      _loading = false;
      _lastRzpOrderId = rzpOrderId;
    });

    if (rzpOrderId == null) {
      await _showDialogOnly("Payment Error", "Failed to create Razorpay order. Try again.");
      return;
    }

    final contact = (widget.orderData["phone"] ?? "9999999999").toString().trim();
    final email = (widget.orderData["email"] ?? "user@example.com").toString().trim();

    final options = {
      "key": _razorpayKeyId,
      "order_id": rzpOrderId,
      "amount": (rupees * 100).round(),
      "name": "Troonky",
      "description": "Secure payment for your order",
      "timeout": 180,
      "prefill": {"contact": contact, "email": email},
      "notes": {"type": "product_order", "local_order_id": localId.toString()},
      "theme": {"color": "#7F00FF"},
    };

    try {
      _razorpay.open(options);
    } catch (_) {
      await _showDialogOnly("Razorpay Error", "Unable to open Razorpay checkout.");
    }
  }

  /// SERVICE: create razorpay order -> open
  /// ✅ Booking will be created by BookServicePage after success/COD.
  Future<void> _startRazorpayFlowService() async {
    _safeSetState(() => _loading = true);

    final sid = _asString(widget.orderData["service_id"] ?? widget.orderData["serviceId"]).trim();
    final rupees = widget.totalAmount;

    final rzpOrderId = await _createRazorpayOrder(
      receipt: "troonky_service_${sid.isEmpty ? "x" : sid}_${DateTime.now().millisecondsSinceEpoch}",
      amountRupees: rupees,
      notes: {
        "type": "service_booking",
        "service_id": sid,
        "business_id": _toStrAny(widget.orderData["business_id"] ?? widget.orderData["shop_id"] ?? widget.orderData["businessId"] ?? widget.orderData["shopId"]),
        "date": _toStrAny(widget.orderData["date"] ?? widget.orderData["booking_date"]),
        "time": _toStrAny(widget.orderData["time"] ?? widget.orderData["time_label"]),
        "customer_mobile": _toStrAny(widget.orderData["mobile"] ?? widget.orderData["phone"]),
      },
    );

    if (!mounted) return;
    _safeSetState(() {
      _loading = false;
      _lastRzpOrderId = rzpOrderId;
    });

    if (rzpOrderId == null) {
      await _showDialogOnly("Payment Error", "Failed to create Razorpay order. Try again.");
      return;
    }

    final contact = (widget.orderData["mobile"] ?? widget.orderData["phone"] ?? "9999999999").toString().trim();
    final email = (widget.orderData["email"] ?? "user@example.com").toString().trim();

    final options = {
      "key": _razorpayKeyId,
      "order_id": rzpOrderId,
      "amount": (rupees * 100).round(),
      "name": "Troonky",
      "description": "Service booking payment",
      "timeout": 180,
      "prefill": {"contact": contact, "email": email},
      "notes": {"type": "service_booking", "service_id": sid},
      "theme": {"color": "#7F00FF"},
    };

    try {
      _razorpay.open(options);
    } catch (_) {
      await _showDialogOnly("Razorpay Error", "Unable to open Razorpay checkout.");
    }
  }

  // =========================================================
  // COD FLOW (UNIFIED)
  // =========================================================
  Future<void> _placeCOD() async {
    if (_isProductOrder) {
      await _placeCODProduct();
    } else {
      await _placeCODService();
    }
  }

  Future<void> _placeCODProduct() async {
    _safeSetState(() => _loading = true);

    final localId = await _createLocalOrder(paymentMode: "cod");
    if (!mounted) return;

    _safeSetState(() => _loading = false);

    if (localId == null) {
      await _showDialogOnly("Order Error", "COD order create failed. Check required fields.");
      return;
    }

    await _finishAndPop(
      title: "COD Confirmed",
      msg: "Order placed successfully.\nOrder ID: $localId",
      result: {
        "status": "cod",
        "method": "COD",
        "mode": "product",
        "order_id": localId,
        "verified": false,
      },
    );
  }

  /// ✅ SERVICE COD: Only return result.
  /// Booking will be created by BookServicePage via POST /api/bookings
  Future<void> _placeCODService() async {
    await _finishAndPop(
      title: "COD Selected",
      msg: "Payment mode set to COD.\nNow booking will be created.",
      result: {
        "status": "cod",
        "method": "COD",
        "mode": "service",
        "verified": false,
      },
    );
  }

  // =========================================================
  // RAZORPAY CALLBACKS
  // =========================================================
  Future<void> _onPaymentSuccess(PaymentSuccessResponse resp) async {
    _safeSetState(() => _loading = true);

    if (_isProductOrder) {
      final localId = _localOrderId;
      bool verified = false;

      if (localId != null) {
        verified = await _verifyPayment(localOrderId: localId, resp: resp);
      }

      if (!mounted) return;
      _safeSetState(() => _loading = false);

      await _finishAndPop(
        title: verified ? "Payment Successful" : "Payment Received",
        msg: verified
            ? "Payment verified ✅\nPayment ID: ${resp.paymentId}\nOrder ID: $localId"
            : "Payment done but verify failed ⚠️\nPayment ID: ${resp.paymentId}\nOrder ID: $localId",
        result: {
          "status": "success",
          "method": "ONLINE",
          "mode": "product",
          "order_id": localId,
          "paymentId": resp.paymentId,
          "razorpayOrderId": resp.orderId,
          "verified": verified,
        },
      );
      return;
    }

    // ✅ SERVICE: DO NOT create booking here (avoid double booking)
    if (!mounted) return;
    _safeSetState(() => _loading = false);

    await _finishAndPop(
      title: "Payment Successful",
      msg: "Payment done ✅\nNow booking will be created.",
      result: {
        "status": "success",
        "method": "ONLINE",
        "mode": "service",
        "paymentId": resp.paymentId,
        "razorpayOrderId": resp.orderId,
        "verified": true,
      },
    );
  }

  void _onPaymentError(PaymentFailureResponse resp) {
    _safeSetState(() => _loading = false);
    _showDialogOnly(
      "Payment Failed",
      resp.message ?? "Unknown error",
    );
  }

  void _onExternalWallet(ExternalWalletResponse resp) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Wallet Selected: ${resp.walletName ?? ""}")),
    );
  }

  // =========================================================
  // UI TEXT
  // =========================================================
  String get _openBoxPolicyText =>
      "Open-Box Delivery Policy\n\n"
          "• Please open the package in front of the delivery agent.\n"
          "• Verify item (quantity, model, color, damage) before accepting.\n"
          "• If you do NOT choose Open-Box delivery, please do NOT accept the parcel.\n"
          "• Once accepted without Open-Box verification, returns/refunds may not be supported.\n\n"
          "By continuing, you agree to follow this policy at the time of delivery.";

  String get _servicePolicyText =>
      "Service Booking Policy\n\n"
          "• After payment, booking request will be shared with provider.\n"
          "• Provider can confirm/reschedule based on availability.\n"
          "• If time is not selected, provider will contact you.\n"
          "• Cancellation/refund depends on provider policy.";

  @override
  void initState() {
    super.initState();

    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);

    _tokenFuture = _initToken();
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_g1, _g2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _topBar(),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF6F6F8),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      _summaryCard(),
                      const SizedBox(height: 12),
                      _methodCard(),
                      const SizedBox(height: 12),
                      _policyCard(),
                      const SizedBox(height: 12),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (!_loading && _selectedMethod == "razorpay" && _lastRzpOrderId == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.grey.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "If payment fails, you can tap Pay Now again to retry.",
                                  style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 90),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _bottomPayBar(),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _alpha(Colors.white, 0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _alpha(Colors.white, 0.28)),
              ),
              child: const Icon(Icons.arrow_back, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isServiceBooking ? "Service Payment" : "Payment",
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _alpha(Colors.white, 0.18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _alpha(Colors.white, 0.28)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(
                  "Secure",
                  style: TextStyle(color: _alpha(Colors.white, 0.95), fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    final shownTotal = (_serverTotal != null && _serverTotal! > 0) ? _serverTotal! : widget.totalAmount;

    final pName = _asString(widget.orderData["customer_name"]).trim();
    final pPhone = _asString(widget.orderData["phone"]).trim();
    final pAddress = _asString(widget.orderData["address"]).trim();
    final pincode = _asString(widget.orderData["pincode"]).trim();

    final sName = _asString(widget.orderData["name"] ?? widget.orderData["customer_name"]).trim();
    final sPhone = _asString(widget.orderData["mobile"] ?? widget.orderData["phone"]).trim();
    final sAddress = _asString(widget.orderData["address"]).trim();
    final sDate = _asString(widget.orderData["date"] ?? widget.orderData["booking_date"]).trim();
    final sTime = _asString(widget.orderData["time"] ?? widget.orderData["time_label"]).trim();
    final sServiceName = _asString(widget.orderData["service_name"] ?? widget.orderData["serviceName"]).trim();

    final title = _isServiceBooking ? (sServiceName.isEmpty ? "Service Booking" : sServiceName) : "Order Summary";

    final name = _isServiceBooking ? (sName.isEmpty ? "Customer" : sName) : (pName.isEmpty ? "Customer" : pName);
    final phone = _isServiceBooking ? sPhone : pPhone;
    final address = _isServiceBooking ? sAddress : pAddress;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(colors: [_g1, _g2]),
                ),
                child: Icon(_isServiceBooking ? Icons.miscellaneous_services : Icons.shopping_bag_outlined, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w900))),
              Text("₹${shownTotal.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ],
          ),
          const SizedBox(height: 10),
          if (phone.isNotEmpty) Text("📞 $phone", style: TextStyle(color: Colors.grey.shade800)),
          if (address.isNotEmpty) Text("🏠 $address", style: TextStyle(color: Colors.grey.shade800)),
          if (_isProductOrder && pincode.isNotEmpty) Text("📍 $pincode", style: TextStyle(color: Colors.grey.shade800)),
          if (_isServiceBooking && sDate.isNotEmpty) Text("📅 $sDate ${sTime.isNotEmpty ? "• $sTime" : ""}", style: TextStyle(color: Colors.grey.shade800)),
        ],
      ),
    );
  }

  Widget _methodCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Choose Payment Method", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 12),
          _methodTile(
            title: "UPI / Card / Wallet (Razorpay)",
            subtitle: _isServiceBooking ? "Pay now to continue booking" : "Pay via UPI, Card, Netbanking, Wallet",
            value: "razorpay",
            icon: Icons.payment,
          ),
          _methodTile(
            title: _isServiceBooking ? "Pay at Venue / Provider (COD)" : "Cash on Delivery (COD)",
            subtitle: _isServiceBooking ? "You can confirm booking with COD (if allowed)" : "Pay after verifying with Open-Box delivery",
            value: "cod",
            icon: Icons.money_rounded,
          ),
          if (_selectedMethod == "razorpay")
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: _alpha(Colors.deepPurple, 0.06),
                border: Border.all(color: _alpha(Colors.deepPurple, 0.14)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.auto_awesome, color: Colors.deepPurple),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Recommended: UPI first, then Card. You can still choose any method inside Razorpay.",
                      style: TextStyle(fontWeight: FontWeight.w700, height: 1.2),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _methodTile({
    required String title,
    required String subtitle,
    required String value,
    required IconData icon,
  }) {
    final selected = _selectedMethod == value;

    return InkWell(
      onTap: () {
        _safeSetState(() {
          _selectedMethod = value;
          if (_selectedMethod != "cod") _agreeOpenBox = false;
          if (_isServiceBooking) _agreeOpenBox = false;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? Colors.deepPurple : Colors.grey.shade300, width: selected ? 1.6 : 1),
          color: selected ? _alpha(Colors.deepPurple, 0.04) : Colors.white,
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.deepPurple),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              height: 22,
              width: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? Colors.deepPurple : Colors.grey.shade400, width: 2),
              ),
              child: selected
                  ? Center(
                child: Container(
                  height: 10,
                  width: 10,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.deepPurple),
                ),
              )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _policyCard() {
    final text = _isServiceBooking ? _servicePolicyText : _openBoxPolicyText;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_outlined, color: Colors.deepPurple),
              const SizedBox(width: 10),
              Text(
                _isServiceBooking ? "Booking Policy" : "Delivery Policy",
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(text, style: TextStyle(color: Colors.grey.shade800, height: 1.35, fontWeight: FontWeight.w600)),
          if (_needsOpenBoxAgreement) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _alpha(Colors.deepPurple, 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _alpha(Colors.deepPurple, 0.14)),
              ),
              child: CheckboxListTile(
                value: _agreeOpenBox,
                onChanged: (v) => _safeSetState(() => _agreeOpenBox = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  "I agree to Open-Box delivery and I will NOT accept the parcel without it.",
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bottomPayBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: const BoxDecoration(color: Colors.white),
        child: SizedBox(
          height: 54,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_g1, _g2]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: ElevatedButton(
              onPressed: !_canPay
                  ? null
                  : () {
                if (_selectedMethod == "razorpay") {
                  _startRazorpayFlow();
                } else {
                  _placeCOD();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(
                _loading
                    ? "Processing..."
                    : (_selectedMethod == "cod"
                    ? (_isServiceBooking ? "Continue (COD)" : "Place COD Order")
                    : "Pay Now"),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
