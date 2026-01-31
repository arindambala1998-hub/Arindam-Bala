import 'package:flutter/material.dart';

class UploadLoader extends StatefulWidget {
  final double size;
  const UploadLoader({super.key, this.size = 70});

  @override
  State<UploadLoader> createState() => _UploadLoaderState();
}

class _UploadLoaderState extends State<UploadLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: RotationTransition(
        turns: _controller,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.deepPurple,
              width: 6,
            ),
          ),
          child: const Icon(Icons.cloud_upload, color: Colors.deepPurple),
        ),
      ),
    );
  }
}
