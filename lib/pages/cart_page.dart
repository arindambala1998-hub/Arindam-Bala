// lib/pages/cart_page.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'checkout_page.dart';
import 'business_profile/controllers/cart_controller.dart';
import 'cart_details_page.dart';
import 'package:troonky_link/services/order_api.dart';

// =============================================================
// ✅ GLOBAL MEDIA URL NORMALIZER (IMAGE FIX)
// =============================================================
const String _mediaHost = "https://adminapi.troonky.in";

String _normalizeMediaUrl(String raw) {
  final s0 = raw.trim();
  if (s0.isEmpty) return "";

  // windows/backslash path fix
  final s = s0.replaceAll("\\", "/");

  if (s.startsWith("http://") || s.startsWith("https://")) return s;
  if (s.startsWith("//")) return "https:$s";

  // only filename
  if (!s.contains("/")) return "$_mediaHost/uploads/$s";

  final path = s.startsWith("/") ? s : "/$s";
  return "$_mediaHost$path";
}

Map<String, dynamic> _safeMapAny(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return <String, dynamic>{};
}

List _safeListAny(dynamic v) => (v is List) ? v : const [];

// ✅ pick helpers (service/product images all cases)
String _pickFirstNonEmpty(List<dynamic> vals) {
  for (final v in vals) {
    final s = (v ?? "").toString().trim();
    if (s.isNotEmpty) return s;
  }
  return "";
}

String _pickImageFromMap(Map<String, dynamic> m) {
  final direct = _pickFirstNonEmpty([
    m["image"],
    m["image_url"],
    m["imageUrl"],
    m["thumbnail"],
    m["thumb"],
    m["photo"],
    m["cover"],
    m["icon"],
  ]);
  if (direct.isNotEmpty) return direct;

  final imgs = m["images"];
  if (imgs is List && imgs.isNotEmpty) {
    final first = (imgs.first ?? "").toString().trim();
    if (first.isNotEmpty) return first;
  }
  return "";
}

Map<String, dynamic> _normalizeOrderImagesLite(Map<String, dynamic> o) {
  final out = Map<String, dynamic>.from(o);

  // normalize top-level image
  final topImg = (out["image"] ?? out["image_url"] ?? out["imageUrl"] ?? "").toString();
  if (topImg.trim().isNotEmpty) out["image"] = _normalizeMediaUrl(topImg);

  // ✅ service can come in many keys
  final svcRaw = out["service"] ??
      out["service_details"] ??
      out["serviceDetail"] ??
      out["service_data"] ??
      out["serviceData"];

  final svc = _safeMapAny(svcRaw);
  if (svc.isNotEmpty) {
    final svcImgRaw = _pickImageFromMap(svc);
    if (svcImgRaw.trim().isNotEmpty) {
      final svc2 = Map<String, dynamic>.from(svc);
      svc2["image"] = _normalizeMediaUrl(svcImgRaw);
      out["service"] = svc2;

      // top-level fallbacks for UI
      out["service_image"] = out["service_image"] ?? out["serviceImage"] ?? svc2["image"];
      if ((out["image"] ?? "").toString().trim().isEmpty) out["image"] = svc2["image"];
    }
  }

  // normalize items images (product order)
  final items = out["items"] ??
      out["order_items"] ??
      out["products"] ??
      out["cart_items"] ??
      out["orderItems"] ??
      out["orderItemsList"];

  if (items is List) {
    out["items"] = items.map((it) {
      final m = _safeMapAny(it);

      final product = _safeMapAny(m["product"]);
      final pImg = (product["image"] ?? product["image_url"] ?? product["imageUrl"] ?? "").toString();

      final imgRaw = (m["image"] ?? m["image_url"] ?? m["imageUrl"] ?? (pImg.isNotEmpty ? pImg : "")).toString();

      final mm = Map<String, dynamic>.from(m);
      if (imgRaw.trim().isNotEmpty) mm["image"] = _normalizeMediaUrl(imgRaw);

      // product.images list normalize (optional)
      if (product.isNotEmpty) {
        final imgs = _safeListAny(product["images"]);
        if (imgs.isNotEmpty) {
          final first = (imgs.first ?? "").toString();
          if (first.trim().isNotEmpty) {
            final p2 = Map<String, dynamic>.from(product);
            p2["images"] = imgs.map((e) => _normalizeMediaUrl((e ?? "").toString())).toList();
            p2["image"] = _normalizeMediaUrl(first);
            mm["product"] = p2;
          }
        } else if (pImg.trim().isNotEmpty) {
          final p2 = Map<String, dynamic>.from(product);
          p2["image"] = _normalizeMediaUrl(pImg);
          mm["product"] = p2;
        }
      }

      return mm;
    }).toList();
  }

  // normalize service_image keys
  final sImgRaw = _pickFirstNonEmpty([
    out["service_image"],
    out["serviceImage"],
    out["service_image_url"],
    out["serviceImageUrl"],
  ]);
  if (sImgRaw.trim().isNotEmpty) out["service_image"] = _normalizeMediaUrl(sImgRaw);

  return out;
}

