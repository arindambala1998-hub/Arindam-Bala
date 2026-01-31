import 'package:flutter/material.dart';

import 'package:troonky_link/pages/messages_page.dart';

import '../controllers/business_profile_controller.dart';
import '../../../services/business_api.dart';

/// Friends tab (production-ready)
/// ✅ uses controller paging cache
/// ✅ no per-item status hammering (backend should return only friends)
class BPFriendsTab extends StatelessWidget {
  final BusinessProfileController ctrl;

  const BPFriendsTab({super.key, required this.ctrl});

  static const Color _gEnd = Color(0xFF333399);

  String _s(dynamic v) => (v ?? '').toString().trim();

  Map<String, dynamic> _toMap(dynamic item) {
    if (item is Map<String, dynamic>) return item;
    if (item is Map) return Map<String, dynamic>.from(item);
    return <String, dynamic>{};
  }

  Map<String, dynamic> _unwrap(dynamic item) {
    final m = _toMap(item);
    for (final k in const ['friend', 'user', 'profile']) {
      final v = m[k];
      if (v is Map) {
        final nm = Map<String, dynamic>.from(v);
        return {...m, ...nm};
      }
    }
    return m;
  }

  String _pickId(Map<String, dynamic> f) {
    for (final k in const [
      'friend_id',
      'id',
      '_id',
      'user_id',
      'uid',
      'target_id'
    ]) {
      final v = _s(f[k]);
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String _pickName(Map<String, dynamic> f) {
    for (final k in const ['name', 'full_name', 'username', 'display_name']) {
      final v = _s(f[k]);
      if (v.isNotEmpty) return v;
    }
    return 'Unknown User';
  }

  String _pickImage(Map<String, dynamic> f) {
    for (final k in const [
      'profile_pic',
      'avatar',
      'image',
      'photo',
      'user_image',
      'dp'
    ]) {
      final v = _s(f[k]);
      if (v.isNotEmpty) return BusinessAPI.toPublicUrl(v);
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final pager = ctrl.friendsPager;

    if (pager.loadingFirst && pager.items.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: _gEnd, strokeWidth: 3),
      );
    }

    if (pager.error.isNotEmpty && pager.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(pager.error, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => pager.loadFirst(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Deduplicate by id for safety
    final map = <String, Map<String, dynamic>>{};
    for (final raw in pager.items) {
      final u = _unwrap(raw);
      final id = _pickId(u);
      if (id.isNotEmpty) map[id] = u;
    }
    final friends = map.values.toList()
      ..sort((a, b) => _pickName(a)
          .toLowerCase()
          .compareTo(_pickName(b).toLowerCase()));

    return RefreshIndicator(
      color: _gEnd,
      onRefresh: () async => ctrl.refresh(),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 220) {
            pager.loadNext();
          }
          return false;
        },
        child: friends.isEmpty
            ? ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(
              child: Text(
                'You have no friends yet',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          ],
        )
            : ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: friends.length + (pager.hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= friends.length) {
              return Center(
                child: pager.loadingNext
                    ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : TextButton.icon(
                  onPressed: () => pager.loadNext(),
                  icon: const Icon(Icons.expand_more),
                  label: const Text('Load more'),
                ),
              );
            }

            final f = friends[index];
            final id = _pickId(f);
            final name = _pickName(f);
            final img = _pickImage(f);

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
                color: Colors.white,
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage:
                  img.isNotEmpty ? NetworkImage(img) : null,
                  child: img.isEmpty
                      ? const Icon(Icons.person, color: Colors.grey)
                      : null,
                ),
                title: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                trailing: id.isEmpty
                    ? null
                    : TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        // ✅ FIXED: use MessagesPage required params
                        builder: (_) => MessagesPage(
                          friendId: id,
                          friendName: name,
                        ),
                      ),
                    );
                  },
                  child: const Text('Message'),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
