// lib/pages/wrapper.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Wrapper extends StatefulWidget {
  const Wrapper({super.key});

  @override
  State<Wrapper> createState() => _WrapperState();
}

class _WrapperState extends State<Wrapper> {
  @override
  void initState() {
    super.initState();
    _decideNext();
  }

  // =============================================================
  // 🔍 DECIDE NEXT SCREEN (FINAL – LAUNCH SAFE)
  // =============================================================
  Future<void> _decideNext() async {
    // Small delay so first frame feels smooth
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final token = (prefs.getString('token') ?? '').trim();

    if (kDebugMode) {
      // ignore: avoid_print
      print("🟢 Wrapper token = $token");
    }

    if (!mounted) return;

    // NOT LOGGED IN → LOGIN
    if (token.isEmpty) {
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    // LOGGED IN → MAIN APP (Feed opens first now)
    Navigator.pushReplacementNamed(context, '/main_app');
  }

  // =============================================================
  // UI (Temporary loading screen)
  // =============================================================
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
