import 'package:flutter/material.dart';

class BusinessPerformancePage extends StatelessWidget {
  const BusinessPerformancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Business Performance"),
        backgroundColor: Colors.deepPurple,
      ),
      body: const Center(
        child: Text("Analytics and charts here"),
      ),
    );
  }
}
