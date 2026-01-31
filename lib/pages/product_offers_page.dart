// lib/pages/product_offers_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import 'business_profile/product_details_page.dart';

class ProductOffersPage extends StatefulWidget {
  const ProductOffersPage({super.key});

  @override
  State<ProductOffersPage> createState() => _ProductOffersPageState();
}

class _ProductOffersPageState extends State<ProductOffersPage> {
  static const String _apiBase = "https://adminapi.troonky.in/api";
  static const String _hostBase = "https://adminapi.troonky.in";
  static const Duration _timeout = Duration(seconds: 25);

  final TextEditingController _searchPinCtrl = TextEditingController();

  bool _gpsLoading = false;
  bool _loading = true;
  String? _error;

  String _activePincode = "Detecting...";

  List<Map<String, dynamic>> _allProducts = [];
  Map<String, Map<String, dynamic>> _shopsById = {}; // "4" -> shop map

  // UI categories
  final List<String> _categories = const [
    "All",
    "Electronics",
    "Mobiles",
    "Computers",
    "Fashion",
    "Footwear",
    "Beauty",
    "Health",
    "Grocery",
    "Home & Kitchen",
    "Furniture",
    "Jewellery",
    "Sports",
    "Toys",
    "Books",
    "Stationery",
    "Automobile",
    "Baby Care",
    "Pet Supplies",
    "Others",
  ];
  String _selectedCategory = "All";

  @override
  void initState() {
    super.initState();
    _detectPincodeAndLoad();
  }

  @override
  void dispose() {
    _searchPinCtrl.dispose();
    super.dispose();
  }

  // ---------------------------
  // Helpers
  // ---------------------------
  bool _isValidPincode(String s) => RegExp(r'^\d{6}$').hasMatch(s.trim());

  String _s(dynamic v, {String fallback = ""}) =>
      v == null ? fallback : v.toString();

  int _asInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  double _asDouble(dynamic v, {double fallback = 0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  String _normalizeImageUrl(String raw) {
    final s = raw.toString().trim();
    if (s.isEmpty) return "";
    if (s.startsWith("http://") || s.startsWith("https://")) return s;
    if (s.startsWith("/")) return "$_hostBase$s";
    return "$_hostBase/$s";
  }

  List<String> _imagesOf(Map<String, dynamic> p) {
    final out = <String>[];

    final imagesAny = p["images"];
    if (imagesAny is List) {
      for (final x in imagesAny) {
        final s = x?.toString().trim() ?? "";
        if (s.isNotEmpty) out.add(_normalizeImageUrl(s));
      }
    } else if (imagesAny is String) {
      final raw = imagesAny.trim();
      if (raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            for (final x in decoded) {
              final s = x?.toString().trim() ?? "";
              if (s.isNotEmpty) out.add(_normalizeImageUrl(s));
            }
          }
        } catch (_) {}
      }
    }

    if (out.isEmpty) {
      final one = (p["image_url"] ?? p["image"] ?? "").toString().trim();
      if (one.isNotEmpty) out.add(_normalizeImageUrl(one));
    }

    return out.toSet().toList();
  }

  String _imageOf(Map<String, dynamic> p) {
    final imgs = _imagesOf(p);
    return imgs.isNotEmpty ? imgs.first : "";
  }

  // ✅ Offer exists if old_price > effectivePrice (offer_price else price)
  bool _isOfferProduct(Map<String, dynamic> p) {
    final price = _asDouble(p["price"], fallback: 0);
    final offerPrice = _asDouble(p["offer_price"], fallback: 0);
    final oldPrice = _asDouble(p["old_price"], fallback: 0);
    final effective = (offerPrice > 0) ? offerPrice : price;
    return (oldPrice > 0 && effective > 0 && oldPrice > effective);
  }

  int _discountPct(Map<String, dynamic> p) {
    final price = _asDouble(p["price"], fallback: 0);
    final offerPrice = _asDouble(p["offer_price"], fallback: 0);
    final oldPrice = _asDouble(p["old_price"], fallback: 0);
    final effective = (offerPrice > 0) ? offerPrice : price;
    if (oldPrice <= 0 || effective <= 0 || oldPrice <= effective) return 0;
    return (((oldPrice - effective) / oldPrice) * 100).round();
  }

  String? _categoryRaw(Map<String, dynamic> p) {
    final c = p["category"];
    if (c == null) return null;
    if (c is String) return c.trim().isEmpty ? null : c.trim();
    if (c is Map && c["name"] != null) {
      final s = c["name"].toString().trim();
      return s.isEmpty ? null : s;
    }
    final s = c.toString().trim();
    return s.isEmpty ? null : s;
  }

  Map<String, dynamic>? _shopOfProduct(Map<String, dynamic> p) {
    final bid = _s(p["business_id"], fallback: "").trim();
    if (bid.isEmpty) return null;
    return _shopsById[bid];
  }

