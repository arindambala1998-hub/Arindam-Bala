import 'package:flutter/material.dart';
import '../controllers/business_profile_controller.dart';

class BPStatsRow extends StatelessWidget {
  final BusinessProfileController ctrl;

  const BPStatsRow({
    super.key,
    required this.ctrl,
  });

  // ----------------------------------------------------
  // SINGLE STAT ITEM (WITH ANIMATION + CLEAN DESIGN)
  // ----------------------------------------------------
  Widget _statItem({
    required String title,
    required int count,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        // Future: Navigate to stats tab or details
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 350),
            tween: Tween(begin: 0, end: count.toDouble()),
            builder: (context, value, _) {
              return Text(
                value.toInt().toString(),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              );
            },
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  int _safeLen(List? v) => v == null ? 0 : v.length;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300),
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statItem(title: "Products", count: _safeLen(ctrl.products)),
          _statItem(title: "Services", count: _safeLen(ctrl.services)),
          _statItem(title: "Posts", count: _safeLen(ctrl.posts)),
          // ✅ Reels removed কারণ controller-এ reels নেই
          _statItem(title: "Friends", count: _safeLen(ctrl.friends)),
        ],
      ),
    );
  }
}
