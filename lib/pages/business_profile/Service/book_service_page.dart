import 'dart:async'; // ✅ ADD THIS (for Timer)
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/business_api.dart';
import '../payment_page.dart';

class BookServicePage extends StatefulWidget {
  final Map<String, dynamic> service;

  const BookServicePage({super.key, required this.service});

  @override
  State<BookServicePage> createState() => _BookServicePageState();
}

class _BookServicePageState extends State<BookServicePage> {
  DateTime? selectedDate;
  TimeOfDay? selectedTime; // optional
  bool _dateLocked = false; // ✅ if schedule_type=date (fixed date)

  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController mobileCtrl = TextEditingController();
  final TextEditingController addressCtrl = TextEditingController();
  final TextEditingController notesCtrl = TextEditingController();

  bool _submitting = false;

  // STATUS
  bool _statusLoading = true;
  String? _statusError;

  int? _todayBookedCount;
  String? _nextFreeSlot;
  String? _bookingNumber;

  final Map<String, Map<String, dynamic>> _statusCache = {};
  Timer? _statusDebounce;

  static const String _baseUrl = "https://adminapi.troonky.in/api";
  static const Duration _timeout = Duration(seconds: 25);

  // ===================== BRAND =====================
  static const _brandGradH = LinearGradient(
    colors: [Color(0xFF5B2EFF), Color(0xFFB12EFF)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // --------------------------
  // SAFE HELPERS
  // --------------------------
  String _s(dynamic v, {String fb = ""}) {
    final x = (v ?? "").toString().trim();
    return x.isEmpty ? fb : x;
  }

  double _d(dynamic v, {double fb = 0}) {
    if (v == null) return fb;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim()) ?? fb;
  }

  int _i(dynamic v, {int fb = 0}) {
    if (v == null) return fb;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim()) ?? fb;
  }

  int? _intTry(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final s = v.toString().trim();
    return int.tryParse(s);
  }

  // ✅ FIXED: NEVER use prefs.getInt(key) directly
  Future<int?> _getUserIdSafe() async {
    final prefs = await SharedPreferences.getInstance();
    const keys = ["userId", "user_id", "id", "uid", "customer_id", "customerId"];
    for (final k in keys) {
      final v = prefs.get(k);
      if (v == null) continue;
      if (v is int && v > 0) return v;
      if (v is double && v > 0) return v.toInt();
      if (v is String) {
        final n = int.tryParse(v.trim());
        if (n != null && n > 0) return n;
      }
    }
    return null;
  }

  String _serviceId(Map<String, dynamic> s) => _s(
    s["service_id"] ??
        s["serviceId"] ??
        s["id"] ??
        s["_id"] ??
        s["serviceID"],
  );

  String _shopId(Map<String, dynamic> s) => _s(
    s["business_id"] ??
        s["businessId"] ??
        s["shop_id"] ??
        s["shopId"] ??
        s["businessID"] ??
        s["shopID"],
  );

  String _scheduleType(Map<String, dynamic> s) =>
      _s(s["schedule_type"] ?? s["scheduleType"]).toLowerCase();

  String _serviceDateIso(Map<String, dynamic> s) =>
      _s(s["service_date"] ?? s["serviceDate"] ?? s["date"]);

  String _fmtDate(DateTime d) =>
      "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  String _prettyDate(DateTime d) =>
      "${d.day.toString().padLeft(2, "0")}/${d.month.toString().padLeft(2, "0")}/${d.year}";

