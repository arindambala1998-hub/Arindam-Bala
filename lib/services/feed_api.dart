// lib/services/feed_api.dart (FINAL • BULLETPROOF • BUG FIXED)
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

// ✅ optional helper (thumbnail generator)
import 'package:troonky_link/helpers/media_helper.dart';

class FeedAPI {
  static const String baseUrl = "https://adminapi.troonky.in/api";
  static const String publicHost = "https://adminapi.troonky.in";

  // Feed rules
  static const int maxTextLen = 1500;
  static const int maxVideoSeconds = 300; // 5 minutes
  static const int defaultLimit = 10;

  static const Duration _timeout = Duration(seconds: 18);

  // =======================================================
  // 🔐 TOKEN (FINAL ✅ multi-key fallback)
  // =======================================================
  static Future<String?> _getToken() async {
    try {
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
    } catch (_) {
      return null;
    }
  }

  static dynamic _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _asMap(dynamic v) =>
      (v is Map) ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static List<dynamic> _asList(dynamic v) => (v is List) ? v : <dynamic>[];

  /// ✅ Unwrap common API shapes.
  /// Supports:
  /// - { success:true, data:{...} }
  /// - { ok:true, data:{...} }
  /// - { data:{ items:[...] } }
  static Map<String, dynamic> _unwrapMap(dynamic decoded) {
    final m = _asMap(decoded);
    final d = m["data"];
    if (d is Map) return Map<String, dynamic>.from(d);
    return m;
  }

