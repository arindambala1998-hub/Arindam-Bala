// lib/pages/business_profile/business_services_list_page.dart

import 'package:flutter/material.dart';
import 'package:troonky_link/services/services_api.dart';

// Correct folder name = Service
import '../Service/service_details_page.dart';

class BusinessServicesListPage extends StatefulWidget {
  final String businessId;

  const BusinessServicesListPage({
    super.key,
    required this.businessId,
  });

  @override
  State<BusinessServicesListPage> createState() =>
      _BusinessServicesListPageState();
}

class _BusinessServicesListPageState extends State<BusinessServicesListPage> {
  bool loading = true;
  List<Map<String, dynamic>> services = [];

  @override
  void initState() {
    super.initState();
    loadServices();
  }

  Future<void> loadServices() async {
    try {
      final response = await ServicesAPI.getBusinessServices(widget.businessId);

      setState(() {
        services = List<Map<String, dynamic>>.from(response);
        loading = false;
      });
    } catch (e) {
      setState(() => loading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to load services"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,

      appBar: AppBar(
        title: const Text("All Services"),
        backgroundColor: Colors.deepPurple,
        elevation: 0,
      ),

      body: loading
          ? const Center(
        child: CircularProgressIndicator(color: Colors.deepPurple),
      )

          : services.isEmpty
          ? const Center(
        child: Text(
          "No services found",
          style: TextStyle(color: Colors.grey, fontSize: 15),
        ),
      )

          : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: services.length,
        itemBuilder: (_, index) {
          final s = services[index];

          final name = s["name"] ?? "Service";
          final price = s["price"]?.toString() ?? "0";
          final duration = s["duration"]?.toString() ?? "";
          final image = ServicesAPI.toPublicUrl(s["image"]);

          return Card(
            elevation: 2,
            margin: const EdgeInsets.symmetric(vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),

            child: ListTile(
              contentPadding: const EdgeInsets.all(12),

              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: image.isEmpty
                    ? Container(
                  height: 50,
                  width: 50,
                  color: Colors.deepPurple.shade100,
                  child: const Icon(Icons.design_services,
                      color: Colors.deepPurple),
                )
                    : Image.network(
                  image,
                  height: 50,
                  width: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Container(
                        height: 50,
                        width: 50,
                        color: Colors.deepPurple.shade100,
                        child: const Icon(Icons.design_services,
                            color: Colors.deepPurple),
                      ),
                ),
              ),

              title: Text(
                name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),

              subtitle: Text(
                "₹$price • $duration",
                style: TextStyle(color: Colors.grey.shade700),
              ),

              trailing: const Icon(Icons.arrow_forward_ios, size: 16),

              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ServiceDetailsPage(
                      service: s,
                      isOwner: false,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
