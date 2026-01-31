// lib/pages/business_profile/chart_analysis_page.dart
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// =============================================================
/// ChartAnalysisPage (NO PDF / ONLY VIEW)
/// - Date filter: Today / 7d / 30d / Custom
/// - KPI cards: Sales, Orders, Items Sold, Low Stock
/// - Main chart toggle: Sales(Line) / Orders(Bar) / Stock(Line)
/// - Top products list
/// - Low stock alert list
///
/// ✅ FINAL:
/// - accepts businessId + business
/// - default useMockOnly = false (LIVE API)
/// - token read fallback (token/auth_token/jwt)
/// =============================================================

class ChartAnalysisPage extends StatefulWidget {
  final String businessId;
  final Map<String, dynamic> business;

  /// ✅ LIVE by default now
  final bool useMockOnly;

  const ChartAnalysisPage({
    super.key,
    required this.businessId,
    required this.business,
    this.useMockOnly = false,
  });

  @override
  State<ChartAnalysisPage> createState() => _ChartAnalysisPageState();
}

class _ChartAnalysisPageState extends State<ChartAnalysisPage> {
  late final AnalyticsAPI _api;

  DateTimeRange _range = _presetRange(_PresetRange.last7Days);

  _PresetRange _preset = _PresetRange.last7Days;
  _Metric _metric = _Metric.sales;
  bool _loading = true;
  String? _error;

  AnalyticsReport _report = AnalyticsReport.empty();

  // memoization: avoid re-fetching same range
  final Map<String, AnalyticsReport> _memo = {};
  final Map<String, Future<AnalyticsReport>> _inflight = {};

  @override
  void initState() {
    super.initState();
    _api = AnalyticsAPI(
      businessId: widget.businessId,
      useMockOnly: widget.useMockOnly,
    );
    _load();
  }

  static DateTimeRange _presetRange(_PresetRange p) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    DateTime start;
    final end = todayStart.add(const Duration(days: 1)); // exclusive end

    switch (p) {
      case _PresetRange.today:
        start = todayStart;
        break;
      case _PresetRange.last7Days:
        start = todayStart.subtract(const Duration(days: 6));
        break;
      case _PresetRange.last30Days:
        start = todayStart.subtract(const Duration(days: 29));
        break;
      case _PresetRange.custom:
        start = todayStart.subtract(const Duration(days: 6));
        break;
    }

