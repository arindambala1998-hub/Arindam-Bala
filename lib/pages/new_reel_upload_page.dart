// lib/pages/new_reel_upload_page.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:troonky_link/helpers/media_helper.dart';
import 'package:troonky_link/services/reels_api.dart';
import 'package:troonky_link/services/reels_refresh_bus.dart'; // ✅ ADD

class NewReelUploadPage extends StatefulWidget {
  const NewReelUploadPage({super.key});

  @override
  State<NewReelUploadPage> createState() => _NewReelUploadPageState();
}

class _NewReelUploadPageState extends State<NewReelUploadPage> {
  final TextEditingController _captionCtrl = TextEditingController();

  File? _videoFile;
  VideoPlayerController? _videoController;

  bool _isPlaying = false;
  bool _uploading = false;
  double _progress = 0.0;

  String _privacy = "public"; // public | friends

  static const int maxCaption = 250;
  // ✅ Reels rules (Troonky): portrait only + max 50 seconds
  static const int maxSeconds = 50;

  // Troonky colors
  final Color gradientStart = const Color(0xFFFF00CC);
  final Color gradientEnd = const Color(0xFF333399);

  @override
  void initState() {
    super.initState();
    _captionCtrl.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _captionCtrl.dispose();
    super.dispose();
  }

  // ==========================
  // Helpers
  // ==========================
  String _asString(dynamic v) => (v ?? "").toString().trim();

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  /// ✅ backend response থেকে reelId বের করা (many shapes safe)
  String _extractReelId(Map<String, dynamic> res) {
    final direct = _asString(res["reel_id"] ?? res["id"] ?? res["reelId"]);
    if (direct.isNotEmpty) return direct;

    final data = _asMap(res["data"]);
    final dataId = _asString(data["reel_id"] ?? data["id"] ?? data["reelId"]);
    if (dataId.isNotEmpty) return dataId;

    final reel = _asMap(res["reel"]);
    final reelId = _asString(reel["reel_id"] ?? reel["id"] ?? reel["reelId"]);
    if (reelId.isNotEmpty) return reelId;

    return "";
  }

  // ==========================
  // Pick video
  // ==========================
  Future<void> _pickVideo() async {
    if (_uploading) return;

    await _removeVideo(); // safe cleanup

    final File? picked = await MediaHelper.pickVideo();
    if (!mounted) return;

    if (picked == null) return; // user canceled

    if (!picked.existsSync()) {
      _snack("Video file not found.", isError: true);
      return;
    }

    setState(() => _videoFile = picked);
    await _initVideoPlayer(picked);
  }

  Future<void> _initVideoPlayer(File file) async {
    final old = _videoController;
    _videoController = null;
    await old?.dispose();

    final ctrl = VideoPlayerController.file(file);
    _videoController = ctrl;

    try {
      await ctrl.initialize();
      if (!mounted) return;

      // ✅ Enforce portrait (vertical) videos only
      // video_player provides the decoded size once initialized.
      final sz = ctrl.value.size;
      if (sz.width > 0 && sz.height > 0) {
        final isPortrait = sz.height >= sz.width;
        if (!isPortrait) {
          _snack(
            "Only vertical (portrait) videos are allowed for Reels.",
            isError: true,
          );
          await _removeVideo();
          return;
        }
      }

      final dur = ctrl.value.duration;
      if (dur.inSeconds > maxSeconds) {
        _snack(
          "Max $maxSeconds seconds allowed. Your video is ${dur.inSeconds}s.",
          isError: true,
        );
        await _removeVideo();
        return;
      }

      await ctrl.setLooping(true);
      await ctrl.play();

      if (!mounted) return;
      setState(() => _isPlaying = true);
    } catch (e) {
      if (!mounted) return;
      _snack("Video load failed: $e", isError: true);
      await _removeVideo();
    }
  }

  void _togglePlay() {
    final c = _videoController;
    if (c == null || !c.value.isInitialized) return;
    if (_uploading) return;

    setState(() {
      if (c.value.isPlaying) {
        c.pause();
        _isPlaying = false;
      } else {
        c.play();
        _isPlaying = true;
      }
    });
  }

  Future<void> _removeVideo() async {
    final old = _videoController;
    _videoController = null;

    await old?.pause();
    await old?.dispose();

    if (!mounted) return;
    setState(() {
      _videoFile = null;
      _isPlaying = false;
      _progress = 0.0;
    });
  }

  // ==========================
  // Upload
  // ==========================
  bool get _captionOk => _captionCtrl.text.trim().length <= maxCaption;

  bool get _readyToUpload => _videoFile != null && !_uploading && _captionOk;

