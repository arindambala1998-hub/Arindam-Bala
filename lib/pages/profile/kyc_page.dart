// lib/pages/profile/kyc_page.dart
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class KycPage extends StatefulWidget {
  const KycPage({super.key});

  @override
  State<KycPage> createState() => _KycPageState();
}

class _KycPageState extends State<KycPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Business KYC Controllers
  final _businessNameCtrl = TextEditingController();
  final _businessAddressCtrl = TextEditingController();
  final _businessPinCodeCtrl = TextEditingController();
  final _businessCategoryCtrl = TextEditingController();
  final _businessAadharCtrl = TextEditingController();
  final _businessPanCtrl = TextEditingController();

  // Service KYC Controllers
  final _serviceNameCtrl = TextEditingController();
  final _serviceAddressCtrl = TextEditingController();
  final _serviceCategoryCtrl = TextEditingController();
  final _serviceAadharCtrl = TextEditingController();

  // Image Files
  File? _shopPhoto;
  File? _aadharPhoto;
  File? _panPhoto;
  File? _govDocPhoto;
  File? _userPhoto;

  bool _isLoading = false;

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(File? fileType) async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        if (fileType == _shopPhoto) {
          _shopPhoto = File(picked.path);
        } else if (fileType == _aadharPhoto) {
          _aadharPhoto = File(picked.path);
        } else if (fileType == _panPhoto) {
          _panPhoto = File(picked.path);
        } else if (fileType == _govDocPhoto) {
          _govDocPhoto = File(picked.path);
        } else if (fileType == _userPhoto) {
          _userPhoto = File(picked.path);
        }
      });
    }
  }

  Future<void> _submitKyc(String type) async {
    // This is where you will make the API call to your backend
    setState(() => _isLoading = true);

    // Simulate API call
    await Future.delayed(const Duration(seconds: 2));

    setState(() => _isLoading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$type KYC Submitted! Backend logic will be added here.')),
      );
      // After successful submission, you will navigate back or to a confirmation page.
      Navigator.of(context).pop();
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _businessNameCtrl.dispose();
    _businessAddressCtrl.dispose();
    _businessPinCodeCtrl.dispose();
    _businessCategoryCtrl.dispose();
    _businessAadharCtrl.dispose();
    _businessPanCtrl.dispose();
    _serviceNameCtrl.dispose();
    _serviceAddressCtrl.dispose();
    _serviceCategoryCtrl.dispose();
    _serviceAadharCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Your KYC'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Business KYC"),
            Tab(text: "Service KYC"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBusinessKycForm(),
          _buildServiceKycForm(),
        ],
      ),
    );
  }

  Widget _buildBusinessKycForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildTextField(_businessNameCtrl, "Business Name", Icons.business),
          _buildTextField(_businessAddressCtrl, "Address", Icons.location_on),
          _buildTextField(_businessPinCodeCtrl, "Pin Code", Icons.numbers),
          _buildTextField(_businessCategoryCtrl, "Business Category", Icons.category),
          _buildTextField(_businessAadharCtrl, "Aadhar Card/Voter Card Number", Icons.credit_card),
          _buildTextField(_businessPanCtrl, "PAN Card Number", Icons.credit_card),
          _buildImagePickerButton("Upload Shop Photo", _shopPhoto, () => _pickImage(_shopPhoto)),
          _buildImagePickerButton("Upload Aadhar/Voter Photo", _aadharPhoto, () => _pickImage(_aadharPhoto)),
          _buildImagePickerButton("Upload PAN Card Photo", _panPhoto, () => _pickImage(_panPhoto)),
          _buildImagePickerButton("Upload Govt. Document Photo", _govDocPhoto, () => _pickImage(_govDocPhoto)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isLoading ? null : () => _submitKyc("Business"),
            child: _isLoading ? const CircularProgressIndicator() : const Text("Submit Business KYC"),
          )
        ],
      ),
    );
  }

  Widget _buildServiceKycForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildTextField(_serviceNameCtrl, "User Name", Icons.person),
          _buildTextField(_serviceAddressCtrl, "Address", Icons.location_on),
          _buildTextField(_serviceCategoryCtrl, "Service Category", Icons.category),
          _buildImagePickerButton("Upload User Photo", _userPhoto, () => _pickImage(_userPhoto)),
          _buildTextField(_serviceAadharCtrl, "Aadhar/Voter/PAN Number", Icons.credit_card),
          _buildImagePickerButton("Upload ID Document Photo", _aadharPhoto, () => _pickImage(_aadharPhoto)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isLoading ? null : () => _submitKyc("Service"),
            child: _isLoading ? const CircularProgressIndicator() : const Text("Submit Service KYC"),
          )
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildImagePickerButton(String label, File? imageFile, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 50),
          side: BorderSide(color: imageFile != null ? Colors.green : Colors.grey),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(imageFile != null ? Icons.check_circle : Icons.upload_file, color: imageFile != null ? Colors.green : null),
            const SizedBox(width: 8),
            Text(imageFile != null ? "Image Selected: $label" : label),
          ],
        ),
      ),
    );
  }
}