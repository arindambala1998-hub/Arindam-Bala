import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:troonky_link/services/order_api.dart';

class CartDetailsPage extends StatefulWidget {
  final Map<String, dynamic> order;
  final bool isService;

  const CartDetailsPage({
    super.key,
    required this.order,
    required this.isService,
  });

  @override
  State<CartDetailsPage> createState() => _CartDetailsPageState();
}

class _CartDetailsPageState extends State<CartDetailsPage> {
  bool loading = false;
  String error = "";
  late Map<String, dynamic> o;

  @override
  void initState() {
    super.initState();
    // ✅ normalize immediately so keys/images/status become consistent
    o = OrdersAPI.normalizeOrderForUi(Map<String, dynamic>.from(widget.order));
    _refresh();
  }

  // ---------------- Safe helpers ----------------
  String _s(dynamic v, {String fb = ""}) {
    final x = (v ?? "").toString().trim();
    return x.isEmpty ? fb : x;
  }

  double _d(dynamic v, {double fb = 0}) {
    if (v == null) return fb;
    if (v is num) return v.toDouble();
    final s = v.toString().replaceAll("₹", "").trim();
    return double.tryParse(s) ?? fb;
  }

  Map<String, dynamic> _map(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return {};
  }

  List _list(dynamic v) => (v is List) ? v : const [];

  // ---------------- IDs ----------------
  String _idForApi() {
    // prefer id already normalized by OrdersAPI.normalizeOrderForUi
    final id = _s(o["id"]);
    if (id.isNotEmpty) return id;

    // fallback: raw possibilities
    final id2 = _s(o["order_id"] ?? o["booking_id"] ?? o["_id"]);
    if (id2.isNotEmpty) return id2;

    // last resort (service): booking number/code (may fail if backend needs numeric)
    final bno = _s(o["booking_number"] ?? o["bookingNo"] ?? o["bookingNumber"]);
    if (bno.isNotEmpty) return bno;

    return "";
  }

  // ---------------- Status ----------------
  String _statusRaw() => _s(
    o["status"] ??
        o["order_status"] ??
        o["booking_status"] ??
        o["service_status"] ??
        o["payment_status"],
    fb: "pending",
  );

  /// ✅ Use OrdersAPI canonical normalization for product, and keep service safe.
  String _statusNorm(String status) {
    final s0 = status.trim().toLowerCase();

    if (widget.isService) {
      if (s0.isEmpty) return "pending";
      if (s0 == "approved" || s0 == "accepted" || s0 == "confirmed") return "approved";
      if (s0 == "done") return "completed";
      if (s0 == "canceled" || s0 == "cancel") return "cancelled";
      return s0;
    }

    return OrdersAPI.normalizeStatus(s0);
  }

  bool get _isTerminal {
    final s = _statusNorm(_statusRaw());
    return s == "cancelled" || s == "completed" || s == "rejected" || s == "failed";
  }

  bool get _canCancel {
    final s = _statusNorm(_statusRaw());
    if (_isTerminal) return false;
    // product: don't allow cancel after delivered
    if (!widget.isService && s == "delivered") return false;
    return true;
  }

  Color _statusColor(String status) {
    final s = _statusNorm(status);
    if (s.contains("cancel") || s == "rejected" || s == "failed") return Colors.red;
    if (s == "completed" || s == "delivered") return Colors.green;
    if (s == "shipped" || s == "out_for_delivery") return Colors.blue;
    if (s == "ready" || s == "processing") return Colors.deepPurple;
    if (s.contains("approved") || s.contains("confirm")) return Colors.orange;
    return Colors.grey;
  }

  // ---------------- Date formatting ----------------
  String _fmtDate(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return "-";
    final dt = DateTime.tryParse(t);
    if (dt == null) return t;
    final d = dt.toLocal();
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return "${d.day.toString().padLeft(2, "0")} ${months[d.month - 1]} ${d.year}";
  }

  String _fmtDateTime(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return "-";
    final dt = DateTime.tryParse(t);
    if (dt == null) return t;
    final d = dt.toLocal();
    final hh = d.hour.toString().padLeft(2, "0");
    final mm = d.minute.toString().padLeft(2, "0");
    return "${_fmtDate(t)}  $hh:$mm";
  }

