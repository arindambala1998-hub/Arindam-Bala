import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'; // compute
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReelsAPI {
  ReelsAPI._();

  // =========================
  // CONFIG
  // =========================
  static const String apiRoot = "https://adminapi.troonky.in";
  static const String _tokenKey = "token";

  static const String _reelsBase = "$apiRoot/api/reels";
  static const String _reelCommentsBase = "$apiRoot/api/reel-comments";
  static const String _messagesBase = "$apiRoot/api/messages";

  static const Duration _timeout = Duration(seconds: 25);

  /// Persistent keep-alive client (better performance)
  static final http.Client _client = http.Client();

  // =========================
  // TOKEN
  // =========================
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

  static bool _isAuthFail(int code) => code == 401 || code == 403;

  // =========================
  // SAFE HELPERS
  // =========================
  static int _asInt(dynamic v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  static bool _asBool(dynamic v, {bool fallback = false}) {
    if (v is bool) return v;
    if (v is int) return v == 1;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (["true", "1", "yes"].contains(s)) return true;
      if (["false", "0", "no"].contains(s)) return false;
    }
    return fallback;
  }

  static Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  static String _msgFrom(Map<String, dynamic> m, {String fallback = "Request failed"}) {
    return (m["message"] ?? m["error"] ?? m["msg"] ?? fallback).toString();
  }

  static String _sanitizePrivacy(String v) {
    final s = v.trim().toLowerCase();
    if (s == "friends") return "friends";
    return "public";
  }

  static String _absUrlIfNeeded(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return s;
    if (s.startsWith("http://") || s.startsWith("https://")) return s;
    if (s.startsWith("/")) return "$apiRoot$s";
    return "$apiRoot/$s";
  }

  static Map<String, dynamic> _decodeToMap(String body) {
    final b = body.trim();
    if (b.isEmpty) return <String, dynamic>{"success": true};
    try {
      final decoded = jsonDecode(b);
      return _asMap(decoded);
    } catch (_) {
      return <String, dynamic>{"success": false, "message": "Invalid server response"};
    }
  }

  // =========================
  // CORE HTTP
  // =========================
  static Future<Map<String, dynamic>> _getJson(String url) async {
    final token = await _getToken();
    if (token == null) throw Exception("Authentication required");

    http.Response res;
    try {
      res = await _client.get(
        Uri.parse(url),
        headers: {
          "Authorization": "Bearer $token",
          "Accept": "application/json",
        },
      ).timeout(_timeout);
    } catch (e) {
      throw Exception("Network error: $e");
    }

    if (_isAuthFail(res.statusCode)) {
      await _clearToken();
      throw Exception("Invalid or expired token");
    }

    final map = _decodeToMap(res.body);
    final okStatus = res.statusCode >= 200 && res.statusCode < 300;
    final ok =
        okStatus && (!_asBool(map["error"])) && (!map.containsKey("success") || _asBool(map["success"], fallback: true));
    if (ok) return map;

    throw Exception(_msgFrom(map));
  }

  static Future<Map<String, dynamic>> _postJson(
      String url,
      Map<String, dynamic> body, {
        bool auth = true,
      }) async {
    final token = await _getToken();
    if (auth && token == null) throw Exception("Authentication required");

    http.Response res;
    try {
      res = await _client
          .post(
        Uri.parse(url),
        headers: {
          if (auth) "Authorization": "Bearer $token",
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode(body),
      )
          .timeout(_timeout);
    } catch (e) {
      throw Exception("Network error: $e");
    }

    if (_isAuthFail(res.statusCode)) {
      await _clearToken();
      throw Exception("Invalid or expired token");
    }

    final map = _decodeToMap(res.body);
    final okStatus = res.statusCode >= 200 && res.statusCode < 300;
    final ok =
        okStatus && (!_asBool(map["error"])) && (!map.containsKey("success") || _asBool(map["success"], fallback: true));
    if (ok) return map;

    throw Exception(_msgFrom(map));
  }

  // =========================
  // REELS FEED
  // =========================
  static Future<List<Map<String, dynamic>>> getReels({
    int page = 1,
    int limit = 15,
  }) async {
    final token = await _getToken();
    if (token == null) return [];

    final uri = Uri.parse("$_reelsBase?page=$page&limit=$limit");
    try {
      final res = await _client.get(
        uri,
        headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
      ).timeout(_timeout);

      if (_isAuthFail(res.statusCode)) {
        await _clearToken();
        return [];
      }
      if (res.statusCode != 200) return [];

      // heavy parse off UI thread
      return await compute(_parseReelsBody, res.body);
    } catch (_) {
      return [];
    }
  }

  static List<Map<String, dynamic>> _parseReelsBody(String body) {
    try {
      final decoded = jsonDecode(body);
      final map = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
      final raw = map["reels"] ?? map["data"] ?? map["results"] ?? <dynamic>[];

      if (raw is! List) return [];

      return raw.whereType<Map>().map((e) {
        final m = Map<String, dynamic>.from(e);

        m["id"] = (m["id"] ?? m["reel_id"] ?? m["video_id"]).toString();
        m["status"] = (m["status"] ?? "ready").toString();

        m["video_url"] = (m["video_url"] ?? m["video"] ?? "").toString();
        m["video_url_low"] = (m["video_url_low"] ?? m["video_low"] ?? "").toString();
        m["thumb_url"] = (m["thumb_url"] ?? m["thumbnail"] ?? m["thumb"] ?? "").toString();
        m["title"] = (m["title"] ?? m["caption"] ?? "").toString();

        m["likes"] = _asInt(m["likes"] ?? m["like_count"]);
        m["comments"] = _asInt(m["comments"] ?? m["comment_count"]);
        m["shares"] = _asInt(m["shares"] ?? m["share_count"]);
        m["views"] = _asInt(m["views"] ?? m["view_count"] ?? m["play_count"] ?? m["plays"] ?? m["total_views"]);

        m["is_liked"] = _asBool(m["is_liked"] ?? m["liked"]);
        m["is_subscribed"] = _asBool(m["is_subscribed"] ?? m["subscribed"]);
        m["subscriber_count"] = _asInt(m["subscriber_count"] ?? m["subscribers"] ?? m["followers_count"]);

        m["privacy"] = (m["privacy"] ?? "public").toString();

        m["user_id"] = (m["user_id"] ?? m["creator_id"] ?? m["owner_id"] ?? "").toString();
        m["username"] = (m["username"] ?? m["user_name"] ?? m["name"] ?? "").toString();

        final rawAvatar = (m["user_avatar"] ?? m["user_profile_pic"] ?? m["avatar"] ?? "").toString();
        m["user_avatar"] = _absUrlIfNeeded(rawAvatar);

        m["tagged_products"] = (m["tagged_products"] is List) ? m["tagged_products"] : [];

        return m;
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // =========================
  // STATUS
  // =========================
  static Future<Map<String, dynamic>> getReelStatus(String reelId) async {
    return _getJson("$_reelsBase/$reelId/status");
  }

  // =========================
  // TRACK VIEW (fire & forget)
  // =========================
  static Future<void> trackReelView({
    required String reelId,
    required int watchTimeInSeconds,
    required bool completed,
    String source = "home_feed",
  }) async {
    // no await for UI smoothness
    _getToken().then((token) {
      if (token == null) return;
      _client
          .post(
        Uri.parse("$_reelsBase/track-view"),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode({
          "reel_id": reelId,
          "watch_time": watchTimeInSeconds,
          "completed": completed,
          "source": source,
        }),
      )
          .catchError((_) {});
    });
  }

  // =========================
  // UPLOAD REEL (Dio multipart)
  // =========================
  static Future<Map<String, dynamic>> uploadReel({
    required File videoFile,
    String? caption,
    String privacy = "public",
    List<String>? productIds,
    void Function(int sent, int total)? onProgress,
    String videoField = "videoFile",
    CancelToken? cancelToken,
  }) async {
    final token = await _getToken();
    if (token == null) throw Exception("Authentication required");
    if (!videoFile.existsSync()) throw Exception("Video file not found");

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 90),
        sendTimeout: const Duration(minutes: 10),
        headers: {
          "Authorization": "Bearer $token",
          "Accept": "application/json",
        },
        validateStatus: (code) => code != null && code >= 200 && code < 600,
      ),
    );

    Future<Map<String, dynamic>> _tryField(String field) async {
      final fileName = videoFile.path.split(Platform.pathSeparator).last;

      final form = FormData();
      final cap = caption?.trim() ?? "";
      if (cap.isNotEmpty) form.fields.add(MapEntry("caption", cap));

      form.fields.add(MapEntry("privacy", _sanitizePrivacy(privacy)));

      if (productIds != null && productIds.isNotEmpty) {
        form.fields.add(MapEntry("tagged_products", jsonEncode(productIds)));
      }

      form.files.add(
        MapEntry(
          field,
          await MultipartFile.fromFile(
            videoFile.path,
            filename: fileName,
            contentType: MediaType("video", "mp4"),
          ),
        ),
      );

      final res = await dio.post(
        "$_reelsBase/upload",
        data: form,
        cancelToken: cancelToken,
        onSendProgress: (sent, total) => onProgress?.call(sent, total),
        options: Options(contentType: "multipart/form-data"),
      );

      final status = res.statusCode ?? 0;

      if (_isAuthFail(status)) {
        await _clearToken();
        throw Exception("Invalid or expired token");
      }

      Map<String, dynamic> map;
      try {
        if (res.data is Map) {
          map = Map<String, dynamic>.from(res.data);
        } else if (res.data is String) {
          map = _asMap(jsonDecode(res.data as String));
        } else {
          map = {"success": false, "message": "Invalid server response"};
        }
      } catch (_) {
        map = {"success": false, "message": "Invalid server response"};
      }

      final okStatus = status >= 200 && status < 300;
      final ok = okStatus &&
          (!_asBool(map["error"])) &&
          (!map.containsKey("success") || _asBool(map["success"], fallback: true));

      if (!ok) throw Exception(_msgFrom(map));

      // normalize reelId
      final rid = (map["reelId"] ??
          map["reel_id"] ??
          map["id"] ??
          (map["data"] is Map ? (map["data"]["id"] ?? map["data"]["reel_id"]) : null))
          ?.toString();
      if (rid != null && rid.trim().isNotEmpty) {
        map["reelId"] = rid.trim();
      }

      return map;
    }

    try {
      return await _tryField(videoField);
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final isFieldIssue =
          msg.contains("missing") || msg.contains("required") || msg.contains("videofile") || msg.contains("video file");
      if (!isFieldIssue) rethrow;

      final alt = (videoField == "videoFile") ? "video" : "videoFile";
      return await _tryField(alt);
    } finally {
      dio.close(force: true);
    }
  }

  // =========================
  // INTERACTIONS
  // =========================
  static Future<Map<String, dynamic>> toggleLike({
    required String reelId,
    required bool like,
  }) async {
    return _postJson(
      like ? "$_reelsBase/like" : "$_reelsBase/unlike",
      {"reel_id": reelId},
    );
  }

  static Future<Map<String, dynamic>> shareReel({
    required String reelId,
    String channel = "native_share",
  }) async {
    return _postJson(
      "$_reelsBase/share",
      {"reel_id": reelId, "channel": channel},
    );
  }

  static Future<Map<String, dynamic>> subscribeCreator({
    required String creatorUserId,
  }) async {
    return _postJson("$_reelsBase/subscribe", {"creator_user_id": creatorUserId});
  }

  static Future<Map<String, dynamic>> unsubscribeCreator({
    required String creatorUserId,
  }) async {
    return _postJson("$_reelsBase/unsubscribe", {"creator_user_id": creatorUserId});
  }

  static Future<Map<String, dynamic>> hideReel(String reelId) async {
    return _postJson("$_reelsBase/$reelId/hide", {});
  }

  static Future<Map<String, dynamic>> blockReel(String reelId) async {
    return _postJson("$_reelsBase/$reelId/block", {});
  }

  // =========================
  // COMMENTS (optional usage)
  // =========================
  static Future<Map<String, dynamic>> getComments({
    required String reelId,
    int page = 1,
    int limit = 20,
  }) async {
    return _getJson("$_reelCommentsBase/$reelId?page=$page&limit=$limit");
  }

  static Future<Map<String, dynamic>> addComment({
    required String reelId,
    required String text,
  }) async {
    return _postJson("$_reelCommentsBase/$reelId", {"text": text});
  }

  static Future<Map<String, dynamic>> deleteComment({
    required String commentId,
  }) async {
    final token = await _getToken();
    if (token == null) throw Exception("Authentication required");

    http.Response res;
    try {
      res = await _client.delete(
        Uri.parse("$_reelCommentsBase/comment/$commentId"),
        headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
      ).timeout(_timeout);
    } catch (e) {
      throw Exception("Network error: $e");
    }

    if (_isAuthFail(res.statusCode)) {
      await _clearToken();
      throw Exception("Invalid or expired token");
    }

    final ok = res.statusCode >= 200 && res.statusCode < 300;
    if (ok) return {"success": true};
    throw Exception("Delete failed (${res.statusCode})");
  }

  static Future<Map<String, dynamic>> pinComment({
    required String commentId,
  }) async {
    return _postJson("$_reelCommentsBase/comment/$commentId/pin", {});
  }

  // =========================
  // UNREAD MESSAGE COUNT (badge)
  // =========================
  static Future<int> getMessageCount() async {
    try {
      final r = await _postJson("$_messagesBase/unread-count", {});
      return _asInt(r["count"] ?? r["unread"]);
    } catch (_) {
      return 0;
    }
  }

  // =========================
  // DELETE REEL (if route exists)
  // =========================
  static Future<bool> deleteReel(String reelId) async {
    final token = await _getToken();
    if (token == null) throw Exception("Authentication required");

    http.Response res;
    try {
      res = await _client.delete(
        Uri.parse("$_reelsBase/$reelId"),
        headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
      ).timeout(_timeout);
    } catch (e) {
      throw Exception("Network error: $e");
    }

    if (_isAuthFail(res.statusCode)) {
      await _clearToken();
      throw Exception("Invalid or expired token");
    }

    return res.statusCode >= 200 && res.statusCode < 300;
  }
}
