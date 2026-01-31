import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class LikesAPI {
  static const String baseUrl = "https://adminapi.troonky.in/api/likes";

  // ============================================================
  // 🔐 GET TOKEN FROM STORAGE
  // ============================================================
  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("token");
  }

  // ============================================================
  // ❤️ LIKE / UNLIKE A POST  → returns true/false
  // ============================================================
  static Future<bool> toggleLike(int postId) async {
    final token = await _getToken();
    if (token == null) return false;

    final url = Uri.parse("$baseUrl/$postId");

    try {
      final res = await http.post(
        url,
        headers: {"Authorization": "Bearer $token"},
      );

      return res.statusCode == 200;
    } catch (e) {
      print("Like Error: $e");
      return false;
    }
  }

  // ============================================================
  // ⭐ GET LIKE COUNT + USER LIKE STATUS
  // ============================================================
  static Future<Map<String, dynamic>> getLikes(int postId) async {
    final url = Uri.parse("$baseUrl/$postId");

    try {
      final res = await http.get(url);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);

        return {
          "count": data["like_count"] ?? 0,
          "liked": data["is_liked"] ?? false,
        };
      }
    } catch (e) {
      print("Get Likes Error: $e");
    }

    return {"count": 0, "liked": false};
  }
}
