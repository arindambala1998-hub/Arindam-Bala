import 'package:flutter/material.dart';

import '../controllers/business_profile_controller.dart';
import '../edit_business_page.dart';
import '../business_dashboard_page.dart';
import '../../../services/business_api.dart';

class BPHeader extends StatelessWidget {
  final BusinessProfileController ctrl;

  /// ✅ main param (BusinessProfilePage uses this)
  final bool isOwner;

  /// ✅ fallback param (if any old file/page uses different name)
  final bool? isOwnerLegacy;

  /// ✅ header cover height (optional)
  final double coverHeight;

  const BPHeader({
    super.key,
    required this.ctrl,
    required this.isOwner,
    this.isOwnerLegacy,
    this.coverHeight = 190,
  });

  static const Color _gStart = Color(0xFFFF00CC);
  static const Color _gEnd = Color(0xFF333399);

  String _s(dynamic v) => (v ?? "").toString().trim();

  @override
  Widget build(BuildContext context) {
    final owner = isOwnerLegacy ?? isOwner;
    final data = ctrl.business;

    // ✅ logo url
    final logoRaw = data["logo_url"] ??
        data["logo"] ??
        data["shop_logo"] ??
        data["image"] ??
        data["photo"] ??
        "";

    final logo = BusinessAPI.toPublicUrl(_s(logoRaw));

    // ✅ cover/background url (এটাই তোমার background image fix)
    final coverRaw = data["cover_url"] ??
        data["cover"] ??
        data["cover_pic"] ??
        data["cover_image"] ??
        data["banner"] ??
        data["bg"] ??
        data["background"] ??
        "";

    final cover = BusinessAPI.toPublicUrl(_s(coverRaw));

    // debug (প্রয়োজনে console এ দেখবে)
    // ignore: avoid_print
    print("BPHeader COVER_URL => $cover");
    // ignore: avoid_print
    print("BPHeader LOGO_URL  => $logo");

    final name = _s(data["name"] ?? data["shop_name"] ?? "Business");
    final tagline = _s(data["tagline"] ?? data["bio"] ?? data["about"]);
    final isVerified = data["is_verified"] == true || _s(data["verified"]) == "1";

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ✅ Cover + Avatar overlay
        Stack(
          clipBehavior: Clip.none,
          children: [
            _coverWidget(cover),

            // avatar + edit icon overlay
            Positioned(
              left: 0,
              right: 0,
              bottom: -55, // avatar half outside cover
              child: Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _avatarWidget(logo),
                    if (owner) _editAvatarButton(context),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 65), // space for avatar

        // ✅ Name pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.black.withValues(alpha: 115),
            border: Border.all(color: Colors.white.withValues(alpha: 55), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 70),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              if (isVerified) ...[
                const SizedBox(width: 8),
                const Icon(Icons.verified, size: 18, color: Color(0xFF2A7DE1)),
              ],
            ],
          ),
        ),

        // ✅ tagline
        if (tagline.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            tagline,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 235),
              fontWeight: FontWeight.w500,
              shadows: const [
                Shadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 2)),
              ],
            ),
          ),
        ],

        const SizedBox(height: 12),

        if (owner) _ownerButtons(context),
      ],
    );
  }

  // ---------------- UI pieces ----------------

  Widget _coverWidget(String coverUrl) {
    return Container(
      height: coverHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_gStart, _gEnd],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 45),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (coverUrl.isNotEmpty)
              Image.network(
                coverUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
                errorBuilder: (_, e, __) {
                  // ignore: avoid_print
                  print("❌ COVER LOAD ERROR => $e  URL=$coverUrl");
                  return _coverFallback();
                },
              )
            else
              _coverFallback(),

            // dark overlay so text/button clear
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 55),
                    Colors.black.withValues(alpha: 120),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_gStart, _gEnd],
        ),
      ),
      child: const Center(
        child: Icon(Icons.image, color: Colors.white70, size: 46),
      ),
    );
  }

  Widget _avatarWidget(String logoUrl) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(colors: [_gStart, _gEnd]),
        boxShadow: [
          BoxShadow(
            color: _gStart.withValues(alpha: 90),
            blurRadius: 18,
            spreadRadius: 3,
          ),
        ],
      ),
      child: CircleAvatar(
        radius: 55,
        backgroundColor: Colors.white,
        child: ClipOval(
          child: SizedBox(
            width: 104,
            height: 104,
            child: logoUrl.isNotEmpty
                ? Image.network(
              logoUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(child: CircularProgressIndicator(strokeWidth: 2));
              },
              errorBuilder: (_, e, __) {
                // ignore: avoid_print
                print("❌ LOGO LOAD ERROR => $e  URL=$logoUrl");
                return const Center(
                  child: Icon(Icons.storefront, size: 50, color: Colors.grey),
                );
              },
            )
                : const Center(
              child: Icon(Icons.storefront, size: 50, color: Colors.grey),
            ),
          ),
        ),
      ),
    );
  }

  Widget _editAvatarButton(BuildContext context) {
    return Positioned(
      right: -2,
      bottom: -2,
      child: InkWell(
        borderRadius: BorderRadius.circular(50),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EditBusinessPage(business: ctrl.business),
            ),
          );
          await ctrl.refresh();
        },
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _gEnd,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 45),
                blurRadius: 8,
                offset: const Offset(0, 3),
              )
            ],
          ),
          child: const Icon(Icons.edit, size: 14, color: Colors.white),
        ),
      ),
    );
  }

  Widget _ownerButtons(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _gradientButton(
          label: "Edit Business",
          icon: Icons.edit,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EditBusinessPage(business: ctrl.business),
              ),
            );
            await ctrl.refresh();
          },
        ),
        const SizedBox(width: 10),
        _outlineButton(
          label: "Dashboard",
          icon: Icons.dashboard_outlined,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BusinessDashboardPage(business: ctrl.business),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _gradientButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(colors: [_gStart, _gEnd]),
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
    );
  }

  Widget _outlineButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gEnd, width: 1.3),
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
                Icon(icon, color: _gEnd, size: 18),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: _gEnd,
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
