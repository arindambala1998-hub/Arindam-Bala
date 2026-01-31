// lib/pages/splash_screen.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:troonky_link/widgets/troonky_logo.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  static const String _tagline = "Connect • Compete • Celebrate";
  int _visibleChars = 0;
  int _dotCount = 0;

  Timer? _textTimer;
  Timer? _redirectTimer;

  bool _navigated = false; // ✅ prevent double navigation

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);

    _textTimer = Timer.periodic(const Duration(milliseconds: 55), (timer) {
      if (!mounted) return;

      if (_visibleChars < _tagline.length) {
        setState(() => _visibleChars++);
      } else {
        setState(() => _dotCount = (_dotCount + 1) % 4);
      }
    });

    // ✅ safer: run after first frame + small delay (avoid init jank)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _redirectTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        _navigateNext();
      });
    });
  }

  // ============================================================
  // SAFE NAVIGATION LOGIC (handles corrupted SharedPrefs types)
  // ============================================================
  String _getStringSafe(SharedPreferences prefs, String key) {
    final v = prefs.get(key);
    if (v == null) return '';
    return v.toString();
  }

  Future<void> _navigateNext() async {
    if (!mounted || _navigated) return;
    _navigated = true;

    try {
      final prefs = await SharedPreferences.getInstance();

      // ✅ Read token safely (can be String/int/anything if previously saved wrong)
      final dynamic rawToken = prefs.get('token');

      String token = '';
      if (rawToken is String) {
        token = rawToken.trim();
      } else if (rawToken == null) {
        token = '';
      } else {
        // ⚠️ token key corrupted (int/bool/etc) -> remove it
        await prefs.remove('token');
        token = '';
      }

      if (kDebugMode) {
        // ignore: avoid_print
        print("🔵 Splash Debug ↓↓↓");
        // ignore: avoid_print
        print("rawTokenType = ${rawToken?.runtimeType}");
        // ignore: avoid_print
        print("Token = $token");
        // ignore: avoid_print
        print("=================================");
      }

      if (!mounted) return;

      if (token.isEmpty) {
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      Navigator.pushReplacementNamed(context, '/main_app');
    } catch (e) {
      // ✅ if prefs read fails, fallback to login (no crash)
      if (kDebugMode) {
        // ignore: avoid_print
        print("❌ PREFS READ ERROR => $e");
      }
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  void dispose() {
    _textTimer?.cancel();
    _redirectTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final angle = t * pi;

        final begin = Alignment(cos(angle), sin(angle));
        final end = Alignment(-cos(angle), -sin(angle));

        final color1 = Color.lerp(
          const Color(0xFF6A5AE0),
          const Color(0xFF9A7BFF),
          t,
        )!;

        final color2 = Color.lerp(
          const Color(0xFFE8E3FF),
          const Color(0xFFC7B9FF),
          1 - t,
        )!;

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: begin,
              end: end,
              colors: [color1, color2],
            ),
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _AnimatedLogo(progress: t),
                  const SizedBox(height: 18),
                  Opacity(
                    opacity: 0.95,
                    child: Text(
                      _visibleChars == 0
                          ? ""
                          : _tagline.substring(0, _visibleChars) +
                          (_visibleChars == _tagline.length
                              ? "." * _dotCount
                              : ""),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Opacity(
                    opacity: 0.85,
                    child: Text(
                      "Connecting to Troonky servers...",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.95),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AnimatedLogo extends StatelessWidget {
  final double progress;
  const _AnimatedLogo({required this.progress});

  @override
  Widget build(BuildContext context) {
    final glow = 0.25 + 0.25 * sin(progress * pi);

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.white.withOpacity(glow),
                blurRadius: 32,
                spreadRadius: 1,
              ),
            ],
          ),
          child: TroonkyLogo(size: 90, showText: true),
        ),
      ],
    );
  }
}
