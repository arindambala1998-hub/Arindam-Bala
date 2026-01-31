// lib/services/reel_global_controller.dart
// --------------------------------------------------
// Global controller to manage Reel pause / resume
// across BottomNavigationBar, lifecycle, and pages
// --------------------------------------------------

typedef ReelVoidCallback = void Function();

class ReelGlobalController {
  static ReelVoidCallback? _onPause;
  static ReelVoidCallback? _onResume;

  /// Attach callbacks from HomePageShortVideo
  static void attach({
    required ReelVoidCallback onPause,
    required ReelVoidCallback onResume,
  }) {
    _onPause = onPause;
    _onResume = onResume;
  }

  /// Detach when page is disposed
  static void detach() {
    _onPause = null;
    _onResume = null;
  }

  /// Pause currently playing reel
  static void pause() {
    _onPause?.call();
  }

  /// Resume current reel
  static void resume() {
    _onResume?.call();
  }
}
