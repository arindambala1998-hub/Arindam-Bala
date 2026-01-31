import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../../../services/services_api.dart';
import '../../../services/business_api.dart'; // ✅ for toPublicUrl

class EditServicePage extends StatefulWidget {
  final Map<String, dynamic> service;

  const EditServicePage({super.key, required this.service});

  @override
  State<EditServicePage> createState() => _EditServicePageState();
}

class _EditServicePageState extends State<EditServicePage> {
  final ImagePicker _picker = ImagePicker();

  late TextEditingController nameCtrl;
  late TextEditingController descCtrl;
  late TextEditingController priceCtrl;
  late TextEditingController durationCtrl;

  late TextEditingController locationCtrl;
  late TextEditingController workingHoursCtrl;

  final List<String> _categories = const [
    "Doctor",
    "Salon/Parlour",
    "Class/Tutor",
    "Seminar/Event",
    "Consultation",
    "Other",
  ];
  String _selectedCategory = "Other";

  File? selectedImageFile;
  bool loading = false;

  // --------------------------
  // Safe helpers
  // --------------------------
  String _s(dynamic v, {String fallback = ""}) => (v ?? fallback).toString().trim();

  double _asDouble(dynamic v, {double fallback = 0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim()) ?? fallback;
  }

  String _serviceId(Map<String, dynamic> s) => _s(s["id"] ?? s["_id"] ?? s["serviceId"]);

  String _businessId(Map<String, dynamic> s) =>
      _s(s["business_id"] ?? s["businessId"] ?? s["shop_id"] ?? s["shopId"]);

  @override
  void initState() {
    super.initState();

    final s = widget.service;

    nameCtrl = TextEditingController(text: _s(s["name"]));
    descCtrl = TextEditingController(text: _s(s["description"]));
    priceCtrl = TextEditingController(
      text: _asDouble(s["price"], fallback: 0).toStringAsFixed(0),
    );
    durationCtrl = TextEditingController(text: _s(s["duration"]));

    locationCtrl = TextEditingController(text: _s(s["location"] ?? s["address"]));
    workingHoursCtrl = TextEditingController(text: _s(s["working_hours"] ?? s["workingHours"]));

    final cat = _s(s["category"], fallback: "Other");
    _selectedCategory = _categories.contains(cat) ? cat : "Other";
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    descCtrl.dispose();
    priceCtrl.dispose();
    durationCtrl.dispose();
    locationCtrl.dispose();
    workingHoursCtrl.dispose();
    super.dispose();
  }

