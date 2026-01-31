import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:troonky_link/helpers/block_helper.dart';
import 'package:troonky_link/pages/profile/profile_page.dart';
import 'package:troonky_link/pages/post_comments_sheet.dart';
import 'package:troonky_link/pages/business_profile/business_profile_page.dart';
import 'package:troonky_link/services/feed_api.dart';

// ✅ FIX: import your controller (this fixes "Undefined class BusinessProfileController")
import 'package:troonky_link/pages/business_profile/controllers/business_profile_controller.dart';

// ✅ reuse your PostCard + ReactionsSheet from feed_page.dart
// যদি path আলাদা হয়: ../../feed_page.dart বা ../feed_page.dart adjust করো
import '../../feed_page.dart';

class BPPostsTab extends StatefulWidget {
  final BusinessProfileController ctrl;
  const BPPostsTab({super.key, required this.ctrl});

  @override
  State<BPPostsTab> createState() => _BPPostsTabState();
}

class _BPPostsTabState extends State<BPPostsTab> {
  Timer? _debounce;

  // ✅ unique hero prefix to avoid collisions between tabs/pages
  late final String _heroPrefix =
      "bp_${widget.ctrl.businessId}_${DateTime.now().millisecondsSinceEpoch}";

  @override
  void initState() {
    super.initState();
    BlockHelper.init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _debounce = null;
    super.dispose();
  }

  // -------------------------- Media helpers --------------------------

  String? _pickUrl(dynamic raw) {
    if (raw == null) return null;

    if (raw is Map) {
      final v = raw["url"] ?? raw["path"] ?? raw["image"] ?? raw["src"];
      return _pickUrl(v);
    }

    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    return FeedAPI.toPublicUrl(s);
  }

  bool _isVideoUrl(String s) {
    final u = s.toLowerCase();
    return u.contains(".mp4") ||
        u.contains(".mov") ||
        u.contains(".m4v") ||
        u.contains(".webm") ||
        u.contains(".m3u8");
  }

  List<String> _collectMediaUrls(Map p) {
    final out = <String>[];

    void addOne(dynamic v) {
      final u = _pickUrl(v);
      if (u != null && u.isNotEmpty && !out.contains(u)) out.add(u);
    }

    const singleKeys = [
      "media_url",
      "media",
      "image",
      "image_url",
      "post_image",
      "thumbnail",
      "thumb",
      "video_thumb",
      "poster",
      "cover",
      "file",
      "url",
    ];

    for (final k in singleKeys) {
      addOne(p[k]);
    }

    final mediaUrls = p["media_urls"];
    if (mediaUrls is List) {
      for (final e in mediaUrls) {
        addOne(e);
        if (out.length >= 12) break;
      }
    }

    final images = p["images"];
    if (images is List) {
      for (final e in images) {
        addOne(e);
        if (out.length >= 12) break;
      }
    }

    final data = p["data"];
    if (data is Map) {
      addOne(data["media_url"]);
      addOne(data["image"]);
      addOne(data["thumbnail"]);
      final l = data["media_urls"];
      if (l is List) {
        for (final e in l) {
          addOne(e);
          if (out.length >= 12) break;
        }
      }
    }

    return out;
  }

  String? _thumbUrl(Map p) {
    const keys = [
      "video_thumb",
      "thumb_url",
      "thumbnail_url",
      "thumbnail",
      "poster",
      "poster_url",
    ];
    for (final k in keys) {
      final u = _pickUrl(p[k]);
      if (u != null && u.isNotEmpty) return u;
    }
    return null;
  }

  bool _isVideoPost(Map p) {
    if (p["is_video"] == true) return true;

    final list = _collectMediaUrls(p);
    if (list.length == 1 && _isVideoUrl(list.first)) return true;

    final hls = (p["video_hls_url"] ??
        p["hls_url"] ??
        p["video_hls"] ??
        p["stream_url"] ??
        p["m3u8_url"] ??
        "")
        .toString()
        .trim();

    if (hls.isNotEmpty && _isVideoUrl(hls)) return true;
    return false;
  }

