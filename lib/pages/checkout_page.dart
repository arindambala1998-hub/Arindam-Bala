// lib/pages/checkout_page.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'business_profile/controllers/cart_controller.dart';
import 'business_profile/payment_page.dart';

class CheckoutPage extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  const CheckoutPage({super.key, required this.items});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  // Troonky gradient
  static const Color _g1 = Color(0xFFFF00CC);
  static const Color _g2 = Color(0xFF333399);

  final _formKey = GlobalKey<FormState>();

  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  final pincodeCtrl = TextEditingController();

  // coupon UI (frontend-ready)
  final couponCtrl = TextEditingController();
  bool couponApplying = false;
  String appliedCoupon = "";
  double discountAmount = 0;

  // pricing
  double shippingFee = 0; // future ready (distance/slot based)
  double taxAmount = 0; // future ready
  bool placing = false;

  // saved address (local)
  Map<String, String> _saved = const {};
  bool _prefilledOnce = false;

  // ---------- safe helpers ----------
  double _asDouble(dynamic v, {double fallback = 0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  int _asInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  String _asString(dynamic v, {String fallback = ""}) => v == null ? fallback : v.toString();

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.deepPurple,
      ),
    );
  }

  /// Returns raw product id string (supports: product_id, productId, id, _id)
  String _productIdRaw(Map<String, dynamic> p) {
    return (p["product_id"] ?? p["productId"] ?? p["id"] ?? p["_id"] ?? "").toString().trim();
  }

  /// Best effort: if numeric -> int else null
  int? _productIdAsIntIfPossible(Map<String, dynamic> p) {
    final raw = _productIdRaw(p);
    if (raw.isEmpty) return null;

    final asInt = int.tryParse(raw);
    if (asInt != null) return asInt;

    final v = p["product_id"];
    final direct = _asInt(v, fallback: 0);
    if (direct > 0) return direct;

    return null;
  }

  /// business_id resolve from item -> shop_id/business_id (supports String/int)
  int _resolveBusinessId() {
    for (final it in widget.items) {
      final b = it["business_id"] ?? it["shop_id"] ?? it["businessId"] ?? it["shopId"];
      final bid = _asInt(b, fallback: 0);
      if (bid > 0) return bid;

      final s = (b ?? "").toString().trim();
      final p = int.tryParse(s);
      if (p != null && p > 0) return p;
    }
    return 0;
  }

  /// ✅ prevent multi-shop checkout (backend order create expects one shop)
  bool _allItemsSameBusiness(int businessId) {
    for (final it in widget.items) {
      final b = it["business_id"] ?? it["shop_id"] ?? it["businessId"] ?? it["shopId"];
      final bid = _asInt(b, fallback: 0);
      if (bid > 0 && bid != businessId) return false;
    }
    return true;
  }

  // ✅ token multi-key fallback (same as CartPage)
  Future<String?> _getToken() async {
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
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  /// ✅ supports int or string stored in prefs
  Future<int?> _getCustomerId() async {
    final prefs = await SharedPreferences.getInstance();
    const keys = ["userId", "customer_id", "id", "user_id", "uid"];
    for (final k in keys) {
      dynamic v;
      try {
        v = prefs.get(k);
      } catch (_) {
        v = null;
      }
      if (v == null) continue;

      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) {
        final n = int.tryParse(v.trim());
        if (n != null) {
          try {
            await prefs.setInt(k, n);
          } catch (_) {}
          return n;
        }
      }
    }
    return null;
  }

  double _unitPrice(Map<String, dynamic> it) {
    final unit = _asDouble(it["unit_price"], fallback: 0);
    if (unit > 0) return unit;
    final offer = _asDouble(it["offer_price"], fallback: 0);
    final base = _asDouble(it["price"], fallback: 0);
    return offer > 0 ? offer : base;
  }

  double get _subtotal {
    double total = 0;
    for (final it in widget.items) {
      final qty = _asInt(it["qty"], fallback: 1);
      final q = qty <= 0 ? 1 : qty;
      total += q * _unitPrice(it);
    }
    return total;
  }

  double get _grandTotal {
    final v = _subtotal + shippingFee + taxAmount - discountAmount;
    return v < 0 ? 0 : v;
  }

  // ==============================
  // ✅ Saved address: local prefs
  // ==============================
  static const _kShipName = "ship_name";
  static const _kShipPhone = "ship_phone";
  static const _kShipAddress = "ship_address";
  static const _kShipPincode = "ship_pincode";

  Future<void> _loadSavedAddress() async {
    final prefs = await SharedPreferences.getInstance();
    final m = <String, String>{
      "name": (prefs.getString(_kShipName) ?? "").trim(),
      "phone": (prefs.getString(_kShipPhone) ?? "").trim(),
      "address": (prefs.getString(_kShipAddress) ?? "").trim(),
      "pincode": (prefs.getString(_kShipPincode) ?? "").trim(),
    };

    if (!mounted) return;
    setState(() => _saved = m);
  }

  Future<void> _saveAddressToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kShipName, nameCtrl.text.trim());
    await prefs.setString(_kShipPhone, phoneCtrl.text.trim());
    await prefs.setString(_kShipAddress, addressCtrl.text.trim());
    await prefs.setString(_kShipPincode, pincodeCtrl.text.trim());
    await _loadSavedAddress();
  }

  Future<void> _clearSavedAddress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kShipName);
    await prefs.remove(_kShipPhone);
    await prefs.remove(_kShipAddress);
    await prefs.remove(_kShipPincode);
    await _loadSavedAddress();
    if (mounted) _snack("Saved address cleared");
  }

  void _useSavedAddress() {
    if (!mounted) return;
    nameCtrl.text = (_saved["name"] ?? "").trim();
    phoneCtrl.text = (_saved["phone"] ?? "").trim();
    addressCtrl.text = (_saved["address"] ?? "").trim();
    pincodeCtrl.text = (_saved["pincode"] ?? "").trim();
    _snack("Saved address applied");
  }

  Future<void> _prefillFromPrefsProfile() async {
    // profile-like keys (backward compat)
    final prefs = await SharedPreferences.getInstance();
    final name = (prefs.getString("name") ?? prefs.getString("username") ?? "").trim();
    final phone = (prefs.getString("phone") ?? "").trim();
    final address = (prefs.getString("address") ?? "").trim();
    final pincode = (prefs.getString("pincode") ?? "").trim();

    if (!mounted) return;

    // Only prefill once & only if empty
    if (!_prefilledOnce) {
      if (nameCtrl.text.trim().isEmpty && name.isNotEmpty) nameCtrl.text = name;
      if (phoneCtrl.text.trim().isEmpty && phone.isNotEmpty) phoneCtrl.text = phone;
      if (addressCtrl.text.trim().isEmpty && address.isNotEmpty) addressCtrl.text = address;
      if (pincodeCtrl.text.trim().isEmpty && pincode.isNotEmpty) pincodeCtrl.text = pincode;
      _prefilledOnce = true;
    }
  }

  // ==============================
  // ✅ Validations
  // ==============================
  String? _validateName(String v) {
    final s = v.trim();
    if (s.length < 2) return "Enter name";
    return null;
  }

  String? _validatePhone(String v) {
    final s = v.trim();
    if (s.length != 10) return "Enter 10 digit phone";
    final n = int.tryParse(s);
    if (n == null) return "Invalid phone";
    // common India mobile rule
    if (!(s.startsWith("6") || s.startsWith("7") || s.startsWith("8") || s.startsWith("9"))) {
      return "Invalid phone";
    }
    return null;
  }

  String? _validateAddress(String v) {
    final s = v.trim();
    if (s.length < 6) return "Enter address";
    return null;
  }

  String? _validatePincode(String v) {
    final s = v.trim();
    if (s.length != 6) return "Enter 6 digit pincode";
    final n = int.tryParse(s);
    if (n == null) return "Invalid pincode";
    if (s.startsWith("0")) return "Invalid pincode";
    return null;
  }

  String? _validateCartItems() {
    if (widget.items.isEmpty) return "Cart is empty.";

    for (final it in widget.items) {
      final qty = _asInt(it["qty"], fallback: 0);
      if (qty <= 0) return "Invalid quantity found in cart.";

      final rawId = _productIdRaw(it);
      final intId = _productIdAsIntIfPossible(it) ?? int.tryParse(rawId);
      if ((intId ?? 0) <= 0) return "Invalid product id: $rawId (must be numeric).";

      final stock = _asInt(it["stock"], fallback: -1);
      if (stock >= 0 && qty > stock) {
        final name = _asString(it["name"], fallback: "Item");
        return "$name has only $stock left. Reduce quantity.";
      }

      final openBox = it["open_box_delivery"];
      if (openBox == false || openBox?.toString().toLowerCase() == "false") {
        final name = _asString(it["name"], fallback: "Item");
        return "Blocked item (Open-box OFF): $name";
      }
    }
    return null;
  }

  // ==============================
  // ✅ Payload matches backend order create (robust keys)
  // ==============================
  Map<String, dynamic> _buildOrderData({
    required int businessId,
    int? customerId,
  }) {
    return {
      "type": "product_order",
      "order_type": "product",
      "payment_mode": "cod", // PaymentPage will override if online

      "business_id": businessId,
      "shop_id": businessId,

      "customer_id": customerId,
      "customer_name": nameCtrl.text.trim(),
      "phone": phoneCtrl.text.trim(),
      "address": addressCtrl.text.trim(),
      "pincode": pincodeCtrl.text.trim(),

      // ✅ price breakup (server should still compute final)
      "subtotal": _subtotal,
      "shipping_fee": shippingFee,
      "tax_amount": taxAmount,
      "discount_amount": discountAmount,
      "total_amount": _grandTotal,

      if (appliedCoupon.isNotEmpty) "coupon_code": appliedCoupon,

      "items": widget.items.map((it) {
        final qty = _asInt(it["qty"], fallback: 1);
        final price = _unitPrice(it);

        final rawId = _productIdRaw(it);
        final intId = _productIdAsIntIfPossible(it) ?? int.tryParse(rawId);

        return {
          "shop_id": businessId,
          "business_id": businessId,

          "product_id": intId ?? 0,
          "id": intId ?? 0,

          "name": _asString(it["name"]),
          "qty": qty,
          "quantity": qty,

          "unit_price": price,
          "price": price,
          "selected_color": _asString(it["selected_color"]),
          "selected_size": _asString(it["selected_size"]),
        };
      }).toList(),
    };
  }

  Future<void> _clearCartSafe() async {
    final cart = Provider.of<CartController>(context, listen: false);

    try {
      await (cart as dynamic).clearCart();
      return;
    } catch (_) {}

    try {
      await (cart as dynamic).reset();
      return;
    } catch (_) {}

    try {
      (cart as dynamic).clear();
      return;
    } catch (_) {}
  }

  // ==============================
  // ✅ Coupon (frontend-ready demo)
  // ==============================
  Future<void> _applyCoupon() async {
    if (couponApplying) return;

    final code = couponCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      _snack("Enter coupon code", error: true);
      return;
    }

    setState(() => couponApplying = true);
    try {
      // ✅ Demo rule:
      // TROONKY10 => 10% off, max 100
      // FREESHIP => shipping=0
      await Future.delayed(const Duration(milliseconds: 400));

      if (code == "TROONKY10") {
        final d = _subtotal * 0.10;
        final capped = d > 100 ? 100.0 : d;
        setState(() {
          appliedCoupon = code;
          discountAmount = capped;
        });
        _snack("Coupon applied: -₹${capped.toStringAsFixed(0)}");
        return;
      }

      if (code == "FREESHIP") {
        setState(() {
          appliedCoupon = code;
          shippingFee = 0;
          discountAmount = 0;
        });
        _snack("Free shipping applied");
        return;
      }

      _snack("Invalid coupon", error: true);
    } finally {
      if (mounted) setState(() => couponApplying = false);
    }
  }

  void _removeCoupon() {
    setState(() {
      appliedCoupon = "";
      discountAmount = 0;
      couponCtrl.clear();
    });
    _snack("Coupon removed");
  }

  // ==============================
  // ✅ Payment result normalize
  // ==============================
  Map<String, dynamic> _normalizePaymentResult(Map<String, dynamic> r) {
    final method = (r["method"] ?? "").toString().toUpperCase().trim();
    final statusRaw = (r["status"] ?? "").toString().toLowerCase().trim();

    String status = statusRaw;
    if (status.isEmpty && method.isNotEmpty) {
      if (method == "COD") status = "cod";
      if (method == "ONLINE") status = "success";
    }

    final orderId = r["order_id"] ?? r["orderId"] ?? r["id"];
    final paymentId = (r["paymentId"] ?? r["razorpay_payment_id"] ?? "").toString();
    final verified = r["verified"] == true;

    return {
      "status": status,
      "order_id": orderId,
      "paymentId": paymentId,
      "verified": verified,
      "method": method,
      "raw": r,
    };
  }

  Future<void> _onPlaceOrderPressed() async {
    if (placing) return;
    if (!_formKey.currentState!.validate()) return;

    final businessId = _resolveBusinessId();
    if (businessId <= 0) {
      _snack("Business ID missing in cart items.", error: true);
      return;
    }

    if (!_allItemsSameBusiness(businessId)) {
      _snack("Multiple shop items in cart. Please checkout one shop at a time.", error: true);
      return;
    }

    if (_subtotal <= 0) {
      _snack("Subtotal invalid.", error: true);
      return;
    }

    final cartErr = _validateCartItems();
    if (cartErr != null) {
      _snack(cartErr, error: true);
      return;
    }

    setState(() => placing = true);

    try {
      // save shipping details locally
      await _saveAddressToPrefs();

      final token = await _getToken();
      final customerId = await _getCustomerId();

      final orderData = _buildOrderData(businessId: businessId, customerId: customerId);

      if (kDebugMode) {
        debugPrint("✅ Checkout -> business_id: ${orderData["business_id"]} | items: ${(orderData["items"] as List).length} | total: $_grandTotal");
      }

      final result = await Navigator.push<Map<String, dynamic>?>(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentPage(
            totalAmount: _grandTotal,
            orderData: orderData,
            authToken: token,
          ),
        ),
      );

      if (!mounted) return;
      if (result == null) return;

      final normalized = _normalizePaymentResult(result);

      final status = (normalized["status"] ?? "").toString();
      final orderId = normalized["order_id"];
      final paymentId = (normalized["paymentId"] ?? "").toString();
      final verified = normalized["verified"] == true;
      final method = (normalized["method"] ?? "").toString();

      final isCod = status == "cod";
      final isOnline = status == "success";

      if (isCod || isOnline) {
        await _clearCartSafe();

        if (isCod) {
          _snack("Order placed (COD) ✅  Order ID: $orderId");
        } else {
          _snack(verified ? "Payment verified ✅  Order ID: $orderId" : "Payment done ✅  Order ID: $orderId");
        }

        Navigator.pop(context, {
          "ok": true,
          "status": status,
          "method": method,
          "order_id": orderId,
          "paymentId": paymentId,
          "verified": verified,
        });
        return;
      }

      _snack("Payment not completed.", error: true);
    } catch (e, st) {
      debugPrint("❌ Checkout error: $e");
      debugPrint("$st");
      final msg = kReleaseMode ? "Something went wrong!" : "Error: $e";
      _snack(msg, error: true);
    } finally {
      if (mounted) setState(() => placing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    // load saved + profile prefill
    unawaited(_loadSavedAddress().then((_) {
      _useSavedIfFormEmpty();
    }));
    unawaited(_prefillFromPrefsProfile());
  }

  void _useSavedIfFormEmpty() {
    // If form is empty but saved exists -> apply gently
    final hasSaved = (_saved["address"] ?? "").trim().isNotEmpty;
    if (!hasSaved) return;

    if (nameCtrl.text.trim().isEmpty &&
        phoneCtrl.text.trim().isEmpty &&
        addressCtrl.text.trim().isEmpty &&
        pincodeCtrl.text.trim().isEmpty) {
      _useSavedAddress();
    }
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    phoneCtrl.dispose();
    addressCtrl.dispose();
    pincodeCtrl.dispose();
    couponCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final multiShopBlocked = () {
      final bid = _resolveBusinessId();
      if (bid <= 0) return false;
      return !_allItemsSameBusiness(bid);
    }();

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF5F6FA),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0.4,
            foregroundColor: Colors.black,
            title: const Text("Checkout"),
          ),
          bottomNavigationBar: _bottomBar(blocked: multiShopBlocked),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 120),
              child: Column(
                children: [
                  if (multiShopBlocked)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.red.withOpacity(0.2)),
                      ),
                      child: const Text(
                        "Multiple shop items detected. একসাথে একাধিক shop থেকে checkout যাবে না।",
                        style: TextStyle(fontWeight: FontWeight.w900, color: Colors.red),
                      ),
                    ),

                  // Delivery card
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Delivery Details", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        const SizedBox(height: 10),

                        // saved address actions
                        if ((_saved["address"] ?? "").trim().isNotEmpty)
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  "Saved address found",
                                  style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w800),
                                ),
                              ),
                              TextButton(
                                onPressed: _useSavedAddress,
                                child: const Text("Use saved", style: TextStyle(fontWeight: FontWeight.w900)),
                              ),
                              TextButton(
                                onPressed: _clearSavedAddress,
                                child: const Text("Clear", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.red)),
                              ),
                            ],
                          ),

                        Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              _tf(
                                nameCtrl,
                                "Full Name",
                                autofill: const [AutofillHints.name],
                                textInputAction: TextInputAction.next,
                                validator: (v) => _validateName(v),
                              ),
                              _tf(
                                phoneCtrl,
                                "Phone",
                                keyboard: TextInputType.phone,
                                autofill: const [AutofillHints.telephoneNumber],
                                textInputAction: TextInputAction.next,
                                validator: (v) => _validatePhone(v),
                              ),
                              _tf(
                                addressCtrl,
                                "Address",
                                maxLines: 3,
                                autofill: const [AutofillHints.fullStreetAddress],
                                textInputAction: TextInputAction.next,
                                validator: (v) => _validateAddress(v),
                              ),
                              _tf(
                                pincodeCtrl,
                                "Pincode",
                                keyboard: TextInputType.number,
                                autofill: const [AutofillHints.postalCode],
                                textInputAction: TextInputAction.done,
                                validator: (v) => _validatePincode(v),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Payment will be selected on next page",
                          style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Coupon + pricing card
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Offers & Pricing", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        const SizedBox(height: 10),

                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: couponCtrl,
                                textCapitalization: TextCapitalization.characters,
                                decoration: InputDecoration(
                                  hintText: "Coupon code",
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            if (appliedCoupon.isEmpty)
                              ElevatedButton(
                                onPressed: couponApplying ? null : _applyCoupon,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepPurple,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                ),
                                child: couponApplying
                                    ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                                    : const Text("Apply", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                              )
                            else
                              TextButton(
                                onPressed: _removeCoupon,
                                child: const Text("Remove", style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900)),
                              ),
                          ],
                        ),

                        if (appliedCoupon.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            "Applied: $appliedCoupon",
                            style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.deepPurple),
                          ),
                        ],

                        const SizedBox(height: 12),
                        _priceRow("Subtotal", _subtotal),
                        _priceRow("Shipping", shippingFee),
                        _priceRow("Tax", taxAmount),
                        _priceRow("Discount", -discountAmount),
                        const Divider(height: 24),
                        _priceRow("Total", _grandTotal, bold: true),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Order summary card
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Order Summary", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        const SizedBox(height: 10),
                        ...widget.items.map((it) {
                          final name = _asString(it["name"], fallback: "Item");
                          final qty = _asInt(it["qty"], fallback: 1);
                          final price = _unitPrice(it);

                          final selColor = _asString(it["selected_color"]);
                          final selSize = _asString(it["selected_size"]);

                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                                      if (selColor.isNotEmpty || selSize.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(
                                            [
                                              if (selColor.isNotEmpty) "Color: $selColor",
                                              if (selSize.isNotEmpty) "Size: $selSize",
                                            ].join(" • "),
                                            style: TextStyle(
                                              color: Colors.grey.shade700,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text("x$qty", style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w900)),
                                const SizedBox(width: 10),
                                Text(
                                  "₹${(price * qty).toStringAsFixed(0)}",
                                  style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.deepPurple),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            "Payable: ₹${_grandTotal.toStringAsFixed(0)}",
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.deepPurple),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        if (placing)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.15),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.deepPurple),
              ),
            ),
          ),
      ],
    );
  }

  Widget _bottomBar({required bool blocked}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "Total: ₹${_grandTotal.toStringAsFixed(0)}",
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
          SizedBox(
            height: 50,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_g1, _g2]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
              ),
              child: ElevatedButton(
                onPressed: (placing || blocked) ? null : _onPlaceOrderPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: placing
                    ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
                    : Text(
                  blocked ? "FIX CART" : "CONTINUE",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceRow(String label, double amount, {bool bold = false}) {
    final v = amount;
    final isNeg = v < 0;
    final show = isNeg ? "-₹${(-v).toStringAsFixed(0)}" : "₹${v.toStringAsFixed(0)}";

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
                color: Colors.black87,
              ),
            ),
          ),
          Text(
            show,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
              color: isNeg ? Colors.green : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 2))],
      ),
      child: child,
    );
  }

  Widget _tf(
      TextEditingController c,
      String label, {
        int maxLines = 1,
        TextInputType keyboard = TextInputType.text,
        List<String> autofill = const [],
        TextInputAction textInputAction = TextInputAction.next,
        String? Function(String v)? validator,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboard,
        autofillHints: autofill.isEmpty ? null : autofill,
        textInputAction: textInputAction,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        validator: (v) => validator?.call((v ?? "").trim()),
      ),
    );
  }
}
