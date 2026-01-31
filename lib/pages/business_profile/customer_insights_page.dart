import 'package:flutter/material.dart';

class CustomerInsightsPage extends StatelessWidget {
  const CustomerInsightsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Customer Insights"),
        backgroundColor: Colors.deepPurple,
      ),
      body: const Center(
        child: Text("Customer insights and data"),
      ),
    );
  }
}
