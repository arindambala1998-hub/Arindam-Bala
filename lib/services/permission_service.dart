// lib/services/permission_service.dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  /// Check single permission status
  static Future<PermissionStatus> checkPermission(Permission p) async {
    return p.status;
  }

  /// Request a single permission
  static Future<PermissionStatus> requestPermission(Permission p) async {
    final status = await p.request();
    return status;
  }

  /// Request multiple permissions at once
  /// Returns a map of Permission -> PermissionStatus
  static Future<Map<Permission, PermissionStatus>> requestAll(
      List<Permission> perms) async {
    return await perms.request();
  }

  /// Request camera + microphone + photos/files in a production-friendly way
  ///
  /// Usage: final ok = await PermissionService.requestMediaPermissions(context);
  /// returns true if all required permissions are granted.
  static Future<bool> requestMediaPermissions(BuildContext context) async {
    // Choose what you need. For Android 13+, READ_MEDIA_IMAGES / VIDEO are used
    final needed = <Permission>[
      Permission.camera,
      Permission.microphone,
      Permission.photos, // iOS / also maps to gallery
      Permission.storage, // Android (pre Android 13)
    ];

    final results = await requestAll(needed);

    // Helper to handle denied/permanentlyDenied states
    bool allGranted = true;
    for (final entry in results.entries) {
      final p = entry.key;
      final status = entry.value;

      if (status.isDenied) {
        allGranted = false;
      } else if (status.isPermanentlyDenied) {
        allGranted = false;
        // Show dialog to open app settings
        final open = await _showOpenSettingsDialog(context, p);
        if (open == true) {
          await openAppSettings();
        }
      }
    }

    return allGranted;
  }

  static Future<bool?> _showOpenSettingsDialog(
      BuildContext context, Permission p) {
    final name = _permissionToString(p);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$name permission required'),
        content: Text(
            'This permission is required for the feature to work. Please enable it in app settings.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open Settings')),
        ],
      ),
    );
  }

  static String _permissionToString(Permission p) {
    switch (p) {
      case Permission.camera:
        return 'Camera';
      case Permission.microphone:
        return 'Microphone';
      case Permission.photos:
        return 'Photos';
      case Permission.storage:
        return 'Storage';
      default:
        return 'Permission';
    }
  }

  /// Utility: open app settings
  static Future<bool> openAppSettings() => openAppSettings();
}
