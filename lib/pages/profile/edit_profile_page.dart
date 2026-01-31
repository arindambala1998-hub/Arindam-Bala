import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ✅ IMPORT: ProfileAPI ফাইলটি ইমপোর্ট করা আবশ্যক।
import '../../services/profile_api.dart';

class EditProfilePage extends StatefulWidget {
  final Map<String, dynamic> user;
  const EditProfilePage({super.key, required this.user});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController nameCtrl;
  late TextEditingController usernameCtrl;
  late TextEditingController bioCtrl;
  late TextEditingController phoneCtrl;
  late TextEditingController emailCtrl;
  late TextEditingController addressCtrl;
  late TextEditingController pincodeCtrl;
  late TextEditingController educationCtrl;
  late TextEditingController workCtrl;
  late TextEditingController websiteCtrl;
  late TextEditingController relationshipCtrl;

  String? gender;
  String? birthday;

  File? newProfilePic;
  File? newCoverPic;

  bool saving = false;

  final Color gradientStart = const Color(0xFFFF00CC);
  final Color gradientEnd = const Color(0xFF333399);

  @override
  void initState() {
    super.initState();
    final u = widget.user;

    nameCtrl = TextEditingController(text: u["name"] ?? "");
    usernameCtrl = TextEditingController(text: u["username"] ?? "");
    bioCtrl = TextEditingController(text: u["bio"] ?? "");
    phoneCtrl = TextEditingController(text: u["phone"] ?? "");
    emailCtrl = TextEditingController(text: u["email"] ?? "");
    addressCtrl = TextEditingController(text: u["address"] ?? "");
    pincodeCtrl = TextEditingController(text: u["pincode"] ?? "");
    educationCtrl = TextEditingController(text: u["education"] ?? "");
    workCtrl = TextEditingController(text: u["work"] ?? "");
    websiteCtrl = TextEditingController(text: u["website"] ?? "");
    relationshipCtrl = TextEditingController(text: u["relationship"] ?? "");

    gender = u["gender"];
    // ✅ FIX 1: 'date_of_birth' কে ডেটাবেস কলাম 'dob' দ্বারা প্রতিস্থাপন করা হলো
    birthday = u["dob"];
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    usernameCtrl.dispose();
    bioCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
    addressCtrl.dispose();
    pincodeCtrl.dispose();
    educationCtrl.dispose();
    workCtrl.dispose();
    websiteCtrl.dispose();
    relationshipCtrl.dispose();
    super.dispose();
  }

