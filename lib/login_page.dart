// lib/login_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:troonky_link/services/auth_api.dart';
import 'package:troonky_link/pages/wrapper.dart';

import 'signup_step1_auth.dart';
import 'forgot_password_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _idCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _obscure = true;

  // 🔥 Troonky official gradient
  final Color gradientStart = const Color(0xFFFF00CC);
  final Color gradientEnd = const Color(0xFF333399);

  @override
  void dispose() {
    _idCtrl.dispose();
    _passCtrl.dispose();
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

  // ============================================================
  // LOGIN
  // ============================================================
  Future<void> _login() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    try {
      final data = await AuthAPI.login(
        emailOrPhone: _idCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );

      if (data["error"] == true) {
        _toast(data["message"] ?? "Invalid credentials");
        return;
      }

      final token = (data["token"] ?? "").toString();
      final userId = (data["userId"] ?? "").toString();
      final userType = (data["userType"] ?? "user").toString().toLowerCase();
      final businessId = data["businessId"]?.toString();
      final refreshToken = data["refreshToken"]?.toString();

      if (token.isEmpty || userId.isEmpty) {
        _toast("Login failed. Invalid server response.");
        return;
      }

      await AuthAPI.saveAuthData(
        token: token,
        userId: userId,
        userType: userType,
        businessId: businessId,
        refreshToken: refreshToken, // Add this new line
      );

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const Wrapper()),
            (_) => false,
      );
    } catch (e) {
      _toast("Login failed. Please try again.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ============================================================
  // FIELD
  // ============================================================
  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    bool password = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextFormField(
        controller: ctrl,
        obscureText: password ? _obscure : false,
        validator: (v) {
          final val = (v ?? "").trim();
          if (val.isEmpty) return "Required";

          if (!password) {
            if (val.length < 3) return "Enter valid email or phone";
          } else {
            if (val.length < 6) return "Minimum 6 characters";
          }
          return null;
        },
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: gradientEnd),
          suffixIcon: password
              ? IconButton(
            icon: Icon(
              _obscure ? Icons.visibility_off : Icons.visibility,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
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

  Widget _gradButton() {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [gradientStart, gradientEnd]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: _loading ? null : _login,
        borderRadius: BorderRadius.circular(16),
        child: Center(
          child: _loading
              ? const CircularProgressIndicator(color: Colors.white)
              : const Text(
            "Login",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Text(
                  "Welcome to Troonky 👋",
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 35),

                _field(
                  ctrl: _idCtrl,
                  label: "Email or Phone",
                  icon: Icons.person_outline,
                ),

                _field(
                  ctrl: _passCtrl,
                  label: "Password",
                  icon: Icons.lock_outline,
                  password: true,
                ),

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ForgotPasswordPage(),
                        ),
                      );
                    },
                    child: const Text("Forgot Password?"),
                  ),
                ),

                const SizedBox(height: 10),
                _gradButton(),
                const SizedBox(height: 25),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Don’t have an account? "),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SignupStep1Auth(),
                        ),
                      ),
                      child: Text(
                        "Sign Up",
                        style: TextStyle(
                          color: gradientEnd,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
