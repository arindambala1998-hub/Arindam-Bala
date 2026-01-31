import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:troonky_link/services/feed_api.dart'; // ✅ toPublicUrl reuse
import 'package:troonky_link/pages/profile/profile_page.dart'; // ✅ open profile

// =========================
// ✅ Troonky Official Theme
// =========================
const Color troonkyColor = Color(0xFF333399); // brand base
const Color troonkyGradA = Color(0xFF7C2AE8); // purple
const Color troonkyGradB = Color(0xFFFF2DAA); // pink

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

class PostCommentsSheet extends StatefulWidget {
  final int postId;
  final int initialCount;

  const PostCommentsSheet({
    super.key,
    required this.postId,
    required this.initialCount,
  });

  @override
  State<PostCommentsSheet> createState() => _PostCommentsSheetState();
}

class _PostCommentsSheetState extends State<PostCommentsSheet> {
  final _ctl = TextEditingController();
  bool _loading = true;
  bool _sending = false;

  List<Map<String, dynamic>> _items = [];
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _count = widget.initialCount;
    _load();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<String?> _token() async {
    final sp = await SharedPreferences.getInstance();
    final t = sp.getString("token");
    if (t == null) return null;
    final s = t.trim();
    return s.isEmpty ? null : s;
  }

  dynamic _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? "") ?? 0;
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final url = Uri.parse("https://adminapi.troonky.in/api/comments/${widget.postId}");

    try {
      // ✅ GET is public (your backend)
      final res = await http.get(url, headers: {"Accept": "application/json"});
      if (res.statusCode != 200) {
        setState(() {
          _loading = false;
          _items = [];
        });
        return;
      }

      final decoded = _tryDecode(res.body);
      List list = [];

      if (decoded is List) list = decoded;
      if (decoded is Map) {
        final data = (decoded["data"] is Map)
            ? Map<String, dynamic>.from(decoded["data"])
            : <String, dynamic>{};

        dynamic raw = decoded["items"] ?? decoded["comments"] ?? decoded["data"];
        if (raw is Map) {
          raw = raw["items"] ?? raw["comments"];
        }
        raw ??= data["items"] ?? data["comments"] ?? <dynamic>[];

        list = (raw is List) ? raw : <dynamic>[];

        final c = decoded["count"] ?? decoded["total"] ?? data["count"] ?? data["total"];
        if (c != null) _count = _toInt(c);
      }

      setState(() {
        _items = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _items = [];
      });
    }
  }

  Future<void> _send() async {
    final text = _ctl.text.trim();
    if (text.isEmpty || _sending) return;

    final token = await _token();
    if (token == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please login again")),
      );
      return;
    }

    setState(() => _sending = true);

    final url = Uri.parse("https://adminapi.troonky.in/api/comments/${widget.postId}");

    try {
      final res = await http.post(
        url,
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode({"text": text}),
      );

      final decoded = _tryDecode(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        _ctl.clear();

        // ✅ server sometimes returns updated count
        int? serverCount;
        if (decoded is Map) {
          final data = (decoded["data"] is Map)
              ? Map<String, dynamic>.from(decoded["data"])
              : <String, dynamic>{};
          final v = decoded["comments_count"] ?? decoded["comment_count"] ?? decoded["count"] ??
              data["comments_count"] ?? data["comment_count"] ?? data["count"];
          serverCount = v != null ? _toInt(v) : null;
        }

        setState(() {
          _count = serverCount ?? (_count + 1);
          _sending = false;
        });

        await _load();
        return;
      }

      final msg = (decoded is Map && decoded["error"] != null)
          ? decoded["error"].toString()
          : (decoded is Map && decoded["message"] != null)
          ? decoded["message"].toString()
          : "Comment failed (${res.statusCode})";

      setState(() => _sending = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      setState(() => _sending = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Comment failed")),
      );
    }
  }

  // ✅ open profile (from comment object)
  void _openUserProfile(Map<String, dynamic> c) {
    final uid = (c["user_id"] ?? c["userId"] ?? c["uid"]);
    final userId = uid?.toString() ?? "";
    if (userId.trim().isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProfilePage(userId: userId)),
    );
  }

  Widget _avatarFromComment(Map<String, dynamic> c) {
    final pic = (c["user_profile_pic"] ??
        c["profile_pic"] ??
        c["profilePic"] ??
        c["avatar"] ??
        c["photo"])
        ?.toString()
        .trim();

    final hasPic = pic != null && pic.isNotEmpty;
    final url = hasPic ? FeedAPI.toPublicUrl(pic) : "";

    if (hasPic) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: Colors.grey.shade200,
        backgroundImage: NetworkImage(url),
        onBackgroundImageError: (_, __) {},
      );
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: troonkyGradient(),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.person, color: Colors.white, size: 20),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.72,
          child: Column(
            children: [
              const SizedBox(height: 10),

              // ✅ Gradient header pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  gradient: troonkyGradient(),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  "Comments ($_count)",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                ),
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),

              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _items.isEmpty
                    ? const Center(child: Text("No comments yet"))
                    : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final c = _items[i];
                    final name = (c["user_name"] ?? c["name"] ?? "User").toString();
                    final text = (c["text"] ?? c["comment"] ?? "").toString();

                    return ListTile(
                      onTap: () => _openUserProfile(c), // ✅ click -> profile
                      leading: _avatarFromComment(c),    // ✅ profile pic
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(text),
                    );
                  },
                ),
              ),

              const Divider(height: 1),

              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctl,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: "Write a comment…",
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: troonkyColor, width: 1.2),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // ✅ Gradient Send button
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: _sending ? null : _send,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: troonkyGradient(),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: troonkyGradA.withOpacity(0.22),
                              blurRadius: 14,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: _sending
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                            : const Text(
                          "Send",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: TextButton(
                  onPressed: () => Navigator.pop(context, _count),
                  child: const Text(
                    "Close",
                    style: TextStyle(fontWeight: FontWeight.w800, color: troonkyColor),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
