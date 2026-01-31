import 'dart:async';

import 'package:flutter/material.dart';
import 'package:troonky_link/pages/business_profile/OrderDetailsPage.dart';
import 'package:troonky_link/pages/business_profile/ServiceOrderDetailsPage.dart';
import 'package:troonky_link/services/order_api.dart';

/// ✅ Production-ready Orders dashboard (Business)
/// - Product + Service tabs
/// - Search (order id / phone / customer)
/// - Status chips
/// - Server paging (if backend supports) + safe client fallback
/// - Pull-to-refresh
class OrdersListPage extends StatefulWidget {
  final String businessId;

  const OrdersListPage({
    super.key,
    required this.businessId,
  });

  @override
  State<OrdersListPage> createState() => _OrdersListPageState();
}

class _OrdersListPageState extends State<OrdersListPage> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _scroll0 = ScrollController();
  final _scroll1 = ScrollController();

  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  bool _loadingProduct = true;
  bool _loadingService = true;
  String _errProduct = '';
  String _errService = '';

  List<Map<String, dynamic>> _allProduct = const [];
  List<Map<String, dynamic>> _allService = const [];

  // UI filters
  String _statusFilterProduct = 'all';
  String _statusFilterService = 'all';
  String _query = '';

  // paging
  static const int _pageSize = 20;
  int _pageProduct = 1;
  int _pageService = 1;

  // server paging flags
  bool _hasMoreProduct = true;
  bool _hasMoreService = true;
  bool _loadingMoreProduct = false;
  bool _loadingMoreService = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);

    _scroll0.addListener(() {
      if (_scroll0.position.pixels >= _scroll0.position.maxScrollExtent - 120) {
        _loadMoreIfPossible(isService: false);
      }
    });
    _scroll1.addListener(() {
      if (_scroll1.position.pixels >= _scroll1.position.maxScrollExtent - 120) {
        _loadMoreIfPossible(isService: true);
      }
    });

    _searchCtrl.addListener(_onSearchChanged);
    _fetchAll();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scroll0.dispose();
    _scroll1.dispose();
    _tab.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  // -----------------------------
  // Data fetch
  // -----------------------------
  Future<void> _fetchAll() async {
    await Future.wait([
      _fetchProduct(reset: true),
      _fetchService(reset: true),
    ]);
  }

  Future<void> _fetchProduct({required bool reset}) async {
    if (reset) {
      _safeSetState(() {
        _loadingProduct = true;
        _errProduct = '';
        _pageProduct = 1;
        _hasMoreProduct = true;
        _loadingMoreProduct = false;
        _allProduct = const [];
      });
    }
    try {
      final res = await OrdersAPI.getBusinessOrdersPaged(
        businessId: widget.businessId,
        page: _pageProduct,
        limit: _pageSize,
      );

      final rawItems = (res['items'] is List) ? (res['items'] as List) : const [];
      final items = rawItems
          .whereType<Map>()
          .map((e) => OrdersAPI.normalizeOrderForUi(Map<String, dynamic>.from(e)))
          .toList();

      // ✅ newest first (robust parse)
      items.sort((a, b) {
        DateTime parse(dynamic x) {
          final s = (x ?? '').toString().trim();
          if (s.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
          return DateTime.tryParse(s) ?? DateTime.fromMillisecondsSinceEpoch(0);
        }

        final da = parse(a['created_at'] ?? a['createdAt'] ?? a['date'] ?? a['order_date']);
        final db = parse(b['created_at'] ?? b['createdAt'] ?? b['date'] ?? b['order_date']);
        return db.compareTo(da);
      });

      // ✅ dedupe by id to avoid duplicates when backend paging is not strict
      final merged = reset ? <Map<String, dynamic>>[] : List<Map<String, dynamic>>.from(_allProduct);
      final seen = <String>{for (final x in merged) (x['id'] ?? x['_id'] ?? x['order_id'] ?? '').toString()};

      for (final it in items) {
        final k = (it['id'] ?? it['_id'] ?? it['order_id'] ?? '').toString();
        if (k.isEmpty || !seen.contains(k)) {
          merged.add(it);
          if (k.isNotEmpty) seen.add(k);
        }
      }

      // ✅ hasMore fallback heuristic (backend may not send meta)
      final hm = res['hasMore'];
      final serverHasMore = hm == true;
      final computedHasMore = items.length >= _pageSize;

      _safeSetState(() {
        _allProduct = merged;
        _hasMoreProduct = serverHasMore || computedHasMore;
        _loadingProduct = false;
        _loadingMoreProduct = false;
      });
    } catch (e) {
      _safeSetState(() {
        _errProduct = e.toString();
        _loadingProduct = false;
        _loadingMoreProduct = false;
        _hasMoreProduct = false;
      });
    }
  }

  Future<void> _fetchService({required bool reset}) async {
    if (reset) {
      _safeSetState(() {
        _loadingService = true;
        _errService = '';
        _pageService = 1;
        _hasMoreService = true;
        _loadingMoreService = false;
        _allService = const [];
      });
    }
    try {
      final res = await OrdersAPI.getBusinessServiceOrdersPaged(
        businessId: widget.businessId,
        page: _pageService,
        limit: _pageSize,
      );

      final rawItems = (res['items'] is List) ? (res['items'] as List) : const [];
      final items = rawItems
          .whereType<Map>()
          .map((e) {
        final m = OrdersAPI.normalizeOrderForUi(Map<String, dynamic>.from(e));
        m['type'] = 'service';
        return m;
      })
          .toList();

      items.sort((a, b) {
        DateTime parse(dynamic x) {
          final s = (x ?? '').toString().trim();
          if (s.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
          return DateTime.tryParse(s) ?? DateTime.fromMillisecondsSinceEpoch(0);
        }

        final da = parse(a['created_at'] ?? a['createdAt'] ?? a['date'] ?? a['booked_at']);
        final db = parse(b['created_at'] ?? b['createdAt'] ?? b['date'] ?? b['booked_at']);
        return db.compareTo(da);
      });

      final merged = reset ? <Map<String, dynamic>>[] : List<Map<String, dynamic>>.from(_allService);
      final seen = <String>{
        for (final x in merged) (x['id'] ?? x['booking_id'] ?? x['booking_number'] ?? '').toString()
      };

      for (final it in items) {
        final k = (it['id'] ?? it['booking_id'] ?? it['booking_number'] ?? '').toString();
        if (k.isEmpty || !seen.contains(k)) {
          merged.add(it);
          if (k.isNotEmpty) seen.add(k);
        }
      }

      final hm = res['hasMore'];
      final serverHasMore = hm == true;
      final computedHasMore = items.length >= _pageSize;

      _safeSetState(() {
        _allService = merged;
        _hasMoreService = serverHasMore || computedHasMore;
        _loadingService = false;
        _loadingMoreService = false;
      });
    } catch (e) {
      _safeSetState(() {
        _errService = e.toString();
        _loadingService = false;
        _loadingMoreService = false;
        _hasMoreService = false;
      });
    }
  }

  // -----------------------------
  // Search + Filter + Paging
  // -----------------------------
  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = _searchCtrl.text.trim();
      _safeSetState(() => _query = q);
    });
  }

  Future<void> _loadMoreIfPossible({required bool isService}) async {
    if (!_hasMore(isService: isService)) return;

    if (isService) {
      if (_loadingMoreService) return;
      _safeSetState(() {
        _loadingMoreService = true;
        _pageService += 1;
      });
      await _fetchService(reset: false);
    } else {
      if (_loadingMoreProduct) return;
      _safeSetState(() {
        _loadingMoreProduct = true;
        _pageProduct += 1;
      });
      await _fetchProduct(reset: false);
    }
  }

  bool _hasMore({required bool isService}) {
    return isService ? _hasMoreService : _hasMoreProduct;
  }

  List<Map<String, dynamic>> _filteredList({required bool isService}) {
    final source = isService ? _allService : _allProduct;
    final statusFilter = isService ? _statusFilterService : _statusFilterProduct;
    final q = _query.toLowerCase();

    bool matchStatus(Map<String, dynamic> o) {
      if (statusFilter == 'all') return true;
      final st = OrdersAPI.normalizeStatus(o['status'] ?? o['order_status']);
      return st == statusFilter;
    }

    bool matchQuery(Map<String, dynamic> o) {
      if (q.isEmpty) return true;
      final id = (o['order_code'] ??
          o['booking_number'] ??
          o['id'] ??
          o['_id'] ??
          o['order_id'] ??
          o['booking_id'] ??
          '')
          .toString();
      final name = (o['customer_name'] ?? o['name'] ?? o['user_name'] ?? '').toString();
      final phone = (o['phone'] ?? o['customer_phone'] ?? o['mobile'] ?? '').toString();
      final hay = '$id $name $phone'.toLowerCase();
      return hay.contains(q);
    }

    return source.where((o) => matchStatus(o) && matchQuery(o)).toList(growable: false);
  }

  // ✅ do NOT client-sublist by page when using server paging;
  // we already append pages into _allProduct/_allService.
  List<Map<String, dynamic>> _pagedList({required bool isService}) {
    return _filteredList(isService: isService);
  }

  // -----------------------------
  // UI helpers
  // -----------------------------
  String _money(dynamic v) {
    final s = v?.toString().trim() ?? '';
    if (s.isEmpty) return '₹0';
    final d = double.tryParse(s.replaceAll('₹', '').trim());
    if (d == null) return '₹$s';
    return '₹${d.toStringAsFixed(0)}';
  }

  String _prettyDate(dynamic v) {
    final s = (v ?? '').toString().trim();
    final dt = DateTime.tryParse(s);
    if (dt == null) return s.isEmpty ? '-' : s;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day.toString().padLeft(2, '0')} ${months[(dt.month - 1).clamp(0, 11)]} ${dt.year}';
  }

  Color _statusColor(String status) {
    switch (OrdersAPI.normalizeStatus(status)) {
      case 'cancelled':
      case 'rejected':
      case 'failed':
        return Colors.red;
      case 'completed':
      case 'delivered':
        return Colors.green;
      case 'shipped':
      case 'out_for_delivery':
        return Colors.blue;
      case 'ready':
      case 'processing':
        return Colors.deepPurple;
      default:
        return Colors.orange;
    }
  }

  List<_StatusChip> _chips({required bool isService}) {
    // ✅ service statuses are not same as product; keep broad.
    if (isService) {
      return const [
        _StatusChip('All', 'all'),
        _StatusChip('Created', 'created'),
        _StatusChip('Processing', 'processing'),
        _StatusChip('Ready', 'ready'),
        _StatusChip('Delivered', 'delivered'),
        _StatusChip('Completed', 'completed'),
        _StatusChip('Cancelled', 'cancelled'),
      ];
    }
    return const [
      _StatusChip('All', 'all'),
      _StatusChip('Created', 'created'),
      _StatusChip('Processing', 'processing'),
      _StatusChip('Ready', 'ready'),
      _StatusChip('Shipped', 'shipped'),
      _StatusChip('Out for delivery', 'out_for_delivery'),
      _StatusChip('Delivered', 'delivered'),
      _StatusChip('Completed', 'completed'),
      _StatusChip('Cancelled', 'cancelled'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Products'),
            Tab(text: 'Services'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () async {
              FocusScope.of(context).unfocus();
              await _fetchAll();
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          SizedBox(
            height: 44,
            child: TabBarView(
              controller: _tab,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildChips(isService: false),
                _buildChips(isService: true),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _buildList(isService: false),
                _buildList(isService: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: TextField(
        controller: _searchCtrl,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search order id / phone / customer',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
            onPressed: () {
              _searchCtrl.clear();
              FocusScope.of(context).unfocus();
            },
            icon: const Icon(Icons.clear),
          ),
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
        ),
      ),
    );
  }

  Widget _buildChips({required bool isService}) {
    final sel = isService ? _statusFilterService : _statusFilterProduct;
    final chips = _chips(isService: isService);

    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      children: chips.map((c) {
        final selected = c.value == sel;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(c.label),
            selected: selected,
            onSelected: (_) {
              _safeSetState(() {
                if (isService) {
                  _statusFilterService = c.value;
                } else {
                  _statusFilterProduct = c.value;
                }
              });
            },
          ),
        );
      }).toList(),
    );
  }

  Widget _buildList({required bool isService}) {
    final loading = isService ? _loadingService : _loadingProduct;
    final err = isService ? _errService : _errProduct;
    final controller = isService ? _scroll1 : _scroll0;

    final items = _pagedList(isService: isService);
    final total = items.length;
    final hasMore = _hasMore(isService: isService);

    final loadingMore = isService ? _loadingMoreService : _loadingMoreProduct;

    return RefreshIndicator(
      onRefresh: () async {
        if (isService) {
          await _fetchService(reset: true);
        } else {
          await _fetchProduct(reset: true);
        }
      },
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : err.isNotEmpty
          ? _buildError(err, onRetry: () {
        if (isService) {
          _fetchService(reset: true);
        } else {
          _fetchProduct(reset: true);
        }
      })
          : total == 0
          ? _buildEmpty()
          : ListView.builder(
        controller: controller,
        padding: const EdgeInsets.all(12),
        itemCount: items.length + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= items.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: loadingMore
                    ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: CircularProgressIndicator(),
                )
                    : OutlinedButton.icon(
                  onPressed: () => _loadMoreIfPossible(isService: isService),
                  icon: const Icon(Icons.expand_more),
                  label: const Text('Load more'),
                ),
              ),
            );
          }
          final o = items[index];
          return _buildOrderCard(o, isService: isService);
        },
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> o, {required bool isService}) {
    final status = OrdersAPI.normalizeStatus(o['status'] ?? o['order_status']);
    final statusColor = _statusColor(status);

    final id = (isService
        ? (o['booking_number'] ?? o['bookingNo'] ?? o['booking_id'] ?? o['id'])
        : (o['order_code'] ?? o['order_id'] ?? o['_id'] ?? o['id']))
        .toString();

    final name = (o['customer_name'] ?? o['name'] ?? o['user_name'] ?? 'Customer').toString();
    final phone = (o['phone'] ?? o['customer_phone'] ?? o['mobile'] ?? '').toString();
    final amount = _money(o['total_amount'] ?? o['amount'] ?? o['total'] ?? 0);
    final created = _prettyDate(o['created_at'] ?? o['createdAt'] ?? o['date'] ?? o['order_date'] ?? o['booked_at']);

    final img = OrdersAPI.firstOrderImage(o);

    return Card(
      elevation: 0.6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          if (isService) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ServiceOrderDetailsPage(order: o),
              ),
            );
          } else {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OrderDetailsPage(order: o),
              ),
            );
          }

          // ✅ refresh after back (status may have changed)
          if (isService) {
            await _fetchService(reset: true);
          } else {
            await _fetchProduct(reset: true);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: img.isEmpty
                    ? Container(
                  width: 58,
                  height: 58,
                  color: Colors.grey.shade200,
                  child: Icon(isService ? Icons.design_services_outlined : Icons.shopping_bag_outlined),
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isService ? 'Booking #$id' : 'Order #$id',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            status.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$name${phone.isEmpty ? '' : ' • $phone'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          amount,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const Spacer(),
                        Text(
                          created,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
  }

  Widget _buildEmpty() {
    return ListView(
      children: const [
        SizedBox(height: 120),
        Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
        SizedBox(height: 12),
        Center(
          child: Text(
            'No orders found',
            style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildError(String msg, {required VoidCallback onRetry}) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.cloud_off_outlined, size: 56, color: Colors.grey),
        const SizedBox(height: 12),
        Text(
          msg,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700),
        ),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}

class _StatusChip {
  final String label;
  final String value;
  const _StatusChip(this.label, this.value);
}
