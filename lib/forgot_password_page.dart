// lib/pages/forgot_password_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:troonky_link/services/auth_api.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;

  // 🔥 Troonky official gradient
  final Color gradientStart = const Color(0xFFFF00CC);
  final Color gradientEnd = const Color(0xFF333399);

  int _step = 1; // 1=email → 2=otp → 3=new password

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg, {bool error = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.redAccent : Colors.green,
      ),
    );
  }

  // ==========================================================
  // STEP 1: SEND OTP
  // ==========================================================
  Future<void> _sendOtp() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final r = await AuthAPI.sendOtp(email: _emailCtrl.text.trim());
      if (r["error"] == true) {
        _toast((r["message"] ?? "Failed to send OTP").toString());
        return;
      }

      _toast((r["message"] ?? "OTP sent").toString(), error: false);
      setState(() => _step = 2);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ==========================================================
  // STEP 2: VERIFY OTP
  // ==========================================================
  Future<void> _verifyOtp() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final r = await AuthAPI.verifyOtp(
        email: _emailCtrl.text.trim(),
        otp: _otpCtrl.text.trim(),
      );

      if (r["error"] == true) {
        _toast((r["message"] ?? "Invalid OTP").toString());
        return;
      }

      _toast((r["message"] ?? "OTP verified").toString(), error: false);

      // ✅ IMPORTANT: lock OTP & email in step-3 so user can't change it
      setState(() => _step = 3);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ==========================================================
  // STEP 3: RESET PASSWORD
  // ==========================================================
  Future<void> _resetPassword() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;

    final p1 = _newPassCtrl.text.trim();
    final p2 = _confirmPassCtrl.text.trim();

    if (p1 != p2) {
      _toast("Passwords do not match");
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final r = await AuthAPI.resetPassword(
        email: _emailCtrl.text.trim(),
        otp: _otpCtrl.text.trim(), // ✅ same verified OTP
        newPassword: p1,
      );

      if (r["error"] == true) {
        _toast((r["message"] ?? "Failed to reset password").toString());
        return;
      }

      _toast((r["message"] ?? "Password updated").toString(), error: false);

      if (!mounted) return;
      Navigator.pop(context); // back to login
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ==========================================================
  // UI HELPERS
  // ==========================================================
  Widget _gradButton({required String text, required VoidCallback onTap}) {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [gradientStart, gradientEnd]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: _loading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Center(
          child: _loading
              ? const CircularProgressIndicator(color: Colors.white)
              : Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _boxField({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    bool isPass = false,
    bool obscure = false,
    VoidCallback? toggle,
    TextInputType? keyboardType,
    bool enabled = true,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextFormField(
        controller: ctrl,
        enabled: enabled,
        obscureText: isPass ? obscure : false,
        keyboardType: keyboardType,
        validator: (v) {
          final val = (v ?? "").trim();
          if (val.isEmpty) return "Required";

          final l = label.toLowerCase();
          if (l.contains("email") && !val.contains("@")) {
            return "Enter valid email";
          }
          if (l.contains("otp")) {
            if (val.length != 6) return "Enter 6 digit OTP";
          }
          if (l.contains("password")) {
            if (val.length < 8) return "Minimum 8 characters";
          }
          return null;
        },
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: gradientEnd),
          suffixIcon: isPass
              ? IconButton(
            icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
            onPressed: toggle,
          )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // UI
  // ==========================================================
  @override
  Widget build(BuildContext context) {
    final title = _step == 1
        ? "Reset Password"
        : _step == 2
        ? "Verify OTP"
        : "Set New Password";

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: gradientEnd,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Text(
                  "Troonky Account Recovery",
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),

                // ✅ Email locked after step-1
                _boxField(
                  ctrl: _emailCtrl,
                  label: "Email",
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  enabled: _step == 1,
                ),

                if (_step >= 2)
                // ✅ OTP locked in step-3 (prevents Invalid OTP)
                  _boxField(
                    ctrl: _otpCtrl,
                    label: "OTP",
                    icon: Icons.verified_outlined,
                    keyboardType: TextInputType.number,
                    enabled: _step == 2,
                  ),

                if (_step == 3) ...[
                  _boxField(
                    ctrl: _newPassCtrl,
                    label: "New Password",
                    icon: Icons.lock_outline,
                    isPass: true,
                    obscure: _obscure1,
                    toggle: () => setState(() => _obscure1 = !_obscure1),
                  ),
                  _boxField(
                    ctrl: _confirmPassCtrl,
                    label: "Confirm Password",
                    icon: Icons.lock_reset_outlined,
                    isPass: true,
                    obscure: _obscure2,
                    toggle: () => setState(() => _obscure2 = !_obscure2),
                  ),
                ],

                const SizedBox(height: 8),

                if (_step == 1) _gradButton(text: "Send OTP", onTap: _sendOtp),
                if (_step == 2) _gradButton(text: "Verify OTP", onTap: _verifyOtp),
                if (_step == 3) _gradButton(text: "Update Password", onTap: _resetPassword),

                const SizedBox(height: 16),
                Text(
                  _step == 1
                      ? "We will send OTP to your email."
                      : _step == 2
                      ? "Enter the OTP you received."
                      : "Set a new password for your account.",
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.black54,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
