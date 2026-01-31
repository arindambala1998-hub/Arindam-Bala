import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:troonky_link/helpers/media_helper.dart';
import 'package:troonky_link/services/reels_api.dart';

/// Helper class for picking & uploading Reels video
/// NOTE: No client-side compression (server handles it)
class ReelsUploadHelper {
  ReelsUploadHelper._(); // static-only class

  // ✅ Reels rules (kept in one place)
  static const int maxSeconds = 50;

  static Future<Map<String, dynamic>?> pickAndUploadReel({
    required BuildContext context,
    String caption = '',
    bool fromCamera = false,
  }) async {
    // 1) Pick video (NO compression)
    final File? video = await MediaHelper.pickVideo(camera: fromCamera);

    if (video == null) return null;

    // ✅ Client-side validation (fast) — portrait only + max 50s
    final ok = await _validateReelVideo(context, video);
    if (!ok) return null;

    // 2) Show loader (DON'T await)
    if (context.mounted) {
      _showLoader(context);
    }

    try {
      // 3) Upload
      final res = await ReelsAPI.uploadReel(
        videoFile: video,
        caption: caption,
      );

      // 4) Close loader
      if (context.mounted) _safePop(context);

      // 5) Success snackbar
      if (context.mounted) {
        _showSnack(
          context,
          message: "✅ Reel uploaded successfully",
          isError: false,
        );
      }

      return res;
    } catch (e) {
      if (context.mounted) _safePop(context);

      if (context.mounted) {
        _showSnack(
          context,
          message:
          "❌ Reel upload failed: ${e.toString().replaceAll('Exception:', '').trim()}",
          isError: true,
        );
      }
      return null;
    }
  }

  static Future<bool> _validateReelVideo(BuildContext context, File file) async {
    VideoPlayerController? ctrl;
    try {
      ctrl = VideoPlayerController.file(file);
      await ctrl.initialize();

      final sz = ctrl.value.size;
      if (sz.width > 0 && sz.height > 0 && sz.width > sz.height) {
        _showSnack(
          context,
          message: "❌ Only vertical (portrait) videos are allowed for Reels.",
          isError: true,
        );
        return false;
      }

      final dur = ctrl.value.duration;
      if (dur.inSeconds > maxSeconds) {
        _showSnack(
          context,
          message: "❌ Max $maxSeconds seconds allowed. Your video is ${dur.inSeconds}s.",
          isError: true,
        );
        return false;
      }

      return true;
    } catch (_) {
      // If we cannot read metadata, allow upload (server will validate).
      return true;
    } finally {
      try {
        await ctrl?.dispose();
      } catch (_) {}
    }
  }

  // ---------------- Fullscreen Loader ----------------
  static void _showLoader(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      useRootNavigator: true,
      builder: (_) {
        return const Center(
          child: SizedBox(
            width: 70,
            height: 70,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------- Safe pop dialog ----------------
  static void _safePop(BuildContext context) {
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) nav.pop();
  }

  // ---------------- SnackBar ----------------
  static void _showSnack(
      BuildContext context, {
        required String message,
        bool isError = false,
      }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