// =============================================================
// ✅ PAGE
// =============================================================
class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  static const String _baseUrl = "https://adminapi.troonky.in/api";

  // =============================
  // Prefs / Auth helpers
  // =============================
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

  int _asInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  // ✅ FIX: prefs.getInt can crash if value stored as String.
  Future<int?> _prefsIntAny(List<String> keys) async {
    final prefs = await SharedPreferences.getInstance();

    for (final k in keys) {
      try {
        final v = prefs.getInt(k);
        if (v != null && v > 0) return v;
      } catch (_) {}
    }

    for (final k in keys) {
      final s = prefs.getString(k);
      final n = int.tryParse((s ?? "").trim());
      if (n != null && n > 0) return n;
    }

    for (final k in keys) {
      final v = prefs.get(k);
      if (v is int && v > 0) return v;
      if (v is double && v > 0) return v.toInt();
      if (v is String) {
        final n = int.tryParse(v.trim());
        if (n != null && n > 0) return n;
      }
    }

    return null;
  }

  Future<String> _getUserType() async {
    final prefs = await SharedPreferences.getInstance();
    final v = (prefs.getString("userType") ??
        prefs.getString("user_type") ??
        prefs.getString("role") ??
        "user")
        .trim()
        .toLowerCase();
    return v.isEmpty ? "user" : v;
  }

  Future<int?> _getUserIdSafe() async {
    return _prefsIntAny(const [
      "userId",
      "user_id",
      "id",
      "uid",
      "customer_id",
      "customerId",
    ]);
  }

  Future<int?> _getBusinessIdSafe() async {
    return _prefsIntAny(const [
      "businessId",
      "business_id",
      "shopId",
      "shop_id",
      "defaultShopId",
      "default_shop_id",
    ]);
  }

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

  // ✅ Better extraction support (orders + bookings)
  List<Map<String, dynamic>> _extractOrdersFromBackend(dynamic body) {
    if (body == null) return [];

    if (body is List) {
      return body.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }

    if (body is Map) {
      final m = Map<String, dynamic>.from(body);

      dynamic node = m["orders"] ??
          m["order"] ??
          m["data"] ??
          m["rows"] ??
          m["result"] ??
          m["bookings"] ??
          m["booking"] ??
          m["service_bookings"] ??
          m["serviceBookings"] ??
          m["items"];

      if (node is Map) {
        final mm = Map<String, dynamic>.from(node);
        node = mm["orders"] ??
            mm["order"] ??
            mm["data"] ??
            mm["rows"] ??
            mm["result"] ??
            mm["bookings"] ??
            mm["booking"] ??
            mm["service_bookings"] ??
            mm["serviceBookings"] ??
            mm["items"] ??
            mm;
      }

      if (node is List) {
        return node.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      if (node is Map) return [Map<String, dynamic>.from(node)];

      if (m.containsKey("id") || m.containsKey("order_id") || m.containsKey("booking_id")) {
        return [m];
      }
    }

    return [];
  }

  bool _looksService(Map<String, dynamic> m) {
    final t = (m["type"] ?? m["order_type"] ?? m["mode"] ?? "").toString().toLowerCase();
    if (t.contains("service") || t.contains("booking")) return true;
    if (m.containsKey("booking_id") || m.containsKey("booking_number")) return true;
    if (m.containsKey("service_id") || m.containsKey("serviceId")) return true;
    return false;
  }

  // =============================================================
  // ✅ FIX: Product detection relaxed (your API may return only id+items)
  // =============================================================
  bool _looksProduct(Map<String, dynamic> m) {
    // service হলে product না
    if (_looksService(m)) return false;

    final t = (m["type"] ?? m["order_type"] ?? m["mode"] ?? "").toString().toLowerCase();
    if (t.contains("product") || t.contains("order")) return true;

    // common keys
    if (m.containsKey("order_id")) return true;
    if (m.containsKey("order_code") || m.containsKey("orderCode")) return true;

    // ✅ items present => almost surely product order
    final items = m["items"] ?? m["order_items"] ?? m["products"] ?? m["cart_items"];
    if (items is List && items.isNotEmpty) return true;

    // fallback: non-service => treat as product
    return true;
  }

  // ✅ Try multiple endpoints (do not stop on net errors)
  Future<List<Map<String, dynamic>>> _tryGetMany(
      List<String> urls, {
        required Map<String, String> headers,
        required String typeTag, // "product" | "service"
      }) async {
    bool saw200ButEmpty = false;
    Map<String, dynamic>? lastError;

    for (final url in urls) {
      try {
        final res = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 25));

        if (kDebugMode) debugPrint("🟦 ORDERS[$typeTag] GET $url -> ${res.statusCode}");

        if (res.statusCode == 401 || res.statusCode == 403) {
          return [
            {"_error": "AUTH", "message": "Please login again (token expired/invalid)."}
          ];
        }

        if (res.statusCode == 404) continue;

        final decoded = _safeJson(res.body);

        if (res.statusCode >= 200 && res.statusCode < 300) {
          if (kDebugMode) debugPrint("✅ ORDERS[$typeTag] BODY: ${res.body}");

          final list0 = _extractOrdersFromBackend(decoded);

          // ✅ ensure type exists BEFORE filtering (important)
          final list = list0.where((e) {
            final m = Map<String, dynamic>.from(e);
            m["type"] = (m["type"] ?? m["order_type"] ?? typeTag);

            if (typeTag == "service") return _looksService(m);
            // ✅ product tab: accept anything that's NOT service
            if (typeTag == "product") return !_looksService(m);

            return true;
          }).toList();

          if (list.isEmpty) {
            saw200ButEmpty = true;
            continue;
          }

          return list.map((e) {
            final m = Map<String, dynamic>.from(e);
            m["type"] = (m["type"] ?? m["order_type"] ?? typeTag);

            // ✅ id fallback more robust (order_code also)
            m["id"] = m["id"] ?? m["order_id"] ?? m["booking_id"] ?? m["_id"] ?? m["order_code"] ?? m["orderCode"];

            return _normalizeOrderImagesLite(m);
          }).toList();
        }

        final msg = (decoded["message"]?.toString().trim().isNotEmpty == true)
            ? decoded["message"].toString()
            : "Orders fetch failed (HTTP ${res.statusCode})";

        lastError = {"_error": "HTTP", "message": msg, "status": res.statusCode};
      } catch (e) {
        if (kDebugMode) debugPrint("❌ ORDERS[$typeTag] net error $url -> $e");
        lastError = {"_error": "NET", "message": "Network/Timeout error. Please try again.", "detail": e.toString()};
      }
    }

    if (saw200ButEmpty) return [];
    if (lastError != null) return [lastError!];

    return [
      {"_error": "NO_ROUTE", "message": "Orders API route পাওয়া যাচ্ছে না। Backend এ endpoint confirm করতে হবে।"}
    ];
  }

  // ==========================================================
  // ✅ FINAL: Orders fetch (User => userId, Business => businessId)
  // ==========================================================
  Future<List<Map<String, dynamic>>> _fetchOrdersByType(String type) async {
    final token = await _getToken();
    if (token == null || token.trim().isEmpty) {
      return [
        {"_error": "AUTH", "message": "Please login again (token missing)."}
      ];
    }

    final userType = await _getUserType();
    final userId = await _getUserIdSafe();
    final businessId = await _getBusinessIdSafe();

    final headers = <String, String>{
      "Content-Type": "application/json",
      "Accept": "application/json",
      "Authorization": "Bearer $token",
    };

    final isBusiness = userType.contains("business") || userType.contains("seller") || userType.contains("shop");

    if (kDebugMode) {
      debugPrint("🟪 CartOrders mode: userType=$userType isBusiness=$isBusiness userId=$userId businessId=$businessId type=$type");
    }

    final urls = <String>[];

    if (isBusiness) {
      if (businessId == null || businessId <= 0) {
        return [
          {"_error": "NO_BUSINESS_ID", "message": "Business ID (shopId/businessId) পাওয়া যায়নি।"}
        ];
      }

      urls.add("$_baseUrl/orders?business_id=$businessId&type=$type&include_items=1");
      urls.add("$_baseUrl/orders?shop_id=$businessId&type=$type&include_items=1");
      urls.add("$_baseUrl/orders/business/$businessId?type=$type&include_items=1");
      urls.add("$_baseUrl/orders/$businessId?type=$type&include_items=1");

      if (type == "service") {
        urls.add("$_baseUrl/bookings?business_id=$businessId");
        urls.add("$_baseUrl/bookings?shop_id=$businessId");
        urls.add("$_baseUrl/bookings/business/$businessId");
        urls.add("$_baseUrl/bookings/$businessId");
        urls.add("$_baseUrl/service-bookings?business_id=$businessId");
        urls.add("$_baseUrl/service-bookings/business/$businessId");
        urls.add("$_baseUrl/service-bookings/$businessId");
      }

      return _tryGetMany(urls, headers: headers, typeTag: type);
    }

    if (userId == null || userId <= 0) {
      return [
        {"_error": "NO_USER_ID", "message": "User ID পাওয়া যায়নি। Logout করে আবার login দাও।"}
      ];
    }

    urls.add("$_baseUrl/orders/my?type=$type&include_items=1");
    urls.add("$_baseUrl/orders?user_id=$userId&type=$type&include_items=1");
    urls.add("$_baseUrl/orders/user/$userId?type=$type&include_items=1");
    urls.add("$_baseUrl/orders/$userId?type=$type&include_items=1");

    if (type == "service") {
      urls.add("$_baseUrl/bookings/my");
      urls.add("$_baseUrl/bookings?user_id=$userId");
      urls.add("$_baseUrl/bookings/user/$userId");
      urls.add("$_baseUrl/service-bookings/my");
      urls.add("$_baseUrl/service-bookings?user_id=$userId");
      urls.add("$_baseUrl/service-bookings/user/$userId");
    }

    return _tryGetMany(urls, headers: headers, typeTag: type);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0.4,
          title: const Text(
            "Cart & Orders",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800),
          ),
          iconTheme: const IconThemeData(color: Colors.black),
          bottom: const TabBar(
            labelColor: Colors.deepPurple,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.deepPurple,
            tabs: [
              Tab(text: "Cart"),
              Tab(text: "Product"),
              Tab(text: "Service"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const _CartTabFinal(), // ✅ polished
            _OrdersTabFinal(
              title: "Product Orders",
              typeTag: "product",
              fetcher: () => _fetchOrdersByType("product"),
              // ✅ use centralized API
              canceler: OrdersAPI.cancelUnified,
            ),
            _OrdersTabFinal(
              title: "Service Orders",
              typeTag: "service",
              fetcher: () => _fetchOrdersByType("service"),
              canceler: OrdersAPI.cancelUnified,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// ✅ CART TAB — FINAL (Shop group + Clear + safety)
// =============================================================
class _CartTabFinal extends StatelessWidget {
  const _CartTabFinal();

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

  bool _asBool(dynamic v, {bool fallback = false}) {
    if (v == null) return fallback;
    if (v is bool) return v;
    if (v is num) return v.toInt() == 1;
    final s = v.toString().trim().toLowerCase();
    if (s == "1" || s == "true" || s == "yes") return true;
    if (s == "0" || s == "false" || s == "no") return false;
    return fallback;
  }

  void _snack(BuildContext context, String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.deepPurple,
      ),
    );
  }

  String _imgOf(Map<String, dynamic> it) {
    final img = (it["image"] ?? it["image_url"] ?? it["imageUrl"] ?? "").toString();
    if (img.trim().isNotEmpty) return _normalizeMediaUrl(img);

    final imgs = it["images"];
    if (imgs is List && imgs.isNotEmpty) {
      final first = (imgs.first ?? "").toString();
      if (first.trim().isNotEmpty) return _normalizeMediaUrl(first);
    }
    return "";
  }

  double _unitPrice(Map<String, dynamic> it) {
    final unit = _asDouble(it["unit_price"], fallback: 0);
    if (unit > 0) return unit;
    final offer = _asDouble(it["offer_price"], fallback: 0);
    final base = _asDouble(it["price"], fallback: 0);
    return offer > 0 ? offer : base;
  }

  int _businessId(Map<String, dynamic> it) {
    return _asInt(it["business_id"] ?? it["shop_id"] ?? it["businessId"] ?? it["shopId"], fallback: 0);
  }

  String _shopName(Map<String, dynamic> it) {
    final name = (it["business_name"] ?? it["shop_name"] ?? it["store_name"] ?? "").toString().trim();
    final bid = _businessId(it);
    return name.isNotEmpty ? name : (bid > 0 ? "Shop #$bid" : "Shop");
  }

  Map<int, List<Map<String, dynamic>>> _groupByShop(List<Map<String, dynamic>> items) {
    final m = <int, List<Map<String, dynamic>>>{};
    for (final it in items) {
      final bid = _businessId(it);
      m.putIfAbsent(bid, () => []);
      m[bid]!.add(it);
    }
    return m;
  }

  List<Map<String, dynamic>> _normalizeForCheckout(BuildContext context, List items) {
    final out = <Map<String, dynamic>>[];

    for (final raw in items) {
      final it = Map<String, dynamic>.from(raw as Map);

      final businessId = _businessId(it);
      if (businessId <= 0) {
        _snack(context, "Business ID missing: ${_asString(it["name"])}", error: true);
        return [];
      }

      final pidRaw = it["product_id"] ?? it["id"] ?? it["_id"] ?? it["productId"];
      final productId = _asInt(pidRaw, fallback: 0);
      if (productId <= 0) {
        _snack(context, "Product ID invalid: ${_asString(it["name"])}", error: true);
        return [];
      }

      final qty = _asInt(it["qty"], fallback: 1);
      final openBox = _asBool(it["open_box_delivery"], fallback: true);

      // ✅ hard safety: checkout blocked if open-box OFF
      if (!openBox) {
        _snack(context, "Blocked item (Open-box OFF): ${_asString(it["name"])}", error: true);
        return [];
      }

      out.add({
        ...it,
        "business_id": businessId,
        "shop_id": businessId,
        "product_id": productId,
        "id": productId,
        "unit_price": _unitPrice(it),
        "qty": qty <= 0 ? 1 : qty,
        "selected_color": _asString(it["selected_color"]),
        "selected_size": _asString(it["selected_size"]),
      });
    }

    // ✅ single-shop checkout enforce
    final firstBid = _businessId(out.first);
    final multi = out.any((e) => _businessId(e) != firstBid);
    if (multi) {
      _snack(context, "একসাথে একাধিক Shop থেকে checkout করা যাবে না। আগে এক Shop রাখো।", error: true);
      return [];
    }

    return out;
  }

  Future<void> _confirmClearCart(BuildContext context, CartController cartCtrl) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Clear cart?"),
        content: const Text("সব item remove হয়ে যাবে।"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Clear", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await cartCtrl.clearCart();
      if (context.mounted) _snack(context, "Cart cleared");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CartController>(
      builder: (_, cartCtrl, __) {
        final items = cartCtrl.cart;

        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_cart_outlined, size: 86, color: Colors.grey.shade300),
                  const SizedBox(height: 10),
                  const Text("Your cart is empty", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text("Products add করলে এখানে দেখাবে।", style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          );
        }

        // totals
        double total = 0;
        int totalQty = 0;
        for (final raw in items) {
          final it = Map<String, dynamic>.from(raw as Map);
          final qty = _asInt(it["qty"], fallback: 1);
          final q = qty <= 0 ? 1 : qty;
          totalQty += q;
          total += q * _unitPrice(it);
        }

        final groups = _groupByShop(items.cast<Map<String, dynamic>>());

        return Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.deepPurple.withOpacity(0.12)),
                  ),
                  child: const Text(
                    "Note: Open-box delivery OFF থাকলে item cart/checkout ব্লক হবে।",
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(height: 10),

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _confirmClearCart(context, cartCtrl),
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text("Clear cart", style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(height: 6),

                for (final entry in groups.entries) ...[
                  Row(
                    children: [
                      const Icon(Icons.storefront, color: Colors.deepPurple),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_shopName(entry.value.first), style: const TextStyle(fontWeight: FontWeight.w900))),
                    ],
                  ),
                  const SizedBox(height: 10),

                  for (final it in entry.value) ...[
                    _CartItemCardFinal(
                      it: it,
                      img: _imgOf(it),
                      name: _asString(it["name"], fallback: "Item"),
                      unitPrice: _unitPrice(it),
                      qty: _asInt(it["qty"], fallback: 1),
                      openBoxOk: _asBool(it["open_box_delivery"], fallback: true),
                      stock: _asInt(it["stock"], fallback: -1),
                      color: _asString(it["selected_color"]),
                      size: _asString(it["selected_size"]),
                      onMinus: () {
                        final idx = items.indexOf(it);
                        if (idx >= 0) cartCtrl.updateQuantity(idx, false);
                      },
                      onPlus: () {
                        final idx = items.indexOf(it);
                        if (idx >= 0) {
                          final ok = cartCtrl.updateQuantity(idx, true);
                          if (!ok) _snack(context, "Blocked (Open-box OFF)", error: true);
                        }
                      },
                      onRemove: () {
                        final idx = items.indexOf(it);
                        if (idx >= 0) cartCtrl.removeItem(idx);
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
              ],
            ),

            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Items: $totalQty", style: const TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 4),
                          Text("Total: ₹${total.toStringAsFixed(0)}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final cartItems = _normalizeForCheckout(context, items);
                        if (cartItems.isEmpty) return;

                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => CheckoutPage(items: cartItems)),
                        );

                        if (result is Map && result["ok"] == true && context.mounted) {
                          _snack(context, "Order placed ✅");
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("CHECKOUT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CartItemCardFinal extends StatelessWidget {
  final Map<String, dynamic> it;
  final String img;
  final String name;
  final double unitPrice;
  final int qty;
  final bool openBoxOk;
  final int stock;
  final String color;
  final String size;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onRemove;

  const _CartItemCardFinal({
    required this.it,
    required this.img,
    required this.name,
    required this.unitPrice,
    required this.qty,
    required this.openBoxOk,
    required this.stock,
    required this.color,
    required this.size,
    required this.onMinus,
    required this.onPlus,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final q = qty <= 0 ? 1 : qty;
    final total = q * (unitPrice <= 0 ? 0 : unitPrice);
    final blocked = !openBoxOk;

    return Opacity(
      opacity: blocked ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: blocked ? Colors.red.withOpacity(0.25) : Colors.grey.shade200),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 62,
                width: 62,
                color: Colors.grey.shade200,
                child: img.isNotEmpty
                    ? Image.network(
                  img,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey),
                )
                    : const Icon(Icons.image_not_supported, color: Colors.grey),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text("₹${unitPrice.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.deepPurple)),
                  const SizedBox(height: 6),

                  if (color.trim().isNotEmpty || size.trim().isNotEmpty)
                    Text(
                      [
                        if (color.trim().isNotEmpty) "Color: $color",
                        if (size.trim().isNotEmpty) "Size: $size",
                      ].join(" • "),
                      style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700, fontSize: 12),
                    ),

                  if (stock == 0) ...[
                    const SizedBox(height: 6),
                    const Text("Out of stock", style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900)),
                  ] else if (stock > 0) ...[
                    const SizedBox(height: 6),
                    Text("Stock: $stock", style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700, fontSize: 12)),
                  ],

                  if (blocked) ...[
                    const SizedBox(height: 6),
                    const Text("Blocked: Open-box delivery OFF", style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900)),
                  ],

                  const SizedBox(height: 10),
                  Row(
                    children: [
                      IconButton(
                        onPressed: onMinus,
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.deepPurple),
                        splashRadius: 18,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                        child: Text("$q", style: const TextStyle(fontWeight: FontWeight.w900)),
                      ),
                      IconButton(
                        onPressed: blocked ? null : onPlus,
                        icon: const Icon(Icons.add_circle_outline, color: Colors.deepPurple),
                        splashRadius: 18,
                      ),
                      const Spacer(),
                      Text("₹${total.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w900)),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              splashRadius: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// ✅ ORDERS TAB — FINAL (filters + search + cancel gating)
// =============================================================
class _OrdersTabFinal extends StatefulWidget {
  final String title;
  final String typeTag; // "product" | "service"
  final Future<List<Map<String, dynamic>>> Function() fetcher;

  final Future<Map<String, dynamic>> Function({
  required String id,
  required String type,
  required String reason,
  }) canceler;

  const _OrdersTabFinal({
    required this.title,
    required this.typeTag,
    required this.fetcher,
    required this.canceler,
  });

  @override
  State<_OrdersTabFinal> createState() => _OrdersTabFinalState();
}

class _OrdersTabFinalState extends State<_OrdersTabFinal> {
  late Future<List<Map<String, dynamic>>> _future;

  // UI controls
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _search = "";
  String _statusFilter = "all";
  int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _future = widget.fetcher();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final v = _searchCtrl.text.trim();
      if (!mounted) return;
      setState(() => _search = v);
    });
  }

  Future<void> _refresh() async {
    setState(() => _future = widget.fetcher());
    try {
      await _future;
    } catch (_) {}
  }

  String _s(dynamic v, {String fb = ""}) {
    final x = (v ?? "").toString().trim();
    return x.isEmpty ? fb : x;
  }

  double _d(dynamic v, {double fb = 0}) {
    if (v == null) return fb;
    if (v is num) return v.toDouble();
    final s = v.toString().replaceAll("₹", "").trim();
    return double.tryParse(s) ?? fb;
  }

  Map<String, dynamic> _map(dynamic v) => _safeMapAny(v);
  List _list(dynamic v) => _safeListAny(v);

  bool _isService(Map<String, dynamic> o) {
    final typeRaw = _s(o["type"] ?? o["order_type"] ?? o["mode"] ?? "");
    final t = typeRaw.toLowerCase();
    if (t.contains("service") || t.contains("booking")) return true;
    if (o.containsKey("booking_id") || o.containsKey("booking_number")) return true;
    if (o.containsKey("service_id") || o.containsKey("serviceId")) return true;
    return widget.typeTag == "service";
  }

  String _serviceStatusNorm(String status) {
    final s = status.trim().toLowerCase();
    if (s == "approved" || s == "accepted" || s == "confirmed") return "approved";
    if (s == "scheduled" || s == "booked") return "scheduled";
    if (s == "in_progress" || s == "ongoing") return "in_progress";
    if (s == "done" || s == "completed" || s == "complete") return "completed";
    if (s == "canceled" || s == "cancel") return "cancelled";
    if (s.isEmpty) return "pending";
    return s;
  }

  String _statusNorm(String status, {required bool isService}) {
    return isService ? _serviceStatusNorm(status) : OrdersAPI.normalizeStatus(status);
  }

  Color _statusColor(String status, {required bool isService}) {
    final s = _statusNorm(status, isService: isService);
    if (s.contains("cancel") || s.contains("reject") || s.contains("fail")) return Colors.red;
    if (s.contains("deliver") || s.contains("complete") || s.contains("done")) return Colors.green;
    if (s.contains("ship")) return Colors.blue;
    if (s.contains("process") || s.contains("confirm") || s.contains("ready") || s.contains("approved") || s.contains("scheduled")) return Colors.orange;
    return Colors.grey;
  }

  bool _canCancel(String status, {required bool isService}) {
    final s = _statusNorm(status, isService: isService);

    if (isService) {
      // ✅ service: allow cancel until completed/cancelled (safe default)
      if (s == "cancelled" || s == "completed" || s == "done") return false;
      return true;
    }

    // ✅ product: allow cancel until shipped+ (safe default)
    if (s == "created" || s == "pending" || s == "payment_pending" || s == "paid") return true;
    if (s == "processing" || s == "ready") return true;
    return false;
  }

  String _fmtDateChip(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return "";
    final dt = DateTime.tryParse(t);
    if (dt == null) return t.contains("T") ? t.split("T").first : t;
    final d = dt.toLocal();
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return "${d.day.toString().padLeft(2, "0")} ${months[d.month - 1]} ${d.year}";
  }

  String _titleOf(Map<String, dynamic> o, {required bool isService}) {
    if (isService) {
      final svc = _map(o["service"] ?? o["service_details"] ?? o["serviceDetail"] ?? o["serviceData"] ?? o["service_data"]);
      return _s(
        o["service_name"] ?? o["serviceName"] ?? o["service_title"] ?? svc["name"] ?? svc["title"] ?? o["title"],
        fb: "Service",
      );
    }

    final items = _list(o["items"] ?? o["order_items"] ?? o["products"] ?? o["cart_items"]);
    if (items.isNotEmpty) {
      final it = _map(items.first);
      final p = _map(it["product"]);
      final nm = _s(it["name"] ?? it["title"] ?? it["product_name"] ?? p["name"] ?? p["title"]);
      if (nm.isNotEmpty) return nm;
    }

    return _s(o["name"] ?? o["title"], fb: "Product");
  }

  String _idLine(Map<String, dynamic> o, {required bool isService}) {
    if (isService) {
      final bno = _s(o["booking_number"] ?? o["bookingNo"] ?? o["bookingNumber"]);
      final id = _s(o["id"] ?? o["booking_id"] ?? o["_id"] ?? o["order_id"]);
      return bno.isNotEmpty ? "Booking #$bno" : (id.isNotEmpty ? "Booking #$id" : "Booking");
    }

    final code = _s(o["order_code"] ?? o["orderCode"]);
    if (code.isNotEmpty) return "Order #$code";

    final id = _s(o["id"] ?? o["order_id"] ?? o["_id"]);
    return id.isNotEmpty ? "Order #$id" : "Order";
  }

  String _imageOf(Map<String, dynamic> o, {required bool isService}) {
    if (isService) {
      final svc = _map(o["service"] ?? o["service_details"] ?? o["serviceDetail"] ?? o["service_data"] ?? o["serviceData"]);
      final raw = _pickFirstNonEmpty([
        o["service_image"],
        o["serviceImage"],
        o["service_image_url"],
        o["serviceImageUrl"],
        o["image"],
        o["image_url"],
        o["imageUrl"],
        _pickImageFromMap(svc),
      ]);
      return _normalizeMediaUrl(raw);
    }

    final items = _list(o["items"] ?? o["order_items"] ?? o["products"] ?? o["cart_items"]);
    if (items.isNotEmpty) {
      final it = _map(items.first);
      final p = _map(it["product"]);
      final raw = _pickFirstNonEmpty([
        it["image"],
        it["image_url"],
        it["imageUrl"],
        p["image"],
        p["image_url"],
        p["imageUrl"],
        (p["images"] is List && (p["images"] as List).isNotEmpty) ? (p["images"] as List).first : null,
      ]);
      return _normalizeMediaUrl(raw);
    }

    return _normalizeMediaUrl(_pickFirstNonEmpty([o["image"], o["image_url"], o["imageUrl"]]));
  }

  String _amountText(Map<String, dynamic> o, {required bool isService}) {
    final v = isService
        ? (o["price"] ?? o["amount"] ?? o["total_amount"] ?? o["total"])
        : (o["total_amount"] ?? o["total"] ?? o["amount"] ?? o["payable_amount"] ?? o["payable"]);
    final n = _d(v, fb: 0);
    if (n > 0) return "₹${n.toStringAsFixed(0)}";
    final s = _s(v, fb: "0").replaceAll("₹", "").trim();
    return "₹${s.isEmpty ? "0" : s}";
  }

  String _dateText(Map<String, dynamic> o) {
    final raw = _s(
      o["created_at"] ?? o["createdAt"] ?? o["order_date"] ?? o["date"] ?? o["booked_at"] ?? o["booking_date"] ?? o["bookingDate"],
      fb: "",
    );
    return _fmtDateChip(raw);
  }

  int _itemsCount(Map<String, dynamic> o) {
    final items = _list(o["items"] ?? o["order_items"] ?? o["products"] ?? o["cart_items"]);
    return items.length;
  }

  bool _matchesSearch(Map<String, dynamic> o, bool isService) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return true;

    final id = _idLine(o, isService: isService).toLowerCase();
    final title = _titleOf(o, isService: isService).toLowerCase();
    final phone = _s(o["phone"] ?? o["customer_phone"] ?? o["mobile"] ?? o["customer_mobile"]).toLowerCase();
    final customer = _s(o["customer_name"] ?? o["customerName"] ?? o["name"] ?? o["user_name"]).toLowerCase();

    return id.contains(q) || title.contains(q) || phone.contains(q) || customer.contains(q);
  }

  bool _matchesStatus(Map<String, dynamic> o) {
    if (_statusFilter == "all") return true;

    final isSvc = _isService(o);
    final raw = _s(o["status"] ?? o["order_status"] ?? o["booking_status"], fb: "");
    final s = _statusNorm(raw, isService: isSvc);

    if (!isSvc) {
      if (_statusFilter == "created") return s == "created" || s == "pending" || s == "payment_pending";
      if (_statusFilter == "processing") return s.contains("process") || s.contains("confirm") || s.contains("ready");
      if (_statusFilter == "shipped") return s.contains("ship") || s.contains("out_for_delivery") || s.contains("ofd");
      if (_statusFilter == "delivered") return s.contains("deliver") || s.contains("complete") || s.contains("done");
      if (_statusFilter == "cancelled") return s.contains("cancel") || s.contains("reject") || s.contains("fail");
      return true;
    }

    // service chips
    if (_statusFilter == "pending") return s == "pending";
    if (_statusFilter == "approved") return s == "approved";
    if (_statusFilter == "scheduled") return s == "scheduled" || s.contains("schedule");
    if (_statusFilter == "completed") return s == "completed" || s == "done";
    if (_statusFilter == "cancelled") return s == "cancelled";
    return true;
  }

  List<Map<String, dynamic>> _sortNewest(List<Map<String, dynamic>> list) {
    DateTime? parse(dynamic v) {
      final s = (v ?? "").toString().trim();
      if (s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    final out = List<Map<String, dynamic>>.from(list);
    out.sort((a, b) {
      final da = parse(a["created_at"] ?? a["createdAt"] ?? a["date"] ?? a["order_date"] ?? a["booked_at"]) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = parse(b["created_at"] ?? b["createdAt"] ?? b["date"] ?? b["order_date"] ?? b["booked_at"]) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });
    return out;
  }

  Future<void> _cancelFlow(BuildContext context, Map<String, dynamic> o, bool isService) async {
    final statusRaw = _s(o["status"] ?? o["order_status"] ?? o["booking_status"], fb: "");
    if (!_canCancel(statusRaw, isService: isService)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("এই status-এ cancel করা যাবে না"), backgroundColor: Colors.red),
      );
      return;
    }

    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isService ? "Cancel booking?" : "Cancel order?"),
        content: TextField(
          controller: reasonCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: "Reason লিখো (required)",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Back")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Cancel", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final reason = reasonCtrl.text.trim();
    if (reason.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Reason required"), backgroundColor: Colors.red),
      );
      return;
    }

    final id = _s(o["id"] ?? o["order_id"] ?? o["booking_id"] ?? o["_id"] ?? o["order_code"] ?? o["orderCode"], fb: "");
    if (id.isEmpty) return;

    final res = await widget.canceler(id: id, type: isService ? "service" : "product", reason: reason);

    if (!context.mounted) return;

    if (res["success"] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res["message"]?.toString() ?? "Cancelled"), backgroundColor: Colors.deepPurple),
      );
      await _refresh();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res["message"]?.toString() ?? "Cancel failed"), backgroundColor: Colors.red),
      );
    }
  }

  Widget _chip(String label, {required bool selected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.deepPurple.withOpacity(0.12) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: selected ? Colors.deepPurple : Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: selected ? Colors.deepPurple : Colors.black87,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  List<Widget> _chipsRow() {
    final isSvcTab = widget.typeTag == "service";
    if (!isSvcTab) {
      return [
        _chip("All", selected: _statusFilter == "all", onTap: () => setState(() => _statusFilter = "all")),
        const SizedBox(width: 8),
        _chip("Created", selected: _statusFilter == "created", onTap: () => setState(() => _statusFilter = "created")),
        const SizedBox(width: 8),
        _chip("Processing", selected: _statusFilter == "processing", onTap: () => setState(() => _statusFilter = "processing")),
        const SizedBox(width: 8),
        _chip("Shipped", selected: _statusFilter == "shipped", onTap: () => setState(() => _statusFilter = "shipped")),
        const SizedBox(width: 8),
        _chip("Delivered", selected: _statusFilter == "delivered", onTap: () => setState(() => _statusFilter = "delivered")),
        const SizedBox(width: 8),
        _chip("Cancelled", selected: _statusFilter == "cancelled", onTap: () => setState(() => _statusFilter = "cancelled")),
      ];
    }

    return [
      _chip("All", selected: _statusFilter == "all", onTap: () => setState(() => _statusFilter = "all")),
      const SizedBox(width: 8),
      _chip("Pending", selected: _statusFilter == "pending", onTap: () => setState(() => _statusFilter = "pending")),
      const SizedBox(width: 8),
      _chip("Approved", selected: _statusFilter == "approved", onTap: () => setState(() => _statusFilter = "approved")),
      const SizedBox(width: 8),
      _chip("Scheduled", selected: _statusFilter == "scheduled", onTap: () => setState(() => _statusFilter = "scheduled")),
      const SizedBox(width: 8),
      _chip("Completed", selected: _statusFilter == "completed", onTap: () => setState(() => _statusFilter = "completed")),
      const SizedBox(width: 8),
      _chip("Cancelled", selected: _statusFilter == "cancelled", onTap: () => setState(() => _statusFilter = "cancelled")),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.deepPurple));
        }

        final data0 = snap.data ?? [];

        // error shape
        if (data0.length == 1 && data0.first["_error"] != null) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 120),
                Icon(Icons.error_outline, size: 60, color: Colors.red.shade300),
                const SizedBox(height: 10),
                Text(
                  data0.first["message"]?.toString() ?? "Error",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                Text(
                  "Pull down করে আবার try করো।",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          );
        }

        // normalize + sort
        final normalized = data0.map((e) => _normalizeOrderImagesLite(e)).toList();
        final sorted = _sortNewest(normalized);

        // filter
        final filtered = <Map<String, dynamic>>[];
        for (final o in sorted) {
          final isService = _isService(o);
          if (!_matchesStatus(o)) continue;
          if (!_matchesSearch(o, isService)) continue;
          filtered.add(o);
        }

        final visible = filtered.take(_pageSize).toList();
        final hasMore = filtered.length > visible.length;

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // controls
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: "Search: order id / booking / phone / name",
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: _chipsRow()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              if (filtered.isEmpty) ...[
                const SizedBox(height: 80),
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.inbox_outlined, size: 70, color: Colors.grey.shade300),
                      const SizedBox(height: 10),
                      const Text("No orders found", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Text(
                        "Filter/Search বদলে আবার দেখো।",
                        style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                for (final o0 in visible)
                  _OrderCardFinal(
                    o0: o0,
                    isService: _isService(o0),
                    title: _titleOf(o0, isService: _isService(o0)),
                    idLine: _idLine(o0, isService: _isService(o0)),
                    img: _imageOf(o0, isService: _isService(o0)),
                    amount: _amountText(o0, isService: _isService(o0)),
                    date: _dateText(o0),
                    status: _statusNorm(
                      _s(o0["status"] ?? o0["order_status"] ?? o0["booking_status"], fb: _isService(o0) ? "pending" : "created"),
                      isService: _isService(o0),
                    ),
                    statusColor: _statusColor(
                      _s(o0["status"] ?? o0["order_status"] ?? o0["booking_status"], fb: _isService(o0) ? "pending" : "created"),
                      isService: _isService(o0),
                    ),
                    phone: _s(o0["phone"] ?? o0["customer_phone"] ?? o0["mobile"] ?? o0["customer_mobile"]),
                    itemsCount: _isService(o0) ? null : _itemsCount(o0),
                    canCancel: _canCancel(
                      _s(o0["status"] ?? o0["order_status"] ?? o0["booking_status"], fb: _isService(o0) ? "pending" : "created"),
                      isService: _isService(o0),
                    ),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => CartDetailsPage(order: o0, isService: _isService(o0))),
                      );
                      await _refresh();
                    },
                    onCancel: () => _cancelFlow(context, o0, _isService(o0)),
                  ),

                if (hasMore) ...[
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () => setState(() => _pageSize += 20),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text("Load more", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                  ),
                ],
                const SizedBox(height: 10),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _OrderCardFinal extends StatelessWidget {
  final Map<String, dynamic> o0;
  final bool isService;
  final String title;
  final String idLine;
  final String img;
  final String amount;
  final String date;
  final String status;
  final Color statusColor;
  final String phone;
  final int? itemsCount;
  final bool canCancel;
  final VoidCallback onTap;
  final VoidCallback onCancel;

  const _OrderCardFinal({
    required this.o0,
    required this.isService,
    required this.title,
    required this.idLine,
    required this.img,
    required this.amount,
    required this.date,
    required this.status,
    required this.statusColor,
    required this.phone,
    required this.itemsCount,
    required this.canCancel,
    required this.onTap,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 66,
                width: 66,
                color: Colors.grey.shade200,
                child: img.isNotEmpty
                    ? Image.network(
                  img,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey),
                )
                    : const Icon(Icons.image_not_supported, color: Colors.grey),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  idLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w800, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _miniChip(amount, bold: true),
                    const SizedBox(width: 8),
                    if (date.trim().isNotEmpty) _miniChip(date),
                    if (!isService && itemsCount != null) ...[
                      const SizedBox(width: 8),
                      _miniChip("$itemsCount items"),
                    ],
                  ],
                ),
                if (phone.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    "Phone: $phone",
                    style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      "View details",
                      style: TextStyle(color: Colors.deepPurple.shade700, fontWeight: FontWeight.w900),
                    ),
                    const Spacer(),
                    if (canCancel)
                      TextButton.icon(
                        onPressed: onCancel,
                        icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                        label: const Text("Cancel", style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900)),
                      )
                    else
                      const SizedBox.shrink(),
                  ],
                )
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniChip(String text, {bool bold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(18)),
      child: Text(text, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w800, fontSize: 12)),
    );
  }
}
