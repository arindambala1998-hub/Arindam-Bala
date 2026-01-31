import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class MessageAPI {
  // ✅ Troonky backend base
  static const String baseUrl = "https://adminapi.troonky.in/api/messages";

  static const Duration _timeout = Duration(seconds: 20);

  // ============================================================
  // Helpers
  // ============================================================
  static Map<String, String> _headers(String token) => {
    "Authorization": "Bearer $token",
    "Accept": "application/json",
  };

  static Map<String, String> _headersJson(String token) => {
    ..._headers(token),
    "Content-Type": "application/json",
  };

  static void _debug(String s) {
    if (kDebugMode) debugPrint(s);
  }

  static String _requireToken(String token) {
    final t = token.trim();
    if (t.isEmpty) throw Exception("Unauthorized: token missing.");
    return t;
  }

  static int _requireId(int id, String name) {
    if (id <= 0) throw Exception("Invalid $name.");
    return id;
  }

  static dynamic _safeJsonDecode(String body) {
    final b = body.trim();
    if (b.isEmpty) return {};
    try {
      return jsonDecode(b);
    } catch (_) {
      return {"_raw": b};
    }
  }

  static Map<String, dynamic> _ensureMap(dynamic decoded) {
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
    return {"data": decoded};
  }

  static String _extractMessage(dynamic decoded, {String fallback = "Request failed"}) {
    try {
      if (decoded is Map) {
        final m = decoded["message"] ??
            decoded["error"] ??
            decoded["msg"] ??
            decoded["detail"] ??
            decoded["errors"];
        if (m is String && m.trim().isNotEmpty) return m.trim();
        if (m is List && m.isNotEmpty) return m.first.toString();
        if (m is Map && m.isNotEmpty) return m.values.first.toString();
        if (decoded["_raw"] != null) return decoded["_raw"].toString();
      }
      if (decoded is String && decoded.trim().isNotEmpty) return decoded.trim();
    } catch (_) {}
    return fallback;
  }

  static bool _successFrom(Map<String, dynamic> map) {
    final s = map["success"];
    if (s is bool) return s;
    if (map["ok"] == true) return true;
    if ((map["status"] ?? "").toString().toLowerCase() == "success") return true;
    return false;
  }

  static Future<Map<String, dynamic>> _get(
      String token,
      Uri url, {
        String fallbackError = "Request failed",
      }) async {
    try {
      final res = await http.get(url, headers: _headers(token)).timeout(_timeout);
      final decoded = _safeJsonDecode(res.body);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final map = _ensureMap(decoded);
        return {"success": _successFrom(map), ...map};
      }

      final msg = _extractMessage(decoded, fallback: fallbackError);
      throw Exception(msg);
    } on TimeoutException {
      throw Exception("Request timeout. Try again.");
    } on SocketException {
      throw Exception("Network error. Check internet connection.");
    }
  }

  static Future<Map<String, dynamic>> _post(
      String token,
      Uri url, {
        Map<String, dynamic>? jsonBody,
        String fallbackError = "Request failed",
      }) async {
    try {
      final res = await http
          .post(
        url,
        headers: jsonBody == null ? _headers(token) : _headersJson(token),
        body: jsonBody == null ? null : jsonEncode(jsonBody),
      )
          .timeout(_timeout);

      final decoded = _safeJsonDecode(res.body);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final map = _ensureMap(decoded);
        return {"success": _successFrom(map), ...map};
      }

      final msg = _extractMessage(decoded, fallback: fallbackError);
      throw Exception(msg);
    } on TimeoutException {
      throw Exception("Request timeout. Try again.");
    } on SocketException {
      throw Exception("Network error. Check internet connection.");
    }
  }

  // ============================================================
  // ✅ SEND MESSAGE (Text or Media)
  // POST /api/messages/send/:friendId   (multipart)
  // fields: text, media
  // ============================================================
  static Future<Map<String, dynamic>> sendMessage({
    required String token,
    required int friendId,
    String? text,
    File? mediaFile,
    String? clientMsgId,
  }) async {
    final t = _requireToken(token);
    _requireId(friendId, "friendId");

    final safeText = (text ?? "").trim();
    if (safeText.isEmpty && mediaFile == null) {
      throw Exception("Message content cannot be empty.");
    }

    final url = Uri.parse("$baseUrl/send/$friendId");

    try {
      final request = http.MultipartRequest("POST", url);
      request.headers.addAll(_headers(t));

      if (safeText.isNotEmpty) request.fields["text"] = safeText;

      // ✅ Idempotency / retry-safe (backend can ignore if unsupported)
      final cmid = (clientMsgId ?? "").trim();
      if (cmid.isNotEmpty) request.fields["client_msg_id"] = cmid;
      

      if (mediaFile != null) {
        request.files.add(await http.MultipartFile.fromPath("media", mediaFile.path));
      }

      final streamed = await request.send().timeout(_timeout);
      final response = await http.Response.fromStream(streamed);
      final decoded = _safeJsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final map = _ensureMap(decoded);
        return {"success": _successFrom(map), ...map};
      }

      final msg = _extractMessage(decoded, fallback: "Failed to send message");
      throw Exception(msg);
    } on TimeoutException {
      throw Exception("Request timeout. Try again.");
    } on SocketException {
      throw Exception("Network error. Check internet connection.");
    } catch (e) {
      _debug("Send Message Error: $e");
      rethrow;
    }
  }

  // ============================================================
  // ✅ GET CONVERSATION
  // GET /api/messages/conversation/:friendId
  // returns: { success:true, conversation_id, messages:[...] }
  // ============================================================
  static Future<Map<String, dynamic>> getConversation({
    required String token,
    required int friendId,
    int? beforeMessageId,
    int limit = 30,
  }) async {
    final t = token.trim();
    if (t.isEmpty || friendId <= 0) return {"success": false, "messages": <dynamic>[]};

    final qp = <String, String>{};
    final b = beforeMessageId ?? 0;
    if (b > 0) qp["before"] = b.toString();
    if (limit > 0) qp["limit"] = limit.toString();

    final url = Uri.parse("$baseUrl/conversation/$friendId").replace(queryParameters: qp.isEmpty ? null : qp);

    try {
      final res = await http.get(url, headers: _headers(t)).timeout(_timeout);
      final decoded = _safeJsonDecode(res.body);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final map = _ensureMap(decoded);
        final msgs = map["messages"] ?? <dynamic>[];
        return {
          ...map,
          "success": _successFrom(map),
          "messages": (msgs is List) ? msgs : <dynamic>[],
        };
      }

      final msg = _extractMessage(decoded, fallback: "Failed to load conversation");
      throw Exception(msg);
    } on TimeoutException {
      throw Exception("Request timeout. Try again.");
    } on SocketException {
      throw Exception("Network error. Check internet connection.");
    } catch (e) {
      _debug("Get Conversation Error: $e");
      return {"success": false, "messages": <dynamic>[]};
    }
  }

  // ============================================================
  // ✅ GET INBOX (conversation list)
  // GET /api/messages/list
  // returns: { success:true, conversations:[...] }
  // ============================================================
  static Future<List<dynamic>> getConversationList({
    required String token,
  }) async {
    final t = token.trim();
    if (t.isEmpty) return <dynamic>[];

    final url = Uri.parse("$baseUrl/list");

    try {
      final res = await http.get(url, headers: _headers(t)).timeout(_timeout);
      final decoded = _safeJsonDecode(res.body);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (decoded is Map) {
          final map = decoded.map((k, v) => MapEntry(k.toString(), v));
          final list = map["conversations"];
          return (list is List) ? list : <dynamic>[];
        }
        return <dynamic>[];
      }

      final msg = _extractMessage(decoded, fallback: "Failed to load inbox");
      throw Exception(msg);
    } on TimeoutException {
      throw Exception("Request timeout. Try again.");
    } on SocketException {
      throw Exception("Network error. Check internet connection.");
    } catch (e) {
      _debug("Get Conversation List Error: $e");
      return <dynamic>[];
    }
  }

  // ============================================================
  // ✅ MARK SEEN
  // POST /api/messages/seen/:friendId
  // ============================================================
  static Future<Map<String, dynamic>> markSeen({
    required String token,
    required int friendId,
  }) async {
    final t = _requireToken(token);
    _requireId(friendId, "friendId");
    final url = Uri.parse("$baseUrl/seen/$friendId");
    return _post(t, url, fallbackError: "Failed to mark seen");
  }

  // ============================================================
  // ✅ DELETE FOR ME
  // POST /api/messages/delete-for-me/:messageId
  // ============================================================
  static Future<Map<String, dynamic>> deleteForMe({
    required String token,
    required int messageId,
  }) async {
    final t = _requireToken(token);
    _requireId(messageId, "messageId");
    final url = Uri.parse("$baseUrl/delete-for-me/$messageId");
    return _post(t, url, fallbackError: "Failed to delete message");
  }

  // ============================================================
  // ✅ DELETE FOR EVERYONE
  // POST /api/messages/delete-for-everyone/:messageId
  // ============================================================
  static Future<Map<String, dynamic>> deleteForEveryone({
    required String token,
    required int messageId,
  }) async {
    final t = _requireToken(token);
    _requireId(messageId, "messageId");
    final url = Uri.parse("$baseUrl/delete-for-everyone/$messageId");
    return _post(t, url, fallbackError: "Failed to delete for everyone");
  }

  // ============================================================
  // ✅ BLOCK / UNBLOCK / STATUS
  // ============================================================
  static Future<Map<String, dynamic>> blockUser({
    required String token,
    required int friendId,
  }) async {
    final t = _requireToken(token);
    _requireId(friendId, "friendId");
    final url = Uri.parse("$baseUrl/block/$friendId");
    return _post(t, url, fallbackError: "Failed to block user");
  }

  static Future<Map<String, dynamic>> unblockUser({
    required String token,
    required int friendId,
  }) async {
    final t = _requireToken(token);
    _requireId(friendId, "friendId");
    final url = Uri.parse("$baseUrl/unblock/$friendId");
    return _post(t, url, fallbackError: "Failed to unblock user");
  }

  static Future<Map<String, dynamic>> blockStatus({
    required String token,
    required int friendId,
  }) async {
    final t = _requireToken(token);
    _requireId(friendId, "friendId");
    final url = Uri.parse("$baseUrl/block-status/$friendId");

    try {
      final res = await _get(t, url, fallbackError: "Failed to check block status");
      return {
        "success": res["success"] == true,
        "blocked_by_me": res["blocked_by_me"] == true,
        "blocked_me": res["blocked_me"] == true,
        ...res,
      };
    } catch (e) {
      _debug("Block Status Error: $e");
      return {"success": false, "blocked_by_me": false, "blocked_me": false};
    }
  }

  // ============================================================
  // ✅ CLEAR CHAT FOR ME (frontend-only implementation)
  // Backend "delete-conversation" route নাই, তাই:
  // GET conversation -> POST delete-for-me each message
  // ============================================================
  static Future<Map<String, dynamic>> clearConversationForMe({
    required String token,
    required int friendId,
  }) async {
    final t = _requireToken(token);
    _requireId(friendId, "friendId");

    final conv = await getConversation(token: t, friendId: friendId);
    final msgs = (conv["messages"] is List) ? (conv["messages"] as List) : <dynamic>[];

    if (msgs.isEmpty) {
      return {"success": true, "deleted": 0, "friendId": friendId};
    }

    int deleted = 0;

    for (final m in msgs) {
      try {
        if (m is Map) {
          final id = int.tryParse((m["id"] ?? "").toString()) ?? 0;
          if (id > 0) {
            final r = await deleteForMe(token: t, messageId: id);
            if (r["success"] == true) deleted++;
          }
        }
      } catch (_) {
        // continue
      }
    }

    return {"success": true, "deleted": deleted, "friendId": friendId};
  }

  // ============================================================
  // ✅ BACKWARD COMPAT alias (if your UI calls deleteConversation)
  // ============================================================
  static Future<Map<String, dynamic>> deleteConversation({
    required String token,
    required int friendId,
  }) {
    return clearConversationForMe(token: token, friendId: friendId);
  }
}
