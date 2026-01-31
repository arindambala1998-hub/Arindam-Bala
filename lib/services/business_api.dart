// lib/services/business_api.dart (FINAL • BULLETPROOF • Backend-compatible)
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class BusinessAPI {
  static const String baseUrl = "https://adminapi.troonky.in/api";
  static const String publicBase = "https://adminapi.troonky.in";

  static const Duration _timeout = Duration(seconds: 20);

  // ============================================================
  // 🔐 TOKEN (multi-key fallback)
  // ============================================================
  static Future<String?> _getToken() async {
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

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("token", token.trim());
  }

  static Future<Map<String, String>> authHeaderOnly() async {
    final token = await _getToken();
    return {
      if (token != null && token.isNotEmpty) "Authorization": "Bearer $token",
      "Accept": "application/json",
    };
  }

  static Future<Map<String, String>> _headers({bool json = true}) async {
    final token = await _getToken();
    return {
      if (json) "Content-Type": "application/json",
      if (token != null && token.isNotEmpty) "Authorization": "Bearer $token",
      "Accept": "application/json",
    };
  }

  // ============================================================
  // ✅ helpers
  // ============================================================
  static bool _isBadString(String? v) {
    final s = (v ?? "").trim();
    if (s.isEmpty) return true;
    final low = s.toLowerCase();
    return low == "null" ||
        low == "undefined" ||
        low == "nan" ||
        low == "none" ||
        low == "false" ||
        low == "0";
  }

  static int _asInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  static Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return {};
  }

  static dynamic _safeJsonDecode(String body) {
    try {
      if (body.trim().isEmpty) return null;
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  static Map<String, dynamic> _safeJsonMap(String body) {
    final decoded = _safeJsonDecode(body);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
  }

  static bool _looksLikeBusinessMap(Map m) {
    return m.containsKey("id") ||
        m.containsKey("_id") ||
        m.containsKey("name") ||
        m.containsKey("shop_id") ||
        m.containsKey("business_id") ||
        m.containsKey("logo") ||
        m.containsKey("cover");
  }

  static bool _looksLikeUserMap(Map m) {
    return m.containsKey("id") ||
        m.containsKey("_id") ||
        m.containsKey("name") ||
        m.containsKey("email") ||
        m.containsKey("user_id") ||
        m.containsKey("userId");
  }

  // ============================================================
  // ✅ /users/me (robust)
  // ============================================================
  static Future<Map<String, dynamic>> fetchMe() async {
    try {
      final res = await http
          .get(
        Uri.parse("$baseUrl/users/me"),
        headers: await _headers(json: false),
      )
          .timeout(_timeout);

      if (kDebugMode) {
        print("🟦 ME GET /users/me -> ${res.statusCode}");
        if (res.body.isNotEmpty) {
          final preview = res.body.length > 350 ? res.body.substring(0, 350) : res.body;
          print("🟨 ME BODY (preview) -> $preview");
        }
      }

      if (res.statusCode != 200) return {};
      final decoded = _safeJsonDecode(res.body);

      if (decoded is Map) {
        dynamic u = decoded["user"] ?? decoded["data"] ?? decoded["result"];
        if (u is Map) {
          u = u["user"] ?? u;
          return _asMap(u);
        }
        if (_looksLikeUserMap(decoded)) return _asMap(decoded);
      }
      return {};
    } catch (e) {
      if (kDebugMode) print("❌ fetchMe error: $e");
      return {};
    }
  }

  static Future<void> cacheMe() async {
    try {
      final me = await fetchMe();
      if (me.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();

      final uid = _asInt(me["id"] ?? me["_id"] ?? me["user_id"] ?? me["userId"]);
      if (uid > 0) {
        await prefs.setInt("user_id", uid);
        await prefs.setString("userId", uid.toString());
        await prefs.setString("userid", uid.toString());
      }

      final bid =
      _asInt(me["business_id"] ?? me["businessId"] ?? me["shop_id"] ?? me["shopId"]);
      if (bid > 0) {
        await prefs.setInt("business_id", bid);
        await prefs.setInt("shop_id", bid);
        await prefs.setString("businessId", bid.toString());
        await prefs.setString("shopId", bid.toString());
      }

      await prefs.setString("me", jsonEncode(me));

      if (kDebugMode) print("✅ cacheMe saved -> user_id=$uid, business_id=$bid");
    } catch (e) {
      if (kDebugMode) print("❌ cacheMe error: $e");
    }
  }

  static Future<int> getCachedBusinessId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt("business_id") ??
        prefs.getInt("shop_id") ??
        int.tryParse((prefs.getString("businessId") ?? "").trim()) ??
        int.tryParse((prefs.getString("shopId") ?? "").trim()) ??
        0;
  }

  // ============================================================
  // ⭐ 1) GET BUSINESS DETAILS (matches your backend: /api/business/:id)
  // returns: { "business": {...} } OR {}
  // ============================================================
  static Future<Map<String, dynamic>> fetchBusiness(String businessId) async {
    final id = businessId.trim();
    if (_isBadString(id)) return {};

    final headers = await _headers(json: false);

    if (kDebugMode) {
      final token = await _getToken();
      print("🔐 token? ${token != null && token.isNotEmpty} len=${token?.length ?? 0}");
      print("➡️ fetchBusiness id=$id");
    }

    final endpoints = <String>[
      "$baseUrl/business/$id",
      "$baseUrl/shops/$id",
      "$baseUrl/shop/$id",
      "$baseUrl/business/profile/$id",
    ];

    for (final ep in endpoints) {
      try {
        final res = await http.get(Uri.parse(ep), headers: headers).timeout(_timeout);

        if (kDebugMode) {
          print("🟦 BUSINESS GET $ep -> ${res.statusCode}");
          if (res.body.isNotEmpty) {
            final preview = res.body.length > 350 ? res.body.substring(0, 350) : res.body;
            print("🟨 BUSINESS BODY (preview) -> $preview");
          }
        }

        if (res.statusCode == 401 || res.statusCode == 403) return {};
        if (res.statusCode != 200) {
          if (res.statusCode == 404) continue;
          continue;
        }

        final decoded = _safeJsonDecode(res.body);

        if (decoded is Map) {
          dynamic b = decoded["business"] ?? decoded["shop"] ?? decoded["data"] ?? decoded["result"];
          if (b is Map) {
            b = b["business"] ?? b["shop"] ?? b;
            return {"business": Map<String, dynamic>.from(b)};
          }

          if (_looksLikeBusinessMap(decoded)) {
            return {"business": Map<String, dynamic>.from(decoded)};
          }
        }
      } catch (e) {
        if (kDebugMode) print("❌ fetchBusiness error ($ep): $e");
      }
    }

    return {};
  }

  // ============================================================
  // ⭐ Dashboard counts (if exists in backend)
  // GET /api/business/:id/dashboard-counts
  // ============================================================
  static Future<Map<String, dynamic>> fetchDashboardCounts(String businessId) async {
    final id = businessId.trim();
    if (_isBadString(id)) return {};

    try {
      final res = await http
          .get(
        Uri.parse("$baseUrl/business/$id/dashboard-counts"),
        headers: await _headers(json: false),
      )
          .timeout(_timeout);

      if (res.statusCode == 401 || res.statusCode == 403) return {};
      if (res.statusCode != 200) return {};

      final data = _safeJsonMap(res.body);
      final countsAny = data["counts"] ?? data["data"] ?? data["result"];
      if (countsAny is Map) return {"counts": Map<String, dynamic>.from(countsAny)};
      return data;
    } catch (e) {
      if (kDebugMode) print("❌ fetchDashboardCounts error: $e");
      return {};
    }
  }

  // ============================================================
  // 🛍️ 2) GET PRODUCTS (backend uses /api/products/:businessId?limit&offset&q)
  // returns list of product maps
  // ✅ /products list (paged)
  static Future<List<Map<String, dynamic>>> fetchProducts({
    required String shopId,
    int page = 1,
    int limit = 50,
  }) async {
    final id = shopId.trim();
    if (_isBadString(id)) return [];

    page = page <= 0 ? 1 : page;
    limit = limit <= 0 ? 50 : limit;

    final candidates = <Uri>[
      // page-based
      Uri.parse("$baseUrl/products/$id?page=$page&limit=$limit"),
      Uri.parse("$baseUrl/products/$id?Page=$page&Limit=$limit"),
      // offset-based fallback
      Uri.parse("$baseUrl/products/$id?offset=${(page - 1) * limit}&limit=$limit"),
    ];

    for (final url in candidates) {
      try {
        final res = await http.get(url, headers: await _headers()).timeout(_timeout);
        if (res.statusCode != 200) continue;

        final decoded = _safeJsonDecode(res.body);

        if (decoded is Map && decoded["products"] is List) {
          return List<Map<String, dynamic>>.from(decoded["products"]);
        }
        if (decoded is Map && decoded["data"] is List) {
          return List<Map<String, dynamic>>.from(decoded["data"]);
        }
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {}
    }

    return [];
  }


  // ============================================================
  // 🧰 3) GET SERVICES (backend uses /api/services?business_id=8)
  // returns list of service maps
  // ============================================================
  static Future<List<Map<String, dynamic>>> fetchServices({
    required String shopId,
    int limit = 100,
    int offset = 0,
  }) async {
    final id = shopId.trim();
    if (_isBadString(id)) return [];

    final url = Uri.parse("$baseUrl/services").replace(queryParameters: {
      "business_id": id,
      "limit": "${limit.clamp(1, 300)}",
      "offset": "${offset.clamp(0, 5000)}",
    });

    try {
      final res = await http.get(url, headers: await _headers(json: false)).timeout(_timeout);

      if (res.statusCode != 200) {
        if (kDebugMode) print("❌ fetchServices failed -> ${res.statusCode} ${res.body}");
        return [];
      }

      final decoded = _safeJsonDecode(res.body);

      if (decoded is Map) {
        final listAny = decoded["services"] ?? decoded["data"] ?? decoded["rows"] ?? decoded["items"];
        if (listAny is List) {
          return listAny
              .where((e) => e is Map)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      }

      if (decoded is List) {
        return decoded
            .where((e) => e is Map)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }

      return [];
    } catch (e) {
      if (kDebugMode) print("❌ fetchServices error: $e");
      return [];
    }
  }

  // ============================================================
  // 📝 4) UPDATE BUSINESS DETAILS
  // PUT /api/business/update/:id
  // returns true/false
  // ============================================================
  static Future<bool> updateBusiness(String businessId, Map<String, dynamic> data) async {
    final id = businessId.trim();
    if (_isBadString(id)) return false;

    final url = Uri.parse("$baseUrl/business/update/$id");

    try {
      final res = await http
          .put(url, headers: await _headers(json: true), body: jsonEncode(data))
          .timeout(const Duration(seconds: 25));

      if (kDebugMode) print("🔵 updateBusiness -> ${res.statusCode} ${res.body}");
      return res.statusCode == 200;
    } catch (e) {
      if (kDebugMode) print("❌ updateBusiness error: $e");
      return false;
    }
  }

  // ============================================================
  // 🖼️ 5) UPLOAD LOGO/COVER
  // POST /api/business/:id/upload
  // returns map with success + logo_url/cover_url if available
  // ============================================================
  static Map<String, dynamic> _pickUploadUrlsFromAny(dynamic decoded) {
    Map<String, dynamic> m = {};
    if (decoded is Map) m = Map<String, dynamic>.from(decoded);

    Map<String, dynamic> b = {};
    final bAny = m["business"] ?? m["shop"] ?? m["data"] ?? m["result"];
    if (bAny is Map) b = Map<String, dynamic>.from(bAny);

    String logo =
    (m["logo_url"] ?? m["logo"] ?? b["logo_url"] ?? b["logo"] ?? "").toString().trim();
    String cover =
    (m["cover_url"] ?? m["cover"] ?? b["cover_url"] ?? b["cover"] ?? "").toString().trim();

    final imagesAny = b["images"];
    if (imagesAny is Map) {
      final im = Map<String, dynamic>.from(imagesAny);
      if (logo.isEmpty) logo = (im["logo_url"] ?? im["logo"] ?? "").toString().trim();
      if (cover.isEmpty) cover = (im["cover_url"] ?? im["cover"] ?? "").toString().trim();
    }

    return {
      if (!_isBadString(logo)) "logo_url": logo,
      if (!_isBadString(cover)) "cover_url": cover,
    };
  }

  static Future<Map<String, dynamic>> uploadBusinessImages(
      String businessId, {
        File? logoFile,
        File? coverFile,
      }) async {
    final id = businessId.trim();
    if (_isBadString(id)) return {"success": false, "message": "Invalid businessId"};

    final token = await _getToken();
    if (token == null || token.isEmpty) return {"success": false, "message": "No token found"};

    final url = Uri.parse("$baseUrl/business/$id/upload");

    try {
      final req = http.MultipartRequest("POST", url);
      req.headers["Authorization"] = "Bearer $token";
      req.headers["Accept"] = "application/json";

      if (logoFile != null && await logoFile.exists()) {
        req.files.add(await http.MultipartFile.fromPath("logo", logoFile.path));
      }
      if (coverFile != null && await coverFile.exists()) {
        req.files.add(await http.MultipartFile.fromPath("cover", coverFile.path));
      }

      if (req.files.isEmpty) return {"success": false, "message": "No files selected"};

      final streamed = await req.send().timeout(const Duration(seconds: 60));
      final res = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 20));

      final decoded = _safeJsonDecode(res.body);

      final okStatus = res.statusCode == 200 || res.statusCode == 201;
      bool okFlag = okStatus;
      if (decoded is Map && decoded.containsKey("success")) {
        okFlag = decoded["success"] == true;
      }

      final urls = _pickUploadUrlsFromAny(decoded);

      return {
        "success": okFlag,
        "statusCode": res.statusCode,
        ...((decoded is Map) ? Map<String, dynamic>.from(decoded) : {"data": decoded}),
        ...urls,
      };
    } catch (e) {
      if (kDebugMode) print("❌ uploadBusinessImages error: $e");
      return {"success": false, "message": e.toString()};
    }
  }

  // ============================================================
  // 🗑️ 6) DELETE PRODUCT
  // DELETE /api/products/delete/:id
  // ============================================================
  static Future<bool> deleteProduct(String productId) async {
    final pid = productId.trim();
    if (_isBadString(pid)) return false;

    final url = Uri.parse("$baseUrl/products/delete/$pid");
    try {
      final res =
      await http.delete(url, headers: await _headers(json: false)).timeout(_timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // 🌍 7) PUBLIC URL BUILDER (FINAL)
  // ============================================================
  static String toPublicUrl(String? path) {
    final raw0 = (path ?? "").trim();
    if (_isBadString(raw0)) return "";

    if (raw0.startsWith("data:") || raw0.startsWith("file://")) return raw0;

    final isWindowsLocal =
        RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(raw0) || raw0.startsWith(r'\\');
    if (isWindowsLocal) return "";

    String raw = raw0.replaceAll('\\', '/').trim();
    raw = raw.replaceAll('"', '').replaceAll("'", '').trim();
    if (_isBadString(raw)) return "";

    if (raw.startsWith("http://") || raw.startsWith("https://")) return Uri.encodeFull(raw);
    if (raw.startsWith("//")) return Uri.encodeFull("https:$raw");

    if (raw.startsWith("adminapi.troonky.in/")) return Uri.encodeFull("https://$raw");
    if (raw.startsWith("/adminapi.troonky.in/")) return Uri.encodeFull("https:/$raw");

    raw = raw.replaceFirst(RegExp(r'^\./'), '');
    raw = raw.replaceFirst(RegExp(r'^/?public/?'), '');
    raw = raw.replaceFirst(RegExp(r'^/?storage/?public/?'), '');
    raw = raw.replaceFirst(RegExp(r'^/?storage/?'), '');

    raw = raw.startsWith("/") ? raw : "/$raw";
    raw = raw.replaceAll(RegExp(r'/{2,}'), '/');

    return Uri.encodeFull("$publicBase$raw");
  }
}
