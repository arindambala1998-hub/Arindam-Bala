// lib/pages/business_profile/add_product_page.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../helpers/image_compressor.dart';
import 'controllers/product_controller.dart';

// ✅ for /uploads -> full URL normalize (display only)
import '../../services/business_api.dart';

class AddProductPage extends StatefulWidget {
  final String businessId;

  /// ✅ EDIT support
  final bool editMode;
  final Map<String, dynamic>? initialProduct;

  const AddProductPage({
    super.key,
    required this.businessId,
    this.editMode = false,
    this.initialProduct,
  });

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  static const int _maxProductsPerBusiness = 20;
  static const int _maxImagesTotal = 5;

  // ✅ Official gradient (Troonky style)
  static const Color _g1 = Color(0xFFFF00CC);
  static const Color _g2 = Color(0xFF333399);

  // ✅ Offer rule
  static const double _minOfferPercent = 20.0;

  final _formKey = GlobalKey<FormState>();

  // Controllers
  final nameCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  final oldPriceCtrl = TextEditingController();
  final stockCtrl = TextEditingController();
  final descCtrl = TextEditingController();

  // META (optional)
  final brandCtrl = TextEditingController();
  final materialCtrl = TextEditingController();
  final weightCtrl = TextEditingController();
  final colorListCtrl = TextEditingController();
  final sizeListCtrl = TextEditingController();

  // ✅ Delivery & Trust (MANDATORY)
  final returnDaysCtrl = TextEditingController(text: "7");
  final pincodeCtrl = TextEditingController(); // ✅ up to 10 pincodes

  // Specs dynamic rows (optional)
  final List<TextEditingController> _specKeyCtrls = [TextEditingController()];
  final List<TextEditingController> _specValCtrls = [TextEditingController()];

  bool _isSaving = false;

  // Trust flags
  bool _codAvailable = true;
  bool _openBoxDelivery = true;
  bool _isOriginal = true;

  // ✅ NEW: Offer flag (only if discount >= 20%)
  bool _addOffer = false;

  // Images
  final List<File> productImages = []; // newly picked files
  final List<String> existingImageUrls = []; // server urls/paths (edit)

  // Category (MANDATORY)
  final List<String> _categories = const [
    "Electronics",
    "Fashion",
    "Grocery",
    "Beauty",
    "Home Decor",
    "Health",
    "Kids",
    "Sports",
    "Others",
  ];
  String _selectedCategory = "Others";

  // Discount UI state
  double? _discountPercent;

  // ─────────────────────────────────────────────
  // SAFE HELPERS
  // ─────────────────────────────────────────────
  String _asString(dynamic v, {String fallback = ""}) =>
      v == null ? fallback : v.toString();

