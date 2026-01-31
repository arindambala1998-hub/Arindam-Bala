// lib/pages/offer_page.dart
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

// প্রয়োজনীয় কন্ট্রোলার ও পেজ
import 'business_profile/controllers/product_controller.dart';
import 'business_profile/product_details_page.dart';

class OfferPage extends StatefulWidget {
  const OfferPage({super.key});

  @override
  State<OfferPage> createState() => _OfferPageState();
}

class _OfferPageState extends State<OfferPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _pinController = TextEditingController();

  bool _isLoading = false;
  String _currentPincode = "Detecting...";
  List<dynamic> _localOffers = [];
  List<dynamic> _globalOffers = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _detectLocationAndFetch();
  }

  // ============================================================
  // 🛰️ LOCATION & PINCODE LOGIC
  // ============================================================
  Future<void> _detectLocationAndFetch() async {
    setState(() => _isLoading = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);

      String? pincode = placemarks.isNotEmpty ? placemarks[0].postalCode : null;

      if (pincode != null) {
        setState(() => _currentPincode = pincode);
        _fetchOffers(pincode);
      }
    } catch (e) {
      setState(() => _currentPincode = "Enter Pincode Manually");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // অফার ফেচ করার লজিক (ProductController ব্যবহার করে)
  void _fetchOffers(String pincode) {
    // এখানে তোমার API থেকে লোকাল ও গ্লোবাল অফার লোড হবে
    // আপাতত এটি সিমুলেট করা হচ্ছে
    setState(() {
      _localOffers = []; // API call logic will go here
      _globalOffers = [];
    });
  }

  // ============================================================
  // 🎨 UI DESIGN
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text("Exclusive Offers", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.deepPurple,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.deepPurple,
          tabs: const [
            Tab(text: "Local (Nearby)"),
            Tab(text: "Global (Premium)"),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildLocationBanner(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOfferList(_localOffers, isLocal: true),
                _buildOfferList(_globalOffers, isLocal: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.deepPurple.shade50,
      child: Row(
        children: [
          const Icon(Icons.location_on, color: Colors.deepPurple, size: 20),
          const SizedBox(width: 8),
          Text("Pin: $_currentPincode", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
          const Spacer(),
          TextButton(
            onPressed: _showPincodeDialog,
            child: const Text("Change", style: TextStyle(color: Colors.deepPurple)),
          )
        ],
      ),
    );
  }

  void _showPincodeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Enter Area Pincode"),
        content: TextField(
          controller: _pinController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: "e.g. 700001"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              setState(() => _currentPincode = _pinController.text);
              _fetchOffers(_pinController.text);
              Navigator.pop(context);
            },
            child: const Text("Set Area"),
          )
        ],
      ),
    );
  }

  Widget _buildOfferList(List offers, {required bool isLocal}) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (offers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_offer_outlined, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 10),
            Text(isLocal ? "No local offers in your area" : "No premium offers today"),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: offers.length,
      itemBuilder: (context, i) => _buildOfferCard(offers[i], isLocal),
    );
  }

  Widget _buildOfferCard(dynamic p, bool isLocal) {
    return Card(
      margin: const EdgeInsets.only(bottom: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          // ইমেজ ও অফার ব্যাজ
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                child: Image.network(p["image_url"] ?? "", height: 180, width: double.infinity, fit: BoxFit.cover),
              ),
              Positioned(
                top: 10, left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: isLocal ? Colors.green : Colors.orange, borderRadius: BorderRadius.circular(20)),
                  child: Text(isLocal ? "Local Deal" : "Super Global Deal", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          // ডিটেইলস
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p["name"] ?? "Offer Product", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text("₹${p["offer_price"]}", style: const TextStyle(fontSize: 18, color: Colors.deepPurple, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 10),
                    Text("₹${p["price"]}", style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey)),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailsPage(product: p)));
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                      child: const Text("Grab Deal"),
                    )
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}