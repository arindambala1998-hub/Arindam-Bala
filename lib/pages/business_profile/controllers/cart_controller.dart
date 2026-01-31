import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CartController extends ChangeNotifier {
  static const String _storageKey = "cart_items_v2";

  final List<Map<String, dynamic>> _cart = [];
  List<Map<String, dynamic>> get cart => List.unmodifiable(_cart);

  CartController() {
    loadCart(); // async best effort
  }

  // ----------------- safe helpers -----------------
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
    if (v is String) {
      final s = v.replaceAll("₹", "").trim();
      return double.tryParse(s) ?? fallback;
    }
    return fallback;
  }

  String _asString(dynamic v, {String fallback = ""}) =>
      v == null ? fallback : v.toString();

  List<String> _asStringList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => (e ?? "").toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return [];
  }

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

  int _resolveProductIdInt(Map<String, dynamic> p) {
    final v = p["product_id"] ?? p["productId"] ?? p["id"] ?? p["_id"];
    final id = _asInt(v, fallback: 0);
    if (id > 0) return id;

    final s = (v ?? "").toString().trim();
    return int.tryParse(s) ?? 0;
  }

  int _resolveBusinessIdInt(Map<String, dynamic> p) {
    final v = p["business_id"] ?? p["shop_id"] ?? p["businessId"] ?? p["shopId"];
    final id = _asInt(v, fallback: 0);
    if (id > 0) return id;

    final s = (v ?? "").toString().trim();
    return int.tryParse(s) ?? 0;
  }

  String _resolveImageUrl(Map<String, dynamic> p) {
    final one =
    _asString(p["image_url"] ?? p["image"] ?? "", fallback: "").trim();
    if (one.isNotEmpty) return one;

    final imgs = _asStringList(p["images"]);
    if (imgs.isNotEmpty) return imgs.first;

    return "";
  }

  String _itemKey({
    required int businessId,
    required int productId,
    required String color,
    required String size,
  }) {
    return "$businessId|$productId|${color.trim()}|${size.trim()}";
  }

  bool _isOpenBoxAllowed(Map<String, dynamic> p) {
    // strict: only true if backend says true/1/yes
    return _asBool01(p["open_box_delivery"], fallback: false);
  }

  // ✅ prevent double-notify during load/save burst
  bool _loadedOnce = false;
  bool _saving = false;

  // ----------------- persistence -----------------
  Future<void> loadCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);

      _cart.clear();

      if (raw == null || raw.trim().isEmpty) {
        _loadedOnce = true;
        notifyListeners();
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final x in decoded) {
          if (x is! Map) continue;

          final m = Map<String, dynamic>.from(x);

          final pid = _resolveProductIdInt(m);
          final bid = _resolveBusinessIdInt(m);
          final qty = _asInt(m["qty"], fallback: 1);

          if (pid <= 0 || bid <= 0) continue;

          final base = _asDouble(m["price"], fallback: 0);
          final offer = _asDouble(m["offer_price"], fallback: 0);
          final unit = _asDouble(
            m["unit_price"],
            fallback: (offer > 0 ? offer : base),
          );

          final color = _asString(m["selected_color"]).trim();
          final size = _asString(m["selected_size"]).trim();

          final key = _asString(m["key"]).trim().isNotEmpty
              ? _asString(m["key"]).trim()
              : _itemKey(businessId: bid, productId: pid, color: color, size: size);

          // open box strict
          final openBox = _isOpenBoxAllowed(m);

          // ✅ DO NOT silently drop legacy items; keep them but mark blocked
          // (UI add/updateQuantity will still block due to openBox rule)
          _cart.add({
            "key": key,
            "product_id": pid,
            "id": pid,
            "business_id": bid,
            "shop_id": bid,
            "name": _asString(m["name"], fallback: "Item"),
            "image_url": _resolveImageUrl(m),
            "image": _resolveImageUrl(m),
            "price": base,
            "offer_price": offer,
            "unit_price": unit,
            "qty": qty <= 0 ? 1 : qty,
            "selected_color": color,
            "selected_size": size,
            "stock": _asInt(m["stock"], fallback: -1),
            "open_box_delivery": openBox,
            "available_pincodes": m["available_pincodes"],
            "_id": _asString(m["_id"] ?? ""),
          });
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint("❌ Cart load error: $e");
      _cart.clear();
    }

    _loadedOnce = true;
    notifyListeners();
  }

  Future<void> _saveCart() async {
    if (_saving) return;
    _saving = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(_cart));
    } catch (e) {
      if (kDebugMode) debugPrint("❌ Cart save error: $e");
    } finally {
      _saving = false;
    }
  }

  // ----------------- core: normalize incoming item -----------------
  Map<String, dynamic>? _normalizeIncoming(
      Map<String, dynamic> product, {
        int qty = 1,
        String selectedColor = "",
        String selectedSize = "",
      }) {
    final pid = _resolveProductIdInt(product);
    final bid = _resolveBusinessIdInt(product);

    if (pid <= 0 || bid <= 0) return null;

    final mapQty = _asInt(product["qty"], fallback: 1);
    final addQty = (qty != 1) ? qty : mapQty;

    final mapColor = _asString(product["selected_color"]).trim();
    final mapSize = _asString(product["selected_size"]).trim();

    final color =
    selectedColor.trim().isNotEmpty ? selectedColor.trim() : mapColor;
    final size = selectedSize.trim().isNotEmpty ? selectedSize.trim() : mapSize;

    final base = _asDouble(product["price"], fallback: 0);
    final offer = _asDouble(product["offer_price"], fallback: 0);
    final unit = _asDouble(
      product["unit_price"],
      fallback: (offer > 0 ? offer : base),
    );

    final name = _asString(product["name"], fallback: "Item").trim();
    final img = _resolveImageUrl(product);

    final stock = _asInt(
      product["stock"],
      fallback: _asInt(product["quantity"], fallback: -1),
    );

    final openBox = _isOpenBoxAllowed(product);

    final key = _itemKey(businessId: bid, productId: pid, color: color, size: size);

    return {
      "key": key,
      "product_id": pid,
      "id": pid,
      "business_id": bid,
      "shop_id": bid,
      "name": name.isEmpty ? "Item" : name,
      "image_url": img,
      "image": img,
      "price": base,
      "offer_price": offer,
      "unit_price": unit,
      "qty": addQty <= 0 ? 1 : addQty,
      "selected_color": color,
      "selected_size": size,
      "stock": stock,
      "open_box_delivery": openBox,
      "available_pincodes": product["available_pincodes"],
      "_id": _asString(product["_id"] ?? product["id"] ?? ""),
    };
  }

  // ----------------- rules -----------------
  bool _canAddToCart(Map<String, dynamic> item) {
    // ✅ rule: open_box_delivery must be true
    if (!_isOpenBoxAllowed(item)) return false;

    // stock check (if provided)
    final stock = _asInt(item["stock"], fallback: -1);
    if (stock == 0) return false;

    return true;
  }

  int _clampQtyToStock(int qty, int stock) {
    if (qty <= 0) return 1;
    if (stock >= 0 && qty > stock) return stock <= 0 ? 1 : stock;
    return qty;
  }

  // ----------------- public APIs -----------------

  /// ✅ Add product/item to cart
  /// Returns:
  /// - true: added/updated
  /// - false: blocked (open_box OFF / out of stock / invalid ids)
  bool addToCart(
      Map<String, dynamic> product, {
        int qty = 1,
        String selectedColor = "",
        String selectedSize = "",
      }) {
    // if loadCart not finished yet, still allow (it will just add to empty list)
    final incoming = _normalizeIncoming(
      product,
      qty: qty,
      selectedColor: selectedColor,
      selectedSize: selectedSize,
    );
    if (incoming == null) return false;

    if (!_canAddToCart(incoming)) return false;

    final key = _asString(incoming["key"]);
    final addQty = _asInt(incoming["qty"], fallback: 1);

    final idx = _cart.indexWhere((it) => _asString(it["key"]) == key);

    if (idx != -1) {
      final current = _asInt(_cart[idx]["qty"], fallback: 1);
      final stock = _asInt(_cart[idx]["stock"], fallback: -1);

      int next = current + (addQty <= 0 ? 1 : addQty);
      next = _clampQtyToStock(next, stock);

      _cart[idx]["qty"] = next;

      // keep latest
      _cart[idx]["open_box_delivery"] = _isOpenBoxAllowed(incoming);
      _cart[idx]["image_url"] = _resolveImageUrl(incoming);
      _cart[idx]["image"] = _resolveImageUrl(incoming);
      _cart[idx]["price"] = _asDouble(incoming["price"], fallback: _asDouble(_cart[idx]["price"]));
      _cart[idx]["offer_price"] = _asDouble(incoming["offer_price"], fallback: _asDouble(_cart[idx]["offer_price"]));
      _cart[idx]["unit_price"] = _asDouble(incoming["unit_price"], fallback: _asDouble(_cart[idx]["unit_price"]));
      _cart[idx]["stock"] = _asInt(incoming["stock"], fallback: _asInt(_cart[idx]["stock"], fallback: -1));
    } else {
      final stock = _asInt(incoming["stock"], fallback: -1);
      int next = _asInt(incoming["qty"], fallback: 1);
      next = _clampQtyToStock(next, stock);

      incoming["qty"] = next;
      _cart.add(incoming);
    }

    _saveCart();
    notifyListeners();
    return true;
  }

  /// ✅ Add by key (useful from UI)
  /// Returns false if item blocked by rule
  bool addByKey(String key, {int qty = 1}) {
    final idx = _cart.indexWhere((it) => _asString(it["key"]) == key);
    if (idx == -1) return false;

    if (!_isOpenBoxAllowed(_cart[idx])) return false;

    final current = _asInt(_cart[idx]["qty"], fallback: 1);
    final stock = _asInt(_cart[idx]["stock"], fallback: -1);

    int next = current + (qty <= 0 ? 1 : qty);
    next = _clampQtyToStock(next, stock);

    _cart[idx]["qty"] = next;
    _saveCart();
    notifyListeners();
    return true;
  }

  /// ✅ Decrement by key
  void decrementByKey(String key, {int qty = 1}) {
    final idx = _cart.indexWhere((it) => _asString(it["key"]) == key);
    if (idx == -1) return;

    final current = _asInt(_cart[idx]["qty"], fallback: 1);
    final next = current - (qty <= 0 ? 1 : qty);

    if (next <= 0) {
      _cart.removeAt(idx);
    } else {
      _cart[idx]["qty"] = next;
    }

    _saveCart();
    notifyListeners();
  }

  /// ✅ Remove by key
  void removeByKey(String key) {
    _cart.removeWhere((it) => _asString(it["key"]) == key);
    _saveCart();
    notifyListeners();
  }

  /// ✅ Remove by index
  void removeItem(int index) {
    if (index < 0 || index >= _cart.length) return;
    _cart.removeAt(index);
    _saveCart();
    notifyListeners();
  }

  /// ✅ Update quantity (index)
  /// Returns false if blocked (open box OFF)
  bool updateQuantity(int index, bool increase) {
    if (index < 0 || index >= _cart.length) return false;

    if (!_isOpenBoxAllowed(_cart[index])) return false;

    final q = _asInt(_cart[index]["qty"], fallback: 1);
    int next = increase ? q + 1 : q - 1;

    final stock = _asInt(_cart[index]["stock"], fallback: -1);
    next = _clampQtyToStock(next, stock);

    if (next <= 0) {
      _cart.removeAt(index);
    } else {
      _cart[index]["qty"] = next;
    }

    _saveCart();
    notifyListeners();
    return true;
  }

  /// ✅ Set exact qty (index)
  /// Returns false if blocked (open box OFF)
  bool setQuantity(int index, int qty) {
    if (index < 0 || index >= _cart.length) return false;

    if (!_isOpenBoxAllowed(_cart[index])) return false;

    if (qty <= 0) {
      _cart.removeAt(index);
    } else {
      final stock = _asInt(_cart[index]["stock"], fallback: -1);
      final next = _clampQtyToStock(qty, stock);
      _cart[index]["qty"] = next;
    }

    _saveCart();
    notifyListeners();
    return true;
  }

  /// ✅ Update options (color/size) and merge if same key exists
  /// Returns false if blocked (open box OFF)
  bool updateOptions(int index, {String? color, String? size}) {
    if (index < 0 || index >= _cart.length) return false;

    if (!_isOpenBoxAllowed(_cart[index])) return false;

    final item = _cart[index];

    final pid = _asInt(item["product_id"] ?? item["id"], fallback: 0);
    final bid = _asInt(item["business_id"] ?? item["shop_id"], fallback: 0);
    if (pid <= 0 || bid <= 0) return false;

    final newColor = (color ?? _asString(item["selected_color"])).trim();
    final newSize = (size ?? _asString(item["selected_size"])).trim();

    final newKey =
    _itemKey(businessId: bid, productId: pid, color: newColor, size: newSize);

    item["selected_color"] = newColor;
    item["selected_size"] = newSize;
    item["key"] = newKey;

    // ✅ merge if another item already has same key
    final otherIndex = _cart.indexWhere((x) => _asString(x["key"]) == newKey);
    if (otherIndex != -1 && otherIndex != index) {
      final q1 = _asInt(_cart[otherIndex]["qty"], fallback: 1);
      final q2 = _asInt(item["qty"], fallback: 1);
      int merged = q1 + q2;

      final stock = _asInt(_cart[otherIndex]["stock"], fallback: -1);
      merged = _clampQtyToStock(merged, stock);

      _cart[otherIndex]["qty"] = merged;

      // remove current item (careful index shift)
      _cart.removeAt(index);
    }

    _saveCart();
    notifyListeners();
    return true;
  }

  Future<void> clearCart() async {
    _cart.clear();
    await _saveCart();
    notifyListeners();
  }

  Future<void> reset() async => clearCart();

  // ----------------- totals -----------------
  int get totalItems {
    int t = 0;
    for (final it in _cart) {
      t += _asInt(it["qty"], fallback: 1);
    }
    return t;
  }

  double get totalAmount {
    double total = 0;
    for (final it in _cart) {
      final qty = _asInt(it["qty"], fallback: 1);
      final unit = _asDouble(it["unit_price"], fallback: 0);

      final offer = _asDouble(it["offer_price"], fallback: 0);
      final base = _asDouble(it["price"], fallback: 0);
      final price = unit > 0 ? unit : (offer > 0 ? offer : base);

      total += qty * price;
    }
    return total;
  }

  bool get hasBusinessId {
    for (final it in _cart) {
      final b = _asInt(it["business_id"] ?? it["shop_id"], fallback: 0);
      if (b > 0) return true;
    }
    return false;
  }

  /// ✅ For checkout: returns normalized list (backend-ready)
  List<Map<String, dynamic>> toCheckoutItems() {
    return _cart.map((it) {
      final pid = _asInt(it["product_id"] ?? it["id"], fallback: 0);
      final bid = _asInt(it["business_id"] ?? it["shop_id"], fallback: 0);

      final qty = _asInt(it["qty"], fallback: 1);

      final offer = _asDouble(it["offer_price"], fallback: 0);
      final base = _asDouble(it["price"], fallback: 0);
      final unit =
      _asDouble(it["unit_price"], fallback: (offer > 0 ? offer : base));

      return {
        "business_id": bid,
        "shop_id": bid,
        "product_id": pid,
        "name": _asString(it["name"]),
        "price": base,
        "offer_price": offer,
        "unit_price": unit,
        "image_url": _asString(it["image_url"] ?? it["image"]),
        "qty": qty,
        "selected_color": _asString(it["selected_color"]),
        "selected_size": _asString(it["selected_size"]),
        "stock": _asInt(it["stock"], fallback: -1),
        "open_box_delivery": _isOpenBoxAllowed(it),
        "available_pincodes": it["available_pincodes"],
        "_id": _asString(it["_id"] ?? ""),
      };
    }).toList();
  }

  // ✅ optional helper: for UI debugging
  bool get isLoaded => _loadedOnce;
}