  double _asDouble(dynamic v, {double fallback = 0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  int _asInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  String _productIdOf(Map<String, dynamic> p) =>
      (p["product_id"] ?? p["_id"] ?? p["id"] ?? p["productId"] ?? "").toString();

  bool _isValidNumber(String v) => double.tryParse(v.trim()) != null;
  bool _isValidInt(String v) => int.tryParse(v.trim()) != null;

  int get _remainingImageSlots =>
      _maxImagesTotal - (existingImageUrls.length + productImages.length);

  bool get _hasAnyImage =>
      productImages.isNotEmpty || existingImageUrls.isNotEmpty;

  bool get _canEnableOffer =>
      (_discountPercent != null) && (_discountPercent! >= _minOfferPercent);

  // ─────────────────────────────────────────────
  // INIT (prefill for edit)
  // ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    // ✅ auto discount calc
    priceCtrl.addListener(_updateDiscount);
    oldPriceCtrl.addListener(_updateDiscount);

    if (widget.editMode && widget.initialProduct != null) {
      final p = widget.initialProduct!;

      nameCtrl.text = _asString(p["name"]);
      priceCtrl.text = _asString(p["price"]);
      oldPriceCtrl.text = _asString(p["old_price"] ?? p["mrp"] ?? p["oldPrice"]);
      stockCtrl.text = _asString(p["stock"]);
      descCtrl.text = _asString(p["description"]);

      _selectedCategory = _asString(p["category"], fallback: "Others");
      if (!_categories.contains(_selectedCategory)) _selectedCategory = "Others";

      brandCtrl.text = _asString(p["brand"]);
      materialCtrl.text = _asString(p["material"]);
      weightCtrl.text = _asString(p["weight"]);

      final colors = p["colors"];
      if (colors is List) {
        colorListCtrl.text = colors
            .map((e) => e.toString())
            .where((s) => s.trim().isNotEmpty)
            .join(", ");
      }

      final sizes = p["sizes"];
      if (sizes is List) {
        sizeListCtrl.text = sizes
            .map((e) => e.toString())
            .where((s) => s.trim().isNotEmpty)
            .join(", ");
      }

      // ✅ Delivery & Trust (prefill)
      returnDaysCtrl.text = _asString(p["return_days"], fallback: "7");
      _codAvailable = (p["cod_available"] == true);
      _openBoxDelivery = (p["open_box_delivery"] == true);
      _isOriginal = (p["is_original"] != false);

      final pincodes = p["available_pincodes"];
      if (pincodes is List) {
        pincodeCtrl.text = pincodes
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .join(", ");
      } else {
        final pcStr = _asString(p["available_pincodes"]);
        if (pcStr.trim().isNotEmpty) pincodeCtrl.text = pcStr;
      }

      // ✅ Offer prefill (optional) - only if backend stores it
      _addOffer = (p["is_offer"] == true) || (p["offer_enabled"] == true);

      // specs (optional)
      _specKeyCtrls.forEach((c) => c.dispose());
      _specValCtrls.forEach((c) => c.dispose());
      _specKeyCtrls.clear();
      _specValCtrls.clear();

      final specsAny = p["specs"];
      if (specsAny is Map) {
        final specs = Map<String, dynamic>.from(specsAny);
        for (final entry in specs.entries) {
          _specKeyCtrls.add(TextEditingController(text: entry.key.toString()));
          _specValCtrls.add(TextEditingController(text: entry.value.toString()));
        }
      }

      if (_specKeyCtrls.isEmpty) {
        _specKeyCtrls.add(TextEditingController());
        _specValCtrls.add(TextEditingController());
      }

      // images from server (raw path keep)
      final imgs = p["images"];
      if (imgs is List) {
        existingImageUrls.addAll(
          imgs.map((e) => (e ?? "").toString()).where((s) => s.trim().isNotEmpty),
        );
      } else {
        final one = _asString(p["image"]);
        if (one.trim().isNotEmpty) existingImageUrls.add(one);
      }

      _updateDiscount(); // will also validate offer rule
    } else {
      _updateDiscount();
    }
  }

  @override
  void dispose() {
    priceCtrl.removeListener(_updateDiscount);
    oldPriceCtrl.removeListener(_updateDiscount);

    nameCtrl.dispose();
    priceCtrl.dispose();
    oldPriceCtrl.dispose();
    stockCtrl.dispose();
    descCtrl.dispose();

    brandCtrl.dispose();
    materialCtrl.dispose();
    weightCtrl.dispose();
    colorListCtrl.dispose();
    sizeListCtrl.dispose();

    returnDaysCtrl.dispose();
    pincodeCtrl.dispose();

    for (final c in _specKeyCtrls) {
      c.dispose();
    }
    for (final c in _specValCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  // =============================================================
  // UI HELPERS
  // =============================================================
  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.deepPurple,
      ),
    );
  }

  List<String> _parseCsvToList(String raw) {
    return raw
        .split(",")
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }

  Map<String, String> _buildSpecsMap() {
    final Map<String, String> specs = {};
    for (int i = 0; i < _specKeyCtrls.length; i++) {
      final k = _specKeyCtrls[i].text.trim();
      final v = _specValCtrls[i].text.trim();
      if (k.isNotEmpty && v.isNotEmpty) specs[k] = v;
    }
    return specs;
  }

  void _addSpecRow() {
    if (_specKeyCtrls.length >= 10) {
      _snack("Max 10 specs allowed.", error: true);
      return;
    }
    setState(() {
      _specKeyCtrls.add(TextEditingController());
      _specValCtrls.add(TextEditingController());
    });
  }

  void _removeSpecRow(int index) {
    if (_specKeyCtrls.length <= 1) return;
    setState(() {
      _specKeyCtrls[index].dispose();
      _specValCtrls[index].dispose();
      _specKeyCtrls.removeAt(index);
      _specValCtrls.removeAt(index);
    });
  }

