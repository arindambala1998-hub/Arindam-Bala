import 'package:flutter/foundation.dart';
import 'package:troonky_link/services/notification_api.dart';

class NotificationsController extends ChangeNotifier {
  NotificationsController({this.pageSize = 20});

  final int pageSize;

  bool _loading = false;
  bool _loadingMore = false;
  String? _error;

  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  String? get error => _error;

  final List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> get items => List.unmodifiable(_items);

  String? _cursor;
  bool _hasMore = true;
  bool get hasMore => _hasMore;

  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  // ------------- Public API -------------
  Future<void> init() async {
    await Future.wait([
      refresh(),
      refreshUnreadCount(),
    ]);
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await NotificationAPI.fetchNotifications(limit: pageSize);
      _items
        ..clear()
        ..addAll(res.items);

      _cursor = res.nextCursor;
      _hasMore = res.hasMore;
    } catch (e) {
      _error = "Failed to load notifications";
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_loadingMore || _loading || !_hasMore) return;
    if (_cursor == null || _cursor!.trim().isEmpty) {
      _hasMore = false;
      notifyListeners();
      return;
    }

    _loadingMore = true;
    notifyListeners();

    try {
      final res = await NotificationAPI.fetchNotifications(
        cursor: _cursor,
        limit: pageSize,
      );

      // Duplicate safe (id based)
      final existingIds = _items.map((e) => (e["id"] ?? "").toString()).toSet();
      for (final n in res.items) {
        final id = (n["id"] ?? "").toString();
        if (id.isNotEmpty && !existingIds.contains(id)) {
          _items.add(n);
        }
      }

      _cursor = res.nextCursor;
      _hasMore = res.hasMore;
    } catch (_) {
      // silent
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  Future<void> markRead(Map<String, dynamic> item) async {
    final id = item["id"];
    if (id == null) return;

    // optimistic update
    final index = _items.indexOf(item);
    if (index >= 0) {
      final wasUnread = (_items[index]["is_read"] == 0) || (_items[index]["is_read"] == false);
      _items[index] = {
        ..._items[index],
        "is_read": 1,
      };
      if (wasUnread && _unreadCount > 0) _unreadCount -= 1;
      notifyListeners();
    }

    await NotificationAPI.markAsRead(id);
  }

  Future<void> markAllRead() async {
    // optimistic
    for (var i = 0; i < _items.length; i++) {
      _items[i] = {..._items[i], "is_read": 1};
    }
    _unreadCount = 0;
    notifyListeners();

    await NotificationAPI.markAllRead();
  }

  Future<void> refreshUnreadCount() async {
    final c = await NotificationAPI.fetchUnreadCount();
    _unreadCount = c;
    notifyListeners();
  }
}
