import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ProfileAPI {
  static const String baseUrl = "https://adminapi.troonky.in/api/profile";

  // =========================
  // GET MY PROFILE
  // =========================
  static Future<Map<String, dynamic>> getMyProfile(String token) async {
    final url = Uri.parse("$baseUrl/me");

    try {
      final response = await http.get(
        url,
        headers: {
          "Authorization": "Bearer $token",
          "Accept": "application/json",
        },
      );

      final body = _safeJson(response.body);

      if (response.statusCode == 200) {
        return {"success": true, ...body};
      }

      return {
        "success": false,
        "message": body["message"] ?? "Failed to load profile",
        "status": response.statusCode,
        "raw": body,
      };
    } catch (e) {
      if (kDebugMode) print("ProfileAPI.getMyProfile Error: $e");
      return {
        "success": false,
        "message": "Server error: $e",
      };
    }
  }

  // =========================
  // GET PROFILE BY ID (token optional)
  // =========================
  static Future<Map<String, dynamic>> getProfileById(
      String id, {
        String? token,
      }) async {
    final url = Uri.parse("$baseUrl/$id");

    try {
      final headers = <String, String>{
        "Accept": "application/json",
      };

      if (token != null && token.trim().isNotEmpty) {
        headers["Authorization"] = "Bearer $token";
      }

      final response = await http.get(url, headers: headers);
      final body = _safeJson(response.body);

      if (response.statusCode == 200) {
        return {"success": true, ...body};
      }

      return {
        "success": false,
        "message": body["message"] ?? "User profile not found",
        "status": response.statusCode,
        "raw": body,
      };
    } catch (e) {
      if (kDebugMode) print("ProfileAPI.getProfileById Error: $e");
      return {
        "success": false,
        "message": "Server error: $e",
      };
    }
  }

  // =========================
  // UPDATE BIO
  // =========================
  static Future<Map<String, dynamic>> updateBio({
    required String token,
    required Map<String, dynamic> data,
  }) async {
    final url = Uri.parse("$baseUrl/update-bio");

    try {
      final response = await http.post(
        url,
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode(data),
      );

      final body = _safeJson(response.body);

      if (response.statusCode == 200) {
        return {
          "success": true,
          "message": body["message"] ?? "Profile updated",
          ...body,
        };
      }

      return {
        "success": false,
        "message": body["message"] ?? "Failed to update profile",
        "status": response.statusCode,
        "raw": body,
      };
    } catch (e) {
      if (kDebugMode) print("ProfileAPI.updateBio Error: $e");
      return {
        "success": false,
        "message": "Server error: $e",
      };
    }
  }

  // =========================
  // UPDATE ANY FIELD
  // =========================
  static Future<Map<String, dynamic>> updateProfileField(
      String token,
      String fieldKey,
      String value,
      ) async {
    final url = Uri.parse("$baseUrl/update-field");
    final payload = {"key": fieldKey, "value": value};

    try {
      final response = await http.post(
        url,
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode(payload),
      );

      final body = _safeJson(response.body);

      if (response.statusCode == 200) {
        return {"success": true, ...body};
      }

      return {
        "success": false,
        "message": body["message"] ?? "Update failed",
        "status": response.statusCode,
        "raw": body,
      };
    } catch (e) {
      if (kDebugMode) print("ProfileAPI.updateProfileField Error: $e");
      return {
        "success": false,
        "message": "Server error: $e",
      };
    }
  }

  // =========================
  // SEND FRIEND REQUEST
  // =========================
  static Future<Map<String, dynamic>> sendFriendRequest(
      String token,
      String targetUserId,
      ) async {
    final url = Uri.parse("$baseUrl/send-friend-request");
    final payload = {"user_id": targetUserId};

    try {
      final response = await http.post(
        url,
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode(payload),
      );

      final body = _safeJson(response.body);

      if (response.statusCode == 200) {
        return {"success": true, ...body};
      }

      return {
        "success": false,
        "message": body["message"] ?? "Request failed",
        "status": response.statusCode,
        "raw": body,
      };
    } catch (e) {
      if (kDebugMode) print("ProfileAPI.sendFriendRequest Error: $e");
      return {
        "success": false,
        "message": "Server error: $e",
      };
    }
  }

  // =========================
  // UPLOAD IMAGE
  // =========================
  static Future<Map<String, dynamic>> uploadImage({
    required String token,
    required File imageFile,
    required String type, // "profile" | "cover" etc.
  }) async {
    final url = Uri.parse("$baseUrl/upload-pic");

    try {
      final request = http.MultipartRequest("POST", url);
      request.headers["Authorization"] = "Bearer $token";
      request.headers["Accept"] = "application/json";
      request.fields["type"] = type;

      request.files.add(
        await http.MultipartFile.fromPath("image", imageFile.path),
      );

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      final body = _safeJson(response.body);

      if (response.statusCode == 200) {
        return {
          "success": true,
          "message": body["message"] ?? "Image uploaded",
          ...body,
        };
      }

      return {
        "success": false,
        "message": body["message"] ?? "Image upload failed",
        "status": response.statusCode,
        "raw": body,
      };
    } catch (e) {
      if (kDebugMode) print("ProfileAPI.uploadImage Error: $e");
      return {
        "success": false,
        "message": "Upload error: $e",
      };
    }
  }

  // =========================
  // SAFE JSON PARSER
  // =========================
  static Map<String, dynamic> _safeJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {"raw": decoded};
    } catch (_) {
      return {"raw": body};
    }
  }
}
