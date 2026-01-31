import 'package:flutter/material.dart';

import '../controllers/business_profile_controller.dart';
import '../Service/service_details_page.dart';
import '../Service/edit_service_page.dart';

class BPServicesTab extends StatelessWidget {
  final BusinessProfileController ctrl;

  /// ✅ parent থেকে force owner (recommended)
  final bool? isOwnerOverride;

  const BPServicesTab({
    super.key,
    required this.ctrl,
    this.isOwnerOverride,
  });

  static const LinearGradient _brandGradient = LinearGradient(
    colors: [Color(0xFF5B2EFF), Color(0xFFB12EFF)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // ✅ production base url for images
  static const String _publicBase = "https://adminapi.troonky.in/";

  String _s(dynamic v) => (v ?? "").toString().trim();

  int _i(dynamic v, {int def = 0}) {
    final t = _s(v);
    final n = int.tryParse(t);
    return n ?? def;
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  String _serviceId(Map<String, dynamic> s) =>
      _s(s["id"] ?? s["_id"] ?? s["serviceId"] ?? s["service_id"] ?? s["serviceId"]);

  // ✅ "2026-01-04" / ISO support
  String _prettyDate(String input) {
    final t = input.trim();
    if (t.isEmpty) return "";
    final dt = DateTime.tryParse(t);
    if (dt == null) return t;

    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec"
    ];
    final dd = dt.day.toString().padLeft(2, "0");
    final mon = months[(dt.month - 1).clamp(0, 11)];
    return "$dd $mon ${dt.year}";
  }

  String _toPublicUrl(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return "";
    if (v.startsWith("http://") || v.startsWith("https://")) return v;
    final cleaned = v.replaceFirst(RegExp(r"^/+"), "");
    return "$_publicBase$cleaned";
  }

  String _serviceImageUrl(Map<String, dynamic> s) {
    final raw = _s(
      s["image_url"] ??
          s["imageUrl"] ??
          s["image"] ??
          s["photo"] ??
          s["photo_url"] ??
          s["photoUrl"],
    );
    return _toPublicUrl(raw);
  }

  String _priceText(Map<String, dynamic> s) {
    final raw = _s(s["price"] ?? s["amount"] ?? s["service_price"]);
    if (raw.isEmpty) return "0";
    final n = double.tryParse(raw);
    if (n == null) return raw;
    if (n == n.roundToDouble()) return n.toStringAsFixed(0);
    return n.toStringAsFixed(2);
  }

  /// schedule_type: "everyday" / "date"
  String _scheduleType(Map<String, dynamic> s) =>
      _s(s["schedule_type"] ?? s["scheduleType"]).toLowerCase();

  String _serviceDateIso(Map<String, dynamic> s) =>
      _s(s["service_date"] ?? s["serviceDate"] ?? s["date"]);

  /// token config fields
  bool _tokenEnabled(Map<String, dynamic> s) {
    final st = _scheduleType(s);
    if (st == "everyday" || st == "date") return true;

    final en = _i(s["token_enabled"] ?? s["tokenEnabled"]);
    return en == 1;
  }

  int _tokenLimit(Map<String, dynamic> s) {
    final v = s["token_limit"] ?? s["tokenLimit"];
    return _i(v, def: 0);
  }

  String _tokenCutoff(Map<String, dynamic> s) {
    // HH:mm
    return _s(
      s["token_cutoff_time"] ??
          s["tokenCutoffTime"] ??
          s["cutoff_time"] ??
          s["cutoffTime"],
    );
  }

  int _tokenUsed(Map<String, dynamic> s) {
    // backend future: send any one of these
    return _i(
      s["token_used"] ??
          s["tokenUsed"] ??
          s["token_count"] ??
          s["tokenCount"] ??
          s["tokens_taken"] ??
          s["tokensTaken"] ??
          s["tokens"] ??
          s["token_no"],
      def: 0,
    );
  }

  TimeOfDay? _parseHHmm(String t) {
    final v = t.trim();
    if (!RegExp(r"^\d{2}:\d{2}$").hasMatch(v)) return null;
    final hh = int.tryParse(v.substring(0, 2));
    final mm = int.tryParse(v.substring(3, 5));
    if (hh == null || mm == null) return null;
    if (hh < 0 || hh > 23 || mm < 0 || mm > 59) return null;
    return TimeOfDay(hour: hh, minute: mm);
  }

  DateTime _atToday(TimeOfDay t) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, t.hour, t.minute);
  }

