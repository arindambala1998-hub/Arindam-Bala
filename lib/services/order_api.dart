// lib/services/order_api.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class OrdersAPI {
  static const String _baseUrl = "https://adminapi.troonky.in/api";

  // ✅ host for media (images)
  static const String _host = "https://adminapi.troonky.in";

  static const Duration _timeout = Duration(seconds: 25);

  // ============================================================
  // ✅ Production-ready order state helpers
  // ============================================================
  // These are the canonical states we want across backend responses.
  // Frontend will map legacy statuses into these for UI.
  static const List<String> canonicalOrderStates = <String>[
    "created",
    "payment_pending",
    "paid",
    "processing",
    "ready",
    "shipped",
    "out_for_delivery",
    "delivered",
    "completed",
    "cancelled",
    "rejected",
    "failed",
    "refunded", // ✅ add (normalizeStatus returns this sometimes)
  ];

  /// Normalize any legacy status to a canonical status for UI.
  static String normalizeStatus(dynamic raw) {
    final s0 = _asString(raw, fallback: "created").toLowerCase().trim();
    if (s0.isEmpty) return "created";

    // common legacy aliases
    if (s0 == "pending") return "created";
    if (s0 == "confirmed" || s0 == "accepted" || s0 == "approved") return "processing";
    if (s0 == "packed" || s0 == "pack" || s0 == "ready_to_ship") return "ready";
    if (s0 == "dispatch" || s0 == "dispatched") return "shipped";
    if (s0 == "ofd" || s0 == "outfordelivery") return "out_for_delivery";
    if (s0 == "done") return "completed";
    if (s0 == "canceled" || s0 == "cancel") return "cancelled";
    if (s0 == "refund" || s0 == "refunded") return "refunded"; // payment-like
    return s0;
  }

  /// Allowed transitions for business-side UI.
  /// This is enforced by UI; backend should also validate.
  static List<String> allowedNextStates(String current) {
    final s = normalizeStatus(current);
    switch (s) {
      case "created":
      case "payment_pending":
      // backend allows created -> confirmed/processing/cancelled
        return const ["confirmed", "processing", "cancelled"];
      case "paid":
        return const ["processing", "cancelled"];
      case "processing":
        return const ["ready", "cancelled"];
      case "ready":
        return const ["shipped", "cancelled"];
      case "shipped":
        return const ["out_for_delivery", "delivered"];
      case "out_for_delivery":
        return const ["delivered"];
      case "delivered":
        return const ["completed"];
      default:
        return const [];
    }
  }

  /// One endpoint to rule them all (target API):
  /// POST /orders/:id/transition { from, to, note }
  ///
  /// Until backend is updated, we fallback to updateOrder() (PUT/PATCH)
  /// which your current backend partially supports.
  static Future<bool> transitionProductOrder({
    required String orderId,
    required String to,
    String? from,
    String? note,
  }) async {
    final oid = orderId.trim();
    if (oid.isEmpty) return false;
    final toState = normalizeStatus(to);
    final fromState = from == null ? null : normalizeStatus(from);

    // 1) Try the future-proof transition endpoint
    final tryEndpoints = <Uri>[
      _u("$_baseUrl/orders/$oid/transition"),
      _u("$_baseUrl/order/$oid/transition"),
    ];

    for (final ep in tryEndpoints) {
      try {
        final decoded = await _request(
          "POST",
          ep,
          authOptional: false,
          body: {
            if (fromState != null) "from": fromState,
            "to": toState,
            if ((note ?? "").trim().isNotEmpty) "note": note!.trim(),
          },
        );
        if (_isOkBody(decoded) || decoded != null) return true;
      } catch (_) {}
    }

    // 2) Fallback to legacy status update
    return updateOrder(
      orderId: oid,
      status: toState,
      extra: {
        if (fromState != null) "from": fromState,
        if ((note ?? "").trim().isNotEmpty) "note": note!.trim(),
      },
    );
  }

  // ============================
  // ✅ Token + Headers (multi-key fallback)
  // ============================
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

  static Future<Map<String, String>> _headers({bool authOptional = true}) async {
    final token = await _getToken();

    final h = <String, String>{
      "Accept": "application/json",
      "Content-Type": "application/json",
    };

    if (token != null && token.isNotEmpty) {
      h["Authorization"] = "Bearer $token";
    } else if (!authOptional) {
      throw Exception("AUTH: token missing");
    }
    return h;
  }

  // ============================
  // ✅ MEDIA URL NORMALIZER (IMAGE FIX)
  // ============================
  static String normalizeMediaUrl(String raw) {
    final s0 = raw.trim();
    if (s0.isEmpty) return "";

    if (s0.startsWith("http://") || s0.startsWith("https://")) return s0;
    if (s0.startsWith("//")) return "https:$s0";

    // if only filename
    if (!s0.contains("/")) {
      return "$_host/uploads/$s0";
    }

    // ✅ if "uploads/.." make sure it becomes "/uploads/.."
    final s = s0.startsWith("uploads/") ? "/$s0" : s0;

    // has path
    final path = s.startsWith("/") ? s : "/$s";
    return "$_host$path";
  }

  static bool _isServiceLike(Map<String, dynamic> o) {
    final rawType = _asString(o["type"] ?? o["order_type"], fallback: "").toLowerCase();
    if (rawType.contains("service") || rawType.contains("booking")) return true;

    return o["service_id"] != null ||
        o["serviceId"] != null ||
        o["booking_id"] != null ||
        o["booking_number"] != null ||
        o["bookingNo"] != null ||
        o["token_number"] != null ||
        o["time_hhmm"] != null ||
        o["time_label"] != null ||
        o["booking_date"] != null;
  }

  static String firstOrderImage(Map<String, dynamic> order) {
    final o = _safeMap(order);

    // ✅ service image priority
    if (_isServiceLike(o)) {
      final svc = _safeMap(o["service"]);
      final raw = _asString(
        o["service_image"] ??
            o["serviceImage"] ??
            svc["image"] ??
            svc["image_url"] ??
            o["image"] ??
            o["image_url"],
        fallback: "",
      );
      return normalizeMediaUrl(raw);
    }

    // product order image from first item
    final items = o["items"];
    if (items is List && items.isNotEmpty) {
      final it = items.first;
      if (it is Map) {
        final img = (it["image"] ?? it["image_url"] ?? "").toString();
        return normalizeMediaUrl(img);
      }
    }

    final img = (o["image"] ?? o["image_url"] ?? "").toString();
    return normalizeMediaUrl(img);
  }

  // ============================
  // Safe helpers
  // ============================
  static dynamic _tryJson(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null; // ✅ handle 204/empty body
    try {
      return jsonDecode(s);
    } catch (_) {
      return raw;
    }
  }

  static Map<String, dynamic> _safeMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  static List _safeList(dynamic v) => (v is List) ? v : const [];

  static int _asInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim()) ?? fallback;
  }

  static double _asDouble(dynamic v, {double fallback = 0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    final s = v.toString().replaceAll("₹", "").trim();
    return double.tryParse(s) ?? fallback;
  }

  static String _asString(dynamic v, {String fallback = ""}) {
    if (v == null) return fallback;
    final s = v.toString().trim();
    return s.isEmpty ? fallback : s;
  }

  static Uri _u(String url, {Map<String, String>? qp}) {
    final uri = Uri.parse(url);
    if (qp == null || qp.isEmpty) return uri;
    return uri.replace(queryParameters: {...uri.queryParameters, ...qp});
  }

  static String _errMsgFromDecoded(dynamic decoded, int status) {
    if (decoded is Map) {
      final m = _safeMap(decoded);
      final msg = m["message"] ?? m["error"] ?? m["errors"];
      if (msg != null) return msg.toString();
    }
    if (decoded is String && decoded.trim().isNotEmpty) return decoded.trim();
    return "HTTP $status";
  }

  static bool _isOkBody(dynamic decoded) {
    if (decoded is Map) {
      final m = _safeMap(decoded);
      final s = m["success"];
      final err = m["error"];
      final st = m["status"];
      if (s == true) return true;
      if (err == false) return true;
      if (st == true) return true;

      final msg = _asString(m["message"], fallback: "").toLowerCase();
      if (msg.contains("cancelled") || msg.contains("canceled") || msg.contains("cancel")) return true;
      if (msg.contains("approved") || msg.contains("accepted") || msg.contains("updated")) return true;
      if (msg.contains("already cancelled") || msg.contains("already canceled")) return true;
      if (msg.contains("order status updated")) return true;
    }
    if (decoded is String) {
      final s = decoded.toLowerCase();
      if (s.contains("ok") || s.contains("success")) return true;
    }
    return false;
  }

  // ============================
  // Low-level request helper
  // ============================
  static Future<dynamic> _request(
      String method,
      Uri uri, {
        bool authOptional = true,
        Map<String, dynamic>? body,
      }) async {
    final headers = await _headers(authOptional: authOptional);

    http.Response res;
    try {
      switch (method.toUpperCase()) {
        case "GET":
          res = await http.get(uri, headers: headers).timeout(_timeout);
          break;
        case "POST":
          res = await http.post(uri, headers: headers, body: jsonEncode(body ?? {})).timeout(_timeout);
          break;
        case "PUT":
          res = await http.put(uri, headers: headers, body: jsonEncode(body ?? {})).timeout(_timeout);
          break;
        case "PATCH":
          res = await http.patch(uri, headers: headers, body: jsonEncode(body ?? {})).timeout(_timeout);
          break;
        case "DELETE":
          res = await http.delete(uri, headers: headers).timeout(_timeout);
          break;
        default:
          throw Exception("Unsupported HTTP method: $method");
      }
    } catch (e) {
      throw Exception("NET: $e");
    }

    final decoded = _tryJson(res.body);

    if (kDebugMode) {
      // ignore: avoid_print
      print("🧾 OrdersAPI ${method.toUpperCase()} ${uri.toString()} -> ${res.statusCode}");
    }

    if (res.statusCode == 200 || res.statusCode == 201 || res.statusCode == 204) {
      return decoded;
    }

    if (res.statusCode == 401 || res.statusCode == 403) {
      throw Exception("AUTH: Unauthorized");
    }

    throw Exception(_errMsgFromDecoded(decoded, res.statusCode));
  }

  // ============================
  // ✅ Single order detector
  // ============================
  static bool _looksLikeSingleOrder(Map<String, dynamic> m) {
    if (m.isEmpty) return false;

    final hasId = m["id"] != null ||
        m["_id"] != null ||
        m["order_id"] != null ||
        m["booking_id"] != null ||
        m["booking_number"] != null ||
        m["bookingNo"] != null;

    final hasTotal = m["total_amount"] != null || m["amount"] != null || m["total"] != null || m["price"] != null;

    final hasStatus =
        m["status"] != null || m["order_status"] != null || m["booking_status"] != null || m["service_status"] != null;

    return hasId && (hasTotal || hasStatus || m["service_id"] != null || m["business_id"] != null);
  }

  // ============================
  // ✅ Deep list extractor
  // ============================
  static const List<String> _listKeys = [
    "orders",
    "order",
    "data",
    "result",
    "payload",
    "rows",
    "items",
    "bookings",
    "booking",
    "service_bookings",
    "serviceBookings",
    "service_orders",
    "serviceOrders",
    "serviceBookingsList",
    "serviceOrdersList",
    "services",
  ];

  static List<Map<String, dynamic>> _deepExtractList(dynamic node) {
    if (node == null) return [];

    if (node is List) {
      return node.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }

    if (node is Map) {
      final m = _safeMap(node);

      // 1) direct list in known keys
      for (final k in _listKeys) {
        final v = m[k];
        if (v is List) {
          return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }

      // 2) nested map/list in known keys
      for (final k in _listKeys) {
        final v = m[k];
        if (v is Map || v is List) {
          final got = _deepExtractList(v);
          if (got.isNotEmpty) return got;
        }
      }

      // 3) generic deep scan
      for (final entry in m.entries) {
        final v = entry.value;
        if (v is Map || v is List) {
          final got = _deepExtractList(v);
          if (got.isNotEmpty) return got;
        }
      }

      // 4) single object fallback
      if (_looksLikeSingleOrder(m)) return [m];
    }

    return [];
  }

  static List<Map<String, dynamic>> _extractOrders(dynamic decoded) => _deepExtractList(decoded);

  // ============================================================
  // ✅ STRICT booking-id (numeric id) extractor for service API
  // ============================================================
  static String _extractServiceNumericId(String anyIdOrCode) {
    final s = anyIdOrCode.trim();
    if (s.isEmpty) return "";
    final n = int.tryParse(s);
    if (n != null && n > 0) return s;
    return "";
  }

  // ============================
  // ✅ Normalize order for UI (includes image URL fix)
  // ============================
  static Map<String, dynamic> normalizeOrderForUi(Map<String, dynamic> o) {
    final out = Map<String, dynamic>.from(o);

    out["id"] = out["id"] ??
        out["_id"] ??
        out["order_id"] ??
        out["order_code"] ??
        out["booking_id"] ??
        out["booking_number"] ??
        out["bookingNo"];

    final hasService = _isServiceLike(out);

    final rawType = _asString(out["type"] ?? out["order_type"], fallback: "");
    final t = rawType.toLowerCase();
    out["type"] = rawType.isNotEmpty ? rawType : (hasService || t.contains("booking") ? "service" : "product");

    // items safe
    final items = out["items"] ??
        out["order_items"] ??
        out["products"] ??
        out["cart_items"] ??
        out["orderItems"] ??
        out["orderItemsList"] ??
        out["orderItemsList"];

    if (items is List) {
      out["items"] = items.map((it) {
        final m = _safeMap(it);

        final pid = _asInt(m["product_id"] ?? m["productId"] ?? m["id"] ?? m["_id"]);
        final qty = _asInt(m["qty"] ?? m["quantity"] ?? 1, fallback: 1);
        final price = _asDouble(m["unit_price"] ?? m["price"] ?? m["offer_price"] ?? 0);

        final productMap = _safeMap(m["product"]);
        final name = _asString(
          m["name"] ?? m["title"] ?? m["product_name"] ?? productMap["name"] ?? productMap["title"],
          fallback: "Item",
        );

        final imgRaw = _asString(
          m["image"] ??
              m["image_url"] ??
              productMap["image"] ??
              productMap["image_url"] ??
              ((_safeList(productMap["images"]).isNotEmpty) ? _safeList(productMap["images"]).first : ""),
          fallback: "",
        );

        final img = normalizeMediaUrl(imgRaw);

        return {
          ...m,
          if (pid > 0) "product_id": pid,
          "qty": qty <= 0 ? 1 : qty,
          if (price > 0) "unit_price": price,
          "name": name,
          if (img.isNotEmpty) "image": img, // ✅ normalized full url
        };
      }).toList();
    } else {
      out["items"] = <dynamic>[];
    }

    // ✅ normalize top-level image fields if present
    final topImgRaw = _asString(out["image"] ?? out["image_url"], fallback: "");
    if (topImgRaw.isNotEmpty) {
      out["image"] = normalizeMediaUrl(topImgRaw);
    }

    // ✅ IMPORTANT: normalize service_image if present (service bookings)
    final svcImgRaw = _asString(out["service_image"] ?? out["serviceImage"], fallback: "");
    if (svcImgRaw.isNotEmpty) {
      out["service_image"] = normalizeMediaUrl(svcImgRaw);
    }

    // ✅ If backend sends service object, normalize its image too
    final svcObj = _safeMap(out["service"]);
    if (svcObj.isNotEmpty) {
      final sImg = _asString(svcObj["image"] ?? svcObj["image_url"], fallback: "");
      if (sImg.isNotEmpty) {
        final svc2 = Map<String, dynamic>.from(svcObj);
        svc2["image"] = normalizeMediaUrl(sImg);
        out["service"] = svc2;
      }
    }

    // ✅ unify service_name/service_title so UI can use either
    final sn = _asString(out["service_name"] ?? out["serviceName"], fallback: "");
    final stt = _asString(out["service_title"] ?? out["serviceTitle"], fallback: "");
    if (sn.isNotEmpty && stt.isEmpty) out["service_title"] = sn;
    if (stt.isNotEmpty && sn.isEmpty) out["service_name"] = stt;

    out["status"] = out["status"] ??
        out["booking_status"] ??
        out["service_status"] ??
        out["order_status"] ??
        out["payment_status"] ??
        "created";

    out["total_amount"] = out["total_amount"] ??
        out["amount"] ??
        out["grand_total"] ??
        out["total"] ??
        out["payable_amount"] ??
        out["price"] ??
        0;

    out["business_id"] = out["business_id"] ?? out["businessId"] ?? out["shop_id"] ?? out["shopId"];

    out["customer_name"] = out["customer_name"] ?? out["customerName"] ?? out["name"] ?? out["user_name"];

    out["phone"] = out["phone"] ?? out["customer_phone"] ?? out["mobile"] ?? out["customer_mobile"];

    out["address"] = out["address"] ?? out["delivery_address"] ?? out["location"];
    out["pincode"] = out["pincode"] ?? out["zip"] ?? out["postal_code"];

    out["created_at"] = out["created_at"] ?? out["createdAt"] ?? out["date"] ?? out["order_date"] ?? out["booked_at"];

    // service extra normalize
    out["service_id"] = out["service_id"] ?? out["serviceId"];
    out["booking_number"] = out["booking_number"] ?? out["bookingNo"];
    out["token_number"] = out["token_number"] ?? out["token"] ?? out["queue_no"] ?? out["queueNo"];
    out["service_time"] = out["service_time"] ??
        out["time_hhmm"] ??
        out["time_label"] ??
        out["scheduled_at"] ??
        out["booking_time"] ??
        out["time"];
    out["booking_date"] = out["booking_date"] ?? out["service_date"] ?? out["appointment_date"];

    out["remarks"] = out["remarks"] ?? out["note"] ?? out["cancel_reason"] ?? out["reason"];

    // ✅ if this is service and service_image still missing but top-level image exists, reuse it
    if (hasService) {
      final si = _asString(out["service_image"], fallback: "");
      if (si.isEmpty) {
        final fromTop = _asString(out["image"] ?? out["image_url"], fallback: "");
        if (fromTop.isNotEmpty) out["service_image"] = normalizeMediaUrl(fromTop);
      }
      // also if service object has image and service_image missing
      final svc = _safeMap(out["service"]);
      if (_asString(out["service_image"], fallback: "").isEmpty && svc.isNotEmpty) {
        final fromSvc = _asString(svc["image"] ?? svc["image_url"], fallback: "");
        if (fromSvc.isNotEmpty) out["service_image"] = normalizeMediaUrl(fromSvc);
      }
    }

    // ===================== Product-only normalize =====================
    final typeLower = _asString(out["type"], fallback: "").toLowerCase();
    final isProduct = typeLower.isEmpty || typeLower == "product";
    if (isProduct) {
      out["status"] = normalizeStatus(out["status"]);
    }

    // ===================== Delivery partner normalize (product orders) =====================
    if (isProduct) {
      final dp = _safeMap(out["delivery_partner"] ??
          out["deliveryPartner"] ??
          out["delivery_boy"] ??
          out["deliveryBoy"] ??
          out["delivery_boy_details"] ??
          out["deliveryBoyDetails"] ??
          out["rider"] ??
          out["rider_details"] ??
          out["delivery_assignment"] ??
          out["deliveryAssignment"]);

      String pickStr(dynamic a, dynamic b, dynamic c) {
        final x = _asString(a, fallback: "");
        if (x.isNotEmpty) return x;
        final y = _asString(b, fallback: "");
        if (y.isNotEmpty) return y;
        return _asString(c, fallback: "");
      }

      out["delivery_partner_name"] = pickStr(
        out["delivery_partner_name"],
        out["deliveryPartnerName"],
        dp["name"] ?? dp["full_name"] ?? dp["deliveryBoyName"] ?? dp["partner_name"],
      );

      out["delivery_partner_phone"] = pickStr(
        out["delivery_partner_phone"],
        out["deliveryPartnerPhone"],
        dp["phone"] ?? dp["mobile"] ?? dp["contact"] ?? dp["partner_phone"],
      );

      out["delivery_eta"] = pickStr(
        out["delivery_eta"],
        out["deliveryEta"],
        dp["eta"] ?? dp["delivery_eta"] ?? dp["deliveryEtaText"],
      );
    }

    return out;
  }

  // ============================================================
  // ✅ SERVICE BOOKING DETAILS (backend-accurate)
  // ============================================================
  static Future<Map<String, dynamic>> getServiceBookingDetails(String idOrCode) async {
    final raw = idOrCode.trim();
    if (raw.isEmpty) return {};

    final numeric = _extractServiceNumericId(raw);

    final endpoints = <Uri>[
      if (numeric.isNotEmpty) _u("$_baseUrl/bookings/details/$numeric"),
      if (numeric.isNotEmpty) _u("$_baseUrl/bookings/$numeric"),
      _u("$_baseUrl/bookings/details/$raw"),
      _u("$_baseUrl/bookings/$raw"),
    ];

    for (final ep in endpoints) {
      try {
        final decoded = await _request("GET", ep, authOptional: false);

        if (decoded is Map) {
          final m = _safeMap(decoded);
          final inner = m["booking"] ?? m["data"] ?? m["result"];
          if (inner is Map) {
            final mm = _safeMap(inner);
            if (mm.isNotEmpty) return normalizeOrderForUi(mm);
          }

          if (_looksLikeSingleOrder(m)) return normalizeOrderForUi(m);

          final list = _extractOrders(decoded);
          if (list.isNotEmpty) return normalizeOrderForUi(list.first);
        }

        if (decoded is List && decoded.isNotEmpty) {
          final one = _safeMap(decoded.first);
          if (one.isNotEmpty) return normalizeOrderForUi(one);
        }
      } catch (_) {}
    }

    return {};
  }

  // ============================================================
  // ✅ CANCEL SERVICE BOOKING (backend-accurate)
  // ============================================================
  static Future<bool> cancelServiceBooking({
    required String idOrCode,
    required String reason,
  }) async {
    final raw = idOrCode.trim();
    final r = reason.trim();
    if (raw.isEmpty || r.isEmpty) return false;

    final numeric = _extractServiceNumericId(raw);

    final endpoints = <Uri>[
      if (numeric.isNotEmpty) _u("$_baseUrl/bookings/$numeric/cancel"),
      _u("$_baseUrl/bookings/$raw/cancel"),
    ];

    for (final ep in endpoints) {
      try {
        final decoded = await _request(
          "PATCH",
          ep,
          authOptional: false,
          body: {"reason": r},
        );
        if (_isOkBody(decoded)) return true;
        if (decoded != null) return true;
      } catch (_) {}
    }

    return false;
  }

  // ============================================================
  // ✅ USER ORDERS (Product/Service)
  // ============================================================
  static Future<List<Map<String, dynamic>>> getMyOrders({String type = "product"}) async {
    final t = type.trim().toLowerCase();

    if (t == "service") {
      final svc = await getMyServiceBookings();
      if (svc.isNotEmpty) return svc;
    }

    final endpoints = <Uri>[
      _u("$_baseUrl/orders/my", qp: {"type": t, "include_items": "1"}),
      _u("$_baseUrl/orders", qp: {"type": t, "include_items": "1"}),
      _u("$_baseUrl/orders/user", qp: {"type": t, "include_items": "1"}),
    ];

    for (final ep in endpoints) {
      try {
        final decoded = await _request("GET", ep, authOptional: false);
        final list = _extractOrders(decoded);
        if (list.isNotEmpty) {
          return list.map((e) {
            final m = normalizeOrderForUi(e);
            m["type"] = _asString(m["type"], fallback: t);
            return m;
          }).toList();
        }
      } catch (_) {}
    }

    return [];
  }

  static Future<List<Map<String, dynamic>>> getMyServiceBookings() async {
    final endpoints = <Uri>[
      _u("$_baseUrl/bookings/my"),
      _u("$_baseUrl/bookings"),
      _u("$_baseUrl/service-orders/my"),
      _u("$_baseUrl/service-orders"),
      _u("$_baseUrl/service-bookings/my"),
      _u("$_baseUrl/service-bookings"),
    ];

    for (final ep in endpoints) {
      try {
        final decoded = await _request("GET", ep, authOptional: false);
        final list = _extractOrders(decoded);
        if (list.isNotEmpty) {
          return list.map((e) {
            final m = normalizeOrderForUi(e);
            m["type"] = "service";
            return m;
          }).toList();
        }
      } catch (_) {}
    }

    return [];
  }

  static Future<List<Map<String, dynamic>>> getUserOrders(
      String userId, {
        String type = "product",
      }) async {
    final uid = userId.trim();
    if (uid.isEmpty) return [];

    final t = type.trim().toLowerCase();
    final endpoints = <Uri>[
      _u("$_baseUrl/orders/user/$uid", qp: {"type": t, "include_items": "1"}),
      _u("$_baseUrl/orders", qp: {"user_id": uid, "type": t, "include_items": "1"}),
      _u("$_baseUrl/orders", qp: {"userId": uid, "type": t, "include_items": "1"}),
      if (t == "service") _u("$_baseUrl/bookings/user/$uid"),
      if (t == "service") _u("$_baseUrl/bookings", qp: {"user_id": uid}),
      if (t == "service") _u("$_baseUrl/service-bookings/user/$uid"),
      if (t == "service") _u("$_baseUrl/service-bookings", qp: {"user_id": uid}),
    ];

    for (final ep in endpoints) {
      try {
        final decoded = await _request("GET", ep, authOptional: false);
        final list = _extractOrders(decoded);
        if (list.isNotEmpty) {
          return list.map((e) {
            final m = normalizeOrderForUi(e);
            m["type"] = _asString(m["type"], fallback: t);
            return m;
          }).toList();
        }
      } catch (_) {}
    }

    return [];
  }

  // ============================================================
  // ✅ BUSINESS ORDERS
  // ============================================================
  static Future<List<Map<String, dynamic>>> getBusinessOrders(String businessId) async {
    final bid = businessId.trim();
    if (bid.isEmpty) return [];

    final endpoints = <Uri>[
      _u("$_baseUrl/orders/business/$bid", qp: {"include_items": "1"}),
      _u("$_baseUrl/orders/$bid", qp: {"include_items": "1"}),
      _u("$_baseUrl/orders", qp: {"business_id": bid, "include_items": "1"}),
      _u("$_baseUrl/orders", qp: {"businessId": bid, "include_items": "1"}),
      _u("$_baseUrl/orders", qp: {"shop_id": bid, "include_items": "1"}),
      _u("$_baseUrl/orders", qp: {"shopId": bid, "include_items": "1"}),
      _u("$_baseUrl/orders", qp: {"business_id": bid, "type": "product", "include_items": "1"}),
    ];

    for (final ep in endpoints) {
      try {
        final decoded = await _request("GET", ep, authOptional: false);
        final list = _extractOrders(decoded);
        if (list.isNotEmpty) {
          return list.map((e) {
            final m = normalizeOrderForUi(e);
            m["type"] = _asString(m["type"], fallback: "product");
            return m;
          }).toList();
        }
      } catch (_) {}
    }

    return [];
  }

  static Future<List<Map<String, dynamic>>> getBusinessServiceOrders(String businessId) async {
    final bid = businessId.trim();
    if (bid.isEmpty) return [];

    final endpoints = <Uri>[
      _u("$_baseUrl/bookings", qp: {"business_id": bid}),
      _u("$_baseUrl/bookings", qp: {"shop_id": bid}),
      _u("$_baseUrl/bookings", qp: {"businessId": bid}),
      _u("$_baseUrl/bookings", qp: {"shopId": bid}),
      _u("$_baseUrl/bookings/business/$bid"),
      _u("$_baseUrl/bookings/$bid"),
      _u("$_baseUrl/bookings/service", qp: {"business_id": bid}),
      _u("$_baseUrl/bookings/service", qp: {"shop_id": bid}),
      _u("$_baseUrl/service-bookings", qp: {"business_id": bid}),
      _u("$_baseUrl/service-bookings/business/$bid"),
      _u("$_baseUrl/service-orders/business/$bid"),
      _u("$_baseUrl/service-orders/$bid"),
      _u("$_baseUrl/service-orders", qp: {"business_id": bid}),
      _u("$_baseUrl/service-orders", qp: {"businessId": bid}),
    ];

    for (final ep in endpoints) {
      try {
        final decoded = await _request("GET", ep, authOptional: false);
        final list = _extractOrders(decoded);

        if (kDebugMode) {
          // ignore: avoid_print
          print("🟩 ServiceOrders extract ${ep.toString()} -> count=${list.length}");
        }

        if (list.isNotEmpty) {
          return list.map((e) {
            final m = normalizeOrderForUi(e);
            m["type"] = "service";
            return m;
          }).toList();
        }
      } catch (_) {}
    }

    return [];
  }

  // ============================================================
  // ✅ ORDER DETAILS (product)
  // NOTE: service details should use getServiceBookingDetails()
  // ============================================================
  static Future<Map<String, dynamic>> getOrderDetails(String orderId) async {
    final id = orderId.trim();
    if (id.isEmpty) return {};

    final endpoints = <Uri>[
      _u("$_baseUrl/orders/details/$id"),
      _u("$_baseUrl/orders/order/$id"),
      _u("$_baseUrl/order/$id"),
      _u("$_baseUrl/orders/get/$id"),
      _u("$_baseUrl/orders/$id"),
    ];

    for (final ep in endpoints) {
      try {
        final decoded = await _request("GET", ep, authOptional: false);

        if (decoded is Map) {
          final m = _safeMap(decoded);

          final inner = m["order"];
          if (inner is Map) {
            final mm = _safeMap(inner);
            if (_looksLikeSingleOrder(mm)) return normalizeOrderForUi(mm);
          }

          if (_looksLikeSingleOrder(m)) return normalizeOrderForUi(m);

          final listMaybe = m["orders"];
          final list = _extractOrders(listMaybe);
          if (list.isNotEmpty) return normalizeOrderForUi(list.first);

          final data = _safeMap(m["data"]);
          if (data.isNotEmpty) {
            final inner2 = data["order"];
            if (inner2 is Map) {
              final mm = _safeMap(inner2);
              if (_looksLikeSingleOrder(mm)) return normalizeOrderForUi(mm);
            }
            if (_looksLikeSingleOrder(data)) return normalizeOrderForUi(data);
          }
        }

        if (decoded is List && decoded.length == 1) {
          final one = _safeMap(decoded.first);
          if (_looksLikeSingleOrder(one)) return normalizeOrderForUi(one);
        }
      } catch (_) {}
    }

    return {};
  }

  // ============================================================
  // ✅ UPDATE ORDER STATUS (product only)
  // IMPORTANT:
  // - Primary endpoint now: PUT /orders/status/:id
  // - Aliases: /orders/update-status/:id , /orders/change-status/:id
  // - Legacy fallback: /orders/update/:id etc.
  // ============================================================
  static Future<bool> updateOrder({
    required String orderId,
    required String status,
    String? paymentStatus,
    String? deliveryPartnerName,
    String? deliveryPartnerPhone,
    String? deliveryEta,
    String? cancelReason,
    Map<String, dynamic>? extra,
  }) async {
    final oid = orderId.trim();
    if (oid.isEmpty) return false;

    // ✅ always send backend-canonical status
    String s = normalizeStatus(status).trim().toLowerCase();

    // ✅ legacy/typo safety
    if (s == "approved" || s == "accepted" || s == "confirmed") s = "processing";
    if (s == "canceled") s = "cancelled";
    if (s == "pending") s = "created";

    final payload = <String, dynamic>{"status": s};

    if (paymentStatus != null && paymentStatus.trim().isNotEmpty) {
      payload["payment_status"] = paymentStatus.trim().toLowerCase();
    }

    final reason = (cancelReason ?? "").trim();
    if (reason.isNotEmpty) {
      payload["cancel_reason"] = reason;
      payload["remarks"] = reason;
      payload["reason"] = reason;
    }

    final n = (deliveryPartnerName ?? "").trim();
    final p = (deliveryPartnerPhone ?? "").trim();
    final eta = (deliveryEta ?? "").trim();
    if (n.isNotEmpty) payload["delivery_partner_name"] = n;
    if (p.isNotEmpty) payload["delivery_partner_phone"] = p;
    if (eta.isNotEmpty) payload["delivery_eta"] = eta;

    if (extra != null && extra.isNotEmpty) payload.addAll(extra);

    // ✅ PRIMARY first (matches your backend now)
    final endpoints = <Uri>[
      _u("$_baseUrl/orders/status/$oid"), // ✅ new primary
      _u("$_baseUrl/orders/update-status/$oid"), // ✅ alias
      _u("$_baseUrl/orders/change-status/$oid"), // ✅ alias

      // legacy fallbacks
      _u("$_baseUrl/orders/update/$oid"),
      _u("$_baseUrl/order/update/$oid"),
      _u("$_baseUrl/orders/$oid"),
    ];

    for (final ep in endpoints) {
      try {
        final decoded = await _request("PUT", ep, authOptional: false, body: payload);
        if (_isOkBody(decoded) || decoded != null) return true;
      } catch (_) {
        try {
          final decoded = await _request("PATCH", ep, authOptional: false, body: payload);
          if (_isOkBody(decoded) || decoded != null) return true;
        } catch (_) {}
      }
    }

    if (kDebugMode) {
      // ignore: avoid_print
      print("❌ updateOrder failed for all endpoints: $oid");
    }
    return false;
  }

  // ============================================================
  // ✅ CANCEL (Unified)
  // ============================================================
  static Future<Map<String, dynamic>> cancelUnified({
    required String id,
    required String type, // "product" | "service"
    required String reason,
  }) async {
    final oid = id.trim();
    if (oid.isEmpty) return {"success": false, "message": "Invalid ID"};

    final r = reason.trim();
    if (r.isEmpty) return {"success": false, "message": "Cancel reason required"};

    final t = type.trim().toLowerCase();

    // ✅ service first: correct backend route
    if (t == "service") {
      final ok = await cancelServiceBooking(idOrCode: oid, reason: r);
      return ok ? {"success": true, "message": "Cancelled"} : {"success": false, "message": "Cancel failed"};
    }

    // ✅ product: PATCH /orders/:id/cancel {"reason": "..."} (matches your backend)
    final endpoints = <Uri>[
      _u("$_baseUrl/orders/$oid/cancel"),
      _u("$_baseUrl/orders/cancel/$oid"),
      _u("$_baseUrl/orders/$oid/status/cancel"),
      _u("$_baseUrl/orders/$oid/status", qp: {"status": "cancelled"}),
    ];

    for (final ep in endpoints) {
      try {
        final decoded = await _request(
          "PATCH",
          ep,
          authOptional: false,
          body: {"reason": r},
        );
        if (_isOkBody(decoded) || decoded != null) return {"success": true, "message": "Cancelled"};
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains("auth:")) {
          return {"success": false, "message": "Unauthorized. Please login again."};
        }
      }
    }

    final ok = await updateOrder(orderId: oid, status: "cancelled", cancelReason: r);
    if (ok) return {"success": true, "message": "Cancelled"};

    return {"success": false, "message": "Cancel failed"};
  }

  // ============================================================
  // ✅ DELETE ORDER / BOOKING
  // ============================================================
  static Future<bool> deleteOrder(String orderId) async {
    final oid = orderId.trim();
    if (oid.isEmpty) return false;

    final endpoints = <Uri>[
      _u("$_baseUrl/orders/delete/$oid"),
      _u("$_baseUrl/order/delete/$oid"),
      _u("$_baseUrl/bookings/delete/$oid"),
      _u("$_baseUrl/service-bookings/delete/$oid"),
      _u("$_baseUrl/orders/$oid"),
      _u("$_baseUrl/bookings/$oid"),
      _u("$_baseUrl/service-bookings/$oid"),
    ];

    for (final ep in endpoints) {
      try {
        await _request("DELETE", ep, authOptional: false);
        return true;
      } catch (_) {}
    }

    if (kDebugMode) {
      // ignore: avoid_print
      print("❌ deleteOrder failed for all endpoints: $oid");
    }
    return false;
  }

  // ============================================================
  // ✅ BUSINESS ORDERS (PAGED) - preferred for performance
  // ============================================================
  static Future<Map<String, dynamic>> getBusinessOrdersPaged({
    required String businessId,
    int page = 1,
    int limit = 20,
  }) async {
    final bid = businessId.trim();
    if (bid.isEmpty) return {"items": <Map<String, dynamic>>[], "hasMore": false, "page": page, "limit": limit};

    final qpCommon = {
      "include_items": "1",
      "page": page.toString(),
      "limit": limit.toString(),
    };

    final endpoints = <Uri>[
      _u("$_baseUrl/orders/business/$bid", qp: qpCommon),
      _u("$_baseUrl/orders/$bid", qp: qpCommon),
      _u("$_baseUrl/orders", qp: {...qpCommon, "business_id": bid}),
      _u("$_baseUrl/orders", qp: {...qpCommon, "businessId": bid}),
      _u("$_baseUrl/orders", qp: {...qpCommon, "shop_id": bid}),
      _u("$_baseUrl/orders", qp: {...qpCommon, "shopId": bid}),
      _u("$_baseUrl/orders", qp: {...qpCommon, "business_id": bid, "type": "product"}),
    ];

    for (final ep in endpoints) {
      try {
        final decoded = await _request("GET", ep, authOptional: false);
        final list = _extractOrders(decoded);
        if (list.isNotEmpty || decoded != null) {
          final items = list.map((e) {
            final m = normalizeOrderForUi(e);
            m["type"] = _asString(m["type"], fallback: "product");
            return m;
          }).toList();

          bool hasMore = false;
          if (decoded is Map) {
            final meta = decoded["meta"] ?? decoded["pagination"] ?? decoded["page"];
            if (meta is Map) {
              final m = Map<String, dynamic>.from(meta);
              final hm = m["hasMore"] ?? m["has_more"] ?? m["has_next"] ?? m["next"];
              if (hm is bool) {
                hasMore = hm;
              } else {
                final total = _asInt(m["total"] ?? m["count"] ?? m["totalCount"] ?? m["total_count"], fallback: 0);
                final p = _asInt(m["page"] ?? m["currentPage"] ?? m["current_page"], fallback: page);
                final l = _asInt(m["limit"] ?? m["perPage"] ?? m["per_page"], fallback: limit);
                if (total > 0) hasMore = p * l < total;
                if (m["nextPage"] != null || m["next_page"] != null) hasMore = true;
              }
            }
          }
          if (!hasMore) {
            hasMore = items.length >= limit;
          }

          return {"items": items, "hasMore": hasMore, "page": page, "limit": limit};
        }
      } catch (_) {}
    }

    return {"items": <Map<String, dynamic>>[], "hasMore": false, "page": page, "limit": limit};
  }

  // ============================================================
  // ✅ SERVICE ORDERS / BOOKINGS (PAGED)
  // ============================================================
  static Future<Map<String, dynamic>> getBusinessServiceOrdersPaged({
    required String businessId,
    int page = 1,
    int limit = 20,
  }) async {
    final bid = businessId.trim();
    if (bid.isEmpty) return {"items": <Map<String, dynamic>>[], "hasMore": false, "page": page, "limit": limit};

    final endpoints = <Uri>[
      _u("$_baseUrl/bookings", qp: {"business_id": bid, "page": page.toString(), "limit": limit.toString()}),
      _u("$_baseUrl/bookings", qp: {"shop_id": bid, "page": page.toString(), "limit": limit.toString()}),
      _u("$_baseUrl/bookings", qp: {"businessId": bid, "page": page.toString(), "limit": limit.toString()}),
      _u("$_baseUrl/bookings", qp: {"shopId": bid, "page": page.toString(), "limit": limit.toString()}),
      _u("$_baseUrl/bookings/business/$bid", qp: {"page": page.toString(), "limit": limit.toString()}),
      _u("$_baseUrl/service-orders/business/$bid", qp: {"page": page.toString(), "limit": limit.toString()}),
      _u("$_baseUrl/service-orders", qp: {"business_id": bid, "page": page.toString(), "limit": limit.toString()}),
    ];

    for (final ep in endpoints) {
      try {
        final decoded = await _request("GET", ep, authOptional: false);
        final list = _extractOrders(decoded);
        if (list.isNotEmpty || decoded != null) {
          final items = list.map((e) {
            final m = normalizeOrderForUi(e);
            m["type"] = "service";
            return m;
          }).toList();

          bool hasMore = false;
          if (decoded is Map) {
            final meta = decoded["meta"] ?? decoded["pagination"] ?? decoded["page"];
            if (meta is Map) {
              final m = Map<String, dynamic>.from(meta);
              final hm = m["hasMore"] ?? m["has_more"] ?? m["has_next"] ?? m["next"];
              if (hm is bool) {
                hasMore = hm;
              } else {
                final total = _asInt(m["total"] ?? m["count"] ?? m["totalCount"] ?? m["total_count"], fallback: 0);
                final p = _asInt(m["page"] ?? m["currentPage"] ?? m["current_page"], fallback: page);
                final l = _asInt(m["limit"] ?? m["perPage"] ?? m["per_page"], fallback: limit);
                if (total > 0) hasMore = p * l < total;
                if (m["nextPage"] != null || m["next_page"] != null) hasMore = true;
              }
            }
          }
          if (!hasMore) {
            hasMore = items.length >= limit;
          }

          return {"items": items, "hasMore": hasMore, "page": page, "limit": limit};
        }
      } catch (_) {}
    }

    return {"items": <Map<String, dynamic>>[], "hasMore": false, "page": page, "limit": limit};
  }
}
