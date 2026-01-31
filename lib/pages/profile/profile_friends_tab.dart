import 'package:flutter/material.dart';
import 'package:troonky_link/helpers/block_helper.dart';
import 'package:troonky_link/pages/messages_page.dart';

class ProfileFriendsTab extends StatelessWidget {
  final List<dynamic> friends;
  final VoidCallback onSeeAll;
  final Function(String userId) onFriendTap;
  final bool isMyProfile;

  const ProfileFriendsTab({
    super.key,
    required this.friends,
    required this.onSeeAll,
    required this.onFriendTap,
    this.isMyProfile = false,
  });

  static const Color gradientStart = Color(0xFFFF00CC);
  static const Color gradientEnd = Color(0xFF333399);

  @override
  Widget build(BuildContext context) {
    if (friends.isEmpty) {
      return const Center(
        child: Text(
          "No friends to show",
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    // preview like before (you can change 6 -> any number)
    final preview = friends.length > 10 ? friends.sublist(0, 10) : friends;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ================= HEADER =================
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Friends",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            TextButton(
              onPressed: onSeeAll,
              child: const Text(
                "See All",
                style: TextStyle(
                  color: gradientEnd,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        // ================= LIST =================
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: preview.length,
          separatorBuilder: (_, __) => Divider(color: Colors.grey.shade200, height: 1),
          itemBuilder: (context, index) {
            final friend = Map<String, dynamic>.from(preview[index] ?? {});
            final String image = (friend["profile_pic"] ?? "").toString();
            final String name = (friend["name"]?.toString().trim().isEmpty ?? true)
                ? "Unknown User"
                : friend["name"].toString();
            final String friendId = (friend["friend_id"] ?? friend["id"] ?? "").toString();

            return InkWell(
              onTap: () {
                if (friendId.isNotEmpty) onFriendTap(friendId);
              },
              onLongPress: isMyProfile
                  ? () => _openActions(context, friendId, name)
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    // ===== AVATAR =====
                    Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [gradientStart, gradientEnd]),
                      ),
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.white,
                        child: CircleAvatar(
                          radius: 20,
                          backgroundImage: image.isNotEmpty ? NetworkImage(image) : null,
                          child: image.isEmpty ? const Icon(Icons.person, size: 22) : null,
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // ===== NAME + SUBTITLE =====
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Friend",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 10),

                    // ===== MESSAGE BUTTON (instead of Add Friend) =====
                    _messageButton(
                      context: context,
                      friendId: friendId,
                      friendName: name,
                      avatarUrl: image,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ===== MESSAGE BUTTON UI =====
  Widget _messageButton({
    required BuildContext context,
    required String friendId,
    required String friendName,
    required String avatarUrl,
  }) {
    final disabled = friendId.isEmpty;

    return GestureDetector(
      onTap: disabled
          ? null
          : () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MessagesPage(
              friendId: friendId,
              friendName: friendName,
              friendAvatarUrl: avatarUrl,
            ),
          ),
        );
      },
      child: Opacity(
        opacity: disabled ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [gradientStart, gradientEnd]),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: gradientEnd.withAlpha((0.20 * 255).round()),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline, color: Colors.white, size: 16),
              SizedBox(width: 6),
              Text(
                "Message",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= ACTION SHEET (optional for my profile) =================
  void _openActions(BuildContext context, String userId, String name) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_remove),
              title: const Text("Remove friend"),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("$name removed")),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.red),
              title: const Text("Block user", style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                await BlockHelper.blockUser(int.tryParse(userId) ?? 0);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("$name blocked")),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