  // --------------------------
  // Snack
  // --------------------------
  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : Colors.deepPurple,
      ),
    );
  }

  // --------------------------
  // Pick + compress image
  // --------------------------
  Future<void> pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    try {
      final outPath = "${picked.path}_compressed.jpg";
      final compressed = await FlutterImageCompress.compressAndGetFile(
        picked.path,
        outPath,
        quality: 70,
        minWidth: 1080,
        minHeight: 1080,
      );

      if (compressed != null) {
        if (!mounted) return;
        setState(() => selectedImageFile = File(compressed.path));
      }
    } catch (_) {
      _snack("Image compress failed. Try another image.", isError: true);
    }
  }

  // --------------------------
  // Validate + Save
  // --------------------------
  Future<void> saveService() async {
    final name = nameCtrl.text.trim();
    final priceText = priceCtrl.text.trim();
    final duration = durationCtrl.text.trim();

    if (name.isEmpty || duration.isEmpty) {
      _snack("Service name & duration are required", isError: true);
      return;
    }

    final price = double.tryParse(priceText) ?? 0;
    if (price <= 0) {
      _snack("Please enter valid price", isError: true);
      return;
    }

    final serviceId = _serviceId(widget.service);
    if (serviceId.isEmpty) {
      _snack("Service ID missing!", isError: true);
      return;
    }

    setState(() => loading = true);

    // ✅ Update payload (NO "image" key here)
    final Map<String, dynamic> body = {
      "name": name,
      "price": price.toStringAsFixed(0), // backend-safe string
      "duration": duration,
      "description": descCtrl.text.trim(),

      // optional fields
      "category": _selectedCategory,
      "location": locationCtrl.text.trim(),
      "working_hours": workingHoursCtrl.text.trim(),
    };

    // ✅ helpful id keys for legacy routes (if backend checks)
    final bid = _businessId(widget.service);
    if (bid.isNotEmpty) {
      body["business_id"] = bid;
      body["businessId"] = bid;
      body["shop_id"] = bid;
      body["shopId"] = bid;
    }

    try {
      final response = await ServicesAPI.updateService(
        serviceId,
        body,
        imageFile: selectedImageFile, // ✅ multipart if selected
      );

      final success = response["success"] == true;

      if (!mounted) return;
      setState(() => loading = false);

      if (success) {
        _snack("Service updated successfully!", isError: false);
        final payload = <String, dynamic>{
          "ok": true,
          "action": "updated",
          "service": response["service"] ?? (response["data"] is Map ? (response["data"]["service"] ?? response["data"]["data"] ?? response["data"]) : response["data"]) ?? widget.service,
        };
        Navigator.pop(context, payload);
      } else {
        _snack(response["message"] ?? "Failed to update service", isError: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => loading = false);
      _snack("Network error. Please try again.", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ old image can be full url OR "uploads/.."
    final oldRaw = _s(widget.service["image_url"] ?? widget.service["image"] ?? widget.service["photo"]);
    final oldImage = BusinessAPI.toPublicUrl(oldRaw); // ✅ FIXED

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text("Edit Service"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.6,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle("Service Image"),
            const SizedBox(height: 10),
            InkWell(
              onTap: loading ? null : pickImage,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                height: 190,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: () {
                    if (selectedImageFile != null) {
                      return Image.file(selectedImageFile!, fit: BoxFit.cover);
                    }
                    if (oldImage.isNotEmpty) {
                      return Image.network(
                        oldImage,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _imagePlaceholder(),
                      );
                    }
                    return _imagePlaceholder();
                  }(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Tap image to change",
              style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
            ),

            const SizedBox(height: 18),

            _sectionTitle("General Information"),
            const SizedBox(height: 10),

            _field(
              label: "Service Name *",
              controller: nameCtrl,
              hint: "e.g. Doctor Consultation / Haircut",
              icon: Icons.title,
              enabled: !loading,
            ),
            const SizedBox(height: 12),

            _field(
              label: "Price (₹) *",
              controller: priceCtrl,
              hint: "e.g. 499",
              icon: Icons.currency_rupee,
              keyboardType: TextInputType.number,
              enabled: !loading,
            ),
            const SizedBox(height: 12),

            _field(
              label: "Duration *",
              controller: durationCtrl,
              hint: "e.g. 30 min",
              icon: Icons.timer_outlined,
              enabled: !loading,
            ),

            const SizedBox(height: 16),

            _sectionTitle("Category"),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCategory,
                  isExpanded: true,
                  items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: loading ? null : (v) => setState(() => _selectedCategory = v ?? "Other"),
                ),
              ),
            ),

            const SizedBox(height: 16),

            _sectionTitle("Appointment Info (Optional)"),
            const SizedBox(height: 10),
            _field(
              label: "Location / Address",
              controller: locationCtrl,
              hint: "Clinic/Salon/Center address",
              icon: Icons.location_on_outlined,
              maxLines: 2,
              enabled: !loading,
            ),
            const SizedBox(height: 12),
            _field(
              label: "Working Hours",
              controller: workingHoursCtrl,
              hint: "e.g. 10AM - 7PM",
              icon: Icons.schedule,
              enabled: !loading,
            ),

            const SizedBox(height: 16),

            _sectionTitle("Description"),
            const SizedBox(height: 10),
            _field(
              label: "Service Description",
              controller: descCtrl,
              hint: "Write service details, rules, requirements...",
              icon: Icons.description_outlined,
              maxLines: 5,
              enabled: !loading,
            ),

            const SizedBox(height: 22),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: loading ? null : saveService,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: loading
                    ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
                    : const Text(
                  "Save Changes",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) {
    return Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900));
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
          ),
        ),
      ],
    );
  }

  Widget _imagePlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.camera_alt, size: 46, color: Colors.grey),
          const SizedBox(height: 8),
          Text("Upload Image", style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
