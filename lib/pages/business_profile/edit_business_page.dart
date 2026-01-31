import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:troonky_link/helpers/image_compressor.dart';
import 'package:troonky_link/services/business_api.dart';

class EditBusinessPage extends StatefulWidget {
  final Map<String, dynamic> business;

  const EditBusinessPage({super.key, required this.business});

  @override
  State<EditBusinessPage> createState() => _EditBusinessPageState();
}

class _EditBusinessPageState extends State<EditBusinessPage> {
  static const Color _gStart = Color(0xFFFF00CC);
  static const Color _gEnd = Color(0xFF333399);

  late final TextEditingController nameController;
  late final TextEditingController taglineController;
  late final TextEditingController descriptionController;
  late final TextEditingController phoneController;
  late final TextEditingController emailController;
  late final TextEditingController websiteController;
  late final TextEditingController addressController;
  late final TextEditingController cityController;
  late final TextEditingController stateController;
  late final TextEditingController pincodeController;
  late final TextEditingController categoryController;
  late final TextEditingController hoursController;
  late final TextEditingController gstController;
  late final TextEditingController regController;

  final ImagePicker _picker = ImagePicker();
  File? _logoFile;
  File? _coverFile;

  String _logoUrlLive = "";
  String _coverUrlLive = "";

  bool _saving = false;

  Map<String, String> _initialText = {};

  String _s(dynamic v) => (v ?? "").toString().trim();
  String _pub(dynamic v) => BusinessAPI.toPublicUrl(_s(v));

  String _cleanPin(String s) => s.trim().replaceAll(RegExp(r'[^0-9]'), '');

  String _resolveBusinessId(Map<String, dynamic> b) {
    return _s(
      b["id"] ??
          b["_id"] ??
          b["business_id"] ??
          b["businessId"] ??
          b["shop_id"] ??
          b["shopId"],
    );
  }

  @override
  void initState() {
    super.initState();

    nameController = TextEditingController(text: _s(widget.business["name"]));
    taglineController = TextEditingController(text: _s(widget.business["tagline"]));
    descriptionController = TextEditingController(text: _s(widget.business["description"]));
    phoneController = TextEditingController(text: _s(widget.business["phone"]));
    emailController = TextEditingController(text: _s(widget.business["email"]));
    websiteController = TextEditingController(text: _s(widget.business["website"]));
    addressController = TextEditingController(text: _s(widget.business["address"]));
    cityController = TextEditingController(text: _s(widget.business["city"]));
    stateController = TextEditingController(text: _s(widget.business["state"]));
    pincodeController = TextEditingController(text: _cleanPin(_s(widget.business["pincode"])));
    categoryController = TextEditingController(text: _s(widget.business["category"]));
    hoursController = TextEditingController(text: _s(widget.business["hours"]));
    gstController = TextEditingController(text: _s(widget.business["gst_no"]));
    regController = TextEditingController(text: _s(widget.business["registration_no"]));

    _logoUrlLive = _s(widget.business["logo_url"] ?? widget.business["logo"]);
    _coverUrlLive = _s(widget.business["cover_url"] ?? widget.business["cover"]);

    _initialText = _snapshotText();
  }

  Map<String, String> _snapshotText() {
    return {
      "name": nameController.text.trim(),
      "tagline": taglineController.text.trim(),
      "description": descriptionController.text.trim(),
      "phone": phoneController.text.trim(),
      "email": emailController.text.trim(),
      "website": websiteController.text.trim(),
      "address": addressController.text.trim(),
      "city": cityController.text.trim(),
      "state": stateController.text.trim(),
      "pincode": _cleanPin(pincodeController.text),
      "category": categoryController.text.trim(),
      "hours": hoursController.text.trim(),
      "gst_no": gstController.text.trim(),
      "registration_no": regController.text.trim(),
    };
  }

  String? _validateForm(Map<String, String> data) {
    final pin = _cleanPin(data["pincode"] ?? "");
    data["pincode"] = pin;

    if ((data["name"] ?? "").trim().isEmpty) return "Business name is required";
    if ((data["phone"] ?? "").trim().isEmpty) return "Phone is required";
    if (pin.isEmpty) return "Pincode is required";
    if (!RegExp(r"^\d{6}$").hasMatch(pin)) return "Pincode must be 6 digits";
    if ((data["category"] ?? "").trim().isEmpty) return "Category is required";

    final email = (data["email"] ?? "").trim();
    if (email.isNotEmpty && !RegExp(r"^[^@\s]+@[^@\s]+\.[^@\s]+$").hasMatch(email)) {
      return "Invalid email";
    }
    return null;
  }

  bool _isTextDirty(Map<String, String> now) {
    for (final e in _initialText.entries) {
      if ((now[e.key] ?? "") != e.value) return true;
    }
    return false;
  }

