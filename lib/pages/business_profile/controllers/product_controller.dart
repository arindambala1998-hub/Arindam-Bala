// lib/pages/business_profile/controllers/product_controller.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/product_model.dart';

class ProductController extends ChangeNotifier {
  static const String _baseUrl = "https://adminapi.troonky.in/api";
  static const Duration _timeout = Duration(seconds: 25);

  List<ProductModel> products = [];
  List<ProductModel> localOffers = [];
  List<ProductModel> globalOffers = [];

  bool isLoading = false;

  /// After add/update, backend may return the created/updated product.
  /// We keep it here so calling pages can do optimistic UI updates.
  Map<String, dynamic>? lastSavedProduct;
  String? lastAction; // 'created' | 'updated'

  // ---------------------------
  // Helpers
  // ---------------------------
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

  String _asIdString(dynamic v) {
    final s = _asString(v).trim();
    if (s.isEmpty) return "";
    final low = s.toLowerCase();
    if (low == "null" || low == "undefined") return "";
    return s;
  }

  void _setLoading(bool v) {
    isLoading = v;
    notifyListeners();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString("token");
    if (t == null) return null;
    final s = t.trim();
    return s.isEmpty ? null : s;
  }

  Future<Map<String, String>> _jsonHeaders() async {
    final token = await _getToken();
    return {
      "Accept": "application/json",
      "Content-Type": "application/json",
      if (token != null) "Authorization": "Bearer $token",
    };
  }

  Future<Map<String, String>> _authHeaderOnly() async {
    final token = await _getToken();
    return {
      "Accept": "application/json",
      if (token != null) "Authorization": "Bearer $token",
    };
  }

