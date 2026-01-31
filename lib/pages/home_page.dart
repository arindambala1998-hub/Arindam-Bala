// lib/pages/home_page.dart
// FINAL • PRODUCTION • STABLE VERSION
// ✅ START PAUSED (App open force pause)
// ✅ TOP PAUSE/PLAY BUTTON ADDED
// ✅ TAP = Pause/Play
// ✅ BACKEND REQUEST STOPS ON PAUSE (HLS Fetching stops)
// ✅ SEEN TRACKING - No repeat reels like Facebook

import 'dart:async';
import 'dart:collection';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:troonky_link/services/reels_api.dart';
import 'package:troonky_link/services/reel_global_controller.dart';
import 'package:troonky_link/pages/reel_comments_sheet.dart';
import 'package:troonky_link/pages/reel_share_sheet.dart';
import 'package:troonky_link/pages/new_reel_upload_page.dart';
import 'package:troonky_link/pages/profile/profile_page.dart';

final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

class HomePageShortVideo extends StatefulWidget {
  final bool active;
  final bool showBack;
  final List<Map<String, dynamic>>? initialVideos;
  final int initialIndex;
  final bool lockToInitialVideos;

  const HomePageShortVideo({
    super.key,
    this.active = true,
    this.showBack = false,
    this.initialVideos,
    this.initialIndex = 0,
    this.lockToInitialVideos = false,
  });

  @override
  State<HomePageShortVideo> createState() => _HomePageShortVideoState();
}

