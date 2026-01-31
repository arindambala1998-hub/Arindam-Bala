import 'package:flutter/material.dart';

class ProfileHeader extends StatelessWidget {
  final String name;
  final String? profilePic;
  final String? coverPic; // no longer used
  final bool isMyProfile;

  // ✅ actions
  final VoidCallback? onAddFriend;
  final VoidCallback? onMessage;

  // ✅ small edit icon on profile picture (my profile)
  final VoidCallback? onEditPhotoTap;

  // ✅ NEW: dynamic friend button (facebook style)
  final String friendButtonText; // Add Friend / Pending / Respond / Friends
  final IconData friendButtonIcon;
  final bool friendButtonDisabled;

  const ProfileHeader({
    super.key,
    required this.name,
    this.profilePic,
    this.coverPic,
    this.isMyProfile = false,
    this.onAddFriend,
    this.onMessage,
    this.onEditPhotoTap,

    // ✅ defaults (so old code won't break)
    this.friendButtonText = "Add Friend",
    this.friendButtonIcon = Icons.person_add,
    this.friendButtonDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    const gradientStart = Color(0xFFFF00CC);
    const gradientEnd = Color(0xFF333399);

    final safeName = name.trim().isNotEmpty ? name.trim() : "Unknown User";

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 10),

        // ================================
        // PROFILE PIC + SMALL EDIT ICON
        // ================================
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [gradientStart, gradientEnd],
                ),
                boxShadow: [
                  BoxShadow(
                    color: gradientStart.withAlpha((0.40 * 255).round()),
                    blurRadius: 18,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 55,
                backgroundColor: Colors.white,
                child: CircleAvatar(
                  radius: 52,
                  backgroundImage: (profilePic != null && profilePic!.isNotEmpty)
                      ? NetworkImage(profilePic!)
                      : null,
                  child: (profilePic == null || profilePic!.isEmpty)
                      ? const Icon(Icons.person, size: 50)
                      : null,
                ),
              ),
            ),

            // ✅ only my profile -> show small edit icon
            if (isMyProfile && onEditPhotoTap != null)
              Positioned(
                right: -2,
                bottom: -2,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onEditPhotoTap,
                    borderRadius: BorderRadius.circular(50),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: gradientEnd,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha((0.18 * 255).round()),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ],
                      ),
                      child: const Icon(Icons.edit, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),

        const SizedBox(height: 10),

        // ================================
        // ✅ NAME (readable pill)
        // ================================
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            // glassy dark overlay so name is readable on any image
            color: Colors.black.withAlpha((0.45 * 255).round()),
            border: Border.all(
              color: Colors.white.withAlpha((0.22 * 255).round()),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha((0.25 * 255).round()),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            safeName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ================================
        // BUTTONS (Friend + Message) only for other profiles
        // ================================
        if (!isMyProfile)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildGradientButton(
                label: friendButtonText,
                icon: friendButtonIcon,
                // ✅ disable if friends or busy
                disabled: friendButtonDisabled,
                onTap: onAddFriend ?? () {},
              ),
              const SizedBox(width: 10),
              _buildOutlineButton(
                label: "Message",
                icon: Icons.chat_bubble_outline,
                onTap: onMessage ?? () {},
              ),
            ],
          ),

        const SizedBox(height: 10),
      ],
    );
  }

  // 🔥 GRADIENT BUTTON
  Widget _buildGradientButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool disabled = false,
  }) {
    return Opacity(
      opacity: disabled ? 0.65 : 1,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: [
              Color(0xFFFF00CC),
              Color(0xFF333399),
            ],
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: disabled ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ✅ OUTLINE BUTTON
  Widget _buildOutlineButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    const gradientEnd = Color(0xFF333399);

    return Container(
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gradientEnd, width: 1.3),
        color: Colors.white,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: gradientEnd, size: 18),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: gradientEnd,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
