// lib/services/friends_api.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class FriendsAPI {
  static const String baseUrl = "https://adminapi.troonky.in/api/friends";

  // ============================================================
  // 🔐 TOKEN (multi-key fallback)
  // ============================================================
  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();

    final candidates = <String?>[
      prefs.getString('token'),
      prefs.getString('auth_token'),
      prefs.getString('access_token'),
      prefs.getString('jwt'),
      prefs.getString('user_token'),
    ];

    for (final t in candidates) {
      final v = (t ?? '').trim();
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  // ============================================================
  // 🧾 HEADERS
  // ============================================================
  static Future<Map<String, String>> _headers({bool json = true}) async {
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw Exception("No token found. Please login again.");
    }
    return {
      "Authorization": "Bearer $token",
      "Accept": "application/json",
      if (json) "Content-Type": "application/json",
    };
  }

  // ============================================================
  // ✅ safe json decode
  // ============================================================
  static dynamic _safeJson(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  // ============================================================
  // ✅ extract list from different response shapes
  // supports:
  //  - [ ... ]
  //  - {requests:[...]} / {suggestions:[...]} / {friends:[...]}
  //  - {data:[...]} / {result:[...]} / {items:[...]}
  // ============================================================
  static List<dynamic> _pickList(dynamic data, List<String> keys) {
    if (data is List) return List.from(data);

    if (data is Map) {
      for (final k in keys) {
        final v = data[k];
        if (v is List) return List.from(v);
      }
      // common fallbacks
      for (final k in const ["data", "result", "items", "rows"]) {
        final v = data[k];
        if (v is List) return List.from(v);
      }
    }

    return [];
  }

  // ============================================================
  // ✅ GET MY FRIENDS (accepted)
  // GET /api/friends
  // ============================================================
  static Future<List<Map<String, dynamic>>> getMyFriends() async {
    final url = Uri.parse(baseUrl);
    final headers = await _headers(json: false);

    try {
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = _safeJson(response.body);
        final list = _pickList(data, const ["friends"]);
        return list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }

      if (kDebugMode) {
        print("❌ getMyFriends Failed => ${response.statusCode} ${response.body}");
      }
    } on SocketException {
      throw Exception("Network error. Check internet connection.");
    } catch (e) {
      if (kDebugMode) print("getMyFriends Error: $e");
      rethrow;
    }

    return [];
  }

  // ============================================================
  // 🤝 SEND FRIEND REQUEST
  // POST /api/friends/requests/:targetId
  // ============================================================
  static Future<void> sendRequest(String targetId) async {
    final tid = targetId.trim();
    final url = Uri.parse("$baseUrl/requests/$tid");
    final headers = await _headers(json: false);

    try {
      final response = await http.post(url, headers: headers);

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(_safeJson(response.body).toString());
      }
    } on SocketException {
      throw Exception("Network error. Check internet connection.");
    } catch (e) {
      if (kDebugMode) print("Send Request Error: $e");
      rethrow;
    }
  }

  // ============================================================
  // ✔️ ACCEPT FRIEND REQUEST
  // POST /api/friends/requests/:requestId/accept
  // ============================================================
  static Future<void> acceptRequest(String requestId) async {
    final rid = requestId.trim();
    final url = Uri.parse("$baseUrl/requests/$rid/accept");
    final headers = await _headers(json: false);

    try {
      final response = await http.post(url, headers: headers);

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(_safeJson(response.body).toString());
      }
    } on SocketException {
      throw Exception("Network error. Check internet connection.");
    } catch (e) {
      if (kDebugMode) print("Accept Request Error: $e");
      rethrow;
    }
  }

  // ============================================================
  // ❌ REJECT REQUEST
  // DELETE /api/friends/requests/:requestId
  // ============================================================
  static Future<void> rejectRequest(String requestId) async {
    final rid = requestId.trim();
    final url = Uri.parse("$baseUrl/requests/$rid");
    final headers = await _headers(json: false);

    try {
      final response = await http.delete(url, headers: headers);

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception(_safeJson(response.body).toString());
      }
    } on SocketException {
      throw Exception("Network error. Check internet connection.");
    } catch (e) {
      if (kDebugMode) print("Reject Request Error: $e");
      rethrow;
    }
  }

  // ============================================================
  // 🔥 CANCEL SENT REQUEST
  // DELETE /api/friends/requests/:targetId
  // ============================================================
  static Future<void> cancelRequest(String targetId) async {
    final tid = targetId.trim();
    final url = Uri.parse("$baseUrl/requests/$tid");
    final headers = await _headers(json: false);

    try {
      final response = await http.delete(url, headers: headers);

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception(_safeJson(response.body).toString());
      }
    } on SocketException {
      throw Exception("Network error. Check internet connection.");
    } catch (e) {
      if (kDebugMode) print("Cancel Request Error: $e");
      rethrow;
    }
  }

  // ============================================================
  // 📨 GET PENDING REQUESTS (incoming)
  // GET /api/friends/requests
  // ============================================================
  static Future<List<dynamic>> getPendingRequests() async {
    final url = Uri.parse("$baseUrl/requests");
    final headers = await _headers(json: false);

    try {
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = _safeJson(response.body);
        return _pickList(data, const ["requests", "pending", "incoming"]);
      }

      if (kDebugMode) {
        print("❌ getPendingRequests Failed => ${response.statusCode} ${response.body}");
      }
    } on SocketException {
      if (kDebugMode) print("getPendingRequests Network Error");
    } catch (e) {
      if (kDebugMode) print("getPendingRequests Error: $e");
    }

    return [];
  }

  // ============================================================
  // 📤 GET SENT REQUESTS
  // GET /api/friends/requests/sent
  // ============================================================
  static Future<List<dynamic>> getSentRequests() async {
    final url = Uri.parse("$baseUrl/requests/sent");
    final headers = await _headers(json: false);

    try {
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = _safeJson(response.body);
        return _pickList(data, const ["requests", "sent"]);
      }

      if (kDebugMode) {
        print("❌ getSentRequests Failed => ${response.statusCode} ${response.body}");
      }
    } on SocketException {
      if (kDebugMode) print("getSentRequests Network Error");
    } catch (e) {
      if (kDebugMode) print("getSentRequests Error: $e");
    }

    return [];
  }

  // ============================================================
  // 🎯 GET FRIEND SUGGESTIONS
  // GET /api/friends/suggestions
  // ============================================================
  static Future<List<dynamic>> getSuggestions() async {
    final url = Uri.parse("$baseUrl/suggestions");
    final headers = await _headers(json: false);

    try {
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = _safeJson(response.body);
        return _pickList(data, const ["suggestions"]);
      }

      if (kDebugMode) {
        print("❌ getSuggestions Failed => ${response.statusCode} ${response.body}");
      }
    } on SocketException {
      if (kDebugMode) print("getSuggestions Network Error");
    } catch (e) {
      if (kDebugMode) print("getSuggestions Error: $e");
    }

    return [];
  }

  // ============================================================
  // ✅ FRIEND STATUS
  // GET /api/friends/status/:targetId
  // returns:
  //  - {"status":"friends"}
  //  - {"status":"sent","requestId":53}
  //  - {"status":"received","requestId":52}
  //  - {"status":"none"}
  // ============================================================
  static Future<Map<String, dynamic>> getFriendStatus(String targetUserId) async {
    final tid = targetUserId.trim();
    final url = Uri.parse("$baseUrl/status/$tid");
    final headers = await _headers(json: false);

    try {
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = _safeJson(response.body);
        if (data is Map) return Map<String, dynamic>.from(data);
        return {"status": "none"};
      }

      throw Exception(_safeJson(response.body).toString());
    } on SocketException {
      throw Exception("Network error. Check internet connection.");
    } catch (e) {
      if (kDebugMode) print("Get Friend Status Error: $e");
      rethrow;
    }
  }
}
