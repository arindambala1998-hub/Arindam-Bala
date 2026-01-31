import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'package:troonky_link/services/feed_api.dart';
import 'package:troonky_link/pages/new_post_page.dart';
import 'package:troonky_link/pages/profile/profile_page.dart';
import 'package:troonky_link/helpers/block_helper.dart';
import 'package:troonky_link/pages/post_comments_sheet.dart';
import 'package:troonky_link/pages/video_fullscreen_page.dart';
import 'package:troonky_link/pages/business_profile/business_profile_page.dart';

import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// =========================
/// ✅ Troonky Official Theme
/// =========================
const Color troonkyColor = Color(0xFF333399);
const Color troonkyGradA = Color(0xFF7C2AE8);
const Color troonkyGradB = Color(0xFFFF2DAA);

LinearGradient troonkyGradient([
  Alignment a = Alignment.centerLeft,
  Alignment b = Alignment.centerRight,
]) {
  return const LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [troonkyGradA, troonkyGradB],
  );
}

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> with WidgetsBindingObserver {
  // ✅ final rendered list (NO MIXING)
  final List<Map<String, dynamic>> _posts = [];
  final ScrollController _scroll = ScrollController();

  bool loading = true;
  bool loadingMore = false;
  String? _error;

  // ✅ paging (cursor preferred)
  String? _nextCursor;
  int _nextPage = 1; // fallback only
  bool _rawHasMore = true;
  bool _fetching = false;

  // ✅ avoid duplicates
  final LinkedHashSet<String> _seenIds = LinkedHashSet(); // keeps insertion order
  final Set<String> _queuedIds = <String>{}; // O(1) checks

  // local cached liked states (UI only)
  final Set<String> _liked = <String>{};

  // ✅ PERFORMANCE TUNING
  static const int _initialTarget = 10;
  static const int _appendTarget = 5;
  static const int _scrollTriggerPx = 200;
  static const int _maxSessionPosts = 30;

  // seen cache
  static const String _prefsSeenKey = "feed_seen_ids_v1";
  static const int _persistSeenMax = 2000;

  bool _usedSeenFallbackOnce = false;

  // auth token cache
  String? _authToken;
  bool _tokenLoaded = false;

  // my identity (for owner delete)
  int? _myUserId;
  bool _meLoaded = false;

  // prefetch tuning
  static const int _prefetchCapPerPost = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    BlockHelper.init();
    _scroll.addListener(_onScroll);

    _hydrateIdentityOnce();
    _loadAuthTokenOnce();
    _loadPosts();
  }

  Future<void> _hydrateIdentityOnce() async {
    if (_meLoaded) return;
    _meLoaded = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final idStr = prefs.getString("userId") ??
          prefs.getString("user_id") ??
          prefs.getString("id") ??
          prefs.getInt("userId")?.toString() ??
          prefs.getInt("user_id")?.toString();

      _myUserId = int.tryParse((idStr ?? "").toString());
    } catch (_) {
      _myUserId = null;
    }
  }

  Future<void> _loadAuthTokenOnce() async {
    if (_tokenLoaded) return;
    _tokenLoaded = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final t = prefs.getString("token")?.trim();
      _authToken = (t == null || t.isEmpty) ? null : t;
    } catch (_) {
      _authToken = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _scroll.removeListener(_onScroll);
    _scroll.dispose();

    _FeedVideoHub.pauseAny();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _FeedVideoHub.pauseAny();
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >
        _scroll.position.maxScrollExtent - _scrollTriggerPx) {
      if (!loadingMore && !_fetching && _rawHasMore) {
        _loadMore();
      }
    }
  }

  // ---------- helpers ----------
  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? "") ?? 0;
  }

  static List<dynamic> _mediaList(Map<String, dynamic> post) {
    final m = post["media_urls"];
    if (m is List) return m;
    final single = post["media_url"] ?? post["mediaFile"];
    if (single != null && single.toString().trim().isNotEmpty) return [single];
    return [];
  }

  static bool _isVideoUrl(String s) {
    final u = s.toLowerCase();
    return u.contains(".mp4") ||
        u.contains(".m3u8") ||
        u.contains(".mov") ||
        u.contains(".m4v") ||
        u.contains(".webm");
  }

  static bool _isVideoPost(Map<String, dynamic> post) {
    final dynIsVideo = post["is_video"];
    if (dynIsVideo == true) return true;

    final media = _mediaList(post);
    if (media.isEmpty) return false;
    if (media.length != 1) return false;
    return _isVideoUrl(media.first.toString().trim());
  }

  bool _isMine(Map<String, dynamic> post) {
    final uid = _toInt(post["user_id"] ?? post["userId"] ?? post["uid"] ?? 0);
    if (_myUserId == null || _myUserId! <= 0) return false;
    if (uid <= 0) return false;
    return uid == _myUserId;
  }

  // =========================
  // ✅ PERSIST SEEN (no repeat like Facebook)
  // =========================
  Future<void> _loadSeenCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefsSeenKey) ?? const <String>[];
      _seenIds.addAll(list);
    } catch (_) {}
  }

  Future<void> _saveSeenCache() async {
    try {
      final ids = _seenIds.toList(); // insertion order
      if (ids.length > _persistSeenMax) {
        ids.removeRange(0, ids.length - _persistSeenMax);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsSeenKey, ids);
    } catch (_) {}
  }

  // =========================
  // ✅ FEED LOADING (NO MIXING)
  // =========================
  Future<void> _loadPosts() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      _error = null;
    });

    _FeedVideoHub.pauseAny();

    // reset state
    _posts.clear();
    _liked.clear();
    _seenIds.clear();
    _queuedIds.clear();

    _nextCursor = null;
    _nextPage = 1;
    _rawHasMore = true;

    _usedSeenFallbackOnce = false;

    await _loadSeenCache();

    try {
      await _fetchNextAndAppend(targetAdd: _initialTarget);

      // liked cache only for rendered posts
      for (final p in _posts) {
        final id = (p["id"] ?? "").toString();
        final serverLiked = (p["is_liked"] == true) || (p["liked"] == true);
        if (id.isNotEmpty && serverLiked) _liked.add(id);
      }

      if (mounted) {
        await _prefetchForPosts(_posts.take(4).toList());
      }

      unawaited(_saveSeenCache());
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Could not load feed. Check internet & try again.");
    } finally {
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (loadingMore || !_rawHasMore || _fetching) return;
    if (!mounted) return;

    setState(() => loadingMore = true);

    final beforeLen = _posts.length;

    try {
      await _fetchNextAndAppend(targetAdd: _appendTarget);

      // update liked cache for newly added only
      for (int i = beforeLen; i < _posts.length; i++) {
        final p = _posts[i];
        final id = (p["id"] ?? "").toString();
        final serverLiked = (p["is_liked"] == true) || (p["liked"] == true);
        if (id.isNotEmpty && serverLiked) _liked.add(id);
      }

      if (mounted && _posts.length > beforeLen) {
        await _prefetchForPosts(_posts.sublist(beforeLen));
      }

      unawaited(_saveSeenCache());
    } catch (_) {
      // keep UI stable
    } finally {
      if (!mounted) return;
      setState(() => loadingMore = false);
    }
  }

  // =========================
  // ✅ FETCH (cursor-first, page fallback) + EXACT ORDER
  // =========================
  Future<void> _fetchNextAndAppend({required int targetAdd}) async {
    if (_fetching || !_rawHasMore) return;
    if (_posts.length >= _maxSessionPosts) {
      _rawHasMore = false;
      return;
    }

    _fetching = true;

    try {
      final added = <Map<String, dynamic>>[];
      int emptyFetchCount = 0;
      const maxEmptyFetches = 3;

      while (added.length < targetAdd &&
          _rawHasMore &&
          emptyFetchCount < maxEmptyFetches) {
        List<Map<String, dynamic>> data = [];

        // cursor-first, fallback page
        bool usedCursor = false;
        try {
          final dynamic resp = await (FeedAPI as dynamic).fetchFeedCursor(
            cursor: _nextCursor,
            limit: FeedAPI.defaultLimit,
          );

          if (resp is Map && resp["ok"] == false) {
            throw Exception(resp["message"]?.toString() ?? "cursor feed failed");
          }

          final rawItems = (resp is Map && resp["items"] is List)
              ? (resp["items"] as List)
              : const <dynamic>[];
          data = rawItems
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();

          final nextCursor =
          (resp is Map ? (resp["nextCursor"] ?? resp["next_cursor"]) : null)
              ?.toString()
              .trim();
          _nextCursor = (nextCursor == null || nextCursor.isEmpty) ? null : nextCursor;

          final hasMoreFlag = (resp is Map) &&
              (resp["hasMore"] == true || resp["has_more"] == true);
          _rawHasMore = hasMoreFlag || (_nextCursor != null && data.isNotEmpty);

          usedCursor = true;
        } catch (_) {
          usedCursor = false;
        }

        if (!usedCursor) {
          data = await FeedAPI.fetchFeed(
            page: _nextPage,
            limit: FeedAPI.defaultLimit,
          );
          _rawHasMore = data.length >= FeedAPI.defaultLimit;
          _nextPage++;
        }

        final filtered = BlockHelper.filterBlockedUsers(data);

        if (filtered.isEmpty) {
          emptyFetchCount++;
          continue;
        }

        int addedThisBatch = 0;
        final remaining = _maxSessionPosts - _posts.length - added.length;

        for (final raw in filtered) {
          if (added.length >= targetAdd) break;
          if (added.length >= remaining) break;

          final p = Map<String, dynamic>.from(raw);
          final id = (p["id"] ?? "").toString();
          if (id.isEmpty) continue;

          if (_queuedIds.contains(id)) continue;
          _queuedIds.add(id);

          if (_seenIds.contains(id)) continue;

          _seenIds.add(id);
          added.add(p);
          addedThisBatch++;
        }

        if (addedThisBatch == 0) {
          emptyFetchCount++;
        } else {
          emptyFetchCount = 0;
        }
      }

      // If everything is seen, reset once and show fresh
      if (_posts.isEmpty && added.isEmpty && !_usedSeenFallbackOnce) {
        _usedSeenFallbackOnce = true;

        _seenIds.clear();
        _queuedIds.clear();
        _nextPage = 1;
        _nextCursor = null;
        _rawHasMore = true;

        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_prefsSeenKey);
        } catch (_) {}

        final freshData =
        await FeedAPI.fetchFeed(page: 1, limit: FeedAPI.defaultLimit);
        _rawHasMore = freshData.length >= FeedAPI.defaultLimit;
        _nextPage = 2;

        final freshFiltered = BlockHelper.filterBlockedUsers(freshData);

        for (final raw in freshFiltered) {
          if (added.length >= targetAdd) break;
          final p = Map<String, dynamic>.from(raw);
          final id = (p["id"] ?? "").toString();
          if (id.isEmpty) continue;

          _queuedIds.add(id);
          _seenIds.add(id);
          added.add(p);
        }
      }

      if (added.isNotEmpty && mounted) {
        setState(() => _posts.addAll(added));
        await _prefetchForPosts(added);
      }
    } finally {
      _fetching = false;
    }
  }

  Future<void> _prefetchForPosts(List<Map<String, dynamic>> posts) async {
    for (final p in posts) {
      try {
        final media = _mediaList(p);
        if (media.isEmpty) continue;

        if (_isVideoPost(p)) {
          final thumbRaw = (p["video_thumb"] ??
              p["thumb_url"] ??
              p["thumbnail_url"] ??
              p["thumbnail"] ??
              p["poster"] ??
              "")
              .toString()
              .trim();
          if (thumbRaw.isEmpty) continue;

          final thumbUrl = FeedAPI.toPublicUrl(thumbRaw);
          await precacheImage(NetworkImage(thumbUrl), context);
        } else {
          int c = 0;
          for (final m in media) {
            final url = FeedAPI.toPublicUrl(m.toString());
            await precacheImage(NetworkImage(url), context);
            c++;
            if (c >= _prefetchCapPerPost) break;
          }
        }
      } catch (_) {}
    }
  }

  // =========================
  // ✅ Reactions list (FB-like)
  // =========================
  Future<void> _openReactions(Map<String, dynamic> post) async {
    final postId = int.tryParse((post["id"] ?? "").toString()) ?? 0;
    if (postId <= 0) return;

    _FeedVideoHub.pauseAny();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.78,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: ReactionsSheet(
          postId: postId,
          postTitle: (post["description"] ?? "").toString(),
        ),
      ),
    );
  }

  // =========================
  // ✅ Comments Sheet
  // =========================
  Future<void> _openComments(Map<String, dynamic> post) async {
    final postId = int.tryParse((post["id"] ?? "").toString()) ?? 0;
    if (postId <= 0) return;

    _FeedVideoHub.pauseAny();

    final updated = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: PostCommentsSheet(
          postId: postId,
          initialCount: _toInt(
            post["comments_count"] ??
                post["comment_count"] ??
                post["comments"] ??
                0,
          ),
        ),
      ),
    );

    if (updated != null && mounted) {
      setState(() {
        post["comments_count"] = updated;
        post["comment_count"] = updated;
        post["comments"] = updated;
      });
    }
  }

  Future<void> _sharePost(Map<String, dynamic> post) async {
    final postId = int.tryParse((post["id"] ?? "").toString()) ?? 0;
    if (postId <= 0) return;

    _FeedVideoHub.pauseAny();

    final text = (post["description"] ?? "").toString();
    final media = _mediaList(post);
    final firstUrl =
    media.isNotEmpty ? FeedAPI.toPublicUrl(media.first.toString()) : "";

    await Share.share("🔥 Troonky Post\n\n$text\n\n$firstUrl");

    final int newShares = await FeedAPI.sharePost(postId);
    if (!mounted) return;

    setState(() {
      if (newShares > 0) {
        post["shares_count"] = newShares;
        post["share_count"] = newShares;
      } else {
        final cur = _toInt(post["shares_count"] ?? post["share_count"] ?? 0);
        post["shares_count"] = cur + 1;
        post["share_count"] = cur + 1;
      }
    });
  }

  Future<void> _toggleLike(Map<String, dynamic> post) async {
    final idStr = (post["id"] ?? "").toString();
    final postId = int.tryParse(idStr) ?? 0;
    if (postId <= 0) return;

    HapticFeedback.lightImpact();

    final wasLiked = _liked.contains(idStr);
    final curLikes =
    _toInt(post["likes_count"] ?? post["like_count"] ?? post["likes"] ?? 0);

    // optimistic
    if (mounted) {
      setState(() {
        if (wasLiked) {
          _liked.remove(idStr);
          final next = (curLikes - 1) < 0 ? 0 : (curLikes - 1);
          post["likes_count"] = next;
          post["like_count"] = next;
          post["likes"] = next;
        } else {
          _liked.add(idStr);
          post["likes_count"] = curLikes + 1;
          post["like_count"] = curLikes + 1;
          post["likes"] = curLikes + 1;
        }
        post["is_liked"] = _liked.contains(idStr);
        post["liked"] = _liked.contains(idStr);
      });
    }

    final res = await FeedAPI.toggleLike(postId, currentlyLiked: wasLiked);
    if (!mounted) return;

    final ok = res["ok"] == true;
    if (!ok) {
      // rollback
      setState(() {
        if (wasLiked) {
          _liked.add(idStr);
        } else {
          _liked.remove(idStr);
        }
        post["likes_count"] = curLikes;
        post["like_count"] = curLikes;
        post["likes"] = curLikes;
        post["is_liked"] = wasLiked;
        post["liked"] = wasLiked;
      });
      return;
    }

    final apiLiked = res["liked"] == true;
    final apiLikes = res["likes"];

    setState(() {
      if (apiLiked) {
        _liked.add(idStr);
      } else {
        _liked.remove(idStr);
      }
      post["is_liked"] = apiLiked;
      post["liked"] = apiLiked;

      int parsed = curLikes;
      if (apiLikes is int) parsed = apiLikes;
      if (apiLikes is String) parsed = int.tryParse(apiLikes) ?? parsed;

      post["likes_count"] = parsed;
      post["like_count"] = parsed;
      post["likes"] = parsed;
    });
  }

  // =========================
  // ✅ Delete Post (Owner only)
  // =========================
  Future<void> _deletePost(Map<String, dynamic> post) async {
    final idStr = (post["id"] ?? "").toString();
    final postId = int.tryParse(idStr) ?? 0;
    if (postId <= 0) return;

    _FeedVideoHub.pauseAny();

    final ok = await _confirmDialog(
      title: "Delete Post",
      message: "Are you sure? This can’t be undone.",
      okText: "Delete",
      cancelText: "Cancel",
      danger: true,
    );
    if (!ok) return;

    // optimistic remove
    final backup = Map<String, dynamic>.from(post);
    final idx = _posts.indexWhere((p) => (p["id"] ?? "").toString() == idStr);
    if (idx >= 0) {
      setState(() => _posts.removeAt(idx));
    }

    try {
      // ✅ preferred
      dynamic resp;
      try {
        resp = await (FeedAPI as dynamic).deletePost(postId);
      } catch (_) {
        // fallback name variants if your API uses different method
        try {
          resp = await (FeedAPI as dynamic).deletePostById(postId);
        } catch (_) {
          resp = await (FeedAPI as dynamic).removePost(postId);
        }
      }

      final success = (resp is Map) && (resp["ok"] == true || resp["success"] == true);
      if (!success) {
        // rollback
        if (idx >= 0 && mounted) {
          setState(() => _posts.insert(idx, backup));
        }
        final msg =
            (resp is Map ? (resp["message"] ?? resp["error"]) : null)?.toString() ??
                "Delete failed";
        _snack(msg, error: true);
        return;
      }

      _snack("Deleted ✅");
    } catch (e) {
      // rollback
      if (idx >= 0 && mounted) {
        setState(() => _posts.insert(idx, backup));
      }
      _snack("Delete failed: $e", error: true);
    }
  }

  // =========================
  // ✅ REPORT / BLOCK
  // =========================
  String _getUserId(Map<String, dynamic> post) {
    final v = post["user_id"] ?? post["userId"] ?? post["uid"] ?? "";
    return v.toString();
  }

  void _removePostById(String id) {
    if (id.isEmpty) return;

    _liked.remove(id);
    _posts.removeWhere((p) => (p["id"] ?? "").toString() == id);

    if (mounted) setState(() {});
  }

  void _removeAllPostsByUser(String userId) {
    if (userId.isEmpty) return;

    _posts.removeWhere((p) => _getUserId(p) == userId);

    if (mounted) setState(() {});
  }

  Future<bool> _confirmDialog({
    required String title,
    required String message,
    String okText = "Confirm",
    String cancelText = "Cancel",
    bool danger = false,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelText),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: danger ? Colors.red : troonkyColor,
            ),
            child: Text(okText),
          ),
        ],
      ),
    );
    return res == true;
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? Colors.red : Colors.green,
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<String?> _pickReportReason() async {
    const reasons = <String>[
      "spam",
      "harassment",
      "hate",
      "nudity",
      "violence",
      "other"
    ];

    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  gradient: troonkyGradient(),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  "Report Reason",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 12),
              ...reasons.map(
                    (r) => ListTile(
                  leading: const Icon(Icons.flag, color: troonkyColor),
                  title: Text(r),
                  onTap: () => Navigator.pop(context, r),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onReportPost(Map<String, dynamic> post) async {
    final postId = int.tryParse((post["id"] ?? "").toString()) ?? 0;
    if (postId <= 0) return;

    _FeedVideoHub.pauseAny();

    final reason = await _pickReportReason();
    if (reason == null) return;

    final ok = await _confirmDialog(
      title: "Report Post",
      message: "Are you sure you want to report this post?\nReason: $reason",
      okText: "Report",
    );
    if (!ok) return;

    final idStr = (post["id"] ?? "").toString();
    _removePostById(idStr);

    final res = await FeedAPI.reportPostById(postId, reason: reason);
    if (!mounted) return;

    if (res["ok"] == true || res["success"] == true) {
      _snack("Reported ✅ Hidden from feed.");
    } else {
      final msg =
      (res["message"] ?? res["error"] ?? "Report failed").toString();
      _snack(msg, error: true);
      _loadPosts();
    }
  }

  Future<void> _onBlockUser(Map<String, dynamic> post) async {
    final userId = _getUserId(post);
    if (userId.isEmpty) return;

    _FeedVideoHub.pauseAny();

    final ok = await _confirmDialog(
      title: "Block User",
      message: "Block this user? You will no longer see their posts.",
      okText: "Block",
    );
    if (!ok) return;

    bool saved = false;
    try {
      // ignore: avoid_dynamic_calls
      (BlockHelper as dynamic).blockUser(userId);
      saved = true;
    } catch (_) {
      saved = false;
    }

    if (!saved) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final list = prefs.getStringList("blocked_users") ?? <String>[];
        if (!list.contains(userId)) {
          list.add(userId);
          await prefs.setStringList("blocked_users", list);
        }
      } catch (_) {}
    }

    _removeAllPostsByUser(userId);
    _snack("User blocked ✅");
  }

  void _onHashtagTap(String tag) => _openTagSheet(title: "Hashtag", value: tag);
  void _onMentionTap(String username) =>
      _openTagSheet(title: "Mention", value: username);

  void _openTagSheet({required String title, required String value}) {
    _FeedVideoHub.pauseAny();

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: troonkyGradient(),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        title,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        value,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ListTile(
                  leading: const Icon(Icons.copy, color: troonkyColor),
                  title: const Text("Copy"),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: value));
                    if (context.mounted) Navigator.pop(context);
                    _snack("Copied ✅");
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // =========================
  // ✅ UI
  // =========================
  @override
  Widget build(BuildContext context) {
    final hasMore = _rawHasMore;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      floatingActionButton: GestureDetector(
        onTap: () async {
          _FeedVideoHub.pauseAny();
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NewPostPage()),
          );
          if (mounted) _loadPosts();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            gradient: troonkyGradient(),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: troonkyGradA.withOpacity(0.25),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, color: Colors.white),
              SizedBox(width: 8),
              Text("New Post",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
      body: loading
          ? const _FeedSkeleton()
          : (_error != null)
          ? _ErrorState(message: _error!, onRetry: _loadPosts)
          : RefreshIndicator(
        onRefresh: _loadPosts,
        child: ListView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          itemCount: _posts.length + (hasMore ? 1 : 0),
          itemBuilder: (_, i) {
            if (i == _posts.length) {
              if (!loadingMore && !_fetching && _rawHasMore) {
                Future.microtask(() => _loadMore());
              }
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: (loadingMore || _fetching)
                      ? const CircularProgressIndicator()
                      : const SizedBox.shrink(),
                ),
              );
            }

            final post = _posts[i];
            final id = (post["id"] ?? "").toString();
            final mine = _isMine(post);

            return PostCard(
              post: post,
              isLiked: _liked.contains(id),
              authToken: _authToken,
              isMine: mine,
              heroPrefix: "feed_${id}_$i", // ✅ avoids hero collisions
              onProfile: () {
                _FeedVideoHub.pauseAny();

                final userType =
                (post["user_type"] ?? "").toString().toLowerCase();
                final shopId = (post["shop_id"] ?? "").toString();

                if (userType == "business" && shopId.isNotEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BusinessProfilePage(
                        businessId: shopId,
                        isOwner: false,
                      ),
                    ),
                  );
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfilePage(
                        userId: (post["user_id"] ?? "").toString(),
                      ),
                    ),
                  );
                }
              },
              onLike: () => _toggleLike(post),
              onComment: () => _openComments(post),
              onShare: () => _sharePost(post),
              onDelete: () => _deletePost(post),
              onReport: () => _onReportPost(post),
              onBlock: () => _onBlockUser(post),
              onHashtagTap: _onHashtagTap,
              onMentionTap: _onMentionTap,
              onOpenReactions: () => _openReactions(post),
            );
          },
        ),
      ),
    );
  }
}