  // =============================================================
  // DISCOUNT CALC (MRP vs Selling Price)
  // =============================================================
  void _updateDiscount() {
    final sp = double.tryParse(priceCtrl.text.trim());
    final mrp = double.tryParse(oldPriceCtrl.text.trim());

    double? next;
    if (sp != null && mrp != null && mrp > 0 && sp > 0 && sp < mrp) {
      final disc = ((mrp - sp) / mrp) * 100.0;
      next = disc.isFinite ? disc : null;
    } else {
      next = null;
    }

    final changed = (_discountPercent ?? -1) != (next ?? -1);

    if (changed) {
      setState(() => _discountPercent = next);
    }

    // ✅ enforce offer rule
    if (!_canEnableOffer && _addOffer) {
      setState(() => _addOffer = false);
    }
  }

  // =============================================================
  // IMAGE PICKER (max 5 total incl existing)
  // =============================================================
  Future<void> pickImage() async {
    final beforeRemaining = _remainingImageSlots;

    if (beforeRemaining <= 0) {
      _snack("Max $_maxImagesTotal images allowed.", error: true);
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 75);
    if (picked.isEmpty) return;

    int canAdd = beforeRemaining;

    for (final img in picked) {
      if (canAdd <= 0) break;

      final original = File(img.path);
      final compressed = await ImageCompressor.compress(original);
      productImages.add(compressed ?? original);
      canAdd--;
    }

    if (!mounted) return;
    setState(() {});

    if (picked.length > beforeRemaining) {
      _snack("Only $_maxImagesTotal images allowed (limit).");
    }
  }

  // =============================================================
  // PRODUCT LIMIT CHECK (20) - only when add (not edit)
  // =============================================================
  Future<bool> _checkProductLimit() async {
    if (widget.editMode) return true;

    final ctrl = Provider.of<ProductController>(context, listen: false);
    try {
      await ctrl.fetchProducts(widget.businessId);
      final count = ctrl.products.length;
      if (count >= _maxProductsPerBusiness) {
        _snack(
          "You already have $count products. Max $_maxProductsPerBusiness allowed.",
          error: true,
        );
        return false;
      }
      return true;
    } catch (_) {
      _snack("Could not verify product limit (network).", error: true);
      return true;
    }
  }

  // =============================================================
  // VALIDATE PINCODES (max 10, 6-digit)
  // =============================================================
  String? _validatePincodes(String raw) {
    final list = _parseCsvToList(raw);
    if (list.isEmpty) return "Add at least 1 pincode";
    if (list.length > 10) return "Max 10 pincodes allowed";

    for (final p in list) {
      final onlyDigits = RegExp(r'^\d{6}$');
      if (!onlyDigits.hasMatch(p)) {
        return "Invalid pincode: $p (must be 6 digits)";
      }
    }
    return null;
  }

  // =============================================================
  // BUILD PRODUCT DATA (backend ready for multipart)
  // ✅ Offer flag included (is_offer)
  // =============================================================
  Map<String, dynamic> _buildProductData() {
    final colors = _parseCsvToList(colorListCtrl.text);
    final sizes = _parseCsvToList(sizeListCtrl.text);
    final specs = _buildSpecsMap();
    final pincodes = _parseCsvToList(pincodeCtrl.text);

    final sp = _asDouble(priceCtrl.text.trim(), fallback: 0);
    final mrp = _asDouble(oldPriceCtrl.text.trim(), fallback: 0);
    final discount =
    (mrp > 0 && sp > 0 && sp < mrp) ? (((mrp - sp) / mrp) * 100.0) : 0.0;

    final base = <String, dynamic>{
      "business_id": widget.businessId,

      "name": nameCtrl.text.trim(),
      "description": descCtrl.text.trim(),
      "category": _selectedCategory,
      "price": sp,
      "old_price": mrp,
      "stock": _asInt(stockCtrl.text.trim(), fallback: 0),

      // images
      "images": productImages, // List<File>
      "existing_images": existingImageUrls, // List<String>

      // Optional meta
      "brand": brandCtrl.text.trim(),
      "material": materialCtrl.text.trim(),
      "weight": weightCtrl.text.trim(),
      "colors": colors,
      "sizes": sizes,
      "specs": specs,

      // Delivery & Trust
      "return_days": _asInt(returnDaysCtrl.text.trim(), fallback: 7),
      "available_pincodes": pincodes,
      "cod_available": _codAvailable,
      "open_box_delivery": _openBoxDelivery,
      "is_original": _isOriginal,

      // Discount badge
      "discount_percent": discount,

      // ✅ Offer flag (backend should use this to show in offers page)
      "is_offer": (_canEnableOffer && _addOffer),
    };

    if (widget.editMode && widget.initialProduct != null) {
      base["product_id"] = _productIdOf(widget.initialProduct!);
    }

    return base;
  }

