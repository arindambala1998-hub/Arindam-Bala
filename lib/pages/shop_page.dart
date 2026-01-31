// lib/pages/shop_page.dart - PREMIER SHOP TRACKER (FINAL FIXED)
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';

// Services & Pages
import 'package:troonky_link/services/shop_api.dart';
import 'package:troonky_link/pages/business_profile/business_profile_page.dart';

class ShopPage extends StatefulWidget {
  const ShopPage({super.key});

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _isGpsLoading = false;
  String? _errorMessage;

  List<Map<String, dynamic>> _allShops = [];
  List<Map<String, dynamic>> _filteredShops = [];
  String _activeLocation = "Nearby Areas";

  final List<String> _categories = const [
    "All",
    "Fashion",
    "Restaurant",
    "Jewellery",
    "Pharmacy",
    "Doctor/Clinic",
    "Furniture",
    "Grocery",
    "Electronics",
    "Salon/Parlour",
    "Gym",
    "Sweet Shop",
    "Hardware",
    "Stationary",
    "Automobile",
    "Bakery",
    "Tailor",
    "Laundry",
    "Others",
  ];

  String _selectedCategory = "All";

  @override
  void initState() {
    super.initState();
    _fetchShops(pincode: null);
    _searchController.addListener(_applyFilters); // ✅ search + category together
  }

  @override
  void dispose() {
    _searchController.removeListener(_applyFilters);
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------
  // Helpers
  // ---------------------------
  bool _isNonEmpty(String? s) => s != null && s.trim().isNotEmpty;
  bool _isValidPincode(String s) => RegExp(r'^\d{6}$').hasMatch(s.trim());

  String _safeString(dynamic v, {String fallback = ""}) =>
      v == null ? fallback : v.toString();

  String _normalizeCategory(dynamic raw) {
    final s = _safeString(raw).trim();
    if (s.isEmpty) return "Others";
    // normalize a few common variations
    final low = s.toLowerCase();
    if (low == "stationery") return "Stationary"; // your UI list uses Stationary
    if (low == "salon" || low == "parlour" || low == "salon/parlor") {
      return "Salon/Parlour";
    }
    // keep as is
    return s;
  }

  // logo url normalize (relative -> absolute)
  String _normalizeImageUrl(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return "";
    if (s.startsWith("http://") || s.startsWith("https://")) return s;
    if (s.startsWith("/")) return "https://adminapi.troonky.in$s";
    return "https://adminapi.troonky.in/$s";
  }

  void _applyFilters() {
    // combine: category + search (name/address/pincode)
    final q = _searchController.text.trim().toLowerCase();

    List<Map<String, dynamic>> list = List<Map<String, dynamic>>.from(_allShops);

    // category filter
    if (_selectedCategory != "All") {
      final sel = _selectedCategory.toLowerCase();
      list = list.where((s) {
        final cat = _normalizeCategory(s["category"]).toLowerCase();
        return cat == sel;
      }).toList();
    }

    // search filter
    if (q.isNotEmpty) {
      list = list.where((s) {
        final name = _safeString(s["name"]).toLowerCase();
        final address = _safeString(s["address"]).toLowerCase();
        final city = _safeString(s["city"]).toLowerCase();
        final pin = _safeString(s["pincode"]).toLowerCase();
        final state = _safeString(s["state"]).toLowerCase();

        return name.contains(q) ||
            address.contains(q) ||
            city.contains(q) ||
            state.contains(q) ||
            pin.contains(q);
      }).toList();
    }

    if (!mounted) return;
    setState(() => _filteredShops = list);
  }

  // ============================================================
  // 🛰️ API CALL
  // ============================================================
  Future<void> _fetchShops({String? pincode}) async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final pin = (pincode ?? "").trim();

    // if user typed something not a pincode, don't call API with garbage
    if (_isNonEmpty(pin) && !_isValidPincode(pin)) {
      setState(() {
        _loading = false;
        _errorMessage = "Enter a valid 6-digit pincode.";
      });
      return;
    }

    try {
      final List<Map<String, dynamic>> shops =
      await ShopAPI.getShops(pincode: _isNonEmpty(pin) ? pin : null);

      if (!mounted) return;

      setState(() {
        _allShops = shops;
        _activeLocation = (_isNonEmpty(pin)) ? "Pincode: $pin" : "Nearby Areas";
        _errorMessage = null;
      });

      _applyFilters(); // ✅ apply category + search after fetch
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = "Could not load shops. Check connection.";
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    if (_isGpsLoading) return;
    if (!mounted) return;

    setState(() => _isGpsLoading = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Location permission denied forever. Enable in Settings.",
            ),
          ),
        );
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final List<Placemark> placemarks =
      await placemarkFromCoordinates(position.latitude, position.longitude);