/* ========================== POST CARD ========================== */

class PostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final bool isLiked;
  final String? authToken;

  final bool isMine;
  final String heroPrefix;

  final VoidCallback onProfile, onLike, onComment, onShare;
  final VoidCallback onDelete;
  final void Function(String tag) onHashtagTap;
  final void Function(String username) onMentionTap;
  final VoidCallback onReport;
  final VoidCallback onBlock;

  final VoidCallback? onOpenReactions;

  const PostCard({
    super.key,
    required this.post,
    required this.isLiked,
    this.authToken,
    required this.isMine,
    required this.heroPrefix,
    required this.onProfile,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onDelete,
    required this.onHashtagTap,
    required this.onMentionTap,
    required this.onReport,
    required this.onBlock,
    this.onOpenReactions,
  });

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? "") ?? 0;
  }

  List<dynamic> _mediaList() {
    final m = post["media_urls"];
    if (m is List) return m;
    final single = post["media_url"] ?? post["mediaFile"];
    if (single != null && single.toString().trim().isNotEmpty) return [single];
    return [];
  }

  bool _isVideoUrl(String s) {
    final u = s.toLowerCase();
    return u.contains(".mp4") ||
        u.contains(".m3u8") ||
        u.contains(".mov") ||
        u.contains(".m4v") ||
        u.contains(".webm");
  }

  @override
  Widget build(BuildContext context) {
    final mediaList = _mediaList();

    final name = (post["user_name"] ?? post["name"] ?? "User").toString();
    final desc = (post["description"] ?? "").toString().trim();

    final likeCount =
    _toInt(post["likes_count"] ?? post["like_count"] ?? post["likes"] ?? 0);
    final shareCount = _toInt(
        post["shares_count"] ?? post["share_count"] ?? post["shares"] ?? 0);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(name),
          if (desc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: ClickableText(
                text: desc,
                onHashtagTap: onHashtagTap,
                onMentionTap: onMentionTap,
              ),
            ),
          if (mediaList.isNotEmpty) _media(mediaList),
          _countsRow(context, likeCount, shareCount),
          const Divider(height: 1),
          _actionsRow(context),
        ],
      ),
    );
  }

  Widget _header(String name) {
    final userType = (post["user_type"] ?? "").toString().toLowerCase();

    final pic = (userType == "business")
        ? (post["shop_logo"] ??
        post["user_profile_pic"] ??
        post["profile_pic"] ??
        "")
        .toString()
        .trim()
        : (post["user_profile_pic"] ??
        post["profile_pic"] ??
        post["userPic"] ??
        post["avatar"] ??
        "")
        .toString()
        .trim();

    final hasPic = pic.isNotEmpty;
    final picUrl = hasPic ? FeedAPI.toPublicUrl(pic) : "";

    return ListTile(
      onTap: onProfile,
      leading: SizedBox(
        width: 44,
        height: 44,
        child: hasPic
            ? CircleAvatar(
          backgroundColor: Colors.grey.shade200,
          backgroundImage: NetworkImage(picUrl),
          onBackgroundImageError: (_, __) {},
        )
            : Container(
          decoration: BoxDecoration(
            gradient: troonkyGradient(),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person, color: Colors.white),
        ),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text("Troonky Feed",
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == "delete") onDelete();
          if (v == "report") onReport();
          if (v == "block") onBlock();
        },
        itemBuilder: (_) {
          if (isMine) {
            return const [
              PopupMenuItem(value: "delete", child: Text("Delete")),
            ];
          }
          return const [
            PopupMenuItem(value: "report", child: Text("Report")),
            PopupMenuItem(value: "block", child: Text("Block")),
          ];
        },
      ),
    );
  }

  Widget _media(List list) {
    final first = list.first.toString().trim();

    if (list.length == 1 && _isVideoUrl(first)) {
      final videoUrl = FeedAPI.toPublicUrl(first);

      final hlsRaw = (post["video_hls_url"] ??
          post["hls_url"] ??
          post["video_hls"] ??
          post["stream_url"] ??
          post["m3u8_url"] ??
          "")
          .toString()
          .trim();
      final hlsUrl = hlsRaw.isEmpty ? null : FeedAPI.toPublicUrl(hlsRaw);

      final thumbRaw = (post["video_thumb"] ??
          post["thumb_url"] ??
          post["thumbnail_url"] ??
          post["thumbnail"] ??
          post["poster"] ??
          "")
          .toString()
          .trim();
      final thumbUrl = thumbRaw.isEmpty ? null : FeedAPI.toPublicUrl(thumbRaw);

      return ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        child: VideoBox(
          url: videoUrl,
          hlsUrl: hlsUrl,
          authToken: authToken,
          thumbnailUrl: thumbUrl,
          title: (post["description"] ?? post["user_name"] ?? "Video").toString(),
          height: 280,
        ),
      );
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      child: AspectRatio(
        aspectRatio: 1,
        child: CarouselMedia(
          urls: list.map((e) => FeedAPI.toPublicUrl(e.toString())).toList(),
          heroPrefix: heroPrefix,
        ),
      ),
    );
  }

  Widget _countsRow(BuildContext context, int likes, int shares) {
    String fmt(int n) => n <= 0 ? "0" : n.toString();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Row(
        children: [
          InkWell(
            onTap: (likes > 0) ? onOpenReactions : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                "${fmt(likes)} likes",
                style: TextStyle(
                  color: (likes > 0) ? troonkyColor : Colors.grey.shade700,
                  fontSize: 12.5,
                  fontWeight: (likes > 0) ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ),
          const Spacer(),
          Text("${fmt(shares)} shares",
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _actionsRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: ReactionLikeButton(
              isLiked: isLiked,
              onTapLike: onLike,
              onReact: (reaction) async {
                final postId = int.tryParse((post["id"] ?? "").toString()) ?? 0;
                if (postId <= 0) return;

                // ✅ IMPORTANT FIX:
                // Reaction will SAVE reaction in backend,
                // but Like toggle should NOT be triggered twice.
                // We only do optimistic like IF not liked already (simple)
                if (!isLiked) {
                  onLike();
                }

                final res = await FeedAPI.reactPost(postId, reaction);
                if (res["ok"] != true) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(res["message"]?.toString() ??
                            "Reaction not saved")),
                  );
                }
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GradientActionButton(
              label: "Comment",
              icon: Icons.comment,
              active: false,
              onTap: onComment,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GradientActionButton(
              label: "Share",
              icon: Icons.share,
              active: false,
              onTap: onShare,
            ),
          ),
        ],
      ),
    );
  }
}

