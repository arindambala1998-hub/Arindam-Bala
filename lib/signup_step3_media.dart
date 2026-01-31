import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:troonky_link/helpers/image_compressor.dart';
import 'package:troonky_link/models/signup_data.dart';
import 'package:troonky_link/services/auth_api.dart';
import 'package:troonky_link/services/profile_api.dart';

class SignupStep3Media extends StatefulWidget {
  final SignupData formData;
  const SignupStep3Media({super.key, required this.formData});

  @override
  State<SignupStep3Media> createState() => _SignupStep3MediaState();
}

class _SignupStep3MediaState extends State<SignupStep3Media> {
  final ImagePicker _picker = ImagePicker();
  bool _loading = false;

  // 🔥 Troonky Official Gradient
  final Color gradientStart = const Color(0xFFFF00CC);
  final Color gradientEnd = const Color(0xFF333399);

  bool get _isBusiness => widget.formData.userType == "business";

  // ===========================================================
  // 📸 PICK IMAGE (Camera / Gallery) + Compress
  // ===========================================================
  Future<void> _pickImage({
    required bool isProfile,
    required ImageSource source,
  }) async {
    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
    );
    if (picked == null) return;

    final originalFile = File(picked.path);
    final compressedFile = await ImageCompressor.compress(originalFile);