  // -------------------------- Paging --------------------------

  void _loadNextSafe() {
    final pager = widget.ctrl.postsPager;
    if (!pager.hasMore) return;
    if (pager.loadingFirst || pager.loadingNext) return;

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      final p = widget.ctrl.postsPager;
      if (p.hasMore && !p.loadingFirst && !p.loadingNext) {
        p.loadNext();
      }
    });
  }

  Future<void> _refresh() async => widget.ctrl.refresh();

  // ✅ Instagram behavior: grid tap -> open FEED style viewer (PostCard)
  void _openAsFeed(int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BusinessPostFeedViewPage(
          posts: widget.ctrl.postsPager.items
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
          initialIndex: initialIndex,
          heroPrefix: _heroPrefix,
          businessId: widget.ctrl.businessId,
        ),
      ),
    );
  }

  // -------------------------- UI --------------------------

  @override
  Widget build(BuildContext context) {
    final pager = widget.ctrl.postsPager;

    if (pager.loadingFirst && pager.items.isEmpty) {
      return const _GridSkeleton();
    }

    if (pager.error.isNotEmpty && pager.items.isEmpty) {
      return _ErrorState(message: pager.error, onRetry: () => pager.loadFirst());
    }

    if (pager.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 90),
            Center(
              child: Text(
                "No posts yet",
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 240) {
            _loadNextSafe();
          }
          return false;
        },
        child: GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(1),
          cacheExtent: 1200,
          itemCount: pager.items.length + (pager.hasMore ? 1 : 0),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 1,
            crossAxisSpacing: 1,
            childAspectRatio: 1,
          ),
          itemBuilder: (_, index) {
            if (index >= pager.items.length) {
              return Center(
                child: pager.loadingNext
                    ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : IconButton(
                  onPressed: _loadNextSafe,
                  icon: const Icon(Icons.expand_more),
                ),
              );
            }

            final post = pager.items[index];
            final media = _collectMediaUrls(post);
            final isVideo = _isVideoPost(post);
            final thumb = _thumbUrl(post);

            final String? gridUrl = isVideo
                ? (thumb ?? (media.isNotEmpty ? media.first : null))
                : (media.isNotEmpty ? media.first : null);

            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                _openAsFeed(index);
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: Colors.black12,
                    child: (gridUrl != null && gridUrl.isNotEmpty)
                        ? Image.network(
                      gridUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (c, w, p) {
                        if (p == null) return w;
                        return const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image,
                            size: 34, color: Colors.white70),
                      ),
                    )
                        : const Center(
                      child: Icon(Icons.photo,
                          size: 38, color: Colors.white70),
                    ),
                  ),
                  if (media.length > 1 && !isVideo)
                    const Positioned(
                      top: 6,
                      right: 6,
                      child: Icon(Icons.collections,
                          color: Colors.white70, size: 18),
                    ),
                  if (isVideo)
                    const Positioned(
                      top: 6,
                      right: 6,
                      child: Icon(Icons.videocam,
                          color: Colors.white70, size: 18),
                    ),
                  if (isVideo)
                    const Center(
                      child: Icon(Icons.play_circle,
                          size: 42, color: Colors.white70),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/* =======================================================================
   ✅ FEED STYLE VIEWER: grid tap -> open PostCard page (Instagram behavior)
   ======================================================================= */

class BusinessPostFeedViewPage extends StatefulWidget {
  final List<Map<String, dynamic>> posts;
  final int initialIndex;
  final String heroPrefix;
  final String businessId;

  const BusinessPostFeedViewPage({
    super.key,
    required this.posts,
    required this.initialIndex,
    required this.heroPrefix,
    required this.businessId,
  });

  @override
  State<BusinessPostFeedViewPage> createState() => _BusinessPostFeedViewPageState();
}

class _BusinessPostFeedViewPageState extends State<BusinessPostFeedViewPage> {
  late final PageController _pc;
  int _idx = 0;

  final Set<String> _liked = <String>{};
  String? _authToken;
  bool _tokenLoaded = false;

  @override
  void initState() {
    super.initState();
    _idx = widget.initialIndex.clamp(0, widget.posts.length - 1);
    _pc = PageController(initialPage: _idx);
    _loadTokenOnce();
    _seedLiked();
  }

  Future<void> _loadTokenOnce() async {
    if (_tokenLoaded) return;
    _tokenLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final t = prefs.getString("token")?.trim();
      _authToken = (t == null || t.isEmpty) ? null : t;
    } catch (_) {
      _authToken = null;
    }
    if (mounted) setState(() {});
  }

  void _seedLiked() {
    for (final p in widget.posts) {
      final id = (p["id"] ?? "").toString();
      final serverLiked = (p["is_liked"] == true) || (p["liked"] == true);
      if (id.isNotEmpty && serverLiked) _liked.add(id);
    }
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? "") ?? 0;
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  // ---------------- actions ----------------

  Future<void> _toggleLike(Map<String, dynamic> post) async {
    final idStr = (post["id"] ?? "").toString();
    final postId = int.tryParse(idStr) ?? 0;
    if (postId <= 0) return;

    HapticFeedback.lightImpact();

    final wasLiked = _liked.contains(idStr);
    final curLikes = _toInt(post["likes_count"] ?? post["like_count"] ?? post["likes"] ?? 0);

    // optimistic
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

    final res = await FeedAPI.toggleLike(postId, currentlyLiked: wasLiked);
    if (!mounted) return;

    if (res["ok"] != true) {
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

      if (apiLikes is int) {
        post["likes_count"] = apiLikes;
        post["like_count"] = apiLikes;
        post["likes"] = apiLikes;
      } else if (apiLikes is String) {
        final parsed = int.tryParse(apiLikes) ?? curLikes;
        post["likes_count"] = parsed;
        post["like_count"] = parsed;
        post["likes"] = parsed;
      }
    });
  }

  Future<void> _openComments(Map<String, dynamic> post) async {
    final postId = int.tryParse((post["id"] ?? "").toString()) ?? 0;
    if (postId <= 0) return;

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
            post["comments_count"] ?? post["comment_count"] ?? post["comments"] ?? 0,
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
    final text = (post["description"] ?? "").toString();
    final media = FeedAPI.rawMediaList(post);
    final firstUrl = (media.isNotEmpty) ? FeedAPI.toPublicUrl(media.first.toString()) : "";

    await Share.share("🔥 Troonky Post\n\n$text\n\n$firstUrl");

    final postId = int.tryParse((post["id"] ?? "").toString()) ?? 0;
    if (postId <= 0) return;

    final int newShares = await FeedAPI.sharePost(postId);
    if (!mounted) return;

    setState(() {
      final cur = _toInt(post["shares_count"] ?? post["share_count"] ?? 0);
      final next = (newShares > 0) ? newShares : (cur + 1);
      post["shares_count"] = next;
      post["share_count"] = next;
    });
  }

  Future<void> _reportPost(Map<String, dynamic> post) async {
    final postId = int.tryParse((post["id"] ?? "").toString()) ?? 0;
    if (postId <= 0) return;

    const reasons = ["spam", "harassment", "hate", "nudity", "violence", "other"];
    final reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            const Text("Report Reason", style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            ...reasons.map((r) => ListTile(
              leading: const Icon(Icons.flag),
              title: Text(r),
              onTap: () => Navigator.pop(context, r),
            )),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (reason == null) return;

    // optimistic remove (hide)
    final idStr = (post["id"] ?? "").toString();
    setState(() {
      widget.posts.removeWhere((p) => (p["id"] ?? "").toString() == idStr);
    });

    final res = await FeedAPI.reportPostById(postId, reason: reason);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text((res["message"] ?? "Reported ✅").toString())),
    );
  }

  Future<void> _blockUser(Map<String, dynamic> post) async {
    final userId = (post["user_id"] ?? post["userId"] ?? post["uid"] ?? "").toString().trim();
    if (userId.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Block User"),
        content: const Text("You will no longer see this user's posts."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Block")),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await BlockHelper.blockUser(int.tryParse(userId) ?? 0);
    } catch (_) {}

    setState(() {
      widget.posts.removeWhere((p) {
        final uid = (p["user_id"] ?? p["userId"] ?? p["uid"] ?? "").toString().trim();
        return uid == userId;
      });
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("User blocked ✅")),
    );
  }

  Future<void> _openReactions(Map<String, dynamic> post) async {
    final postId = int.tryParse((post["id"] ?? "").toString()) ?? 0;
    if (postId <= 0) return;

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

  void _onProfile(Map<String, dynamic> post) {
    final userType = (post["user_type"] ?? "").toString().toLowerCase();
    final shopId = (post["shop_id"] ?? post["shopId"] ?? "").toString();

    if (userType == "business" && shopId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BusinessProfilePage(businessId: shopId, isOwner: false),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProfilePage(userId: (post["user_id"] ?? "").toString()),
        ),
      );
    }
  }

  void _onHashtagTap(String tag) => HapticFeedback.selectionClick();
  void _onMentionTap(String username) => HapticFeedback.selectionClick();

  bool _isMine(Map<String, dynamic> post) {
    // ✅ business profile view: treat as owner only if controller.isOwner true
    // (optional logic: compare shop_id with widget.businessId)
    if (widget.businessId.trim().isEmpty) return false;
    if (widget.businessId == (post["shop_id"] ?? post["shopId"] ?? "").toString()) {
      return widget.businessId == widget.businessId; // true
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.posts.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Posts")),
        body: const Center(child: Text("No posts")),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text("Posts"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.6,
      ),
      body: PageView.builder(
        controller: _pc,
        scrollDirection: Axis.vertical, // ✅ Instagram-like
        onPageChanged: (i) => setState(() => _idx = i),
        itemCount: widget.posts.length,
        itemBuilder: (_, i) {
          final post = widget.posts[i];
          final id = (post["id"] ?? "").toString();

          final bool isMine = widget.businessId.isNotEmpty &&
              ((post["shop_id"] ?? post["shopId"] ?? "").toString() == widget.businessId);

          return SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: PostCard(
                post: post,
                isLiked: _liked.contains(id),
                authToken: _authToken,

                // ✅ REQUIRED params (your earlier screenshot errors)
                heroPrefix: widget.heroPrefix,
                isMine: isMine,
                onDelete: () async {
                  if (!isMine) return;
                  final postId = int.tryParse(id) ?? 0;
                  if (postId <= 0) return;
                  final res = await FeedAPI.deletePost(postId);
                  if (!mounted) return;
                  if (res["ok"] == true || res["success"] == true) {
                    setState(() {
                      widget.posts.removeAt(i);
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Post deleted ✅")),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text((res["message"] ?? "Delete failed").toString())),
                    );
                  }
                },

                onProfile: () => _onProfile(post),
                onLike: () => _toggleLike(post),
                onComment: () => _openComments(post),
                onShare: () => _sharePost(post),
                onReport: () => _reportPost(post),
                onBlock: () => _blockUser(post),
                onHashtagTap: _onHashtagTap,
                onMentionTap: _onMentionTap,
                onOpenReactions: () => _openReactions(post),
              ),
            ),
          );
        },
      ),
    );
  }
}

/* ---------------------- UI Helpers ---------------------- */

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(1),
      itemCount: 18,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 1,
        crossAxisSpacing: 1,
        childAspectRatio: 1,
      ),
      itemBuilder: (_, __) => Container(
        color: Colors.black12,
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44, color: Colors.redAccent),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text("Retry")),
          ],
        ),
      ),
    );
  }
}
