import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:troonky_link/services/feed_api.dart';
import 'package:troonky_link/helpers/media_helper.dart';
import 'package:video_player/video_player.dart';

const Color troonkyColor = Color(0xFF333399);

const int maxTextLength = 1000;
const int maxImages = 10;

// ✅ Only size-based limit (no duration limit)
const int maxVideoMB = 20;
const int maxVideoBytes = maxVideoMB * 1024 * 1024;

class NewPostPage extends StatefulWidget {
  const NewPostPage({super.key});

  @override
  State<NewPostPage> createState() => _NewPostPageState();
}

class _NewPostPageState extends State<NewPostPage> {
  final TextEditingController _descCtrl = TextEditingController();

  final List<File> _images = [];
  File? _videoFile;
  File? _videoThumb; // preview only
  VideoPlayerController? _videoCtrl;

  bool _loading = false;

  // Cursor for image carousel
  final PageController _pageCtrl = PageController();
  int _pageIndex = 0;

  // ================= INIT =================
  @override
  void initState() {
    super.initState();
    _restoreDraft();
    _descCtrl.addListener(() {
      _saveDraft();
      if (mounted) setState(() {}); // live counter
    });
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _disposeVideoPreview();
    _pageCtrl.dispose();
    super.dispose();
  }

  // ================= DRAFT =================
  Future<void> _saveDraft() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString("draft_text", _descCtrl.text);
    } catch (_) {}
  }

  Future<void> _restoreDraft() async {
    try {
      final p = await SharedPreferences.getInstance();
      _descCtrl.text = p.getString("draft_text") ?? "";
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _clearDraft() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove("draft_text");
    } catch (_) {}
  }

  bool get _hasContent =>
      _descCtrl.text.trim().isNotEmpty || _images.isNotEmpty || _videoFile != null;

  // ================= IMAGE PICK (MULTIPLE) =================
  Future<void> _pickImages() async {
    if (_loading) return;

    if (_images.length >= maxImages) {
      _snack("Max $maxImages photos allowed", error: true);
      return;
    }

    final files = await MediaHelper.pickMultipleCompressedImages();
    if (!mounted || files.isEmpty) return;

    // ✅ switching to images => dispose video preview/controller
    _disposeVideoPreview();

    // ✅ enforce max 10
    final remaining = maxImages - _images.length;
    final toAdd = files.take(remaining).toList();

    setState(() {
      _videoFile = null;
      _videoThumb = null;
      _images.addAll(toAdd);
      _pageIndex = 0;
    });

    if (files.length > remaining) {
      _snack("Only $maxImages photos allowed. Extra photos were skipped.", error: false);
    }
  }

  // ================= VIDEO PICK (SIZE VALIDATION + THUMB) =================
  Future<void> _pickVideo() async {
    if (_loading) return;

    final file = await MediaHelper.pickFeedVideo();
    if (!mounted || file == null) return;

    // ✅ validate size (ONLY)
    int bytes = 0;
    try {
      bytes = await file.length();
    } catch (_) {
      _snack("Could not read video file", error: true);
      return;
    }

    if (bytes > maxVideoBytes) {
      _snack("Video must be under ${maxVideoMB}MB", error: true);
      return;
    }

    // ✅ switching to video => clear images
    setState(() {
      _images.clear();
      _pageIndex = 0;
    });

    // ✅ dispose old controller before creating new
    _disposeVideoPreview();

    // Initialize video player for preview
    final ctrl = VideoPlayerController.file(file);
    try {
      await ctrl.initialize();
    } catch (_) {
      await ctrl.dispose();
      if (!mounted) return;
      _snack("Video preview failed", error: true);
      return;
    }

    // ✅ generate thumb (preview only, best effort)
    File? thumb;
    try {
      thumb = await MediaHelper.generateVideoThumbnail(file);
    } catch (_) {
      thumb = null;
    }

    if (!mounted) {
      await ctrl.dispose();
      return;
    }

    setState(() {
      _videoCtrl = ctrl;
      _videoFile = file;
      _videoThumb = thumb;
    });
  }

  void _disposeVideoPreview() {
    final c = _videoCtrl;
    _videoCtrl = null;

    try {
      c?.pause();
    } catch (_) {}
    try {
      c?.dispose();
    } catch (_) {}

    _videoFile = null;
    _videoThumb = null;
  }

  // ================= SUBMIT =================
  Future<void> _submitPost() async {
    if (_loading) return;

    final desc = _descCtrl.text.trim();

    if (desc.isEmpty && _images.isEmpty && _videoFile == null) {
      _snack("Write something or add media", error: true);
      return;
    }

    if (desc.length > maxTextLength) {
      _snack("Text max $maxTextLength characters", error: true);
      return;
    }

    // ✅ enforce max images again (safety)
    if (_images.length > maxImages) {
      _snack("Max $maxImages photos allowed", error: true);
      return;
    }

    // ✅ validate video size again (safety)
    if (_videoFile != null) {
      try {
        final bytes = await _videoFile!.length();
        if (bytes > maxVideoBytes) {
          _snack("Video must be under ${maxVideoMB}MB", error: true);
          return;
        }
      } catch (_) {
        _snack("Could not read video file", error: true);
        return;
      }
    }

    setState(() => _loading = true);

    try {
      await FeedAPI.createPost(
        description: desc,
        postType: _videoFile != null
            ? "video"
            : _images.isNotEmpty
            ? "image"
            : "text",
        mediaFiles: _images.isNotEmpty ? _images : null,
        mediaFile: _videoFile,
        videoThumbFile: _videoThumb,
      );

      await _clearDraft();

      if (!mounted) return;
      HapticFeedback.lightImpact();
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _snack("Post failed. Try again.", error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ================= UX: CONFIRM EXIT =================
  Future<bool> _confirmExitIfNeeded() async {
    if (!_hasContent || _loading) return true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Discard post?"),
        content: const Text("You have an unfinished post. Do you want to discard it?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "Discard",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    return ok ?? false;
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    final count = _descCtrl.text.length;

    return WillPopScope(
      onWillPop: _confirmExitIfNeeded,
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 1,
          centerTitle: true,
          title: const Text(
            "Create Post",
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final ok = await _confirmExitIfNeeded();
              if (ok && mounted) Navigator.pop(context, false);
            },
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _loading
                  ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
                  : TextButton(
                onPressed: _submitPost,
                child: const Text(
                  "POST",
                  style: TextStyle(
                    color: troonkyColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            )
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _userHeader(),
              const SizedBox(height: 12),
              Card(
                elevation: 1.5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  child: Column(
                    children: [
                      TextField(
                        controller: _descCtrl,
                        maxLength: maxTextLength,
                        maxLines: null,
                        minLines: 4,
                        textInputAction: TextInputAction.newline,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(maxTextLength),
                          // ✅ avoid weird control chars
                          FilteringTextInputFormatter.deny(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]')),
                        ],
                        decoration: const InputDecoration(
                          hintText: "What's on your mind?  #hashtag  @mention",
                          border: InputBorder.none,
                          counterText: "",
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          "$count / $maxTextLength",
                          style: TextStyle(
                            fontSize: 12,
                            color: count > maxTextLength ? Colors.red : Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_images.isNotEmpty) _imageCarousel(),
              if (_videoCtrl != null) _videoPreview(),
              const SizedBox(height: 10),
              _rules(),
              const SizedBox(height: 60),
            ],
          ),
        ),
        bottomNavigationBar: _toolbar(),
      ),
    );
  }

  Widget _userHeader() {
    return Row(
      children: [
        const CircleAvatar(
          radius: 22,
          backgroundColor: troonkyColor,
          child: Icon(Icons.person, color: Colors.white),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            "Posting as You",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        if (_descCtrl.text.trim().isNotEmpty && !_loading)
          TextButton(
            onPressed: () async {
              setState(() => _descCtrl.clear());
              await _clearDraft();
              if (mounted) _snack("Draft cleared");
            },
            child: const Text(
              "Clear draft",
              style: TextStyle(color: troonkyColor, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }

  // ================= IMAGE CAROUSEL =================
  Widget _imageCarousel() {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 280,
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageCtrl,
              onPageChanged: (i) => setState(() => _pageIndex = i),
              itemCount: _images.length,
              itemBuilder: (_, i) => Image.file(
                _images[i],
                fit: BoxFit.cover,
                width: double.infinity,
                gaplessPlayback: true,
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  "${_pageIndex + 1}/${_images.length} • ${_images.length} photos",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Positioned(
              right: 10,
              top: 10,
              child: _closeBtn(() => setState(() => _images.clear())),
            ),
            // ✅ remove current image (fast UX)
            if (_images.length > 1)
              Positioned(
                right: 10,
                bottom: 10,
                child: _chipButton(
                  icon: Icons.delete_outline,
                  label: "Remove",
                  onTap: () {
                    final idx = _pageIndex.clamp(0, _images.length - 1);
                    setState(() {
                      _images.removeAt(idx);
                      _pageIndex = 0;
                      _pageCtrl.jumpToPage(0);
                    });
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ================= VIDEO =================
  Widget _videoPreview() {
    final c = _videoCtrl!;
    final thumb = _videoThumb;

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (thumb != null && !(c.value.isPlaying))
                  Image.file(thumb, fit: BoxFit.cover, gaplessPlayback: true),
                VideoPlayer(c),
              ],
            ),
          ),
          Positioned(
            right: 10,
            top: 10,
            child: _closeBtn(() {
              _disposeVideoPreview();
              setState(() {});
            }),
          ),
          Positioned.fill(
            child: Center(
              child: IconButton(
                icon: Icon(
                  c.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                  color: Colors.white70,
                  size: 64,
                ),
                onPressed: () {
                  if (c.value.isPlaying) {
                    c.pause();
                  } else {
                    c.play();
                  }
                  setState(() {});
                },
              ),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                "Max ${maxVideoMB}MB",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= TOOLBAR =================
  Widget _toolbar() => Container(
    padding: EdgeInsets.only(
      left: 16,
      right: 16,
      top: 10,
      bottom: MediaQuery.of(context).viewInsets.bottom + 12,
    ),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Colors.grey.shade300)),
    ),
    child: Row(
      children: [
        const Text("Add to your post", style: TextStyle(fontWeight: FontWeight.w700)),
        const Spacer(),
        IconButton(
          tooltip: "Add photos",
          icon: const Icon(Icons.image, color: Colors.green),
          onPressed: _loading || _videoFile != null ? null : _pickImages,
        ),
        IconButton(
          tooltip: "Add video",
          icon: const Icon(Icons.videocam, color: Colors.red),
          onPressed: _loading || _images.isNotEmpty ? null : _pickVideo,
        ),
      ],
    ),
  );

  // ================= RULES =================
  Widget _rules() => Padding(
    padding: const EdgeInsets.only(left: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text("• Multiple photos allowed (max 10)"),
        Text("• Video max 20MB (MP4, MOV, WebM)"),
        Text("• Text ≤ 1000 characters"),
        Text("• Images auto-compressed to WebP"),
      ],
    ),
  );

  Widget _closeBtn(VoidCallback onTap) => GestureDetector(
    onTap: _loading ? null : onTap,
    child: const CircleAvatar(
      radius: 16,
      backgroundColor: Colors.black54,
      child: Icon(Icons.close, size: 18, color: Colors.white),
    ),
  );

  Widget _chipButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? Colors.red : Colors.green,
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