  // ✅ NEW: category product->shop fallback
  String _categoryOfProduct(Map<String, dynamic> p) {
    final direct = _categoryRaw(p);
    if (direct != null && direct.isNotEmpty) return direct;

    final shop = _shopOfProduct(p);
    final shopCat = shop?["category"];
    if (shopCat == null) return "Others";

    if (shopCat is String) {
      final s = shopCat.trim();
      return s.isEmpty ? "Others" : s;
    }

    if (shopCat is Map && shopCat["name"] != null) {
      final s = shopCat["name"].toString().trim();
      return s.isEmpty ? "Others" : s;
    }

    final s = shopCat.toString().trim();
    return s.isEmpty ? "Others" : s;
  }

  // ✅ FIXED: category filter now uses _categoryOfProduct (shop.category)
  bool _matchCategory(Map<String, dynamic> p) {
    if (_selectedCategory == "All") return true;
    final c = _categoryOfProduct(p);
    return c.toLowerCase() == _selectedCategory.toLowerCase();
  }

  List<Map<String, dynamic>> _view() {
    return _allProducts
        .where((p) => _isOfferProduct(p) && _matchCategory(p))
        .toList();
  }

  String _shopName(Map<String, dynamic> p) {
    final shop = _shopOfProduct(p);
    final name = shop != null ? _s(shop["name"]).trim() : "";
    if (name.isNotEmpty) return name;

    return (p["shop_name"] ??
        p["business_name"] ??
        (p["shop"] is Map ? p["shop"]["name"] : null) ??
        "Shop")
        .toString();
  }