  /// ✅ booking availability logic
  /// returns record: (canBook, reason)
  ({bool canBook, String reason}) _bookingStatus(Map<String, dynamic> s) {
    final isActive = _i(s["is_active"] ?? s["isActive"], def: 1) != 0;
    final isDeleted = _i(s["is_deleted"] ?? s["isDeleted"], def: 0) == 1;
    if (!isActive || isDeleted) return (canBook: false, reason: "Closed");

    final st = _scheduleType(s);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // token limit
    final limit = _tokenLimit(s);
    final used = _tokenUsed(s);
    if (limit > 0 && used >= limit) {
      return (canBook: false, reason: "Full");
    }

    final cutoffStr = _tokenCutoff(s);
    final cutoff = _parseHHmm(cutoffStr);
    final cutoffPassed = (cutoff != null) && now.isAfter(_atToday(cutoff));

    if (st == "date") {
      final dateIso = _serviceDateIso(s);
      final d = DateTime.tryParse(dateIso);
      if (d != null) {
        final serviceDay = DateTime(d.year, d.month, d.day);
        if (today.isAfter(serviceDay)) return (canBook: false, reason: "Expired");
        if (today.isAtSameMomentAs(serviceDay) && cutoffPassed) {
          return (canBook: false, reason: "Closed");
        }
      }
    } else if (st == "everyday") {
      if (cutoffPassed) return (canBook: false, reason: "Closed");
    }

    return (canBook: true, reason: "");
  }