  String _timeToHHmm(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, "0");
    final m = t.minute.toString().padLeft(2, "0");
    return "$h:$m";
  }

  String _durationText(Map<String, dynamic> s) {
    final raw = _s(s["duration"]);
    if (raw.isNotEmpty) {
      final n = int.tryParse(raw);
      if (n != null) return "$n min";
      return raw;
    }
    final mins = _i(s["duration_minutes"] ?? s["durationMinutes"], fb: 0);
    if (mins <= 0) return "0 min";
    if (mins < 60) return "$mins min";
    final h = mins ~/ 60;
    final mm = (mins % 60).toString().padLeft(2, "0");
    return "$h:$mm h";
  }

  bool _isValidMobile(String m) {
    final onlyDigits = m.replaceAll(RegExp(r'[^0-9]'), '');
    return onlyDigits.length == 10;
  }

  // --------------------------
  // AUTH HEADERS (✅ include x-access-token)
  // --------------------------
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final candidates = <String?>[
      prefs.getString("token"),
      prefs.getString("auth_token"),
      prefs.getString("access_token"),
      prefs.getString("jwt"),
      prefs.getString("user_token"),
    ];
    for (final t in candidates) {
      final v = (t ?? "").trim();
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  Future<Map<String, String>> _headers({bool json = false}) async {
    final token = await _getToken();
    return {
      "Accept": "application/json",
      if (json) "Content-Type": "application/json",
      if (token != null && token.isNotEmpty) "Authorization": "Bearer $token",
      if (token != null && token.isNotEmpty) "x-access-token": token, // ✅ IMPORTANT
    };
  }

  Map<String, dynamic> _safeJsonMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return {"data": decoded};
    } catch (_) {
      return {"raw": raw};
    }
  }

  Map<String, dynamic> _cleanPayload(Map<String, dynamic> input) {
    final out = <String, dynamic>{};
    input.forEach((k, v) {
      if (v == null) return;
      if (v is String && v.trim().isEmpty) return;
      out[k] = v;
    });
    return out;
  }

  Future<Map<String, dynamic>> _attachUserId(Map<String, dynamic> m) async {
    try {
      final uid = await _getUserIdSafe();
      if (uid != null && uid > 0) {
        m["user_id"] = uid;
        m["userId"] = uid;
        m["customer_id"] = uid;
        m["customerId"] = uid;
      }
    } catch (e) {
      debugPrint("❌ _attachUserId failed => $e");
    }
    return m;
  }

  // --------------------------
  // SMALL UI HELPERS
  // --------------------------
  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF5B2EFF),
      ),
    );
  }

  Future<void> _alert(String title, String msg) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  // --------------------------
  // INIT
  // --------------------------
  @override
  void initState() {
    super.initState();
    _prefillFromPrefs();
    _initDateFromService();
    _loadStatus();
  }

  void _initDateFromService() {
    final s = widget.service;

    // 1) if ServiceDetails injected booking_date (preferred)
    final injected = _s(s["booking_date"] ?? s["bookingDate"]);
    final st = _scheduleType(s);

    DateTime? fixed;
    if (injected.isNotEmpty) {
      final d = DateTime.tryParse(injected);
      if (d != null) fixed = DateTime(d.year, d.month, d.day);
    }

    // 2) if schedule_type=date use service_date
    if (fixed == null && st == "date") {
      final iso = _serviceDateIso(s);
      final d = DateTime.tryParse(iso);
      if (d != null) fixed = DateTime(d.year, d.month, d.day);
    }

    if (fixed != null) {
      selectedDate = fixed;
      _dateLocked = (st == "date"); // lock only for date type
    } else {
      // default today
      final now = DateTime.now();
      selectedDate = DateTime(now.year, now.month, now.day);
      _dateLocked = false;
    }
  }

  Future<void> _prefillFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    final name = prefs.getString("name") ?? prefs.getString("username") ?? "";
    final phone = prefs.getString("phone") ?? "";
    final address = prefs.getString("address") ?? "";

    if (!mounted) return;

    if (nameCtrl.text.trim().isEmpty && name.trim().isNotEmpty) {
      nameCtrl.text = name.trim();
    }
    if (mobileCtrl.text.trim().isEmpty && phone.trim().isNotEmpty) {
      mobileCtrl.text = phone.trim();
    }
    if (addressCtrl.text.trim().isEmpty && address.trim().isNotEmpty) {
      addressCtrl.text = address.trim();
    }
  }

  Future<void> _persistUserInputs() async {
    final prefs = await SharedPreferences.getInstance();
    final n = nameCtrl.text.trim();
    final p = mobileCtrl.text.trim();
    final a = addressCtrl.text.trim();
    if (n.isNotEmpty) await prefs.setString("name", n);
    if (p.isNotEmpty) await prefs.setString("phone", p);
    if (a.isNotEmpty) await prefs.setString("address", a);
  }

  // --------------------------
  // STATUS (best-effort) + caching per-date (fast)
  // --------------------------
  String _statusKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  void _loadStatusDebounced({bool force = false}) {
    _statusDebounce?.cancel();
    _statusDebounce = Timer(const Duration(milliseconds: 320), () {
      _loadStatus(force: force);
    });
  }

  Future<void> _loadStatus({bool force = false}) async {
    final sid = _serviceId(widget.service);
    if (sid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _statusLoading = false;
        _statusError = "Service id missing";
      });
      return;
    }

    final date = selectedDate ?? DateTime.now();
    final key = _statusKey(date);

    if (!force && _statusCache.containsKey(key)) {
      final data = _statusCache[key]!;
      if (!mounted) return;
      setState(() {
        _applyStatusData(data);
        _statusLoading = false;
        _statusError = null;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _statusLoading = true;
        _statusError = null;
      });
    }

    try {
      final data = await _fetchStatusFromBackend(serviceId: sid, date: date);
      _statusCache[key] = Map<String, dynamic>.from(data);

      if (!mounted) return;
      setState(() {
        _applyStatusData(data);
        _statusLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusLoading = false;
        _statusError = "Status load failed (endpoint missing).";
      });
    }
  }

  void _applyStatusData(Map<String, dynamic> data) {
    _bookingNumber = _s(data["booking_number"] ?? data["bookingNo"]);
    if ((_bookingNumber ?? "").isEmpty) _bookingNumber = null;

    _nextFreeSlot = _s(data["next_free_slot"] ?? data["nextFreeSlot"]);
    if ((_nextFreeSlot ?? "").isEmpty) _nextFreeSlot = null;

    final c = data["today_booked"] ?? data["booked_count"] ?? data["bookedToday"];
    final n = _i(c, fb: -1);
    _todayBookedCount = (n >= 0) ? n : null;
  }

  Future<Map<String, dynamic>> _fetchStatusFromBackend({required String serviceId, required DateTime date}) async {
    final dateStr = _fmtDate(date);

    final candidates = <Uri>[
      Uri.parse("$_baseUrl/services/status/$serviceId?date=$dateStr"),
      Uri.parse("$_baseUrl/services/$serviceId/status?date=$dateStr"),
      Uri.parse("$_baseUrl/bookings/services/status/$serviceId?date=$dateStr"),
      Uri.parse("$_baseUrl/services/details/$serviceId"),
    ];

    for (final url in candidates) {
      try {
        final res =
        await http.get(url, headers: await _headers()).timeout(_timeout);
        if (res.statusCode == 200) {
          final m = _safeJsonMap(res.body);

          if (url.path.contains("/services/details/")) {
            return {
              "today_booked": 0,
              "booking_number": "",
              "next_free_slot": "",
              "details": m["data"] ?? m["service"] ?? m,
            };
          }

          return m;
        }
      } catch (_) {}
    }

    return {"today_booked": 0, "booking_number": "", "next_free_slot": ""};
  }

  // --------------------------
  // PICK DATE/TIME
  // --------------------------
  Future<void> pickDate() async {
    if (_dateLocked) {
      _snack("This service has a fixed date.", isError: true);
      return;
    }

    final today = DateTime.now();
    final init = selectedDate ?? today;

    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: DateTime(today.year + 1),
      helpText: "Select appointment date",
    );

    if (picked != null) {
      setState(() => selectedDate = picked);
      _loadStatusDebounced();
    }
  }

  Future<void> pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: selectedTime ?? TimeOfDay.now(),
      helpText: "Select appointment time (optional)",
    );

    if (picked != null) setState(() => selectedTime = picked);
  }

  void _clearTime() => setState(() => selectedTime = null);

  // --------------------------
  // OPEN PaymentPage
  // --------------------------
  Future<Map<String, dynamic>?> _openPaymentPage({
    required double total,
    required Map<String, dynamic> orderData,
  }) async {
    final token = await _getToken();
    if (!mounted) return null;

    final res = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => PaymentPage(
          totalAmount: total,
          orderData: orderData,
          authToken: token,
        ),
      ),
    );

    if (res == null) return null;
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return Map<String, dynamic>.from(res);
    return {"status": "unknown", "raw": res};
  }

  // --------------------------
  // ✅ NEW: CREATE BOOKING (PRIMARY) -> POST /api/bookings
  // --------------------------
  Future<Map<String, dynamic>> _createBookingViaBookingsApi(
      Map<String, dynamic> bookingInfo) async {
    final url = Uri.parse("$_baseUrl/bookings");

    final res = await http
        .post(
      url,
      headers: await _headers(json: true),
      body: jsonEncode(_cleanPayload(bookingInfo)),
    )
        .timeout(_timeout);

    final data = _safeJsonMap(res.body);

    // normalize message
    final msg = _s(data["message"] ?? data["error"] ?? data["msg"]);

    if (res.statusCode == 401 || res.statusCode == 403) {
      return {
        "success": false,
        "statusCode": res.statusCode,
        "message": msg.isNotEmpty ? msg : "Unauthorized (token missing/invalid)",
        "data": data,
        "usedUrl": url.toString(),
      };
    }

    final okHttp = res.statusCode == 200 || res.statusCode == 201;
    final okBody = data["success"] == true;

    if (okHttp && okBody) {
      return {
        "success": true,
        "statusCode": res.statusCode,
        "message": msg.isNotEmpty ? msg : "Booked",
        "data": data,
        "usedUrl": url.toString(),
      };
    }

    return {
      "success": false,
      "statusCode": res.statusCode,
      "message": msg.isNotEmpty ? msg : "Booking failed",
      "data": data,
      "usedUrl": url.toString(),
    };
  }

  // --------------------------
  // FALLBACK (keep old probes)
  // --------------------------
  Future<Map<String, dynamic>> _createBookingOnBackend(
      Map<String, dynamic> bookingInfo) async {
    // ✅ first try new stable endpoint
    try {
      final first = await _createBookingViaBookingsApi(bookingInfo);
      if (first["success"] == true) return first;
      // if token missing => no need further probes
      final sc = first["statusCode"];
      if (sc == 401 || sc == 403) return first;
    } catch (_) {}

    // old probing (kept)
    final shopId = _shopId(widget.service);
    final sid = _serviceId(widget.service);
    final attempts = <Map<String, dynamic>>[];
    final payload = _cleanPayload(bookingInfo);

    final candidates = <Uri>[
      Uri.parse("$_baseUrl/bookings/service/add"),
      Uri.parse("$_baseUrl/service-bookings/add"),
      Uri.parse("$_baseUrl/bookings/add"),
      Uri.parse("$_baseUrl/bookings/create"),
      Uri.parse("$_baseUrl/services/book"),
      Uri.parse("$_baseUrl/bookings/service"),
      if (shopId.isNotEmpty && sid.isNotEmpty)
        Uri.parse("$_baseUrl/shops/$shopId/services/$sid/book"),
      if (shopId.isNotEmpty) Uri.parse("$_baseUrl/shops/$shopId/book-service"),
    ];

    for (final url in candidates) {
      try {
        debugPrint("📌 BOOKING TRY => $url");

        final res = await http
            .post(
          url,
          headers: await _headers(json: true),
          body: jsonEncode(payload),
        )
            .timeout(_timeout);

        final data = _safeJsonMap(res.body);

        if (res.statusCode == 401 || res.statusCode == 403) {
          return {
            "success": false,
            "usedUrl": url.toString(),
            "statusCode": res.statusCode,
            "message": "Unauthorized (token missing/invalid)",
            "data": data,
          };
        }

        final okHttp = res.statusCode == 200 || res.statusCode == 201;
        final okBody = (data["success"] == true) || (data["error"] == false);

        if (okHttp && okBody) {
          return {
            "success": true,
            "usedUrl": url.toString(),
            "statusCode": res.statusCode,
            "data": data,
          };
        }

        attempts.add({"url": url.toString(), "statusCode": res.statusCode, "data": data});
      } catch (e) {
        attempts.add({"url": url.toString(), "error": e.toString()});
      }
    }

    return {"success": false, "attempts": attempts, "message": "All booking endpoints failed"};
  }

  // --------------------------
  // CONFIRM BOOKING -> PAYMENT -> POST /api/bookings
  // --------------------------
  Future<void> confirmBooking() async {
    FocusScope.of(context).unfocus();

    if (_submitting) return;

    // date required (we prefill, but still check)
    if (selectedDate == null) {
      await _alert("Missing info", "Please select date");
      return;
    }

    final customerName = nameCtrl.text.trim();
    if (customerName.isEmpty) {
      await _alert("Missing info", "Please enter your name");
      return;
    }

    final mob = mobileCtrl.text.trim();
    if (mob.isEmpty || !_isValidMobile(mob)) {
      await _alert("Invalid mobile", "Enter valid 10 digit mobile number");
      return;
    }

    final token = await _getToken();
    if (token == null || token.trim().isEmpty) {
      await _alert("Login required",
          "Token পাওয়া যাচ্ছে না। আগে login করো, তারপর আবার try করো।");
      return;
    }

    final s = widget.service;

    final price = _d(
      s["offer_price"] ?? s["offerPrice"] ?? s["price"] ?? s["amount"],
      fb: 0,
    );
    if (price <= 0) {
      await _alert("Invalid service", "Service price invalid");
      return;
    }

    final sidRaw = _serviceId(s);
    if (sidRaw.isEmpty) {
      await _alert("Invalid service", "Service id missing");
      return;
    }

    final sidInt = _intTry(s["service_id"] ?? s["serviceId"] ?? s["id"]) ??
        int.tryParse(sidRaw);

    setState(() => _submitting = true);
    _snack("Opening payment…", isError: false);

    try {
      await _persistUserInputs();

      // Build orderData for PaymentPage
      final orderData = <String, dynamic>{
        "type": "service_booking",
        "mode": "service",
        "order_type": "service",

        if (sidInt != null && sidInt > 0) "service_id": sidInt else "service_id": sidRaw,
        if (sidInt != null && sidInt > 0) "serviceId": sidInt else "serviceId": sidRaw,

        "customer_name": customerName,
        "name": customerName,
        "mobile": mob,
        "phone": mob,

        "booking_date": _fmtDate(selectedDate!),
        "date": _fmtDate(selectedDate!),

        // time optional
        "time_hhmm": selectedTime == null ? "" : _timeToHHmm(selectedTime!),
        "time_label": selectedTime == null ? "" : selectedTime!.format(context),

        "address": addressCtrl.text.trim(),
        "notes": notesCtrl.text.trim(),

        "price": price,
        "total_amount": price,

        "duration": _durationText(s),
        "service_name": _s(s["name"], fb: "Service"),
      };

      await _attachUserId(orderData);

      final cleanedOrder = _cleanPayload(orderData);

      // 1) Payment step
      final result = await _openPaymentPage(total: price, orderData: cleanedOrder);

      if (!mounted) return;

      if (result == null) {
        _snack("Payment cancelled", isError: true);
        return;
      }

      final status = _s(result["status"]).toLowerCase();
      final ok = status == "success" || status == "cod";
      if (!ok) {
        _snack("Payment not completed", isError: true);
        return;
      }

      // 2) After payment, create booking on backend (NEW endpoint)
      final bookingPayload = <String, dynamic>{
        "service_id": (sidInt != null && sidInt > 0) ? sidInt : int.tryParse(sidRaw) ?? sidRaw,
        "booking_date": _fmtDate(selectedDate!),

        "customer_name": customerName,
        "mobile": mob,

        // optional
        "address": addressCtrl.text.trim(),
        "notes": notesCtrl.text.trim(),

        "time_label": selectedTime == null ? null : selectedTime!.format(context),
        "time_hhmm": selectedTime == null ? null : _timeToHHmm(selectedTime!),
        "time_optional": selectedTime == null ? 1 : 0,

        // align with DB columns
        "duration_minutes": _i(s["duration_minutes"] ?? s["durationMinutes"], fb: 0),
        "price": price,

        // keep payment info as extra (backend ignores unknown fields safely)
        "payment_mode": status == "cod" ? "cod" : "online",
        "payment_status": status == "cod" ? "unpaid" : "paid",
        "payment_id": result["paymentId"] ?? result["razorpay_payment_id"],
        "razorpay_order_id": result["razorpayOrderId"] ?? result["razorpay_order_id"],
        "verified": result["verified"] == true,
      };

      await _attachUserId(bookingPayload);

      final backendRes = await _createBookingViaBookingsApi(bookingPayload);

      if (backendRes["success"] == true) {
        final data = backendRes["data"];
        final booking = (data is Map) ? (data["booking"] ?? data["data"] ?? data) : data;

        final bno = (booking is Map)
            ? _s(booking["booking_number"] ?? booking["bookingNo"] ?? booking["booking_number".toString()])
            : "";

        _snack(
          bno.isNotEmpty ? "Booking confirmed ✅  No: $bno" : "Booking confirmed ✅",
          isError: false,
        );

        await _loadStatus();

        // optional: go back with success
        if (mounted) {
          Navigator.pop(context, true);
        }
        return;
      }

      // if failed, show server message
      final msg = _s(backendRes["message"], fb: "Booking failed");
      _snack(msg, isError: true);

      debugPrint("❌ Booking failed => $backendRes");
    } catch (e, st) {
      debugPrint("❌ Booking flow error => $e\n$st");
      if (mounted) _snack("Booking failed: $e", isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _statusDebounce?.cancel();
    nameCtrl.dispose();
    mobileCtrl.dispose();
    addressCtrl.dispose();
    notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;

    final name = _s(s["name"], fb: "Service");
    final desc = _s(s["description"]);
    final price = _d(
      s["offer_price"] ?? s["offerPrice"] ?? s["price"] ?? s["amount"],
      fb: 0,
    );
    final duration = _durationText(s);
    final category = _s(s["category"], fb: "Appointment");

    final rawImage = _s(s["image_url"] ?? s["image"] ?? s["photo"]);
    final image = BusinessAPI.toPublicUrl(rawImage);

    final slotText = (selectedDate != null)
        ? (selectedTime != null
        ? "${_prettyDate(selectedDate!)} • ${selectedTime!.format(context)}"
        : "${_prettyDate(selectedDate!)} • Time not set")
        : "Not selected";

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text("Book Service",
            style: TextStyle(fontWeight: FontWeight.w900)),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: _brandGradH),
        ),
        actions: [
          IconButton(
            onPressed: _loadStatus,
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: "Refresh Status",
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _statusCard(),
                  const SizedBox(height: 14),
                  _serviceCard(
                    image: image,
                    name: name,
                    desc: desc,
                    price: price,
                    duration: duration,
                    category: category,
                  ),
                  const SizedBox(height: 14),
                  _card(
                    title: "Select Date & Time",
                    subtitle: _dateLocked
                        ? "Date is fixed for this service. Time is optional."
                        : "Date is required. Time is optional.",
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _pickerTile(
                                label: _dateLocked ? "Date (Fixed)" : "Choose Date *",
                                value: selectedDate == null
                                    ? "Tap to select"
                                    : _prettyDate(selectedDate!),
                                icon: Icons.calendar_month_outlined,
                                onTap: pickDate,
                                accent: const Color(0xFF5B2EFF),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _pickerTile(
                                label: "Choose Time (Optional)",
                                value: selectedTime == null
                                    ? "Skip / Tap"
                                    : selectedTime!.format(context),
                                icon: Icons.schedule_outlined,
                                onTap: pickTime,
                                accent: const Color(0xFFB12EFF),
                                trailing: selectedTime == null
                                    ? null
                                    : IconButton(
                                  onPressed: _clearTime,
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF5B2EFF).withOpacity(0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFF5B2EFF).withOpacity(0.12),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.event_available,
                                  color: Color(0xFF5B2EFF)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "Selected Slot: $slotText",
                                  style: const TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _card(
                    title: "Your Details",
                    subtitle: "Use correct mobile so provider can contact you.",
                    child: Column(
                      children: [
                        _textField(
                          controller: nameCtrl,
                          label: "Your Name",
                          hint: "e.g. Arindam",
                          icon: Icons.person_outline,
                        ),
                        const SizedBox(height: 12),
                        _textField(
                          controller: mobileCtrl,
                          label: "Mobile Number",
                          hint: "10 digit mobile",
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),
                        _textField(
                          controller: addressCtrl,
                          label: "Address (Optional)",
                          hint: "House, Road, Area",
                          icon: Icons.location_on_outlined,
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _card(
                    title: "Notes (Optional)",
                    subtitle: "Anything provider should know (symptoms / style / etc.)",
                    child: _textField(
                      controller: notesCtrl,
                      label: "Notes",
                      hint: "e.g. Prefer evening slot...",
                      icon: Icons.note_alt_outlined,
                      maxLines: 3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _bottomBar(price: price, duration: duration),
        ],
      ),
    );
  }

  // ================= STATUS UI =================
  Widget _statusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.18)),
            ),
            child: const Icon(Icons.insights_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Status",
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.white),
                ),
                const SizedBox(height: 8),
                if (_statusLoading)
                  Row(
                    children: const [
                      SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      ),
                      SizedBox(width: 10),
                      Text(
                        "Loading status...",
                        style: TextStyle(
                            fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ],
                  )
                else if (_statusError != null)
                  Text(
                    _statusError!,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800),
                  )
                else ...[
                    Text(
                      "Today booked: ${_todayBookedCount ?? 0}",
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _bookingNumber != null
                          ? "Booking No: $_bookingNumber"
                          : "Booking No: will be assigned by provider",
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.88),
                          fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    if (_nextFreeSlot != null)
                      Text(
                        "Next Free Slot: $_nextFreeSlot",
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.90),
                            fontWeight: FontWeight.w800),
                      ),
                  ],
                const SizedBox(height: 10),
                Text(
                  "Booked count/slots will show automatically when backend endpoints exist.",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.70),
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _loadStatus,
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: "Refresh",
          ),
        ],
      ),
    );
  }

  // ================= UI HELPERS =================
  Widget _serviceCard({
    required String image,
    required String name,
    required String desc,
    required double price,
    required String duration,
    required String category,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            blurRadius: 14,
            offset: const Offset(0, 8),
            color: Colors.black.withOpacity(0.06),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 92,
              width: 92,
              color: Colors.grey.shade200,
              child: (image.isNotEmpty)
                  ? Image.network(
                image,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                    Icons.miscellaneous_services,
                    size: 40,
                    color: Colors.grey),
              )
                  : const Icon(Icons.miscellaneous_services,
                  size: 40, color: Colors.grey),
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
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  desc.trim().isEmpty ? "No description" : desc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _miniPill("₹${price.toStringAsFixed(0)}",
                        Icons.currency_rupee_rounded, const Color(0xFF5B2EFF)),
                    _miniPill(duration, Icons.timer_outlined,
                        const Color(0xFF334155)),
                    _miniPill(category, Icons.category_outlined,
                        const Color(0xFF16A34A)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniPill(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }

  Widget _card({required String title, String? subtitle, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                  height: 1.3),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _pickerTile({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
    required Color accent,
    Widget? trailing,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              height: 38,
              width: 38,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withOpacity(0.16)),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: const Color(0xFFF7F7FB),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
      ),
    );
  }

  Widget _bottomBar({required double price, required String duration}) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 18,
                offset: const Offset(0, -8)),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7FB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "₹${price.toStringAsFixed(0)}",
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: Color(0xFF5B2EFF),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Duration: $duration",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade700,
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: _brandGradH,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF5B2EFF).withOpacity(0.28),
                        blurRadius: 16,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _submitting ? null : confirmBooking,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _submitting
                        ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                        : const Text(
                      "CONFIRM & PAY",
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Colors.white),
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
}
