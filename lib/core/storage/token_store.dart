import 'package:shared_preferences/shared_preferences.dart';

/// Single place to read/write auth tokens.
/// Uses multi-key fallback for backward compatibility.
class TokenStore {
  static const _primaryKey = 'token';
  static const _fallbackKeys = <String>[
    'token',
    'auth_token',
    'access_token',
    'jwt',
    'user_token',
  ];

  static Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in _fallbackKeys) {
      final v = (prefs.getString(k) ?? '').trim();
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  static Future<void> write(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_primaryKey, token.trim());
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in _fallbackKeys) {
      await prefs.remove(k);
    }
  }
}
