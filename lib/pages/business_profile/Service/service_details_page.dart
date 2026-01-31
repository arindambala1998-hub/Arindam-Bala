import 'dart:ui'; // ✅ for ImageFilter.blur
import 'package:flutter/material.dart';

import 'book_service_page.dart';
import 'edit_service_page.dart';
import '../../../services/services_api.dart';

class ServiceDetailsPage extends StatelessWidget {
  final Map<String, dynamic> service;
  final bool isOwner;

  const ServiceDetailsPage({
    super.key,
    required this.service,
    required this.isOwner,
  });

  // ===================== SAFE HELPERS =====================
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

  int _serviceId(Map<String, dynamic> s) {
    final raw = s["id"] ?? s["_id"] ?? s["serviceId"] ?? s["service_id"];
    return _i(raw, fb: 0);
  }

  // duration: can be "30 min" OR 30 OR duration_minutes
  String _durationText(Map<String, dynamic> s) {
    final raw = _s(s["duration"]);
    if (raw.isNotEmpty) {
      final n = int.tryParse(raw);
      if (n != null) return "$n min";
      return raw;
    }
    final mins = _i(s["duration_minutes"] ?? s["durationMinutes"]);
    if (mins <= 0) return "";
    if (mins < 60) return "$mins min";
    final h = mins ~/ 60;
    final mm = (mins % 60).toString().padLeft(2, "0");
    return "$h:$mm h";
  }

  // schedule: schedule_type/date (✅ only DATE shown; no time)
  String _scheduleType(Map<String, dynamic> s) =>
      _s(s["schedule_type"] ?? s["scheduleType"]).toLowerCase();

  String _serviceDateIso(Map<String, dynamic> s) =>
      _s(s["service_date"] ?? s["serviceDate"] ?? s["schedule_date"] ?? s["date"]);

  String _scheduleText(Map<String, dynamic> s) {
    final type = _scheduleType(s);

    // ✅ Everyday => show today's date (only date)
    if (type == "everyday") {
      final now = DateTime.now();
      final todayIso =
          "${now.year}-${now.month.toString().padLeft(2, "0")}-${now.day.toString().padLeft(2, "0")}";
      return _prettyDate(todayIso);
    }

    final ds = _serviceDateIso(s);
    if (ds.isNotEmpty) return _prettyDate(ds);

    return "";
  }

  // supports "2026-01-04" OR ISO
  String _prettyDate(String input) {
    final t = input.trim();
    if (t.isEmpty) return "";
    final dt = DateTime.tryParse(t);
    if (dt == null) return t;

    const months = [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ];
    final dd = dt.day.toString().padLeft(2, "0");
    final mon = months[(dt.month - 1).clamp(0, 11)];
    return "$dd $mon ${dt.year}";
  }

  bool _autoApprove(Map<String, dynamic> s) {
    final v = s["auto_approve"] ?? s["autoApprove"];
    if (v == true) return true;
    final n = _i(v, fb: 0);
    return n == 1;
  }

  bool _isActive(Map<String, dynamic> s) {
    final v = s["is_active"] ?? s["isActive"];
    final n = _i(v, fb: 1);
    return n == 1;
  }

  bool _isDeleted(Map<String, dynamic> s) {
    final v = s["is_deleted"] ?? s["isDeleted"];
    final n = _i(v, fb: 0);
    return n == 1;
  }

  // ✅ service image fixer (FULL URL + relative both)
  String _serviceImageUrl(Map<String, dynamic> s) {
    final raw = _s(
      s["image_url"] ??
          s["imageUrl"] ??
          s["image"] ??
          s["photo"] ??
          s["photo_url"] ??
          s["photoUrl"],
    );
    return ServicesAPI.toPublicUrl(raw);
  }

  // ===================== TOKEN HELPERS =====================
  int _tokenEnabled(Map<String, dynamic> s) =>
      _i(s["token_enabled"] ?? s["tokenEnabled"], fb: 0);

  int _tokenLimit(Map<String, dynamic> s) =>
      _i(s["token_limit"] ?? s["tokenLimit"], fb: 0);

