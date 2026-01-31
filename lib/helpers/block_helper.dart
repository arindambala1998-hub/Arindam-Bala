import 'package:shared_preferences/shared_preferences.dart';

class BlockHelper {
  static const String _key = "blocked_users";

  // In-memory cache for performance
  static final Set<int> _cache = <int>{};

  static bool _inited = false;

  // ====================================================
  // INIT (call once at app start if possible)
  // ====================================================
  static Future<void> init() async {
    if (_inited) return;
    _inited = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_key) ?? const <String>[];
      _cache
        ..clear()
        ..addAll(
          list
              .map((e) => int.tryParse(e.trim()) ?? -1)
              .where((e) => e > 0),
        );
    } catch (_) {
      // ignore
    }
  }

  /// ✅ If you forgot to call init() somewhere, this keeps it safe
  static Future<void> ensureInit() async {
    if (_inited) return;
    await init();
  }

  // ====================================================
  // BLOCK USER
  // ====================================================
  static Future<void> blockUser(int userId) async {
    if (userId <= 0) return;
    await ensureInit();

    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_key) ?? <String>[];

      final s = userId.toString();
      if (!list.contains(s)) {
        list.add(s);
        await prefs.setStringList(_key, list);
      }
      _cache.add(userId);
    } catch (_) {
      // still keep cache updated even if prefs write fails
      _cache.add(userId);
    }
  }

  // ====================================================
  // UNBLOCK USER
  // ====================================================
  static Future<void> unblockUser(int userId) async {
    if (userId <= 0) return;
    await ensureInit();

    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_key) ?? <String>[];
      list.remove(userId.toString());
      await prefs.setStringList(_key, list);
    } catch (_) {
      // ignore
    }
    _cache.remove(userId);
  }

  // ====================================================
  // CHECK BLOCK
  // ====================================================
  static bool isBlockedSync(int userId) {
    if (userId <= 0) return false;
    return _cache.contains(userId);
  }

  static Future<bool> isBlocked(int userId) async {
    if (userId <= 0) return false;
    await ensureInit();
    return _cache.contains(userId);
  }

  // ====================================================
  // PARSE HELPERS (✅ handles int/string/null)
  // ====================================================
  static int _parseUserId(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString().trim()) ?? 0;
  }

  static int userIdFromPost(
      Map<String, dynamic> item, {
        String? userIdKey,
      }) {
    // priority: given key
    if (userIdKey != null && userIdKey.isNotEmpty) {
      final id = _parseUserId(item[userIdKey]);
      if (id > 0) return id;
    }

    // fallback keys (your backend can vary)
    final id1 = _parseUserId(item["user_id"]);
    if (id1 > 0) return id1;

    final id2 = _parseUserId(item["userId"]);
    if (id2 > 0) return id2;

    final id3 = _parseUserId(item["uid"]);
    if (id3 > 0) return id3;

    return 0;
  }

  // ====================================================
  // FILTER HELPERS (FEED / REELS / POSTS)
  // ====================================================
  static List<Map<String, dynamic>> filterBlockedUsers(
      List<Map<String, dynamic>> items, {
        String userIdKey = "user_id",
      }) {
    if (_cache.isEmpty) return items;

    return items.where((item) {
      final uid = userIdFromPost(item, userIdKey: userIdKey);
      return uid <= 0 || !_cache.contains(uid);
    }).toList();
  }

  /// ✅ Shortcut: block user by post map
  static Future<void> blockUserFromPost(
      Map<String, dynamic> post, {
        String userIdKey = "user_id",
      }) async {
    final uid = userIdFromPost(post, userIdKey: userIdKey);
    if (uid > 0) {
      await blockUser(uid);
    }
  }

  /// ✅ Shortcut: check blocked by post map
  static bool isBlockedPostSync(
      Map<String, dynamic> post, {
        String userIdKey = "user_id",
      }) {
    final uid = userIdFromPost(post, userIdKey: userIdKey);
    if (uid <= 0) return false;
    return _cache.contains(uid);
  }

  // ====================================================
  // DEBUG / CLEAR (optional)
  // ====================================================
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // ignore
    }
    _cache.clear();
    _inited = true; // still treated as inited
  }

  static List<int> blockedIdsSnapshot() => _cache.toList();
}
