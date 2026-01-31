import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/image_compressor.dart';
import '../../../services/services_api.dart';

class AddServicePage extends StatefulWidget {
  final String businessId; // shopId/businessId

  const AddServicePage({
    super.key,
    required this.businessId,
  });

  @override
  State<AddServicePage> createState() => _AddServicePageState();
}

class _AddServicePageState extends State<AddServicePage> {
  final _formKey = GlobalKey<FormState>();

  final nameCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  final durationCtrl = TextEditingController(); // read-only (picker fills)
  final descCtrl = TextEditingController();

  final locationCtrl = TextEditingController();
  final workingHoursCtrl = TextEditingController();

  // ✅ token config
  final tokenLimitCtrl = TextEditingController();
  final tokenCutoffCtrl = TextEditingController(); // read-only time label
  TimeOfDay? _tokenCutoffTime;

  String? _cachedBusinessName;

  final List<String> _categories = const [
    "Doctor",
    "Salon/Parlour",
    "Class/Tutor",
    "Seminar/Event",
    "Consultation",
    "Other",
  ];
  String _selectedCategory = "Other";

  File? serviceImage;
  bool isLoading = false;

  // ✅ Duration optional
  int _durationMinutes = 0; // 0 = Not set

  // ✅ Auto approve (MANDATORY ON) - default ON
  bool _autoApprove = true;

  // ✅ Schedule options (Date vs Everyday)
  bool _everyday = false;
  DateTime? _serviceDate;