    if (!mounted) return;
    setState(() {
      if (isProfile) {
        widget.formData.profilePicFile = compressedFile ?? originalFile;
      } else {
        widget.formData.coverPicFile = compressedFile ?? originalFile;
      }
    });
  }

  void _removeImage(bool isProfile) {
    if (!mounted) return;
    setState(() {
      if (isProfile) {
        widget.formData.profilePicFile = null;
      } else {
        widget.formData.coverPicFile = null;
      }
    });
  }

  Future<void> _showPickSheet(bool isProfile) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        // ✅ BottomSheet open থাকাকালীন state refresh safe করার জন্য
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final hasImg = isProfile
                ? widget.formData.profilePicFile != null
                : widget.formData.coverPicFile != null;

            Future<void> pickFrom(ImageSource src) async {
              Navigator.pop(context);
              await _pickImage(isProfile: isProfile, source: src);
              if (!mounted) return;
              setSheet(() {}); // sheet reopen হলে fresh state থাকবে
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 55,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    isProfile ? "Select Profile Photo" : "Select Cover Banner",
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _sheetBtn(
                          icon: Icons.photo_library_rounded,
                          title: "Gallery",
                          onTap: () => pickFrom(ImageSource.gallery),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _sheetBtn(
                          icon: Icons.photo_camera_rounded,
                          title: "Camera",
                          onTap: () => pickFrom(ImageSource.camera),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (hasImg)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _removeImage(isProfile);
                      },
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Colors.redAccent),
                      label: const Text(
                        "Remove",
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _sheetBtn({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: gradientEnd),
            const SizedBox(width: 10),
            Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ===========================================================
  // ✅ FINAL SUBMIT (Register -> Login -> Upload -> Save session)
  // ===========================================================
  Future<void> _submit() async {
    if (_loading) return;

    // Safety
    if ((widget.formData.emailOrPhone ?? "").trim().isEmpty) {
      _snack("Email missing. Please go back and enter email.", isError: true);
      return;
    }
    if ((widget.formData.password ?? "").trim().isEmpty) {
      _snack("Password missing. Please go back and enter password.",
          isError: true);
      return;
    }

    setState(() => _loading = true);

    try {
      final payload = widget.formData.toRegisterPayload();

      // ✅ signup() named param payload
      final regRes = await AuthAPI.signup(payload: payload);
      if (regRes["error"] == true) {
        throw Exception(regRes["message"] ?? "Registration failed");
      }

      // ✅ login() named params
      final loginRes = await AuthAPI.login(
        emailOrPhone: widget.formData.emailOrPhone!.trim(),
        password: widget.formData.password!.trim(),
      );
      if (loginRes["error"] == true) {
        throw Exception(
            "Account created, but login failed. Please login manually.");
      }

      final String token = (loginRes["token"] ?? "").toString().trim();
      if (token.isEmpty) throw Exception("Login token missing");

      // Uploads (optional)
      final tasks = <Future>[];
      if (widget.formData.profilePicFile != null) {
        tasks.add(ProfileAPI.uploadImage(
          token: token,
          imageFile: widget.formData.profilePicFile!,
          type: "profile",
        ));
      }
      if (widget.formData.coverPicFile != null) {
        tasks.add(ProfileAPI.uploadImage(
          token: token,
          imageFile: widget.formData.coverPicFile!,
          type: "cover",
        ));
      }

      if (tasks.isNotEmpty) {
        await Future.wait(tasks).catchError((e) {
          debugPrint("Media Upload Error: $e");
          return [];
        });
      }

      await AuthAPI.saveAuthData(
        token: token,
        userId: (loginRes["userId"] ?? "").toString(),
        userType: (loginRes["userType"] ?? "user").toString(),
        businessId: loginRes["businessId"]?.toString(),
      );

      if (!mounted) return;

      _snack("Welcome to Troonky! 🎉", isError: false);

      final type = (loginRes["userType"] ?? "user").toString().toLowerCase();

      // ✅ IMPORTANT FIX: business_profile route এ businessId পাঠানো হচ্ছে
      if (type == "business") {
        String businessId = (loginRes["businessId"] ?? "").toString().trim();

        // fallback: prefs থেকে নাও (যদি backend key mismatch/late save হয়)
        if (businessId.isEmpty) {
          final prefs = await SharedPreferences.getInstance();
          businessId = (prefs.getString("businessId") ?? "").trim();
        }

        // (optional) debug
        debugPrint("NAV -> business_profile businessId=$businessId");

        Navigator.pushNamedAndRemoveUntil(
          context,
          "/business_profile",
              (route) => false,
          arguments: {
            "businessId": businessId,
            "isOwner": true,
          },
        );
      } else {
        Navigator.pushNamedAndRemoveUntil(
          context,
          "/main_app",
              (route) => false,
        );
      }
    } catch (e) {
      final msg = e.toString().replaceAll("Exception:", "").trim();
      _snack(msg.isEmpty ? "Something went wrong" : msg, isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ===========================================================
  // UI
  // ===========================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _premiumAppBar(step: 3),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Add visuals",
              style:
              GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              _isBusiness
                  ? "Add shop logo and banner to build trust"
                  : "Make your profile stand out with photos",
              style: GoogleFonts.poppins(color: Colors.grey, fontSize: 15),
            ),
            const SizedBox(height: 26),
            _hintCard(),
            const SizedBox(height: 28),
            Center(child: _imageCard(isProfile: true)),
            const SizedBox(height: 22),
            _imageCard(isProfile: false),
            const SizedBox(height: 80),
          ],
        ),
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  Widget _hintCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [gradientStart, gradientEnd]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.tips_and_updates_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "You can skip this step now and add photos later from profile settings.",
              style: GoogleFonts.poppins(fontSize: 13.5, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageCard({required bool isProfile}) {
    final img =
    isProfile ? widget.formData.profilePicFile : widget.formData.coverPicFile;

    return GestureDetector(
      onTap: _loading ? null : () => _showPickSheet(isProfile),
      child: Opacity(
        opacity: _loading ? 0.75 : 1,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 14,
                offset: const Offset(0, 8),
              )
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                height: isProfile ? 72 : 62,
                width: isProfile ? 72 : 110,
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  shape: isProfile ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: isProfile ? null : BorderRadius.circular(16),
                  border: Border.all(
                    color: gradientEnd.withOpacity(0.18),
                    width: 2,
                  ),
                  image: img != null
                      ? DecorationImage(image: FileImage(img), fit: BoxFit.cover)
                      : null,
                ),
                child: img == null
                    ? Icon(
                  isProfile
                      ? Icons.person_add_alt_1_rounded
                      : Icons.photo_size_select_large_rounded,
                  color: gradientEnd.withOpacity(0.60),
                  size: 28,
                )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isProfile ? "Profile Picture" : "Cover / Banner",
                      style: GoogleFonts.poppins(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      img == null ? "Tap to upload" : "Tap to change",
                      style: GoogleFonts.poppins(
                          fontSize: 12.5, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              if (img != null)
                IconButton(
                  onPressed: _loading ? null : () => _removeImage(isProfile),
                  icon: const Icon(Icons.close_rounded),
                  color: Colors.redAccent,
                )
              else
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: gradientEnd.withOpacity(0.60),
                ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _premiumAppBar({required int step}) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(150),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [gradientStart, gradientEnd]),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(45)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios,
                        color: Colors.white, size: 20),
                    onPressed: _loading ? null : () => Navigator.pop(context),
                  ),
                  Text(
                    "Step $step of 3",
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(
                  "Final Step",
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 24,
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

  Widget _bottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: _loading ? null : _submit,
              child: Text(
                "Skip for now",
                style: GoogleFonts.poppins(
                  color: gradientEnd,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _loading ? null : _submit,
              borderRadius: BorderRadius.circular(20),
              child: Opacity(
                opacity: _loading ? 0.75 : 1,
                child: Container(
                  height: 60,
                  decoration: BoxDecoration(
                    gradient:
                    LinearGradient(colors: [gradientStart, gradientEnd]),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: gradientEnd.withOpacity(0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: Center(
                    child: _loading
                        ? const SizedBox(
                      height: 26,
                      width: 26,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                        : Text(
                      "Create My Account",
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(15),
      ),
    );
  }
}
