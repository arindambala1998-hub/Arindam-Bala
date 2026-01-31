// lib/helpers/share_helper.dart

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

class ShareHelper {
  // ------------------------------------------------
  // 🔗 COPY LINK TO CLIPBOARD
  // ------------------------------------------------
  static Future<void> copyLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
  }

  // ------------------------------------------------
  // 📤 SHARE TEXT / URL
  // ------------------------------------------------
  static Future<void> shareText(String text) async {
    await Share.share(text);
  }

  // ------------------------------------------------
  // 📸 SHARE A SINGLE FILE (IMAGE/VIDEO)
  // ------------------------------------------------
  static Future<void> shareFile(String filePath) async {
    await Share.shareXFiles([XFile(filePath)]);
  }

  // ------------------------------------------------
  // 📂 SHARE MULTIPLE FILES
  // ------------------------------------------------
  static Future<void> shareFiles(List<String> filePaths) async {
    final List<XFile> files =
    filePaths.map((path) => XFile(path)).toList();

    await Share.shareXFiles(files);
  }
}
