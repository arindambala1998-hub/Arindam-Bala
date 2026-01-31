import 'package:flutter/material.dart';

class ProfileAboutTab extends StatelessWidget {
  final Map<String, dynamic> user;

  const ProfileAboutTab({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    const gradientStart = Color(0xFFFF00CC);
    const gradientEnd = Color(0xFF333399);

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _sectionCard(
          title: "Basic Info",
          icon: Icons.person,
          gradientStart: gradientStart,
          gradientEnd: gradientEnd,
          children: [
            _infoRow("Name", user["name"]),
            _infoRow("Username", user["username"]),
            _infoRow("Bio", user["bio"]),
          ],
        ),

        _sectionCard(
          title: "Contact Details",
          icon: Icons.call,
          gradientStart: gradientStart,
          gradientEnd: gradientEnd,
          children: [
            _infoRow("Phone", user["phone"]),
            _infoRow("Email", user["email"]),
            _infoRow("Address", user["address"]),
            _infoRow("Pincode", user["pincode"]),
          ],
        ),

        _sectionCard(
          title: "Personal Info",
          icon: Icons.info_outline,
          gradientStart: gradientStart,
          gradientEnd: gradientEnd,
          children: [
            _infoRow("Gender", user["gender"]),
            // ✅ FIX: date_of_birth এর বদলে 'dob' ব্যবহার করা হলো (ডেটাবেস কলাম অনুযায়ী)
            _infoRow("Birthday", _formatDate(user["dob"])),
            _infoRow("Relationship", user["relationship"]),
          ],
        ),

        _sectionCard(
          title: "Education & Work",
          icon: Icons.school,
          gradientStart: gradientStart,
          gradientEnd: gradientEnd,
          children: [
            _infoRow("Education", user["education"]),
            _infoRow("Work", user["work"]),
          ],
        ),

        _sectionCard(
          title: "Links",
          icon: Icons.link,
          gradientStart: gradientStart,
          gradientEnd: gradientEnd,
          children: [
            _infoRow("Website", user["website"]),
          ],
        ),
      ],
    );
  }

  // ======================================================
  // SECTION CARD WITH GRADIENT HEADER
  // ======================================================
  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Color gradientStart,
    required Color gradientEnd,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: gradientStart.withOpacity(0.20),
            blurRadius: 10,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Column(
        children: [
          // 🌈 Gradient Title Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              gradient: LinearGradient(
                colors: [gradientStart, gradientEnd],
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // 📌 Content
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  // ======================================================
  // INFO ROW — FULL NULL-SAFE
  // ======================================================
  Widget _infoRow(String label, dynamic value) {
    final displayValue = _safeValue(value);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              displayValue,
              style: const TextStyle(
                fontSize: 15,
                height: 1.3,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ======================================================
  // SAFE VALUE CONVERTER
  // ======================================================
  String _safeValue(dynamic v) {
    if (v == null) return "Not added";
    if (v is String && v.trim().isEmpty) return "Not added";
    return v.toString();
  }

  // ======================================================
  // SAFE DATE FORMATTER
  // ======================================================
  String _formatDate(dynamic dateValue) {
    if (dateValue == null || dateValue.toString().isEmpty) return "Not added";

    try {
      // Assuming DOB is stored in a format DateTime.parse can handle (e.g., 'YYYY-MM-DD').
      final date = DateTime.parse(dateValue.toString());
      return "${date.day}/${date.month}/${date.year}";
    } catch (e) {
      // fallback if date parsing fails
      return dateValue.toString();
    }
  }
}