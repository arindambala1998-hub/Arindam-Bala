import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:troonky_link/pages/notifications/controllers/notifications_controller.dart';
import 'package:troonky_link/pages/notifications/widgets/notification_tile.dart';

// Existing pages (routes use)
import 'package:troonky_link/pages/profile/profile_page.dart';
import 'package:troonky_link/pages/business_profile/OrderDetailsPage.dart';
import 'package:troonky_link/pages/business_profile/ServiceOrderDetailsPage.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController()
      ..addListener(() {
        final c = context.read<NotificationsController>();
        if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
          c.loadMore();
        }
      });

    // first load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationsController>().init();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  Map<String, dynamic> _parseDataJson(dynamic raw) {
    if (raw == null) return {};
    if (raw is Map) return _asMap(raw);

    final s = raw.toString().trim();
    if (s.isEmpty) return {};
    try {
      final d = jsonDecode(s);
      if (d is Map) return _asMap(d);
    } catch (_) {}
    return {};
  }

  Future<void> _handleTap(BuildContext context, Map<String, dynamic> item) async {
    final c = context.read<NotificationsController>();
    await c.markRead(item);

    final type = (item["type"] ?? "").toString().trim();
    final data = _parseDataJson(item["data_json"] ?? item["data"] ?? item["payload"]);
    final deepLink = (item["deep_link"] ?? item["deeplink"] ?? "").toString().trim();

    // ---- If backend sends a deeplink, you can handle it here later ----
    if (deepLink.isNotEmpty) {
      // for now: fallback
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Deep link: $deepLink")),
      );
      return;
    }

    // ---- Type based navigation (friend/comment/order) ----
    if (type == "FRIEND_REQUEST" || type == "friend_request") {
      Navigator.pushNamed(context, "/friend_requests");
      return;
    }

    if (type == "POST_COMMENT" || type == "post_comment") {
      // তোমার প্রজেক্টে PostDetails page route না থাকলে আপাতত Feed এ পাঠাচ্ছি
      // data["postId"] থাকলে ভবিষ্যতে single post view ওপেন করবে
      Navigator.pushNamed(context, "/main_app");
      return;
    }

    if (type.startsWith("ORDER_") || type == "order" || type == "order_update") {
      // data থেকে orderType + orderId পেলেই details page খুলবে
      final orderId = (data["orderId"] ?? data["id"] ?? "").toString().trim();
      final orderType = (data["orderType"] ?? data["type"] ?? "product").toString().toLowerCase();

      if (orderId.isNotEmpty) {
        if (orderType == "service") {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ServiceOrderDetailsPage(order: {"id": orderId}),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OrderDetailsPage(order: {"id": orderId}),
            ),
          );
        }
        return;
      }

      Navigator.pushNamed(context, "/main_app");
      return;
    }

    // Generic fallback (profile open if actorId exists)
    final actorId = (item["actor_id"] ?? item["from_id"] ?? data["actorId"] ?? "").toString().trim();
    if (actorId.isNotEmpty) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ProfilePage(userId: actorId)));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Notification clicked")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NotificationsController(pageSize: 20),
      child: Builder(
        builder: (ctx) {
          return Scaffold(
            appBar: AppBar(
              title: const Text("Notifications"),
              centerTitle: true,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 0.6,
              actions: [
                Consumer<NotificationsController>(
                  builder: (_, c, __) {
                    final hasUnread = c.unreadCount > 0;
                    return IconButton(
                      tooltip: "Mark all as read",
                      onPressed: c.items.isEmpty ? null : () => c.markAllRead(),
                      icon: Stack(
                        children: [
                          const Icon(Icons.done_all_rounded),
                          if (hasUnread)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
            body: _Body(scroll: _scroll, onTapItem: (item) => _handleTap(ctx, item)),
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.scroll,
    required this.onTapItem,
  });

  final ScrollController scroll;
  final Future<void> Function(Map<String, dynamic> item) onTapItem;

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationsController>(
      builder: (_, c, __) {
        if (c.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (c.error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 46),
                  const SizedBox(height: 12),
                  Text(c.error!, textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: c.refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text("Try Again"),
                  ),
                ],
              ),
            ),
          );
        }

        if (c.items.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_off_outlined, color: Colors.grey[400], size: 64),
                const SizedBox(height: 14),
                const Text(
                  "No notifications yet",
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: c.refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text("Refresh"),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            await c.refresh();
            await c.refreshUnreadCount();
          },
          child: ListView.builder(
            controller: scroll,
            itemCount: c.items.length + (c.loadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= c.items.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final item = c.items[index];
              return NotificationTile(
                item: item,
                onTap: () => onTapItem(item),
              );
            },
          ),
        );
      },
    );
  }
}