  String _scheduleText(Map<String, dynamic> s) {
    final type = _scheduleType(s);
    if (type == "everyday") return "Everyday";

    final date = _serviceDateIso(s);
    if (date.isNotEmpty) return _prettyDate(date);

    final created = _s(s["created_at"] ?? s["createdAt"]);
    if (created.isNotEmpty) return _prettyDate(created);

    return "";
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        final bool isOwnerNow = isOwnerOverride ?? ctrl.isOwner;
        final pager = ctrl.servicesPager;

        final List<Map<String, dynamic>> services =
        pager.items.map(_asMap).where((m) => m.isNotEmpty).toList();

        if (pager.loadingFirst && services.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (pager.error.isNotEmpty && services.isEmpty) {
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
            child: services.isEmpty
                ? const Center(
              child: Text(
                "No services added yet",
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: services.length + (pager.hasMore ? 1 : 0),
              itemBuilder: (_, index) {
                if (index >= services.length) {
                  if (pager.loadingNext) {
                    return const Padding(
                      padding: EdgeInsets.all(18),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return Center(
                    child: TextButton.icon(
                      onPressed: () => pager.loadNext(),
                      icon: const Icon(Icons.expand_more),
                      label: const Text('Load more'),
                    ),
                  );
                }

                final s = services[index];

                final name =
                _s(s["name"]).isEmpty ? "Service" : _s(s["name"]);
                final desc = _s(s["description"]);
                final image = _serviceImageUrl(s);

                final price = _priceText(s);
                final schedule = _scheduleText(s);

                final tokenEnabled = _tokenEnabled(s);
                final tokenLimit = _tokenLimit(s);
                final tokenCutoff = _tokenCutoff(s);

                final status = _bookingStatus(s);
                final canBook = status.canBook;

                return InkWell(
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ServiceDetailsPage(
                          service: s,
                          isOwner: isOwnerNow,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // IMAGE
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: 86,
                              height: 86,
                              color: Colors.grey.shade100,
                              child: image.isNotEmpty
                                  ? Image.network(
                                image,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                const Icon(
                                  Icons.broken_image_rounded,
                                  size: 34,
                                  color: Colors.grey,
                                ),
                              )
                                  : const Icon(
                                Icons.design_services_rounded,
                                size: 36,
                                color: Colors.grey,
                              ),
                            ),
                          ),

                          const SizedBox(width: 12),

                          // RIGHT SIDE
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                // Title + menu
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w900,
                                          height: 1.1,
                                        ),
                                      ),
                                    ),
                                    if (isOwnerNow)
                                      _threeDotMenu(context, s),
                                  ],
                                ),

                                if (desc.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    desc,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      height: 1.2,
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 10),

                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (price.isNotEmpty)
                                      _pricePill(price),
                                    if (schedule.isNotEmpty)
                                      _miniPill(
                                          Icons.schedule_rounded,
                                          schedule),
                                    if (tokenEnabled)
                                      _miniPill(
                                        Icons.confirmation_number_rounded,
                                        'Token: $tokenLimit',
                                      ),
                                    if (tokenCutoff.isNotEmpty)
                                      _miniPill(
                                        Icons.timer_rounded,
                                        'Cutoff: $tokenCutoff',
                                      ),
                                    if (!canBook && status.reason.isNotEmpty)
                                      _statusPill(status.reason),
                                  ],
                                ),

                                const SizedBox(height: 12),

                                // CTA
                                Row(
                                  children: [
                                    Expanded(
                                      child: _bookButton(
                                        context,
                                        s,
                                        enabled: canBook,
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
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ---------- UI PARTS ----------
  Widget _pricePill(String price) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: _brandGradient,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        "₹$price",
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 12.5,
        ),
      ),
    );
  }

  Widget _miniPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.red.withValues(alpha: 0.18)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: Colors.red.shade700,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  // ✅ Owner menu (Edit/Delete)
  Widget _threeDotMenu(BuildContext context, Map<String, dynamic> s) {
    return SizedBox(
      width: 34,
      height: 34,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: PopupMenuButton<String>(
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.more_vert_rounded, size: 18),
          onSelected: (value) async {
            if (value == "edit") {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => EditServicePage(service: s)),
              );

              if (context.mounted) {
                if (result is Map && result["service"] is Map) {
                  ctrl.upsertService(
                      Map<String, dynamic>.from(result["service"] as Map));
                } else if (result == true) {
                  await ctrl.refresh();
                }
              }
            } else if (value == "delete") {
              _confirmDelete(context, s);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: "edit",
              child: Row(
                children: [
                  Icon(Icons.edit_rounded, size: 18),
                  SizedBox(width: 10),
                  Text("Edit Service"),
                ],
              ),
            ),
            PopupMenuItem(
              value: "delete",
              child: Row(
                children: [
                  Icon(Icons.delete_rounded, size: 18, color: Colors.red),
                  SizedBox(width: 10),
                  Text("Delete Service"),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bookButton(BuildContext context, Map<String, dynamic> s,
      {required bool enabled}) {
    return InkWell(
      onTap: enabled
          ? () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ServiceDetailsPage(service: s, isOwner: false),
          ),
        );
      }
          : null,
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            gradient: enabled ? _brandGradient : null,
            color: enabled ? null : Colors.grey.shade400,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                enabled ? Icons.calendar_month_rounded : Icons.block_rounded,
                size: 17,
                color: Colors.white,
              ),
              const SizedBox(width: 7),
              Text(
                enabled ? "Book" : "Closed",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- DELETE ----------
  void _confirmDelete(BuildContext context, Map<String, dynamic> service) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Service"),
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

              final id = _serviceId(service);
              if (id.isEmpty) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Service id missing"),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              bool ok = false;
              try {
                ok = await ctrl.deleteService(id);
              } catch (_) {
                ok = false;
              }

              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      ok ? "Service deleted successfully" : "Delete failed"),
                  backgroundColor: ok ? Colors.green : Colors.red,
                ),
              );
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }
}
