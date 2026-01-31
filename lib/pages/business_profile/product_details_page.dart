// lib/pages/business_profile/product_details_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:troonky_link/pages/checkout_page.dart';
import 'package:troonky_link/services/business_api.dart';
import 'package:troonky_link/services/product_api.dart';

import 'controllers/cart_controller.dart';

class ProductDetailsPage extends StatefulWidget {
  final Map<String, dynamic> product;

  /// ✅ optional: pass businessId to prevent missing business_id
  final int? businessId;

  const ProductDetailsPage({
    super.key,
    required this.product,
    this.businessId,
  });

  @override
  State<ProductDetailsPage> createState() => _ProductDetailsPageState();
}

class _ProductDetailsPageState extends State<ProductDetailsPage> {
  late Map<String, dynamic> _product;

  int _selectedImage = 0;
  int _qty = 1;

  String? _selectedColor;
  String? _selectedSize;

  bool _expandedDesc = false;
  bool _isWishlisted = false;

  final TextEditingController _pincodeCtrl = TextEditingController();
  String? _deliveryResult;
  bool _checkingPincode = false;

  Future<List<Map<String, dynamic>>>? _otherProductsFuture;

  bool _refreshing = false;
  late final PageController _heroPc;

  // ---------------- SAFE HELPERS ----------------
  double _asDouble(dynamic v, {double fallback = 0.0}) {
    if (v == null) return fallback;
    if (v is double) return v;
    if (v is int) return v.toDouble();
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

  String _asString(dynamic v, {String fallback = ""}) =>
      v == null ? fallback : v.toString();

  bool _asBool01(dynamic v, {bool fallback = false}) {
    if (v == null) return fallback;
    if (v is bool) return v;
    if (v is num) return v.toInt() == 1;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == "1" || s == "true" || s == "yes") return true;
      if (s == "0" || s == "false" || s == "no") return false;
    }
    return fallback;
  }

  // ✅ NEW: Accept List OR JSON-string list ("[]")
  List<String> _asStringListLoose(dynamic v) {
    if (v == null) return [];
    if (v is List) {
      return v
          .map((e) => (e ?? "").toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (v is String) {
      final raw = v.trim();
      if (raw.isEmpty) return [];
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .map((e) => (e ?? "").toString().trim())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      } catch (_) {}
    }
    return [];
  }

  // ✅ NEW: Accept Map OR JSON-string map ("{}")
  Map<String, String> _asStringMapLoose(dynamic v) {
    if (v == null) return {};
    if (v is Map) {
      final m = <String, String>{};
      v.forEach((k, val) {
        final ks = (k ?? "").toString().trim();
        final vs = (val ?? "").toString().trim();
        if (ks.isNotEmpty && vs.isNotEmpty) m[ks] = vs;
      });
      return m;
    }
    if (v is String) {
      final raw = v.trim();
      if (raw.isEmpty) return {};
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final m = <String, String>{};
          decoded.forEach((k, val) {
            final ks = (k ?? "").toString().trim();
            final vs = (val ?? "").toString().trim();
            if (ks.isNotEmpty && vs.isNotEmpty) m[ks] = vs;
          });
          return m;
        }
      } catch (_) {}
    }
    return {};
  }

  Color _withOpacity(Color c, double opacity) {
    final o = opacity.clamp(0.0, 1.0);
    return c.withAlpha((o * 255).round());
  }

  // ---------------- PRODUCT NORMALIZATION ----------------
  String _productIdStr(Map<String, dynamic> p) {
    final v = p["product_id"] ?? p["id"] ?? p["_id"] ?? p["productId"];
    return (v ?? "").toString().trim();
  }

  int _productIdInt(Map<String, dynamic> p) {
    final raw = (p["product_id"] ?? p["id"] ?? p["_id"] ?? p["productId"] ?? "")
        .toString()
        .trim();
    return int.tryParse(raw) ?? _asInt(p["id"], fallback: 0);
  }

  int _businessIdInt(Map<String, dynamic> p) {
    final raw = (p["business_id"] ??
        p["shop_id"] ??
        p["businessId"] ??
        p["shopId"] ??
        widget.businessId ??
        0)
        .toString()
        .trim();
    return int.tryParse(raw) ?? 0;
  }

  String _shopIdStr(Map<String, dynamic> p) {
    final v = p["shop_id"] ?? p["business_id"] ?? p["shopId"] ?? p["businessId"];
    return (v ?? "").toString().trim();
  }

  int _stockOf(Map<String, dynamic> p) {
    return _asInt(p["stock"] ?? p["quantity"] ?? p["qty_available"] ?? 0,
        fallback: 0);
  }

  bool _openBoxOf(Map<String, dynamic> p) {
    return _asBool01(p["open_box_delivery"], fallback: false);
  }

  bool _codOf(Map<String, dynamic> p) {
    return _asBool01(p["cod_available"], fallback: false);
  }

  bool _isOriginalOf(Map<String, dynamic> p) {
    // ✅ default true
    return _asBool01(p["is_original"], fallback: true);
  }

  int _returnDaysOf(Map<String, dynamic> p) {
    return _asInt(p["return_days"], fallback: 7);
  }

  List<String> _images(Map<String, dynamic> p) {
    final out = <String>[];

    // absolute urls list
    final urls = p["image_urls"];
    if (urls is List) {
      for (final u in urls) {
        final s = (u ?? "").toString().trim();
        if (s.isNotEmpty) out.add(s);
      }
    }

    // ✅ paths list (supports List or "[]")
    if (out.isEmpty) {
      final imgs = _asStringListLoose(p["images"]);
      if (imgs.isNotEmpty) {
        out.addAll(imgs.map((e) => BusinessAPI.toPublicUrl(e)));
      }
    }

    // single path
    if (out.isEmpty) {
      final one = _asString(p["image"] ?? p["image_url"] ?? "");
      if (one.trim().isNotEmpty) out.add(BusinessAPI.toPublicUrl(one.trim()));
    }

    return out.toSet().toList();
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

  int _discountPercent({required double price, required double mrp}) {
    if (mrp <= 0 || price <= 0) return 0;
    if (mrp <= price) return 0;
    return (((mrp - price) / mrp) * 100).round();
  }

  bool get _cartBuyDisabled {
    final stock = _stockOf(_product);
    final openBox = _openBoxOf(_product);
    return stock <= 0 || !openBox;
  }

  // ---------------- WISHLIST ----------------
  Future<void> _loadWishlist() async {
    final id = _productIdStr(_product);
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList("wishlist") ?? [];
    if (!mounted) return;
    setState(() => _isWishlisted = list.contains(id));
  }

  Future<void> _toggleWishlist() async {
    final id = _productIdStr(_product);
    if (id.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList("wishlist") ?? [];

    setState(() => _isWishlisted = !_isWishlisted);

    if (_isWishlisted) {
      if (!list.contains(id)) list.add(id);
    } else {
      list.remove(id);
    }
    await prefs.setStringList("wishlist", list);
  }

  // ---------------- SERVER REFRESH ----------------
  Future<void> _refreshProductFromServer() async {
    final pid = _productIdStr(_product);
    if (pid.isEmpty) return;

    setState(() => _refreshing = true);

    try {
      final fresh = await ProductAPI.getDetailById(pid);
      if (fresh.isEmpty) return;

      // preserve business/shop id if missing
      fresh["business_id"] ??= _product["business_id"] ?? widget.businessId;
      fresh["shop_id"] ??= _product["shop_id"] ?? widget.businessId;

      if (!mounted) return;
      setState(() {
        _product = fresh;

        _selectedImage = 0;
        _heroPc.jumpToPage(0);

        // ✅ use Loose parsers
        final colors = _asStringListLoose(_product["colors"]);
        final sizes = _asStringListLoose(_product["sizes"]);
        _selectedColor = colors.isNotEmpty ? colors.first : null;
        _selectedSize = sizes.isNotEmpty ? sizes.first : null;

        // qty safety after refresh
        final stock = _stockOf(_product);
        if (stock > 0 && _qty > stock) _qty = stock;
        if (stock <= 0) _qty = 1;

        _otherProductsFuture = _loadOtherBestOffers();
      });

      await _loadWishlist();
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  // ---------------- OTHER BEST OFFERS ----------------
  Future<List<Map<String, dynamic>>> _loadOtherBestOffers() async {
    final shopId = _shopIdStr(_product).trim();
    final myId = _productIdStr(_product);
    if (shopId.isEmpty) return [];

    final list = await ProductAPI.listByShop(shopId: shopId);

    final others = list.where((p) => _productIdStr(p) != myId).toList();

    others.sort((a, b) {
      final ap = _asDouble(a["price"]);
      final aop = _asDouble(a["offer_price"]);
      final amrpRaw = _asDouble(a["old_price"]);
      final aShow = (aop > 0) ? aop : ap;
      final aStrike = (aop > 0 && ap > 0) ? ap : (amrpRaw > 0 ? amrpRaw : 0.0);
      final aOff = _discountPercent(price: aShow, mrp: aStrike);

      final bp = _asDouble(b["price"]);
      final bop = _asDouble(b["offer_price"]);
      final bmrpRaw = _asDouble(b["old_price"]);
      final bShow = (bop > 0) ? bop : bp;
      final bStrike = (bop > 0 && bp > 0) ? bp : (bmrpRaw > 0 ? bmrpRaw : 0.0);
      final bOff = _discountPercent(price: bShow, mrp: bStrike);

      if (bOff != aOff) return bOff.compareTo(aOff);
      return aShow.compareTo(bShow);
    });

    final filtered = others.where((p) {
      final ap = _asDouble(p["price"]);
      final aop = _asDouble(p["offer_price"]);
      final amrp = _asDouble(p["old_price"]);
      final show = (aop > 0) ? aop : ap;
      final strike = (aop > 0 && ap > 0) ? ap : (amrp > 0 ? amrp : 0.0);
      final off = _discountPercent(price: show, mrp: strike);
      return aop > 0 || off > 0;
    }).toList();

    if (filtered.isEmpty) return others.take(5).toList();
    return filtered.take(5).toList();
  }

  // ---------------- DELIVERY CHECK ----------------
  bool _isValidPin(String pin) => RegExp(r'^\d{6}$').hasMatch(pin);

  Future<void> _checkDelivery() async {
    final pin = _pincodeCtrl.text.trim();

    if (!_isValidPin(pin)) {
      setState(() => _deliveryResult = "Invalid pincode. Enter 6 digits.");
      return;
    }

    setState(() {
      _checkingPincode = true;
      _deliveryResult = null;
    });

    try {
      final pid = _productIdStr(_product);
      if (pid.isEmpty) {
        setState(() => _deliveryResult = "Product ID missing ❌");
        return;
      }

      final res = await ProductAPI.checkDelivery(productId: pid, pincode: pin);

      final ok = res["available"] == true;
      final msg = (res["message"] ?? "").toString().trim();
      final eta = (res["eta"] ?? "").toString().trim();
      final charge = res["delivery_charge"];

      setState(() {
        if (ok) {
          final parts = <String>["✅ Available for pincode $pin"];
          if (eta.isNotEmpty) parts.add("ETA: $eta");
          if (charge != null) parts.add("Delivery: ₹$charge");
          _deliveryResult = parts.join(" • ");
        } else {
          _deliveryResult =
          msg.isNotEmpty ? "❌ $msg" : "❌ Not available for pincode $pin";
        }
      });
    } catch (_) {
      setState(() => _deliveryResult = "Network error. Please try again.");
    } finally {
      if (mounted) setState(() => _checkingPincode = false);
    }
  }

  // ---------------- CART ITEM (BACKEND READY) ----------------
  Map<String, dynamic> _buildCartItem() {
    final p = _product;

    final bid = _businessIdInt(p);
    final pidInt = _productIdInt(p);

    final basePrice = _asDouble(p["price"]);
    final offerPrice = _asDouble(p["offer_price"]);
    final unit = (offerPrice > 0) ? offerPrice : basePrice;

    final imgs = _images(p);
    final img = imgs.isNotEmpty ? imgs.first : "";

    return {
      "business_id": bid,
      "shop_id": bid,

      "product_id": pidInt, // ✅ backend expects int
      "name": _asString(p["name"]),
      "unit_price": unit,

      "price": basePrice,
      "offer_price": offerPrice,
      "old_price": _asDouble(p["old_price"] ?? p["mrp"], fallback: 0),

      "image": img,
      "image_url": img,

      "qty": _qty,
      "selected_color": _selectedColor ?? "",
      "selected_size": _selectedSize ?? "",

      "stock": _stockOf(p),
      "cod_available": _codOf(p),
      "open_box_delivery": _openBoxOf(p),

      "_id": _productIdStr(p),
      "id": pidInt,
    };
  }

  bool _validateBeforeBuyOrCart() {
    final bid = _businessIdInt(_product);
    if (bid <= 0) {
      _snack("Business ID missing ❌", error: true);
      return false;
    }

    final stock = _stockOf(_product);
    if (stock <= 0) {
      _snack("Out of stock ❌", error: true);
      return false;
    }

    // ✅ enforce open_box_delivery for BOTH actions
    if (!_openBoxOf(_product)) {
      _snack("This product is Buy Disabled (Open Box OFF) ❌", error: true);
      return false;
    }

    if (_qty > stock) {
      _snack("Only $stock item(s) available ❌", error: true);
      return false;
    }

    final pid = _productIdInt(_product);
    if (pid <= 0) {
      _snack("Product ID invalid ❌", error: true);
      return false;
    }

    return true;
  }

  // ---------------- LIFECYCLE ----------------
  @override
  void initState() {
    super.initState();

    _product = Map<String, dynamic>.from(widget.product);

    // ensure business_id exists from widget arg
    if ((_product["business_id"] == null ||
        _product["business_id"].toString().trim().isEmpty) &&
        (widget.businessId ?? 0) > 0) {
      _product["business_id"] = widget.businessId;
      _product["shop_id"] = widget.businessId;
    }

    _heroPc = PageController(initialPage: 0);

    // ✅ use Loose parsers
    final colors = _asStringListLoose(_product["colors"]);
    final sizes = _asStringListLoose(_product["sizes"]);
    if (colors.isNotEmpty) _selectedColor = colors.first;
    if (sizes.isNotEmpty) _selectedSize = sizes.first;

    // qty safety
    final stock = _stockOf(_product);
    if (stock > 0 && _qty > stock) _qty = stock;
    if (stock <= 0) _qty = 1;

    _loadWishlist();
    _otherProductsFuture = _loadOtherBestOffers();

    // refresh from backend
    _refreshProductFromServer();
  }

  @override
  void dispose() {
    _pincodeCtrl.dispose();
    _heroPc.dispose();
    super.dispose();
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final p = _product;

    final imgs = _images(p);
    final title = _asString(p["name"], fallback: "Product");

    final basePrice = _asDouble(p["price"]);
    final offerPrice = _asDouble(p["offer_price"]);
    final showPrice = (offerPrice > 0) ? offerPrice : basePrice;

    final mrpVal = _asDouble(p["old_price"]);
    final mrp = mrpVal > 0 ? mrpVal : null;
    final strike = (offerPrice > 0 && basePrice > 0) ? basePrice : mrp;

    final rating = _asDouble(p["rating"], fallback: 0.0);
    final reviews =
    _asInt(p["reviews"] ?? p["review_count"] ?? p["total_reviews"], fallback: 0);

    final discount = (strike != null && strike > showPrice && strike > 0)
        ? (((strike - showPrice) / strike) * 100).round()
        : 0;

    // ✅ use Loose parsers
    final colors = _asStringListLoose(p["colors"]);
    final sizes = _asStringListLoose(p["sizes"]);

    final returnDays = _returnDaysOf(p);
    final codAvailable = _codOf(p);
    final isOriginal = _isOriginalOf(p);
    final openBoxDelivery = _openBoxOf(p);

    final desc = _asString(p["description"], fallback: "No description available");
    final specs = _asStringMapLoose(p["specs"]);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.6,
        foregroundColor: Colors.black,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            tooltip: "Refresh",
            onPressed: _refreshProductFromServer,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: _toggleWishlist,
            icon: Icon(
              _isWishlisted ? Icons.favorite : Icons.favorite_border,
              color: _isWishlisted ? Colors.red : Colors.black87,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildHero(imgs, discount),
                  const SizedBox(height: 10),

                  // ✅ PRICE CARD
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "₹${showPrice.toStringAsFixed(0)}",
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: Colors.deepPurple,
                              ),
                            ),
                            if (strike != null && strike > showPrice) ...[
                              const SizedBox(width: 10),
                              Text(
                                "₹${strike.toStringAsFixed(0)}",
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                  decoration: TextDecoration.lineThrough,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                            if (discount > 0) ...[
                              const SizedBox(width: 10),
                              _pill(
                                text: "Save $discount%",
                                bg: _withOpacity(Colors.green, 0.12),
                                fg: Colors.green,
                                icon: Icons.local_offer_outlined,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),

                        // ✅ FIX: Wrap (no overflow)
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _ratingPill(rating: rating, reviews: reviews),
                            _pill(
                              text: "Assured",
                              bg: _withOpacity(Colors.deepPurple, 0.10),
                              fg: Colors.deepPurple,
                              icon: Icons.verified_outlined,
                            ),
                            _pill(
                              text: openBoxDelivery ? "Open Box" : "Open Box OFF",
                              bg: _withOpacity(
                                  openBoxDelivery ? Colors.green : Colors.red, 0.10),
                              fg: openBoxDelivery ? Colors.green : Colors.red,
                              icon: Icons.inventory_2_outlined,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),
                  if (colors.isNotEmpty || sizes.isNotEmpty)
                    _buildSelection(colors, sizes),
                  const SizedBox(height: 10),

                  _buildDeliveryTrust(
                    returnDays: returnDays,
                    codAvailable: codAvailable,
                    isOriginal: isOriginal,
                    openBoxDelivery: openBoxDelivery,
                  ),

                  const SizedBox(height: 10),
                  _buildOtherProductsRow(),
                  const SizedBox(height: 10),

                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Description",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        Text(
                          desc,
                          maxLines: _expandedDesc ? 100 : 3,
                          overflow:
                          _expandedDesc ? TextOverflow.visible : TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () =>
                                setState(() => _expandedDesc = !_expandedDesc),
                            child: Text(
                              _expandedDesc ? "Read Less" : "Read More",
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  if (specs.isNotEmpty)
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Key Specifications",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 10),
                          ...specs.entries.map(
                                (e) => Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                border:
                                Border(bottom: BorderSide(color: Colors.grey.shade200)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 4,
                                    child: Text(
                                      e.key,
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 6,
                                    child: Text(
                                      e.value,
                                      style: const TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                ],
                              ),
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

          // ✅ BOTH buttons disable here
          _bottomBar(unitPrice: showPrice),
        ],
      ),
    );
  }

  // ---------------- UI HELPERS ----------------
  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 2))
        ],
      ),
      child: child,
    );
  }

  Widget _pill({
    required String text,
    required Color bg,
    required Color fg,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: fg, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _ratingPill({required double rating, required int reviews}) {
    final show = rating > 0 ? rating.toStringAsFixed(1) : "0.0";
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _withOpacity(Colors.green, 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star, size: 16, color: Colors.green),
          const SizedBox(width: 6),
          Text(
            "$show  •  ${reviews > 0 ? '$reviews reviews' : 'No reviews'}",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.green),
          ),
        ],
      ),
    );
  }

  // ---------------- OTHER PRODUCTS ----------------
  Widget _buildOtherProductsRow() {
    final shopId = _shopIdStr(_product).trim();
    if (shopId.isEmpty) return const SizedBox.shrink();

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  "Other Products • Best Offers",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                "Top 5",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _withOpacity(Colors.deepPurple, 0.90),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _otherProductsFuture,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return SizedBox(
                  height: 120.0,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      color: _withOpacity(Colors.deepPurple, 0.90),
                    ),
                  ),
                );
              }

              final items = snap.data ?? [];
              if (items.isEmpty) {
                return Text(
                  "No other offers found right now.",
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                );
              }

              return SizedBox(
                height: 150.0,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) {
                    final pp = items[i];
                    final title = _asString(pp["name"], fallback: "Product");

                    final base = _asDouble(pp["price"]);
                    final op = _asDouble(pp["offer_price"]);
                    final show = (op > 0) ? op : base;

                    final mrpRaw = _asDouble(pp["old_price"]);
                    final strike =
                    (op > 0 && base > 0) ? base : (mrpRaw > 0 ? mrpRaw : 0.0);
                    final off = _discountPercent(price: show, mrp: strike);

                    final imgs = _images(pp);
                    final img = imgs.isNotEmpty ? imgs.first : "";

                    final nextBid = _businessIdInt(pp);

                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProductDetailsPage(
                              product: pp,
                              businessId: nextBid > 0 ? nextBid : widget.businessId,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        width: 120,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(16)),
                                    child: SizedBox.expand(
                                      child: img.isNotEmpty
                                          ? Image.network(
                                        img,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            Container(
                                              color: Colors.grey.shade200,
                                              child: const Center(
                                                child: Icon(Icons.broken_image,
                                                    color: Colors.grey),
                                              ),
                                            ),
                                      )
                                          : Container(
                                        color: Colors.grey.shade200,
                                        child: const Center(
                                          child: Icon(Icons.image_not_supported,
                                              color: Colors.grey),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (off > 0)
                                    Positioned(
                                      top: 8,
                                      left: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: _withOpacity(Colors.green, 0.92),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          "$off% OFF",
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                              child: Row(
                                children: [
                                  Text(
                                    "₹${show.toStringAsFixed(0)}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: Colors.deepPurple,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  if (strike > 0 && strike > show)
                                    Text(
                                      "₹${strike.toStringAsFixed(0)}",
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                        decoration: TextDecoration.lineThrough,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------------- HERO ----------------
  Widget _buildHero(List<String> imgs, int discount) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          SizedBox(
            height: 320.0,
            child: Stack(
              children: [
                if (imgs.isEmpty)
                  const Center(
                    child: Icon(Icons.image_not_supported,
                        size: 90, color: Colors.grey),
                  )
                else
                  PageView.builder(
                    controller: _heroPc,
                    itemCount: imgs.length,
                    onPageChanged: (i) => setState(() => _selectedImage = i),
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => _openZoomViewer(imgs, i),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Image.network(
                          imgs[i],
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image,
                                size: 90, color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _withOpacity(Colors.black, 0.06),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text("Tap to Zoom",
                        style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
                if (discount > 0)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        "$discount% OFF",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                if (imgs.length > 1)
                  Positioned(
                    bottom: 10,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        imgs.length,
                            (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _selectedImage == i ? 14.0 : 8.0,
                          height: 8.0,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: _selectedImage == i
                                ? Colors.deepPurple
                                : Colors.grey.shade400,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (imgs.length > 1)
            SizedBox(
              height: 74.0,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: imgs.length,
                itemBuilder: (_, i) {
                  final selected = _selectedImage == i;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedImage = i);
                      _heroPc.animateToPage(
                        i,
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOut,
                      );
                    },
                    child: Container(
                      width: 64,
                      margin: const EdgeInsets.only(right: 10, bottom: 10),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected ? Colors.deepPurple : Colors.grey.shade200,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Image.network(
                        imgs[i],
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                        const Icon(Icons.image, color: Colors.grey),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  void _openZoomViewer(List<String> imgs, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ZoomViewer(images: imgs, initialIndex: initialIndex),
      ),
    );
  }

  // ---------------- SELECTION ----------------
  Widget _buildSelection(List<String> colors, List<String> sizes) {
    final stock = _stockOf(_product);
    final canMinus = _qty > 1;
    final canPlus = (stock <= 0) ? true : _qty < stock;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Selection",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          if (colors.isNotEmpty) ...[
            const Text("Color", style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: colors.map((c) {
                final selected = _selectedColor == c;
                return ChoiceChip(
                  label: Text(c),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedColor = c),
                  selectedColor: Colors.deepPurple,
                  labelStyle: TextStyle(color: selected ? Colors.white : Colors.black),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
          if (sizes.isNotEmpty) ...[
            Row(
              children: [
                const Expanded(
                    child: Text("Size",
                        style: TextStyle(fontWeight: FontWeight.w900))),
                TextButton(
                  onPressed: _showSizeChart,
                  child: const Text("Size Chart",
                      style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ],
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: sizes.map((s) {
                final selected = _selectedSize == s;
                return ChoiceChip(
                  label: Text(s),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedSize = s),
                  selectedColor: Colors.deepPurple,
                  labelStyle: TextStyle(color: selected ? Colors.white : Colors.black),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
          const Text("Quantity", style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton(
                onPressed: canMinus ? () => setState(() => _qty--) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12)),
                child: Text("$_qty",
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
              IconButton(
                onPressed: canPlus
                    ? () {
                  setState(() {
                    _qty++;
                    if (stock > 0 && _qty > stock) _qty = stock;
                  });
                }
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
              if (stock > 0) ...[
                const SizedBox(width: 10),
                Text("Stock: $stock",
                    style: TextStyle(
                        color: Colors.grey.shade700, fontWeight: FontWeight.w800)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showSizeChart() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Size Chart",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              SizedBox(height: 10),
              Text("S = 36-38\nM = 38-40\nL = 40-42\nXL = 42-44",
                  style: TextStyle(height: 1.6)),
              SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  // ---------------- DELIVERY TRUST ----------------
  Widget _buildDeliveryTrust({
    required int returnDays,
    required bool codAvailable,
    required bool isOriginal,
    required bool openBoxDelivery,
  }) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Delivery & Trust",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pincodeCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: "Enter pincode",
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _checkingPincode ? null : _checkDelivery,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                child: _checkingPincode
                    ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                    : const Text("Check",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          if (_deliveryResult != null) ...[
            const SizedBox(height: 10),
            Text(
              _deliveryResult!,
              style: TextStyle(
                color: _deliveryResult!.startsWith("✅")
                    ? Colors.green.shade700
                    : Colors.red,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _badge("$returnDays Days Return", Icons.assignment_return),
              if (codAvailable) _badge("Cash on Delivery", Icons.payments_outlined),
              if (openBoxDelivery)
                _badge("Open Box Delivery", Icons.inventory_2_outlined)
              else
                _badge("Open Box OFF", Icons.block_outlined),
              if (isOriginal) _badge("100% Original", Icons.verified_outlined),
              _badge("Secure Payments", Icons.lock_outline),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(String t, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.deepPurple),
          const SizedBox(width: 8),
          Text(t, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  // ---------------- BOTTOM BAR ----------------
  Widget _bottomBar({required double unitPrice}) {
    final total = unitPrice * _qty;

    final stock = _stockOf(_product);
    final openBox = _openBoxOf(_product);
    final disabledAll = stock <= 0 || !openBox;

    final String buyText = (stock <= 0)
        ? "OUT OF STOCK"
        : (!openBox ? "BUY DISABLED" : "BUY • ₹${total.toStringAsFixed(0)}");

    final String cartText = (stock <= 0)
        ? "OUT OF STOCK"
        : (!openBox ? "ADD DISABLED" : "ADD TO CART");

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: disabledAll
                  ? null
                  : () {
                if (!_validateBeforeBuyOrCart()) return;
                final item = _buildCartItem();
                Provider.of<CartController>(context, listen: false)
                    .addToCart(item);
                _snack("Added to cart ✅");
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: disabledAll ? Colors.grey : Colors.deepPurple,
                  width: 1.6,
                ),
                foregroundColor: disabledAll ? Colors.grey : Colors.deepPurple,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                cartText,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: disabledAll
                  ? null
                  : () {
                if (!_validateBeforeBuyOrCart()) return;
                final item = _buildCartItem();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CheckoutPage(items: [item]),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: disabledAll ? Colors.grey : Colors.deepPurple,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                buyText,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- FULL SCREEN ZOOM VIEWER ----------------
class _ZoomViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  const _ZoomViewer({required this.images, required this.initialIndex});

  @override
  State<_ZoomViewer> createState() => _ZoomViewerState();
}

class _ZoomViewerState extends State<_ZoomViewer> {
  late final PageController _pc = PageController(initialPage: widget.initialIndex);
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    _idx = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text("${_idx + 1}/${widget.images.length}"),
      ),
      body: PageView.builder(
        controller: _pc,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _idx = i),
        itemBuilder: (_, i) {
          return InteractiveViewer(
            minScale: 1.0,
            maxScale: 4.0,
            child: Center(
              child: Image.network(
                widget.images[i],
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image, size: 90, color: Colors.white70),
              ),
            ),
          );
        },
      ),
    );
  }
}
