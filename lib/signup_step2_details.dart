import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:troonky_link/models/signup_data.dart';
import 'package:troonky_link/signup_step3_media.dart';

class SignupStep2Details extends StatefulWidget {
  final SignupData formData;
  const SignupStep2Details({super.key, required this.formData});

  @override
  State<SignupStep2Details> createState() => _SignupStep2DetailsState();
}

class _SignupStep2DetailsState extends State<SignupStep2Details> {
  final _formKey = GlobalKey<FormState>();

  // 🔥 Troonky Official Gradient
  final Color gradientStart = const Color(0xFFFF00CC);
  final Color gradientEnd = const Color(0xFF333399);

  late TextEditingController _mainNameCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _pincodeCtrl;
  late TextEditingController _bioCtrl;
  late TextEditingController _dobCtrl;

  String? _gender = "Male";
  String? _relationship = "Single";
  String? _shopCategory;

  bool get _isBusiness => widget.formData.userType == "business";

  @override
  void initState() {
    super.initState();

    _mainNameCtrl = TextEditingController(
      text: _isBusiness ? widget.formData.shopName : widget.formData.name,
    );
    _addressCtrl = TextEditingController(
      text: _isBusiness ? widget.formData.shopAddress : widget.formData.address,
    );
    _pincodeCtrl = TextEditingController(text: widget.formData.pincode);
    _bioCtrl = TextEditingController(
      text: _isBusiness ? widget.formData.shopDescription : widget.formData.bio,
    );

    _dobCtrl = TextEditingController(
      text: widget.formData.dob != null
          ? DateFormat('dd MMM yyyy').format(widget.formData.dob!)
          : "",
    );

    _shopCategory = widget.formData.shopCategory;
  }

  @override
  void dispose() {
    _mainNameCtrl.dispose();
    _addressCtrl.dispose();
    _pincodeCtrl.dispose();
    _bioCtrl.dispose();
    _dobCtrl.dispose();
    super.dispose();
  }

  // ============================================================
  // DOB PICKER (AGE >= 13)
  // ============================================================
  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.formData.dob ?? DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 13)),
    );

    if (picked != null) {
      widget.formData.dob = picked;
      _dobCtrl.text = DateFormat('dd MMM yyyy').format(picked);
      if (mounted) setState(() {});
    }
  }

  // ============================================================
  // NEXT STEP
  // ============================================================
  void _next() {
    if (!_formKey.currentState!.validate()) return;

    if (_isBusiness) {
      widget.formData.shopName = _mainNameCtrl.text.trim();
      widget.formData.shopAddress = _addressCtrl.text.trim();
      widget.formData.shopDescription = _bioCtrl.text.trim();
      widget.formData.shopCategory = _shopCategory;
    } else {
      widget.formData.name = _mainNameCtrl.text.trim();
      widget.formData.address = _addressCtrl.text.trim();
      widget.formData.bio = _bioCtrl.text.trim();
      widget.formData.gender = _gender;
      widget.formData.relationshipStatus = _relationship;
    }

    widget.formData.pincode = _pincodeCtrl.text.trim();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SignupStep3Media(formData: widget.formData),
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
      appBar: _premiumAppBar(step: 2),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isBusiness ? "Business Details" : "Personal Details",
                style: GoogleFonts.poppins(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _isBusiness
                    ? "Tell customers about your shop"
                    : "Tell us more about yourself",
                style: GoogleFonts.poppins(color: Colors.grey, fontSize: 15),
              ),
              const SizedBox(height: 30),

              _premiumField(
                _mainNameCtrl,
                _isBusiness ? "Shop Name" : "Full Name",
                Icons.person_outline,
              ),

              if (!_isBusiness) ...[
                _premiumField(
                  _dobCtrl,
                  "Date of Birth",
                  Icons.calendar_month_outlined,
                  readOnly: true,
                  onTap: _pickDob,
                  validator: (v) =>
                  v == null || v.isEmpty ? "Date of birth required" : null,
                ),
                _buildDropdown(
                  "Gender",
                  ["Male", "Female", "Other"],
                  _gender,
                      (v) => setState(() => _gender = v),
                ),
                _buildDropdown(
                  "Relationship Status",
                  ["Single", "Married", "Complicated"],
                  _relationship,
                      (v) => setState(() => _relationship = v),
                ),
              ],

              if (_isBusiness)
                _buildDropdown(
                  "Shop Category",
                  [
                    "Fashion",
                    "Restaurant",
                    "Jewellery",
                    "Pharmacy",
                    "Doctor/Clinic",
                    "Furniture",
                    "Grocery",
                    "Electronics",
                    "Salon/Parlour",
                    "Gym",
                    "Sweet Shop",
                    "Hardware",
                    "Stationary",
                    "Automobile",
                    "Bakery",
                    "Tailor",
                    "Laundry"
                    "Others"
                  ],
                  _shopCategory,
                      (v) => setState(() => _shopCategory = v),
                  required: true,
                ),

              _premiumField(
                _addressCtrl,
                _isBusiness ? "Shop Address" : "Current Address",
                Icons.location_on_outlined,
              ),

              _premiumField(
                _pincodeCtrl,
                "Pincode",
                Icons.pin_drop_outlined,
                isNumber: true,
                validator: (v) {
                  if (v == null || v.isEmpty) return "Pincode required";
                  if (v.length != 6) return "Enter valid 6-digit pincode";
                  return null;
                },
              ),

              _premiumField(
                _bioCtrl,
                _isBusiness ? "Shop Description" : "Bio (optional)",
                Icons.info_outline,
                required: false,
                maxLines: 3,
                validator: (v) =>
                v != null && v.length > 150 ? "Max 150 characters" : null,
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _bottomNextButton(),
    );
  }

  // ============================================================
  // COMPONENTS
  // ============================================================
  Widget _premiumField(
      TextEditingController ctrl,
      String label,
      IconData icon, {
        bool readOnly = false,
        VoidCallback? onTap,
        bool required = true,
        bool isNumber = false,
        int maxLines = 1,
        String? Function(String?)? validator,
      }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextFormField(
        controller: ctrl,
        readOnly: readOnly,
        onTap: onTap,
        maxLines: maxLines,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        validator: validator ??
            (required
                ? (v) => v == null || v.isEmpty ? "$label required" : null
                : null),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: gradientEnd, size: 20),
          border: InputBorder.none,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildDropdown(
      String label,
      List<String> items,
      String? currentVal,
      Function(String?) onChange, {
        bool required = false,
      }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonFormField<String>(
        value: currentVal,
        validator:
        required ? (v) => v == null ? "$label required" : null : null,
        decoration: InputDecoration(labelText: label, border: InputBorder.none),
        items: items
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
        onChanged: onChange,
      ),
    );
  }

  PreferredSizeWidget _premiumAppBar({required int step}) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(150),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [gradientStart, gradientEnd]),
          borderRadius:
          const BorderRadius.vertical(bottom: Radius.circular(40)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios,
                          color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Account Setup",
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "Step $step of 3",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
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
        child: InkWell(
          onTap: _next,
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
                  "Continue",
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
    );
  }
}