  int _tokenUsed(Map<String, dynamic> s) {
    // backend may send one of these
    return _i(
      s["token_used"] ??
          s["tokenUsed"] ??
          s["token_count"] ??
          s["tokenCount"] ??
          s["tokens_taken"] ??
          s["tokensTaken"],
      fb: 0,
    );
  }

  String _runningToken(Map<String, dynamic> s) {
    return _s(
      s["running_token"] ??
          s["runningToken"] ??
          s["current_token"] ??
          s["currentToken"],
    );
  }

  // ===================== BOOKING HELPERS =====================
  DateTime _todayLocal() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  String _toIsoDate(DateTime d) =>
      "${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}";

  /// ✅ Decide booking availability for UI only.
  /// Server-side validation remains the source of truth.
  ({bool canBook, String reason, String? fixedBookingDate}) _bookingStatus(Map<String, dynamic> s) {
    if (_isDeleted(s)) return (canBook: false, reason: "Service deleted", fixedBookingDate: null);
    if (!_isActive(s)) return (canBook: false, reason: "Service inactive", fixedBookingDate: null);

    final sid = _serviceId(s);
    if (sid <= 0) return (canBook: false, reason: "Service id missing", fixedBookingDate: null);

    final type = _scheduleType(s);
    final today = _todayLocal();

    // schedule_type == date => only that date is valid (server enforces exact date)
    if (type == "date") {
      final isoRaw = _serviceDateIso(s);
      final parsed = DateTime.tryParse(isoRaw);
      if (parsed == null) {
        return (canBook: false, reason: "Service date missing", fixedBookingDate: null);
      }
      final serviceDay = DateTime(parsed.year, parsed.month, parsed.day);

      if (serviceDay.isBefore(today)) {
        return (canBook: false, reason: "Expired", fixedBookingDate: _toIsoDate(serviceDay));
      }

      // ✅ allow booking for that date (today or future)
      return (canBook: true, reason: "", fixedBookingDate: _toIsoDate(serviceDay));
    }

    // everyday or others => allow (server will check cutoff/time/token limit)
    return (canBook: true, reason: "", fixedBookingDate: _toIsoDate(today));
  }

