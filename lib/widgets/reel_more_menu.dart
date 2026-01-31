import 'package:flutter/material.dart';
import 'package:troonky_link/pages/reel_report_sheet.dart';

class ReelMoreMenu extends StatelessWidget {
  final int reelId;
  final VoidCallback onHide;
  final VoidCallback onBlock;

  const ReelMoreMenu({
    super.key,
    required this.reelId,
    required this.onHide,
    required this.onBlock,
  });

  @override
  Widget build(BuildContext context) {
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
            _handle(),
            const SizedBox(height: 12),

            _tile(
              icon: Icons.visibility_off,
              text: "Hide this reel",
              onTap: () async {
                final ok = await _confirm(
                  context,
                  title: "Hide reel?",
                  message:
                  "You will see fewer reels like this.",
                  positive: "Hide",
                );
                if (!ok) return;
                Navigator.pop(context);
                onHide();
              },
            ),

            _tile(
              icon: Icons.flag,
              text: "Report reel",
              onTap: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) =>
                      ReelReportSheet(reelId: reelId),
                );
              },
            ),

            _tile(
              icon: Icons.block,
              text: "Block user",
              danger: true,
              onTap: () async {
                final ok = await _confirm(
                  context,
                  title: "Block this user?",
                  message:
                  "You will no longer see reels from this user.",
                  positive: "Block",
                  danger: true,
                );
                if (!ok) return;
                Navigator.pop(context);
                onBlock();
              },
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
  Widget _handle() {
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.grey.shade400,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(
        icon,
        color: danger ? Colors.red : Colors.black,
      ),
      title: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: danger ? Colors.red : Colors.black,
        ),
      ),
      onTap: onTap,
    );
  }

  // ====================================================
  // CONFIRM DIALOG (SECURITY UX)
  // ====================================================
  Future<bool> _confirm(
      BuildContext context, {
        required String title,
        required String message,
        required String positive,
        bool danger = false,
      }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: Text(
              positive,
              style: TextStyle(
                color: danger ? Colors.red : Colors.deepPurple,
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    return res ?? false;
  }
}
