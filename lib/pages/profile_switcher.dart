import 'package:flutter/material.dart';
import 'package:troonky_link/pages/profile/profile_page.dart';

/// ------------------ Profile Switcher ------------------
class ProfileSwitcher extends StatefulWidget {
  const ProfileSwitcher({super.key});

  @override
  State<ProfileSwitcher> createState() => _ProfileSwitcherState();
}

class _ProfileSwitcherState extends State<ProfileSwitcher> {
  // ✅ Hardcoded user IDs from the database, not full user objects
  String _selectedUserId = "1";

  // ✅ Placeholder to hold user data for displaying in the dropdown menu
  final Map<String, String> _users = {
    "1": "Normal User",
    "2": "Business User",
    "3": "Service User",
  };

  @override
  void initState() {
    super.initState();
    _setUser("1"); // Set a default user ID
  }

  void _setUser(String? userId) {
    if (userId != null) {
      setState(() {
        _selectedUserId = userId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile Switcher"),
        actions: [
          PopupMenuButton<String>(
            onSelected: _setUser,
            initialValue: _selectedUserId,
            itemBuilder: (context) => _users.keys.map((String userId) {
              return PopupMenuItem<String>(
                value: userId,
                child: Text(_users[userId]!),
              );
            }).toList(),
          ),
        ],
      ),
      // ✅ Now passes only the userId to ProfilePage
      body: ProfilePage(userId: _selectedUserId),
    );
  }
}