/* ========================== REACTIONS SHEET ========================== */

class ReactionsSheet extends StatefulWidget {
  final int postId;
  final String postTitle;

  const ReactionsSheet({
    super.key,
    required this.postId,
    required this.postTitle,
  });

  @override
  State<ReactionsSheet> createState() => _ReactionsSheetState();
}

class _ReactionsSheetState extends State<ReactionsSheet> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _all = [];
  String _filter = "all";

  static const _filters = ["all", "like", "love", "haha", "wow", "sad", "angry"];

  String _emoji(String r) {
    switch (r) {
      case "like":
        return "👍";
      case "love":
        return "❤️";
      case "haha":
        return "😂";
      case "wow":
        return "😮";
      case "sad":
        return "😢";
      case "angry":
        return "😡";
      default:
        return "👍";
    }
  }

  String _norm(dynamic r) => (r ?? "").toString().trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      dynamic resp;
      try {
        resp = await (FeedAPI as dynamic).fetchPostReactions(widget.postId);
      } catch (_) {
        try {
          resp = await (FeedAPI as dynamic).getPostReactions(widget.postId);
        } catch (_) {
          resp = await (FeedAPI as dynamic).postReactions(widget.postId);
        }
      }

      List items = [];
      if (resp is Map && resp["items"] is List) {
        items = resp["items"] as List;
      } else if (resp is List) {
        items = resp;
      } else if (resp is Map && resp["data"] is List) {
        items = resp["data"] as List;
      }

      final list = items
          .map((e) => (e is Map)
          ? Map<String, dynamic>.from(e)
          : <String, dynamic>{})
          .where((m) => m.isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Reactions list not available (API missing).";
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == "all") return _all;
    return _all
        .where((e) =>
    _norm(e["reaction"] ?? e["type"] ?? e["emoji"]) == _filter)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.postTitle.trim();
    final showTitle = title.isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  "Reactions",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        if (showTitle)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
            ),
          ),
        SizedBox(
          height: 42,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemBuilder: (_, i) {
              final f = _filters[i];
              final active = f == _filter;
              final chipText = (f == "all") ? "All" : _emoji(f);
              return ChoiceChip(
                selected: active,
                label: Text(
                  chipText,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: active ? Colors.white : troonkyColor,
                  ),
                ),
                selectedColor: troonkyColor,
                onSelected: (_) => setState(() => _filter = f),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemCount: _filters.length,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : (_error != null)
              ? _SheetError(message: _error!, onRetry: _load)
              : (_filtered.isEmpty)
              ? const Center(
            child: Text(
              "No reactions yet",
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          )
              : ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            itemBuilder: (_, i) {
              final u = _filtered[i];

              final name =
              (u["user_name"] ?? u["name"] ?? "User").toString();
              final pic = (u["profile_pic"] ??
                  u["user_profile_pic"] ??
                  u["avatar"] ??
                  "")
                  .toString()
                  .trim();
              final reaction = _norm(
                  u["reaction"] ?? u["type"] ?? u["emoji"] ?? "like");
              final emoji = _emoji(reaction);

              return ListTile(
                leading: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: pic.isNotEmpty
                          ? NetworkImage(FeedAPI.toPublicUrl(pic))
                          : null,
                      child: pic.isEmpty
                          ? const Icon(Icons.person,
                          color: troonkyColor)
                          : null,
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.10),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            )
                          ],
                        ),
                        child: Text(
                          emoji,
                          style: const TextStyle(
                            fontSize: 14,
                            fontFamilyFallback: [
                              'Noto Color Emoji',
                              'Segoe UI Emoji',
                              'Apple Color Emoji'
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                title: Text(name,
                    style:
                    const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(reaction,
                    style: TextStyle(
                        color: Colors.grey.shade700, fontSize: 12)),
              );
            },
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemCount: _filtered.length,
          ),
        ),
      ],
    );
  }
}

