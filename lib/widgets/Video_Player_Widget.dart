// lib/widgets/Video_Player_Widget.dart
// FINAL • PRODUCTION • HIGH PERFORMANCE REELS PLAYER
// ✅ ENGINE: BetterPlayerPlus (Optimized for HLS & Caching)
// ✅ CACHING: Saves data, zero buffering on replay
// ✅ UI: Fullscreen Cover Fit for Reels
// ✅ FAIL-SAFE: Error handling & Placeholder support

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String url;
  final bool autoPlay;
  final bool looping;
  final bool showControls; // false = reels mode (Fullscreen)
  final String? thumbnailUrl; // Optional thumbnail while loading

  const VideoPlayerWidget({
    super.key,
    required this.url,
    this.autoPlay = false,
    this.looping = true,
    this.showControls = false,
    this.thumbnailUrl,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> with WidgetsBindingObserver {
  BetterPlayerController? _betterPlayerController;
  bool _isInitialized = false;
  bool _hasError = false;

  // ✅ Global Cache Configuration (Shared across instances)
  static const BetterPlayerCacheConfiguration _cacheConfig = BetterPlayerCacheConfiguration(
    useCache: true,
    preCacheSize: 10 * 1024 * 1024, // Pre-load 10MB
    maxCacheSize: 100 * 1024 * 1024, // Max 100MB Cache
    maxCacheFileSize: 20 * 1024 * 1024, // Max 20MB per file
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPlayer();
  }

  // ======================================================
  // INIT PLAYER ENGINE
  // ======================================================
  Future<void> _initPlayer() async {
    if (widget.url.isEmpty) {
      if (mounted) setState(() => _hasError = true);
      return;
    }

    try {
      // 1. Configure Data Source (HLS + Caching)
      final dataSource = BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        widget.url,
        videoFormat: BetterPlayerVideoFormat.hls, // Smart Streaming
        cacheConfiguration: _cacheConfig,
        bufferingConfiguration: const BetterPlayerBufferingConfiguration(
          minBufferMs: 2000,       // Minimum 2s buffer before play
          maxBufferMs: 10000,      // Max 10s buffer
          bufferForPlaybackMs: 1000, // Play when 1s is ready
          bufferForPlaybackAfterRebufferMs: 2000,
        ),
      );

      // 2. Configure Player Controls & UI
      final config = BetterPlayerConfiguration(
        autoPlay: widget.autoPlay,
        looping: widget.looping,
        fit: widget.showControls ? BoxFit.contain : BoxFit.cover, // Reels = Cover
        aspectRatio: widget.showControls ? 16 / 9 : null, // Reels = Fullscreen
        handleLifecycle: true, // Auto pause on app background
        autoDispose: true,
        controlsConfiguration: widget.showControls
            ? const BetterPlayerControlsConfiguration(
          enableRetry: true,
          enableSkips: false,
        )
            : const BetterPlayerControlsConfiguration(
          showControls: false, // No UI for Reels
          enableRetry: true,
        ),
      );

      // 3. Create Controller
      _betterPlayerController = BetterPlayerController(config);
      await _betterPlayerController!.setupDataSource(dataSource);

      // 4. Update State
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _hasError = false;
        });
      }
    } catch (e) {
      debugPrint("❌ VIDEO PLAYER ERROR: $e");
      if (mounted) setState(() => _hasError = true);
    }
  }

  // ======================================================
  // LIFECYCLE MANAGEMENT
  // ======================================================
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_betterPlayerController == null) return;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _betterPlayerController!.pause();
    } else if (state == AppLifecycleState.resumed && widget.autoPlay) {
      _betterPlayerController!.play();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Note: BetterPlayer handles its own disposal via autoDispose: true
    // But forcing dispose here is safer for list views
    _betterPlayerController?.dispose(forceDispose: true);
    super.dispose();
  }

  // ======================================================
  // UI BUILDER
  // ======================================================
  @override
  Widget build(BuildContext context) {
    // 1. Error State
    if (_hasError) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.white54, size: 40),
              SizedBox(height: 8),
              Text("Video unavailable", style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    // 2. Loading State (Show Thumbnail or Spinner)
    if (!_isInitialized || _betterPlayerController == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty)
            Image.network(
              widget.thumbnailUrl!,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => Container(color: Colors.black),
            )
          else
            Container(color: Colors.black),

          const Center(child: CircularProgressIndicator(color: Colors.white30, strokeWidth: 2)),
        ],
      );
    }

    // 3. Active Player
    return Container(
      color: Colors.black, // Background color to prevent white flashes
      child: widget.showControls
          ? AspectRatio(
        aspectRatio: 16 / 9,
        child: BetterPlayer(controller: _betterPlayerController!),
      )
          : SizedBox.expand(
        // Reels Mode: Full Cover
        child: BetterPlayer(controller: _betterPlayerController!),
      ),
    );
  }
}