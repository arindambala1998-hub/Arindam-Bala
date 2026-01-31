// lib/services/auth_api.dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthAPI {
  // ✅ Backend base URL
  static const String _baseUrl = "https://adminapi.troonky.in/api/auth";

  static const Duration _timeout = Duration(seconds: 20);

  // --------------------------------------------------
  // Helpers
  // --------------------------------------------------
  static Uri _u(String path) => Uri.parse("$_baseUrl$path");

  static Map<String, dynamic> _safeJson(String body) {
    try {
      final d = jsonDecode(body);
      return d is Map<String, dynamic> ? d : {};
    } catch (_) {
      return {};
    }
  }

  static String _extractMessage(
      Map<String, dynamic> data, {
        String fallback = "Something went wrong",
      }) {
    final m = data["message"] ?? data["error"] ?? data["msg"];
    if (m == null) return fallback;
    final s = m.toString().trim();
    return s.isEmpty ? fallback : s;
  }

  static String _statusToMessage(int status, Map<String, dynamic> data) {
    final serverMsg = _extractMessage(data, fallback: "");
    if (serverMsg.isNotEmpty) return serverMsg;

    switch (status) {
      case 400:
        return "Invalid request";
      case 401:
        return "Unauthorized. Please login again.";
      case 403:
        return "Forbidden";
      case 404:
        return "Not found";
      case 429:
        return "Too many requests. Try again later.";
      default:
        if (status >= 500) return "Server error. Try again later.";
        return "Request failed";
    }
  }

  static Future<Map<String, dynamic>> _postJson(
      String path, {
        required Map<String, dynamic> body,
        Map<String, String>? headers,
      }) async {
    try {
      final res = await http
          .post(
        _u(path),
        headers: {
          "Content-Type": "application/json",
          ...(headers ?? {}),
        },
        body: jsonEncode(body),
      )
          .timeout(_timeout);

      final data = _safeJson(res.body);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return {"error": false, "data": data};
      }

      return {
        "error": true,
        "message": _statusToMessage(res.statusCode, data),
        "data": data,
      };
    } on TimeoutException {
      return {
        "error": true,
        "message": "Request timeout. Check internet & try again."
      };
    } catch (_) {
      return {"error": true, "message": "Server connection failed"};
    }
  }

  // -----------------------------
  // Normalizers / Extractors
  // -----------------------------
  static String _norm(Object? v) => (v ?? "").toString().trim();
  static String _lower(Object? v) => _norm(v).toLowerCase();

  static bool _validId(Object? v) {
    final s = _lower(v);
    return s.isNotEmpty &&
        s != "0" &&
        s != "null" &&
        s != "undefined" &&
        s != "nan";
  }

  /// ✅ businessId/shopId/business_id/shop_id + nested shop.id + business.id
  static String? _pickBusinessId(Map<String, dynamic> data) {
    // direct keys
    final candidates = [
      data["businessId"],
      data["shopId"],
      data["shop_id"],
      data["business_id"],
      data["storeId"],
      data["store_id"],
    ];

    for (final c in candidates) {
      if (_validId(c)) return _norm(c);
    }

    // nested objects: shop.id / business.id / store.id
    final nestedKeys = ["shop", "business", "store"];
    for (final key in nestedKeys) {
      final obj = data[key];
      if (obj is Map && _validId(obj["id"])) return _norm(obj["id"]);
    }

    return null;
  }

  // --------------------------------------------------
  // AUTH APIs
  // --------------------------------------------------

  // 🔐 LOGIN
  static Future<Map<String, dynamic>> login({
    required String emailOrPhone,
    required String password,
  }) async {
    final r = await _postJson(
      "/login",
      body: {
        "email_or_phone": emailOrPhone.trim(),
        "password": password,
      },
    );

    if (r["error"] == true) {
      return {"error": true, "message": r["message"] ?? "Login failed"};
    }

    final data = (r["data"] as Map<String, dynamic>?) ?? {};

    final token = _norm(data["token"]);
    final userId = _norm(data["userId"]);
    final userType =
    _lower(data["userType"]).isEmpty ? "user" : _lower(data["userType"]);
    final businessId = _pickBusinessId(data);

    // ✅ NEW: extract refresh token
    final refreshToken = _norm(data["refreshToken"]);

    return {
      "error": false,
      "message": _extractMessage(data, fallback: "Login successful"),
      "token": token,
      "userId": userId,
      "userType": userType,
      "businessId": businessId,
      "refreshToken": _norm(data["refreshToken"]), // ✅ Add this new line
    };
  }

  // 📧 SEND OTP
  static Future<Map<String, dynamic>> sendOtp({
    required String email,
  }) async {
    final r = await _postJson("/send-otp", body: {"email": email.trim()});

    if (r["error"] == true) {
      return {"error": true, "message": r["message"] ?? "OTP failed"};
    }

    final data = (r["data"] as Map<String, dynamic>?) ?? {};
    return {
      "error": false,
      "message": _extractMessage(data, fallback: "OTP sent successfully"),
    };
  }

  // ✅ VERIFY OTP
  static Future<Map<String, dynamic>> verifyOtp({
    required String email,
    required String otp,
  }) async {
    final r = await _postJson(
      "/verify-otp",
      body: {"email": email.trim(), "otp": otp.trim()},
    );

    if (r["error"] == true) {
      return {"error": true, "message": r["message"] ?? "Invalid OTP"};
    }

    final data = (r["data"] as Map<String, dynamic>?) ?? {};
    return {
      "error": false,
      "message": _extractMessage(data, fallback: "OTP verified"),
    };
  }

  // 📝 SIGNUP
  static Future<Map<String, dynamic>> signup({
    required Map<String, dynamic> payload,
  }) async {
    final r = await _postJson("/register", body: payload);

    if (r["error"] == true) {
      return {"error": true, "message": r["message"] ?? "Signup failed"};
    }

    final data = (r["data"] as Map<String, dynamic>?) ?? {};

    final userId = _norm(data["userId"]);
    final userType =
    _lower(data["userType"]).isEmpty ? "user" : _lower(data["userType"]);
    final businessId = _pickBusinessId(data);

    return {
      "error": false,
      "message": _extractMessage(data, fallback: "Signup successful"),
      "userId": userId,
      "userType": userType,
      "businessId": businessId,
    };
  }

  // 🔁 RESET PASSWORD
  static Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    final r = await _postJson(
      "/reset-password",
      body: {
        "email": email.trim(),
        "otp": otp.trim(),
        "newPassword": newPassword,
      },
    );

    if (r["error"] == true) {
      return {"error": true, "message": r["message"] ?? "Reset failed"};
    }

    final data = (r["data"] as Map<String, dynamic>?) ?? {};
    return {
      "error": false,
      "message": _extractMessage(data, fallback: "Password updated"),
    };
  }

  // --------------------------------------------------
  // SESSION
  // --------------------------------------------------
  static Future<void> saveAuthData({
    required String token,
    required String userId,
    required String userType,
    String? businessId,
    String? refreshToken, // This is the new parameter
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final t = _norm(token);
    final uid = _norm(userId);
    final ut = _lower(userType).isEmpty ? "user" : _lower(userType);

    await prefs.setString("token", t);
    await prefs.setString("userId", uid);
    await prefs.setString("userType", ut);
    await prefs.setBool("loggedIn", true);

    // ✅ strong businessId validation
    if (_validId(businessId)) {
      await prefs.setString("businessId", _norm(businessId));
    } else {
      await prefs.remove("businessId");
    }

    // ✅ NEW: Save refresh token if provided
    if (refreshToken != null && refreshToken.trim().isNotEmpty) {
      await prefs.setString("refreshToken", refreshToken.trim());
    } else {
      await prefs.remove("refreshToken");
    }
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  static Future<Map<String, String>> authHeader() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");
    if (!_validId(token)) return {};
    return {"Authorization": "Bearer ${token!.trim()}"};
  }
}
