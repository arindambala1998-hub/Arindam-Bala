import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:troonky_link/services/feed_api.dart';
import 'package:troonky_link/helpers/block_helper.dart';
import 'package:troonky_link/pages/profile/profile_page.dart';

// ✅ Feed page যে comment sheet ব্যবহার করে সেটাই ব্যবহার করো
import 'package:troonky_link/pages/post_comments_sheet.dart';

/// =========================
/// Troonky Theme
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

/// ====================================================
/// PROFILE POSTS TAB (Feed-style + owner delete)
/// ====================================================
/// ✅ ProfilePage থেকে এগুলো pass করলে name/pic সবসময় ঠিক দেখাবে:
/// ProfilePostsTab(
///   posts: posts,
///   profileUserId: int.tryParse(profileUserIdString),
///   profileName: profileName,
///   profilePic: profilePic,
/// )
class ProfilePostsTab extends StatefulWidget {
  final List<dynamic> posts;

  /// ✅ Profile identity fallback
  final int? profileUserId;
  final String? profileName;
  final String? profilePic; // raw path or url

  const ProfilePostsTab({
    super.key,
    required this.posts,
    this.profileUserId,
    this.profileName,
    this.profilePic,
  });

  @override
  State<ProfilePostsTab> createState() => _ProfilePostsTabState();
}