  String _locationText(Map<String, dynamic> p) {
    final shop = _shopOfProduct(p);

    final a = _s((shop?["address"] ?? p["address"]) ?? "").trim();
    final city = _s((shop?["city"] ?? p["city"]) ?? "").trim();
    final state = _s((shop?["state"] ?? p["state"]) ?? "").trim();
    final pin = _s((shop?["pincode"] ?? p["pincode"]) ?? "").trim();

    final parts = [a, city, state, pin].where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return "Location not available";
    return parts.join(", ");
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.deepPurple),
    );
  }

  // ---------------------------
  // Location -> Pincode
  // ---------------------------
  Future<void> _detectPincodeAndLoad() async {
    if (!mounted) return;

    setState(() {
      _gpsLoading = true;
      _error = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _activePincode = "Enter Pincode");
        await _loadByPincode(null);
        _snack("Location service is OFF. Please enter pincode.");
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        setState(() => _activePincode = "Enter Pincode");
        await _loadByPincode(null);
        _snack("Location permission denied. Please enter pincode.");
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _activePincode = "Enter Pincode");
        await _loadByPincode(null);
        _snack("Permission denied forever. Enable location permission in Settings.");
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final placemarks =
      await placemarkFromCoordinates(pos.latitude, pos.longitude);
      final pin =
      placemarks.isNotEmpty ? (placemarks[0].postalCode ?? "").trim() : "";

      if (_isValidPincode(pin)) {
        setState(() => _activePincode = pin);
        _searchPinCtrl.text = pin;
        await _loadByPincode(pin);
      } else {
        setState(() => _activePincode = "Enter Pincode");
        await _loadByPincode(null);
      }
    } catch (_) {
      setState(() => _activePincode = "Enter Pincode");
      await _loadByPincode(null);
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  // ---------------------------
  // API fetcher
  // GET /offers/local?pincode=XXXXXX
  // response: { success, pincode, shops:[], products:[] }
  // ---------------------------
  Future<void> _loadByPincode(String? pin) async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
      _allProducts = [];
      _shopsById = {};
    });

    final clean = (pin ?? "").trim();

    if (!_isValidPincode(clean)) {
      setState(() {
        _loading = false;
        _error = "Set your 6-digit pincode to see offers in your area.";
      });
      return;
    }

    try {
      final url = Uri.parse(
          "$_apiBase/offers/local?pincode=${Uri.encodeQueryComponent(clean)}");

      final res = await http.get(url).timeout(_timeout);

      if (res.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = "Offers load failed (HTTP ${res.statusCode}).";
        });
        return;
      }

      final decodedAny = jsonDecode(res.body);

      // shops
      List shopsRaw = [];
      if (decodedAny is Map && decodedAny["shops"] is List) {
        shopsRaw = decodedAny["shops"] as List;
      }

      final Map<String, Map<String, dynamic>> shopsMap = {};
      for (final s in shopsRaw) {
        if (s is Map) {
          final m = Map<String, dynamic>.from(s.cast());
          final id = _s(m["id"] ?? m["_id"]).trim();
          if (id.isNotEmpty) shopsMap[id] = m;
        }
      }

      // products
      List rawList = [];
      if (decodedAny is Map && decodedAny["products"] is List) {
        rawList = decodedAny["products"] as List;
      } else if (decodedAny is Map && decodedAny["offers"] is List) {
        rawList = decodedAny["offers"] as List;
      } else if (decodedAny is List) {
        rawList = decodedAny;
      }

      final List<Map<String, dynamic>> list = [];
      for (final e in rawList) {
        if (e is Map) {
          list.add(Map<String, dynamic>.from(e.cast()));
        }
      }

      setState(() {
        _shopsById = shopsMap;
        _allProducts = list;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _error = "Offers load failed (network/parse error).";
      });
    }
  }

  // ---------------------------
  // UI
  // ---------------------------
  @override
  Widget build(BuildContext context) {
    final data = _view();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Text(
          "Product Offers",
          style: GoogleFonts.poppins(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _gpsLoading ? null : _detectPincodeAndLoad,
            icon: _gpsLoading
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.deepPurple,
              ),
            )
                : const Icon(Icons.my_location, color: Colors.deepPurple),
            tooltip: "Use GPS",
          ),
          IconButton(
            onPressed: () async {
              final pin = _activePincode.trim();
              if (_isValidPincode(pin)) {
                await _loadByPincode(pin);
              } else {
                _snack("Enter valid pincode");
              }
            },
            icon: const Icon(Icons.refresh, color: Colors.deepPurple),
            tooltip: "Refresh",
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchAndLocationHeader(),
          _buildCategorySlider(),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              color: Colors.deepPurple,
              onRefresh: () async {
                final pin = _activePincode.trim();
                if (_isValidPincode(pin)) {
                  await _loadByPincode(pin);
                } else {
                  final typed = _searchPinCtrl.text.trim();
                  if (_isValidPincode(typed)) {
                    setState(() => _activePincode = typed);
                    await _loadByPincode(typed);
                  }
                }
              },
              child: _buildList(
                loading: _loading,
                error: _error,
                data: data,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndLocationHeader() {
    final pin = _activePincode.trim();
    final isOk = _isValidPincode(pin);

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
              controller: _searchPinCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              onSubmitted: (val) async {
                final typed = val.trim();
                if (_isValidPincode(typed)) {
                  setState(() => _activePincode = typed);
                  await _loadByPincode(typed);
                } else {
                  _snack("Enter valid 6-digit pincode");
                }
              },
              decoration: const InputDecoration(
                counterText: "",
                hintText: "Search by Pincode...",
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
                  isOk ? "Your Area: $pin" : "Your Area: $_activePincode",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  final typed = _searchPinCtrl.text.trim();
                  if (_isValidPincode(typed)) {
                    setState(() => _activePincode = typed);
                    await _loadByPincode(typed);
                  } else {
                    _snack("Enter valid 6-digit pincode");
                  }
                },
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
          final c = _categories[i];
          final isSelected = _selectedCategory == c;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(c),
              selected: isSelected,
              onSelected: (_) => setState(() => _selectedCategory = c),
              selectedColor: Colors.deepPurple,
              backgroundColor: Colors.grey.shade100,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
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

  Widget _buildList({
    required bool loading,
    required String? error,
    required List<Map<String, dynamic>> data,
  }) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.deepPurple),
      );
    }

    if (error != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
        ],
      );
    }

    if (data.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.local_offer_outlined,
                    size: 80, color: Colors.grey.shade300),
                const SizedBox(height: 10),
                Text(
                  "No offers found for this pincode/category",
                  style: GoogleFonts.poppins(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      itemCount: data.length,
      itemBuilder: (_, i) => _productCard(data[i]),
    );
  }

  Widget _productCard(Map<String, dynamic> p) {
    final img = _imageOf(p);

    final title = _s(p["name"], fallback: "Product");
    final shop = _shopName(p);
    final loc = _locationText(p);

    final price = _asDouble(p["price"], fallback: 0);
    final offerPrice = _asDouble(p["offer_price"], fallback: 0);
    final oldPrice = _asDouble(p["old_price"], fallback: 0);

    final showPrice = offerPrice > 0 ? offerPrice : price;
    final pct = _discountPct(p);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ProductDetailsPage(product: p)),
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
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 72,
                      width: 72,
                      color: const Color(0xFFEDEDED),
                      child: img.isNotEmpty
                          ? Image.network(
                        img,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.image_not_supported,
                          color: Colors.grey,
                          size: 34,
                        ),
                      )
                          : const Icon(Icons.image,
                          color: Colors.grey, size: 34),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          shop,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.location_on,
                                size: 16, color: Colors.grey.shade600),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                loc,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
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
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          "₹${showPrice.toStringAsFixed(0)}",
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (oldPrice > 0 && oldPrice > showPrice) ...[
                        const SizedBox(height: 8),
                        Text(
                          "₹${oldPrice.toStringAsFixed(0)}",
                          style: GoogleFonts.poppins(
                            color: Colors.grey,
                            decoration: TextDecoration.lineThrough,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "OFFER",
                          style: GoogleFonts.poppins(
                            color: Colors.green,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      if (pct > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          "Save $pct%",
                          style: GoogleFonts.poppins(
                            color: Colors.green,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
