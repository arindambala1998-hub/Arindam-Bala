import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:troonky_link/services/order_api.dart';

class ServiceOrderDetailsPage extends StatefulWidget {
  final Map<String, dynamic> order;
  const ServiceOrderDetailsPage({super.key, required this.order});

  @override
  State<ServiceOrderDetailsPage> createState() => _ServiceOrderDetailsPageState();
}

class _ServiceOrderDetailsPageState extends State<ServiceOrderDetailsPage> {
  bool loading = false;
  String error = "";
  late Map<String, dynamic> order;

  @override
  void initState() {
    super.initState();
    order = OrdersAPI.normalizeOrderForUi(widget.order);
    _refreshDetails();
  }

  // ===================== SAFE HELPERS =====================
  String _s(dynamic v, {String fb = "-"}) {
    final x = (v ?? "").toString().trim();
    return x.isEmpty ? fb : x;
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
      SnackBar(content: Text(msg), backgroundColor: bad ? Colors.red : Colors.green),
    );
  }

  // ===================== IDs + Status =====================
  String _bookingIdUi() {
    final bno = _s(order["booking_number"], fb: "");
    if (bno.isNotEmpty) return bno;
    return _s(order["id"], fb: "-");
  }

  /// IMPORTANT:
  /// Backend details/cancel endpoints require numeric booking id
  /// OrdersAPI.getServiceBookingDetails() & cancelServiceBooking() already enforce that.
  /// Here we still prefer numeric `id` first.
  String _bookingIdApi() => _s(order["id"], fb: "");

  String _statusRaw() => _s(
    order["status"] ??
        order["booking_status"] ??
        order["service_status"] ??
        order["order_status"],
    fb: "pending",
  );

  /// ✅ Canonicalize service statuses for UI consistency.
  /// (We keep service statuses separate from product state machine.)
  String _status() {
    final s = _statusRaw().trim().toLowerCase();
    if (s.isEmpty) return "pending";

    // common aliases
    if (s == "approved" || s == "accepted" || s == "confirm" || s == "confirmed") return "approved";
    if (s == "done") return "completed";
    if (s == "canceled" || s == "cancel") return "cancelled";

    return s;
  }

  bool get _isTerminal {
    final s = _status();
    return s == "cancelled" || s == "completed" || s == "rejected" || s == "failed";
  }

  bool get _canCancel {
    // business can cancel until terminal.
    return !_isTerminal;
  }

  String _serviceNameSmart(Map<String, dynamic> o) {
    final svc = _safeMap(o["service"]);
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

  String _serviceImageSmart(Map<String, dynamic> o) {
    final raw = _s(
      o["service_image"] ??
          o["serviceImage"] ??
          _safeMap(o["service"])["image"] ??
          _safeMap(o["service"])["image_url"] ??
          o["image"] ??
          o["image_url"],
      fb: "",
    );
    if (raw.isEmpty) return "";
    return OrdersAPI.normalizeMediaUrl(raw);
  }

  // ===================== FORMATTERS =====================
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

  // ===================== Refresh details =====================
  Future<void> _refreshDetails() async {
    final id = _bookingIdApi();
    if (id.isEmpty) return;

    setState(() {
      loading = true;
      error = "";
    });

    try {
      // ✅ backend-accurate for service booking
      final details = await OrdersAPI.getServiceBookingDetails(id);
      if (!mounted) return;
      if (details.isNotEmpty) {
        setState(() => order = OrdersAPI.normalizeOrderForUi(details));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => error = "Failed to load full service booking details");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ===================== Cancel Flow =====================
  Future<void> _cancelFlow() async {
    final id = _bookingIdApi();
    if (id.isEmpty) {
      _snack("Booking id missing", bad: true);
      return;
    }

    final reasonCtrl = TextEditingController();
    bool submitting = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: !submitting,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setD) {
            final reason = reasonCtrl.text.trim();
            final valid = reason.isNotEmpty;

            return AlertDialog(
              title: const Text("Cancel Booking"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Cancellation reason required.", style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: "Reason *",
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

                    // ✅ Use unified cancel for service (routes/bookings.js PATCH /bookings/:id/cancel)
                    // It already calls cancelServiceBooking internally for service, keeping future-proofing.
                    final res = await OrdersAPI.cancelUnified(
                      id: id,
                      type: "service",
                      reason: reasonCtrl.text.trim(),
                    );
                    final done = res["success"] == true;

                    if (context.mounted) Navigator.pop(context, done);
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
      _snack("Booking cancelled ✅");
      await _refreshDetails();
    } else if (ok == false) {
      _snack("Cancel failed ❌", bad: true);
    }
  }

  // ===================== UI helpers =====================
  Color _badgeColor(String v) {
    final s = v.toLowerCase();
    if (s.contains("approved") || s.contains("paid") || s.contains("completed")) return Colors.green;
    if (s.contains("cancel") || s.contains("reject") || s.contains("fail")) return Colors.red;
    if (s.contains("pending")) return Colors.orange;
    return Colors.grey;
  }

  Widget _badge(String text) {
    final c = _badgeColor(text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withOpacity(0.25)),
      ),
      child: Text(text.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: c)),
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

  // ===================== BUILD =====================
  @override
  Widget build(BuildContext context) {
    final status = _status();
    final bookingUi = _bookingIdUi();

    final bookingId = _s(order["id"], fb: "-");
    final createdAt = _fmtDateTime(_s(order["created_at"], fb: ""));
    final bookingDate = _fmtDate(_s(order["booking_date"], fb: ""));

    final amountNum = _d(order["total_amount"] ?? order["price"] ?? order["amount"], fb: 0);
    final amount = amountNum > 0
        ? amountNum.toStringAsFixed(0)
        : _s(order["total_amount"] ?? order["price"] ?? order["amount"], fb: "0");

    final token = _s(order["token_number"], fb: "");
    final timeLabel = _s(order["service_time"], fb: "");

    final customerName = _s(order["customer_name"] ?? order["name"], fb: "Unknown Customer");
    final customerPhone = _s(order["phone"] ?? order["mobile"], fb: "-");
    final customerAddress = _s(order["address"], fb: "-");

    final serviceName = _serviceNameSmart(order);
    final remarks = _s(order["remarks"] ?? order["note"] ?? order["cancel_reason"], fb: "");

    final meta = _tryJson(order["meta"] ?? order["extra"] ?? order["details"]);
    final metaMap = _safeMap(meta);

    final img = _serviceImageSmart(order);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text("Service Booking Details"),
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

            // Header summary (with image)
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: img.isEmpty
                          ? Container(
                        width: 58,
                        height: 58,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.design_services_outlined),
                      )
                          : Image.network(
                        img,
                        width: 58,
                        height: 58,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 58,
                          height: 58,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Booking: $bookingUi", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _badge(status),
                              if (token.isNotEmpty) _badge("token:$token"),
                              if (timeLabel.isNotEmpty) _badge(timeLabel),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: "Copy Booking ID",
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: bookingUi));
                        _snack("Booking copied ✅");
                      },
                      icon: const Icon(Icons.copy),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            _section("Booking Info", [
              _kv("Status", status.toUpperCase()),
              _kv("Booking No", _s(order["booking_number"], fb: "-"),
                  copyable: _s(order["booking_number"], fb: "").isNotEmpty),
              _kv("Booking ID", bookingId, copyable: bookingId != "-"),
              _kv("Created At", createdAt),
              _kv("Booking Date", bookingDate),
              _kv("Total Amount", "₹$amount"),
              if (token.isNotEmpty) _kv("Token", token, copyable: true),
              if (timeLabel.isNotEmpty) _kv("Time", timeLabel),
            ]),
            const SizedBox(height: 12),

            _section("Customer Info", [
              _kv("Name", customerName),
              _kv("Phone", customerPhone, copyable: customerPhone != "-"),
              _kv("Address", customerAddress),
            ]),
            const SizedBox(height: 12),

            _section("Service Info", [
              _kv("Service", serviceName),
              _kv("Remarks", remarks.isEmpty ? "-" : remarks),
            ]),

            if (metaMap.isNotEmpty) ...[
              const SizedBox(height: 12),
              _section("Extra", [_kv("Meta", metaMap.toString())]),
            ],

            const SizedBox(height: 14),

            if (_canCancel)
              SizedBox(
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: loading ? null : _cancelFlow,
                  icon: const Icon(Icons.close, color: Colors.white),
                  label: const Text("CANCEL BOOKING", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
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
                  "This booking is closed (status: ${status.toUpperCase()}).",
                  style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
