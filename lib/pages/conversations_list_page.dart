import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:troonky_link/services/message_api.dart';
import 'package:troonky_link/services/feed_api.dart';
import 'package:troonky_link/pages/messages_page.dart';

// =========================
// ✅ Troonky Theme
// =========================
const Color troonkyColor = Color(0xFF333399);
const Color troonkyGradA = Color(0xFF7C2AE8);
const Color troonkyGradB = Color(0xFFFF2DAA);

LinearGradient troonkyGradient() {
  return const LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [troonkyGradA, troonkyGradB],
  );
}

enum _MsgStatus { none, sent, delivered, seen }

class ConversationsListPage extends StatefulWidget {
  const ConversationsListPage({super.key});

  @override
  State<ConversationsListPage> createState() => _ConversationsListPageState();
}

class _ConversationsListPageState extends State<ConversationsListPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  String _token = "";
  int _myUserId = 0;

  bool _loading = true;

  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    _token = (prefs.getString("token") ?? "").trim();
    _myUserId = int.tryParse((prefs.getString("userId") ?? "").trim()) ?? 0;

    await _loadConversations(initial: true);
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;

      final q = _searchCtrl.text.trim().toLowerCase();
      if (q.isEmpty) {
        setState(() => _filtered = List<Map<String, dynamic>>.from(_all));
        return;
      }

      setState(() {
        _filtered = _all.where((c) {
          final name = _str(c, ['friend_name', 'friendName', 'name']).toLowerCase();
          final last = _lastPreview(c).toLowerCase();
          return name.contains(q) || last.contains(q);
        }).toList();
      });
    });
  }

  // ============================================================
  // LOAD CONVERSATIONS (backend: GET /api/messages/list)
  // ============================================================
  Future<void> _loadConversations({bool initial = false}) async {
    if (!mounted) return;

    setState(() => _loading = initial ? true : _loading);

    if (_token.isEmpty) {
      setState(() {
        _all = [];
        _filtered = [];
        _loading = false;
      });
      return;
    }

    try {
      final rawList = await MessageAPI.getConversationList(token: _token);

      final list = rawList
          .where((e) => e is Map)
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // ✅ newest chat first
      list.sort((a, b) => _parseTime(b).compareTo(_parseTime(a)));

      _all = list;
      _filtered = _applySearchNow(list);

      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to load chats: $e")),
      );
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _applySearchNow(List<Map<String, dynamic>> list) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return List<Map<String, dynamic>>.from(list);

    return list.where((c) {
      final name = _str(c, ['friend_name', 'friendName', 'name']).toLowerCase();
      final last = _lastPreview(c).toLowerCase();
      return name.contains(q) || last.contains(q);
    }).toList();
  }

  // ============================================================
  // NAVIGATION
  // ============================================================
  void _navigateToMessages(Map<String, dynamic> c) {
    final friendId = _toInt(c['friend_id'] ?? c['friendId'] ?? c['id']);
    if (friendId <= 0) return;

    final blockedByMe = _toBool(c['is_blocked_by_me'] ?? c['blocked_by_me']);
    final blockedMe = _toBool(c['blocked_me']);

    if (blockedByMe || blockedMe) {
      final msg = blockedMe
          ? "You are blocked by this user."
          : "You blocked this user. Unblock to chat.";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }

    final friendName = _str(c, ['friend_name', 'friendName', 'name']).trim();
    final avatarRaw = _str(c, ['friend_avatar', 'friendAvatar', 'profile_pic', 'avatar']).trim();
    final friendAvatarUrl = avatarRaw.isNotEmpty ? _publicUrl(avatarRaw) : "";

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessagesPage(
          friendId: friendId.toString(),
          friendName: friendName.isEmpty ? "User" : friendName,
          friendAvatarUrl: friendAvatarUrl,
        ),
      ),
    ).then((_) => _loadConversations());
  }

  // ============================================================
  // SWIPE ACTIONS
  // LEFT  -> Clear Chat (delete-for-me all messages)
  // RIGHT -> Block user
  // ============================================================
  Future<bool> _confirmClearChat(Map<String, dynamic> c) async {
    final name = _str(c, ['friend_name', 'friendName', 'name']).trim();
    return (await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Clear chat?"),
        content: Text(
          "This will hide all messages in this chat from your inbox (delete-for-me).\n\nChat with: ${name.isEmpty ? "User" : name}",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Clear")),
        ],
      ),
    )) ??
        false;
  }

  Future<bool> _confirmBlock(Map<String, dynamic> c) async {
    final name = _str(c, ['friend_name', 'friendName', 'name']).trim();
    return (await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Block user?"),
        content: Text(
            "Block ${name.isEmpty ? "this user" : name}? They won’t be able to message you."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Block")),
        ],
      ),
    )) ??
        false;
  }

  Future<void> _doClearChatForMe(Map<String, dynamic> c) async {
    final friendId = _toInt(c['friend_id'] ?? c['friendId'] ?? c['id']);
    if (_token.isEmpty || friendId <= 0) return;

    // ✅ IMPORTANT: MessageAPI তে এই method থাকতে হবে
    await MessageAPI.clearConversationForMe(token: _token, friendId: friendId);
  }

  Future<void> _doBlockUser(Map<String, dynamic> c) async {
    final friendId = _toInt(c['friend_id'] ?? c['friendId'] ?? c['id']);
    if (_token.isEmpty || friendId <= 0) return;

    await MessageAPI.blockUser(token: _token, friendId: friendId);
  }

  // ============================================================
  // HELPERS
  // ============================================================
  static String _str(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null) return v.toString();
    }
    return "";
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? "") ?? 0;
  }

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v == 1;
    final s = (v ?? "").toString().toLowerCase().trim();
    return s == "true" || s == "1" || s == "yes";
  }

  // ✅ fixes UTC "Z" + mysql "YYYY-MM-DD HH:MM:SS"
  static DateTime _parseServerTime(dynamic v) {
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);

    if (v is int) {
      if (v > 1000000000000) return DateTime.fromMillisecondsSinceEpoch(v).toLocal();
      return DateTime.fromMillisecondsSinceEpoch(v * 1000).toLocal();
    }

    final raw = v.toString().trim();
    if (raw.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);

    String s = raw.contains(' ') && !raw.contains('T')
        ? raw.replaceFirst(' ', 'T')
        : raw;

    final dt = DateTime.tryParse(s);
    if (dt == null) return DateTime.fromMillisecondsSinceEpoch(0);

    return dt.isUtc ? dt.toLocal() : dt;
  }

  static DateTime _parseTime(Map<String, dynamic> c) {
    final v = c['last_time'] ??
        c['last_message_time'] ??
        c['lastMessageTime'] ??
        c['updated_at'] ??
        c['updatedAt'] ??
        c['created_at'] ??
        c['createdAt'];

    return _parseServerTime(v);
  }

  static String _fmtTime(DateTime dt) {
    if (dt.millisecondsSinceEpoch == 0) return "";
    final now = DateTime.now();
    final sameDay = now.year == dt.year && now.month == dt.month && now.day == dt.day;

    String two(int n) => n.toString().padLeft(2, '0');

    if (sameDay) {
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final ampm = dt.hour >= 12 ? "PM" : "AM";
      return "$h:${two(dt.minute)} $ampm";
    }
    return "${two(dt.day)}/${two(dt.month)}";
  }

  static String _publicUrl(String s) {
    final t = s.trim();
    if (t.isEmpty) return "";
    if (t.startsWith("http://") || t.startsWith("https://")) return t;
    return FeedAPI.toPublicUrl(t);
  }

  // ✅ last preview normalize (newline remove, media fallback)
  static String _lastPreview(Map<String, dynamic> c) {
    final txt = _str(c, ['last_message', 'lastMessage', 'message'])
        .replaceAll('\n', ' ')
        .trim();

    if (txt.isNotEmpty) return txt;

    final media = _str(c, ['last_media', 'lastMedia', 'media_url', 'mediaUrl']).trim();
    if (media.isNotEmpty) return "📷 Photo";

    return "";
  }

  static _MsgStatus _statusFromListRow(Map<String, dynamic> c, int myUserId) {
    final lastSenderId = _toInt(c['last_sender_id'] ?? c['lastSenderId'] ?? c['sender_id']);
    if (lastSenderId <= 0 || myUserId <= 0) return _MsgStatus.none;

    final fromMe = lastSenderId == myUserId;
    if (!fromMe) return _MsgStatus.none;

    final lastIsSeen = _toBool(c['last_is_seen'] ?? c['lastIsSeen'] ?? c['is_seen']);
    return lastIsSeen ? _MsgStatus.seen : _MsgStatus.delivered;
  }

  // ============================================================
  // UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        elevation: 0,
        title: const Text("Messages"),
        flexibleSpace: Container(decoration: BoxDecoration(gradient: troonkyGradient())),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
              onRefresh: () => _loadConversations(),
              child: _filtered.isEmpty
                  ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Text(
                      "Start a new chat!",
                      style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              )
                  : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 84),
                itemBuilder: (_, i) {
                  final c = _filtered[i];

                  final friendName = _str(c, ['friend_name', 'friendName', 'name']).trim();
                  final avatarRaw =
                  _str(c, ['friend_avatar', 'friendAvatar', 'profile_pic', 'avatar']).trim();
                  final avatarUrl = avatarRaw.isNotEmpty ? _publicUrl(avatarRaw) : "";

                  final lastPreview = _lastPreview(c);
                  final unread = _toInt(c['unread_count'] ?? c['unread'] ?? c['unreadCount'] ?? 0);

                  final lastTime = _parseTime(c);
                  final timeText = _fmtTime(lastTime);

                  final status = _statusFromListRow(c, _myUserId);
                  final fromMe = status != _MsgStatus.none;

                  final blockedByMe = _toBool(c['is_blocked_by_me'] ?? c['blocked_by_me']);
                  final blockedMe = _toBool(c['blocked_me']);
                  final isBlocked = blockedByMe || blockedMe;

                  return Dismissible(
                    key: ValueKey(
                        "conv_${_toInt(c['conversation_id'] ?? c['conversationId'])}_${_toInt(c['friend_id'] ?? c['friendId'])}_$i"),
                    direction: isBlocked ? DismissDirection.none : DismissDirection.horizontal,
                    background: _swipeBg(
                      alignLeft: true,
                      icon: Icons.delete_outline,
                      label: "Clear",
                      color: Colors.red.shade600,
                    ),
                    secondaryBackground: _swipeBg(
                      alignLeft: false,
                      icon: Icons.block,
                      label: "Block",
                      color: Colors.orange.shade700,
                    ),
                    confirmDismiss: (dir) async {
                      if (dir == DismissDirection.startToEnd) {
                        return await _confirmClearChat(c);
                      } else {
                        return await _confirmBlock(c);
                      }
                    },
                    onDismissed: (dir) async {
                      final removed = c;
                      setState(() {
                        _all.remove(removed);
                        _filtered.remove(removed);
                      });

                      try {
                        if (dir == DismissDirection.startToEnd) {
                          await _doClearChatForMe(removed);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Chat cleared ✅")),
                          );
                        } else {
                          await _doBlockUser(removed);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("User blocked ✅")),
                          );
                        }
                      } catch (e) {
                        if (!mounted) return;
                        await _loadConversations();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
                      }
                    },
                    child: _ConversationRow(
                      name: friendName.isEmpty ? "User" : friendName,
                      lastMessage: lastPreview.isEmpty ? " " : lastPreview,
                      avatarUrl: avatarUrl,
                      unread: unread,
                      timeText: timeText,
                      fromMe: fromMe,
                      status: status,
                      isBlocked: isBlocked,
                      blockedMe: blockedMe,
                      blockedByMe: blockedByMe,
                      onTap: () => _navigateToMessages(c),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      color: Colors.white,
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: "Search messages...",
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchCtrl.text.trim().isEmpty
              ? null
              : IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              _searchCtrl.clear();
              FocusScope.of(context).unfocus();
              setState(() => _filtered = List<Map<String, dynamic>>.from(_all));
            },
          ),
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }

  Widget _swipeBg({
    required bool alignLeft,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      alignment: alignLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!alignLeft) Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          if (!alignLeft) const SizedBox(width: 10),
          Icon(icon, color: Colors.white),
          if (alignLeft) const SizedBox(width: 10),
          if (alignLeft) Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  final String name;
  final String lastMessage;
  final String avatarUrl;

  final int unread;
  final String timeText;

  final bool fromMe;
  final _MsgStatus status;

  final bool isBlocked;
  final bool blockedMe;
  final bool blockedByMe;

  final VoidCallback onTap;

  const _ConversationRow({
    required this.name,
    required this.lastMessage,
    required this.avatarUrl,
    required this.unread,
    required this.timeText,
    required this.fromMe,
    required this.status,
    required this.isBlocked,
    required this.blockedMe,
    required this.blockedByMe,
    required this.onTap,
  });

  Widget _tick() {
    if (!fromMe) return const SizedBox.shrink();

    IconData icon;
    Color color;

    switch (status) {
      case _MsgStatus.delivered:
        icon = Icons.done_all;
        color = Colors.grey;
        break;
      case _MsgStatus.seen:
        icon = Icons.done_all;
        color = troonkyGradB;
        break;
      case _MsgStatus.sent:
        icon = Icons.check;
        color = Colors.grey;
        break;
      default:
        return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Icon(icon, size: 16, color: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firstLetter = name.isNotEmpty ? name[0].toUpperCase() : "?";

    final subtitle = isBlocked
        ? (blockedMe ? "You are blocked" : "You blocked this user")
        : lastMessage;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: Colors.grey.shade200,
              backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
              child: avatarUrl.isEmpty
                  ? Text(
                firstLetter,
                style: const TextStyle(
                  color: troonkyColor,
                  fontWeight: FontWeight.w900,
                ),
              )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _tick(),
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isBlocked ? Colors.red.shade400 : Colors.grey.shade700,
                            fontSize: 13.2,
                            height: 1.15,
                            fontWeight: isBlocked ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  timeText,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                if (unread > 0 && !isBlocked)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: troonkyGradient(),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      unread > 99 ? "99+" : unread.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
