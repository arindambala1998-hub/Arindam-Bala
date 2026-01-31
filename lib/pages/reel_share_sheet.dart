import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:troonky_link/helpers/share_helper.dart';

class ReelShareSheet extends StatefulWidget {
  final String reelUrl; // (optional) server url if you want
  final String reelId;  // ✅ required for deep link

  const ReelShareSheet({
    super.key,
    required this.reelUrl,
    required this.reelId,
  });

  @override
  State<ReelShareSheet> createState() => _ReelShareSheetState();
}

class _ReelShareSheetState extends State<ReelShareSheet> {
  bool _busy = false;

  /// ✅ App-only deep link
  String get _deepLink => "troonky://reel/${widget.reelId}";

  /// ✅ Facebook style share text
  String get _shareText => "Watch this reel on Troonky 👇\n$_deepLink";

  void _safe(VoidCallback action) {
    if (_busy) return;
    _busy = true;
    action();
    Future.delayed(const Duration(milliseconds: 450), () {
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dragHandle(),
            const SizedBox(height: 16),
            _title(),
            const SizedBox(height: 20),

            _actionTile(
              icon: Icons.link,
              label: "Copy link",
              onTap: () => _safe(() {
                Navigator.pop(context);
                ShareHelper.copyLink(_deepLink);
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text("Link copied"),
                    duration: Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }),
            ),

            _actionTile(
              icon: Icons.share,
              label: "Share",
              onTap: () => _safe(() {
                Navigator.pop(context);
                ShareHelper.shareText(_shareText);
              }),
            ),

            _actionTile(
              icon: Icons.chat,
              label: "Share to WhatsApp",
              onTap: () => _safe(() {
                Navigator.pop(context);
                ShareHelper.shareText(_shareText);
              }),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ====================================================
  // UI PARTS
  // ====================================================
  Widget _dragHandle() {
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.grey.shade400,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _title() {
    return Text(
      "Share reel",
      style: GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: Colors.deepPurple),
      title: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }
}
