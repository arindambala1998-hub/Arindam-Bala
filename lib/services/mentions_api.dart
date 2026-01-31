import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class MessageAPI {
  // Your live base
  static const String baseUrl = "https://adminapi.troonky.in/api/messages";

  // ✅ Your backend uses this field for multipart media upload.
  // If your backend expects "mediaFile" or "file", just change here.
  static const String mediaFieldName = "media";

  // ------------------------------------------------------------
  // helpers
  // ------------------------------------------------------------
  static Map<String, String> _headers(String token, {bool json = false}) {
    final h = <String, String>{
      "Authorization": "Bearer $token",
      "Accept": "application/json",
    };
    if (json) h["Content-Type"] = "application/json";
    return h;
  }

  static dynamic _tryDecode(String body) {
    try {
      if (body.trim().isEmpty) return null;
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  static String _extractError(dynamic decoded, int statusCode) {
    if (decoded is Map) {
      final m = Map<String, dynamic>.from(decoded);
      final msg = m["message"] ?? m["error"] ?? m["errors"] ?? m["detail"];
      if (msg != null) return msg.toString();
    }
    return "Request failed ($statusCode)";
  }

  // ============================================================
  // 💬 SEND MESSAGE (Text or Media)
  // POST /api/messages/send/:friendId
  // multipart: text + media
  // ============================================================
  static Future<Map<String, dynamic>> sendMessage({
    required String token,
    required int friendId,
    String? text,
    File? mediaFile,
  }) async {
    final t = (text ?? "").trim();
    if (t.isEmpty && mediaFile == null) {
      return {"ok": false, "success": false, "message": "Message content cannot be empty"};
    }

    final url = Uri.parse("$baseUrl/send/$friendId");

    try {
      final req = http.MultipartRequest("POST", url);
      req.headers.addAll(_headers(token));

      if (t.isNotEmpty) {
        req.fields["text"] = t;
      }

      if (mediaFile != null) {
        req.files.add(
          await http.MultipartFile.fromPath(mediaFieldName, mediaFile.path),
        );
      }

      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);

      final decoded = _tryDecode(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        // normalize success shape
        if (decoded is Map) {
          return {"ok": true, "success": true, ...Map<String, dynamic>.from(decoded)};
        }
        return {"ok": true, "success": true};
      }

      final msg = _extractError(decoded, res.statusCode);
      return {"ok": false, "success": false, "message": msg, "status": res.statusCode};
    } on SocketException {
      return {"ok": false, "success": false, "message": "Network error. Check internet connection."};
    } catch (e) {
      if (kDebugMode) debugPrint("Send Message Error: $e");
      return {"ok": false, "success": false, "message": e.toString()};
    }
  }

  // ============================================================
  // 📜 GET FULL CONVERSATION (Chat History)
  // GET /api/messages/conversation/:friendId
  // ============================================================
  static Future<Map<String, dynamic>> getConversation({
    required String token,
    required int friendId,
  }) async {
    final url = Uri.parse("$baseUrl/conversation/$friendId");

    try {
      final res = await http.get(url, headers: _headers(token));
      final decoded = _tryDecode(res.body);

      if (res.statusCode == 200) {
        if (decoded is Map) {
          return {"ok": true, "success": true, ...Map<String, dynamic>.from(decoded)};
        }
        // if server returns list directly
        if (decoded is List) {
          return {"ok": true, "success": true, "messages": decoded};
        }
        return {"ok": true, "success": true, "messages": []};
      }

      final msg = _extractError(decoded, res.statusCode);
      return {"ok": false, "success": false, "message": msg, "status": res.statusCode, "messages": []};
    } on SocketException {
      return {"ok": false, "success": false, "message": "Network error. Check internet connection.", "messages": []};
    } catch (e) {
      if (kDebugMode) debugPrint("Get Conversation Error: $e");
      return {"ok": false, "success": false, "message": e.toString(), "messages": []};
    }
  }

  // ============================================================
  // 📬 GET ALL CONVERSATIONS (Inbox)
  // GET /api/messages/list
  // ============================================================
  static Future<List<Map<String, dynamic>>> getConversationList({
    required String token,
  }) async {
    final url = Uri.parse("$baseUrl/list");

    try {
      final res = await http.get(url, headers: _headers(token));
      final decoded = _tryDecode(res.body);

      if (res.statusCode == 200) {
        // supports: {conversations:[...]} OR [...]
        List list = [];
        if (decoded is List) list = decoded;
        if (decoded is Map) {
          list = (decoded["conversations"] ??
              decoded["items"] ??
              decoded["data"] ??
              decoded["chats"] ??
              []) as List? ??
              [];
        }

        return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }

      final msg = _extractError(decoded, res.statusCode);
      if (kDebugMode) debugPrint("Inbox load failed: $msg");
      return [];
    } on SocketException {
      if (kDebugMode) debugPrint("Inbox Network error");
      return [];
    } catch (e) {
      if (kDebugMode) debugPrint("Get Conversation List Error: $e");
      return [];
    }
  }
}