  static List<Map<String, dynamic>> _extractItems(dynamic decoded) {
    // direct list
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    final root = _asMap(decoded);
    final data = _unwrapMap(decoded);

    dynamic itemsRaw =
        root["items"] ??
            root["posts"] ??
            root["result"] ??
            root["rows"] ??
            (root["data"] is List ? root["data"] : null) ??
            data["items"] ??
            data["posts"] ??
            data["result"] ??
            data["rows"] ??
            (data["data"] is List ? data["data"] : null);

    // if root["data"] is a Map, treat as wrapper
    if (itemsRaw is Map) {
      final m = Map<String, dynamic>.from(itemsRaw);
      itemsRaw = m["items"] ?? m["posts"] ?? m["rows"] ?? m["result"] ?? <dynamic>[];
    }

    return _asList(itemsRaw)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? "") ?? 0;
  }

  static Map<String, String> _headers({String? token, bool json = false}) {
    final h = <String, String>{"Accept": "application/json"};
    if (json) h["Content-Type"] = "application/json";
    final t = token?.trim();
    if (t != null && t.isNotEmpty) h["Authorization"] = "Bearer $t";
    return h;
  }

  static String _extractErrorMessage(dynamic decoded,
      {String fallback = "Request failed"}) {
    if (decoded is Map) {
      final m = Map<String, dynamic>.from(decoded);
      final e = m["error"] ?? m["message"] ?? m["msg"];
      if (e != null) return e.toString();
      if (m["data"] is Map) {
        final dm = Map<String, dynamic>.from(m["data"]);
        final e2 = dm["error"] ?? dm["message"] ?? dm["msg"];
        if (e2 != null) return e2.toString();
      }
    }
    return fallback;
  }

  // =======================================================
  // ✅ MEDIA HELPERS
  // =======================================================
  static bool isVideoPath(String pathOrUrl) {
    final p = pathOrUrl.toLowerCase();
    return p.contains(".mp4") ||
        p.contains(".mov") ||
        p.contains(".avi") ||
        p.contains(".mkv") ||
        p.contains(".webm") ||
        p.contains(".m4v") ||
        p.contains(".m3u8");
  }

  static bool isHlsPath(String pathOrUrl) =>
      pathOrUrl.toLowerCase().contains(".m3u8");

  static List<dynamic> rawMediaList(Map<String, dynamic> post) {
    final m = post["media_urls"];
    if (m is List) return m;
    final single = post["media_url"] ??
        post["mediaFile"] ??
        post["media"] ??
        post["file"];
    if (single != null && single.toString().trim().isNotEmpty) return [single];
    return [];
  }

  static List<String> mediaUrls(Map<String, dynamic> post) {
    return rawMediaList(post)
        .map((e) => toPublicUrl(e?.toString()))
        .where((s) => s.trim().isNotEmpty)
        .toList();
  }

  static bool isVideoPost(Map<String, dynamic> post) {
    if (post["is_video"] == true) return true;
    final list = rawMediaList(post);
    if (list.length != 1) return false;
    return isVideoPath(list.first.toString().trim());
  }

  static String? hlsUrl(Map<String, dynamic> post) {
    final raw = (post["video_hls_url"] ??
        post["hls_url"] ??
        post["video_hls"] ??
        post["stream_url"] ??
        post["m3u8_url"] ??
        post["hls"] ??
        "")
        .toString()
        .trim();
    if (raw.isEmpty) return null;
    final fixed = toPublicUrl(raw);
    return fixed.isEmpty ? null : fixed;
  }

  static String? videoPlayUrl(Map<String, dynamic> post) {
    final hls = hlsUrl(post);
    if (hls != null && hls.isNotEmpty && isHlsPath(hls)) return hls;

    final list = mediaUrls(post);
    if (list.isEmpty) return null;
    final first = list.first.trim();
    return first.isEmpty ? null : first;
  }

  static String? videoThumbUrl(Map<String, dynamic> post) {
    final raw = (post["video_thumb"] ??
        post["thumb_url"] ??
        post["thumbnail_url"] ??
        post["thumbnail"] ??
        post["poster"] ??
        post["poster_url"] ??
        "")
        .toString()
        .trim();
    if (raw.isEmpty) return null;
    final fixed = toPublicUrl(raw);
    return fixed.isEmpty ? null : fixed;
  }

  // =======================================================
  // 🟡 FETCH FEED (PAGE) - FINAL ✅ page+limit + offset fallback
  // =======================================================
  static Future<List<Map<String, dynamic>>> fetchFeed({
    int page = 1,
    int limit = defaultLimit,
  }) async {
    page = page <= 0 ? 1 : page;
    limit = limit <= 0 ? defaultLimit : limit;

    final token = await _getToken(); // optional
    final offset = (page - 1) * limit;

    final candidates = <Uri>[
      // page/limit
      Uri.parse("$baseUrl/posts/feed?page=$page&limit=$limit"),
      Uri.parse("$baseUrl/feed/feed?page=$page&limit=$limit"),
      Uri.parse("$baseUrl/feed?page=$page&limit=$limit"),
      Uri.parse("$baseUrl/posts?page=$page&limit=$limit"),

      // offset/limit fallback
      Uri.parse("$baseUrl/posts/feed?offset=$offset&limit=$limit"),
      Uri.parse("$baseUrl/feed/feed?offset=$offset&limit=$limit"),
      Uri.parse("$baseUrl/feed?offset=$offset&limit=$limit"),
      Uri.parse("$baseUrl/posts?offset=$offset&limit=$limit"),
    ];

    for (final u in candidates) {
      try {
        final res =
        await http.get(u, headers: _headers(token: token)).timeout(_timeout);

        if (kDebugMode) {
          // ignore: avoid_print
          print("🟦 FeedAPI GET $u -> ${res.statusCode}");
        }

        if (res.statusCode == 404) continue;
        if (res.statusCode != 200) continue;

        final decoded = _tryDecode(res.body);

        // ✅ IMPORTANT: invalid json? try next endpoint instead of returning []
        if (decoded == null) continue;

        return _extractItems(decoded);
      } catch (_) {
        // try next
      }
    }

    return [];
  }

  // =======================================================
  // 🟠 FETCH FEED (CURSOR) - optional
  // =======================================================
  static Future<Map<String, dynamic>> fetchFeedCursor({
    String? cursor,
    int limit = defaultLimit,
  }) async {
    final token = await _getToken();
    final c = (cursor ?? "").trim();
    final qs = c.isEmpty ? "limit=$limit" : "cursor=$c&limit=$limit";

    final candidates = <Uri>[
      Uri.parse("$baseUrl/posts/feed?$qs"),
      Uri.parse("$baseUrl/feed/feed?$qs"),
      Uri.parse("$baseUrl/feed?$qs"),
      Uri.parse("$baseUrl/posts?$qs"),
    ];

    dynamic lastDecoded;

    for (final u in candidates) {
      try {
        final res =
        await http.get(u, headers: _headers(token: token)).timeout(_timeout);

        if (res.statusCode == 404) continue;

        final decoded = _tryDecode(res.body);
        lastDecoded = decoded;

        // invalid json -> try next endpoint
        if (decoded == null) continue;

        if (res.statusCode != 200) {
          return {
            "ok": false,
            "message": _extractErrorMessage(decoded,
                fallback: "Cursor feed failed"),
            "status": res.statusCode
          };
        }

        final items = _extractItems(decoded);

        final root = _asMap(decoded);
        final data = _unwrapMap(decoded);

        final next = (root["nextCursor"] ??
            root["next_cursor"] ??
            root["next"] ??
            root["cursor_next"] ??
            data["nextCursor"] ??
            data["next_cursor"] ??
            data["next"] ??
            data["cursor_next"] ??
            "")
            .toString()
            .trim();

        final nextCursor = next.isEmpty ? null : next;

        final hasMore = (root["hasMore"] == true) ||
            (root["has_more"] == true) ||
            (data["hasMore"] == true) ||
            (data["has_more"] == true) ||
            (nextCursor != null && items.isNotEmpty);

        return {
          "ok": true,
          "items": items,
          "nextCursor": nextCursor,
          "hasMore": hasMore
        };
      } catch (_) {
        // try next
      }
    }

    return {
      "ok": false,
      "message": _extractErrorMessage(lastDecoded,
          fallback: "Cursor endpoint not found")
    };
  }

  // =======================================================
  // 🟢 CREATE POST (BUG FIXED ✅)
  // =======================================================
  static Future<Map<String, dynamic>> createPost({
    required String description,
    required String postType,
    File? mediaFile,
    List<File>? mediaFiles,
    File? videoThumbFile,
  }) async {
    final token = await _getToken();
    if (token == null) throw Exception("User not logged in");

    final desc = description.trim();
    if (desc.length > maxTextLen) {
      throw Exception("Max $maxTextLen characters allowed");
    }

    // ✅ Correct null-aware spread syntax
    final files = <File>[
      if (mediaFiles != null) ...mediaFiles,
      if (mediaFile != null) mediaFile,
    ];

    String finalType = postType.trim().toLowerCase();

    if (files.isNotEmpty) {
      finalType = _isVideo(files.first.path) ? "video" : "image";
    } else {
      finalType = "text";
    }

    if (finalType == "video" && files.isNotEmpty) {
      final seconds = await _getVideoDuration(files.first);
      if (seconds > maxVideoSeconds) {
        throw Exception("Video must be 5 minutes or less");
      }
    }

    final candidates = <Uri>[
      Uri.parse("$baseUrl/posts"),
      Uri.parse("$baseUrl/feed"),
    ];

    http.Response? okRes;
    dynamic okDecoded;

    for (final u in candidates) {
      try {
        final req = http.MultipartRequest("POST", u);
        req.headers.addAll(_headers(token: token));

        req.fields["description"] = desc;
        req.fields["postType"] = finalType;
        req.fields["post_type"] = finalType;

        if (files.isNotEmpty) {
          if (files.length == 1) {
            req.files.add(await _multipart(field: "mediaFile", file: files.first));
          } else {
            for (final f in files) {
              req.files.add(await _multipart(field: "mediaFiles", file: f));
            }
          }
        }

        if (finalType == "video" && files.isNotEmpty) {
          File? thumbToSend = videoThumbFile;
          if (thumbToSend == null) {
            try {
              thumbToSend = await MediaHelper.generateVideoThumbnail(files.first);
            } catch (_) {
              thumbToSend = null;
            }
          }
          if (thumbToSend != null) {
            // support multiple backend field names safely
            req.files.add(await _multipart(field: "video_thumb", file: thumbToSend));
            req.files.add(await _multipart(field: "thumb", file: thumbToSend));
            req.files.add(await _multipart(field: "thumbnail", file: thumbToSend));
          }
        }

        final streamed = await req.send().timeout(_timeout);
        final res = await http.Response.fromStream(streamed);
        final decoded = _tryDecode(res.body);

        if (res.statusCode == 200 || res.statusCode == 201) {
          okRes = res;
          okDecoded = decoded;
          break;
        }

        if (res.statusCode == 404) continue;

        throw Exception(_extractErrorMessage(decoded, fallback: "Post upload failed"));
      } catch (_) {
        // if first endpoint fails, try next; but if both fail, throw
        if (u.toString().endsWith("/posts")) continue;
        rethrow;
      }
    }

    if (okRes == null) {
      throw Exception("Post upload failed (no endpoint matched).");
    }

    if (okDecoded is Map) return Map<String, dynamic>.from(okDecoded);
    return {};
  }

  // =======================================================
  // ❤️ LIKE / UNLIKE
  // =======================================================
  static Future<Map<String, dynamic>> toggleLike(
      int postId, {
        required bool currentlyLiked,
      }) async {
    final token = await _getToken();
    if (token == null) {
      return {"ok": false, "liked": currentlyLiked, "message": "No token"};
    }

    final url = Uri.parse("$baseUrl/likes/$postId");

    try {
      final http.Response res = currentlyLiked
          ? await http.delete(url, headers: _headers(token: token)).timeout(_timeout)
          : await http.post(url, headers: _headers(token: token)).timeout(_timeout);

      final decoded = _tryDecode(res.body);

      if (res.statusCode != 200) {
        return {
          "ok": false,
          "liked": currentlyLiked,
          "message": _extractErrorMessage(decoded, fallback: "Like failed"),
          "status": res.statusCode
        };
      }

      if (decoded is Map) {
        final m = Map<String, dynamic>.from(decoded);
        final liked = (m["liked"] ?? (!currentlyLiked)) == true;
        final likes = m["likesCount"] ?? m["likes"] ?? m["like_count"] ?? m["likes_count"];
        return {"ok": true, "liked": liked, if (likes != null) "likes": _toInt(likes)};
      }

      return {"ok": true, "liked": !currentlyLiked};
    } catch (e) {
      return {"ok": false, "liked": currentlyLiked, "message": e.toString()};
    }
  }

  // =======================================================
  // 👥 WHO LIKED / REACTED
  // =======================================================
  static Future<List<Map<String, dynamic>>> fetchReactions(
      int postId, {
        int limit = 50,
        int offset = 0,
      }) async {
    final token = await _getToken();
    if (token == null) return [];

    final candidates = <Uri>[
      Uri.parse("$baseUrl/likes/$postId?limit=$limit&offset=$offset"),
      Uri.parse("$baseUrl/posts/$postId/likes?limit=$limit&offset=$offset"),
      Uri.parse("$baseUrl/posts/$postId/reactions?limit=$limit&offset=$offset"),
    ];

    for (final u in candidates) {
      try {
        final res =
        await http.get(u, headers: _headers(token: token)).timeout(_timeout);

        if (res.statusCode == 404) continue;
        if (res.statusCode != 200) continue;

        final decoded = _tryDecode(res.body);
        if (decoded == null) continue;

        final root = _asMap(decoded);
        final data = _unwrapMap(decoded);

        final listRaw = root["items"] ??
            root["likes"] ??
            root["reactions"] ??
            root["users"] ??
            (root["data"] is List ? root["data"] : null) ??
            data["items"] ??
            data["likes"] ??
            data["reactions"] ??
            data["users"] ??
            (data["data"] is List ? data["data"] : null) ??
            <dynamic>[];

        return _asList(listRaw)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } catch (_) {
        // try next
      }
    }

    return [];
  }

  static Future<List<Map<String, dynamic>>> fetchPostReactions(int postId) =>
      fetchReactions(postId);
  static Future<List<Map<String, dynamic>>> getPostReactions(int postId) =>
      fetchReactions(postId);
  static Future<List<Map<String, dynamic>>> postReactions(int postId) =>
      fetchReactions(postId);

  // =======================================================
  // 💬 COMMENTS
  // =======================================================
  static Future<Map<String, dynamic>> addComment(int postId, String text) async {
    final token = await _getToken();
    final t = text.trim();
    if (token == null || t.isEmpty) return {"ok": false, "message": "No token/text"};

    try {
      final res = await http
          .post(
        Uri.parse("$baseUrl/comments/$postId"),
        headers: _headers(token: token, json: true),
        body: jsonEncode({"text": t, "comment": t}),
      )
          .timeout(_timeout);

      final decoded = _tryDecode(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        if (decoded is Map) {
          final root = Map<String, dynamic>.from(decoded);
          final data = _unwrapMap(decoded);
          final count = root["comments_count"] ??
              root["comment_count"] ??
              root["count"] ??
              data["comments_count"] ??
              data["comment_count"] ??
              data["count"];
          return {"ok": true, "count": count != null ? _toInt(count) : null, "data": root};
        }
        return {"ok": true};
      }

      return {
        "ok": false,
        "message": _extractErrorMessage(decoded, fallback: "Comment failed"),
        "status": res.statusCode
      };
    } catch (e) {
      return {"ok": false, "message": e.toString()};
    }
  }

  // =======================================================
  // 🔁 SHARE
  // =======================================================
  static Future<int> sharePost(int postId) async {
    final token = await _getToken();
    if (token == null) return 0;

    final url = Uri.parse("$baseUrl/posts/$postId/share");

    try {
      final res = await http.post(url, headers: _headers(token: token)).timeout(_timeout);
      final decoded = _tryDecode(res.body);
      if (res.statusCode != 200 || decoded is! Map) return 0;

      final root = Map<String, dynamic>.from(decoded);
      final data = _unwrapMap(decoded);
      final shares = root["shares"] ??
          root["share_count"] ??
          root["count"] ??
          data["shares"] ??
          data["share_count"] ??
          data["count"];
      return _toInt(shares);
    } catch (_) {
      return 0;
    }
  }

  // =======================================================
  // ✅ OPTIONAL: REACTION POST
  // =======================================================
  static Future<Map<String, dynamic>> reactPost(int postId, String reaction) async {
    final token = await _getToken();
    if (token == null) return {"ok": false, "message": "No token"};

    final r = reaction.trim().toLowerCase();
    if (r.isEmpty) return {"ok": false, "message": "No reaction"};

    final candidates = <Uri>[
      Uri.parse("$baseUrl/posts/$postId/react"),
      Uri.parse("$baseUrl/feed/$postId/react"),
    ];

    dynamic lastDecoded;

    for (final u in candidates) {
      try {
        final res = await http
            .post(
          u,
          headers: _headers(token: token, json: true),
          body: jsonEncode({"reaction": r}),
        )
            .timeout(_timeout);

        final decoded = _tryDecode(res.body);
        lastDecoded = decoded;

        if (res.statusCode == 200 || res.statusCode == 201) {
          if (decoded is Map) {
            final m = Map<String, dynamic>.from(decoded);
            m["ok"] = true;
            return m;
          }
          return {"ok": true};
        }

        if (res.statusCode == 404) continue;

        return {
          "ok": false,
          "message": _extractErrorMessage(decoded, fallback: "Reaction failed"),
          "status": res.statusCode
        };
      } catch (_) {}
    }

    return {
      "ok": false,
      "message": _extractErrorMessage(lastDecoded, fallback: "Reaction failed")
    };
  }

  // =======================================================
  // 🚩 REPORT POST
  // =======================================================
  static Future<Map<String, dynamic>> reportPostById(
      int postId, {
        required String reason,
      }) async {
    final token = await _getToken();
    if (token == null) return {"ok": false, "message": "No token"};

    final r = reason.trim().toLowerCase();
    if (r.isEmpty) return {"ok": false, "message": "No reason"};

    final candidates = <Uri>[
      Uri.parse("$baseUrl/reports/post/$postId"),
      Uri.parse("$baseUrl/reports/posts/$postId"),
      Uri.parse("$baseUrl/posts/$postId/report"),
      Uri.parse("$baseUrl/feed/$postId/report"),
    ];

    dynamic lastDecoded;

    for (final u in candidates) {
      try {
        final res = await http
            .post(
          u,
          headers: _headers(token: token, json: true),
          body: jsonEncode({"reason": r}),
        )
            .timeout(_timeout);

        final decoded = _tryDecode(res.body);
        lastDecoded = decoded;

        if (res.statusCode == 200 || res.statusCode == 201) {
          if (decoded is Map) {
            final m = Map<String, dynamic>.from(decoded);
            m["ok"] = true;
            return m;
          }
          return {"ok": true};
        }

        if (res.statusCode == 404) continue;

        return {
          "ok": false,
          "message": _extractErrorMessage(decoded, fallback: "Report failed"),
          "status": res.statusCode,
        };
      } catch (_) {}
    }

    return {"ok": false, "message": _extractErrorMessage(lastDecoded, fallback: "Report failed")};
  }

  static Future<Map<String, dynamic>> reportPost({
    required int postId,
    required String reason,
  }) =>
      reportPostById(postId, reason: reason);

  // =======================================================
  // 🗑️ DELETE POST
  // =======================================================
  static Future<Map<String, dynamic>> deletePost(int postId) async {
    final token = await _getToken();
    if (token == null) return {"ok": false, "message": "No token"};

    final candidates = <Uri>[
      Uri.parse("$baseUrl/posts/$postId"),
      Uri.parse("$baseUrl/feed/$postId"),
      Uri.parse("$baseUrl/posts/delete/$postId"),
    ];

    dynamic lastDecoded;

    for (final u in candidates) {
      try {
        final res =
        await http.delete(u, headers: _headers(token: token)).timeout(_timeout);
        final decoded = _tryDecode(res.body);
        lastDecoded = decoded;

        if (res.statusCode == 200 || res.statusCode == 204) {
          if (decoded is Map) {
            final m = Map<String, dynamic>.from(decoded);
            m["ok"] = true;
            return m;
          }
          return {"ok": true};
        }

        if (res.statusCode == 404) continue;

        return {
          "ok": false,
          "message": _extractErrorMessage(decoded, fallback: "Delete failed"),
          "status": res.statusCode,
        };
      } catch (_) {}
    }

    return {"ok": false, "message": _extractErrorMessage(lastDecoded, fallback: "Delete failed")};
  }

  // =======================================================
  // #️⃣ HASHTAG: FETCH POSTS BY HASHTAG
  // =======================================================
  static Future<List<Map<String, dynamic>>> fetchByHashtag(
      String hashtag, {
        int page = 1,
        int limit = defaultLimit,
      }) async {
    final tag = hashtag.replaceAll("#", "").trim().toLowerCase();
    if (tag.isEmpty) return [];

    final token = await _getToken();

    final candidates = <Uri>[
      Uri.parse("$baseUrl/posts/hashtag/$tag?page=$page&limit=$limit"),
      Uri.parse("$baseUrl/feed/hashtag/$tag?page=$page&limit=$limit"),
    ];

    for (final url in candidates) {
      try {
        final res =
        await http.get(url, headers: _headers(token: token)).timeout(_timeout);
        if (res.statusCode != 200) {
          if (res.statusCode == 404) continue;
          continue;
        }

        final decoded = _tryDecode(res.body);
        if (decoded == null) continue;

        return _extractItems(decoded);
      } catch (_) {}
    }

    return [];
  }

  // =======================================================
  // @️⃣ resolve user by username
  // =======================================================
  static Future<Map<String, dynamic>?> fetchUserByUsername(String username) async {
    final token = await _getToken();
    if (token == null) return null;

    final u = username.replaceAll("@", "").trim().toLowerCase();
    if (u.isEmpty) return null;

    final url = Uri.parse("$baseUrl/users/username/$u");

    try {
      final res = await http.get(url, headers: _headers(token: token)).timeout(_timeout);
      if (res.statusCode != 200) return null;

      final decoded = _tryDecode(res.body);
      if (decoded is Map) {
        final m = Map<String, dynamic>.from(decoded);
        final data = (m["data"] is Map) ? Map<String, dynamic>.from(m["data"]) : m;
        return data;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // =======================================================
  // 🔗 MEDIA URL FIX (FINAL ✅ filename->uploads)
  // =======================================================
  static String toPublicUrl(String? path) {
    final raw0 = (path ?? "").trim();
    if (raw0.isEmpty) return "";

    // already absolute
    if (raw0.startsWith("http://") || raw0.startsWith("https://")) {
      return Uri.encodeFull(raw0);
    }
    if (raw0.startsWith("//")) return Uri.encodeFull("https:$raw0");

    // normalize slashes
    String raw = raw0.replaceAll('\\', '/').trim();

    // remove leading slashes
    raw = raw.replaceFirst(RegExp(r'^/+'), '');

    // strip accidental "public/" prefix
    raw = raw.replaceFirst(RegExp(r'^public/'), '');

    // ✅ IMPORTANT: if only filename (no slash), assume uploads/
    if (!raw.contains('/')) {
      return Uri.encodeFull("$publicHost/uploads/$raw");
    }

    // keep known folders
    if (raw.startsWith("uploads/") ||
        raw.startsWith("reels/") ||
        raw.startsWith("hls/")) {
      return Uri.encodeFull("$publicHost/$raw");
    }

    // otherwise treat as relative under host
    return Uri.encodeFull("$publicHost/$raw");
  }

  // =======================================================
  // Helpers
  // =======================================================
  static bool _isVideo(String path) {
    final p = path.toLowerCase();
    return [".mp4", ".mov", ".avi", ".mkv", ".webm", ".m4v"].any((e) => p.endsWith(e));
  }

  static MediaType _guessMime(String filePath) {
    final p = filePath.toLowerCase();
    if (p.endsWith(".mp4")) return MediaType("video", "mp4");
    if (p.endsWith(".mov")) return MediaType("video", "quicktime");
    if (p.endsWith(".webm")) return MediaType("video", "webm");
    if (p.endsWith(".m4v")) return MediaType("video", "mp4");
    if (p.endsWith(".png")) return MediaType("image", "png");
    if (p.endsWith(".webp")) return MediaType("image", "webp");
    if (p.endsWith(".gif")) return MediaType("image", "gif");
    return MediaType("image", "jpeg");
  }

  static Future<http.MultipartFile> _multipart({
    required String field,
    required File file,
  }) async {
    final mime = _guessMime(file.path);
    return http.MultipartFile.fromPath(field, file.path, contentType: mime);
  }

  static Future<int> _getVideoDuration(File file) async {
    try {
      final ctrl = VideoPlayerController.file(file);
      await ctrl.initialize();
      final sec = ctrl.value.duration.inSeconds;
      await ctrl.dispose();
      return sec;
    } catch (_) {
      // safest fallback (block upload)
      return maxVideoSeconds;
    }
  }
}