class _SheetError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _SheetError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42, color: troonkyColor),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(backgroundColor: troonkyColor),
              child: const Text("Retry"),
            ),
          ],
        ),
      ),
    );
  }
}

/* ========================== UI helpers ========================== */

class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics()),
      itemCount: 6,
      itemBuilder: (_, __) => Card(
        elevation: 1.5,
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          height: 260,
          child: Center(
              child: CircularProgressIndicator(
                  color: troonkyColor.withOpacity(0.7))),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 44, color: troonkyColor),
            const SizedBox(height: 10),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(backgroundColor: troonkyColor),
              child: const Text("Retry"),
            ),
          ],
        ),
      ),
    );
  }
}

/* ========================== GRADIENT ACTION BUTTON ========================== */

class GradientActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const GradientActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final border = Border.all(color: troonkyColor.withOpacity(0.18), width: 1);

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          gradient: active ? troonkyGradient() : null,
          color: active ? null : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: active ? null : border,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: active ? Colors.white : troonkyColor, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : troonkyColor,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ========================== CLICKABLE TEXT (# + @) ========================== */

class ClickableText extends StatelessWidget {
  final String text;
  final void Function(String tag) onHashtagTap;
  final void Function(String username) onMentionTap;

  const ClickableText({
    super.key,
    required this.text,
    required this.onHashtagTap,
    required this.onMentionTap,
  });

  @override
  Widget build(BuildContext context) {
    final spans = _buildSpans(text);
    return RichText(
      text: TextSpan(
        style: const TextStyle(
            fontSize: 14.5, height: 1.35, color: Colors.black87),
        children: spans,
      ),
    );
  }

  List<TextSpan> _buildSpans(String input) {
    final exp = RegExp(r'(#\w+|@\w+)');
    final matches = exp.allMatches(input).toList();
    if (matches.isEmpty) return [TextSpan(text: input)];

    final spans = <TextSpan>[];
    int last = 0;

    for (final m in matches) {
      if (m.start > last) {
        spans.add(TextSpan(text: input.substring(last, m.start)));
      }

      final token = input.substring(m.start, m.end);
      final isHash = token.startsWith("#");
      final isAt = token.startsWith("@");

      spans.add(
        TextSpan(
          text: token,
          style:
          const TextStyle(color: troonkyColor, fontWeight: FontWeight.w800),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              HapticFeedback.selectionClick();
              if (isHash) onHashtagTap(token);
              if (isAt) onMentionTap(token);
            },
        ),
      );

      last = m.end;
    }

    if (last < input.length) spans.add(TextSpan(text: input.substring(last)));
    return spans;
  }
}