  // ---------------- Derived fields ----------------
  String _nameOf() {
    if (widget.isService) {
      final svc = _map(o["service"]);
      return _s(
        o["service_name"] ??
            o["serviceName"] ??
            o["service_title"] ??
            o["serviceTitle"] ??
            svc["name"] ??
            svc["title"] ??
            o["title"],
        fb: "Service",
      );
    }

    // product: try first item name
    final items = _list(o["items"] ?? o["order_items"] ?? o["products"] ?? o["cart_items"]);
    if (items.isNotEmpty) {
      final it = _map(items.first);
      final p = _map(it["product"]);
      final nm = _s(it["name"] ?? it["title"] ?? it["product_name"] ?? p["name"] ?? p["title"]);
      if (nm.isNotEmpty) return nm;
    }

    return _s(o["name"] ?? o["title"], fb: "Product");
  }

  String _imageOf() {
    // ✅ always use OrdersAPI helpers so relative URLs work
    if (widget.isService) {
      final svc = _map(o["service"]);
      final raw = _s(
        o["service_image"] ??
            o["serviceImage"] ??
            o["image"] ??
            o["image_url"] ??
            svc["image"] ??
            svc["image_url"],
      );
      return raw.isEmpty ? "" : OrdersAPI.normalizeMediaUrl(raw);
    }

    return OrdersAPI.firstOrderImage(o);
  }

  String _amountText() {
    final v = widget.isService
        ? (o["price"] ?? o["amount"] ?? o["total_amount"] ?? o["total"])
        : (o["total_amount"] ?? o["total"] ?? o["amount"] ?? o["payable_amount"] ?? o["payable"]);
    final n = _d(v, fb: 0);
    if (n > 0) return n.toStringAsFixed(0);
    return _s(v, fb: "0").replaceAll("₹", "").trim();
  }

  String _dateText() {
    final raw = _s(
      o["created_at"] ??
          o["createdAt"] ??
          o["order_date"] ??
          o["date"] ??
          o["booked_at"] ??
          o["booking_date"] ??
          o["bookingDate"],
      fb: "",
    );
    if (raw.isEmpty) return "-";
    // ISO timestamps contain "T"; MySQL timestamps may not.
    if (raw.contains("T")) return _fmtDateTime(raw);
    // if looks like "YYYY-MM-DD HH:MM:SS" -> parse as DateTime too
    final dt = DateTime.tryParse(raw);
    if (dt != null) return _fmtDateTime(raw);
    return _fmtDate(raw);
  }

  String _slotText() {
    final d = _s(o["booking_date"] ?? o["bookingDate"] ?? o["service_date"] ?? o["date"]);
    final label = _s(o["time_label"]);
    final hhmm = _s(o["time_hhmm"]);
    final any = _s(o["service_time"] ?? o["booking_time"] ?? o["time"]);
    final token = _s(o["token_number"] ?? o["token"] ?? o["queue_no"] ?? o["queueNo"]);

    final parts = <String>[];
    if (d.isNotEmpty) parts.add(_fmtDate(d));
    final t = label.isNotEmpty ? label : (hhmm.isNotEmpty ? hhmm : any);
    if (t.isNotEmpty) parts.add(t);

    final slot = parts.isEmpty ? "-" : parts.join(" • ");
    final tok = token.isNotEmpty ? token : "-";
    return "Slot: $slot\nToken: $tok";
  }

