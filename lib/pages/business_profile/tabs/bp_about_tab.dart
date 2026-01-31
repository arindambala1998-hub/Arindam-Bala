import 'package:flutter/material.dart';
import '../controllers/business_profile_controller.dart';

class BPAboutTab extends StatelessWidget {
  final BusinessProfileController ctrl;

  const BPAboutTab({
    super.key,
    required this.ctrl,
  });

  // ======================================================
  // SECTION CARD WITH GRADIENT HEADER (Same as ProfileAboutTab)
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
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
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
  // INFO ROW — NULL-SAFE (Same style)
  // ======================================================
  Widget _infoRow(String label, dynamic value) {
    final displayValue = _safeValue(value);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
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

  String _safeValue(dynamic v) {
    if (v == null) return "Not added";
    final s = v.toString().trim();
    if (s.isEmpty) return "Not added";
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final data = ctrl.business;

    if (data.isEmpty) {
      return const Center(
        child: Text(
          "No information available",
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
      );
    }

    const gradientStart = Color(0xFFFF00CC);
    const gradientEnd = Color(0xFF333399);

    // BACKEND SAFE FIELDS
    final description = (data["description"] ?? "").toString().trim();

    final phone = (data["phone"] ?? "").toString().trim();
    final email = (data["email"] ?? "").toString().trim();
    final website = (data["website"] ?? "").toString().trim();

    final category = (data["category"] ?? "").toString().trim();
    final hours = (data["hours"] ?? "").toString().trim();
    final gst = (data["gst_no"] ?? "").toString().trim();
    final regNo = (data["registration_no"] ?? "").toString().trim();

    final addressParts = [
      data["address"],
      data["city"],
      data["state"],
      data["pincode"],
    ];

    final address = addressParts
        .where((e) => e != null && e.toString().trim().isNotEmpty)
        .map((e) => e.toString().trim())
        .join(", ");

    // Same padding/scroll vibe as profile about tab (card list look)
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // ABOUT
        if (description.isNotEmpty)
          _sectionCard(
            title: "About",
            icon: Icons.info_outline,
            gradientStart: gradientStart,
            gradientEnd: gradientEnd,
            children: [
              Text(
                description,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: Colors.black,
                ),
              ),
            ],
          ),

        // CONTACT
        if (phone.isNotEmpty || email.isNotEmpty || website.isNotEmpty)
          _sectionCard(
            title: "Contact Details",
            icon: Icons.call,
            gradientStart: gradientStart,
            gradientEnd: gradientEnd,
            children: [
              if (phone.isNotEmpty) _infoRow("Phone", phone),
              if (email.isNotEmpty) _infoRow("Email", email),
              if (website.isNotEmpty) _infoRow("Website", website),
            ],
          ),

        // ADDRESS
        if (address.isNotEmpty)
          _sectionCard(
            title: "Business Address",
            icon: Icons.location_on,
            gradientStart: gradientStart,
            gradientEnd: gradientEnd,
            children: [
              _infoRow("Address", address),
            ],
          ),

        // BUSINESS DETAILS (hours/category/gst/reg)
        if (hours.isNotEmpty ||
            category.isNotEmpty ||
            gst.isNotEmpty ||
            regNo.isNotEmpty)
          _sectionCard(
            title: "Business Details",
            icon: Icons.storefront,
            gradientStart: gradientStart,
            gradientEnd: gradientEnd,
            children: [
              if (hours.isNotEmpty) _infoRow("Hours", hours),
              if (category.isNotEmpty) _infoRow("Category", category),
              if (gst.isNotEmpty) _infoRow("GST No", gst),
              if (regNo.isNotEmpty) _infoRow("Reg No", regNo),
            ],
          ),
      ],
    );
  }
}