      final String pin =
      placemarks.isNotEmpty ? (placemarks[0].postalCode ?? "").trim() : "";

      if (_isValidPincode(pin)) {
        _searchController.text = pin;
        await _fetchShops(pincode: pin);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not detect pincode from location")),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("GPS Error: Could not get location")),
      );
    } finally {
      if (mounted) setState(() => _isGpsLoading = false);
    }
  }

  void _onCategorySelected(String cat) {
    if (!mounted) return;
    setState(() => _selectedCategory = cat);
    _applyFilters(); // ✅ filter instantly
  }

  // ============================================================
  // 🎨 UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          "Shop Tracker",
          style: GoogleFonts.poppins(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _useCurrentLocation,
            icon: _isGpsLoading
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.deepPurple,
              ),
            )
                : const Icon(Icons.my_location, color: Colors.deepPurple),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchAndLocationHeader(),
          _buildCategorySlider(),
          const Divider(height: 1),
          Expanded(child: _buildMainContent()),
        ],
      ),
    );
  }

  Widget _buildSearchAndLocationHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(30),
            ),
            child: TextField(
              controller: _searchController,
              keyboardType: TextInputType.number,
              onSubmitted: (val) => _fetchShops(pincode: val.trim()),
              decoration: const InputDecoration(
                hintText: "Track by Pincode... (or type to search)",
                border: InputBorder.none,
                icon: Icon(Icons.search, color: Colors.deepPurple),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.location_on, size: 14, color: Colors.deepPurple),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  _activeLocation,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _fetchShops(pincode: _searchController.text),
                child: const Text(
                  "Go",
                  style: TextStyle(
                      fontWeight: FontWeight.w800, color: Colors.deepPurple),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySlider() {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _categories.length,
        itemBuilder: (context, i) {
          final cat = _categories[i];
          final bool isSelected = _selectedCategory == cat;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(cat),
              selected: isSelected,
              onSelected: (_) => _onCategorySelected(cat),
              selectedColor: Colors.deepPurple,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
              backgroundColor: Colors.grey.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMainContent() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.deepPurple),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }

    if (_filteredShops.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.storefront_outlined,
                size: 80, color: Colors.grey.shade200),
            const SizedBox(height: 10),
            Text(
              "No shops found",
              style: GoogleFonts.poppins(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      itemCount: _filteredShops.length,
      itemBuilder: (context, i) => _buildShopCard(_filteredShops[i]),
    );
  }

  // ============================================================
  // ✅ SHOP CARD
  // ============================================================
  Widget _buildShopCard(Map<String, dynamic> shop) {
    final String name = _safeString(shop["name"], fallback: "Unknown Shop");
    final String address = _safeString(
      shop["address"] ?? shop["city"] ?? shop["pincode"],
      fallback: "Address not available",
    );

    final bool isVerified = shop["is_verified"] == true;

    final double rating =
        double.tryParse(_safeString(shop["rating"], fallback: "4.2")) ?? 4.2;

    final int reviews = int.tryParse(
      _safeString(
        shop["reviews"] ?? shop["review_count"] ?? shop["total_reviews"],
        fallback: "0",
      ),
    ) ??
        0;

    final String rawLogo =
    _safeString(shop["logo_url"] ?? shop["image_url"] ?? shop["logo"])
        .trim();
    final String logoUrl = rawLogo.isEmpty ? "" : _normalizeImageUrl(rawLogo);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            final String businessId =
            _safeString(shop["id"] ?? shop["_id"] ?? shop["business_id"])
                .trim();
            if (businessId.isEmpty) return;

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BusinessProfilePage(
                  businessId: businessId,
                  isOwner: false,
                  shop: shop,
                ),
              ),
            );
          },
          child: Ink(
            decoration: BoxDecoration(
              color: const Color(0xFFF7F3FF),
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 14,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          height: 72,
                          width: 72,
                          color: const Color(0xFFEDEDED),
                          child: logoUrl.isNotEmpty
                              ? Image.network(
                            logoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.storefront,
                              size: 34,
                              color: Colors.grey,
                            ),
                          )
                              : const Icon(
                            Icons.storefront,
                            size: 34,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.star,
                                    size: 18, color: Color(0xFFF5B301)),
                                const SizedBox(width: 6),
                                Text(
                                  rating.toStringAsFixed(1),
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  reviews > 0
                                      ? "($reviews reviews)"
                                      : "(No reviews)",
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.location_on,
                                    size: 16, color: Colors.grey.shade600),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    address,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (isVerified)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Color(0xFF2A7DE1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.verified,
                          size: 18, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
