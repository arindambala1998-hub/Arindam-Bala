import 'package:flutter/material.dart';

// SERVICE
import 'service/add_service_page.dart';
import 'widgets/business_services_list_page.dart';

// PRODUCT
import 'add_product_page.dart';

// ORDERS
import 'orders_list_page.dart';

// ✅ CHART ANALYSIS
import 'chart_analysis_page.dart';

// PROFILE (to open products via tab)
import 'business_profile_page.dart';

import '../../services/business_api.dart';

class BusinessDashboardPage extends StatefulWidget {
  final Map<String, dynamic> business;

  const BusinessDashboardPage({
    super.key,
    required this.business,
  });

  @override
  State<BusinessDashboardPage> createState() => _BusinessDashboardPageState();
}

class _BusinessDashboardPageState extends State<BusinessDashboardPage> {
  Map<String, dynamic> _counts = <String, dynamic>{};
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final id = getBusinessId(widget.business);
      final res = await BusinessAPI.fetchDashboardCounts(id);

      setState(() {
        _counts = Map<String, dynamic>.from(res['counts'] ?? res);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ------------------------------------------------------
  // SAFE EXTRACT BUSINESS ID (Works in ALL cases)
  // ------------------------------------------------------
  String getBusinessId(Map<String, dynamic> data) {
    if (data.isEmpty) return "";

    if (data["_id"] != null) return data["_id"].toString();
    if (data["id"] != null) return data["id"].toString();
    if (data["businessId"] != null) return data["businessId"].toString();

    // Nested object
    if (data["business"] != null && data["business"] is Map) {
      final nested = data["business"] as Map;
      if (nested["_id"] != null) return nested["_id"].toString();
      if (nested["id"] != null) return nested["id"].toString();
      if (nested["businessId"] != null) return nested["businessId"].toString();
    }

    return "";
  }

  @override
  Widget build(BuildContext context) {
    final String businessId = getBusinessId(widget.business);

    if (businessId.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text(
            "Error: businessId missing!",
            style: TextStyle(color: Colors.red, fontSize: 18),
          ),
        ),
      );
    }

    final String name = widget.business["name"]?.toString() ?? "Business";

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text("$name Dashboard"),
        backgroundColor: Colors.deepPurple,
      ),
      body: RefreshIndicator(
        onRefresh: _loadCounts,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER SECTION
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF7F00FF), Color(0xFFE100FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 22,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Manage your business activities easily",
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // SUMMARY CARDS
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _loading
                    ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Center(child: CircularProgressIndicator()),
                )
                    : _error.isNotEmpty
                    ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Center(
                    child: Text(
                      _error,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                )
                    : Row(
                  children: [
                    Expanded(
                      child: _summaryCard(
                        "Products",
                        (_counts["products"] ??
                            _counts["products_count"] ??
                            widget.business["products_count"] ??
                            0)
                            .toString(),
                            () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BusinessProfilePage(
                                businessId: businessId,
                                isOwner: true,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _summaryCard(
                        "Orders",
                        (_counts["orders"] ??
                            _counts["orders_count"] ??
                            widget.business["orders_count"] ??
                            0)
                            .toString(),
                            () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  OrdersListPage(businessId: businessId),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _summaryCard(
                        "Services",
                        (_counts["services"] ??
                            _counts["services_count"] ??
                            widget.business["services_count"] ??
                            0)
                            .toString(),
                            () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BusinessServicesListPage(
                                  businessId: businessId),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 25),

              _sectionTitle("Quick Actions"),

              // ADD PRODUCT BUTTON
              _actionButton(
                icon: Icons.add_box,
                label: "Add New Product",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddProductPage(businessId: businessId),
                    ),
                  );
                },
              ),

              // ADD SERVICE BUTTON
              _actionButton(
                icon: Icons.design_services,
                label: "Add New Service",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddServicePage(businessId: businessId),
                    ),
                  );
                },
              ),

              // VIEW ORDERS BUTTON
              _actionButton(
                icon: Icons.shopping_bag,
                label: "View All Orders",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OrdersListPage(businessId: businessId),
                    ),
                  );
                },
              ),

              // ✅ CHART ANALYSIS BUTTON
              _actionButton(
                icon: Icons.query_stats,
                label: "Chart Analysis",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChartAnalysisPage(
                        businessId: businessId,
                        business: widget.business, // ✅ FIXED
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------- UI HELPERS -----------------

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _summaryCard(String title, String count, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 90,
        decoration: BoxDecoration(
          color: const Color(0xFFD1C4E9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              count,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                color: Colors.deepPurple.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        tileColor: Colors.grey.shade200,
        leading: Icon(icon, color: Colors.deepPurple, size: 26),
        title: Text(label, style: const TextStyle(fontSize: 16)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}
