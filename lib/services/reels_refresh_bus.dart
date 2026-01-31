// lib/services/reels_refresh_bus.dart
import 'dart:async';

class ReelsRefreshBus {
  ReelsRefreshBus._();

  static final StreamController<int> _ctrl =
  StreamController<int>.broadcast();

  static Stream<int> get stream => _ctrl.stream;

  /// Call this when reels list needs refresh (after upload/hide/block/etc.)
  static void bump() {
    if (_ctrl.isClosed) return;
    _ctrl.add(DateTime.now().millisecondsSinceEpoch);
  }

  static void dispose() {
    _ctrl.close();
  }
}
