import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class CommentsAPI {
  CommentsAPI._();

  static const String _apiRoot = "https://adminapi.troonky.in";
  static const String _base = "$_apiRoot/api/reel-comments";
  static const String _tokenKey = "token";

  static const Duration _timeout = Duration(seconds: 25);
  static final http.Client _client = http.Client();

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_tokenKey);
    if (t == null) return null;
    final s = t.trim();
    return s.isEmpty ? null : s;
  }

  static Future<void> _clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  static bool _isAuthFail(int status) => status == 401 || status == 403;

  static Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  static Map<String, dynamic> _decodeBody(String body) {
    final b = body.trim();
    if (b.isEmpty) return <String, dynamic>{"success": true};
    try {
      return _asMap(jsonDecode(b));
    } catch (_) {
      return <String, dynamic>{"success": false, "message": "Invalid server response"};
    }
  }

  static String _msg(Map<String, dynamic> m, {String fb = "Request failed"}) {
    return (m["message"] ?? m["error"] ?? m["msg"] ?? fb).toString();
  }

  /// GET /api/reel-comments/:reelId?page=&limit=
  static Future<Map<String, dynamic>> fetchComments({
    required int reelId,
    int page = 1,
    int limit = 20,
  }) async {
    final token = await _getToken();
    if (token == null) throw Exception("Authentication required");

    final uri = Uri.parse("$_base/$reelId?page=$page&limit=$limit");

    final res = await _client
        .get(
      uri,
      headers: {
        "Authorization": "Bearer $token",
        "Accept": "application/json",
      },
    )
        .timeout(_timeout);

    if (_isAuthFail(res.statusCode)) {
      await _clearToken();
      throw Exception("Invalid or expired token");
    }

    final map = _decodeBody(res.body);
    final ok = res.statusCode >= 200 && res.statusCode < 300;
    if (ok && (map["success"] == true || !map.containsKey("success"))) return map;

    throw Exception(_msg(map, fb: "Failed to load comments"));
  }

  /// POST /api/reel-comments/:reelId  {text}
  static Future<bool> addComment({
    required int reelId,
    required String text,
  }) async {
    final token = await _getToken();
    if (token == null) throw Exception("Authentication required");

    final res = await _client
        .post(
      Uri.parse("$_base/$reelId"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: jsonEncode({"text": text}),
    )
        .timeout(_timeout);

    if (_isAuthFail(res.statusCode)) {
      await _clearToken();
      throw Exception("Invalid or expired token");
    }

    final ok = res.statusCode >= 200 && res.statusCode < 300;
    if (!ok) return false;

    // if server returns success flag, respect it
    final map = _decodeBody(res.body);
    if (map.containsKey("success")) return map["success"] == true;
    return true;
  }

  /// DELETE /api/reel-comments/comment/:id
  static Future<bool> deleteComment({required String commentId}) async {
    final token = await _getToken();
    if (token == null) throw Exception("Authentication required");

    final res = await _client
        .delete(
      Uri.parse("$_base/comment/$commentId"),
      headers: {
        "Authorization": "Bearer $token",
        "Accept": "application/json",
      },
    )
        .timeout(_timeout);

    if (_isAuthFail(res.statusCode)) {
      await _clearToken();
      throw Exception("Invalid or expired token");
    }

    final ok = res.statusCode >= 200 && res.statusCode < 300;
    if (!ok) return false;

    final map = _decodeBody(res.body);
    if (map.containsKey("success")) return map["success"] == true;
    return true;
  }

  /// POST /api/reel-comments/comment/:id/pin
  static Future<bool> pinComment({required String commentId}) async {
    final token = await _getToken();
    if (token == null) throw Exception("Authentication required");

    final res = await _client
        .post(
      Uri.parse("$_base/comment/$commentId/pin"),
      headers: {
        "Authorization": "Bearer $token",
        "Accept": "application/json",
      },
    )
        .timeout(_timeout);

    if (_isAuthFail(res.statusCode)) {
      await _clearToken();
      throw Exception("Invalid or expired token");
    }

    final ok = res.statusCode >= 200 && res.statusCode < 300;
    if (!ok) return false;

    final map = _decodeBody(res.body);
    if (map.containsKey("success")) return map["success"] == true;
    return true;
  }
}
