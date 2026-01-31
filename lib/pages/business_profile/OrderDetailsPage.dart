import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:troonky_link/services/order_api.dart';

class OrderDetailsPage extends StatefulWidget {
  final Map<String, dynamic> order;
  const OrderDetailsPage({super.key, required this.order});

  @override
  State<OrderDetailsPage> createState() => _OrderDetailsPageState();
}

class _OrderDetailsPageState extends State<OrderDetailsPage> {
  bool loading = false;
  String error = "";
  late Map<String, dynamic> order;

  @override
  void initState() {
    super.initState();
    order = OrdersAPI.normalizeOrderForUi(widget.order);
    _refreshDetails();
  }

  // ================== Safe Helpers ==================
  String _s(dynamic v, {String fb = "-"}) {
    final x = (v ?? "").toString().trim();
    return x.isEmpty ? fb : x;
  }

  int _i(dynamic v, {int fb = 0}) {
    if (v == null) return fb;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim()) ?? fb;
  }

  double _d(dynamic v, {double fb = 0}) {
    if (v == null) return fb;
    if (v is num) return v.toDouble();
    final s = v.toString().replaceAll("₹", "").trim();
    return double.tryParse(s) ?? fb;
  }

  dynamic _tryJson(dynamic v) {
    if (v == null) return null;
    if (v is Map || v is List) return v;
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return null;
      try {
        return jsonDecode(s);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Map<String, dynamic> _safeMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  void _snack(String msg, {bool bad = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: bad ? Colors.red : Colors.green,
      ),
    );
  }

  // ================== IDs + Status ==================
  String _orderIdUi() {
    final code = _s(order["order_code"], fb: "");
    if (code.isNotEmpty) return code;
    return _s(order["id"], fb: "-");
  }

  String _orderIdApi() => _s(order["id"], fb: "");

  String _status() => OrdersAPI.normalizeStatus(order["status"] ?? order["order_status"]);

  String _payStatus() {
    final s = _s(order["payment_status"] ?? order["pay_status"] ?? order["paymentStatus"], fb: "");
    if (s.isEmpty) return "unknown";
    final x = s.toLowerCase();
    if (x.contains("paid") || x == "success") return "paid";
    if (x.contains("fail")) return "failed";
    if (x.contains("refund")) return "refunded";
    if (x.contains("pending") || x == "unpaid") return "pending";
    return x;
  }

  String _payMode() {
    final s = _s(order["payment_mode"] ?? order["paymentMode"] ?? order["pay_mode"], fb: "");
    return s.isEmpty ? "-" : s.toUpperCase();
  }

  bool get _isTerminal {
    final s = _status();
    return s == "cancelled" || s == "completed" || s == "rejected" || s == "failed";
  }

  // ================== Allowed Actions (State Machine Style) ==================
  // ✅ backend flow we just tested:
  // created -> processing -> ready -> shipped -> out_for_delivery -> delivered -> completed
  bool get _canAccept =>
      !_isTerminal && (_status() == "created" || _status() == "payment_pending" || _status() == "paid");

  bool get _canReady => !_isTerminal && (_status() == "processing");
  bool get _canShip => !_isTerminal && (_status() == "ready");

  bool get _canOutForDelivery => !_isTerminal && (_status() == "shipped");
  bool get _canDeliver => !_isTerminal && (_status() == "out_for_delivery");

  bool get _canComplete => !_isTerminal && (_status() == "delivered");

  // ✅ backend allows cancel from created/processing/ready (and probably shipped/out_for_delivery too)
  // but keep it safe: not after delivered
  bool get _canCancel => !_isTerminal && _status() != "delivered";

  // ================== Items ==================
  List<dynamic> _itemsList() {
    dynamic items = order["items"] ??
        order["order_items"] ??
        order["orderItems"] ??
        order["cart_items"] ??
        order["products"] ??
        order["product_items"];

    if (items is Map) {
      final m = _safeMap(items);
      items = m["items"] ?? m["order_items"] ?? m["products"] ?? m["data"];
    }

    final decoded = _tryJson(items);
    if (decoded is List) return decoded;
    return <dynamic>[];
  }

  String _itemName(Map m) {
    final product = (m["product"] is Map) ? _safeMap(m["product"]) : <String, dynamic>{};
    final v = m["name"] ??
        m["product_name"] ??
        m["title"] ??
        product["name"] ??
        product["title"] ??
        product["product_name"];
    return _s(v, fb: "Item");
  }

  int _itemQty(Map m) {
    final v = m["qty"] ?? m["quantity"] ?? m["count"] ?? m["product_qty"];
    final q = _i(v, fb: 1);
    return q <= 0 ? 1 : q;
  }

  double _itemUnitPrice(Map m) {
    final product = (m["product"] is Map) ? _safeMap(m["product"]) : <String, dynamic>{};
    final v = m["unit_price"] ??
        m["price"] ??
        m["offer_price"] ??
        m["amount"] ??
        product["unit_price"] ??
        product["price"] ??
        product["offer_price"];
    return _d(v, fb: 0);
  }

  String _itemColor(Map m) => _s(m["selected_color"] ?? m["color"], fb: "");
  String _itemSize(Map m) => _s(m["selected_size"] ?? m["size"], fb: "");

  // ================== Refresh Details ==================
  Future<void> _refreshDetails() async {
    final oid = _orderIdApi();
    if (oid.isEmpty) return;

    setState(() {
      loading = true;
      error = "";
    });

    try {
      final details = await OrdersAPI.getOrderDetails(oid);
      if (!mounted) return;
      if (details.isNotEmpty) {
        setState(() => order = OrdersAPI.normalizeOrderForUi(details));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => error = "Failed to load full order details");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ================== Actions ==================
  Future<void> _acceptFlow() async {
    final oid = _orderIdApi();
    if (oid.isEmpty) return;

    final nameCtrl = TextEditingController(text: _s(order["delivery_partner_name"], fb: ""));
    final phoneCtrl = TextEditingController(text: _s(order["delivery_partner_phone"], fb: ""));
    final etaCtrl = TextEditingController(text: _s(order["delivery_eta"], fb: ""));

    bool submitting = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: !submitting,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setD) {
            final name = nameCtrl.text.trim();
            final phone = phoneCtrl.text.trim();
            final eta = etaCtrl.text.trim();
            final phoneDigits = phone.replaceAll(RegExp(r"[^0-9]"), "");
            final phoneOk = phoneDigits.length >= 10 && phoneDigits.length <= 13;
            final valid = name.isNotEmpty && phoneOk && eta.isNotEmpty;

            return AlertDialog(
              title: const Text("Accept Order"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Delivery info required (production-grade).",
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: "Delivery Partner Name *",
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setD(() {}),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(13),
                    ],
                    decoration: InputDecoration(
                      labelText: "Delivery Partner Phone *",
                      border: const OutlineInputBorder(),
                      errorText: (phone.isEmpty || phoneOk) ? null : "Enter valid phone (10-13 digits)",
                    ),
                    onChanged: (_) => setD(() {}),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: etaCtrl,
                    decoration: const InputDecoration(
                      labelText: "Delivery ETA *",
                      hintText: "e.g. Today 6pm / 2 days",
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setD(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.pop(context, false),
                  child: const Text("Close"),
                ),
                ElevatedButton(
                  onPressed: (!valid || submitting)
                      ? null
                      : () async {
                    setD(() => submitting = true);

                    // ✅ backend canonical: created -> processing
                    final done = await OrdersAPI.updateOrder(
                      orderId: oid,
                      status: "processing",
                      deliveryPartnerName: name,
                      deliveryPartnerPhone: phone,
                      deliveryEta: eta,
                    );

                    if (context.mounted) Navigator.pop(context, done);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                  child: submitting
                      ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : const Text("ACCEPT", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok == true) {
      _snack("Order accepted ✅");
      await _refreshDetails();
    } else if (ok == false) {
      _snack("Accept failed ❌", bad: true);
    }
  }

  Future<void> _simpleTransition({
    required String toStatus,
    String title = "Update Order",
    String? helpText,
    bool requireReason = false,
    bool danger = false,
  }) async {
    final oid = _orderIdApi();
    if (oid.isEmpty) return;

    final reasonCtrl = TextEditingController();
    bool submitting = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: !submitting,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setD) {
            final reason = reasonCtrl.text.trim();
            final valid = requireReason ? reason.isNotEmpty : true;

            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (helpText != null && helpText.trim().isNotEmpty) ...[
                    Text(helpText, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                  ],
                  if (requireReason)
                    TextField(
                      controller: reasonCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: "Reason *",
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setD(() {}),
                    )
                  else
                    Text(
                      "This will set status to: ${OrdersAPI.normalizeStatus(toStatus).toUpperCase()}",
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.pop(context, false),
                  child: const Text("Close"),
                ),
                ElevatedButton(
                  onPressed: (!valid || submitting)
                      ? null
                      : () async {
                    setD(() => submitting = true);

                    final done = await OrdersAPI.updateOrder(
                      orderId: oid,
                      status: toStatus,
                      cancelReason: requireReason ? reasonCtrl.text.trim() : null,
                    );

                    if (context.mounted) Navigator.pop(context, done);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: danger ? Colors.red : Colors.deepPurple),
                  child: submitting
                      ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : Text(danger ? "CONFIRM" : "UPDATE", style: const TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok == true) {
      _snack("Status updated ✅");
      await _refreshDetails();
    } else if (ok == false) {
      _snack("Update failed ❌", bad: true);
    }
  }

  Future<void> _cancelFlow() async {
    await _simpleTransition(
      toStatus: "cancelled",
      title: "Cancel Order",
      helpText: "Cancellation reason required.",
      requireReason: true,
      danger: true,
    );
  }

  // ================== UI helpers ==================
  Color _badgeColor(String v) {
    final s = v.toLowerCase();
    if (s.contains("paid") || s == "completed" || s == "delivered" || s == "processing") return Colors.green;
    if (s.contains("fail") || s.contains("cancel") || s.contains("reject")) return Colors.red;
    if (s.contains("out_for_delivery")) return Colors.teal;
    if (s.contains("ship")) return Colors.blue;
    if (s.contains("ready") || s.contains("pack")) return Colors.orange;
    return Colors.grey;
  }

  Widget _badge(String text) {
    final bg = _badgeColor(text).withOpacity(0.10);
    final br = _badgeColor(text).withOpacity(0.25);
    final fg = _badgeColor(text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: br),
      ),
      child: Text(text.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: fg)),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v, {bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(k, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w800))),
          if (copyable)
            IconButton(
              tooltip: "Copy",
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: v));
                _snack("Copied ✅");
              },
              icon: const Icon(Icons.copy, size: 18),
            ),
        ],
      ),
    );
  }

  Widget _itemsSection(List items) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Items (${items.length})", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            if (items.isEmpty)
              const Text("No items found", style: TextStyle(color: Colors.grey))
            else
              for (final it in items) _itemTile(it),
          ],
        ),
      ),
    );
  }

  Widget _itemTile(dynamic it) {
    final m = (it is Map) ? Map<String, dynamic>.from(it) : <String, dynamic>{};

    final name = _itemName(m);
    final qty = _itemQty(m);
    final unit = _itemUnitPrice(m);
    final line = (unit > 0) ? (qty * unit) : 0;

    final color = _itemColor(m);
    final size = _itemSize(m);

    final pillBg = Colors.deepPurple.withOpacity(0.10);
    final pillBorder = Colors.deepPurple.withOpacity(0.18);

    Widget pill(String text, {Color? bg, Color? border}) {
      final b = bg ?? pillBg;
      final br = border ?? pillBorder;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: b,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: br),
        ),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.black87)),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              pill("Qty: $qty"),
              pill("Unit: ₹${unit > 0 ? unit.toStringAsFixed(0) : '-'}"),
              pill("Total: ₹${line > 0 ? line.toStringAsFixed(0) : '-'}"),
              if (color.isNotEmpty)
                pill(
                  "Color: $color",
                  bg: Colors.teal.withOpacity(0.08),
                  border: Colors.teal.withOpacity(0.14),
                ),
              if (size.isNotEmpty)
                pill(
                  "Size: $size",
                  bg: Colors.orange.withOpacity(0.10),
                  border: Colors.orange.withOpacity(0.16),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ================== Build ==================
  @override
  Widget build(BuildContext context) {
    final orderId = _orderIdUi();
    final status = _status();
    final pay = _payStatus();

    final createdAt = _s(order["created_at"], fb: "-");
    final amount = _s(order["total_amount"], fb: "0");
    final amountNum = _d(amount, fb: 0);
    final amountText = amountNum > 0 ? amountNum.toStringAsFixed(0) : amount;

    final customerName = _s(order["customer_name"], fb: "Unknown Customer");
    final customerPhone = _s(order["phone"], fb: "-");
    final pincode = _s(order["pincode"], fb: "-");
    final address = _s(order["address"], fb: "-");

    final cancelReason = _s(order["cancel_reason"], fb: "");
    final dpName = _s(order["delivery_partner_name"], fb: "");
    final dpPhone = _s(order["delivery_partner_phone"], fb: "");
    final eta = _s(order["delivery_eta"], fb: "");

    final items = _itemsList();

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text("Order Details"),
        backgroundColor: Colors.deepPurple,
        actions: [
          IconButton(
            onPressed: loading ? null : _refreshDetails,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshDetails,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(error, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w800)),
              ),
            if (loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: LinearProgressIndicator(minHeight: 3),
              ),

            // Header summary
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Order: $orderId", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _badge(status),
                              _badge("pay:$pay"),
                              _badge("mode:${_payMode()}"),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: "Copy Order ID",
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: orderId));
                        _snack("Order ID copied ✅");
                      },
                      icon: const Icon(Icons.copy),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            _section("Order Info", [
              _kv("Order ID", orderId, copyable: true),
              _kv("Status", status.toUpperCase()),
              _kv("Date", createdAt),
              _kv("Total Amount", "₹$amountText"),
              _kv("Payment", "${pay.toUpperCase()} (${_payMode()})"),
            ]),
            const SizedBox(height: 12),

            _section("Customer Info", [
              _kv("Name", customerName),
              _kv("Phone", customerPhone, copyable: customerPhone != "-"),
              _kv("Pincode", pincode),
              _kv("Address", address),
            ]),
            const SizedBox(height: 12),

            if (cancelReason.isNotEmpty) ...[
              _section("Cancellation", [_kv("Reason", cancelReason)]),
              const SizedBox(height: 12),
            ],

            if (dpName.isNotEmpty || dpPhone.isNotEmpty || eta.isNotEmpty) ...[
              _section("Delivery Info", [
                _kv("Partner", dpName.isEmpty ? "-" : dpName),
                _kv("Partner Phone", dpPhone.isEmpty ? "-" : dpPhone),
                _kv("ETA", eta.isEmpty ? "-" : eta),
              ]),
              const SizedBox(height: 12),
            ],

            _itemsSection(items),
            const SizedBox(height: 14),

            // Actions (state-machine style)
            if (!_isTerminal)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_canAccept)
                    SizedBox(
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: loading ? null : _acceptFlow,
                        icon: const Icon(Icons.check, color: Colors.white),
                        label: const Text(
                          "ACCEPT ORDER",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),

                  if (_canReady) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: loading
                            ? null
                            : () => _simpleTransition(
                          toStatus: "ready",
                          title: "Mark as READY",
                          helpText: "After packing, mark READY.",
                        ),
                        icon: const Icon(Icons.inventory_2, color: Colors.white),
                        label: const Text(
                          "MARK READY",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],

                  if (_canShip) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: loading
                            ? null
                            : () => _simpleTransition(
                          toStatus: "shipped",
                          title: "Mark as SHIPPED",
                          helpText: "Courier picked up / delivered to rider.",
                        ),
                        icon: const Icon(Icons.local_shipping, color: Colors.white),
                        label: const Text(
                          "MARK SHIPPED",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],

                  // ✅ shipped -> out_for_delivery (separate button)
                  if (_canOutForDelivery) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: loading
                            ? null
                            : () => _simpleTransition(
                          toStatus: "out_for_delivery",
                          title: "Mark as OUT FOR DELIVERY",
                          helpText: "Rider is on the way to customer.",
                        ),
                        icon: const Icon(Icons.directions_bike, color: Colors.white),
                        label: const Text(
                          "OUT FOR DELIVERY",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],

                  // ✅ out_for_delivery -> delivered
                  if (_canDeliver) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: loading
                            ? null
                            : () => _simpleTransition(
                          toStatus: "delivered",
                          title: "Mark as DELIVERED",
                          helpText: "Customer received the product.",
                        ),
                        icon: const Icon(Icons.home_filled, color: Colors.white),
                        label: const Text(
                          "MARK DELIVERED",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],

                  if (_canComplete) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: loading
                            ? null
                            : () => _simpleTransition(
                          toStatus: "completed",
                          title: "Complete Order",
                          helpText: "After delivery verification, complete order.",
                        ),
                        icon: const Icon(Icons.verified, color: Colors.white),
                        label: const Text(
                          "COMPLETE ORDER",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black87,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],

                  if (_canCancel) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: loading ? null : _cancelFlow,
                        icon: const Icon(Icons.close, color: Colors.white),
                        label: const Text(
                          "CANCEL ORDER",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ],
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  "This order is closed (status: ${status.toUpperCase()}).",
                  style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