/* ========================== CAROUSEL (tap => fullscreen) ========================== */

class CarouselMedia extends StatefulWidget {
  final List<String> urls;
  final String heroPrefix;

  const CarouselMedia({super.key, required this.urls, required this.heroPrefix});

  @override
  State<CarouselMedia> createState() => _CarouselMediaState();
}

class _CarouselMediaState extends State<CarouselMedia> {
  final PageController _pc = PageController();
  int _idx = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _openFullscreen(int initialIndex) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => _FullscreenImageViewer(
          urls: widget.urls,
          initialIndex: initialIndex,
          heroPrefix: widget.heroPrefix,
        ),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PageView.builder(
          controller: _pc,
          itemCount: widget.urls.length,
          onPageChanged: (i) => setState(() => _idx = i),
          itemBuilder: (_, i) {
            final url = widget.urls[i];
            return GestureDetector(
              onTap: () => _openFullscreen(i),
              child: Hero(
                tag: "${widget.heroPrefix}_img_$url",
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  loadingBuilder: (c, w, p) =>
                  (p == null) ? w : const Center(child: CircularProgressIndicator()),
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.black12,
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image, size: 40),
                  ),
                ),
              ),
            );
          },
        ),
        if (widget.urls.length > 1)
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.urls.length, (i) {
                final active = i == _idx;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 10 : 6,
                  height: active ? 10 : 6,
                  decoration: BoxDecoration(
                    color: active ? Colors.white : Colors.white70,
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

class _FullscreenImageViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  final String heroPrefix;

  const _FullscreenImageViewer({
    required this.urls,
    required this.initialIndex,
    required this.heroPrefix,
  });

  @override
  State<_FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<_FullscreenImageViewer> {
  late final PageController _pc;
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    _idx = widget.initialIndex.clamp(0, widget.urls.length - 1);
    _pc = PageController(initialPage: _idx);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: PageView.builder(
              controller: _pc,
              onPageChanged: (i) => setState(() => _idx = i),
              itemCount: widget.urls.length,
              itemBuilder: (_, i) {
                final url = widget.urls[i];
                return Center(
                  child: Hero(
                    tag: "${widget.heroPrefix}_img_$url",
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        loadingBuilder: (c, w, p) =>
                        (p == null) ? w : const CircularProgressIndicator(),
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image,
                            color: Colors.white70, size: 60),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ),
          if (widget.urls.length > 1)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    "${_idx + 1}/${widget.urls.length}",
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/* ========================== FEED VIDEO HUB (one play at a time) ========================== */

class _FeedVideoHub {
  static VoidCallback? _pauseCurrent;

  static void claim(VoidCallback pauseMe) {
    if (_pauseCurrent != null && _pauseCurrent != pauseMe) {
      try {
        _pauseCurrent!.call();
      } catch (_) {}
    }
    _pauseCurrent = pauseMe;
  }

  static void release(VoidCallback pauseMe) {
    if (_pauseCurrent == pauseMe) _pauseCurrent = null;
  }

  static void pauseAny() {
    try {
      _pauseCurrent?.call();
    } catch (_) {}
  }
}

/* ========================== VIDEO (no autoplay + thumb + adaptive HLS) ========================== */

class VideoBox extends StatefulWidget {
  final String url;
  final String? hlsUrl;
  final String? thumbnailUrl;
  final String? authToken;
  final String? title;
  final double height;

  const VideoBox({
    super.key,
    required this.url,
    this.hlsUrl,
    this.thumbnailUrl,
    this.authToken,
    this.title,
    this.height = 280,
  });

  @override
  State<VideoBox> createState() => _VideoBoxState();
}

class _VideoBoxState extends State<VideoBox> with WidgetsBindingObserver {
  VideoPlayerController? _ctrl;

  bool _initing = false;
  bool _ready = false;
  bool _muted = false;

  Timer? _disposeTimer;
  String? _token;

  static const String _apiHost = "adminapi.troonky.in";

  String get _effectiveUrl {
    final hls = (widget.hlsUrl ?? "").trim();
    if (hls.isNotEmpty && hls.toLowerCase().contains(".m3u8")) return hls;
    return widget.url.trim();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _token = widget.authToken;
    if (_token == null || _token!.isEmpty) {
      _loadToken();
    }
  }

  @override
  void didUpdateWidget(covariant VideoBox oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.authToken != oldWidget.authToken) {
      _token = widget.authToken;
    }
    if (oldWidget.url != widget.url || oldWidget.hlsUrl != widget.hlsUrl) {
      _FeedVideoHub.release(_pauseMe);
      _disposeTimer?.cancel();
      _disposeTimer = null;
      _disposeController();
    }
  }

  Future<void> _loadToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final t = prefs.getString("token")?.trim();
      if (!mounted) return;
      _token = (t == null || t.isEmpty) ? null : t;
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _disposeTimer?.cancel();
    _disposeTimer = null;

    _FeedVideoHub.release(_pauseMe);
    _disposeController();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _pauseMe();
    }
  }

  Map<String, String> _headersForUrl(String url) {
    try {
      final u = Uri.parse(url);
      if (u.host == _apiHost && _token != null && _token!.isNotEmpty) {
        return {"Authorization": "Bearer $_token"};
      }
    } catch (_) {}
    return const {};
  }

  void _pauseMe() {
    final c = _ctrl;
    if (c == null) return;
    if (c.value.isInitialized && c.value.isPlaying) {
      try {
        c.pause();
      } catch (_) {}
      if (mounted) setState(() {});
    }
  }

  Future<void> _ensureInit() async {
    if (_ctrl != null || _initing) return;
    final url = _effectiveUrl;
    if (url.isEmpty) return;

    if (_token == null) await _loadToken();

    _initing = true;

    final headers = _headersForUrl(url);

    final c = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: headers,
      formatHint: url.contains(".m3u8") ? VideoFormat.hls : null,
    );
    _ctrl = c;

    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(_muted ? 0 : 1);

      if (!mounted) {
        c.dispose();
        return;
      }

      setState(() => _ready = true);
    } catch (_) {
      try {
        c.dispose();
      } catch (_) {}
      _ctrl = null;
      if (mounted) setState(() => _ready = false);
    } finally {
      _initing = false;
      if (mounted) setState(() {});
    }
  }

  void _disposeController() {
    final c = _ctrl;
    _ctrl = null;
    _ready = false;
    _initing = false;

    if (c != null) {
      try {
        c.pause();
      } catch (_) {}
      try {
        c.dispose();
      } catch (_) {}
    }
  }

  void _scheduleDispose() {
    _disposeTimer?.cancel();
    _disposeTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      _FeedVideoHub.release(_pauseMe);
      _disposeController();
      if (mounted) setState(() {});
    });
  }

  void _cancelDispose() {
    _disposeTimer?.cancel();
    _disposeTimer = null;
  }

  Future<void> _togglePlay() async {
    HapticFeedback.lightImpact();
    _FeedVideoHub.claim(_pauseMe);

    if (_ctrl == null) {
      await _ensureInit();
    }

    final c = _ctrl;
    if (c == null || !c.value.isInitialized) return;

    if (c.value.isPlaying) {
      _pauseMe();
    } else {
      try {
        await c.play();
      } catch (_) {}
      if (mounted) setState(() {});
    }
  }

  void _toggleMute() {
    HapticFeedback.lightImpact();
    _muted = !_muted;

    final c = _ctrl;
    if (c != null && c.value.isInitialized) {
      c.setVolume(_muted ? 0 : 1);
    }
    if (mounted) setState(() {});
  }

  Future<void> _openFullscreen() async {
    final url = _effectiveUrl;
    if (url.isEmpty) return;

    _pauseMe();
    _FeedVideoHub.pauseAny();

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoFullscreenPage(
          url: url,
          title: widget.title,
          thumbUrl: widget.thumbnailUrl,
          headers: _headersForUrl(url),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: ValueKey("feed_video_${_effectiveUrl.hashCode}"),
      onVisibilityChanged: (info) {
        final v = info.visibleFraction;

        if (v < 0.15) {
          _pauseMe();
          _scheduleDispose();
          return;
        }

        _cancelDispose();

        if (v > 0.20 && !_ready && !_initing) {
          _ensureInit();
        }
      },
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_ctrl != null && _ready && _ctrl!.value.isInitialized)
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _ctrl!.value.size.width,
                    height: _ctrl!.value.size.height,
                    child: VideoPlayer(_ctrl!),
                  ),
                )
              else
                _thumbOrFallback(),
              Positioned.fill(
                child: GestureDetector(
                  onTap: _togglePlay,
                  onDoubleTap: _openFullscreen,
                  onLongPress: _toggleMute,
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox.expand(),
                ),
              ),
              if (!(_ctrl?.value.isPlaying ?? false))
                const Center(
                  child: Icon(Icons.play_circle, size: 64, color: Colors.white70),
                ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 8,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _togglePlay,
                      icon: Icon(
                        (_ctrl?.value.isPlaying ?? false) ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                      ),
                    ),
                    Expanded(
                      child: (_ctrl != null && _ready && _ctrl!.value.isInitialized)
                          ? VideoProgressIndicator(
                        _ctrl!,
                        allowScrubbing: true,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        colors: VideoProgressColors(
                          playedColor: troonkyColor,
                          bufferedColor: Colors.white54,
                          backgroundColor: Colors.white24,
                        ),
                      )
                          : const SizedBox(height: 18),
                    ),
                    IconButton(
                      onPressed: _toggleMute,
                      icon: Icon(_muted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
                    ),
                  ],
                ),
              ),
              if (_initing)
                Container(
                  color: Colors.black26,
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbOrFallback() {
    final t = (widget.thumbnailUrl ?? "").trim();
    if (t.isNotEmpty) {
      return Image.network(
        t,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(color: Colors.black12),
        loadingBuilder: (c, w, p) => (p == null)
            ? w
            : Container(
          color: Colors.black12,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(),
        ),
      );
    }
    return Container(color: Colors.black12);
  }
}