  // =============================================================
  // SAVE / UPDATE PRODUCT
  // =============================================================
  Future<void> _saveOrUpdate() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    if (!_hasAnyImage) {
      _snack("Upload at least 1 image", error: true);
      return;
    }

    if ((existingImageUrls.length + productImages.length) > _maxImagesTotal) {
      _snack("Max $_maxImagesTotal images allowed.", error: true);
      return;
    }

    // Offer safety check
    if (_addOffer && !_canEnableOffer) {
      _snack("Offer needs minimum ${_minOfferPercent.toStringAsFixed(0)}% OFF", error: true);
      return;
    }

    final ok = await _checkProductLimit();
    if (!ok) return;

    final data = _buildProductData();

    if (widget.editMode) {
      final pid = _asString(data["product_id"]).trim();
      if (pid.isEmpty) {
        _snack("Product id missing", error: true);
        return;
      }
    }

    setState(() => _isSaving = true);

    final ctrl = Provider.of<ProductController>(context, listen: false);

    final success = await ctrl.saveOrUpdateProduct(
      data,
      editMode: widget.editMode,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      _snack(widget.editMode ? "Product updated ✅" : "Product saved ✅");
      final result = <String, dynamic>{
        "ok": true,
        "action": ctrl.lastAction ?? (widget.editMode ? "updated" : "created"),
        "product": ctrl.lastSavedProduct,
      };
      Navigator.pop(context, result);
    } else {
      _snack(
        widget.editMode ? "Failed to update product" : "Failed to save product",
        error: true,
      );
    }
  }

  // =============================================================
  // UI
  // =============================================================
  @override
  Widget build(BuildContext context) {
    final titleStyle = GoogleFonts.poppins(
      fontWeight: FontWeight.w800,
      fontSize: 18,
      color: Colors.white,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(
        elevation: 0,
        centerTitle: false,
        foregroundColor: Colors.white,
        title: Text(widget.editMode ? "Edit Product" : "Add Product", style: titleStyle),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_g1, _g2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      bottomNavigationBar: _bottomActions(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 120),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _topInfoCard(),
                const SizedBox(height: 12),

                // ✅ Product Images
                _sectionCard(
                  title: "Product Images",
                  icon: Icons.photo_library_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (existingImageUrls.isNotEmpty) ...[
                        _hint("Existing images (server)"),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 86,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: existingImageUrls.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 10),
                            itemBuilder: (_, i) {
                              final raw = existingImageUrls[i];
                              final url = BusinessAPI.toPublicUrl(raw);

                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Image.network(
                                      url,
                                      height: 86,
                                      width: 86,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        height: 86,
                                        width: 86,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(14),
                                          color: Colors.grey.shade200,
                                        ),
                                        child: const Icon(Icons.broken_image, color: Colors.grey),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: -6,
                                    right: -6,
                                    child: IconButton(
                                      icon: const Icon(Icons.cancel, color: Colors.red, size: 20),
                                      onPressed: _isSaving ? null : () => setState(() => existingImageUrls.removeAt(i)),
                                      tooltip: "Remove",
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      _hint("Add images (Total max $_maxImagesTotal). Remaining: $_remainingImageSlots"),
                      const SizedBox(height: 8),
                      _buildImagePicker(),
                      const SizedBox(height: 6),
                      Text(
                        "• At least 1 image is required",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ✅ General Information
                _sectionCard(
                  title: "General Information",
                  icon: Icons.info_outline,
                  child: Column(
                    children: [
                      _tf(
                        nameCtrl,
                        "Product Name",
                        "e.g. Wireless Headphones",
                        Icons.title,
                        requiredField: true,
                        validatorExtra: (v) => v.trim().length < 3 ? "Minimum 3 characters" : null,
                      ),
                      _tf(
                        descCtrl,
                        "Description",
                        "Short highlights...",
                        Icons.description_outlined,
                        requiredField: true,
                        maxLines: 3,
                        validatorExtra: (v) => v.trim().length < 10 ? "Write at least 10 characters" : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ✅ Category
                _sectionCard(
                  title: "Category",
                  icon: Icons.category_outlined,
                  child: DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    decoration: _inputDeco(label: "Category", icon: Icons.category_outlined),
                    items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: _isSaving ? null : (val) => setState(() => _selectedCategory = (val ?? "Others")),
                    validator: (v) => (v ?? "").trim().isEmpty ? "Required" : null,
                  ),
                ),
                const SizedBox(height: 12),

                // ✅ Pricing & Inventory
                _sectionCard(
                  title: "Pricing & Inventory",
                  icon: Icons.currency_rupee,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _tf(
                              priceCtrl,
                              "Selling Price",
                              "0.00",
                              Icons.currency_rupee,
                              keyboardType: TextInputType.number,
                              requiredField: true,
                              validatorExtra: (v) {
                                if (!_isValidNumber(v)) return "Invalid price";
                                if (_asDouble(v) <= 0) return "Price must be > 0";
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _tf(
                              oldPriceCtrl,
                              "MRP",
                              "0.00",
                              Icons.money_off_outlined,
                              keyboardType: TextInputType.number,
                              requiredField: true,
                              validatorExtra: (v) {
                                if (v.trim().isEmpty) return "Required";
                                if (!_isValidNumber(v)) return "Invalid MRP";
                                final mrp = _asDouble(v);
                                final sp = _asDouble(priceCtrl.text.trim(), fallback: 0);
                                if (mrp <= 0) return "MRP must be > 0";
                                if (sp > 0 && mrp < sp) return "MRP must be ≥ Selling Price";
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),

                      // ✅ Always show discount status nicely
                      const SizedBox(height: 2),
                      if (_discountPercent == null)
                        Text(
                          "Discount: 0% (Enter valid MRP and Selling Price)",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey.shade700,
                          ),
                        )
                      else
                        Text(
                          "${_discountPercent!.toStringAsFixed(0)}% OFF",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: (_discountPercent! >= _minOfferPercent) ? Colors.green : Colors.orange,
                          ),
                        ),

                      const SizedBox(height: 8),

                      _tf(
                        stockCtrl,
                        "Available Stock",
                        "e.g. 50",
                        Icons.inventory_2_outlined,
                        keyboardType: TextInputType.number,
                        requiredField: true,
                        validatorExtra: (v) {
                          if (!_isValidInt(v)) return "Invalid stock";
                          if (_asInt(v) < 0) return "Stock can't be negative";
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Optional: Variants
                _sectionCard(
                  title: "Variants (Optional)",
                  icon: Icons.tune,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _hint("Comma separated values. Example: Red, Blue, Black"),
                      _tf(colorListCtrl, "Colors", "Red, Blue, Black", Icons.palette_outlined, requiredField: false),
                      _hint("Example: S, M, L, XL or 6, 7, 8"),
                      _tf(sizeListCtrl, "Sizes", "S, M, L, XL", Icons.straighten_outlined, requiredField: false),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Optional: Extra Details
                _sectionCard(
                  title: "Extra Details (Optional)",
                  icon: Icons.receipt_long_outlined,
                  child: Column(
                    children: [
                      _tf(brandCtrl, "Brand", "e.g. Sony", Icons.branding_watermark_outlined, requiredField: false),
                      _tf(materialCtrl, "Material", "e.g. Cotton / Plastic", Icons.layers_outlined, requiredField: false),
                      _tf(weightCtrl, "Weight", "e.g. 450g / 1.2kg", Icons.scale_outlined, requiredField: false),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Optional: Specs
                _sectionCard(
                  title: "Key Specifications (Optional)",
                  icon: Icons.list_alt_outlined,
                  child: _buildSpecsEditor(),
                ),
                const SizedBox(height: 12),

                // ✅ Delivery & Trust
                _sectionCard(
                  title: "Delivery & Trust",
                  icon: Icons.verified_outlined,
                  child: Column(
                    children: [
                      _tf(
                        returnDaysCtrl,
                        "Return Days",
                        "e.g. 7",
                        Icons.assignment_return_outlined,
                        keyboardType: TextInputType.number,
                        requiredField: true,
                        validatorExtra: (v) {
                          if (v.trim().isEmpty) return "Required";
                          final n = int.tryParse(v.trim());
                          if (n == null) return "Invalid";
                          if (n < 0 || n > 30) return "0-30 allowed";
                          return null;
                        },
                      ),
                      _tf(
                        pincodeCtrl,
                        "Available Pincodes (Max 10)",
                        "e.g. 700001, 700002",
                        Icons.location_on_outlined,
                        requiredField: true,
                        validatorExtra: (v) => _validatePincodes(v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _codAvailable,
                        onChanged: _isSaving ? null : (v) => setState(() => _codAvailable = v),
                        title: const Text("Cash on Delivery Available"),
                        activeColor: Colors.deepPurple,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _openBoxDelivery,
                        onChanged: _isSaving ? null : (v) => setState(() => _openBoxDelivery = v),
                        title: const Text("Open Box Delivery Available"),
                        subtitle: const Text("If OFF, product will list but Buy Now should be disabled on details page."),
                        activeColor: Colors.deepPurple,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _isOriginal,
                        onChanged: _isSaving ? null : (v) => setState(() => _isOriginal = v),
                        title: const Text("100% Original Product"),
                        activeColor: Colors.deepPurple,
                      ),

                      const SizedBox(height: 8),

                      // ✅ NEW: Add Offer Page block
                      _offerSection(),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _offerSection() {
    final disc = _discountPercent ?? 0.0;
    final ok = _canEnableOffer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ok ? Colors.green.withOpacity(0.35) : Colors.orange.withOpacity(0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_offer_outlined, color: ok ? Colors.green : Colors.orange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Add Offer Page",
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ),
              Switch(
                value: _addOffer,
                onChanged: (_isSaving || !ok)
                    ? null
                    : (v) {
                  setState(() => _addOffer = v);
                },
                activeColor: Colors.deepPurple,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "Minimum ${_minOfferPercent.toStringAsFixed(0)}% OFF হলে এটা apply করতে পারবে।",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Current Discount: ${disc.toStringAsFixed(0)}%",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: ok ? Colors.green : Colors.orange,
            ),
          ),
          if (!ok)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                "Offer enable করতে Selling Price কমাও বা MRP বাড়াও (কমপক্ষে ${_minOfferPercent.toStringAsFixed(0)}% দরকার)।",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.redAccent,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // =============================================================
  // TOP INFO CARD
  // =============================================================
  Widget _topInfoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [_g1.withOpacity(0.12), _g2.withOpacity(0.12)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.deepPurple.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(colors: [_g1, _g2]),
            ),
            child: const Icon(Icons.storefront, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.editMode
                  ? "Editing product • Keep/remove old images or add new ones"
                  : "Max $_maxProductsPerBusiness products per business • Max $_maxImagesTotal images per product",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =============================================================
  // SECTION CARD
  // =============================================================
  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.deepPurple),
              const SizedBox(width: 10),
              Text(
                title,
                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _hint(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
    );
  }

  InputDecoration _inputDeco({required String label, required IconData icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
    );
  }

  Widget _tf(
      TextEditingController ctrl,
      String label,
      String hint,
      IconData icon, {
        int maxLines = 1,
        TextInputType keyboardType = TextInputType.text,
        bool requiredField = true,
        String? Function(String v)? validatorExtra,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: _inputDeco(label: label, icon: icon).copyWith(hintText: hint),
        validator: (v) {
          final vv = (v ?? "").trim();
          if (requiredField && vv.isEmpty) return "Required";
          if (validatorExtra != null) return validatorExtra(vv);
          return null;
        },
      ),
    );
  }

  // =============================================================
  // IMAGE PICKER UI
  // =============================================================
  Widget _buildImagePicker() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        InkWell(
          onTap: _isSaving ? null : pickImage,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 86,
            width: 86,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.deepPurple.withOpacity(0.25)),
              color: Colors.deepPurple.withOpacity(0.06),
            ),
            child: const Icon(Icons.add_a_photo_outlined, color: Colors.deepPurple),
          ),
        ),
        ...productImages.map(
              (file) => Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(file, height: 86, width: 86, fit: BoxFit.cover),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.red, size: 20),
                  onPressed: _isSaving ? null : () => setState(() => productImages.remove(file)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =============================================================
  // SPECS EDITOR
  // =============================================================
  Widget _buildSpecsEditor() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          for (int i = 0; i < _specKeyCtrls.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _specKeyCtrls[i],
                      decoration: InputDecoration(
                        hintText: "Key (e.g. Brand)",
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _specValCtrls[i],
                      decoration: InputDecoration(
                        hintText: "Value (e.g. Sony)",
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: _isSaving ? null : () => _removeSpecRow(i),
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: "Remove",
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _isSaving ? null : _addSpecRow,
              icon: const Icon(Icons.add, color: Colors.deepPurple),
              label: const Text(
                "Add Spec",
                style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =============================================================
  // BOTTOM ACTIONS (Save/Update ONLY)
  // =============================================================
  Widget _bottomActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2)),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _isSaving ? null : _saveOrUpdate,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.deepPurple, width: 1.6),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: _isSaving
              ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : Text(
            widget.editMode ? "UPDATE PRODUCT" : "SAVE PRODUCT",
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.deepPurple,
            ),
          ),
        ),
      ),
    );
  }
}
