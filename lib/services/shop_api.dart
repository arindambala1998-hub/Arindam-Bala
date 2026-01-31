// lib/services/shop_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ShopAPI {
  static const String _base = "https://adminapi.troonky.in/api";
  static const Duration _timeout = Duration(seconds: 25);

  // ---------------------------
  // Token + Headers
  // ---------------------------
  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("token");
  }

  static Future<Map<String, String>> _authHeaderOnly() async {
    final token = await _getToken();
    if (token == null || token.trim().isEmpty) {
      throw Exception("AUTH: User not logged in");
    }
    return {"Authorization": "Bearer ${token.trim()}"};
  }

  static Future<Map<String, String>> _jsonHeaders({bool auth = false}) async {
    final h = <String, String>{"Content-Type": "application/json"};
    if (auth) {
      final a = await _authHeaderOnly();
      h.addAll(a);
    } else {
      // optional token (if available)
      final t = await _getToken();
      if (t != null && t.trim().isNotEmpty) {
        h["Authorization"] = "Bearer ${t.trim()}";
      }
    }
    return h;
  }

  static Map<String, dynamic> _safeJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return {"data": decoded};
    } catch (_) {
      return {"raw": raw};
    }
  }

  // -----------------------------------------------------------
  // 🏪 1) Get Shops (pincode filter optional)
  // GET /api/shops?pincode=700001
  // Response: { success:true, shops:[...] }
  // -----------------------------------------------------------
  static Future<List<Map<String, dynamic>>> getShops({String? pincode}) async {
    final q = (pincode != null && pincode.trim().isNotEmpty)
        ? "?pincode=${Uri.encodeQueryComponent(pincode.trim())}"
        : "";

    final uri = Uri.parse("$_base/shops$q");

    try {
      final res = await http.get(uri, headers: await _jsonHeaders()).timeout(_timeout);
      if (res.statusCode != 200) return [];

      final decoded = _safeJson(res.body);
      final list = decoded["shops"];
      if (list is List) return List<Map<String, dynamic>>.from(list);

      // fallback
      if (decoded["data"] is List) return List<Map<String, dynamic>>.from(decoded["data"]);
      return [];
    } catch (_) {
      return [];
    }
  }

  // -----------------------------------------------------------
  // 🏪 2) Get Shop/Business by ID
  // GET /api/shops/:id
  // Response: { success:true, business:{...} }
  // -----------------------------------------------------------
  static Future<Map<String, dynamic>> getShopById(String shopId) async {
    final uri = Uri.parse("$_base/shops/$shopId");

    try {
      final res = await http.get(uri, headers: await _jsonHeaders()).timeout(_timeout);
      if (res.statusCode != 200) return {};

      final decoded = _safeJson(res.body);

      // backend returns { success:true, business:{...} }
      final b = decoded["business"];
      if (b is Map) return Map<String, dynamic>.from(b);

      // fallback
      return decoded;
    } catch (_) {
      return {};
    }
  }

  // -----------------------------------------------------------
  // 🏪 3) Update Shop details
  // PUT /api/shops/:id/update   (AUTH required)
  // Body: JSON (any fields)
  // Response: { success:true, message:"..." }
  // -----------------------------------------------------------
  static Future<bool> updateShop({
    required String shopId,
    required Map<String, dynamic> data,
  }) async {
    final uri = Uri.parse("$_base/shops/$shopId/update");

    try {
      final res = await http
          .put(uri, headers: await _jsonHeaders(auth: true), body: jsonEncode(data))
          .timeout(_timeout);

      if (res.statusCode != 200) {
        // ignore: avoid_print
        print("❌ updateShop failed ${res.statusCode} -> ${res.body}");
      }
      return res.statusCode == 200;
    } catch (e) {
      // ignore: avoid_print
      print("❌ updateShop error: $e");
      return false;
    }
  }

  // -----------------------------------------------------------
  // 🛍️ 4) Get Products of this Shop (backend uses business_id)
  // GET /api/shops/:id/products
  // Response: { success:true, products:[...] }
  // -----------------------------------------------------------
  static Future<List<Map<String, dynamic>>> getShopProducts(String shopId) async {
    final uri = Uri.parse("$_base/shops/$shopId/products");

    try {
      final res = await http.get(uri, headers: await _jsonHeaders()).timeout(_timeout);
      if (res.statusCode != 200) return [];

      final decoded = _safeJson(res.body);
      final list = decoded["products"];
      if (list is List) return List<Map<String, dynamic>>.from(list);

      // fallback
      if (decoded["data"] is List) return List<Map<String, dynamic>>.from(decoded["data"]);
      return [];
    } catch (_) {
      return [];
    }
  }

  // -----------------------------------------------------------
  // 🧰 5) Get Services of this Shop
  // GET /api/shops/:id/services
  // Response: { success:true, services:[...] }
  // -----------------------------------------------------------
  static Future<List<Map<String, dynamic>>> getShopServices(String shopId) async {
    final uri = Uri.parse("$_base/shops/$shopId/services");

    try {
      final res = await http.get(uri, headers: await _jsonHeaders()).timeout(_timeout);
      if (res.statusCode != 200) return [];

      final decoded = _safeJson(res.body);
      final list = decoded["services"];
      if (list is List) return List<Map<String, dynamic>>.from(list);

      // fallback
      if (decoded["data"] is List) return List<Map<String, dynamic>>.from(decoded["data"]);
      return [];
    } catch (_) {
      return [];
    }
  }

  // -----------------------------------------------------------
  // ⚠️ OPTIONAL STUB (Only keep to avoid breaking old UI)
  // If backend doesn't have /api/shops/create, do NOT call it.
  // We'll implement properly when you add backend endpoint.
  // -----------------------------------------------------------
  static Future<Map<String, dynamic>> createShopNotReadyYet() async {
    return {
      "success": false,
      "message": "Shop create endpoint not confirmed in backend. Skip for now.",
    };
  }
}