/* ========================== REACTION LIKE BUTTON (FB style) ========================== */

class ReactionLikeButton extends StatefulWidget {
  final bool isLiked;
  final VoidCallback onTapLike;
  final void Function(String reaction) onReact;

  const ReactionLikeButton({
    super.key,
    required this.isLiked,
    required this.onTapLike,
    required this.onReact,
  });

  @override
  State<ReactionLikeButton> createState() => _ReactionLikeButtonState();
}

class _ReactionLikeButtonState extends State<ReactionLikeButton> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;

  void _hide() {
    final e = _entry;
    if (e != null) {
      try {
        e.remove();
      } catch (_) {}
      _entry = null;
    }
  }

  void _showPopup() {
    if (!mounted) return;
    if (_entry != null) return;

    final overlay = Overlay.of(context);
    if (overlay == null) return;

    HapticFeedback.selectionClick();

    _entry = OverlayEntry(
      builder: (_) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _hide,
          child: Stack(
            children: [
              CompositedTransformFollower(
                link: _link,
                showWhenUnlinked: false,
                offset: const Offset(-120, -72),
                child: Material(
                  color: Colors.transparent,
                  child: ReactionPopup(
                    onSelect: (reaction) {
                      widget.onReact(reaction);
                      _hide();
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    overlay.insert(_entry!);
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final border = Border.all(color: troonkyColor.withOpacity(0.18), width: 1);

    return CompositedTransformTarget(
      link: _link,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: widget.onTapLike,
        onLongPress: _showPopup,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            gradient: widget.isLiked ? troonkyGradient() : null,
            color: widget.isLiked ? null : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: widget.isLiked ? null : border,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.isLiked ? Icons.favorite : Icons.favorite_border,
                color: widget.isLiked ? Colors.white : troonkyColor,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                "Like",
                style: TextStyle(
                  color: widget.isLiked ? Colors.white : troonkyColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReactionPopup extends StatelessWidget {
  final void Function(String reaction) onSelect;

  const ReactionPopup({super.key, required this.onSelect});

  Widget _emoji(String reaction, String emoji) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => onSelect(reaction),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Text(
          emoji,
          style: const TextStyle(
            fontSize: 26,
            fontFamilyFallback: [
              'Noto Color Emoji',
              'Segoe UI Emoji',
              'Apple Color Emoji'
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _emoji("like", "👍"),
          _emoji("love", "❤️"),
          _emoji("haha", "😂"),
          _emoji("wow", "😮"),
          _emoji("sad", "😢"),
          _emoji("angry", "😡"),
        ],
      ),
    );
  }
}
