import 'package:flutter/material.dart';
import 'package:troonky_link/services/report_api.dart';

class ReelReportSheet extends StatefulWidget {
  final int reelId;

  const ReelReportSheet({
    super.key,
    required this.reelId,
  });

  @override
  State<ReelReportSheet> createState() => _ReelReportSheetState();
}

class _ReelReportSheetState extends State<ReelReportSheet> {
  String? _reason;
  final TextEditingController _otherCtrl = TextEditingController();
  bool _loading = false;

  final List<String> _reasons = const [
    "Spam",
    "Nudity or sexual content",
    "Hate speech",
    "Violence",
    "False information",
    "Harassment or bullying",
    "Copyright issue",
    "Other",
  ];

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  // ====================================================
  // 🚨 SUBMIT REPORT (SAFE)
  // ====================================================
  Future<void> _submit() async {
    if (_loading || _reason == null) return;

    final reasonText = _reason == "Other"
        ? _otherCtrl.text.trim()
        : _reason!;

    if (reasonText.isEmpty) {
      _toast("Please enter details");
      return;
    }

    setState(() => _loading = true);

    final ok = await ReportAPI.reportReel(
      reelId: widget.reelId,
      reason: reasonText,
    );

    if (!mounted) return;

    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? "Thanks for reporting. We’ll review it shortly."
              : "Something went wrong. Please try again later.",
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: ok ? Colors.green : Colors.redAccent,
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ====================================================
  // 🖥 UI
  // ====================================================
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ================= HEADER =================
            const Center(
              child: Text(
                "Report Reel",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            const SizedBox(height: 8),
            const Divider(),

            // ================= REASONS =================
            ..._reasons.map(
                  (r) => RadioListTile<String>(
                value: r,
                groupValue: _reason,
                dense: true,
                activeColor: Colors.redAccent,
                title: Text(
                  r,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                    _reason == r ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                onChanged: _loading
                    ? null
                    : (v) => setState(() => _reason = v),
              ),
            ),

            // ================= OTHER INPUT =================
            if (_reason == "Other")
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: _otherCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: "Please describe the issue",
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 14),

            // ================= SUBMIT =================
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                (_reason == null || _loading) ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Text(
                  "Submit Report",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
