import 'package:flutter/material.dart';

class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.item,
    required this.onTap,
  });

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  String _s(dynamic v, {String fb = ""}) {
    final x = (v ?? "").toString().trim();
    return x.isEmpty ? fb : x;
  }

  bool _isUnread() {
    final v = item["is_read"];
    if (v is bool) return v == false;
    if (v is num) return v == 0;
    final s = (v ?? "").toString().toLowerCase();
    if (s.isEmpty) return true;
    return s == "0" || s == "false" || s == "unread";
  }

  IconData _iconForType(String type) {
    switch (type) {
      case "FRIEND_REQUEST":
      case "friend_request":
        return Icons.group_add_rounded;

      case "POST_COMMENT":
      case "post_comment":
        return Icons.mode_comment_outlined;

      case "ORDER_PLACED":
      case "ORDER_CONFIRMED":
      case "ORDER_SHIPPED":
      case "ORDER_DELIVERED":
      case "ORDER_CANCELLED":
      case "order":
      case "order_update":
        return Icons.local_shipping_outlined;

      case "new_message":
        return Icons.message_outlined;

      default:
        return Icons.notifications_none_rounded;
    }
  }

  String _timeAgo(dynamic createdAt) {
    // Accepts: ISO string / timestamp / "time" field fallback
    if (createdAt == null) return "";
    DateTime? dt;

    try {
      if (createdAt is int) {
        dt = DateTime.fromMillisecondsSinceEpoch(createdAt);
      } else if (createdAt is num) {
        dt = DateTime.fromMillisecondsSinceEpoch(createdAt.toInt());
      } else {
        final s = createdAt.toString().trim();
        if (s.isEmpty) return "";
        dt = DateTime.tryParse(s);
      }
    } catch (_) {}

    if (dt == null) return _s(createdAt);

    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) return "${diff.inSeconds}s ago";
    if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
    if (diff.inHours < 24) return "${diff.inHours}h ago";
    if (diff.inDays < 7) return "${diff.inDays}d ago";

    // fallback date
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final type = _s(item["type"], fb: "general");
    final title = _s(item["title"], fb: _s(item["body"], fb: "Notification"));
    final body = _s(item["body"]);
    final createdAt = item["created_at"] ?? item["createdAt"] ?? item["time"];
    final actorName = _s(item["actor_name"] ?? item["from_name"] ?? item["sender_name"]);
    final actorAvatar = _s(item["actor_avatar"] ?? item["from_avatar"] ?? item["sender_avatar"]);
    final unread = _isUnread();

    return InkWell(
      onTap: onTap,
      child: Container(
        color: unread ? Colors.deepPurple.withOpacity(0.06) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.deepPurple.shade50,
                  backgroundImage: actorAvatar.isNotEmpty ? NetworkImage(actorAvatar) : null,
                  child: actorAvatar.isEmpty
                      ? Icon(_iconForType(type), color: Colors.deepPurple)
                      : null,
                ),
                if (unread)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.deepPurple,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    actorName.isNotEmpty ? "$actorName • $title" : title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    _timeAgo(createdAt),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