  // ---------------- API refresh ----------------
  Future<void> _refresh() async {
    final id = _idForApi();
    if (id.isEmpty) return;

    setState(() {
      loading = true;
      error = "";
    });

    try {
      final details = widget.isService
          ? await OrdersAPI.getServiceBookingDetails(id)
          : await OrdersAPI.getOrderDetails(id);

      if (!mounted) return;

      if (details.isNotEmpty) {
        // ✅ merge + normalize again (ensures image/status keys consistent)
        setState(() => o = OrdersAPI.normalizeOrderForUi({...o, ...details}));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => error = "Failed to load details");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ---------------- Cancel ----------------
  Future<void> _cancel() async {
    final id = _idForApi();
    if (id.isEmpty) return;

    final reasonCtrl = TextEditingController();
    bool submitting = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: !submitting,
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            final r = reasonCtrl.text.trim();
            final valid = r.isNotEmpty;

            return AlertDialog(
              title: Text(widget.isService ? "Cancel Booking" : "Cancel Order"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Remarks required (why cancel?)"),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: "Remarks *",
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setD(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.pop(ctx, false),
                  child: const Text("Close"),
                ),
                ElevatedButton(
                  onPressed: (!valid || submitting)
                      ? null
                      : () async {
                    setD(() => submitting = true);
                    final res = await OrdersAPI.cancelUnified(
                      id: id,
                      type: widget.isService ? "service" : "product",
                      reason: r,
                    );
                    if (ctx.mounted) Navigator.pop(ctx, res["success"] == true);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: submitting
                      ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : const Text("CANCEL", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cancelled ✅"), backgroundColor: Colors.green),
      );
      await _refresh();
    }
  }

  // ---------------- UI blocks ----------------
  @override
  Widget build(BuildContext context) {
    final name = _nameOf();
    final img = _imageOf();
    final amount = _amountText();
    final date = _dateText();

    final status = _statusNorm(_statusRaw());
    final statusColor = _statusColor(status);

    final id = _s(o["id"], fb: "-");
    final bookingNo = _s(o["booking_number"] ?? o["bookingNo"] ?? o["bookingNumber"], fb: "-");

    final customer = _s(o["customer_name"] ?? o["name"] ?? o["customerName"], fb: "-");
    final phone = _s(o["mobile"] ?? o["phone"], fb: "-");
    final address = _s(o["address"], fb: "-");

    final remarks = _s(o["remarks"] ?? o["note"] ?? o["notes"] ?? o["cancel_reason"], fb: "-");

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(widget.isService ? "Booking Details" : "Order Details"),
        backgroundColor: Colors.deepPurple,
        actions: [
          IconButton(onPressed: loading ? null : _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
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

          // Header card (image + name + status)
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 64,
                      width: 64,
                      color: Colors.grey.shade200,
                      child: img.isNotEmpty
                          ? Image.network(
                        img,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey),
                      )
                          : Icon(widget.isService ? Icons.design_services_outlined : Icons.shopping_bag_outlined,
                          color: Colors.grey),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.isService ? "Booking: $bookingNo" : "Order: #$id",
                          style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                status.replaceAll("_", " ").toUpperCase(),
                                style: TextStyle(color: statusColor, fontWeight: FontWeight.w800, fontSize: 12),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              "₹$amount",
                              style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.deepPurple, fontSize: 16),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          _section("Info", [
            _kv("Date", date),
            _kv(widget.isService ? "Booking ID" : "Order ID", id),
            if (widget.isService) _kv("Slot / Token", _slotText()),
            _kv("Remarks", remarks),
          ]),

          const SizedBox(height: 12),

          _section("Customer", [
            _kv("Name", customer),
            _kv("Phone", phone),
            _kv("Address", address),
          ]),

          const SizedBox(height: 14),

          // ✅ Delivery partner (product orders)
          if (!widget.isService)
            Builder(builder: (_) {
              final dpName = _s(o["delivery_partner_name"], fb: "");
              final dpPhone = _s(o["delivery_partner_phone"], fb: "");
              final eta = _s(o["delivery_eta"], fb: "");
              if (dpName.isEmpty && dpPhone.isEmpty && eta.isEmpty) return const SizedBox.shrink();
              return Column(
                children: [
                  _section("Delivery", [
                    _kv("Partner", dpName.isEmpty ? "-" : dpName),
                    _kv("Phone", dpPhone.isEmpty ? "-" : dpPhone),
                    _kv("ETA", eta.isEmpty ? "-" : eta),
                  ]),
                  const SizedBox(height: 14),
                ],
              );
            }),

          if (_canCancel)
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: loading ? null : _cancel,
                icon: const Icon(Icons.cancel_outlined, color: Colors.white),
                label: Text(
                  widget.isService ? "CANCEL BOOKING" : "CANCEL ORDER",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
              child: Text(
                "Cannot cancel (status: ${status.replaceAll("_", " ").toUpperCase()})",
                style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
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
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(k, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }
}
