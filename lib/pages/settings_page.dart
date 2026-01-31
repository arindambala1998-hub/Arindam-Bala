// lib/pages/settings_page.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:troonky_link/login_page.dart';
import 'package:troonky_link/pages/profile/kyc_page.dart'; // ✅ KYC Page import

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        children: [
          // ℹ️ About
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text("About"),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: "Troonky",
                applicationVersion: "1.0.0",
                applicationLegalese: "Developed by sona 💙",
              );
            },
          ),

          const Divider(),

          // 🔒 Privacy Policy
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text("Privacy Policy"),
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text("Privacy Policy"),
                  content: const Text(
                    "By using this app, you agree to our Terms & Conditions.\n"
                        "Your data will be kept safe.\n\n"
                        "Full document will be added later.",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("OK"),
                    ),
                  ],
                ),
              );
            },
          ),

          const Divider(),

          // 📝 KYC Button
          ListTile(
            leading: const Icon(Icons.verified_user),
            title: const Text("Complete KYC"),
            onTap: () {
              // ✅ KYC পেজে নেভিগেট করা হবে
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const KycPage()),
              );
            },
          ),

          const Divider(),

          // ➡️ Logout Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
            child: ElevatedButton.icon(
              onPressed: () async {
                // ✅ START: Logout logic
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Logging out...')),
                );

                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('loggedIn');

                // Navigate back to the login page and remove all previous routes
                if (mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                        (Route<dynamic> route) => false,
                  );
                }
                // ✅ END: Logout logic
              },
              icon: const Icon(Icons.logout, color: Colors.white),
              label: const Text(
                "Logout",
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}