    return DateTimeRange(start: start, end: end);
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initial = _range;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(
        start: initial.start,
        end: initial.end.subtract(const Duration(days: 1)),
      ),
    );

    if (picked == null) return;

    final fixed = DateTimeRange(
      start: DateTime(picked.start.year, picked.start.month, picked.start.day),
      end: DateTime(picked.end.year, picked.end.month, picked.end.day)
          .add(const Duration(days: 1)),
    );

    setState(() {
      _preset = _PresetRange.custom;
      _range = fixed;
    });

    await _load();
  }

  Future<void> _setPreset(_PresetRange p) async {
    if (p == _PresetRange.custom) {
      await _pickCustomRange();
      return;
    }
    setState(() {
      _preset = p;
      _range = _presetRange(p);
    });
    await _load();
  }

  Future<void> _load() async {
    final key = '${_range.start.toIso8601String()}__${_range.end.toIso8601String()}';

    // instant from memory cache
    if (_memo.containsKey(key)) {
      setState(() {
        _report = _memo[key]!;
        _loading = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final fut = _inflight[key] ?? _api.fetchOverview(from: _range.start, to: _range.end);
      _inflight[key] = fut;
      final res = await fut;
      _inflight.remove(key);
      _memo[key] = res;

      if (!mounted) return;
      setState(() {
        _report = res;
        _loading = false;
      });
    } catch (e) {
      _inflight.remove(key);
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _report = AnalyticsReport.mock(from: _range.start, to: _range.end);
        _loading = false;
      });
    }
  }

  String _fmtDate(DateTime d) {
    final mm = d.month.toString().padLeft(2, "0");
    final dd = d.day.toString().padLeft(2, "0");
    return "${d.year}-$mm-$dd";
  }

  String _rangeLabel() {
    final start = _fmtDate(_range.start);
    final endInclusive = _range.end.subtract(const Duration(days: 1));
    final end = _fmtDate(endInclusive);
    return "$start → $end";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final businessName = widget.business["name"]?.toString().trim();
    final nameHeader =
    (businessName != null && businessName.isNotEmpty) ? businessName : "Business";

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: Text("Chart Analysis • $nameHeader"),
        backgroundColor: Colors.white,
        elevation: 0.6,
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            tooltip: "Refresh",
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
          children: [
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          "Date Range",
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _rangeLabel(),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _chip("Today", _preset == _PresetRange.today,
                              () => _setPreset(_PresetRange.today)),
                      _chip("Last 7 Days", _preset == _PresetRange.last7Days,
                              () => _setPreset(_PresetRange.last7Days)),
                      _chip("Last 30 Days", _preset == _PresetRange.last30Days,
                              () => _setPreset(_PresetRange.last30Days)),
                      _chip("Custom", _preset == _PresetRange.custom, _pickCustomRange),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      "⚠️ Data source issue (showing mock): $_error",
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            _kpiGrid(_report.summary),
            const SizedBox(height: 12),

            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Trends",
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _seg("Sales", _metric == _Metric.sales,
                              () => setState(() => _metric = _Metric.sales)),
                      const SizedBox(width: 8),
                      _seg("Orders", _metric == _Metric.orders,
                              () => setState(() => _metric = _Metric.orders)),
                      const SizedBox(width: 8),
                      _seg("Stock", _metric == _Metric.stock,
                              () => setState(() => _metric = _Metric.stock)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 220,
                    child: _loading
                        ? const Center(
                        child: CircularProgressIndicator(color: Colors.deepPurple))
                        : _buildChart(_metric, _report.timeseries),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _metric == _Metric.sales
                        ? "Sales (₹) by date"
                        : _metric == _Metric.orders
                        ? "Orders by date"
                        : "Stock trend by date",
                    style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Top Products",
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 12),
                  if (_loading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(color: Colors.deepPurple),
                      ),
                    )
                  else if (_report.topProducts.isEmpty)
                    Text("No product data found.",
                        style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700))
                  else
                    ..._report.topProducts.take(8).map(_productRow).toList(),
                ],
              ),
            ),

            const SizedBox(height: 12),

            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text("Low Stock Alerts",
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.red.withAlpha(18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          "${_report.lowStockProducts.length} items",
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_loading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(color: Colors.deepPurple),
                      ),
                    )
                  else if (_report.lowStockProducts.isEmpty)
                    Text("সবকিছু ঠিক আছে ✅ (No low stock)",
                        style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700))
                  else
                    ..._report.lowStockProducts.take(10).map(_lowStockRow).toList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(_Metric metric, List<DayPoint> points) {
    if (points.isEmpty) {
      return Center(
        child: Text("No data",
            style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700)),
      );
    }

    final labels = points.map((e) => e.dateLabel).toList();
    final values = points.map((e) {
      switch (metric) {
        case _Metric.sales:
          return e.sales;
        case _Metric.orders:
          return e.orders.toDouble();
        case _Metric.stock:
          return e.stock.toDouble();
      }
    }).toList();

    if (metric == _Metric.orders) {
      return SimpleBarChart(values: values, labels: labels);
    }
    return SimpleLineChart(values: values, labels: labels);
  }

  Widget _chip(String t, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(t,
          style: TextStyle(fontWeight: FontWeight.w800, color: selected ? Colors.white : Colors.black)),
      selected: selected,
      selectedColor: Colors.deepPurple,
      onSelected: (_) => onTap(),
      backgroundColor: Colors.grey.shade200,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }

  Widget _seg(String t, bool selected, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.deepPurple : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              t,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: selected ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _kpiGrid(ReportSummary s) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.55,
      children: [
        _kpiCard(title: "Total Sales", value: "₹${s.totalSales.toStringAsFixed(0)}", icon: Icons.currency_rupee),
        _kpiCard(title: "Total Orders", value: "${s.totalOrders}", icon: Icons.shopping_bag_outlined),
        _kpiCard(title: "Items Sold", value: "${s.itemsSold}", icon: Icons.inventory_2_outlined),
        _kpiCard(title: "Low Stock", value: "${s.lowStockCount}", icon: Icons.warning_amber_rounded, danger: true),
      ],
    );
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required IconData icon,
    bool danger = false,
  }) {
    final color = danger ? Colors.red : Colors.deepPurple;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 34,
                width: 34,
                decoration: BoxDecoration(color: color.withAlpha(18), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 10),
          Text(title, style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }

  Widget _productRow(ProductReport p) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
      child: Row(
        children: [
          Expanded(
            flex: 6,
            child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
          Expanded(
            flex: 2,
            child: Text("Sold ${p.qtySold}", textAlign: TextAlign.right,
                style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Text("Stock ${p.stock}", textAlign: TextAlign.right,
                style: TextStyle(color: p.stock <= 5 ? Colors.red : Colors.green.shade700, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Widget _lowStockRow(ProductReport p) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
      child: Row(
        children: [
          Expanded(
            child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.red.withAlpha(18), borderRadius: BorderRadius.circular(999)),
            child: Text("Stock ${p.stock}", style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 2))],
      ),
      child: child,
    );
  }
}

/// =============================================================
/// API + Models
/// =============================================================

class AnalyticsAPI {
  static const String _baseUrl = "https://adminapi.troonky.in/api";

  final String businessId;
  final bool useMockOnly;

  AnalyticsAPI({required this.businessId, required this.useMockOnly});

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    // ✅ token key fallback
    return prefs.getString("token") ??
        prefs.getString("auth_token") ??
        prefs.getString("jwt");
  }

  String _fmt(DateTime d) {
    final mm = d.month.toString().padLeft(2, "0");
    final dd = d.day.toString().padLeft(2, "0");
    return "${d.year}-$mm-$dd";
  }

  Future<AnalyticsReport> fetchOverview({required DateTime from, required DateTime to}) async {
    if (useMockOnly) {
      return AnalyticsReport.mock(from: from, to: to);
    }

    final token = await _getToken();
    final headers = <String, String>{
      "Content-Type": "application/json",
      if (token != null && token.isNotEmpty) "Authorization": "Bearer $token",
    };

    final uri = Uri.parse(
      "$_baseUrl/analytics/overview"
          "?businessId=$businessId"
          "&from=${_fmt(from)}"
          "&to=${_fmt(to)}",
    );

    final res = await http.get(uri, headers: headers);

    if (res.statusCode == 401 || res.statusCode == 403) {
      throw Exception("AUTH: Please login again (token expired/invalid).");
    }
    if (res.statusCode != 200) {
      throw Exception("HTTP ${res.statusCode}: ${res.body}");
    }

    final body = jsonDecode(res.body);
    if (body is! Map) throw Exception("Invalid response shape (expected JSON object).");

    return AnalyticsReport.fromJson(Map<String, dynamic>.from(body));
  }
}

class AnalyticsReport {
  final ReportSummary summary;
  final List<DayPoint> timeseries;
  final List<ProductReport> topProducts;
  final List<ProductReport> lowStockProducts;

  const AnalyticsReport({
    required this.summary,
    required this.timeseries,
    required this.topProducts,
    required this.lowStockProducts,
  });

  factory AnalyticsReport.empty() => AnalyticsReport(
    summary: const ReportSummary(totalSales: 0, totalOrders: 0, itemsSold: 0, lowStockCount: 0),
    timeseries: const [],
    topProducts: const [],
    lowStockProducts: const [],
  );

  static double _asDouble(dynamic v, {double fallback = 0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  static int _asInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  static String _asString(dynamic v, {String fallback = ""}) {
    if (v == null) return fallback;
    return v.toString();
  }

  factory AnalyticsReport.fromJson(Map<String, dynamic> json) {
    final sumRaw = json["summary"];
    final summary = (sumRaw is Map)
        ? ReportSummary(
      totalSales: _asDouble(sumRaw["totalSales"] ?? sumRaw["sales"]),
      totalOrders: _asInt(sumRaw["totalOrders"] ?? sumRaw["orders"]),
      itemsSold: _asInt(sumRaw["itemsSold"] ?? sumRaw["qtySold"] ?? sumRaw["items"]),
      lowStockCount: _asInt(sumRaw["lowStockCount"] ?? sumRaw["lowStock"]),
    )
        : const ReportSummary(totalSales: 0, totalOrders: 0, itemsSold: 0, lowStockCount: 0);

    final tsRaw = json["timeseries"];
    final ts = <DayPoint>[];
    if (tsRaw is List) {
      for (final it in tsRaw) {
        if (it is Map) {
          final m = Map<String, dynamic>.from(it);
          ts.add(DayPoint(
            dateLabel: _asString(m["date"], fallback: ""),
            sales: _asDouble(m["sales"]),
            orders: _asInt(m["orders"]),
            stock: _asInt(m["stock"]),
          ));
        }
      }
    }

    final topRaw = json["topProducts"];
    final top = <ProductReport>[];
    if (topRaw is List) {
      for (final it in topRaw) {
        if (it is Map) {
          final m = Map<String, dynamic>.from(it);
          top.add(ProductReport(
            name: _asString(m["name"], fallback: "Product"),
            qtySold: _asInt(m["qtySold"] ?? m["sold"]),
            stock: _asInt(m["stock"]),
          ));
        }
      }
    }

    final lowRaw = json["lowStockProducts"];
    final low = <ProductReport>[];
    if (lowRaw is List) {
      for (final it in lowRaw) {
        if (it is Map) {
          final m = Map<String, dynamic>.from(it);
          low.add(ProductReport(
            name: _asString(m["name"], fallback: "Product"),
            qtySold: _asInt(m["qtySold"] ?? m["sold"]),
            stock: _asInt(m["stock"]),
          ));
        }
      }
    }

    return AnalyticsReport(summary: summary, timeseries: ts, topProducts: top, lowStockProducts: low);
  }

  factory AnalyticsReport.mock({required DateTime from, required DateTime to}) {
    final days = max(1, to.difference(from).inDays);
    final rnd = Random(from.millisecondsSinceEpoch);
    final ts = <DayPoint>[];

    double totalSales = 0;
    int totalOrders = 0;
    int itemsSold = 0;
    int stockBase = 180;

    for (int i = 0; i < days; i++) {
      final d = from.add(Duration(days: i));
      final label =
          "${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}";

      final orders = 1 + rnd.nextInt(8);
      final sales = orders * (200 + rnd.nextInt(900));
      stockBase = max(0, stockBase - rnd.nextInt(6));

      totalSales += sales.toDouble();
      totalOrders += orders;
      itemsSold += orders + rnd.nextInt(6);

      ts.add(DayPoint(dateLabel: label, sales: sales.toDouble(), orders: orders, stock: stockBase));
    }

    final products = List.generate(8, (i) {
      final sold = 5 + rnd.nextInt(40);
      final stock = rnd.nextInt(20);
      return ProductReport(name: "Product ${i + 1}", qtySold: sold, stock: stock);
    });

    products.sort((a, b) => b.qtySold.compareTo(a.qtySold));
    final low = products.where((p) => p.stock <= 5).toList();

    return AnalyticsReport(
      summary: ReportSummary(
        totalSales: totalSales,
        totalOrders: totalOrders,
        itemsSold: itemsSold,
        lowStockCount: low.length,
      ),
      timeseries: ts,
      topProducts: products,
      lowStockProducts: low,
    );
  }
}

class ReportSummary {
  final double totalSales;
  final int totalOrders;
  final int itemsSold;
  final int lowStockCount;

  const ReportSummary({
    required this.totalSales,
    required this.totalOrders,
    required this.itemsSold,
    required this.lowStockCount,
  });
}

class DayPoint {
  final String dateLabel;
  final double sales;
  final int orders;
  final int stock;

  const DayPoint({
    required this.dateLabel,
    required this.sales,
    required this.orders,
    required this.stock,
  });
}

class ProductReport {
  final String name;
  final int qtySold;
  final int stock;

  const ProductReport({
    required this.name,
    required this.qtySold,
    required this.stock,
  });
}

enum _PresetRange { today, last7Days, last30Days, custom }
enum _Metric { sales, orders, stock }

/// =============================================================
/// SIMPLE CHARTS (NO PACKAGE)
/// =============================================================

class SimpleLineChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;

  const SimpleLineChart({super.key, required this.values, required this.labels});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LineChartPainter(values: values, labels: labels),
      child: Container(),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;

  _LineChartPainter({required this.values, required this.labels});

  @override
  void paint(Canvas canvas, Size size) {
    final padL = 36.0;
    final padR = 12.0;
    final padT = 12.0;
    final padB = 26.0;

    final chartW = max(1.0, size.width - padL - padR);
    final chartH = max(1.0, size.height - padT - padB);

    final minV = values.reduce(min);
    final maxV = values.reduce(max);
    final range = (maxV - minV).abs() < 0.00001 ? 1.0 : (maxV - minV);

    final grid = Paint()..color = Colors.black.withAlpha(25)..strokeWidth = 1;
    final axis = Paint()..color = Colors.black.withAlpha(50)..strokeWidth = 1.2;
    final line = Paint()..color = Colors.deepPurple..strokeWidth = 2.6..style = PaintingStyle.stroke;
    final dot = Paint()..color = Colors.deepPurple;

    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    for (int i = 0; i <= 4; i++) {
      final y = padT + (chartH / 4) * i;
      canvas.drawLine(Offset(padL, y), Offset(padL + chartW, y), grid);
    }

    canvas.drawLine(Offset(padL, padT), Offset(padL, padT + chartH), axis);
    canvas.drawLine(Offset(padL, padT + chartH), Offset(padL + chartW, padT + chartH), axis);

    final n = values.length;
    final dx = n <= 1 ? 0.0 : chartW / (n - 1);

    final pts = <Offset>[];
    for (int i = 0; i < n; i++) {
      final norm = (values[i] - minV) / range;
      final x = padL + dx * i;
      final y = padT + chartH - (norm * chartH);
      pts.add(Offset(x, y));
    }

    final path = Path();
    if (pts.isNotEmpty) {
      path.moveTo(pts.first.dx, pts.first.dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      canvas.drawPath(path, line);
      for (final p in pts) {
        canvas.drawCircle(p, 3.4, dot);
      }
    }

    final tp = TextPainter(textDirection: TextDirection.ltr);
    final showIdx = <int>{0, (n / 2).floor(), max(0, n - 1)};
    for (final i in showIdx) {
      if (i < 0 || i >= labels.length) continue;
      final t = labels[i].split("-").last;
      tp.text = TextSpan(
        text: t,
        style: TextStyle(color: Colors.black.withAlpha(140), fontWeight: FontWeight.w700, fontSize: 11),
      );
      tp.layout();
      final x = padL + dx * i - (tp.width / 2);
      final y = padT + chartH + 6;
      tp.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    // ✅ safer repaint
    return oldDelegate.values.length != values.length ||
        oldDelegate.labels.length != labels.length ||
        oldDelegate.values.asMap().entries.any((e) => e.value != values[e.key]) ||
        oldDelegate.labels.asMap().entries.any((e) => e.value != labels[e.key]);
  }
}

class SimpleBarChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;

  const SimpleBarChart({super.key, required this.values, required this.labels});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BarChartPainter(values: values, labels: labels),
      child: Container(),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;

  _BarChartPainter({required this.values, required this.labels});

  @override
  void paint(Canvas canvas, Size size) {
    final padL = 36.0;
    final padR = 12.0;
    final padT = 12.0;
    final padB = 26.0;

    final chartW = max(1.0, size.width - padL - padR);
    final chartH = max(1.0, size.height - padT - padB);

    final maxV = max(1.0, values.reduce(max));

    final grid = Paint()..color = Colors.black.withAlpha(25)..strokeWidth = 1;
    final axis = Paint()..color = Colors.black.withAlpha(50)..strokeWidth = 1.2;
    final barPaint = Paint()..color = Colors.deepPurple.withAlpha(180);

    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    for (int i = 0; i <= 4; i++) {
      final y = padT + (chartH / 4) * i;
      canvas.drawLine(Offset(padL, y), Offset(padL + chartW, y), grid);
    }

    canvas.drawLine(Offset(padL, padT), Offset(padL, padT + chartH), axis);
    canvas.drawLine(Offset(padL, padT + chartH), Offset(padL + chartW, padT + chartH), axis);

    final n = values.length;
    final slot = chartW / max(1, n);
    final barW = min(18.0, slot * 0.55);

    for (int i = 0; i < n; i++) {
      final v = values[i];
      final h = (v / maxV) * chartH;

      final x = padL + slot * i + (slot - barW) / 2;
      final y = padT + chartH - h;

      final r = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, barW, h), const Radius.circular(8));
      canvas.drawRRect(r, barPaint);
    }

    final tp = TextPainter(textDirection: TextDirection.ltr);
    final showIdx = <int>{0, (n / 2).floor(), max(0, n - 1)};
    for (final i in showIdx) {
      if (i < 0 || i >= labels.length) continue;
      final t = labels[i].split("-").last;
      tp.text = TextSpan(
        text: t,
        style: TextStyle(color: Colors.black.withAlpha(140), fontWeight: FontWeight.w700, fontSize: 11),
      );
      tp.layout();
      final x = padL + slot * i + (slot / 2) - (tp.width / 2);
      final y = padT + chartH + 6;
      tp.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) {
    // ✅ safer repaint
    return oldDelegate.values.length != values.length ||
        oldDelegate.labels.length != labels.length ||
        oldDelegate.values.asMap().entries.any((e) => e.value != values[e.key]) ||
        oldDelegate.labels.asMap().entries.any((e) => e.value != labels[e.key]);
  }
}
