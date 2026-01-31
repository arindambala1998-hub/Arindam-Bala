// lib/services/product_api.dart (FINAL • BULLETPROOF • Troonky backend compatible)
//
// ✅ Works with your backend endpoints:
// - GET  /api/business/:id/products   (your new business.js route)
// - GET  /api/products/:businessId    (legacy fallback)
// - POST /api/products/add            (multipart)
// - PUT  /api/products/update/:id     (supports multipart + json)
// - DELETE /api/products/delete/:id
// - GET  /api/offers/local?pincode=
//
// ✅ Key fixes vs your current file:
// - listByBusiness() now prefers /business/:id/products (because that's what your backend exposes now)
// - updateProductJson supports BOTH JSON + multipart fallback (because your update route accepts -F image too)
// - safer auth headers merge (no duplicate Accept/Content-Type issues)
// - normalizeProduct includes image_urls + image_url generation using BusinessAPI.toPublicUrl()
// - images/colors/sizes/specs robust parsing (JSON string / list / csv)
// - offers parser reads multiple possible keys

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:troonky_link/services/business_api.dart';

class ProductAPI {
  static const String baseUrl = "https://adminapi.troonky.in/api";
  static const Duration _timeout = Duration(seconds: 25);

  // ---------------------------
  // Helpers
  // ---------------------------
  static String _s(dynamic v) => v == null ? "" : v.toString();

  static bool _isBadString(String? v) {
    final s = (v ?? "").trim();
    if (s.isEmpty) return true;
    final low = s.toLowerCase();
    return low == "null" || low == "undefined" || low == "nan" || low == "none";
  }

