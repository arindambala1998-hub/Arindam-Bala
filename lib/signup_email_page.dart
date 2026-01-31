import 'package:flutter/material.dart';
import 'package:troonky_link/helpers/api_helper.dart';

class SignupEmailPage extends StatefulWidget {
  const SignupEmailPage({super.key});

  @override
  State<SignupEmailPage> createState() => _SignupEmailPageState();
}

class _SignupEmailPageState extends State<SignupEmailPage> {
  final TextEditingController _emailCtrl = TextEditingController();
  final FocusNode _emailFocus = FocusNode();

  final ApiHelper _api = ApiHelper();
  bool _loading = false;

  // 🔥 Troonky Official Gradient
  final Color gradientStart = const Color(0xFFFF00CC);
  final Color gradientEnd = const Color(0xFF333399);

  final RegExp _emailRegex = RegExp(r'^[\w\.-]+@([\w-]+\.)+[a-zA-Z]{2,}$');

  bool get _isEmailValid {
    final email = _emailCtrl.text.trim();
    return email.isNotEmpty && _emailRegex.hasMatch(email);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  // ===========================================================
  // 🚀 SEND OTP (PRODUCTION)
  // ===========================================================
  Future<void> _sendOtp() async {
    if (_loading) return;

    final email = _emailCtrl.text.trim();

    if (!_isEmailValid) {
      _showSnack("Please enter a valid email", isError: true);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    try {
      final response = await _api.post("/auth/send-otp", {"email": email});

      if (!mounted) return;

      final msg = (response is Map && response["message"] != null)
          ? response["message"].toString()
          : "Verification code sent to $email";

      _showSnack(msg, isError: false);

      Navigator.pushNamed(
        context,
        "/signup-otp",
        arguments: email,
      );
    } catch (e) {
      final err = e.toString().replaceAll("Exception:", "").trim();
      _showSnack(err.isEmpty ? "OTP send failed" : err, isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
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

  // ===========================================================
  // UI
  // ===========================================================
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    // ✅ responsive header height (small phone safe)
    final double headerH = (top + 118).clamp(120, 150).toDouble();

    return Scaffold(
      backgroundColor: Colors.white,

      // ✅ Premium gradient header (no overflow)
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
                  // top row
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
                        "Create Account",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // ✅ prevent overflow by limiting lines
                  Text(
                    "Enter your email",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 24, // ✅ 26 -> 24 (safer on small phone)
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "We’ll send a 6-digit verification code",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),

      // ✅ ScrollView to avoid overflow on small screens / keyboard
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 18),

              // Email field
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: TextField(
                  controller: _emailCtrl,
                  focusNode: _emailFocus,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _sendOtp(),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: "example@email.com",
                    prefixIcon: Icon(Icons.email_rounded, color: gradientEnd),
                    suffixIcon: _emailCtrl.text.trim().isEmpty
                        ? null
                        : Icon(
                      _isEmailValid ? Icons.check_circle : Icons.error,
                      color: _isEmailValid ? Colors.green : Colors.redAccent,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              Text(
                _emailCtrl.text.trim().isEmpty
                    ? "Use a valid email to receive OTP"
                    : (_isEmailValid ? "Looks good ✅" : "Email format is invalid"),
                style: TextStyle(
                  color: _emailCtrl.text.trim().isEmpty
                      ? Colors.black54
                      : (_isEmailValid ? Colors.green : Colors.redAccent),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 26),

              // ✅ Continue button (proper gradient button)
              SizedBox(
                width: double.infinity,
                height: 56,
                child: AbsorbPointer(
                  absorbing: _loading || !_isEmailValid,
                  child: Opacity(
                    opacity: (_loading || !_isEmailValid) ? 0.55 : 1,
                    child: Material(
                      borderRadius: BorderRadius.circular(18),
                      elevation: 2,
                      child: InkWell(
                        onTap: _sendOtp,
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
                              "Continue",
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

              const SizedBox(height: 18),

              // Login link
              Center(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text("Already have an account? "),
                    GestureDetector(
                      onTap: () => Navigator.pushReplacementNamed(context, "/login"),
                      child: Text(
                        "Login",
                        style: TextStyle(
                          color: gradientEnd,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
