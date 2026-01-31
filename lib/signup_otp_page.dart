import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:troonky_link/helpers/api_helper.dart';

class SignupOtpPage extends StatefulWidget {
  final String email;
  const SignupOtpPage({super.key, required this.email});

  @override
  State<SignupOtpPage> createState() => _SignupOtpPageState();
}

class _SignupOtpPageState extends State<SignupOtpPage> {
  final ApiHelper _api = ApiHelper();

  final List<TextEditingController> _otpCtrls =
  List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _loading = false;

  int _secondsLeft = 60;
  Timer? _timer;

  // 🔥 Troonky Official Gradient
  final Color gradientStart = const Color(0xFFFF00CC);
  final Color gradientEnd = const Color(0xFF333399);

  String get _otp => _otpCtrls.map((c) => c.text.trim()).join();
  bool get _otpComplete => _otp.length == 6 && !_otp.contains(RegExp(r'\s'));

  @override
  void initState() {
    super.initState();
    _startTimer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes.first.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in _otpCtrls) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _timer?.cancel();
    super.dispose();
  }

  // =====================================================
  // ⏱️ TIMER LOGIC
  // =====================================================
  void _startTimer() {
    setState(() => _secondsLeft = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 0) {
        t.cancel();
      } else {
        if (mounted) setState(() => _secondsLeft--);
      }
    });
  }

  // =====================================================
  // 🧠 HANDLE PASTE (6 digits)
  // =====================================================
  void _fillOtpFromPaste(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 6) return;

    for (int i = 0; i < 6; i++) {
      _otpCtrls[i].text = digits[i];
    }
    FocusScope.of(context).unfocus();
    setState(() {});
    _verifyOtp();
  }

  void _clearOtp() {
    for (final c in _otpCtrls) {
      c.clear();
    }
    _focusNodes.first.requestFocus();
    setState(() {});
  }

  // =====================================================
  // 🚀 VERIFY OTP
  // =====================================================
  Future<void> _verifyOtp() async {
    if (_loading) return;

    if (!_otpComplete) {
      _snack("Enter 6 digit OTP", isError: true);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    try {
      await _api.post("/auth/verify-otp", {
        "email": widget.email,
        "otp": _otp,
      });

      if (!mounted) return;
      _snack("Email verified successfully! 🚀", isError: false);

      Navigator.pushReplacementNamed(
        context,
        "/signup",
        arguments: widget.email,
      );
    } catch (e) {
      final msg = e.toString().replaceAll("Exception:", "").trim();
      _snack(msg.isEmpty ? "Invalid OTP" : msg, isError: true);
      _clearOtp();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // =====================================================
  // 🔄 RESEND OTP
  // =====================================================
  Future<void> _resendOtp() async {
    if (_loading) return;
    if (_secondsLeft > 0) return;

    setState(() => _loading = true);
    try {
      await _api.post("/auth/send-otp", {"email": widget.email});
      if (!mounted) return;
      _startTimer();
      _snack("OTP sent again to your email ✅", isError: false);
    } catch (_) {
      _snack("Failed to resend OTP", isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // =====================================================
  // OTP BOX
  // =====================================================
  Widget _otpBox(int i) {
    return SizedBox(
      width: 48,
      height: 58,
      child: RawKeyboardListener(
        focusNode: FocusNode(),
        onKey: (event) {
          if (event is RawKeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace) {
            if (_otpCtrls[i].text.isEmpty && i > 0) {
              _focusNodes[i - 1].requestFocus();
              _otpCtrls[i - 1].selection = TextSelection.fromPosition(
                TextPosition(offset: _otpCtrls[i - 1].text.length),
              );
            }
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _otpCtrls[i].text.isNotEmpty
                  ? gradientEnd.withValues(alpha: 0.50)
                  : Colors.grey.shade300,
              width: 1.2,
            ),
          ),
          child: TextField(
            controller: _otpCtrls[i],
            focusNode: _focusNodes[i],
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 1,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: gradientEnd,
            ),
            decoration: const InputDecoration(
              counterText: "",
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 14),
            ),
            onChanged: (v) {
              if (v.length > 1) {
                _fillOtpFromPaste(v);
                return;
              }

              if (v.isNotEmpty && i < 5) {
                _focusNodes[i + 1].requestFocus();
              }

              setState(() {});

              if (i == 5 && _otpComplete) {
                _verifyOtp();
              }
            },
          ),
        ),
      ),
    );
  }

  // =====================================================
  // UI
  // =====================================================
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    // ✅ responsive header height
    final double headerH = (top + 130).clamp(140, 175).toDouble();

    return Scaffold(
      backgroundColor: Colors.white,

      appBar: PreferredSize(
        preferredSize: Size.fromHeight(headerH),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [gradientStart, gradientEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(35)),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Icon(Icons.arrow_back_ios_new, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "Verify OTP",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Text(
                    "Verification Code",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 24, // safer for small screens
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // ✅ avoid overflow: limit lines + ellipsis
                  Text(
                    "Enter the 6-digit code sent to",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),

      // ✅ Scroll to avoid overflow with keyboard
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 18),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, _otpBox),
              ),

              const SizedBox(height: 14),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Tip: you can paste the full code",
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                  TextButton(
                    onPressed: _loading ? null : () => Navigator.pop(context),
                    child: Text(
                      "Change email",
                      style: TextStyle(
                        color: gradientEnd,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // ✅ button: proper gradient + ripple
              SizedBox(
                width: double.infinity,
                height: 56,
                child: AbsorbPointer(
                  absorbing: _loading || !_otpComplete,
                  child: Opacity(
                    opacity: (_loading || !_otpComplete) ? 0.55 : 1,
                    child: Material(
                      borderRadius: BorderRadius.circular(18),
                      elevation: 2,
                      child: InkWell(
                        onTap: _verifyOtp,
                        borderRadius: BorderRadius.circular(18),
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [gradientStart, gradientEnd]),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: gradientEnd.withValues(alpha: 0.25),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              )
                            ],
                          ),
                          child: Center(
                            child: _loading
                                ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              ),
                            )
                                : const Text(
                              "Verify & Continue",
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 22),

              Center(
                child: TextButton(
                  onPressed: (_secondsLeft == 0 && !_loading) ? _resendOtp : null,
                  child: Text(
                    _secondsLeft == 0 ? "Resend Code" : "Resend code in ${_secondsLeft}s",
                    style: TextStyle(
                      color: _secondsLeft == 0 ? gradientEnd : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