  static const _brandGrad = LinearGradient(
    colors: [Color(0xFF5B2EFF), Color(0xFFB12EFF)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  @override
  void initState() {
    super.initState();
    durationCtrl.text = "";
    tokenCutoffCtrl.text = "";
    _loadBusinessNameForPreview();
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    priceCtrl.dispose();
    durationCtrl.dispose();
    descCtrl.dispose();
    locationCtrl.dispose();
    workingHoursCtrl.dispose();
    tokenLimitCtrl.dispose();
    tokenCutoffCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBusinessNameForPreview() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = (prefs.getString("businessName") ??
          prefs.getString("business_name") ??
          prefs.getString("shopName") ??
          prefs.getString("shop_name") ??
          "")
          .trim();
      if (!mounted) return;
      setState(() => _cachedBusinessName = v.isEmpty ? null : v);
    } catch (_) {}
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.deepPurple,
      ),
    );
  }

  // ------------------------------------------------------------
  // helpers
  // ------------------------------------------------------------
  String _dateIso(DateTime d) {
    final mm = d.month.toString().padLeft(2, "0");
    final dd = d.day.toString().padLeft(2, "0");
    return "${d.year}-$mm-$dd";
  }

  String _dateDisplay(DateTime d) {
    const months = [
      "Jan","Feb","Mar","Apr","May","Jun",
      "Jul","Aug","Sep","Oct","Nov","Dec"
    ];
    final dd = d.day.toString().padLeft(2, "0");
    final mon = months[(d.month - 1).clamp(0, 11)];
    return "$dd $mon ${d.year}";
  }

  String _dateDDMMYYYY(DateTime d) {
    final dd = d.day.toString().padLeft(2, "0");
    final mm = d.month.toString().padLeft(2, "0");
    return "$dd$mm${d.year}";
  }

  String _timeHHmm(TimeOfDay t) {
    final hh = t.hour.toString().padLeft(2, "0");
    final mm = t.minute.toString().padLeft(2, "0");
    return "$hh:$mm";
  }

  bool _tokenSystemEnabled() => _everyday || _serviceDate != null;

  String _tokenPreview() {
    final name = (_cachedBusinessName ?? "").trim();
    final prefix = name.isNotEmpty ? name[0].toUpperCase() : "S";
    final now = DateTime.now();
    final d = _serviceDate ?? DateTime(now.year, now.month, now.day);
    return "${prefix}${_dateDDMMYYYY(d)}001";
  }

  int _tokenLimitValue() {
    final raw = tokenLimitCtrl.text.trim();
    return int.tryParse(raw) ?? 0;
  }

  // ------------------------------------------------------------
  // pickers
  // ------------------------------------------------------------
  Future<void> _pickScheduleDate() async {
    if (isLoading) return;

    final now = DateTime.now();
    final initial = _serviceDate ?? DateTime(now.year, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2, 12, 31),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF5B2EFF),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (!mounted) return;
    if (picked == null) return;

    setState(() {
      _serviceDate = DateTime(picked.year, picked.month, picked.day);
      _everyday = false;
    });
  }

  Future<void> _pickTokenCutoffTime() async {
    if (isLoading) return;

    final picked = await showTimePicker(
      context: context,
      initialTime: _tokenCutoffTime ?? const TimeOfDay(hour: 18, minute: 0),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF5B2EFF),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (!mounted) return;
    if (picked == null) return;

    setState(() {
      _tokenCutoffTime = picked;
      tokenCutoffCtrl.text = _timeHHmm(picked);
    });
  }

  // ------------------------------------------------------------
  // Premium Duration Picker (same feel, but DB sends "X min")
  // ------------------------------------------------------------
  String _durationUiLabel(int minutes) {
    if (minutes <= 0) return "Not set";
    if (minutes < 60) return "$minutes m";
    final h = minutes ~/ 60;
    final mm = (minutes % 60).toString().padLeft(2, "0");
    return "$h:$mm h";
  }

  Future<void> _pickDurationPremium() async {
    if (isLoading) return;

    final quick = <int>[0, 10, 15, 20, 30, 45, 60, 90, 120, 180];
    int temp = _durationMinutes;

    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (ctx) {
        return _GlassSheet(
          child: StatefulBuilder(
            builder: (_, setD) {
              final opts = List<int>.generate(37, (i) => i * 5)
                  .where((m) => m <= 180)
                  .toList();

              int clamp5(int v) {
                if (v < 0) return 0;
                if (v > 180) return 180;
                return (v / 5).round() * 5;
              }

              void setTemp(int v) => setD(() => temp = clamp5(v));

              return Padding(
                padding: EdgeInsets.only(
                  left: 14,
                  right: 14,
                  top: 12,
                  bottom: 14 + MediaQuery.of(ctx).padding.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 5,
                      width: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Duration",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Colors.white.withOpacity(0.95),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white.withOpacity(0.18)),
                          ),
                          child: Text(
                            _durationUiLabel(temp),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Quick pick",
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final m in quick)
                          _Chip(
                            text: _durationUiLabel(m),
                            selected: temp == m,
                            onTap: () => setTemp(m),
                          ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Precise (5 min steps)",
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withOpacity(0.16)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _MiniBtn(
                              icon: Icons.remove,
                              onTap: () => setTemp(temp - 5),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: _MinutePicker(
                              values: opts,
                              value: temp,
                              onChanged: setTemp,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _MiniBtn(
                              icon: Icons.add,
                              onTap: () => setTemp(temp + 5),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, null),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.white.withOpacity(0.35)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text(
                              "Cancel",
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, temp),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text(
                              "Done",
                              style: TextStyle(
                                color: Color(0xFF5B2EFF),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    if (!mounted) return;
    if (picked == null) return;

    setState(() {
      _durationMinutes = picked;
      durationCtrl.text = (_durationMinutes <= 0) ? "" : _durationUiLabel(_durationMinutes);
    });
  }

  // ------------------------------------------------------------
  // image
  // ------------------------------------------------------------
  Future<void> pickServiceImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      final original = File(picked.path);
      final compressed = await ImageCompressor.compress(original);

      if (!mounted) return;
      setState(() => serviceImage = compressed ?? original);
    } catch (e) {
      debugPrint("Image Pick Error → $e");
      _snack("Failed to pick image: $e", error: true);
    }
  }

  // ------------------------------------------------------------
  // backend body (match service.js mapping)
  // ------------------------------------------------------------
  Map<String, dynamic> _buildBody() {
    final rawId = widget.businessId.toString().trim();
    final intId = int.tryParse(rawId);
    final price = double.tryParse(priceCtrl.text.trim()) ?? 0;

    final tokenEnabled = _tokenSystemEnabled();

    final body = <String, dynamic>{
      // business/shop id (backend can pick from token OR param OR body)
      "shop_id": intId ?? rawId,
      "business_id": intId ?? rawId,

      "name": nameCtrl.text.trim(),
      "price": price,
      "description": descCtrl.text.trim(),

      // backend uses category -> service_type too
      "category": _selectedCategory,
      "location": locationCtrl.text.trim(),
      "working_hours": workingHoursCtrl.text.trim(),

      // ✅ mandatory
      "auto_approve": 1,
      "is_active": 1,
    };

    // duration
    if (_durationMinutes > 0) {
      body["duration_minutes"] = _durationMinutes;
      body["duration"] = "${_durationMinutes} min"; // backend durationFromBody safe
    }

    // schedule
    if (_serviceDate != null) {
      body["schedule_type"] = "date";
      body["service_date"] = _dateIso(_serviceDate!);
    } else if (_everyday) {
      body["schedule_type"] = "everyday";
    }

    // token config only if schedule enabled
    if (tokenEnabled) {
      body["token_enabled"] = 1;
      body["token_limit"] = _tokenLimitValue();
      body["token_cutoff_time"] = tokenCutoffCtrl.text.trim(); // HH:mm
      body["token_reset_mode"] = "midnight";
      body["token_rule"] = "FIRST_LETTER + DDMMYYYY + 3DIGIT";
    }

    return body;
  }

  bool _validateTokenConfig() {
    if (!_tokenSystemEnabled()) return true;

    if (_tokenCutoffTime == null || tokenCutoffCtrl.text.trim().isEmpty) {
      _snack("Token cutoff time সেট করো", error: true);
      return false;
    }
    final limit = _tokenLimitValue();
    if (limit <= 0) {
      _snack("Token limit সেট করো (যেমন 50/100)", error: true);
      return false;
    }
    return true;
  }

  Future<void> saveService() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    // mandatory auto approve
    if (!_autoApprove) {
      _snack("Auto Approve ON না করলে Service post হবে না", error: true);
      return;
    }

    if (serviceImage == null) {
      _snack("Please upload a service image", error: true);
      return;
    }

    if (!_validateTokenConfig()) return;

    setState(() => isLoading = true);

    final body = _buildBody();

    try {
      final res = await ServicesAPI.addService(
        body: body,
        imageFile: serviceImage!,
      );

      if (!mounted) return;
      setState(() => isLoading = false);

      final ok = (res["success"] == true) ||
          (res["error"] == false) ||
          (res["status"] == true);

      if (ok) {
        _snack("Service added successfully!");
        final payload = <String, dynamic>{
          "ok": true,
          "action": "created",
          "service": res["service"] ?? (res["data"] is Map ? (res["data"]["service"] ?? res["data"]["data"] ?? res["data"]) : res["data"]),
        };
        Navigator.pop(context, payload);
      } else {
        _snack("Failed: ${res["message"] ?? "Something went wrong"}", error: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      _snack("Network error: $e", error: true);
    }
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final tokenEnabled = _tokenSystemEnabled();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text("Add New Service", style: TextStyle(fontWeight: FontWeight.w900)),
        centerTitle: true,
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: _brandGrad)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 22),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _CardShell(
                title: "Service Image",
                child: InkWell(
                  onTap: isLoading ? null : pickServiceImage,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    height: 190,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.05),
                          Colors.black.withOpacity(0.02),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      image: serviceImage != null
                          ? DecorationImage(image: FileImage(serviceImage!), fit: BoxFit.cover)
                          : null,
                    ),
                    child: serviceImage == null
                        ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 14,
                                offset: const Offset(0, 8),
                              )
                            ],
                          ),
                          child: const Icon(Icons.add_photo_alternate_outlined, size: 30),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Tap to upload",
                          style: TextStyle(
                            color: Colors.grey.shade800,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "A clean cover builds trust",
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                        : Align(
                      alignment: Alignment.topRight,
                      child: Container(
                        margin: const EdgeInsets.all(10),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          "Change",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              _CardShell(
                title: "General Information",
                child: Column(
                  children: [
                    _field(
                      label: "Service Name *",
                      controller: nameCtrl,
                      hint: "e.g. Doctor Consultation / Haircut",
                      icon: Icons.title,
                      validator: (v) => (v == null || v.trim().isEmpty) ? "Enter service name" : null,
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _field(
                            label: "Price (₹) *",
                            controller: priceCtrl,
                            hint: "500",
                            icon: Icons.currency_rupee,
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              final t = (v ?? "").trim();
                              if (t.isEmpty) return "Enter price";
                              final p = double.tryParse(t);
                              if (p == null) return "Invalid price";
                              if (p <= 0) return "Price must be > 0";
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _pickerField(
                            label: "Duration (Optional)",
                            controller: durationCtrl,
                            hint: "Not set",
                            icon: Icons.timer_outlined,
                            onTap: _pickDurationPremium,
                            trailing: durationCtrl.text.trim().isEmpty
                                ? const Icon(Icons.keyboard_arrow_down_rounded)
                                : IconButton(
                              onPressed: isLoading
                                  ? null
                                  : () => setState(() {
                                _durationMinutes = 0;
                                durationCtrl.text = "";
                              }),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              _CardShell(
                title: "Schedule (Optional)",
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF5B2EFF).withOpacity(0.10),
                        const Color(0xFFB12EFF).withOpacity(0.08),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: const Color(0xFF5B2EFF).withOpacity(0.10)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Choose one", style: TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Expanded(
                            child: _ChoicePill(
                              title: "Everyday",
                              subtitle: "Token refresh 12AM",
                              selected: _everyday && _serviceDate == null,
                              icon: Icons.repeat_rounded,
                              onTap: isLoading
                                  ? null
                                  : () {
                                setState(() {
                                  _everyday = true;
                                  _serviceDate = null;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _ChoicePill(
                              title: "Date",
                              subtitle: _serviceDate == null ? "Pick a date" : _dateDisplay(_serviceDate!),
                              selected: _serviceDate != null,
                              icon: Icons.calendar_month_rounded,
                              onTap: isLoading ? null : _pickScheduleDate,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      if (_serviceDate != null)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                "Selected date service. After that day booking off (backend).",
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: isLoading
                                  ? null
                                  : () => setState(() {
                                _serviceDate = null;
                              }),
                              child: const Text("Clear"),
                            ),
                          ],
                        )
                      else if (_everyday)
                        Text(
                          "Everyday is ON.",
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      else
                        Text(
                          "Leave empty for normal/manual token logic.",
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w700,
                          ),
                        ),

                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: _pickerField(
                              label: "Token cutoff time${tokenEnabled ? " *" : ""}",
                              controller: tokenCutoffCtrl,
                              hint: "Pick time",
                              icon: Icons.schedule_outlined,
                              onTap: _pickTokenCutoffTime,
                              trailing: tokenCutoffCtrl.text.trim().isEmpty
                                  ? const Icon(Icons.keyboard_arrow_down_rounded)
                                  : IconButton(
                                onPressed: isLoading
                                    ? null
                                    : () => setState(() {
                                  _tokenCutoffTime = null;
                                  tokenCutoffCtrl.text = "";
                                }),
                                icon: const Icon(Icons.close, size: 18),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _field(
                              label: "Token limit${tokenEnabled ? " *" : ""}",
                              controller: tokenLimitCtrl,
                              hint: "e.g. 50",
                              icon: Icons.confirmation_number_outlined,
                              keyboardType: TextInputType.number,
                              validator: (v) {
                                if (!tokenEnabled) return null;
                                final n = int.tryParse((v ?? "").trim());
                                if (n == null || n <= 0) return "Enter limit";
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.65),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF5B2EFF).withOpacity(0.10)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Token format preview", style: TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 6),
                            Text(
                              _tokenPreview(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: Color(0xFF5B2EFF),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "Rule: 1st letter + DDMMYYYY + 001.. (reset 12AM).",
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              _CardShell(
                title: "Automation",
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF5B2EFF).withOpacity(0.10),
                        const Color(0xFFB12EFF).withOpacity(0.08),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: const Color(0xFF5B2EFF).withOpacity(0.10)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 6),
                            )
                          ],
                        ),
                        child: const Icon(Icons.bolt_rounded, color: Color(0xFF5B2EFF)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Auto Approve (Required)",
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                            const SizedBox(height: 4),
                            Text(
                              _autoApprove
                                  ? "ON: Service post হবে"
                                  : "OFF: Service post হবে না",
                              style: TextStyle(
                                color: _autoApprove ? Colors.grey.shade700 : Colors.red.shade700,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _autoApprove,
                        onChanged: isLoading ? null : (v) => setState(() => _autoApprove = v),
                        activeColor: const Color(0xFF5B2EFF),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              _CardShell(title: "Category", child: _dropdown()),

              const SizedBox(height: 12),

              _CardShell(
                title: "Appointment Info (Optional)",
                child: Column(
                  children: [
                    _field(
                      label: "Location / Address",
                      controller: locationCtrl,
                      hint: "Clinic/Salon/Center address",
                      icon: Icons.location_on_outlined,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    _field(
                      label: "Working Hours",
                      controller: workingHoursCtrl,
                      hint: "e.g. 10AM - 7PM",
                      icon: Icons.schedule,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              _CardShell(
                title: "Description",
                child: _field(
                  label: "Service Description *",
                  controller: descCtrl,
                  hint: "Describe the service, rules, requirements...",
                  icon: Icons.description_outlined,
                  maxLines: 5,
                  validator: (v) => (v == null || v.trim().isEmpty) ? "Enter service description" : null,
                ),
              ),

              const SizedBox(height: 18),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: _brandGrad,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF5B2EFF).withOpacity(0.25),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: isLoading ? null : saveService,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    child: isLoading
                        ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                        : const Text(
                      "Add Service",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // UI small parts
  // ------------------------------------------------------------
  Widget _dropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7FB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCategory,
          isExpanded: true,
          borderRadius: BorderRadius.circular(16),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
          onChanged: isLoading ? null : (v) => setState(() => _selectedCategory = v ?? "Other"),
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon),
            filled: true,
            fillColor: const Color(0xFFF7F7FB),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pickerField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required VoidCallback onTap,
    required Widget trailing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          readOnly: true,
          onTap: onTap,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon),
            suffixIcon: trailing,
            filled: true,
            fillColor: const Color(0xFFF7F7FB),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------
// Premium shells + picker widgets
// ------------------------------------------------------------
class _CardShell extends StatelessWidget {
  final String title;
  final Widget child;

  const _CardShell({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ChoicePill extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final IconData icon;
  final VoidCallback? onTap;

  const _ChoicePill({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  static const _grad = LinearGradient(
    colors: [Color(0xFF5B2EFF), Color(0xFFB12EFF)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: selected ? _grad : null,
          color: selected ? null : Colors.white.withOpacity(0.65),
          border: Border.all(
            color: selected ? Colors.transparent : const Color(0xFF5B2EFF).withOpacity(0.18),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: selected ? Colors.white : Colors.white.withOpacity(0.85),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: const Color(0xFF5B2EFF)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: selected ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white.withOpacity(0.92) : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassSheet extends StatelessWidget {
  final Widget child;
  const _GlassSheet({required this.child});

  static const _grad = LinearGradient(
    colors: [Color(0xFF5B2EFF), Color(0xFFB12EFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: const BoxDecoration(
            gradient: _grad,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({required this.text, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withOpacity(0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withOpacity(selected ? 0.0 : 0.18)),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: selected ? const Color(0xFF5B2EFF) : Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _MiniBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MiniBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.16),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.18)),
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _MinutePicker extends StatelessWidget {
  final List<int> values;
  final int value;
  final ValueChanged<int> onChanged;

  const _MinutePicker({
    required this.values,
    required this.value,
    required this.onChanged,
  });

  String _label(int m) {
    if (m == 0) return "Not set";
    if (m < 60) return "$m m";
    final h = m ~/ 60;
    final mm = (m % 60).toString().padLeft(2, "0");
    return "$h:$mm h";
  }

  @override
  Widget build(BuildContext context) {
    final idx = values.indexOf(value).clamp(0, values.length - 1);

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: values[idx],
          isExpanded: true,
          dropdownColor: const Color(0xFF2A145C),
          iconEnabledColor: Colors.white,
          items: values
              .map((m) => DropdownMenuItem(
            value: m,
            child: Text(
              _label(m),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
            ),
          ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