  Map<String, dynamic> _safeJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return {"data": decoded};
    } catch (_) {
      return {"raw": raw};
    }
  }

  Future<Map<String, dynamic>> _safeJsonFromStreamed(http.StreamedResponse sres) async {
    final text = await sres.stream.bytesToString();
    return _safeJson(text);
  }

  bool _looksOk(Map<String, dynamic> decoded) {
    if (decoded["success"] == true) return true;
    if (decoded["ok"] == true) return true;
    if (decoded["status"] == "success") return true;
    if (decoded["product"] != null) return true;
    if (decoded["product_id"] != null) return true;
    if (decoded["id"] != null) return true;

    // some backends return only message even on success
    final msg = decoded["message"]?.toString().trim() ?? "";
    if (msg.isNotEmpty && !msg.toLowerCase().contains("error")) return true;

    return false;
  }

  List<String> _asStringList(dynamic v) {
    if (v is List) {
      return v.map((e) => (e ?? "").toString()).where((s) => s.trim().isNotEmpty).toList();
    }
    return [];
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return {};
  }

  Map<String, dynamic>? _extractProduct(Map<String, dynamic> decoded) {
    try {
      final p = decoded["product"] ?? decoded["data"] ?? decoded["result"];
      if (p is Map<String, dynamic>) return p;
      if (p is Map) return Map<String, dynamic>.from(p);
      // Some APIs return { id: ... } only
      if (decoded["id"] != null || decoded["product_id"] != null) {
        return {
          "id": decoded["id"] ?? decoded["product_id"],
          ...?(_asMap(decoded["payload"])),
        };
      }
    } catch (_) {}
    return null;
  }

  void _upsertLocal(Map<String, dynamic> product, {bool atTop = false}) {
    try {
      final model = ProductModel.fromJson(product);
      final idx = products.indexWhere((p) => p.id == model.id);

      if (idx >= 0) {
        products[idx] = model;
        if (atTop && idx != 0) {
          final moved = products.removeAt(idx);
          products.insert(0, moved);
        }
      } else {
        // new product
        if (atTop) {
          products.insert(0, model);
        } else {
          products.add(model);
        }
      }

      notifyListeners();
    } catch (_) {
      // ignore parsing error; list will refresh from server later
    }
  }

  // business_id sometimes int sometimes string (make compatible)
  dynamic _businessIdValue(String businessIdStr) {
    final n = int.tryParse(businessIdStr);
    return n ?? businessIdStr;
  }

  // -----------------------------------------------------------
  // ✅ 1) Fetch products by businessId
  // TRY:
  //   A) GET /api/shops/:shopId/products?page=1&limit=200
  //   B) fallback GET /api/products/:businessId
  // -----------------------------------------------------------
  Future<void> fetchProducts(String businessId) async {
    final id = _asIdString(businessId);
    if (id.isEmpty) {
      products = [];
      notifyListeners();
      return;
    }

    try {
      _setLoading(true);

      final headers = await _jsonHeaders();

      // A) shops route
      final urlA = Uri.parse("$_baseUrl/shops/$id/products?page=1&limit=200");
      final resA = await http.get(urlA, headers: headers).timeout(_timeout);

      if (resA.statusCode == 200) {
        final decoded = _safeJson(resA.body);
        final List data = (decoded["products"] is List) ? decoded["products"] : [];
        products = data.map((p) => ProductModel.fromJson(p)).toList();
        return;
      }

      // B) fallback products route
      final urlB = Uri.parse("$_baseUrl/products/$id");
      final resB = await http.get(urlB, headers: headers).timeout(_timeout);

      if (resB.statusCode == 200) {
        final decoded = _safeJson(resB.body);
        final List data = (decoded["products"] is List) ? decoded["products"] : [];
        products = data.map((p) => ProductModel.fromJson(p)).toList();
      } else {
        debugPrint("❌ fetchProducts failed: A=${resA.statusCode}, B=${resB.statusCode}");
        products = [];
      }
    } catch (e) {
      debugPrint("❌ Fetch Products Error: $e");
      products = [];
    } finally {
      _setLoading(false);
    }
  }

  // -----------------------------------------------------------
  // ✅ 2) Add OR Update wrapper (AddProductPage uses this)
  // -----------------------------------------------------------
  Future<bool> saveOrUpdateProduct(
      Map<String, dynamic> productData, {
        required bool editMode,
      }) async {
    if (editMode) return updateProduct(productData);
    return addProduct(productData);
  }

  // -----------------------------------------------------------
  // ✅ Build payload (common) from AddProductPage map (BACKEND MATCH)
  // - Offer fields removed
  // - Added: open_box_delivery, available_pincodes, discount_percent
  // - existing_images kept for edit
  // -----------------------------------------------------------
  Map<String, dynamic> _buildPayload(Map<String, dynamic> d) {
    final businessIdStr = _asIdString(d["business_id"]);

    final name = _asString(d["name"]).trim();
    final description = _asString(d["description"]).trim();

    // ✅ keep numbers as numbers (not strings) to avoid backend parsing issues
    final price = _asDouble(d["price"], fallback: 0);
    final oldPrice = _asDouble(d["old_price"], fallback: 0);

    final stock = _asInt(d["stock"], fallback: 0);
    final category = _asString(d["category"], fallback: "Others").trim();

    final brand = _asString(d["brand"]).trim();
    final material = _asString(d["material"]).trim();
    final weight = _asString(d["weight"]).trim();

    final colors = _asStringList(d["colors"]);
    final sizes = _asStringList(d["sizes"]);
    final specs = _asMap(d["specs"]);

    final returnDays = _asInt(d["return_days"], fallback: 7);
    final codAvailable = d["cod_available"] == true;
    final openBoxDelivery = d["open_box_delivery"] == true;
    final isOriginal = d["is_original"] != false;

    final availablePincodes = _asStringList(d["available_pincodes"]);
    final discountPercent = _asDouble(d["discount_percent"], fallback: 0);

    // ✅ keep old images (important for edit)
    final existingImages = _asStringList(d["existing_images"]);

    // ✅ Backend routes in your project use MySQL 'products' table with:
    // name, description, category, price, offer_price?, stock, business_id, images...
    // We send only what AddProductPage guarantees.
    return <String, dynamic>{
      "business_id": _businessIdValue(businessIdStr),

      "name": name,
      "description": description,
      "category": category,

      "price": price,
      "old_price": oldPrice,
      "stock": stock,

      // optional meta
      "brand": brand,
      "material": material,
      "weight": weight,
      "colors": colors,
      "sizes": sizes,
      "specs": specs,

      // delivery & trust
      "return_days": returnDays,
      "available_pincodes": availablePincodes,
      "cod_available": codAvailable,
      "open_box_delivery": openBoxDelivery,
      "is_original": isOriginal,

      // badge/helper
      "discount_percent": discountPercent,

      // keep existing server images in edit
      "existing_images": existingImages,
    };
  }

  List<File> _extractFiles(dynamic v) {
    if (v is List<File>) return v;
    if (v is List) {
      final out = <File>[];
      for (final e in v) {
        if (e is File) out.add(e);
      }
      return out;
    }
    return <File>[];
  }

  // -----------------------------------------------------------
  // Multipart sender (images upload + fields)
  // - fields: List/Map => jsonEncode string
  // - images: send "images" as multi (do NOT send "image" duplicate; causes duplicates on some backends)
  // -----------------------------------------------------------
  Future<bool> _sendMultipart({
    required String method,
    required Uri url,
    required Map<String, dynamic> fields,
    required List<File> imageFiles,
  }) async {
    try {
      final req = http.MultipartRequest(method, url);
      req.headers.addAll(await _authHeaderOnly());

      // fields as string (List/Map -> json)
      fields.forEach((k, v) {
        if (v == null) return;

        if (v is List || v is Map) {
          req.fields[k] = jsonEncode(v);
        } else {
          req.fields[k] = v.toString();
        }
      });

      // ✅ Attach images as "images"
      for (final f in imageFiles) {
        if (!f.existsSync()) continue;

        final fileName = f.path.split(Platform.pathSeparator).last;
        req.files.add(
          await http.MultipartFile.fromPath(
            "images",
            f.path,
            filename: fileName,
          ),
        );
      }

      final streamed = await req.send().timeout(_timeout);
      final decoded = await _safeJsonFromStreamed(streamed);

      if (streamed.statusCode == 200 || streamed.statusCode == 201) {
        final ok = _looksOk(decoded);
        if (ok) {
          lastSavedProduct = _extractProduct(decoded);
        }
        return ok;
      }

      debugPrint("❌ multipart failed: ${streamed.statusCode} $decoded");
      return false;
    } catch (e) {
      debugPrint("❌ multipart error: $e");
      return false;
    }
  }

  // -----------------------------------------------------------
  // JSON sender (no new images)
  // -----------------------------------------------------------
  Future<bool> _sendJson({
    required String method,
    required Uri url,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final headers = await _jsonHeaders();
      late http.Response res;

      if (method == "POST") {
        res = await http.post(url, headers: headers, body: jsonEncode(payload)).timeout(_timeout);
      } else if (method == "PUT") {
        res = await http.put(url, headers: headers, body: jsonEncode(payload)).timeout(_timeout);
      } else {
        throw Exception("Unsupported method: $method");
      }

      final decoded = _safeJson(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        final ok = _looksOk(decoded);
        if (ok) {
          lastSavedProduct = _extractProduct(decoded);
        }
        return ok;
      }

      debugPrint("❌ json failed: ${res.statusCode} $decoded");
      return false;
    } catch (e) {
      debugPrint("❌ json error: $e");
      return false;
    }
  }

  // -----------------------------------------------------------
  // ✅ 3) Add product
  // POST /api/products/add
  // - If has new images => multipart
  // - Else => json
  // -----------------------------------------------------------
  Future<bool> addProduct(Map<String, dynamic> productData) async {
    final businessId = _asIdString(productData["business_id"]);
    final name = _asString(productData["name"]).trim();

    if (businessId.isEmpty || name.isEmpty) {
      debugPrint("❌ addProduct: business_id/name missing");
      return false;
    }

    final payload = _buildPayload(productData);

    // new picked files
    final newFiles = _extractFiles(productData["images"]);
    final url = Uri.parse("$_baseUrl/products/add");

    lastSavedProduct = null;
    lastAction = 'created';
    final ok = newFiles.isNotEmpty
        ? await _sendMultipart(method: "POST", url: url, fields: payload, imageFiles: newFiles)
        : await _sendJson(method: "POST", url: url, payload: payload);

    if (ok) {
      final prodMap = lastSavedProduct;
      if (prodMap != null && prodMap.isNotEmpty) {
        _upsertLocal(prodMap, atTop: true);
      } else {
        // fallback: one-time sync
        await fetchProducts(businessId);
      }
      return true;
    }

    return false;
  }

  // -----------------------------------------------------------
  // ✅ 4) Update product
  // PUT /api/products/update/:id
  // -----------------------------------------------------------
  Future<bool> updateProduct(Map<String, dynamic> productData) async {
    final businessId = _asIdString(productData["business_id"]);
    final productId = _asIdString(productData["product_id"] ?? productData["id"]);
    final name = _asString(productData["name"]).trim();

    if (businessId.isEmpty || productId.isEmpty || name.isEmpty) {
      debugPrint("❌ updateProduct: business_id/product_id/name missing");
      return false;
    }

    final payload = _buildPayload(productData);
    // backend sometimes expects product_id too
    payload["product_id"] = productId;

    final newFiles = _extractFiles(productData["images"]);
    final url = Uri.parse("$_baseUrl/products/update/$productId");

    lastSavedProduct = null;
    lastAction = 'updated';
    final ok = newFiles.isNotEmpty
        ? await _sendMultipart(method: "PUT", url: url, fields: payload, imageFiles: newFiles)
        : await _sendJson(method: "PUT", url: url, payload: payload);

    if (ok) {
      final prodMap = lastSavedProduct;
      if (prodMap != null && prodMap.isNotEmpty) {
        _upsertLocal(prodMap);
      } else {
        await fetchProducts(businessId);
      }
      return true;
    }

    return false;
  }

  // -----------------------------------------------------------
  // ✅ 5) Delete product
  // DELETE /api/products/delete/:id
  // -----------------------------------------------------------
  Future<bool> deleteProduct(String id, {String? businessId}) async {
    try {
      final pid = _asIdString(id);
      if (pid.isEmpty) return false;

      final url = Uri.parse("$_baseUrl/products/delete/$pid");
      final res = await http.delete(url, headers: await _jsonHeaders()).timeout(_timeout);

      if (res.statusCode == 200) {
        products.removeWhere((p) => p.id == pid);
        localOffers.removeWhere((p) => p.id == pid);
        globalOffers.removeWhere((p) => p.id == pid);
        notifyListeners();

        final bid = _asIdString(businessId);
        if (bid.isNotEmpty) {
          await fetchProducts(bid);
        }
        return true;
      }

      debugPrint("❌ deleteProduct failed: ${res.statusCode} ${res.body}");
      return false;
    } catch (e) {
      debugPrint("❌ Delete Error: $e");
      return false;
    }
  }

  // -----------------------------------------------------------
  // ⚠️ Offers (যদি backend থাকে)
  // -----------------------------------------------------------
  Future<void> fetchLocalOffers(String pincode) async {
    try {
      _setLoading(true);

      final url = Uri.parse("$_baseUrl/offers/local?pincode=$pincode");
      final res = await http.get(url, headers: await _jsonHeaders()).timeout(_timeout);

      if (res.statusCode == 200) {
        final decoded = _safeJson(res.body);
        final List data = (decoded["offers"] is List) ? decoded["offers"] : [];
        localOffers = data.map((p) => ProductModel.fromJson(p)).toList();
      } else {
        localOffers = [];
      }
    } catch (e) {
      debugPrint("❌ Local Offers Error: $e");
      localOffers = [];
    } finally {
      _setLoading(false);
    }
  }

  Future<void> fetchGlobalOffers() async {
    try {
      _setLoading(true);

      final url = Uri.parse("$_baseUrl/offers/global");
      final res = await http.get(url, headers: await _jsonHeaders()).timeout(_timeout);

      if (res.statusCode == 200) {
        final decoded = _safeJson(res.body);
        final List data = (decoded["offers"] is List) ? decoded["offers"] : [];
        globalOffers = data.map((p) => ProductModel.fromJson(p)).toList();
      } else {
        globalOffers = [];
      }
    } catch (e) {
      debugPrint("❌ Global Offers Error: $e");
      globalOffers = [];
    } finally {
      _setLoading(false);
    }
  }

  // -----------------------------------------------------------
  // 🔍 Search
  // -----------------------------------------------------------
  List<ProductModel> searchProducts(String query) {
    if (query.trim().isEmpty) return products;
    final q = query.toLowerCase().trim();
    return products.where((p) => p.name.toLowerCase().contains(q)).toList();
  }
}