class _ProfilePostsTabState extends State<ProfilePostsTab>
    with WidgetsBindingObserver {
  final List<Map<String, dynamic>> _posts = [];
  final Set<String> _likedIds = {};

  int? _myUserId;

  // own info fallback (when API doesn’t send user_name/pic)
  String? _myName;
  String? _myPic;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hydrate();
  }

  @override
  void didUpdateWidget(covariant ProfilePostsTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ✅ IMPORTANT: overwrite না করে MERGE করবে, যাতে count reset না হয়
    if (!identical(oldWidget.posts, widget.posts) ||
        oldWidget.posts.length != widget.posts.length) {
      _mergeIncoming(widget.posts);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  Future<void> _hydrate() async {
    await BlockHelper.init();
    await _loadMyIdentity();

    _mergeIncoming(widget.posts);

    // preload liked set from server flags
    _likedIds.clear();
    for (final p in _posts) {
      final id = (p["id"] ?? "").toString();
      final liked = (p["is_liked"] == true) || (p["liked"] == true);
      if (id.isNotEmpty && liked) _likedIds.add(id);
    }

    if (mounted) setState(() {});
  }

  // ✅ merge incoming posts without losing local counters/liked state
  void _mergeIncoming(List<dynamic> incoming) {
    final incomingMaps =
    incoming.map((e) => Map<String, dynamic>.from(e ?? {})).toList();

    // apply block filter
    final filtered =
    BlockHelper.filterBlockedUsers(incomingMaps, userIdKey: "user_id");

    final byId = <String, Map<String, dynamic>>{};
    for (final p in _posts) {
      final id = (p["id"] ?? "").toString();
      if (id.isNotEmpty) byId[id] = p;
    }

    const keepKeys = <String>{
      "likes_count",
      "like_count",
      "likes",
      "shares_count",
      "share_count",
      "shares",
      "comments_count",
      "comment_count",
      "comments",
      "is_liked",
      "liked",
    };

    final merged = <Map<String, dynamic>>[];

    for (final inc in filtered) {
      final id = (inc["id"] ?? "").toString();
      if (id.isEmpty) {
        merged.add(inc);
        continue;
      }

      final existing = byId[id];
      if (existing == null) {
        merged.add(inc);
        continue;
      }

      // keep local counters/liked flags, update rest from incoming
      final next = Map<String, dynamic>.from(existing);
      for (final entry in inc.entries) {
        if (keepKeys.contains(entry.key)) continue;
        next[entry.key] = entry.value;
      }
      merged.add(next);
    }

    _posts
      ..clear()
      ..addAll(merged);
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? "") ?? 0;
  }

  Future<void> _loadMyIdentity() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final idStr = prefs.getString("userId") ??
          prefs.getString("user_id") ??
          prefs.getString("id") ??
          prefs.getInt("userId")?.toString() ??
          prefs.getInt("user_id")?.toString();

      _myUserId = int.tryParse((idStr ?? "").toString());

      _myName = (prefs.getString("user_name") ??
          prefs.getString("username") ??
          prefs.getString("name") ??
          prefs.getString("full_name") ??
          prefs.getString("fullName") ??
          "")
          .trim();
      if (_myName != null && _myName!.isEmpty) _myName = null;

      _myPic = (prefs.getString("user_profile_pic") ??
          prefs.getString("profile_pic") ??
          prefs.getString("avatar") ??
          prefs.getString("userPic") ??
          "")
          .trim();
      if (_myPic != null && _myPic!.isEmpty) _myPic = null;

      // ✅ JWT fallback
      if (_myUserId == null || _myUserId == 0) {
        final token = prefs.getString("token")?.trim();
        final jwtId = _tryExtractUserIdFromJwt(token);
        if (jwtId != null && jwtId > 0) _myUserId = jwtId;
      }
    } catch (_) {
      _myUserId = null;
    }
  }

  int? _tryExtractUserIdFromJwt(String? token) {
    try {
      if (token == null || token.isEmpty) return null;
      final parts = token.split(".");
      if (parts.length < 2) return null;

      String payload = parts[1];
      payload = payload.replaceAll("-", "+").replaceAll("_", "/");
      while (payload.length % 4 != 0) {
        payload += "=";
      }

      final decoded = utf8.decode(base64Decode(payload));
      final map = jsonDecode(decoded);

      if (map is Map) {
        final v = map["userId"] ?? map["id"] ?? map["user_id"];
        final n = int.tryParse(v?.toString() ?? "");
        return n;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  bool _isMine(Map<String, dynamic> post) {
    final uid = _toInt(post["user_id"] ?? post["userId"] ?? post["owner_id"] ?? 0);

    // normal case
    if (_myUserId != null && _myUserId! > 0 && uid > 0) {
      return uid == _myUserId;
    }

    // ✅ fallback: if this tab is my profile, treat as mine
    if (widget.profileUserId != null && _myUserId != null) {
      if (widget.profileUserId == _myUserId) return true;
    }

    return false;
  }

  // -------------------- ACTIONS --------------------

  Future<void> _toggleLike(Map<String, dynamic> post) async {
    final idStr = (post["id"] ?? "").toString();
    final postId = int.tryParse(idStr) ?? 0;
    if (postId <= 0) return;

    HapticFeedback.lightImpact();

    final wasLiked = _likedIds.contains(idStr);
    final curLikes =
    _toInt(post["likes_count"] ?? post["like_count"] ?? post["likes"] ?? 0);

    // optimistic
    setState(() {
      final nextLikes =
      wasLiked ? (curLikes - 1 < 0 ? 0 : curLikes - 1) : (curLikes + 1);

      if (wasLiked) {
        _likedIds.remove(idStr);
      } else {
        _likedIds.add(idStr);
      }

      final likedNow = _likedIds.contains(idStr);
      post["is_liked"] = likedNow;
      post["liked"] = likedNow;

      post["likes_count"] = nextLikes;
      post["like_count"] = nextLikes;
      post["likes"] = nextLikes;
    });

    final res = await FeedAPI.toggleLike(postId, currentlyLiked: wasLiked);
    if (!mounted) return;

    if (res["ok"] != true) {
      // rollback
      setState(() {
        if (wasLiked) {
          _likedIds.add(idStr);
        } else {
          _likedIds.remove(idStr);
        }

        post["is_liked"] = wasLiked;
        post["liked"] = wasLiked;

        post["likes_count"] = curLikes;
        post["like_count"] = curLikes;
        post["likes"] = curLikes;
      });
      return;
    }

    final apiLiked = res["liked"] == true;
    final apiLikes = res["likes"];

    setState(() {
      if (apiLiked) {
        _likedIds.add(idStr);
      } else {
        _likedIds.remove(idStr);
      }

      post["is_liked"] = apiLiked;
      post["liked"] = apiLiked;

      final fixedLikes = (apiLikes is int)
          ? apiLikes
          : int.tryParse(apiLikes?.toString() ?? "") ??
          _toInt(post["likes_count"]);
      post["likes_count"] = fixedLikes;
      post["like_count"] = fixedLikes;
      post["likes"] = fixedLikes;
    });
  }

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
              post["comments_count"] ?? post["comment_count"] ?? post["comments"] ?? 0),
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
    _FeedVideoHub.pauseAny();

    final text = (post["description"] ?? "").toString();
    final media = _mediaList(post);
    final firstUrl =
    media.isNotEmpty ? FeedAPI.toPublicUrl(media.first.toString()) : "";

    await Share.share("🔥 Troonky Post\n\n$text\n\n$firstUrl");

    final postId = int.tryParse((post["id"] ?? "").toString()) ?? 0;
    if (postId <= 0) return;

    final curShares =
    _toInt(post["shares_count"] ?? post["share_count"] ?? post["shares"] ?? 0);
    final newShares = await FeedAPI.sharePost(postId);
    if (!mounted) return;

    setState(() {
      final fixed = (newShares > 0) ? newShares : (curShares + 1);
      post["shares_count"] = fixed;
      post["share_count"] = fixed;
      post["shares"] = fixed;
    });
  }

  Future<void> _reportPost(Map<String, dynamic> post) async {
    final postId = int.tryParse((post["id"] ?? "").toString()) ?? 0;
    if (postId <= 0) return;

    _FeedVideoHub.pauseAny();

    final reason = await _askReasonSheet(title: "Report Post", defaultReason: "spam");
    if (reason == null) return;

    try {
      final res = await FeedAPI.reportPost(postId: postId, reason: reason);
      if (!mounted) return;

      if (res["ok"] == true) {
        setState(() => _posts.removeWhere(
                (p) => (p["id"] ?? "").toString() == postId.toString()));
        _snack("Reported ✅");
      } else {
        _snack("Report failed", error: true);
      }
    } catch (e) {
      if (!mounted) return;
      _snack("Report failed: $e", error: true);
    }
  }

  Future<void> _blockUserFromPost(Map<String, dynamic> post) async {
    final uid = _toInt(post["user_id"] ?? post["userId"] ?? 0);
    if (uid <= 0) return;

    _FeedVideoHub.pauseAny();

    final ok = await _confirmDialog(
      title: "Block user?",
      message: "You will not see this user’s posts again.",
      okText: "Block",
    );
    if (ok != true) return;

    await BlockHelper.blockUser(uid);

    if (!mounted) return;
    setState(() {
      _posts.removeWhere((p) => _toInt(p["user_id"] ?? p["userId"] ?? 0) == uid);
    });

    _snack("Blocked ✅");
  }

  Future<void> _deletePost(Map<String, dynamic> post) async {
    final postId = int.tryParse((post["id"] ?? "").toString()) ?? 0;
    if (postId <= 0) return;

    _FeedVideoHub.pauseAny();

    final ok = await _confirmDialog(
      title: "Delete post?",
      message: "This can’t be undone.",
      okText: "Delete",
      danger: true,
    );
    if (ok != true) return;

    try {
      final res = await FeedAPI.deletePost(postId);
      if (!mounted) return;

      if (res["ok"] == true) {
        setState(() => _posts.removeWhere(
                (p) => (p["id"] ?? "").toString() == postId.toString()));
        _snack("Deleted ✅");
      } else {
        _snack(res["message"]?.toString() ?? "Delete failed", error: true);
      }
    } catch (e) {
      if (!mounted) return;
      _snack("Delete failed: $e", error: true);
    }
  }

  // -------------------- REACTIONS (✅ FIXED) --------------------

  void _openReactions(Map<String, dynamic> post) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Reactions",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _reactionChip("👍", "Like"),
                    _reactionChip("❤️", "Love"),
                    _reactionChip("😆", "Haha"),
                    _reactionChip("😮", "Wow"),
                    _reactionChip("😢", "Sad"),
                    _reactionChip("😡", "Angry"),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  "Backend reaction API connect korle ekhane reaction save hobe.",
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _reactionChip(String emoji, String label) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$emoji $label (coming soon)")),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text("$emoji  $label"),
      ),
    );
  }

  // -------------------- UI HELPERS --------------------

  Future<String?> _askReasonSheet(
      {required String title, required String defaultReason}) async {
    final reasons = <String>[
      defaultReason,
      "hate",
      "nudity",
      "violence",
      "harassment",
      "spam",
      "other",
    ];

    return showModalBottomSheet<String>(
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: troonkyGradient(),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(title,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...reasons.map((r) => ListTile(
                  title: Text(r),
                  onTap: () => Navigator.pop(context, r),
                )),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String message,
    required String okText,
    bool danger = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(okText,
                style: TextStyle(
                    color: danger ? Colors.red : troonkyColor,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? Colors.red : Colors.green,
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static List<dynamic> _mediaList(Map<String, dynamic> post) {
    final m = post["media_urls"];
    if (m is List) return m;
    final single = post["media_url"] ?? post["mediaFile"];
    if (single != null && single.toString().trim().isNotEmpty) return [single];
    return [];
  }

  @override
  Widget build(BuildContext context) {
    if (_posts.isEmpty) {
      return const Center(
        child: Text("No posts yet",
            style: TextStyle(fontSize: 16, color: Colors.grey)),
      );
    }

    final fallbackName = widget.profileName ?? _myName;
    final fallbackPic = widget.profilePic ?? _myPic;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: _posts.length,
      itemBuilder: (_, i) {
        final post = _posts[i];
        final postId = int.tryParse((post["id"] ?? "").toString()) ?? 0;

        return _ProfilePostCard(
          post: post,
          isLiked: _likedIds.contains((post["id"] ?? "").toString()),
          isMine: _isMine(post),
          fallbackName: fallbackName,
          fallbackPic: fallbackPic,
          onProfile: () {
            _FeedVideoHub.pauseAny();
            final uidStr =
            (post["user_id"] ?? post["userId"] ?? "").toString().trim();
            if (uidStr.isEmpty) return;
            Navigator.push(
                context, MaterialPageRoute(builder: (_) => ProfilePage(userId: uidStr)));
          },
          onLike: () => _toggleLike(post),
          onComment: () => _openComments(post),
          onShare: () => _sharePost(post),
          onDelete: () => _deletePost(post),
          onReport: () => _reportPost(post),
          onBlock: () => _blockUserFromPost(post),
          onOpenReactions: () => _openReactions(post), // ✅ FIXED
          heroPrefix: "profile_$postId",
        );
      },
    );
  }
}

/// ====================================================
/// POST CARD (Feed-like)
/// ====================================================
class _ProfilePostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final bool isLiked;
  final bool isMine;

  final String? fallbackName;
  final String? fallbackPic;

  final VoidCallback onProfile;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;

  final VoidCallback onDelete; // only if mine
  final VoidCallback onReport;
  final VoidCallback onBlock;

  final VoidCallback onOpenReactions; // ✅ ADD
  final String heroPrefix;

  const _ProfilePostCard({
    required this.post,
    required this.isLiked,
    required this.isMine,
    required this.onProfile,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onDelete,
    required this.onReport,
    required this.onBlock,
    required this.onOpenReactions, // ✅ ADD
    required this.heroPrefix,
    this.fallbackName,
    this.fallbackPic,
  });

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? "") ?? 0;
  }

  Map<String, dynamic>? _userMap() {
    final u = post["user"] ?? post["user_info"] ?? post["userInfo"] ?? post["author"];
    return (u is Map) ? Map<String, dynamic>.from(u) : null;
  }

  String _userName() {
    final u = _userMap();
    final v = post["user_name"] ??
        post["username"] ??
        post["name"] ??
        post["full_name"] ??
        post["fullName"] ??
        post["userName"] ??
        u?["user_name"] ??
        u?["username"] ??
        u?["name"] ??
        u?["full_name"] ??
        u?["fullName"];

    final s = (v ?? "").toString().trim();
    if (s.isNotEmpty) return s;

    final fb = (fallbackName ?? "").trim();
    return fb.isNotEmpty ? fb : "User";
  }

  String _profilePic() {
    final u = _userMap();
    final v = post["user_profile_pic"] ??
        post["profile_pic"] ??
        post["avatar"] ??
        post["userPic"] ??
        post["profilePic"] ??
        u?["user_profile_pic"] ??
        u?["profile_pic"] ??
        u?["avatar"] ??
        u?["userPic"] ??
        u?["profilePic"];

    final s = (v ?? "").toString().trim();
    if (s.isNotEmpty) return s;

    return (fallbackPic ?? "").trim();
  }

  String _timeText() {
    final v = post["created_at"] ?? post["createdAt"] ?? post["time"] ?? "";
    final s = v.toString().trim();
    return s.isEmpty ? "Just now" : s;
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
    final name = _userName();
    final pic = _profilePic();
    final picUrl = pic.isNotEmpty ? FeedAPI.toPublicUrl(pic) : "";

    final desc = (post["description"] ?? "").toString().trim();

    final likes = _toInt(post["likes_count"] ?? post["like_count"] ?? post["likes"] ?? 0);
    final shares = _toInt(post["shares_count"] ?? post["share_count"] ?? post["shares"] ?? 0);

    final media = _mediaList();

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            onTap: onProfile,
            leading: SizedBox(
              width: 44,
              height: 44,
              child: picUrl.isNotEmpty
                  ? CircleAvatar(
                backgroundColor: Colors.grey.shade200,
                backgroundImage: NetworkImage(picUrl),
                onBackgroundImageError: (_, __) {},
              )
                  : Container(
                decoration: BoxDecoration(gradient: troonkyGradient(), shape: BoxShape.circle),
                child: const Icon(Icons.person, color: Colors.white),
              ),
            ),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(_timeText(), style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
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
          ),

          if (desc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: ClickableText(
                text: desc,
                onHashtagTap: (tag) => _copySheet(context, "Hashtag", tag),
                onMentionTap: (u) => _copySheet(context, "Mention", u),
              ),
            ),

          if (media.isNotEmpty) _mediaWidget(media),

          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Row(
              children: [
                Text("${likes < 0 ? 0 : likes} likes",
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5)),
                const Spacer(),
                Text("${shares < 0 ? 0 : shares} shares",
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5)),
              ],
            ),
          ),

          const Divider(height: 1),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: GradientActionButton(
                    label: "Like",
                    icon: isLiked ? Icons.favorite : Icons.favorite_border,
                    active: isLiked,
                    onTap: onLike,
                    onLongPress: onOpenReactions, // ✅ LONG PRESS → REACTIONS
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
          ),
        ],
      ),
    );
  }

  Widget _mediaWidget(List list) {
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
          thumbnailUrl: thumbUrl,
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

  static void _copySheet(BuildContext context, String title, String value) {
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: troonkyGradient(),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(title,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(value,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
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
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text("Copied ✅")));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// ====================================================
/// BUTTON
/// ====================================================
class GradientActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onLongPress; // ✅ ADD

  const GradientActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.onLongPress, // ✅ ADD
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final border = Border.all(color: troonkyColor.withOpacity(0.18), width: 1);

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      onLongPress: onLongPress, // ✅ ADD
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

/// ====================================================
/// CLICKABLE TEXT (# + @)
/// ====================================================
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
        style: const TextStyle(fontSize: 14.5, height: 1.35, color: Colors.black87),
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
      if (m.start > last) spans.add(TextSpan(text: input.substring(last, m.start)));

      final token = input.substring(m.start, m.end);
      final isHash = token.startsWith("#");
      final isAt = token.startsWith("@");

      spans.add(
        TextSpan(
          text: token,
          style: const TextStyle(color: troonkyColor, fontWeight: FontWeight.w800),
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

/// ====================================================
/// CAROUSEL + FULLSCREEN
/// ====================================================
class CarouselMedia extends StatefulWidget {
  final List<String> urls;
  final String heroPrefix;

  const CarouselMedia({
    super.key,
    required this.urls,
    required this.heroPrefix,
  });

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
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
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
            final heroTag = "${widget.heroPrefix}_img_$url";
            return GestureDetector(
              onTap: () => _openFullscreen(i),
              child: Hero(
                tag: heroTag,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  loadingBuilder: (c, w, p) => (p == null)
                      ? w
                      : const Center(child: CircularProgressIndicator()),
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
                final heroTag = "${widget.heroPrefix}_img_$url";
                return Center(
                  child: Hero(
                    tag: heroTag,
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        loadingBuilder: (c, w, p) =>
                        (p == null) ? w : const CircularProgressIndicator(),
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image,
                          color: Colors.white70,
                          size: 60,
                        ),
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

/// ====================================================
/// ONE VIDEO PLAY AT A TIME
/// ====================================================
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

/// ====================================================
/// VIDEO (NO AUTOPLAY + THUMB + HLS)
/// ====================================================
class VideoBox extends StatefulWidget {
  final String url;
  final String? hlsUrl;
  final String? thumbnailUrl;
  final double height;

  const VideoBox({
    super.key,
    required this.url,
    this.hlsUrl,
    this.thumbnailUrl,
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
    _loadToken();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeTimer?.cancel();
    _FeedVideoHub.release(_pauseMe);
    _disposeController();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pauseMe();
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

    if (_ctrl == null) await _ensureInit();

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

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: ValueKey("profile_video_${_effectiveUrl.hashCode}"),
      onVisibilityChanged: (info) {
        if (info.visibleFraction < 0.15) {
          _pauseMe();
          _scheduleDispose();
        } else {
          _cancelDispose();
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
        loadingBuilder: (c, w, p) =>
        (p == null)
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