  // ===================== BRAND COLORS =====================
  static const _brandGrad = LinearGradient(
    colors: [Color(0xFF5B2EFF), Color(0xFFB12EFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const _brandGradH = LinearGradient(
    colors: [Color(0xFF5B2EFF), Color(0xFFB12EFF)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  @override
  Widget build(BuildContext context) {
    final image = _serviceImageUrl(service);

    final name = _s(service["name"], fb: "Service");
    final description = _s(service["description"], fb: "");
    final price = _d(service["price"], fb: 0);

    final duration = _durationText(service);
    final category = _s(service["category"], fb: "Service");
    final location = _s(service["location"] ?? service["address"]);
    final workingHours = _s(service["working_hours"] ?? service["workingHours"]);
    final schedule = _scheduleText(service);
    final autoApprove = _autoApprove(service);

    final runningToken = _runningToken(service);
    final tokenLimit = _tokenLimit(service);
    final tokenUsed = _tokenUsed(service);
    final tokenEnabled = _tokenEnabled(service);

    final booking = _bookingStatus(service);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        actions: [
          if (isOwner) _ownerMenuButton(context),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _hero(
                    imageUrl: image,
                    title: name,
                    price: price,
                    duration: duration,
                    schedule: schedule,
                    autoApprove: autoApprove,

                    // token display
                    runningToken: runningToken,
                    tokenUsed: tokenUsed,
                    tokenLimit: tokenLimit,
                    tokenEnabled: tokenEnabled,
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Service Overview",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _infoPill(
                                icon: Icons.currency_rupee_rounded,
                                label: "Price",
                                value: "₹${price.toStringAsFixed(0)}",
                                grad: _brandGradH,
                              ),

                              if (schedule.isNotEmpty)
                                _infoPill(
                                  icon: Icons.calendar_month_rounded,
                                  label: "Date",
                                  value: schedule,
                                  grad: LinearGradient(
                                    colors: [
                                      const Color(0xFF111827).withOpacity(0.85),
                                      const Color(0xFF111827).withOpacity(0.60),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),

                              if (duration.isNotEmpty)
                                _infoPill(
                                  icon: Icons.timer_rounded,
                                  label: "Duration",
                                  value: duration,
                                  grad: LinearGradient(
                                    colors: [
                                      const Color(0xFF0EA5E9).withOpacity(0.85),
                                      const Color(0xFF22C55E).withOpacity(0.85),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),

                              _infoPill(
                                icon: Icons.category_rounded,
                                label: "Category",
                                value: category,
                                grad: LinearGradient(
                                  colors: [
                                    const Color(0xFF8B5CF6).withOpacity(0.85),
                                    const Color(0xFFEC4899).withOpacity(0.75),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),

                              _infoPill(
                                icon: Icons.verified_rounded,
                                label: "Approval",
                                value: autoApprove ? "Auto" : "Manual",
                                grad: LinearGradient(
                                  colors: [
                                    (autoApprove ? const Color(0xFF16A34A) : const Color(0xFFF59E0B))
                                        .withOpacity(0.90),
                                    (autoApprove ? const Color(0xFF22C55E) : const Color(0xFFFB7185))
                                        .withOpacity(0.75),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),

                              // token pill (display only)
                              if (tokenEnabled == 1 && tokenLimit > 0)
                                _infoPill(
                                  icon: Icons.confirmation_number_outlined,
                                  label: "Token",
                                  value: "${tokenUsed > 0 ? tokenUsed : 0}/$tokenLimit",
                                  grad: LinearGradient(
                                    colors: [
                                      const Color(0xFF0F172A).withOpacity(0.80),
                                      const Color(0xFF334155).withOpacity(0.70),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                            ],
                          ),
                          if (location.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _rowInfo(Icons.location_on_outlined, location),
                          ],
                          if (workingHours.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _rowInfo(Icons.schedule_rounded, "Working Hours: $workingHours"),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "About This Service",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            description.isEmpty ? "No description available." : description,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.6,
                              color: Colors.grey.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ),
          if (!isOwner)
            _bottomBookingBar(
              context,
              price: price,
              duration: duration,
              schedule: schedule,
              canBook: booking.canBook,
              reason: booking.reason,
              fixedBookingDate: booking.fixedBookingDate,
            ),
        ],
      ),
    );
  }

  // ===================== HERO =====================
  Widget _hero({
    required String imageUrl,
    required String title,
    required double price,
    required String duration,
    required String schedule,
    required bool autoApprove,
    required String runningToken,
    required int tokenUsed,
    required int tokenLimit,
    required int tokenEnabled,
  }) {
    final tokenTopText = runningToken.isNotEmpty
        ? "Running Token: $runningToken"
        : (tokenEnabled == 1 && tokenLimit > 0
        ? "Token: ${tokenUsed > 0 ? tokenUsed : 0}/$tokenLimit"
        : "");

    return SizedBox(
      height: 320,
      child: Stack(
        children: [
          Positioned.fill(
            child: imageUrl.isNotEmpty
                ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                decoration: const BoxDecoration(gradient: _brandGrad),
                child: const Center(
                  child: Icon(Icons.design_services_rounded, size: 90, color: Colors.white),
                ),
              ),
            )
                : Container(
              decoration: const BoxDecoration(gradient: _brandGrad),
              child: const Center(
                child: Icon(Icons.design_services_rounded, size: 90, color: Colors.white),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.18),
                    Colors.black.withOpacity(0.70),
                  ],
                ),
              ),
            ),
          ),

          // TOP TOKEN BADGE (display only)
          if (tokenTopText.isNotEmpty)
            Positioned(
              left: 12,
              right: 12,
              top: 110,
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: _brandGradH,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 16,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: Text(
                    tokenTopText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ),
            ),

          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.18)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _heroChip(
                            icon: Icons.currency_rupee_rounded,
                            text: "₹${price.toStringAsFixed(0)}",
                            grad: _brandGradH,
                            solid: true,
                          ),
                          if (schedule.isNotEmpty)
                            _heroChip(
                              icon: Icons.calendar_month_rounded,
                              text: schedule,
                              grad: const LinearGradient(colors: [Colors.transparent, Colors.transparent]),
                              solid: false,
                            ),
                          if (duration.isNotEmpty)
                            _heroChip(
                              icon: Icons.timer_rounded,
                              text: duration,
                              grad: const LinearGradient(colors: [Colors.transparent, Colors.transparent]),
                              solid: false,
                            ),
                          _heroChip(
                            icon: autoApprove ? Icons.flash_on_rounded : Icons.verified_rounded,
                            text: autoApprove ? "Auto approve" : "Manual approve",
                            grad: const LinearGradient(colors: [Colors.transparent, Colors.transparent]),
                            solid: false,
                          ),
                          if (tokenEnabled == 1 && tokenLimit > 0)
                            _heroChip(
                              icon: Icons.confirmation_number_outlined,
                              text: "${tokenUsed > 0 ? tokenUsed : 0}/$tokenLimit",
                              grad: const LinearGradient(colors: [Colors.transparent, Colors.transparent]),
                              solid: false,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroChip({
    required IconData icon,
    required String text,
    required LinearGradient grad,
    required bool solid,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: solid ? grad : null,
        color: solid ? null : Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  // ===================== CARD =====================
  Widget _card({required Widget child}) {
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
      child: child,
    );
  }

  Widget _rowInfo(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoPill({
    required IconData icon,
    required String label,
    required String value,
    required LinearGradient grad,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: grad,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, size: 0),
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            "$label: ",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.white.withOpacity(0.92),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
        ],
      ),
    );
  }

  // ===================== BOTTOM BAR =====================
  Widget _bottomBookingBar(
      BuildContext context, {
        required double price,
        required String duration,
        required String schedule,
        required bool canBook,
        required String reason,
        required String? fixedBookingDate,
      }) {
    final subText = schedule.isNotEmpty
        ? "Date: $schedule"
        : (duration.isNotEmpty ? "Duration: $duration" : "Booking service");

    final buttonText = canBook ? "BOOK NOW" : (reason.isNotEmpty ? reason.toUpperCase() : "CLOSED");

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
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
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
                      subText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
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
                    gradient: canBook ? _brandGradH : null,
                    color: canBook ? null : Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: canBook
                        ? () {
                      // ✅ inject booking_date + service_id so BookServicePage can use it
                      final sid = _serviceId(service);
                      final payload = Map<String, dynamic>.from(service);
                      if (sid > 0) payload["service_id"] = sid;
                      if (fixedBookingDate != null && fixedBookingDate.isNotEmpty) {
                        payload["booking_date"] = fixedBookingDate;
                      }

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BookServicePage(service: payload),
                        ),
                      );
                    }
                        : () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(reason.isNotEmpty ? reason : "Booking closed"),
                          backgroundColor: Colors.red,
                        ),
                      );
                    },
                    icon: Icon(
                      canBook ? Icons.event_available_rounded : Icons.block_rounded,
                      color: Colors.white,
                    ),
                    label: Text(
                      buttonText,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

  // ===================== OWNER MENU (BOTTOM SHEET) =====================
  Widget _ownerMenuButton(BuildContext context) {
    return IconButton(
      onPressed: () => _openOwnerSheet(context),
      icon: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.16),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.22)),
        ),
        child: const Icon(Icons.more_vert, color: Colors.white),
      ),
    );
  }

  void _openOwnerSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: const Text("Edit Service"),
                  onTap: () async {
                    Navigator.pop(context);

                    final ok = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => EditServicePage(service: service)),
                    );

                    if (ok == true && context.mounted) {
                      Navigator.pop(context, true);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_rounded, color: Colors.red),
                  title: const Text("Delete Service"),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmDelete(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ===================== DELETE =====================
  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Service?"),
        content: const Text("Are you sure you want to delete this service?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);

              final sid = _serviceId(service);
              if (sid <= 0) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Service id missing"),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              final res = await ServicesAPI.deleteService(sid.toString());
              final success = res["success"] == true;

              if (!context.mounted) return;

              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Service deleted successfully"),
                    backgroundColor: Colors.green,
                  ),
                );
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(res["message"] ?? "Failed to delete service"),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }
}
