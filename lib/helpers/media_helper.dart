// lib/helpers/media_helper.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class MediaHelper {
  static final ImagePicker _picker = ImagePicker();

  // ✅ Reels max video duration (60s)
  static const int MAX_REEL_VIDEO_SECONDS = 60;

  // ✅ Feed max video duration (5 minutes)
  static const int MAX_FEED_VIDEO_SECONDS = 300;

  // -----------------------------------------------------------
  // 🖼️ Pick + Compress IMAGE (Single)
  // -----------------------------------------------------------
  static Future<File?> pickCompressedImage({bool camera = false}) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 100,
      );

      if (picked == null) return null;

      final tempDir = await getTemporaryDirectory();
      final targetPath =
          "${tempDir.path}/IMG_${DateTime.now().millisecondsSinceEpoch}.jpg";

      final compressed = await FlutterImageCompress.compressAndGetFile(
        picked.path,
        targetPath,
        minWidth: 1080,
        minHeight: 1080,
        quality: 70,
      );

      return compressed != null ? File(compressed.path) : File(picked.path);
    } catch (e) {
      debugPrint("❌ Image compress error: $e");
      return null;
    }
  }

  // -----------------------------------------------------------
  // 🖼️ Pick + Compress MULTIPLE IMAGES (Carousel)
  // -----------------------------------------------------------
  static Future<List<File>> pickMultipleCompressedImages() async {
    try {
      final List<XFile> picked = await _picker.pickMultiImage(
        imageQuality: 100,
      );

      if (picked.isEmpty) return [];

      final tempDir = await getTemporaryDirectory();
      final out = <File>[];

      for (final x in picked) {
        final targetPath =
            "${tempDir.path}/IMG_${DateTime.now().millisecondsSinceEpoch}_${x.name}.jpg";

        final compressed = await FlutterImageCompress.compressAndGetFile(
          x.path,
          targetPath,
          minWidth: 1080,
          minHeight: 1080,
          quality: 70,
        );

        out.add(compressed != null ? File(compressed.path) : File(x.path));
      }

      return out;
    } catch (e) {
      debugPrint("❌ Multi image pick error: $e");
      return [];
    }
  }

  // -----------------------------------------------------------
  // 🎥 PICK VIDEO (REELS)  ✅ THIS FIXES YOUR ERROR
  // - This method exists so ReelsUploadHelper can call it.
  // - Hard limit 60 seconds
  // -----------------------------------------------------------
  static Future<File?> pickVideo({bool camera = false}) async {
    return pickReelVideo(camera: camera);
  }

  // -----------------------------------------------------------
  // 🎥 PICK REEL VIDEO (60s hard)
  // -----------------------------------------------------------
  static Future<File?> pickReelVideo({bool camera = false}) async {
    try {
      final XFile? picked = await _picker.pickVideo(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        maxDuration: const Duration(seconds: MAX_REEL_VIDEO_SECONDS),
      );

      if (picked == null) return null;
      return File(picked.path);
    } catch (e) {
      debugPrint("❌ Reel video pick error: $e");
      return null;
    }
  }

  // -----------------------------------------------------------
  // 🎥 PICK FEED VIDEO (5 minutes hard)
  // -----------------------------------------------------------
  static Future<File?> pickFeedVideo({bool camera = false}) async {
    try {
      final XFile? picked = await _picker.pickVideo(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        maxDuration: const Duration(seconds: MAX_FEED_VIDEO_SECONDS),
      );

      if (picked == null) return null;
      return File(picked.path);
    } catch (e) {
      debugPrint("❌ Feed video pick error: $e");
      return null;
    }
  }

  // -----------------------------------------------------------
  // 🖼️✅ GENERATE VIDEO THUMBNAIL (Feed)
  // - Returns a File (jpg) saved in temp directory
  // - Best-effort: can return null if fails
  // -----------------------------------------------------------
  static Future<File?> generateVideoThumbnail(File videoFile) async {
    try {
      final dir = await getTemporaryDirectory();

      final thumbPath = await VideoThumbnail.thumbnailFile(
        video: videoFile.path,
        thumbnailPath: dir.path,
        imageFormat: ImageFormat.JPEG,
        maxHeight: 720, // good for feed thumbnail
        quality: 75,
      );

      if (thumbPath == null || thumbPath.trim().isEmpty) return null;
      final f = File(thumbPath);
      if (!await f.exists()) return null;
      return f;
    } catch (e) {
      debugPrint("❌ Thumbnail generate error: $e");
      return null;
    }
  }
}
