// lib/services/services_api.dart (FINAL • BULLETPROOF • Troonky backend compatible)
//
// ✅ Matches your backend reality:
// - Your backend has: GET /api/business/:id/services  (routes/business.js)
// - And legacy probes: /api/services, /api/services/:id, /api/services/add, /api/services/update/:id etc
//
// ✅ Key upgrades vs your current file:
// 1) getBusinessServices() & paged version now prefer /business/:id/services (guaranteed on your backend)
// 2) Multipart upload tries multiple image keys + ALSO retries common endpoint patterns
// 3) toPublicUrl fixed so "uploads/.." becomes "https://host/uploads/.." (not https://host/uploads/.. missing slash issues)
// 4) Normalize service images: supports image_url + image_urls + images(JSON string/list) fallback
// 5) Safe JSON list extraction covers nested wrappers
// 6) Better success detection + 404 continue logic
// 7) No unused imports, clean + production-ready

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ServicesAPI {
  static const String baseUrl = "https://adminapi.troonky.in/api";
  static const Duration _timeout = Duration(seconds: 25);

  // Host for public media URLs (derived from baseUrl)
  static final Uri _api = Uri.parse(baseUrl);

  static String get _origin {
    final portPart =
    (_api.hasPort && _api.port != 80 && _api.port != 443) ? ":${_api.port}" : "";
    return "${_api.scheme}://${_api.host}$portPart";
  }

  // -------------------------------------------------------
  // TOKEN (multi-key fallback)
  // -------------------------------------------------------
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

  // -------------------------------------------------------
  // HEADERS
  // -------------------------------------------------------
  static Future<Map<String, String>> _headers({bool json = false}) async {
    final token = await _getToken();
    return {
      "Accept": "application/json",
      if (json) "Content-Type": "application/json",
      if (token != null && token.isNotEmpty) "Authorization": "Bearer $token",
    };
  }

  // -------------------------------------------------------
  // SAFE JSON
  // -------------------------------------------------------
  static dynamic _tryJson(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return raw;
    }
  }

  static Map<String, dynamic> _safeMap(dynamic decoded) {
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
  }

  static Map<String, dynamic> _safeJsonMap(String raw) {
    final decoded = _tryJson(raw);
    if (decoded is Map) return _safeMap(decoded);
    return {"data": decoded};
  }

  static List<dynamic> _safeJsonList(String raw) {
    final decoded = _tryJson(raw);

    if (decoded is List) return decoded;

    if (decoded is Map) {
      final m = _safeMap(decoded);

      // common wrappers
      for (final key in ["services", "data", "rows", "result", "items"]) {
        final v = m[key];
        if (v is List) return v;
      }

      // nested: {data:{services:[...]}}
      final inner = m["data"];
      if (inner is Map) {
        final mm = _safeMap(inner);
        for (final key in ["services", "rows", "result", "items"]) {
          final v = mm[key];
          if (v is List) return v;
        }
      }
    }

    return [];
  }

  // -------------------------------------------------------
  // ID helpers
  // -------------------------------------------------------
  static String _pickShopIdFromBody(Map<String, dynamic> body) {
    final v = body["businessId"] ??
        body["business_id"] ??
        body["shopId"] ??
        body["shop_id"] ??
        body["businessID"] ??
        body["shopID"];
    return (v ?? "").toString().trim();
  }

  static int? _tryInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static bool _looksSuccess(dynamic decoded, int statusCode) {
    final okStatus = statusCode == 200 || statusCode == 201 || statusCode == 204;
    if (decoded is Map) {
      final m = _safeMap(decoded);
      final s = m["success"];
      final err = m["error"];
      final st = m["status"];
      if (s == true) return true;
      if (err == false) return true;
      if (st == true) return true;

      final msg = (m["message"] ?? "").toString().toLowerCase();
      if (msg.contains("success") || msg.contains("updated") || msg.contains("deleted")) return true;
    }
    return okStatus;
  }

  // -------------------------------------------------------
  // PUBLIC URL FIXER (important)
  // Accepts:
  // - https://...
  // - //domain/...
  // - uploads/x.jpg
  // - /uploads/x.jpg
  // - x.jpg   -> /uploads/x.jpg
  // -------------------------------------------------------
  static String toPublicUrl(String? path) {
    final raw0 = (path ?? "").trim();
    if (raw0.isEmpty) return "";

    if (raw0.startsWith("http://") || raw0.startsWith("https://")) return Uri.encodeFull(raw0);
    if (raw0.startsWith("//")) return Uri.encodeFull("https:$raw0");
    if (raw0.startsWith("adminapi.troonky.in/")) return Uri.encodeFull("https://$raw0");

    String p = raw0.replaceAll('\\', '/').trim();

    // if only filename
    if (!p.contains("/")) p = "uploads/$p";

    // if starts with uploads/ ensure leading slash
    if (p.startsWith("uploads/")) p = "/$p";
    if (!p.startsWith("/")) p = "/$p";

    return Uri.encodeFull("$_origin$p");
  }

  // -------------------------------------------------------
  // Normalize service for UI
  // - set image_url (absolute)
  // - set image_urls (absolute list) if possible
  // -------------------------------------------------------
  static List<dynamic> _asListLoose(dynamic v) {
    if (v == null) return [];
    if (v is List) return v;
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return [];
      if (s.startsWith("[") && s.endsWith("]")) {
        final decoded = _tryJson(s);
        if (decoded is List) return decoded;
      }
      if (s.contains(",")) {
        return s.split(",").map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
    }
    return [];
  }

  static Map<String, dynamic> _normalizeService(Map<String, dynamic> s) {
    final m = Map<String, dynamic>.from(s);

    // base candidates
    final imageUrl = (m["image_url"] ?? m["imageUrl"] ?? "").toString().trim();
    final image = (m["image"] ?? m["photo"] ?? m["cover"] ?? "").toString().trim();

    // images list (string/list)
    final imagesRaw = m["images"] ?? m["image_urls"] ?? m["imageUrls"];
    final images = _asListLoose(imagesRaw)
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();

    // pick main
    String main = "";
    if (imageUrl.isNotEmpty) {
      main = imageUrl;
    } else if (image.isNotEmpty) {
      main = image;
    } else if (images.isNotEmpty) {
      main = images.first;
    }

    m["image_url"] = main.isNotEmpty ? toPublicUrl(main) : "";

    // unify "image"
    if ((m["image"] ?? "").toString().trim().isEmpty && main.isNotEmpty) {
      m["image"] = main;
    }

    // image_urls list (absolute)
    final urls = <String>[];
    if (images.isNotEmpty) {
      for (final x in images) {
        final u = toPublicUrl(x);
        if (u.isNotEmpty) urls.add(u);
      }
    } else if (main.isNotEmpty) {
      urls.add(toPublicUrl(main));
    }
    m["image_urls"] = urls.toSet().toList();

    return m;
  }

  // -------------------------------------------------------
  // 1) GET SERVICES of a business/shop (preferred)
  // ✅ Your backend route: GET /api/business/:id/services
  // -------------------------------------------------------
  static Future<List<Map<String, dynamic>>> getBusinessServices(String businessId) async {
    return getBusinessServicesPaged(businessId, page: 1, limit: 300);
  }

  // -------------------------------------------------------
  // 1b) GET SERVICES (PAGED) - preferred for performance
  // Tries new route first, then legacy probes
  // -------------------------------------------------------
  static Future<List<Map<String, dynamic>>> getBusinessServicesPaged(
      String businessId, {
        int page = 1,
        int limit = 20,
      }) async {
    final id = businessId.trim();
    if (id.isEmpty) return [];

    final urls = <Uri>[
      // ✅ New guaranteed route in your backend (routes/business.js)
      Uri.parse("$baseUrl/business/$id/services?limit=$limit&offset=${(page - 1) * limit}"),

      // legacy probes
      Uri.parse("$baseUrl/services?business_id=$id&page=$page&limit=$limit"),
      Uri.parse("$baseUrl/services?shop_id=$id&page=$page&limit=$limit"),
      Uri.parse("$baseUrl/shops/$id/services?page=$page&limit=$limit"),
      Uri.parse("$baseUrl/services/business/$id?page=$page&limit=$limit"),
      Uri.parse("$baseUrl/services/$id?page=$page&limit=$limit"),
    ];

    for (final url in urls) {
      try {
        final res = await http.get(url, headers: await _headers()).timeout(_timeout);

        if (kDebugMode) {
          debugPrint("🟦 getBusinessServicesPaged GET $url -> ${res.statusCode}");
        }

        if (res.statusCode == 200) {
          final list = _safeJsonList(res.body);

          return list
              .map((e) {
            if (e is Map<String, dynamic>) return e;
            if (e is Map) return Map<String, dynamic>.from(e);
            return <String, dynamic>{};
          })
              .where((m) => m.isNotEmpty)
              .map(_normalizeService)
              .toList();
        }
      } catch (e) {
        if (kDebugMode) debugPrint("❌ getBusinessServicesPaged() ERROR $url → $e");
      }
    }

    return [];
  }

  // -------------------------------------------------------
  // INTERNAL: multipart upload (tries multiple image field keys)
  // -------------------------------------------------------
  static Future<Map<String, dynamic>> _multipartTry({
    required String method, // "POST" | "PUT"
    required Uri url,
    required Map<String, dynamic> body,
    required File imageFile,
  }) async {
    const imageKeys = ["image", "photo", "service_image", "cover", "thumbnail"];

    Map<String, dynamic> last = {
      "success": false,
      "message": "Upload failed",
      "usedUrl": url.toString(),
      "statusCode": 0,
    };

    for (final keyName in imageKeys) {
      try {
        final request = http.MultipartRequest(method, url);
        request.headers.addAll(await _headers()); // no json header for multipart

        body.forEach((key, value) {
          if (value == null) return;
          final s = value.toString().trim();
          if (s.isEmpty) return;
          request.fields[key] = s;
        });

        request.files.add(await http.MultipartFile.fromPath(keyName, imageFile.path));

        final streamed = await request.send().timeout(_timeout);
        final responseBody = await streamed.stream.bytesToString();
        final data = _safeJsonMap(responseBody);

        final success = _looksSuccess(data, streamed.statusCode);

        last = {
          "success": success,
          "message": data["message"] ??
              (success
                  ? (method == "PUT" ? "Update successful" : "Service added successfully")
                  : "Request failed"),
          "data": data,
          "service": data["service"] ?? data["data"] ?? data["result"],
          "statusCode": streamed.statusCode,
          "usedUrl": url.toString(),
          "usedImageKey": keyName,
          "raw": responseBody,
        };

        if (success) return last;
        if (streamed.statusCode == 404) continue;
      } catch (e) {
        last = {
          "success": false,
          "message": "Upload error: $e",
          "usedUrl": url.toString(),
          "usedImageKey": keyName,
        };
        if (kDebugMode) debugPrint("❌ multipartTry ERROR $url key=$keyName → $e");
      }
    }

    return last;
  }

  // -------------------------------------------------------
  // 2) ADD SERVICE (image optional)
  // We try multiple endpoints (because backend may differ)
  // -------------------------------------------------------
  static Future<Map<String, dynamic>> addService({
    required Map<String, dynamic> body,
    File? imageFile,
  }) async {
    final shopId = _pickShopIdFromBody(body);

    final primaryUrl = shopId.isEmpty ? null : Uri.parse("$baseUrl/shops/$shopId/services");
    final candidates = <Uri>[
      if (primaryUrl != null) primaryUrl,
      Uri.parse("$baseUrl/services/add"),
      Uri.parse("$baseUrl/services"),
      // sometimes backend uses /service/add
      Uri.parse("$baseUrl/service/add"),
    ];

    // normalize ids for backend acceptance
    final normalizedBody = Map<String, dynamic>.from(body);
    if (shopId.isNotEmpty) {
      final intId = _tryInt(shopId);
      normalizedBody["business_id"] = intId ?? shopId;
      normalizedBody["shop_id"] = intId ?? shopId;
      normalizedBody["businessId"] = intId ?? shopId;
      normalizedBody["shopId"] = intId ?? shopId;
    }

    for (final url in candidates) {
      try {
        // ✅ Multipart (with image)
        if (imageFile != null) {
          final r = await _multipartTry(
            method: "POST",
            url: url,
            body: normalizedBody,
            imageFile: imageFile,
          );
          if (r["success"] == true) return r;
          // if 404 => try next endpoint
          if ((r["statusCode"] ?? 0) == 404) continue;
          // otherwise still return, so UI can show backend error message
          return r;
        }

        // ✅ JSON (no image)
        final res = await http
            .post(url, headers: await _headers(json: true), body: jsonEncode(normalizedBody))
            .timeout(_timeout);

        final data = _safeJsonMap(res.body);
        final success = _looksSuccess(data, res.statusCode);

        if (!success && res.statusCode == 404) continue;

        return {
          "success": success,
          "message": data["message"] ?? (success ? "Service added successfully" : "Service add failed"),
          "data": data,
          "service": data["service"] ?? data["data"] ?? data["result"],
          "statusCode": res.statusCode,
          "usedUrl": url.toString(),
          "raw": res.body,
        };
      } catch (e) {
        if (kDebugMode) debugPrint("❌ addService() ERROR $url → $e");
      }
    }

    return {
      "success": false,
      "message": "Service upload failed",
      "error": "All endpoint attempts failed",
    };
  }

  // -------------------------------------------------------
  // 3) UPDATE SERVICE (image optional)
  // -------------------------------------------------------
  static Future<Map<String, dynamic>> updateService(
      String id,
      Map<String, dynamic> body, {
        File? imageFile,
      }) async {
    final sid = id.trim();
    if (sid.isEmpty) return {"success": false, "message": "Service id missing"};

    final normalizedBody = Map<String, dynamic>.from(body);
    final shopId = _pickShopIdFromBody(normalizedBody);
    if (shopId.isNotEmpty) {
      final intId = _tryInt(shopId);
      normalizedBody["business_id"] = intId ?? shopId;
      normalizedBody["shop_id"] = intId ?? shopId;
      normalizedBody["businessId"] = intId ?? shopId;
      normalizedBody["shopId"] = intId ?? shopId;
    }

    final candidates = <Uri>[
      Uri.parse("$baseUrl/services/update/$sid"),
      Uri.parse("$baseUrl/services/edit/$sid"),
      Uri.parse("$baseUrl/services/$sid"),
      // sometimes: /service/update/:id
      Uri.parse("$baseUrl/service/update/$sid"),
      Uri.parse("$baseUrl/service/$sid"),
    ];

    for (final url in candidates) {
      try {
        if (imageFile != null) {
          final r = await _multipartTry(
            method: "PUT",
            url: url,
            body: normalizedBody,
            imageFile: imageFile,
          );
          if (r["success"] == true) return r;
          if ((r["statusCode"] ?? 0) == 404) continue;
          return r;
        }

        final res = await http
            .put(url, headers: await _headers(json: true), body: jsonEncode(normalizedBody))
            .timeout(_timeout);

        final data = _safeJsonMap(res.body);
        final success = _looksSuccess(data, res.statusCode);

        if (!success && res.statusCode == 404) continue;

        return {
          "success": success,
          "data": data,
          "message": data["message"] ?? (success ? "Update successful" : "Update failed"),
          "statusCode": res.statusCode,
          "usedUrl": url.toString(),
          "raw": res.body,
        };
      } catch (e) {
        if (kDebugMode) debugPrint("❌ updateService() ERROR $url → $e");
      }
    }

    return {
      "success": false,
      "message": "Update service failed",
      "error": "All endpoint attempts failed",
    };
  }

  // -------------------------------------------------------
  // 4) DELETE SERVICE
  // -------------------------------------------------------
  static Future<Map<String, dynamic>> deleteService(String id) async {
    final sid = id.trim();
    if (sid.isEmpty) return {"success": false, "message": "Service id missing"};

    final candidates = <Uri>[
      Uri.parse("$baseUrl/services/delete/$sid"),
      Uri.parse("$baseUrl/services/remove/$sid"),
      Uri.parse("$baseUrl/services/$sid"),
      Uri.parse("$baseUrl/service/delete/$sid"),
      Uri.parse("$baseUrl/service/$sid"),
    ];

    for (final url in candidates) {
      try {
        final res = await http.delete(url, headers: await _headers()).timeout(_timeout);
        final data = _safeJsonMap(res.body);

        final success = _looksSuccess(data, res.statusCode);

        if (!success && res.statusCode == 404) continue;

        return {
          "success": success,
          "data": data,
          "message": data["message"] ?? (success ? "Deletion successful" : "Deletion failed"),
          "statusCode": res.statusCode,
          "usedUrl": url.toString(),
          "raw": res.body,
        };
      } catch (e) {
        if (kDebugMode) debugPrint("❌ deleteService() ERROR $url → $e");
      }
    }

    return {
      "success": false,
      "message": "Delete failed",
      "error": "All endpoint attempts failed",
    };
  }
}
