import 'package:flutter/material.dart';

class BPTabBar extends StatelessWidget {
  final TabController controller;
  final List<String>? labels;

  const BPTabBar({
    super.key,
    required this.controller,
    this.labels,
  });

  static const Color _gEnd = Color(0xFF333399);

  List<String> _defaultLabels() => const [
    "Products",
    "Services",
    "Posts",
    "About",
    "Friends",
  ];

  @override
  Widget build(BuildContext context) {
    final labs = (labels != null && labels!.isNotEmpty) ? labels! : _defaultLabels();

    return Container(
      height: 55,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        labelColor: _gEnd,
        unselectedLabelColor: Colors.grey,
        indicatorColor: _gEnd,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        tabs: labs.map((t) => Tab(text: t)).toList(),
      ),
    );
  }
}
