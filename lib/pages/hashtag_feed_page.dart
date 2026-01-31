import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:troonky_link/helpers/block_helper.dart';
import 'package:troonky_link/pages/profile/profile_page.dart';
import 'package:troonky_link/services/feed_api.dart';

import 'feed_page.dart'; // ✅ uses your updated PostCard

const Color troonkyColor = Color(0xFF333399);

class HashtagFeedPage extends StatefulWidget {
  final String hashtag;

  const HashtagFeedPage({
    super.key,
    required this.hashtag,
  });

  @override
  State<HashtagFeedPage> createState() => _HashtagFeedPageState();
}

class _HashtagFeedPageState extends State<HashtagFeedPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _posts = [];

  String? _myUserId; // ✅ to detect isMine

  @override
  void initState() {
    super.initState();
    BlockHelper.init();
    _load();
  }

  // ---------------- helpers ----------------
  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? "") ?? 0;
  }

  static List<dynamic> _mediaList(Map<String, dynamic> post) {
    final m = post["media_urls"];
    if (m is List) return m;
    final single = post["media_url"] ?? post["mediaFile"] ?? post["media"];
    if (single != null && single.toString().trim().isNotEmpty) return [single];
    return [];
  }

  static String _getUserId(Map<String, dynamic> post) {
    return (post["user_id"] ?? post["userId"] ?? post["uid"] ?? "").toString().trim();
  }

  Future<void> _loadMyUserIdOnce() async {
    if (_myUserId != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      // ✅ adjust keys as per your app
      _myUserId = (prefs.getString("user_id") ??
          prefs.getString("uid") ??
          prefs.getString("userId") ??
          prefs.getString("id"))
          ?.toString()
          .trim();
    } catch (_) {
      _myUserId = null;
    }
  }

  bool _isMine(Map<String, dynamic> post) {
    final me = (_myUserId ?? "").trim();
    if (me.isEmpty) return false;
    final uid = _getUserId(post);
    return uid.isNotEmpty && uid == me;
  }

  bool _isLiked(Map<String, dynamic> post) {
    return (post["is_liked"] == true) || (post["liked"] == true);
  }

  // ---------------- load ----------------
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    await _loadMyUserIdOnce();

    try {
      final data = await FeedAPI.fetchByHashtag(widget.hashtag);

      final filtered = BlockHelper.filterBlockedUsers(data);

      if (!mounted) return;
      setState(() {
        _posts = filtered;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "Something went wrong";
        _loading = false;
      });
    }
  }

  // ---------------- actions ----------------
  void _sharePost(Map<String, dynamic> post) {
    final text = (post["description"] ?? "").toString();
    final media = _mediaList(post);
    final first = media.isNotEmpty ? media.first.toString() : (post["media_url"] ?? "").toString();
    final url = FeedAPI.toPublicUrl(first);

    Share.share("🔥 #${widget.hashtag.replaceAll("#", "")}\n\n$text\n\n$url");
  }

  Future<void> _openComments(Map<String, dynamic> post) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Comments temporarily disabled")),
    );
  }

  Future<void> _toggleLike(Map<String, dynamic> post) async {
    final id = int.tryParse((post["id"] ?? "").toString());
    if (id == null) return;

    HapticFeedback.lightImpact();

    final oldLiked = _isLiked(post);
    final oldCount = _toInt(post["likes"] ?? post["likes_count"] ?? post["like_count"] ?? 0);

    // optimistic
    if (mounted) {
      setState(() {
        final nextLiked = !oldLiked;
        post["is_liked"] = nextLiked;
        post["liked"] = nextLiked;

        final nextCount = nextLiked ? (oldCount + 1) : (oldCount - 1);
        final safe = nextCount < 0 ? 0 : nextCount;

        post["likes"] = safe;
        post["likes_count"] = safe;
        post["like_count"] = safe;
      });
    }

    final res = await FeedAPI.toggleLike(id, currentlyLiked: oldLiked);
    if (!mounted) return;

    final liked = res["liked"];
    final likes = res["likes"];

    setState(() {
      if (liked is bool) {
        post["is_liked"] = liked;
        post["liked"] = liked;
      }
      if (likes is int) {
        post["likes"] = likes;
        post["likes_count"] = likes;
        post["like_count"] = likes;
      } else if (likes is String) {
        final n = int.tryParse(likes);
        if (n != null) {
          post["likes"] = n;
          post["likes_count"] = n;
          post["like_count"] = n;
        }
      }
    });
  }

  void _onHashtagTap(String tag) {
    final clean = tag.replaceAll("#", "").trim();
    if (clean.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HashtagFeedPage(hashtag: clean)),
    );
  }

  Future<void> _onMentionTap(String username) async {
    final clean = username.replaceAll("@", "").trim();
    if (clean.isEmpty) return;

    final user = await FeedAPI.fetchUserByUsername(clean);
    final userId = user?["id"] ?? user?["user_id"];

    if (!mounted) return;

    if (userId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProfilePage(userId: userId.toString())),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("User @$clean not found")),
      );
    }
  }

  // ---------------- report / block / delete ----------------
  Future<void> _reportPost(Map<String, dynamic> post) async {
    final postId = int.tryParse((post["id"] ?? "").toString()) ?? 0;
    if (postId <= 0) return;

    final reason = await _pickReportReason();
    if (reason == null) return;

    try {
      await FeedAPI.reportPost(postId: postId, reason: reason);

      if (!mounted) return;
      setState(() => _posts.removeWhere((p) => (p["id"] ?? "").toString() == postId.toString()));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Reported ✅ Post removed from feed.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Report failed: $e")),
      );
    }
  }

  Future<String?> _pickReportReason() async {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        const items = <Map<String, String>>[
          {"k": "spam", "t": "Spam"},
          {"k": "nudity", "t": "Nudity / Sexual"},
          {"k": "harassment", "t": "Harassment"},
          {"k": "violence", "t": "Violence"},
          {"k": "hate", "t": "Hate Speech"},
          {"k": "false_info", "t": "False Information"},
          {"k": "other", "t": "Other"},
        ];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              const Text("Report reason",
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              ...items.map(
                    (m) => ListTile(
                  title: Text(m["t"]!),
                  onTap: () => Navigator.pop(context, m["k"]),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _blockUser(Map<String, dynamic> post) async {
    final userId = _getUserId(post);
    if (userId.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Block user?"),
        content: const Text("You won’t see this user’s posts anymore."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Block")),
        ],
      ),
    );

    if (ok != true) return;

    final uidInt = int.tryParse(userId) ?? 0;
    if (uidInt <= 0) return;

    await BlockHelper.blockUser(uidInt);

    if (!mounted) return;
    setState(() {
      _posts.removeWhere((p) => (int.tryParse(_getUserId(p)) ?? 0) == uidInt);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("User blocked ✅")),
    );
  }

  Future<void> _deletePost(Map<String, dynamic> post) async {
    final postId = int.tryParse((post["id"] ?? "").toString()) ?? 0;
    if (postId <= 0) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete post?"),
        content: const Text("This post will be removed permanently."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete")),
        ],
      ),
    );

    if (ok != true) return;

    // optimistic remove
    if (mounted) {
      setState(() => _posts.removeWhere((p) => (p["id"] ?? "").toString() == postId.toString()));
    }

    final res = await FeedAPI.deletePost(postId);
    if (!mounted) return;

    if (res["ok"] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Deleted ✅")),
      );
      return;
    }

    // rollback by reload
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res["message"]?.toString() ?? "Delete failed")),
    );
    _load();
  }

  void _openReactions(Map<String, dynamic> post) {
    showModalBottomSheet(
      context: context,
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
              children: const [
                Text("Reactions",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                SizedBox(height: 12),
                Text("Reactions list FeedPage থেকেই খুলবে (PostCard onOpenReactions)."),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final tagTitle = widget.hashtag.replaceAll("#", "");

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text("#$tagTitle"),
        backgroundColor: troonkyColor,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: _load, child: const Text("Retry"))
          ],
        ),
      )
          : (_posts.isEmpty)
          ? const Center(
        child: Text("No posts found for this hashtag",
            style: TextStyle(fontSize: 16)),
      )
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 20),
          itemCount: _posts.length,
          itemBuilder: (_, i) {
            final post = _posts[i];
            final pid = (post["id"] ?? "").toString().trim();

            return PostCard(
              post: post,
              isLiked: _isLiked(post),

              // ✅ REQUIRED (new PostCard params)
              heroPrefix: "hashtag_${tagTitle}_", // unique prefix
              isMine: _isMine(post),
              onDelete: () => _deletePost(post),

              onLike: () => _toggleLike(post),
              onComment: () => _openComments(post),
              onShare: () => _sharePost(post),

              onHashtagTap: _onHashtagTap,
              onMentionTap: _onMentionTap,

              onProfile: () {
                final uid = _getUserId(post);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfilePage(userId: uid),
                  ),
                );
              },

              onReport: () => _reportPost(post),
              onBlock: () => _blockUser(post),
              onOpenReactions: () => _openReactions(post),
            );
          },
        ),
      ),
    );
  }
}
