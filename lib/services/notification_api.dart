import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// ✅ NotificationAPI (FULL + FINAL)
/// Backend compatible (flexible response):
/// - List: [ ... ]
/// - Map: { success, notifications|data|items: [...], nextCursor|next_cursor, hasMore|has_more, count }
///
/// Endpoints expected:
/// GET    /api/notifications?limit=&cursor=
/// POST   /api/notifications/:id/read
/// POST   /api/notifications/read-all
/// GET    /api/notifications/unread-count
class NotificationAPI {
  static const String _baseUrl = "https://adminapi.troonky.in/api/notifications";

  // timeouts (avoid hanging UI)
  static const Duration _timeout = Duration(seconds: 15);

  // ---------- Token ----------
  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    // support multiple common keys (just in case)
    return prefs.getString('token') ??
        prefs.getString('access_token') ??
        prefs.getString('jwt') ??
        prefs.getString('authToken');
  }

  // GET -> no need content-type
  static Map<String, String> _authHeaders(String token) => {
    "Authorization": "Bearer $token",
    "Accept": "application/json",
  };

  // POST/PUT with json body (we mostly don’t send body here, but safe)
  static Map<String, String> _authJsonHeaders(String token) => {
    "Authorization": "Bearer $token",
    "Accept": "application/json",
    "Content-Type": "application/json",
  };

  // ---------- JSON helpers ----------
  static dynamic _safeJsonDecode(String s) {
    try {
      if (s.trim().isEmpty) return null;
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  static List<Map<String, dynamic>> _normalizeList(dynamic decoded) {
    if (decoded is List) {
      return decoded
          .where((e) => e is Map)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }

    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);

      final raw = map["notifications"] ?? map["data"] ?? map["items"] ?? map["rows"] ?? [];
      if (raw is List) {
        return raw
            .where((e) => e is Map)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    }

    return <Map<String, dynamic>>[];
  }

  static String? _readNextCursor(dynamic decoded) {
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    final v = map["nextCursor"] ?? map["next_cursor"] ?? map["cursor_next"] ?? map["next"];
    final s = (v ?? "").toString().trim();
    return s.isEmpty ? null : s;
  }

  static bool _readHasMore(dynamic decoded, {String? nextCursor}) {
    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      final raw = map["hasMore"] ?? map["has_more"] ?? map["more"];
      if (raw is bool) return raw;
      final txt = (raw ?? "").toString().toLowerCase().trim();
      if (txt == "true" || txt == "1" || txt == "yes") return true;
    }
    // fallback: if cursor exists, assume more possible
    return nextCursor != null && nextCursor.trim().isNotEmpty;
  }

  static bool _isSuccess(dynamic decoded) {
    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      final s = map["success"];
      if (s is bool) return s;
      final txt = (s ?? "").toString().toLowerCase().trim();
      if (txt == "true" || txt == "1" || txt == "yes") return true;
    }
    // if it returned a list, treat as success
    if (decoded is List) return true;
    return false;
  }

  // ==============================
  // ✅ GET notifications (pagination)
  // ==============================
  static Future<NotificationsPageResult> fetchNotifications({
    String? cursor,
    int limit = 20,
  }) async {
    final token = await _getToken();
    if (token == null || token.trim().isEmpty) {
      return const NotificationsPageResult(items: [], nextCursor: null, hasMore: false);
    }

    final qp = <String, String>{
      "limit": "${limit.clamp(1, 200)}",
      if (cursor != null && cursor.trim().isNotEmpty) "cursor": cursor.trim(),
    };

    final uri = Uri.parse(_baseUrl).replace(queryParameters: qp);

    try {
      final res = await http.get(uri, headers: _authHeaders(token)).timeout(_timeout);

      if (res.statusCode == 401 || res.statusCode == 403) {
        // token invalid/expired -> return empty
        return const NotificationsPageResult(items: [], nextCursor: null, hasMore: false);
      }

      final decoded = _safeJsonDecode(res.body);

      // if backend sends {success:false,...}
      if (res.statusCode != 200 && !_isSuccess(decoded)) {
        // ignore: avoid_print
        print("❌ fetchNotifications failed: ${res.statusCode} ${res.body}");
        return const NotificationsPageResult(items: [], nextCursor: null, hasMore: false);
      }

      final list = _normalizeList(decoded);
      final next = _readNextCursor(decoded);
      final hasMore = _readHasMore(decoded, nextCursor: next);

      return NotificationsPageResult(items: list, nextCursor: next, hasMore: hasMore);
    } on SocketException catch (e) {
      // ignore: avoid_print
      print("❌ NotificationAPI network error: $e");
      return const NotificationsPageResult(items: [], nextCursor: null, hasMore: false);
    } on HttpException catch (e) {
      // ignore: avoid_print
      print("❌ NotificationAPI http error: $e");
      return const NotificationsPageResult(items: [], nextCursor: null, hasMore: false);
    } on FormatException catch (e) {
      // ignore: avoid_print
      print("❌ NotificationAPI json parse error: $e");
      return const NotificationsPageResult(items: [], nextCursor: null, hasMore: false);
    } catch (e) {
      // ignore: avoid_print
      print("❌ NotificationAPI error: $e");
      return const NotificationsPageResult(items: [], nextCursor: null, hasMore: false);
    }
  }

  // ==============================
  // ✅ POST /:id/read
  // ==============================
  static Future<bool> markAsRead(dynamic notificationId) async {
    final token = await _getToken();
    if (token == null || token.trim().isEmpty) return false;

    final id = (notificationId ?? "").toString().trim();
    if (id.isEmpty) return false;

    final uri = Uri.parse("$_baseUrl/$id/read");

    try {
      final res = await http.post(uri, headers: _authJsonHeaders(token)).timeout(_timeout);

      if (res.statusCode == 401 || res.statusCode == 403) return false;
      if (res.statusCode >= 200 && res.statusCode < 300) return true;

      // fallback: some backends return 200 with success:false
      final decoded = _safeJsonDecode(res.body);
      return _isSuccess(decoded);
    } catch (_) {
      return false;
    }
  }

  // ==============================
  // ✅ POST /read-all
  // ==============================
  static Future<bool> markAllRead() async {
    final token = await _getToken();
    if (token == null || token.trim().isEmpty) return false;

    final uri = Uri.parse("$_baseUrl/read-all");

    try {
      final res = await http.post(uri, headers: _authJsonHeaders(token)).timeout(_timeout);

      if (res.statusCode == 401 || res.statusCode == 403) return false;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = _safeJsonDecode(res.body);
        // if server returns nothing or non-json -> still ok
        return decoded == null ? true : _isSuccess(decoded);
      }

      final decoded = _safeJsonDecode(res.body);
      return _isSuccess(decoded);
    } catch (_) {
      return false;
    }
  }

  // ==============================
  // ✅ GET /unread-count
  // ==============================
  static Future<int> fetchUnreadCount() async {
    final token = await _getToken();
    if (token == null || token.trim().isEmpty) return 0;

    final uri = Uri.parse("$_baseUrl/unread-count");

    try {
      final res = await http.get(uri, headers: _authHeaders(token)).timeout(_timeout);

      if (res.statusCode == 401 || res.statusCode == 403) return 0;
      if (res.statusCode != 200) return 0;

      final decoded = _safeJsonDecode(res.body);

      // number-only response
      if (decoded is int) return decoded;
      if (decoded is String) return int.tryParse(decoded.trim()) ?? 0;

      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        final raw = map["count"] ?? map["unread"] ?? map["unreadCount"] ?? map["unread_count"] ?? 0;
        if (raw is int) return raw;
        return int.tryParse(raw.toString()) ?? 0;
      }

      return 0;
    } catch (_) {
      return 0;
    }
  }
}

class NotificationsPageResult {
  final List<Map<String, dynamic>> items;
  final String? nextCursor;
  final bool hasMore;

  const NotificationsPageResult({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });
}
