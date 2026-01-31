import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:troonky_link/models/signup_data.dart';
import 'package:troonky_link/signup_step2_details.dart';

class SignupStep1Auth extends StatefulWidget {
  const SignupStep1Auth({super.key});

  @override
  State<SignupStep1Auth> createState() => _SignupStep1AuthState();
}

class _SignupStep1AuthState extends State<SignupStep1Auth> {
  final _formKey = GlobalKey<FormState>();
  final SignupData _formData = SignupData();

  final _idCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _rePassCtrl = TextEditingController();

  final _passFocus = FocusNode();
  final _rePassFocus = FocusNode();

  bool _obscure1 = true;
  bool _obscure2 = true;

  // 🔥 Troonky official gradient
  final Color gradientStart = const Color(0xFFFF00CC);
  final Color gradientEnd = const Color(0xFF333399);

  // live password rules
  bool _hasUpper = false;
  bool _hasLower = false;
  bool _hasNumber = false;
  bool _minLen = false;

  bool _emailInitialized = false;

  bool get _isBusiness => _formData.userType == "business";

  @override
  void initState() {
    super.initState();

    _passCtrl.addListener(_updatePasswordRules);
    _rePassCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _passCtrl.removeListener(_updatePasswordRules);
    _idCtrl.dispose();
    _passCtrl.dispose();
    _rePassCtrl.dispose();
    _passFocus.dispose();
    _rePassFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // OTP verification page থেকে verified email আসে (only once)
    if (_emailInitialized) return;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args == null) {
      Future.microtask(() {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, "/signup-email");
      });
      return;
    }

    String email = "";
    if (args is String) {
      email = args.trim();
    } else if (args is Map) {
      email = (args["email"] ?? "").toString().trim();
    }

    if (email.isEmpty) {
      Future.microtask(() {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, "/signup-email");
      });
      return;
    }

    _idCtrl.text = email;
    _emailInitialized = true;
  }

  void _updatePasswordRules() {
    final v = _passCtrl.text;

    final upper = RegExp(r'[A-Z]').hasMatch(v);
    final lower = RegExp(r'[a-z]').hasMatch(v);
    final num = RegExp(r'\d').hasMatch(v);
    final len = v.trim().length >= 8;

    if (_hasUpper != upper || _hasLower != lower || _hasNumber != num || _minLen != len) {
      if (!mounted) return;
      setState(() {
        _hasUpper = upper;
        _hasLower = lower;
        _hasNumber = num;
        _minLen = len;
      });
    }
  }

  String? _passwordValidator(String? v) {
    final val = (v ?? "").trim();
    if (val.length < 8) return "Minimum 8 characters required";
    if (!RegExp(r'[A-Z]').hasMatch(val)) return "Add at least 1 uppercase letter";
    if (!RegExp(r'[a-z]').hasMatch(val)) return "Add at least 1 lowercase letter";
    if (!RegExp(r'\d').hasMatch(val)) return "Add at least 1 number";
    return null;
  }

  String? _confirmValidator(String? v) {
    final val = (v ?? "").trim();
    if (val.isEmpty) return "Required";
    if (val != _passCtrl.text.trim()) return "Passwords do not match";
    return null;
  }

  bool get _canContinue {
    final emailOk = _idCtrl.text.trim().contains("@");
    final passOk = _passwordValidator(_passCtrl.text) == null;
    final confirmOk = _confirmValidator(_rePassCtrl.text) == null;
    return emailOk && passOk && confirmOk;
  }

  void _nextPage() {
    if (!_formKey.currentState!.validate()) return;

    _formData.emailOrPhone = _idCtrl.text.trim();
    _formData.password = _passCtrl.text.trim();

    FocusScope.of(context).unfocus();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SignupStep2Details(formData: _formData),
      ),
    );
  }

  void _changeEmail() {
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, "/signup-email");
  }

  // ===================== UI =====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _premiumAppBar(step: 1),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Let’s get started",
                style: GoogleFonts.poppins(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Create your Troonky login credentials",
                style: GoogleFonts.poppins(color: Colors.grey, fontSize: 15),
              ),
              const SizedBox(height: 26),

              _userTypeSelector(),
              const SizedBox(height: 18),

              // Verified Email + Change
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Verified Email",
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextButton(
                    onPressed: _changeEmail,
                    child: Text(
                      "Change",
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: gradientEnd),
                    ),
                  ),
                ],
              ),
              _premiumField(
                controller: _idCtrl,
                label: "Email (OTP verified)",
                icon: Icons.verified_user_rounded,
                enabled: false,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  final val = (v ?? "").trim();
                  if (val.isEmpty) return "Email required";
                  if (!val.contains("@")) return "Enter valid email";
                  return null;
                },
              ),
              const SizedBox(height: 18),

              _premiumField(
                controller: _passCtrl,
                focusNode: _passFocus,
                label: "Password",
                icon: Icons.lock_rounded,
                isPassword: true,
                obscureText: _obscure1,
                onVisibilityToggle: () => setState(() => _obscure1 = !_obscure1),
                validator: _passwordValidator,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_rePassFocus),
                autofillHints: const [AutofillHints.newPassword],
              ),
              const SizedBox(height: 10),

              _passwordRules(),

              const SizedBox(height: 18),

              _premiumField(
                controller: _rePassCtrl,
                focusNode: _rePassFocus,
                label: "Confirm Password",
                icon: Icons.lock_outline_rounded,
                isPassword: true,
                obscureText: _obscure2,
                onVisibilityToggle: () => setState(() => _obscure2 = !_obscure2),
                validator: _confirmValidator,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _nextPage(),
                autofillHints: const [AutofillHints.newPassword],
              ),

              if (_rePassCtrl.text.isNotEmpty && _rePassCtrl.text.trim() != _passCtrl.text.trim())
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    "Passwords don’t match",
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

              const SizedBox(height: 22),

              if (_isBusiness)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: gradientEnd.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: gradientEnd.withOpacity(0.14)),
                  ),
                  child: Text(
                    "Business selected ✅\nNext step-এ shop details (name, category, address, etc.) নিতে পারবে।",
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _bottomNextButton(),
    );
  }

  Widget _passwordRules() {
    Widget item(String text, bool ok) {
      return Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16, color: ok ? Colors.green : Colors.grey),
          const SizedBox(width: 8),
          Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: ok ? Colors.green : Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Password rules",
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          item("Minimum 8 characters", _minLen),
          const SizedBox(height: 6),
          item("At least 1 uppercase letter", _hasUpper),
          const SizedBox(height: 6),
          item("At least 1 lowercase letter", _hasLower),
          const SizedBox(height: 6),
          item("At least 1 number", _hasNumber),
        ],
      ),
    );
  }

  Widget _premiumField({
    required TextEditingController controller,
    FocusNode? focusNode,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool obscureText = false,
    bool enabled = true,
    VoidCallback? onVisibilityToggle,
    String? Function(String?)? validator,
    void Function(String)? onFieldSubmitted,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    List<String>? autofillHints,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        validator: validator,
        obscureText: isPassword ? obscureText : false,
        enabled: enabled,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        autofillHints: autofillHints,
        onFieldSubmitted: onFieldSubmitted,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: enabled ? Colors.black87 : Colors.grey,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.grey.shade600,
            fontWeight: FontWeight.normal,
          ),
          prefixIcon: Icon(icon, color: gradientEnd),
          suffixIcon: isPassword
              ? IconButton(
            icon: Icon(
              obscureText ? Icons.visibility_off : Icons.visibility,
              color: Colors.grey,
            ),
            onPressed: onVisibilityToggle,
          )
              : (!enabled ? const Icon(Icons.check_circle, color: Colors.green) : null),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        ),
      ),
    );
  }

  Widget _userTypeSelector() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          _toggleItem("Personal", "user"),
          _toggleItem("Business", "business"),
        ],
      ),
    );
  }

  Widget _toggleItem(String title, String value) {
    final isActive = _formData.userType == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _formData.userType = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: isActive ? LinearGradient(colors: [gradientStart, gradientEnd]) : null,
            color: isActive ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            boxShadow: isActive
                ? [
              BoxShadow(
                color: gradientStart.withOpacity(0.25),
                blurRadius: 10,
                offset: const Offset(0, 5),
              )
            ]
                : [],
          ),
          child: Text(
            title,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.grey.shade600,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _premiumAppBar({required int step}) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(160),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [gradientStart, gradientEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(45)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 22),
                    ),
                    Text(
                      "Step $step of 3",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  "Account Setup",
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomNextButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: IgnorePointer(
          ignoring: !_canContinue,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _canContinue ? 1 : 0.55,
            child: InkWell(
              onTap: _nextPage,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                height: 58,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [gradientStart, gradientEnd]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: gradientEnd.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    )
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text(
                      "Continue to Details",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 10),
                    Icon(Icons.arrow_forward_rounded, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