  Future<void> _upload() async {
    if (!_readyToUpload) return;

    final file = _videoFile!;
    final caption = _captionCtrl.text.trim();

    setState(() {
      _uploading = true;
      _progress = 0.0;
    });

    // pause preview
    _videoController?.pause();
    setState(() => _isPlaying = false);

    try {
      final res = await ReelsAPI.uploadReel(
        caption: caption.isEmpty ? null : caption,
        privacy: _privacy,
        videoFile: file,
        onProgress: (sent, total) {
          if (!mounted) return;
          if (total <= 0) {
            setState(() => _progress = 0.0);
            return;
          }
          final p = sent / total;
          setState(() => _progress = p.isNaN ? 0.0 : p.clamp(0.0, 1.0));
        },
      );

      if (!mounted) return;

      final ok = res["success"] == true || res["status"] == true;
      if (ok) {
        final reelId = _extractReelId(res);
        // ignore: avoid_print
        print("✅ Uploaded reelId=$reelId (privacy=$_privacy)");

        _snack("Reel uploaded 🎉 Processing started.");

        // ✅ KEY: upload success => app-wide refresh signal
        ReelsRefreshBus.bump();

        // ✅ keep old behaviour (HomePageShortVideo expects `true`)
        Navigator.pop(context, true);
        return;
      }

      throw Exception(res["message"] ?? "Upload failed");
    } catch (e) {
      if (!mounted) return;
      _snack(
        e.toString().replaceAll("Exception:", "").trim(),
        isError: true,
      );
    } finally {
      if (!mounted) return;
      setState(() => _uploading = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ==========================
  // UI
  // ==========================
  @override
  Widget build(BuildContext context) {
    final ready = _readyToUpload;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0.6,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text(
          "New Reel",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: ready ? _upload : null,
            child: _uploading
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : Text(
              "Post",
              style: TextStyle(
                fontSize: 16,
                color: ready ? gradientEnd : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Caption
          TextField(
            controller: _captionCtrl,
            maxLength: maxCaption,
            maxLines: 3,
            enabled: !_uploading,
            decoration: InputDecoration(
              hintText: "Write a caption… #vibes #troonky",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Privacy
          Row(
            children: [
              const Icon(Icons.lock_outline, size: 20),
              const SizedBox(width: 8),
              const Text("Privacy"),
              const Spacer(),
              DropdownButton<String>(
                value: _privacy,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: "public", child: Text("Public")),
                  DropdownMenuItem(value: "friends", child: Text("Friends")),
                ],
                onChanged: _uploading ? null : (v) => setState(() => _privacy = v!),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Video area
          _videoFile == null ? _uploadPlaceholder() : _videoPreview(),

          // Upload progress
          if (_uploading) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: (_progress <= 0) ? null : _progress,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              (_progress > 0)
                  ? "Uploading ${(100 * _progress).toStringAsFixed(0)}%"
                  : "Uploading…",
              style: const TextStyle(color: Colors.grey),
            ),
          ],

          const SizedBox(height: 30),

          // Bottom Upload Button
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: ready ? _upload : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: gradientEnd,
                disabledBackgroundColor: Colors.grey.shade400,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _uploading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                "Share Reel",
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================
  // Widgets
  // ==========================
  Widget _uploadPlaceholder() {
    return GestureDetector(
      onTap: _pickVideo,
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: gradientEnd.withOpacity(0.4), width: 1.6),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [gradientStart, gradientEnd]),
              ),
              child: const Icon(Icons.video_library, size: 36, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Text(
              "Tap to select a video",
              style: TextStyle(color: gradientEnd, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              "Max $maxSeconds seconds",
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _videoPreview() {
    final c = _videoController;

    if (c == null || !c.value.isInitialized) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: c.value.aspectRatio == 0 ? (9 / 16) : c.value.aspectRatio,
            child: VideoPlayer(c),
          ),
        ),

        // tap to play/pause overlay
        Positioned.fill(
          child: GestureDetector(
            onTap: _togglePlay,
            child: Container(
              color: Colors.transparent,
              child: (!_isPlaying)
                  ? const Center(
                child: Icon(Icons.play_arrow, size: 56, color: Colors.white),
              )
                  : const SizedBox.shrink(),
            ),
          ),
        ),

        // remove button
        Positioned(
          top: 10,
          right: 10,
          child: InkWell(
            onTap: _uploading ? null : () => _removeVideo(),
            child: CircleAvatar(
              radius: 14,
              backgroundColor: Colors.black54,
              child: Icon(
                Icons.close,
                size: 16,
                color: _uploading ? Colors.white30 : Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