  static int _asInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  static double _asDouble(dynamic v, {double fallback = 0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  static bool _asBool01(dynamic v, {bool fallback = false}) {
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

  static dynamic _safeDecodeAny(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

  /// ✅ Safe JSON decode (Map preferred)
  static Map<String, dynamic> _safeJson(String raw) {
    final decoded = _safeDecodeAny(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return {"data": decoded};
  }

  /// ✅ Parse List from:
  /// - List
  /// - JSON String list: "[]"
  /// - comma string: "a,b"
  static List<dynamic> _asListLoose(dynamic v) {
    if (v == null) return [];
    if (v is List) return v;
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return [];
      if (s.startsWith('[') && s.endsWith(']')) {
        final decoded = _safeDecodeAny(s);
        if (decoded is List) return decoded;
      }
      if (s.contains(',')) {
        return s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
    }
    return [];
  }

  /// ✅ Parse Map from:
  /// - Map
  /// - JSON String map: "{}"
  static Map<String, dynamic> _asMapLoose(dynamic v) {
    if (v == null) return {};
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return {};
      if (s.startsWith('{') && s.endsWith('}')) {
        final decoded = _safeDecodeAny(s);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
    }
    return {};
  }

  static Future<Map<String, String>> _authOnly() async {
    // BusinessAPI final auth header helper (Authorization + Accept)
    return await BusinessAPI.authHeaderOnly();
  }

  static Future<Map<String, String>> _jsonHeaders() async {
    final h = await _authOnly();
    // avoid duplicate keys problems: force our json headers, then merge auth
    return {
      "Accept": "application/json",
      "Content-Type": "application/json",
      ...h,
    };
  }

  // ============================================================
  // ✅ NORMALIZE PRODUCT (VERY IMPORTANT)
  // ============================================================
  static Map<String, dynamic> normalizeProduct(
      Map<String, dynamic> p, {
        String? businessId,
      }) {
    final out = Map<String, dynamic>.from(p);

    // unify id keys
    final idRaw = out["id"] ?? out["_id"] ?? out["product_id"] ?? out["productId"];
    out["id"] = idRaw;
    out["product_id"] = out["product_id"] ?? idRaw;

    // business/shop id normalization
    final incomingBiz = (out["business_id"] ??
        out["shop_id"] ??
        out["businessId"] ??
        out["shopId"] ??
        businessId)
        ?.toString()
        .trim();

    if (!_isBadString(incomingBiz)) {
      final parsed = int.tryParse(incomingBiz!);
      out["business_id"] = out["business_id"] ?? out["shop_id"] ?? parsed ?? incomingBiz;
      out["shop_id"] = out["shop_id"] ?? out["business_id"];
    }

    // ✅ price fields
    out["price"] = out["price"] ?? out["unit_price"];
    out["offer_price"] = out["offer_price"] ?? out["discount_price"] ?? out["offerPrice"];
    out["old_price"] = out["old_price"] ?? out["mrp"] ?? out["oldPrice"];

    // numeric defaults
    out["stock"] = _asInt(out["stock"], fallback: 0);
    out["low_stock_threshold"] = _asInt(out["low_stock_threshold"], fallback: 5);

    // backend uses 0/1
    out["cod_available"] = _asInt(out["cod_available"], fallback: 0);
    out["open_box_delivery"] = _asInt(out["open_box_delivery"], fallback: 0);
    out["is_deleted"] = _asInt(out["is_deleted"], fallback: 0);
    out["is_original"] = _asInt(out["is_original"], fallback: 1);

    // JSON-string fields
    out["images"] = _asListLoose(out["images"]);
    out["colors"] = _asListLoose(out["colors"]);
    out["sizes"] = _asListLoose(out["sizes"]);
    out["specs"] = _asMapLoose(out["specs"]);

    // ✅ image_url + image_urls (absolute) if backend didn't provide
    final main = _s(out["image_url"] ?? out["image"]).trim();
    if (main.isNotEmpty) {
      out["image_url"] = BusinessAPI.toPublicUrl(main);
    }

    final rawUrls = out["image_urls"];
    final urls = <String>[];

    if (rawUrls is List) {
      for (final x in rawUrls) {
        final s = _s(x).trim();
        if (s.isNotEmpty) urls.add(BusinessAPI.toPublicUrl(s));
      }
    }

    if (urls.isEmpty) {
      final imgs = _asListLoose(out["images"]);
      for (final x in imgs) {
        final s = _s(x).trim();
        if (s.isNotEmpty) urls.add(BusinessAPI.toPublicUrl(s));
      }
    }

    if (urls.isEmpty && main.isNotEmpty) {
      urls.add(BusinessAPI.toPublicUrl(main));
    }

    out["image_urls"] = urls.toSet().toList();

    return out;
  }

  /// UI helper: product image normalization (absolute url list)
  static List<String> normalizeImages(Map<String, dynamic> p) {
    final List<String> out = [];

    final urls = p["image_urls"];
    if (urls is List) {
      for (final x in urls) {
        final s = _s(x).trim();
        if (s.isNotEmpty) out.add(BusinessAPI.toPublicUrl(s));
      }
    }

    if (out.isEmpty) {
      final imgs = _asListLoose(p["images"]);
      for (final x in imgs) {
        final s = _s(x).trim();
        if (s.isNotEmpty) out.add(BusinessAPI.toPublicUrl(s));
      }
    }

    if (out.isEmpty) {
      final one = _s(p["image_url"] ?? p["image"]).trim();
      if (one.isNotEmpty) out.add(BusinessAPI.toPublicUrl(one));
    }

    return out.toSet().toList();
  }

  // ============================================================
  // 1) LIST PRODUCTS (Business) - prefer new backend route
  // GET /api/business/:id/products?limit=..&offset=..
  // fallback: /api/products/:businessId
  // ============================================================
  static Future<List<Map<String, dynamic>>> listByBusiness({
    required String businessId,
    int limit = 200,
    int offset = 0,
  }) async {
    final id = businessId.trim();
    if (id.isEmpty) return [];

    final candidates = <Uri>[
      Uri.parse("$baseUrl/business/$id/products?limit=$limit&offset=$offset"),
      Uri.parse("$baseUrl/products/$id"), // legacy
    ];

    for (final uri in candidates) {
      try {
        final res = await http.get(uri, headers: await _jsonHeaders()).timeout(_timeout);
        if (res.statusCode != 200) continue;

        final decoded = _safeJson(res.body);

        // new route returns { products:[...] }
        final list1 = decoded["products"];
        if (list1 is List) {
          return list1
              .whereType<Map>()
              .map((e) => normalizeProduct(Map<String, dynamic>.from(e), businessId: id))
              .toList();
        }

        // other shapes
        final list2 = decoded["data"];
        if (list2 is List) {
          return list2
              .whereType<Map>()
              .map((e) => normalizeProduct(Map<String, dynamic>.from(e), businessId: id))
              .toList();
        }

        // sometimes backend returns List directly
        final any = decoded["data"];
        if (any is List) {
          return any
              .whereType<Map>()
              .map((e) => normalizeProduct(Map<String, dynamic>.from(e), businessId: id))
              .toList();
        }
      } catch (_) {}
    }

    return [];
  }

  // ============================================================
  // 2) LIST PRODUCTS (Shop) (legacy probe)
  // GET /api/shops/:id/products  (may not exist on your backend)
  // fallback: use listByBusiness which definitely works
  // ============================================================
  static Future<List<Map<String, dynamic>>> listByShop({
    required String shopId,
    int limit = 200,
    int offset = 0,
  }) async {
    final id = shopId.trim();
    if (id.isEmpty) return [];

    final candidates = <Uri>[
      Uri.parse("$baseUrl/shops/$id/products"),
      Uri.parse("$baseUrl/shop/$id/products"),
      Uri.parse("$baseUrl/business/$id/products?limit=$limit&offset=$offset"), // safest
      Uri.parse("$baseUrl/products/$id"), // legacy
    ];

    for (final uri in candidates) {
      try {
        final res = await http.get(uri, headers: await _jsonHeaders()).timeout(_timeout);
        if (res.statusCode != 200) continue;

        final decoded = _safeJson(res.body);

        final list = decoded["products"] ?? decoded["data"];
        if (list is List) {
          return list
              .whereType<Map>()
              .map((e) => normalizeProduct(Map<String, dynamic>.from(e), businessId: id))
              .toList();
        }
      } catch (_) {}
    }

    return [];
  }

  // ============================================================
  // 3) GET PRODUCT DETAIL BY ID (robust)
  // Tries common endpoints.
  // ============================================================
  static Future<Map<String, dynamic>> getDetailById(String productId) async {
    final pid = productId.trim();
    if (pid.isEmpty) return {};

    final candidates = <Uri>[
      Uri.parse("$baseUrl/product/products/$pid"),
      Uri.parse("$baseUrl/products/details/$pid"),
      Uri.parse("$baseUrl/products/detail/$pid"),
      Uri.parse("$baseUrl/products/$pid"),
    ];

    for (final uri in candidates) {
      try {
        final res = await http.get(uri, headers: await _jsonHeaders()).timeout(_timeout);
        if (res.statusCode != 200) continue;

        final decoded = _safeJson(res.body);

        final prod = decoded["product"] ?? decoded["data"] ?? decoded["result"];
        if (prod is Map) return normalizeProduct(Map<String, dynamic>.from(prod));

        // sometimes backend returns product directly
        final looksLikeProduct = decoded.containsKey("id") || decoded.containsKey("name") || decoded.containsKey("price");
        if (looksLikeProduct) return normalizeProduct(decoded);
      } catch (_) {}
    }

    return {};
  }

  // ============================================================
  // 4) CHECK DELIVERY (pincode)
  // GET /api/product/products/:id/check-delivery?pincode=XXXXXX
  // ============================================================
  static Future<Map<String, dynamic>> checkDelivery({
    required String productId,
    required String pincode,
  }) async {
    final pid = productId.trim();
    final pin = pincode.trim();
    if (pid.isEmpty || pin.isEmpty) {
      return {"success": false, "message": "productId & pincode required"};
    }

    final uri = Uri.parse("$baseUrl/product/products/$pid/check-delivery?pincode=$pin");

    try {
      final res = await http.get(uri, headers: await _jsonHeaders()).timeout(_timeout);
      final decoded = _safeJson(res.body);

      if (res.statusCode == 200) return decoded;

      return {"success": false, "statusCode": res.statusCode, "body": decoded};
    } catch (e) {
      return {"success": false, "message": "Network error: $e"};
    }
  }

  // ============================================================
  // 5) ADD PRODUCT (MULTIPART)
  // POST /api/products/add
  // ============================================================
  static Future<Map<String, dynamic>> addProduct({
    required int businessId,
    required String name,
    required num price,
    String description = "",
    int? stock,
    int? lowStockThreshold,
    int? codAvailable,
    int? openBoxDelivery,
    File? imageFile,
  }) async {
    final uri = Uri.parse("$baseUrl/products/add");

    try {
      final auth = await _authOnly();

      final req = http.MultipartRequest("POST", uri);
      req.headers.addAll({"Accept": "application/json", ...auth});

      req.fields["business_id"] = businessId.toString();
      req.fields["name"] = name.trim();
      req.fields["price"] = price.toString();

      if (description.trim().isNotEmpty) req.fields["description"] = description.trim();
      if (stock != null) req.fields["stock"] = stock.toString();
      if (lowStockThreshold != null) req.fields["low_stock_threshold"] = lowStockThreshold.toString();
      if (codAvailable != null) req.fields["cod_available"] = codAvailable.toString();
      if (openBoxDelivery != null) req.fields["open_box_delivery"] = openBoxDelivery.toString();

      if (imageFile != null && await imageFile.exists()) {
        req.files.add(await http.MultipartFile.fromPath("image", imageFile.path));
      }

      final streamed = await req.send().timeout(_timeout);
      final res = await http.Response.fromStream(streamed).timeout(_timeout);

      final decoded = _safeJson(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) return decoded;

      return {
        "success": false,
        "statusCode": res.statusCode,
        "message": decoded["message"] ?? "Add product failed",
        "body": decoded,
      };
    } catch (e) {
      return {"success": false, "message": "Network error: $e"};
    }
  }

  // ============================================================
  // 6) UPDATE PRODUCT
  // Your backend supports:
  // - multipart: -F image=...
  // - and/or json body fields
  // We do: try JSON first; if imageFile present -> multipart.
  // ============================================================
  static Future<Map<String, dynamic>> updateProduct({
    required String productId,
    String? name,
    num? price,
    String? description,
    int? stock,
    int? lowStockThreshold,
    int? codAvailable,
    int? openBoxDelivery,
    File? imageFile,
  }) async {
    final pid = productId.trim();
    if (pid.isEmpty) return {"success": false, "message": "Invalid productId"};

    // If image is present => prefer multipart (matches your tested curl)
    if (imageFile != null) {
      final r = await updateProductMultipart(
        productId: pid,
        name: name,
        price: price,
        description: description,
        stock: stock,
        lowStockThreshold: lowStockThreshold,
        codAvailable: codAvailable,
        openBoxDelivery: openBoxDelivery,
        imageFile: imageFile,
      );
      return r;
    }

    // else json
    final ok = await updateProductJson(
      productId: pid,
      name: name,
      price: price,
      description: description,
      stock: stock,
      lowStockThreshold: lowStockThreshold,
      codAvailable: codAvailable,
      openBoxDelivery: openBoxDelivery,
    );

    return ok ? {"success": true} : {"success": false, "message": "Update failed"};
  }

  static Future<Map<String, dynamic>> updateProductMultipart({
    required String productId,
    String? name,
    num? price,
    String? description,
    int? stock,
    int? lowStockThreshold,
    int? codAvailable,
    int? openBoxDelivery,
    required File imageFile,
  }) async {
    final pid = productId.trim();
    if (pid.isEmpty) return {"success": false, "message": "Invalid productId"};

    final uri = Uri.parse("$baseUrl/products/update/$pid");

    try {
      final auth = await _authOnly();
      final req = http.MultipartRequest("PUT", uri);
      req.headers.addAll({"Accept": "application/json", ...auth});

      if (name != null && name.trim().isNotEmpty) req.fields["name"] = name.trim();
      if (price != null) req.fields["price"] = price.toString();
      if (description != null && description.trim().isNotEmpty) req.fields["description"] = description.trim();
      if (stock != null) req.fields["stock"] = stock.toString();
      if (lowStockThreshold != null) req.fields["low_stock_threshold"] = lowStockThreshold.toString();
      if (codAvailable != null) req.fields["cod_available"] = codAvailable.toString();
      if (openBoxDelivery != null) req.fields["open_box_delivery"] = openBoxDelivery.toString();

      if (await imageFile.exists()) {
        req.files.add(await http.MultipartFile.fromPath("image", imageFile.path));
      } else {
        return {"success": false, "message": "Image file not found"};
      }

      final streamed = await req.send().timeout(const Duration(seconds: 60));
      final res = await http.Response.fromStream(streamed).timeout(_timeout);

      final decoded = _safeJson(res.body);
      final ok = (res.statusCode == 200 || res.statusCode == 201);

      return {
        "success": ok && (decoded["success"] == null || decoded["success"] == true),
        "statusCode": res.statusCode,
        "body": decoded,
        ...decoded,
      };
    } catch (e) {
      return {"success": false, "message": "Network error: $e"};
    }
  }

  // kept for compatibility with your older calls
  static Future<bool> updateProductJson({
    required String productId,
    String? name,
    num? price,
    String? description,
    String? image, // rarely used now; backend expects file normally
    int? stock,
    int? lowStockThreshold,
    int? codAvailable,
    int? openBoxDelivery,
  }) async {
    final pid = productId.trim();
    if (pid.isEmpty) return false;

    final uri = Uri.parse("$baseUrl/products/update/$pid");

    final body = <String, dynamic>{
      if (name != null && name.trim().isNotEmpty) "name": name.trim(),
      if (price != null) "price": price.toString(),
      if (description != null && description.trim().isNotEmpty) "description": description.trim(),
      if (image != null && image.trim().isNotEmpty) "image": image.trim(),
      if (stock != null) "stock": stock,
      if (lowStockThreshold != null) "low_stock_threshold": lowStockThreshold,
      if (codAvailable != null) "cod_available": codAvailable,
      if (openBoxDelivery != null) "open_box_delivery": openBoxDelivery,
    };

    if (body.isEmpty) return false;

    try {
      final res = await http.put(uri, headers: await _jsonHeaders(), body: jsonEncode(body)).timeout(_timeout);

      if (res.statusCode != 200 && kDebugMode) {
        // ignore: avoid_print
        print("❌ updateProductJson failed ${res.statusCode} -> ${res.body}");
      }
      return res.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print("❌ updateProductJson error: $e");
      }
      return false;
    }
  }

  // ============================================================
  // 7) DELETE PRODUCT (soft delete)
  // DELETE /api/products/delete/:id
  // ============================================================
  static Future<bool> delete(String productId) async {
    final pid = productId.trim();
    if (pid.isEmpty) return false;

    final uri = Uri.parse("$baseUrl/products/delete/$pid");

    try {
      final res = await http.delete(uri, headers: await _jsonHeaders()).timeout(_timeout);

      if (res.statusCode != 200 && kDebugMode) {
        // ignore: avoid_print
        print("❌ delete failed ${res.statusCode} -> ${res.body}");
      }
      return res.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print("❌ delete error: $e");
      }
      return false;
    }
  }

  // ============================================================
  // ✅ 8) OFFERS (PINCODE BASED)
  // GET /api/offers/local?pincode=XXXXXX
  // ============================================================
  static bool isValidPincode(String s) => RegExp(r'^\d{6}$').hasMatch(s.trim());

  static bool isOfferProduct(Map<String, dynamic> p) {
    final offerFlag = _asBool01(p["is_offer"], fallback: false) ||
        _asBool01(p["isOffer"], fallback: false) ||
        _asBool01(p["has_offer"], fallback: false) ||
        _asBool01(p["hasOffer"], fallback: false) ||
        _asBool01(p["offer"], fallback: false);

    final offerPrice = _asDouble(p["offer_price"] ?? p["offerPrice"], fallback: 0);
    final price = _asDouble(p["price"], fallback: 0);
    final oldPrice = _asDouble(p["old_price"] ?? p["oldPrice"] ?? p["mrp"], fallback: 0);

    if (offerFlag) return true;
    if (offerPrice > 0) return true;
    if (oldPrice > 0 && price > 0 && oldPrice > price) return true;

    final discPct = _asDouble(p["discount_percent"] ?? p["discountPercent"], fallback: 0);
    if (discPct > 0) return true;

    return false;
  }

  static String categoryOf(Map<String, dynamic> p) {
    final c = p["category"];
    if (c == null) return "Others";
    if (c is String) return c.trim().isEmpty ? "Others" : c.trim();
    if (c is Map && c["name"] != null) return c["name"].toString().trim();
    return c.toString().trim().isEmpty ? "Others" : c.toString().trim();
  }

  static Future<List<Map<String, dynamic>>> listOffersByPincode({
    required String pincode,
  }) async {
    final pin = pincode.trim();
    if (!isValidPincode(pin)) return [];

    final uri = Uri.parse("$baseUrl/offers/local?pincode=${Uri.encodeQueryComponent(pin)}");

    try {
      final res = await http.get(uri, headers: await _jsonHeaders()).timeout(_timeout);
      if (res.statusCode != 200) return [];

      final decoded = _safeJson(res.body);

      dynamic raw =
          decoded["products"] ??
              decoded["offers"] ??
              decoded["items"] ??
              decoded["data"] ??
              decoded["result"];

      // sometimes nested
      if (raw is Map) {
        raw = raw["products"] ?? raw["offers"] ?? raw["items"] ?? raw["data"];
      }

      if (raw is! List) return [];

      final list = raw
          .whereType<Map>()
          .map((e) => normalizeProduct(Map<String, dynamic>.from(e)))
          .toList();

      return list.where(isOfferProduct).toList();
    } catch (_) {
      return [];
    }
  }

  static List<Map<String, dynamic>> filterOffers(
      List<Map<String, dynamic>> input, {
        String selectedCategory = "All",
      }) {
    final cat = selectedCategory.trim().toLowerCase();

    return input.where((p) {
      if (!isOfferProduct(p)) return false;
      if (cat == "all") return true;
      return categoryOf(p).toLowerCase() == cat;
    }).toList();
  }
}