  // =====================================================
  // IMAGE PICKERS
  // =====================================================
  Future<void> pickProfilePic() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x != null) setState(() => newProfilePic = File(x.path));
  } //

  Future<void> pickCoverPic() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x != null) setState(() => newCoverPic = File(x.path));
  } //

  // =====================================================
  // SAVE PROFILE (FIXED LOGIC)
  // =====================================================
  Future<void> saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    if (mounted) setState(() => saving = true);

    String? token;
    try {
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString("token");
    } catch (_) {
      // Handle SharedPreferences error
    }

    if (token == null || token.isEmpty) {
      if (mounted) setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Login again.")),
      );
      return;
    }

    try {
      // 1. SAVE TEXT DATA
      // ✅ ProfileAPI.updateBio কে কল করা হলো
      await ProfileAPI.updateBio(
        token: token,
        data: {
          "name": nameCtrl.text,
          "username": usernameCtrl.text,
          "bio": bioCtrl.text,
          "phone": phoneCtrl.text,
          "email": emailCtrl.text,
          "address": addressCtrl.text,
          "pincode": pincodeCtrl.text,
          "education": educationCtrl.text,
          "work": workCtrl.text,
          "website": websiteCtrl.text,
          "relationship": relationshipCtrl.text,
          "gender": gender ?? "",
          // ✅ FIX 2: সেভ করার সময় API-তে 'dob' কী পাঠানো হলো
          "dob": birthday ?? "",
        },
      ); //

      // 2. UPLOAD IMAGES
      if (newProfilePic != null) {
        await ProfileAPI.uploadImage(
          token: token,
          imageFile: newProfilePic!,
          type: "profile",
        ); //
      }

      if (newCoverPic != null) {
        await ProfileAPI.uploadImage(
          token: token,
          imageFile: newCoverPic!,
          type: "cover",
        ); //
      }

      // ✅ SUCCESS: Navigator pop and Snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile updated successfully!")),
        );
        Navigator.pop(context, true);
      }

    } catch (e) {
      // ❌ FAIL: API Call Exception
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Save failed: ${e.toString()}")),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  // =====================================================
  // SAFE IMAGE LOADERS
  // =====================================================
  ImageProvider? _getProfileImage() {
    if (newProfilePic != null) return FileImage(newProfilePic!);
    if (widget.user["profile_pic"] != null &&
        widget.user["profile_pic"].toString().isNotEmpty) {
      return NetworkImage(widget.user["profile_pic"]);
    }
    return null;
  } //

  ImageProvider? _getCoverImage() {
    if (newCoverPic != null) return FileImage(newCoverPic!);
    if (widget.user["cover_pic"] != null &&
        widget.user["cover_pic"].toString().isNotEmpty) {
      return NetworkImage(widget.user["cover_pic"]);
    }
    return null;
  } //

  // =====================================================
  // UI STARTS
  // =====================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Profile"),
        backgroundColor: gradientEnd,
      ),

      body: saving
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ============================
              // PROFILE PHOTOS
              // ============================
              _sectionTitle("Profile Photos"), //

              Row(
                children: [
                  GestureDetector(
                    onTap: pickProfilePic, //
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [gradientStart, gradientEnd],
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.white,
                        backgroundImage: _getProfileImage(), //
                        child: _getProfileImage() == null
                            ? const Icon(Icons.person, size: 45)
                            : null,
                      ),
                    ),
                  ),

                  const SizedBox(width: 20),

                  GestureDetector(
                    onTap: pickCoverPic, //
                    child: Container(
                      width: 130,
                      height: 85,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: [gradientStart, gradientEnd]), //
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: _getCoverImage() != null
                            ? Image(
                          image: _getCoverImage()!, //
                          fit: BoxFit.cover,
                        )
                            : const Icon(Icons.photo,
                            color: Colors.white, size: 40),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 25),

              // ============================
              // BASIC INFO
              // ============================
              _sectionTitle("Basic Info"), //
              _inputField(nameCtrl, "Full Name"), //
              _inputField(usernameCtrl, "Username"), //
              _inputField(bioCtrl, "Bio", maxLines: 3), //

              const SizedBox(height: 25),

              // ============================
              // CONTACT INFO
              // ============================
              _sectionTitle("Contact Info"), //
              _inputField(phoneCtrl, "Phone"), //
              _inputField(emailCtrl, "Email"), //
              _inputField(addressCtrl, "Address"), //
              _inputField(pincodeCtrl, "Pincode"), //

              const SizedBox(height: 25),

              // ============================
              // PERSONAL INFO
              // ============================
              _sectionTitle("Personal Info"), //

              DropdownButtonFormField(
                value: gender, //
                items: const [
                  DropdownMenuItem(value: "male", child: Text("Male")),
                  DropdownMenuItem(value: "female", child: Text("Female")),
                  DropdownMenuItem(value: "other", child: Text("Other")),
                ], //
                decoration: _inputDecoration("Gender"), //
                onChanged: (v) => setState(() => gender = v), //
              ),

              _inputField(relationshipCtrl, "Relationship"), //
              _inputField(educationCtrl, "Education"), //
              _inputField(workCtrl, "Work / Profession"), //

              const SizedBox(height: 25),

              // ============================
              // LINKS
              // ============================
              _sectionTitle("Links"), //
              _inputField(websiteCtrl, "Website"), //

              const SizedBox(height: 40),

              // ============================
              // SAVE BUTTON
              // ============================
              Container(
                height: 55,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [gradientStart, gradientEnd]), //
                  borderRadius: BorderRadius.circular(14),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: saving ? null : saveProfile, // ✅ FIX: Saving state disables tap
                  child: Center(
                    child: saving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                      "Save Changes",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
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

  // =====================================================
  // HELPERS
  // =====================================================
  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  } //

  Widget _inputField(TextEditingController ctrl, String label,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        validator: (v) {
          if (label == "Full Name" && (v == null || v.isEmpty)) {
            return "Name is required";
          }
          return null;
        },
        decoration: _inputDecoration(label),
      ),
    );
  } //

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: gradientEnd, width: 2),
      ),
    );
  } //
}