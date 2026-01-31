import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:troonky_link/services/comments_api.dart';

class ReelCommentsSheet extends StatefulWidget {
  final int reelId;
  final int initialCount;

  const ReelCommentsSheet({
    super.key,
    required this.reelId,
    this.initialCount = 0,
  });

  @override
  State<ReelCommentsSheet> createState() => _ReelCommentsSheetState();
}

class _ReelCommentsSheetState extends State<ReelCommentsSheet> {
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  final List<Map<String, dynamic>> _comments = [];

  bool _loading = true;
  bool _sending = false;
  bool _actionBusy = false;
  String? _error;

  late int _commentCount;
  String? _selfUserId;

  final Color primaryColor = const Color(0xFF333399);

  @override
  void initState() {
    super.initState();
    _commentCount = widget.initialCount;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadSelfUserId();
    await _loadComments();
  }

  Future<void> _loadSelfUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.get('userId');
      if (v == null) return;
      _selfUserId = v.toString().trim();
    } catch (_) {}
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // =========================
  // Helpers (server mismatch safe)
  // =========================
  String _pickText(Map m) {
    final v = m["text"] ?? m["comment"] ?? m["content"] ?? m["message"] ?? "";
    return v.toString();
  }

  String _pickName(Map m) {
    final v = m["user_name"] ?? m["name"] ?? m["username"] ?? "User";
    final s = v.toString().trim();
    return s.isEmpty ? "User" : s;
  }

  String? _pickAvatar(Map m) {
    final v = m["user_profile_pic"] ?? m["profile_pic"] ?? m["avatar"] ?? m["photo"];
    final s = v?.toString().trim();
    if (s == null || s.isEmpty) return null;
    return s;
  }

  String _pickUserId(Map m) {
    final v = m["user_id"] ?? m["uid"] ?? m["userId"] ?? "";
    return v.toString().trim();
  }

  bool _isPinned(Map m) {
    final v = m["is_pinned"] ?? m["pinned"];
    if (v is bool) return v;
    if (v is int) return v == 1;
    final s = v?.toString().trim();
    return s == "1" || s?.toLowerCase() == "true";
  }

  // ✅ backend gives "uploads/xx.jpg" so make it full URL safely
  String? _toPublicUrl(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith("http://") || s.startsWith("https://")) return s;

    final clean = s.startsWith("/") ? s.substring(1) : s;
    return "https://adminapi.troonky.in/$clean";
  }

  int _asInt(dynamic v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  void _close() => Navigator.pop(context, _commentCount);

  // =========================
  // LOAD COMMENTS
  // =========================
  Future<void> _loadComments() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await CommentsAPI.fetchComments(
        reelId: widget.reelId,
        page: 1,
        limit: 50,
      );

      final dynamic raw = res["comments"];
      final List<Map<String, dynamic>> list = (raw is List)
          ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];

      // pinned first
      list.sort((a, b) {
        final ap = _isPinned(a) ? 1 : 0;
        final bp = _isPinned(b) ? 1 : 0;
        return bp.compareTo(ap);
      });

      final totalFromServer = _asInt(
        res["total"] ?? res["total_comments"] ?? res["count"] ?? res["comment_count"],
        fallback: 0,
      );

      if (!mounted) return;
      setState(() {
        _comments
          ..clear()
          ..addAll(list);

        if (totalFromServer > 0) {
          _commentCount = totalFromServer;
        } else {
          // fallback: keep the maximum between initial & loaded
          if (list.length > _commentCount) _commentCount = list.length;
        }

        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Something went wrong.";
        _loading = false;
      });
    }
  }

  // =========================
  // SEND COMMENT (optimistic + reload)
  // =========================
  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    final tempId = DateTime.now().millisecondsSinceEpoch;
    final optimistic = <String, dynamic>{
      "id": "temp_$tempId",
      "text": text,
      "user_name": "You",
      "user_profile_pic": null,
      "user_id": _selfUserId,
      "created_at": DateTime.now().toIso8601String(),
      "is_pinned": 0,
      "_optimistic": true,
    };

    setState(() {
      _sending = true;
      _comments.insert(0, optimistic);
      _commentCount = (_commentCount + 1).clamp(0, 1 << 30);
    });

    _textCtrl.clear();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });

    try {
      final ok = await CommentsAPI.addComment(
        reelId: widget.reelId,
        text: text,
      );

      if (!mounted) return;

      if (!ok) {
        setState(() {
          _comments.removeWhere((x) => x["id"] == "temp_$tempId");
          _commentCount = (_commentCount - 1).clamp(0, 1 << 30);
        });
      } else {
        await _loadComments();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _comments.removeWhere((x) => x["id"] == "temp_$tempId");
        _commentCount = (_commentCount - 1).clamp(0, 1 << 30);
      });
    } finally {
      if (!mounted) return;
      setState(() => _sending = false);
    }
  }

  // =========================
  // PIN / DELETE
  // =========================
  Future<void> _pinComment(Map<String, dynamic> c) async {
    if (_actionBusy) return;
    final id = c["id"]?.toString().trim();
    if (id == null || id.isEmpty || id.startsWith("temp_")) return;

    setState(() => _actionBusy = true);
    try {
      final ok = await CommentsAPI.pinComment(commentId: id);
      if (ok && mounted) {
        await _loadComments();
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _deleteComment(Map<String, dynamic> c) async {
    if (_actionBusy) return;
    final id = c["id"]?.toString().trim();
    if (id == null || id.isEmpty || id.startsWith("temp_")) return;

    setState(() => _actionBusy = true);

    // optimistic remove
    final backup = Map<String, dynamic>.from(c);
    setState(() {
      _comments.removeWhere((x) => x["id"].toString() == id);
      _commentCount = (_commentCount - 1).clamp(0, 1 << 30);
    });

    try {
      final ok = await CommentsAPI.deleteComment(commentId: id);
      if (!ok && mounted) {
        // rollback
        setState(() {
          _comments.insert(0, backup);
          _commentCount = (_commentCount + 1).clamp(0, 1 << 30);
        });
      } else if (mounted) {
        // refresh to be accurate
        await _loadComments();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _comments.insert(0, backup);
        _commentCount = (_commentCount + 1).clamp(0, 1 << 30);
      });
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  // =========================
  // OPEN USER PROFILE (keep your existing routing)
  // =========================
  void _openUserProfile(Map<String, dynamic> c) {
    final userId = _pickUserId(c);
    if (userId.isEmpty) return;

    Navigator.pushNamed(
      context,
      "/profile",
      arguments: {
        "userId": userId,
        "userType": (c["user_type"] ?? "user").toString(),
      },
    );
  }

  void _openActions(Map<String, dynamic> c) {
    final isMine = _selfUserId != null && _selfUserId == _pickUserId(c);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: Text(
                "Pin comment",
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                "Backend: POST /api/reel-comments/comment/:id/pin",
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _pinComment(c);
              },
            ),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(
                  "Delete comment",
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.red),
                ),
                subtitle: Text(
                  "Backend: DELETE /api/reel-comments/comment/:id",
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _deleteComment(c);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _close();
      },
      child: SafeArea(
        child: Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              _dragHandle(),
              const SizedBox(height: 8),
              _title(),
              const Divider(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? _errorView()
                    : _comments.isEmpty
                    ? _empty()
                    : RefreshIndicator(
                  onRefresh: _loadComments,
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _comments.length,
                    itemBuilder: (_, i) => _commentItem(_comments[i]),
                  ),
                ),
              ),
              const Divider(height: 1),
              _inputBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dragHandle() => Container(
    width: 42,
    height: 4,
    decoration: BoxDecoration(
      color: Colors.grey.shade400,
      borderRadius: BorderRadius.circular(3),
    ),
  );

  Widget _title() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        "Comments ($_commentCount)",
        style: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      IconButton(
        onPressed: _close,
        icon: const Icon(Icons.close),
      ),
    ],
  );

  Widget _empty() => Center(
    child: Text(
      "Be the first to comment 👋",
      style: GoogleFonts.poppins(color: Colors.grey),
    ),
  );

  Widget _errorView() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(_error ?? "", style: GoogleFonts.poppins(color: Colors.red)),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: _loadComments,
          child: const Text("Retry"),
        ),
      ],
    ),
  );

  Widget _commentItem(Map<String, dynamic> c) {
    final avatarRaw = _pickAvatar(c);
    final avatarUrl = _toPublicUrl(avatarRaw);

    final name = _pickName(c);
    final text = _pickText(c);
    final isOptimistic = c["_optimistic"] == true;
    final pinned = _isPinned(c);

    return InkWell(
      onLongPress: () => _openActions(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Opacity(
          opacity: isOptimistic ? 0.75 : 1,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _openUserProfile(c),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.grey.shade300,
                  backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl == null
                      ? const Icon(Icons.person, size: 18, color: Colors.white)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => _openUserProfile(c),
                          child: Text(
                            name,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (pinned)
                          Row(
                            children: [
                              Icon(Icons.push_pin, size: 14, color: primaryColor),
                              const SizedBox(width: 4),
                              Text(
                                "Pinned",
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: primaryColor,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      text,
                      style: GoogleFonts.poppins(fontSize: 14),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _openActions(c),
                icon: const Icon(Icons.more_vert, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputBar() => Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.of(context).viewInsets.bottom,
      top: 6,
    ),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _textCtrl,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              hintText: "Add a comment...",
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: _sending
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : Icon(Icons.send, color: primaryColor),
          onPressed: _sending ? null : _send,
        ),
      ],
    ),
  );
}
