import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/business_profile_controller.dart';
import '../product_details_page.dart';
import '../add_product_page.dart';
import '../../../services/business_api.dart';

import '../controllers/cart_controller.dart';

class BPProductsTab extends StatelessWidget {
  final BusinessProfileController ctrl;

  /// ✅ parent থেকে force owner (recommended)
  final bool? isOwnerOverride;

  const BPProductsTab({
    super.key,
    required this.ctrl,
    this.isOwnerOverride,
  });

  static const int _maxShow = 20;

  static const Color _g1 = Color(0xFFFF00CC);
  static const Color _g2 = Color(0xFF333399);

  // ---------------- SAFE HELPERS ----------------
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

  String _asString(dynamic v, {String fallback = ""}) =>
      v == null ? fallback : v.toString();

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);

    // try toJson()
    try {
      final dynamic toJson = (raw as dynamic).toJson;
      if (toJson != null) {
        final m = (raw as dynamic).toJson();
        if (m is Map) return Map<String, dynamic>.from(m);
      }
    } catch (_) {}

    return <String, dynamic>{};
  }

  List<String> _asImages(Map<String, dynamic> p) {
    final imgs = p["images"];
    if (imgs is List && imgs.isNotEmpty) {
      return imgs
          .map((e) => BusinessAPI.toPublicUrl((e ?? "").toString()))
          .where((s) => s.trim().isNotEmpty)
          .toList();
    }

    final one =
    (p["image_url"] ?? p["image"] ?? p["photo"] ?? p["logo_url"] ?? "")
        .toString();
    final fixed = BusinessAPI.toPublicUrl(one);
    if (fixed.trim().isNotEmpty) return [fixed];
    return [];
  }

  String _productId(Map<String, dynamic> p) =>
      (p["id"] ?? p["_id"] ?? p["product_id"] ?? p["productId"] ?? "")
          .toString()
          .trim();

  int _productIdInt(Map<String, dynamic> p) {
    final raw =
    (p["product_id"] ?? p["productId"] ?? p["_id"] ?? p["id"] ?? "")
        .toString()
        .trim();
    return int.tryParse(raw) ?? _asInt(p["id"], fallback: 0);
  }

  int _businessIdInt(Map<String, dynamic> p) {
    final raw = (p["business_id"] ??
        p["shop_id"] ??
        p["businessId"] ??
        p["shopId"] ??
        ctrl.businessId ??
        0)
        .toString()
        .trim();
    return int.tryParse(raw) ?? _asInt(raw, fallback: 0);
  }

  int _discountPercent({required double price, required double mrp}) {
    if (mrp <= 0 || price <= 0) return 0;
    if (mrp <= price) return 0;
    return (((mrp - price) / mrp) * 100).round();
  }

  void _snack(BuildContext context, String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  bool _openBoxOf(Map<String, dynamic> p) {
    final v = p["open_box_delivery"];
    if (v is bool) return v;
    if (v is num) return v.toInt() == 1;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == "1" || s == "true" || s == "yes";
    }
    return false;
  }

  Map<String, dynamic> _normalizeForCart(Map<String, dynamic> p) {
    final out = Map<String, dynamic>.from(p);

    final bid = _businessIdInt(out);
    if (bid > 0) {
      out["business_id"] = bid;
      out["shop_id"] = bid;
    }

    final pid = _productIdInt(out);
    if (pid > 0) out["product_id"] = pid;

    out["id"] =
        out["id"] ?? out["_id"] ?? out["product_id"] ?? out["productId"];

    final imgs = _asImages(out);
    if (imgs.isNotEmpty) {
      out["image"] = imgs.first;
      out["image_url"] = imgs.first;
      out["images"] = imgs;
    }

    out["price"] = _asDouble(out["price"], fallback: 0);
    out["offer_price"] = _asDouble(out["offer_price"], fallback: 0);
    out["old_price"] = _asDouble(out["old_price"] ?? out["mrp"], fallback: 0);

    out["qty"] = _asInt(out["qty"], fallback: 1);
    out["selected_color"] = _asString(out["selected_color"]);
    out["selected_size"] = _asString(out["selected_size"]);

    return out;
  }

  // =============================================================
  // ✅ OWNER MENU (EDIT / DELETE ONLY)  ✅ ADD REMOVED
  // =============================================================
  Future<void> _openOwnerMenu(BuildContext context,
      {required Map<String, dynamic> product}) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 4,
                width: 44,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 10),

              ListTile(
                leading: const Icon(Icons.edit, color: Colors.deepPurple),
                title: const Text("Edit Product",
                    style: TextStyle(fontWeight: FontWeight.w900)),
                subtitle: const Text("Update name, images, price, stock…"),
                onTap: () => Navigator.pop(context, "edit"),
              ),

              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text("Delete Product",
                    style: TextStyle(fontWeight: FontWeight.w900)),
                subtitle: const Text(
                    "This removes from server (soft/hard depends on backend)."),
                onTap: () => Navigator.pop(context, "delete"),
              ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );

    if (action == "edit") {
      final businessId = _asString(
        product["business_id"] ??
            product["shop_id"] ??
            product["businessId"] ??
            ctrl.businessId,
      ).trim();

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AddProductPage(
            businessId: businessId,
            editMode: true,
            initialProduct: product,
          ),
        ),
      );

      if (context.mounted) {
        if (result is Map && result["product"] is Map) {
          ctrl.upsertProduct(Map<String, dynamic>.from(result["product"] as Map));
        } else if (result == true) {
          await ctrl.refresh();
        }
      }
      return;
    }

    if (action == "delete") {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Delete Product?"),
          content:
          const Text("This will remove the product from your business profile."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Delete", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      final id = _productId(product);
      if (id.isEmpty) {
        _snack(context, "Product id missing", error: true);
        return;
      }

      final ok = await ctrl.deleteProduct(id);

      if (!context.mounted) return;
      _snack(context, ok ? "Product deleted ✅" : "Delete failed ❌", error: !ok);
    }
  }

  // =============================================================
  // PRODUCT CARD
  // =============================================================
  Widget _productCard(BuildContext context, Map<String, dynamic> p,
      {required bool isOwnerNow}) {
    final name = _asString(p["name"], fallback: "Product");

    final offer = _asDouble(p["offer_price"], fallback: 0);
    final base = _asDouble(p["price"], fallback: 0);
    final price = offer > 0 ? offer : base;

    final mrp = _asDouble(p["old_price"] ?? p["mrp"], fallback: 0);

    final stock = _asInt(p["stock"], fallback: 0);
    final outOfStock = stock <= 0;

    final openBoxDelivery = _openBoxOf(p);
    final disabledAll = outOfStock || !openBoxDelivery;

    final off = _discountPercent(price: price, mrp: mrp);

    final imgs = _asImages(p);
    final image = imgs.isNotEmpty ? imgs.first : "";

    final bid = _businessIdInt(p);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductDetailsPage(
              product: p,
              businessId: bid > 0 ? bid : _businessIdInt({"business_id": ctrl.businessId}),
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: SizedBox.expand(
                      child: image.isNotEmpty
                          ? Image.network(
                        image,
                        fit: BoxFit.cover,
                        loadingBuilder: (c, w, e) {
                          if (e == null) return w;
                          return Container(
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        },
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: Icon(Icons.broken_image, size: 36, color: Colors.grey),
                          ),
                        ),
                      )
                          : Container(
                        color: Colors.grey.shade200,
                        child: const Center(
                          child: Icon(Icons.image_not_supported, size: 36, color: Colors.grey),
                        ),
                      ),
                    ),
                  ),

                  if (off > 0)
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.green.withOpacity(0.25)),
                        ),
                        child: Text(
                          "$off% OFF",
                          style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.green),
                        ),
                      ),
                    ),

                  if (outOfStock)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.35),
                        alignment: Alignment.center,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            "OUT OF STOCK",
                            style: TextStyle(fontWeight: FontWeight.w900, color: Colors.red),
                          ),
                        ),
                      ),
                    ),

                  // ✅ Owner ⋮ menu (Edit/Delete only)
                  if (isOwnerNow)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: InkWell(
                        onTap: () => _openOwnerMenu(context, product: p),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.92),
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
                            ],
                          ),
                          child: const Icon(Icons.more_vert, size: 18),
                        ),
                      ),
                    ),

                  // ✅ Buyer cart button
                  if (!isOwnerNow)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: InkWell(
                        onTap: disabledAll
                            ? () {
                          if (outOfStock) {
                            _snack(context, "Out of stock ❌", error: true);
                            return;
                          }
                          _snack(context, "Add disabled (Open Box OFF) ❌", error: true);
                        }
                            : () {
                          final cart = Provider.of<CartController>(context, listen: false);
                          cart.addToCart(_normalizeForCart(p));
                          _snack(context, "Added to cart ✅");
                        },
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.92),
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
                            ],
                          ),
                          child: Icon(
                            Icons.add_shopping_cart_rounded,
                            size: 20,
                            color: disabledAll ? Colors.grey : Colors.deepPurple,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Row(
                children: [
                  Text(
                    "₹${price.toStringAsFixed(0)}",
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.deepPurple,
                    ),
                  ),
                  if (mrp > 0 && mrp > price) ...[
                    const SizedBox(width: 8),
                    Text(
                      "₹${mrp.toStringAsFixed(0)}",
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        decoration: TextDecoration.lineThrough,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: outOfStock ? Colors.red.withOpacity(0.10) : Colors.blueGrey.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: outOfStock ? Colors.red.withOpacity(0.18) : Colors.blueGrey.withOpacity(0.18),
                      ),
                    ),
                    child: Text(
                      outOfStock ? "Out" : "In Stock",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: outOfStock ? Colors.red : Colors.blueGrey,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: SizedBox(
                width: double.infinity,
                height: 38,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [
                        (disabledAll ? Colors.grey : _g1).withOpacity(0.75),
                        (disabledAll ? Colors.grey : _g2).withOpacity(0.75),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: ElevatedButton(
                    onPressed: disabledAll
                        ? null
                        : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProductDetailsPage(
                            product: p,
                            businessId: bid > 0 ? bid : _businessIdInt({"business_id": ctrl.businessId}),
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      disabledForegroundColor: Colors.white70,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      outOfStock ? "OUT OF STOCK" : (!openBoxDelivery ? "BUY DISABLED" : "BUY NOW"),
                      style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        final bool isOwnerNow = isOwnerOverride ?? ctrl.isOwner;
        final pager = ctrl.productsPager;

        if (pager.loadingFirst && pager.items.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (pager.error.isNotEmpty && pager.items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(pager.error, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => pager.loadFirst(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ctrl.refresh(),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.pixels >= n.metrics.maxScrollExtent - 220) {
                pager.loadNext();
              }
              return false;
            },
            child: pager.items.isEmpty
                ? const Center(
                    child: Text(
                      'No products added yet',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  )
                : GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: pager.items.length + (pager.hasMore ? 1 : 0),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.70,
                    ),
                    itemBuilder: (context, index) {
                      if (index >= pager.items.length) {
                        if (pager.loadingNext) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        return Center(
                          child: TextButton.icon(
                            onPressed: () => pager.loadNext(),
                            icon: const Icon(Icons.expand_more),
                            label: const Text('Load more'),
                          ),
                        );
                      }
                      final p = _asMap(pager.items[index]);
                      if (p.isEmpty) return const SizedBox.shrink();
                      return _productCard(context, p, isOwnerNow: isOwnerNow);
                    },
                  ),
          ),
        );
      },
    );
  }
}
