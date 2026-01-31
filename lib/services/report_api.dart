import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ReportAPI {
  ReportAPI._();

  static const String _apiRoot = "https://adminapi.troonky.in";
  static const String _baseUrl = "$_apiRoot/api/reports";
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

  /// POST /api/reports/reel/:reelId { reason }
  static Future<bool> reportReel({
    required int reelId,
    required String reason,
  }) async {
    final token = await _getToken();
    if (token == null) return false;

    final res = await _client
        .post(
      Uri.parse("$_baseUrl/reel/$reelId"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: jsonEncode({"reason": reason}),
    )
        .timeout(_timeout);

    if (_isAuthFail(res.statusCode)) {
      await _clearToken();
      return false;
    }

    return res.statusCode >= 200 && res.statusCode < 300;
  }
}
