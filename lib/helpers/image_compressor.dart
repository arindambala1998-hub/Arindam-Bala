// lib/helpers/image_compressor.dart
import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class ImageCompressor {
  /// Compress any image file
  static Future<File?> compress(File file) async {
    try {
      final dir = await getTemporaryDirectory();
      final targetPath = p.join(
        dir.path,
        "${DateTime.now().millisecondsSinceEpoch}.jpg",
      );

      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: 70,          // lower = more compression
        minWidth: 600,
        minHeight: 600,
      );

      if (result == null) return null;

      return File(result.path);
    } catch (e) {
      print("Compression Error: $e");
      return file; // fallback
    }
  }
}
