// lib/pages/video_fullscreen_page.dart
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoFullscreenPage extends StatefulWidget {
  final String url;
  final String? thumbUrl;
  final String? title;

  // ✅ ADD THIS
  final Map<String, String>? headers;

  const VideoFullscreenPage({
    super.key,
    required this.url,
    this.thumbUrl,
    this.title,
    this.headers, // ✅ ADD THIS
  });

  @override
  State<VideoFullscreenPage> createState() => _VideoFullscreenPageState();
}

class _VideoFullscreenPageState extends State<VideoFullscreenPage> {
  VideoPlayerController? _c;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final url = widget.url.trim();
      final isHls = url.toLowerCase().contains(".m3u8");

      final ctrl = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: widget.headers ?? const <String, String>{}, // ✅ AUTH HEADERS
        formatHint: isHls ? VideoFormat.hls : null, // ✅ HLS SUPPORT
      );

      _c = ctrl;

      await ctrl.initialize();
      await ctrl.setLooping(true);
      await ctrl.play();

      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  @override
  void dispose() {
    try {
      _c?.pause();
    } catch (_) {}
    _c?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;

    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title ?? "Video"),
      ),
      body: Center(
        child: _error
            ? const Text("Video failed to load", style: TextStyle(color: Colors.white))
            : (c == null || _loading)
            ? const CircularProgressIndicator()
            : GestureDetector(
          onTap: _togglePlay,
          child: AspectRatio(
            aspectRatio: (c.value.aspectRatio == 0) ? (16 / 9) : c.value.aspectRatio,
            child: VideoPlayer(c),
          ),
        ),
      ),
      floatingActionButton: (c == null || _loading || _error)
          ? null
          : FloatingActionButton(
        backgroundColor: Colors.white,
        onPressed: _togglePlay,
        child: Icon(
          c.value.isPlaying ? Icons.pause : Icons.play_arrow,
          color: Colors.black,
        ),
      ),
    );
  }
}