class _HomePageShortVideoState extends State<HomePageShortVideo>
    with WidgetsBindingObserver, TickerProviderStateMixin, RouteAware {
  late final PageController _pageCtrl;
  final List<Map<String, dynamic>> _videos = [];

  final Map<int, BetterPlayerController> _controllers = {};

  int _current = 0;
  int _page = 1;
  bool _loading = true;
  bool _hasMore = true;

  static const int _initialLoadCount = 10;
  static const int _nextLoadCount = 5;
  static const int _triggerAfterScrollCount = 3;
  int _lastLoadTriggerIndex = 0;

  // ✅ SEEN TRACKING (no repeat reels like Facebook)
  static const String _prefsSeenKey = "reels_seen_ids_v1";
  static const int _persistSeenMax = 2000;
  static const int _maxSessionReels = 50;  // Max reels per session
  final LinkedHashSet<String> _seenIds = LinkedHashSet();
  final Set<String> _queuedIds = <String>{};
  bool _usedSeenFallbackOnce = false;

  // ✅ Reels best practice: autoplay sound OFF by default
  bool _muted = true;

  // ✅ Start PAUSED to prevent autoplay on app launch
  bool _pausedByUser = true;

  // ✅ Until user taps play at least once, keep everything paused.
  bool _userEverPlayed = false;

  bool _routeActive = true;
  bool _showHeart = false;
  bool _captionExpanded = false;
  bool _likeBusy = false;
  bool _actionBusy = false;

  DateTime? _startTime;
  Duration _startPos = Duration.zero;

  bool _tapBusy = false;

  late final AnimationController _heartAnim;
  final Color gradientStart = const Color(0xFFFF00CC);
  final Color gradientEnd = const Color(0xFF333399);
  static const double _railWidth = 70;
  static const double _railIconSize = 34;
  static const String _apiRoot = "https://adminapi.troonky.in";

  static const BetterPlayerCacheConfiguration _cacheCfg =
  BetterPlayerCacheConfiguration(
    useCache: true,
    preCacheSize: 5 * 1024 * 1024,
    maxCacheSize: 100 * 1024 * 1024,
    maxCacheFileSize: 15 * 1024 * 1024,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _heartAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    ReelGlobalController.attach(
      onPause: _pauseCurrentReel,
      onResume: _resumeCurrentReel,
    );

    _current = widget.initialIndex.clamp(0, 999999);
    _pageCtrl = PageController(initialPage: _current);

    if (widget.initialVideos != null && widget.initialVideos!.isNotEmpty) {
      _videos.addAll(widget.initialVideos!);
      _loading = false;
      _hasMore = false;

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _initController(_current);
        // ❌ REMOVED FORCE PLAY on init
        // _ctrl(_current)?.play();

        await Future.delayed(const Duration(milliseconds: 250));
        if (mounted) await _initController(_current + 1);
        if (mounted) setState(() {});
      });
    } else {
      _loadReels(reset: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) routeObserver.subscribe(this, route);
  }

  // ✅ Handle when parent changes widget.active (e.g., tab switch)
  @override
  void didUpdateWidget(covariant HomePageShortVideo oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ✅ If widget becomes inactive, FORCE PAUSE
    if (oldWidget.active && !widget.active) {
      _pauseCurrentReel();
    }

    // ✅ If widget becomes active AND user hasn't paused, resume
    if (!oldWidget.active && widget.active && !_pausedByUser && _userEverPlayed) {
      _resumeCurrentReel();
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _trackWatchTime(_current);
    ReelGlobalController.detach();
    WidgetsBinding.instance.removeObserver(this);
    _disposeAllControllers();
    _pageCtrl.dispose();
    _heartAnim.dispose();
    super.dispose();
  }

  void _disposeAllControllers() {
    _controllers.forEach((_, controller) {
      try {
        controller.pause();
        controller.dispose(forceDispose: true);
      } catch (_) {}
    });
    _controllers.clear();
  }

  // ---------------- LIFECYCLE ----------------
  @override
  void deactivate() {
    _pauseCurrentReel();
    super.deactivate();
  }

  @override
  void didPushNext() {
    _routeActive = false;
    _pauseCurrentReel();
  }

  @override
  void didPopNext() {
    _routeActive = true;
    _resumeCurrentReel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pauseCurrentReel();
    }
    if (state == AppLifecycleState.resumed) {
      _resumeCurrentReel();
    }
  }

  // =============================================================
  // ✅ SMART LOADING
  // =============================================================
  Future<void> _manageSlidingWindow(int index) async {
    if (!mounted) return;

    final keep = <int>{index - 1, index, index + 1};

    final toRemove = _controllers.keys.where((k) => !keep.contains(k)).toList();
    for (final k in toRemove) {
      final c = _controllers[k];
      if (c != null) {
        try {
          c.pause();
          c.dispose(forceDispose: true);
        } catch (_) {}
      }
      _controllers.remove(k);
    }

    await _initController(index);
    await Future.delayed(const Duration(milliseconds: 150));
    await _initController(index + 1);
    await _initController(index - 1);
  }

  Future<void> _initController(int index) async {
    if (index < 0 || index >= _videos.length) return;
    if (_controllers.containsKey(index)) return;

    final v = _videos[index];

    // ✅ Prefer 480/360/240/144 if server provides, and avoid 780.
    // Fallbacks remain safe (low -> full).
    String playUrl = _absUrlIfNeeded(_pickBestPlaybackUrl(v));
    if (playUrl.isEmpty) return;

    try {
      final dataSource = BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        playUrl,
        videoFormat: BetterPlayerVideoFormat.hls,
        cacheConfiguration: _cacheCfg,
        bufferingConfiguration: const BetterPlayerBufferingConfiguration(
          minBufferMs: 2000,
          maxBufferMs: 10000,
          bufferForPlaybackMs: 500,
          bufferForPlaybackAfterRebufferMs: 1000,
        ),
      );

      final controller = BetterPlayerController(
        BetterPlayerConfiguration(
          autoPlay: false, // Internal autoplay stays false
          looping: true,
          fit: BoxFit.cover,
          aspectRatio: MediaQuery.of(context).size.width /
              MediaQuery.of(context).size.height,
          controlsConfiguration: const BetterPlayerControlsConfiguration(
            showControls: false,
            enableRetry: true,
          ),
          handleLifecycle: false,
          autoDispose: false,
        ),
        betterPlayerDataSource: dataSource,
      );

      _controllers[index] = controller;
      _applyVolume(index);

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Controller Init Error: $e");
    }
  }

  // ---------------- HELPERS ----------------
  String _absUrlIfNeeded(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return s;
    if (s.startsWith("http")) return s;
    return "$_apiRoot${s.startsWith('/') ? '' : '/'}$s";
  }

  int _asInt(dynamic v) => int.tryParse(v.toString()) ?? 0;
  String _urlFull(Map v) => (v["video_url"] ?? v["video"] ?? "").toString();
  String _urlLow(Map v) =>
      (v["video_url_low"] ?? v["video_low"] ?? "").toString();
  String _thumb(Map v) => (v["thumbnail"] ?? v["thumb_url"] ?? "").toString();

  /// ✅ Prefer capped qualities (480/360/240/144). Avoid 780p by default.
  /// Falls back to low or full if server doesn't provide these keys.
  String _pickBestPlaybackUrl(Map v) {
    String _val(String k) => (v[k] ?? "").toString();

    // Common keys we might get from backend/CDN
    final candidates = <String>[
      _val("video_url_480"),
      _val("video_480"),
      _val("video480"),
      _val("video_url_360"),
      _val("video_360"),
      _val("video360"),
      _val("video_url_240"),
      _val("video_240"),
      _val("video240"),
      _val("video_url_144"),
      _val("video_144"),
      _val("video144"),
      _urlLow(v),
      _urlFull(v),
    ];

    for (final c in candidates) {
      final s = c.trim();
      if (s.isEmpty) continue;
      if (s.toLowerCase().endsWith("null")) continue;
      // Avoid known 780/720 variant keys if backend sends them accidentally.
      if (s.contains("780") || s.contains("720")) {
        // only skip if we have other candidates; keep looping
        continue;
      }
      return s;
    }

    // If everything got skipped due to '780' etc, fall back to full.
    final f = _urlFull(v).trim();
    return f.isNotEmpty ? f : "";
  }

  BetterPlayerController? _ctrl(int index) => _controllers[index];
  bool _bpReady(BetterPlayerController? c) =>
      c != null && (c.isVideoInitialized() ?? false);

  void _applyVolume(int index) {
    _ctrl(index)?.setVolume(_muted ? 0.0 : 1.0);
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    // Apply to current + neighbors (sliding window)
    _applyVolume(_current);
    _applyVolume(_current - 1);
    _applyVolume(_current + 1);
  }

  // ---------------- TRACKING & PAUSE LOGIC ----------------
  void _markWatchStartFor(int index) {
    _startTime = DateTime.now();
    final c = _ctrl(index);
    _startPos = _bpReady(c)
        ? c!.videoPlayerController!.value.position
        : Duration.zero;
  }

  void _trackWatchTime(int index) {
    if (index < 0 || index >= _videos.length || _startTime == null) return;
    final c = _ctrl(index);

    int watchSeconds = 0;
    if (_bpReady(c)) {
      watchSeconds =
          (c!.videoPlayerController!.value.position - _startPos).inSeconds;
    } else {
      watchSeconds = DateTime.now().difference(_startTime!).inSeconds;
    }

    if (watchSeconds < 1) return;

    ReelsAPI.trackReelView(
      reelId: _videos[index]["id"].toString(),
      watchTimeInSeconds: watchSeconds,
      completed: false,
    );
  }

  // ✅ PAUSE = STOP REQUESTS (Implicitly stops HLS fetching)
  void _pauseCurrentReel() {
    final c = _ctrl(_current);
    if (c != null) {
      c.pause(); // This stops media chunk requests
    }
    _trackWatchTime(_current);
  }

  void _resumeCurrentReel() {
    // ✅ STRICT: Only resume if ALL conditions met
    if (!widget.active) return;        // Widget must be active
    if (!_routeActive) return;         // Route must be active
    if (_pausedByUser) return;         // User must not have paused
    if (!_userEverPlayed) return;      // User must have played at least once

    final c = _ctrl(_current);
    if (c != null && _bpReady(c)) {
      c.play();
      _markWatchStartFor(_current);
    }
  }

  Future<void> _togglePlayPause() async {
    if (_tapBusy) return;
    _tapBusy = true;

    try {
      BetterPlayerController? c = _ctrl(_current);

      if (c == null) {
        await _initController(_current);
        c = _ctrl(_current);
      }
      if (c == null) return;

      if (_pausedByUser) {
        // Play
        setState(() => _pausedByUser = false);
        _userEverPlayed = true;
        c.play();
        _markWatchStartFor(_current);
      } else {
        // Pause
        setState(() => _pausedByUser = true);
        c.pause();
        _trackWatchTime(_current);
      }
    } finally {
      _tapBusy = false;
    }
  }

  // ---------------- DATA LOADING ----------------

  // ✅ SEEN CACHE MANAGEMENT
  Future<void> _loadSeenCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefsSeenKey) ?? const <String>[];
      _seenIds.addAll(list);
    } catch (_) {}
  }

  Future<void> _saveSeenCache() async {
    try {
      final ids = _seenIds.toList();
      if (ids.length > _persistSeenMax) {
        ids.removeRange(0, ids.length - _persistSeenMax);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsSeenKey, ids);
    } catch (_) {}
  }

  Future<void> _loadReels({bool reset = false}) async {
    if (widget.lockToInitialVideos && _videos.isNotEmpty) return;
    if (!reset && !_hasMore) return;

    if (reset) {
      _page = 1;
      _videos.clear();
      _hasMore = true;
      _loading = true;
      _current = 0;
      _pausedByUser = true;
      _usedSeenFallbackOnce = false;

      // ✅ Clear session tracking but keep seen cache
      _queuedIds.clear();
      _seenIds.clear();

      _disposeAllControllers();
      if (mounted) setState(() {});

      // ✅ Load seen cache from storage
      await _loadSeenCache();
    }

    // ✅ Check if we've reached max session reels
    if (_videos.length >= _maxSessionReels) {
      _hasMore = false;
      if (mounted) setState(() => _loading = false);
      return;
    }

    final limit = reset ? _initialLoadCount : _nextLoadCount;
    final targetAdd = reset ? _initialLoadCount : _nextLoadCount;

    final added = <Map<String, dynamic>>[];
    int emptyFetchCount = 0;
    const maxEmptyFetches = 3;

    // ✅ Keep fetching until we have enough unseen reels
    while (added.length < targetAdd && _hasMore && emptyFetchCount < maxEmptyFetches) {
      final list = await ReelsAPI.getReels(page: _page, limit: limit);

      if (list.isEmpty) {
        _hasMore = false;
        break;
      }

      _page++;

      // ignore: avoid_print
      print("🎬 ReelsPage: API returned ${list.length} reels, seenIds=${_seenIds.length}, added=${added.length}");

      int addedThisBatch = 0;
      final remaining = _maxSessionReels - _videos.length - added.length;

      for (final raw in list) {
        if (added.length >= targetAdd) break;
        if (added.length >= remaining) break;

        final reel = Map<String, dynamic>.from(raw);
        final id = (reel["id"] ?? "").toString();
        if (id.isEmpty) continue;

        // ✅ Duplicate guard (current session)
        if (_queuedIds.contains(id)) continue;
        _queuedIds.add(id);

        // ✅ Seen guard (FB-like no repeat)
        if (_seenIds.contains(id)) continue;

        _seenIds.add(id);
        added.add(reel);
        addedThisBatch++;
      }

      if (addedThisBatch == 0) {
        emptyFetchCount++;
      } else {
        emptyFetchCount = 0;
      }
    }

    // ✅ FALLBACK: If ALL reels seen, clear cache and show fresh
    if (_videos.isEmpty && added.isEmpty && !_usedSeenFallbackOnce) {
      _usedSeenFallbackOnce = true;

      // ignore: avoid_print
      print("🔄 ReelsPage: ALL REELS SEEN! Clearing cache and starting fresh...");

      _seenIds.clear();
      _queuedIds.clear();
      _page = 1;
      _hasMore = true;

      // Clear persistent cache
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefsSeenKey);
      } catch (_) {}

      // Fetch fresh from page 1
      final freshList = await ReelsAPI.getReels(page: 1, limit: _initialLoadCount);
      _page = 2;
      _hasMore = freshList.length >= _initialLoadCount;

      for (final raw in freshList) {
        if (added.length >= targetAdd) break;
        final reel = Map<String, dynamic>.from(raw);
        final id = (reel["id"] ?? "").toString();
        if (id.isEmpty) continue;

        _queuedIds.add(id);
        _seenIds.add(id);
        added.add(reel);
      }

      // ignore: avoid_print
      print("🔄 ReelsPage: Showing ${added.length} fresh reels after reset");
    }

    // ✅ Add to videos list
    if (added.isNotEmpty) {
      _videos.addAll(added);
    }

    // ✅ Save seen cache
    unawaited(_saveSeenCache());

    if (mounted) {
      setState(() => _loading = false);
      if (reset && _videos.isNotEmpty) {
        await _initController(0);

        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) _initController(1);
        });
      }
    }
  }

  Future<void> _maybeLoadNextBatchOnScroll(int newIndex) async {
    if (widget.lockToInitialVideos || !_hasMore) return;
    if ((newIndex - _lastLoadTriggerIndex) >= _triggerAfterScrollCount) {
      _lastLoadTriggerIndex = newIndex;
      await _loadReels(reset: false);
    }
  }

  // ---------------- ACTIONS ----------------
  Future<void> _onLikeToggle(int index) async {
    if (_likeBusy) return;
    _likeBusy = true;

    final v = _videos[index];
    final bool wasLiked = v["is_liked"] == true;
    final int oldLikes = _asInt(v["likes"]);

    setState(() {
      v["is_liked"] = !wasLiked;
      v["likes"] = oldLikes + (wasLiked ? -1 : 1);
      if (!wasLiked) _showHeartOverlay();
    });

    try {
      await ReelsAPI.toggleLike(reelId: v["id"].toString(), like: !wasLiked);
    } catch (_) {
      setState(() {
        v["is_liked"] = wasLiked;
        v["likes"] = oldLikes;
      });
    } finally {
      _likeBusy = false;
    }
  }

  void _showHeartOverlay() {
    setState(() => _showHeart = true);
    _heartAnim.forward(from: 0).then((_) {
      if (mounted) setState(() => _showHeart = false);
    });
  }

  Future<void> _toggleSubscribe(Map v) async {
    final creatorId = (v["user_id"] ?? "").toString();
    if (creatorId.isEmpty) return;

    final bool wasSubscribed = v["is_subscribed"] == true;
    setState(() {
      v["is_subscribed"] = !wasSubscribed;
      v["subscriber_count"] =
          _asInt(v["subscriber_count"]) + (wasSubscribed ? -1 : 1);
    });

    try {
      wasSubscribed
          ? await ReelsAPI.unsubscribeCreator(creatorUserId: creatorId)
          : await ReelsAPI.subscribeCreator(creatorUserId: creatorId);
    } catch (_) {
      setState(() => v["is_subscribed"] = wasSubscribed);
    }
  }

  Future<void> _hideReelBackend(int index) async {
    if (_actionBusy) return;
    _actionBusy = true;
    _pauseCurrentReel();
    try {
      final res = await ReelsAPI.hideReel(_videos[index]["id"].toString());
      if (res["success"] == true) _loadReels(reset: true);
    } finally {
      _actionBusy = false;
    }
  }

  Future<void> _blockReelBackend(int index) async {
    if (_actionBusy) return;
    _actionBusy = true;
    _pauseCurrentReel();
    try {
      final res = await ReelsAPI.blockReel(_videos[index]["id"].toString());
      if (res["success"] == true) _loadReels(reset: true);
    } finally {
      _actionBusy = false;
    }
  }

  // =============================================================
  // UI BUILDER
  // =============================================================
  @override
  Widget build(BuildContext context) {
    if (_loading && _videos.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_videos.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off, color: Colors.white54, size: 60),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _loadReels(reset: true),
                child: const Text("Refresh Reels"),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageCtrl,
            scrollDirection: Axis.vertical,
            itemCount: _videos.length,
            onPageChanged: (i) async {
              _trackWatchTime(_current);
              _controllers[_current]?.pause(); // Pause old video

              setState(() {
                _current = i;
                _captionExpanded = false;
                // ✅ Only autoplay after user has tapped play at least once.
                _pausedByUser = !_userEverPlayed;
              });

              // ✅ Play new video only when allowed
              if (!_pausedByUser && widget.active && _routeActive) {
                _ctrl(i)?.play();
              }

              await _manageSlidingWindow(i);
              await _maybeLoadNextBatchOnScroll(i);
            },
            itemBuilder: (_, i) => _buildReel(i),
          ),

          if (widget.showBack)
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back,
                      color: Colors.white, size: 30),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),

          // ✅ NEW: Top Pause/Play Button
          _buildTopPauseControl(),

          // ✅ NEW: Top Mute Toggle (sound off by default)
          _buildTopMuteControl(),
        ],
      ),
    );
  }

  // ✅ Top Button Widget
  Widget _buildTopPauseControl() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      right: 15,
      child: InkWell(
        onTap: _togglePlayPause,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black38,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: Icon(
            _pausedByUser ? Icons.play_arrow : Icons.pause,
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }

  Widget _buildTopMuteControl() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 15,
      child: InkWell(
        onTap: _toggleMute,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black38,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: Icon(
            _muted ? Icons.volume_off : Icons.volume_up,
            color: Colors.white,
            size: 26,
          ),
        ),
      ),
    );
  }

  Widget _buildReel(int index) {
    final v = _videos[index];
    final c = _ctrl(index);

    return VisibilityDetector(
      key: ValueKey("reel_$index"),
      onVisibilityChanged: (info) {
        // ✅ STRICT CHECK: Only process if this is current reel AND widget is active
        if (index != _current) return;
        if (!widget.active || !_routeActive) {
          // ✅ Force pause if not active
          if (_bpReady(c) && c!.isPlaying() == true) c.pause();
          return;
        }

        // ✅ Only play if NOT paused by user AND widget is active AND route is active
        if (info.visibleFraction < 0.5) {
          if (_bpReady(c) && c!.isPlaying() == true) c.pause();
        } else {
          // Play only if ALL conditions met
          if (widget.active && !_pausedByUser && _routeActive && _userEverPlayed) {
            if (_bpReady(c) && c!.isPlaying() != true) c.play();
          }
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: () => _togglePlayPause(),
            onDoubleTap: () => _onLikeToggle(index),
            child: _buildPlayerOrThumb(index, v, c),
          ),
          _buildGradient(),
          _buildRightRail(index),
          _buildBottomLeftInfo(v),
          // ✅ REMOVED duplicate mute icon - _buildTopMuteControl() already shows it
          if (_showHeart) _buildHeartOverlay(),

          // Center Play Icon (Shows if paused)
          if (_pausedByUser && index == _current)
            Center(
              child: Icon(
                Icons.play_circle_fill,
                size: 86,
                color: Colors.white.withOpacity(0.55),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlayerOrThumb(int index, Map v, BetterPlayerController? c) {
    final t = _absUrlIfNeeded(_thumb(v));

    if (c == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (t.isNotEmpty) Image.network(t, fit: BoxFit.cover),
          const Center(child: CircularProgressIndicator(color: Colors.white30)),
        ],
      );
    }

    final ready = (c.isVideoInitialized() ?? false);

    return Stack(
      fit: StackFit.expand,
      children: [
        BetterPlayer(controller: c),

        if (!ready)
          const Center(child: CircularProgressIndicator(color: Colors.white30)),

        // Paused state thumbnail overlay
        if (_pausedByUser && index == _current && t.isNotEmpty)
          Image.network(t, fit: BoxFit.cover),
      ],
    );
  }

  Widget _buildGradient() => Positioned.fill(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.black.withOpacity(0.6),
            Colors.transparent,
            Colors.black.withOpacity(0.4),
          ],
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
        ),
      ),
    ),
  );

  // ✅ REMOVED _buildMuteIcon() - using _buildTopMuteControl() instead

  Widget _buildHeartOverlay() => Center(
    child: ScaleTransition(
      scale: Tween(begin: 0.7, end: 1.2).animate(_heartAnim),
      child: const Icon(Icons.favorite, color: Colors.white70, size: 110),
    ),
  );

  Widget _buildRightRail(int index) {
    final v = _videos[index];
    final isSub = v["is_subscribed"] == true;

    return Positioned(
      right: 10,
      bottom: 20,
      child: SizedBox(
        width: _railWidth,
        child: Column(
          children: [
            _railIcon(
              icon: v["is_liked"] == true
                  ? Icons.favorite
                  : Icons.favorite_border,
              label: _asInt(v["likes"]).toString(),
              color: v["is_liked"] == true ? gradientStart : Colors.white,
              onTap: () => _onLikeToggle(index),
            ),
            _railIcon(
              icon: Icons.comment,
              label: _asInt(v["comments"]).toString(),
              color: Colors.white,
              onTap: () {
                _pauseCurrentReel();
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (_) => ReelCommentsSheet(
                    reelId: _asInt(v["id"]),
                    initialCount: _asInt(v["comments"]),
                  ),
                ).then((_) => _resumeCurrentReel());
              },
            ),
            _railIcon(
              icon: Icons.share,
              label: "Share",
              color: Colors.white,
              onTap: () {
                _pauseCurrentReel();
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (_) => ReelShareSheet(
                    reelId: v["id"].toString(),
                    reelUrl: _absUrlIfNeeded(_urlFull(v)),
                  ),
                ).then((_) => _resumeCurrentReel());
              },
            ),
            _railIcon(
              icon: Icons.more_horiz,
              label: "",
              color: Colors.white,
              onTap: () => _showMoreMenu(index),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: _openUpload,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient:
                  LinearGradient(colors: [gradientStart, gradientEnd]),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 30),
              ),
            ),
            const SizedBox(height: 15),
            InkWell(
              onTap: () => _toggleSubscribe(v),
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: isSub ? gradientStart : Colors.white, width: 1.5),
                ),
                child: Icon(
                  isSub
                      ? Icons.notifications_active
                      : Icons.notifications_none,
                  color: isSub ? gradientStart : Colors.white,
                ),
              ),
            ),
            Text(
              _asInt(v["subscriber_count"]).toString(),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _railIcon({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          IconButton(
            icon: Icon(icon, color: color, size: _railIconSize),
            onPressed: onTap,
          ),
          if (label.isNotEmpty)
            Text(
              label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomLeftInfo(Map v) {
    final username = (v["username"] ?? v["user_name"] ?? "User").toString();
    final avatar = _absUrlIfNeeded((v["user_avatar"] ?? "").toString());
    final caption = (v["caption"] ?? v["title"] ?? "").toString();

    return Positioned(
      left: 15,
      bottom: 25,
      right: 90,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _openProfile(v),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage:
                  avatar.isNotEmpty ? NetworkImage(avatar) : null,
                  backgroundColor: Colors.white24,
                  child: avatar.isEmpty
                      ? const Icon(Icons.person, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 10),
                Text(
                  "@$username",
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (caption.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() => _captionExpanded = !_captionExpanded),
              child: Text(
                caption,
                maxLines: _captionExpanded ? 10 : 2,
                overflow: TextOverflow.ellipsis,
                style:
                GoogleFonts.poppins(color: Colors.white, fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }

  void _openUpload() {
    _pauseCurrentReel();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NewReelUploadPage()),
    ).then((res) {
      if (res == true) _loadReels(reset: true);
      _resumeCurrentReel();
    });
  }

  void _openProfile(Map v) {
    final uid = (v["user_id"] ?? "").toString();
    if (uid.isNotEmpty) {
      _pauseCurrentReel();
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProfilePage(userId: uid)),
      ).then((_) => _resumeCurrentReel());
    }
  }

  void _showMoreMenu(int index) {
    _pauseCurrentReel();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_off, color: Colors.white),
              title: const Text("Hide this reel",
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _hideReelBackend(index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.red),
              title:
              const Text("Block User", style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _blockReelBackend(index);
              },
            ),
          ],
        ),
      ),
    ).then((_) => _resumeCurrentReel());
  }
}