  @override
  void dispose() {
    nameController.dispose();
    taglineController.dispose();
    descriptionController.dispose();
    phoneController.dispose();
    emailController.dispose();
    websiteController.dispose();
    addressController.dispose();
    cityController.dispose();
    stateController.dispose();
    pincodeController.dispose();
    categoryController.dispose();
    hoursController.dispose();
    gstController.dispose();
    regController.dispose();
    super.dispose();
  }

  Future<void> _pickImage({required bool isLogo}) async {
    if (_saving) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              height: 5,
              width: 50,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text("Choose from Gallery"),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text("Take a Photo"),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );

    if (source == null) return;

    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1400,
    );
    if (picked == null) return;

    setState(() {
      if (isLogo) {
        _logoFile = File(picked.path);
      } else {
        _coverFile = File(picked.path);
      }
    });
  }

  Future<void> _saveChanges() async {
    if (_saving) return;
    setState(() => _saving = true);

    final businessId = _resolveBusinessId(widget.business);
    if (businessId.isEmpty) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Invalid business id")),
        );
      }
      return;
    }

    final textNow = _snapshotText();

    // keep controller clean
    final cleanedPin = _cleanPin(textNow["pincode"] ?? "");
    textNow["pincode"] = cleanedPin;
    if (pincodeController.text != cleanedPin) {
      pincodeController.text = cleanedPin;
      pincodeController.selection = TextSelection.collapsed(offset: cleanedPin.length);
    }

    final validationError = _validateForm(textNow);
    final imagesDirty = _logoFile != null || _coverFile != null;
    final textDirty = _isTextDirty(textNow);

    if (!textDirty && !imagesDirty) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Nothing changed")),
        );
      }
      return;
    }

    if (validationError != null) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(validationError)),
        );
      }
      return;
    }

    // 1) Update text
    if (textDirty) {
      final okText = await BusinessAPI.updateBusiness(businessId, textNow);
      if (!okText) {
        if (mounted) {
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Update Failed!")),
          );
        }
        return;
      }
    }

    // 2) Upload images
    if (imagesDirty) {
      File? logo = _logoFile;
      File? cover = _coverFile;

      if (logo != null) logo = await ImageCompressor.compress(logo) ?? logo;
      if (cover != null) cover = await ImageCompressor.compress(cover) ?? cover;

      final upRes = await BusinessAPI.uploadBusinessImages(
        businessId,
        logoFile: logo,
        coverFile: cover,
      );

      if (upRes["success"] != true) {
        final msg = (upRes["message"] ?? upRes["error"] ?? "Image Upload Failed").toString();
        if (mounted) {
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
        return;
      }
    }

    // 3) Fetch latest business
    final freshRes = await BusinessAPI.fetchBusiness(businessId);
    final freshBusiness = (freshRes["business"] is Map)
        ? Map<String, dynamic>.from(freshRes["business"])
        : (freshRes is Map<String, dynamic>)
        ? Map<String, dynamic>.from(freshRes)
        : <String, dynamic>{};

    if (mounted) {
      widget.business.addAll(freshBusiness);

      final logo = _s(freshBusiness["logo_url"] ?? freshBusiness["logo"]);
      final cover = _s(freshBusiness["cover_url"] ?? freshBusiness["cover"]);
      if (logo.isNotEmpty) _logoUrlLive = logo;
      if (cover.isNotEmpty) _coverUrlLive = cover;

      _logoFile = null;
      _coverFile = null;

      // ✅ reset dirty baseline after save
      _initialText = _snapshotText();

      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Business Updated Successfully!")),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        foregroundColor: Colors.white,
        title: const Text(
          "Edit Business",
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_gStart, _gEnd]),
          ),
        ),
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader("Images", Icons.photo_camera_outlined),
              _imagesCard(),
              const SizedBox(height: 18),
              _sectionHeader("Details", Icons.edit_note_rounded),
              _infoCard(),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _saveChanges,
                  child: Ink(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(colors: [_gStart, _gEnd]),
                      boxShadow: [
                        BoxShadow(
                          color: _gStart.withAlpha(64),
                          blurRadius: 14,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _saving
                          ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Text(
                        "Save Changes",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
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

  Widget _sectionHeader(String title, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(colors: [_gStart, _gEnd]),
        boxShadow: [
          BoxShadow(
            color: _gStart.withAlpha(46),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagesCard() {
    final logoUrl = _pub(_logoUrlLive);
    final coverUrl = _pub(_coverUrlLive);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Logo", style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _imageBox(
            height: 110,
            width: 110,
            url: logoUrl,
            file: _logoFile,
            placeholderIcon: Icons.storefront,
            onTap: () => _pickImage(isLogo: true),
            isCircle: true,
          ),
          const SizedBox(height: 18),
          const Text("Cover Photo", style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _imageBox(
            height: 150,
            width: double.infinity,
            url: coverUrl,
            file: _coverFile,
            placeholderIcon: Icons.image_rounded,
            onTap: () => _pickImage(isLogo: false),
            isCircle: false,
          ),
          const SizedBox(height: 8),
          Text(
            "Tap image to change (Gallery/Camera).",
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _infoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(
        children: [
          _input("Business Name", nameController, Icons.store),
          _gap(),
          _input("Tagline", taglineController, Icons.short_text),
          _gap(),
          _multi("Description", descriptionController),
          _bigGap(),
          _input("Phone", phoneController, Icons.phone),
          _gap(),
          _input("Email", emailController, Icons.email),
          _gap(),
          _input("Website", websiteController, Icons.language),
          _gap(),
          _input("Address", addressController, Icons.location_on),
          _gap(),
          _input("City", cityController, Icons.location_city),
          _gap(),
          _input("State", stateController, Icons.map),
          _gap(),
          _input("Pincode", pincodeController, Icons.pin_drop_rounded, isPincode: true),
          _gap(),
          _input("Category", categoryController, Icons.category),
          _gap(),
          _input("Hours", hoursController, Icons.access_time),
          _gap(),
          _input("GST Number", gstController, Icons.receipt_long),
          _gap(),
          _input("Registration No.", regController, Icons.badge),
        ],
      ),
    );
  }

  Widget _input(
      String label,
      TextEditingController c,
      IconData icon, {
        bool isPincode = false,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade800)),
        const SizedBox(height: 7),
        TextField(
          controller: c,
          keyboardType: isPincode ? TextInputType.number : TextInputType.text,

          // ✅ IMPORTANT: DO NOT use const here (it causes your compile error)
          inputFormatters: isPincode
              ? [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ]
              : null,

          onChanged: isPincode
              ? (v) {
            final clean = _cleanPin(v);
            if (clean != v) {
              c.text = clean;
              c.selection = TextSelection.collapsed(offset: clean.length);
            }
          }
              : null,

          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: _gEnd),
            filled: true,
            fillColor: Colors.white,
            hintText: "Enter $label",
            hintStyle: TextStyle(color: Colors.grey.shade500),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _gEnd, width: 1.6),
            ),
          ),
        ),
      ],
    );
  }

  Widget _multi(String label, TextEditingController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade800)),
        const SizedBox(height: 7),
        TextField(
          controller: c,
          maxLines: 4,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            hintText: "Enter $label",
            hintStyle: TextStyle(color: Colors.grey.shade500),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _gEnd, width: 1.6),
            ),
          ),
        ),
      ],
    );
  }

  Widget _imageBox({
    required double height,
    required double width,
    required String url,
    required File? file,
    required IconData placeholderIcon,
    required VoidCallback onTap,
    required bool isCircle,
  }) {
    final hasFile = file != null;
    final hasNetwork = url.trim().isNotEmpty;

    Widget imageChild;

    if (hasFile) {
      imageChild = Image.file(file!, fit: BoxFit.cover, width: width, height: height);
    } else if (hasNetwork) {
      imageChild = Image.network(
        url,
        fit: BoxFit.cover,
        width: width,
        height: height,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            alignment: Alignment.center,
            color: Colors.grey.shade100,
            child: const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: _gEnd),
            ),
          );
        },
        errorBuilder: (_, __, ___) {
          return Container(
            alignment: Alignment.center,
            color: Colors.grey.shade100,
            child: Icon(placeholderIcon, color: Colors.grey, size: isCircle ? 44 : 48),
          );
        },
      );
    } else {
      imageChild = Container(
        alignment: Alignment.center,
        color: Colors.grey.shade100,
        child: Icon(placeholderIcon, color: Colors.grey, size: isCircle ? 44 : 48),
      );
    }

    final hasAnyImage = hasFile || hasNetwork;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: isCircle
                  ? Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(width: 110, height: 110, child: imageChild),
                ),
              )
                  : imageChild,
            ),
            if (hasAnyImage)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withAlpha(13),
                        Colors.black.withAlpha(89),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  gradient: const LinearGradient(colors: [_gStart, _gEnd]),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(31),
                      blurRadius: 10,
                      offset: const Offset(0, 6),
                    )
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text(
                      "Change",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gap() => const SizedBox(height: 16);
  Widget _bigGap() => const SizedBox(height: 22);

  BoxDecoration _card() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withAlpha(15),
          blurRadius: 10,
          offset: const Offset(0, 6),
        )
      ],
    );
  }
}
