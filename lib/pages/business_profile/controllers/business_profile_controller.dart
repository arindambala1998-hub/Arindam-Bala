import 'package:flutter/foundation.dart';

import 'package:troonky_link/core/cache/memory_cache.dart';
import 'package:troonky_link/core/paging/paged_controller.dart';

import 'package:troonky_link/helpers/block_helper.dart';
import 'package:troonky_link/services/business_api.dart';
import 'package:troonky_link/services/feed_api.dart';
import 'package:troonky_link/services/friends_api.dart';
import 'package:troonky_link/services/services_api.dart';

/// Production-ready controller for BusinessProfilePage.
/// ✅ Single source of truth for business + tab lists
/// ✅ In-memory cache per business (tab switch instant)
/// ✅ Pagination: Products true backend paging; others safe client paging fallback
class BusinessProfileController extends ChangeNotifier {
  final String businessId;

  bool loadingHeader = false;
  String errorHeader = '';

  bool isOwner = false; // should ideally come from backend; fallback computed
  Map<String, dynamic> business = <String, dynamic>{};

  static const int _pageSize = 20;

  late final PagedController<Map<String, dynamic>> productsPager;
  late final PagedController<Map<String, dynamic>> servicesPager;
  late final PagedController<Map<String, dynamic>> postsPager;
  late final PagedController<Map<String, dynamic>> friendsPager;

  // Client-side paging caches (until backend adds paging endpoints)
  List<Map<String, dynamic>> _servicesAll = const [];
  List<Map<String, dynamic>> _friendsAll = const [];

  // ✅ Posts paging helpers (for fallback mode)
  final List<Map<String, dynamic>> _postsAccum = <Map<String, dynamic>>[];
  bool _postsTriedBusinessEndpoint = false;
  bool _postsUseBusinessEndpoint = false;

  int _seq = 0;

  BusinessProfileController({required this.businessId}) {
    productsPager = PagedController<Map<String, dynamic>>(
      limit: _pageSize,
      loader: ({required int page, required int limit}) async {
        return BusinessAPI.fetchProducts(shopId: businessId, page: page, limit: limit);
      },
    );

    servicesPager = PagedController<Map<String, dynamic>>(
      limit: _pageSize,
      loader: ({required int page, required int limit}) async {
        if (page == 1) {
          final list = await ServicesAPI.getBusinessServices(businessId);
          _servicesAll = list;
        }
        final start = (page - 1) * limit;
        if (start >= _servicesAll.length) return [];
        final end = (start + limit).clamp(0, _servicesAll.length);
        return _servicesAll.sublist(start, end);
      },
    );

    postsPager = PagedController<Map<String, dynamic>>(
      limit: _pageSize,
      loader: ({required int page, required int limit}) async {
        // ✅ reset accum on first page
        if (page == 1) {
          _postsAccum.clear();
          _postsTriedBusinessEndpoint = false;
          _postsUseBusinessEndpoint = false;
          await BlockHelper.init();
        }

        // ✅ 1) Try business specific endpoints first (best for Instagram profile style)
        final businessPosts = await _fetchBusinessPostsIfPossible(page: page, limit: limit);
        if (businessPosts != null) {
          _postsUseBusinessEndpoint = true;
          final cleaned = BlockHelper.filterBlockedUsers(
            businessPosts.map((e) => Map<String, dynamic>.from(e)).toList(),
          );
          return cleaned;
        }

        // ✅ 2) Fallback: pull global feed pages and filter by businessId (client-side)
        final filtered = await _fetchFromGlobalFeedAndFilter(page: page, limit: limit);

        // ✅ Make paging stable: accumulate then slice to page window
        _postsAccum.addAll(filtered);

        final start = (page - 1) * limit;
        if (start >= _postsAccum.length) return [];
        final end = (start + limit).clamp(0, _postsAccum.length);
        return _postsAccum.sublist(start, end);
      },
    );

    friendsPager = PagedController<Map<String, dynamic>>(
      limit: _pageSize,
      loader: ({required int page, required int limit}) async {
        if (page == 1) {
          final raw = await FriendsAPI.getSuggestions();
          final list = <Map<String, dynamic>>[];
          for (final e in raw) {
            if (e is Map<String, dynamic>) {
              list.add(e);
            } else if (e is Map) {
              list.add(Map<String, dynamic>.from(e));
            }
          }
          _friendsAll = list;
        }
        final start = (page - 1) * limit;
        if (start >= _friendsAll.length) return [];
        final end = (start + limit).clamp(0, _friendsAll.length);
        return _friendsAll.sublist(start, end);
      },
    );

    void relay() => notifyListeners();
    productsPager.addListener(relay);
    servicesPager.addListener(relay);
    postsPager.addListener(relay);
    friendsPager.addListener(relay);
  }

  // -------------------- POSTS LOADERS --------------------

  bool _matchBusiness(Map<String, dynamic> p) {
    final id = businessId.trim();
    if (id.isEmpty) return false;

    final sid = (p['shop_id'] ?? p['shopId'] ?? p['shopID'] ?? '').toString().trim();
    final bid = (p['business_id'] ?? p['businessId'] ?? p['businessID'] ?? '').toString().trim();

    // some backends store owner business id under "seller_id" / "store_id"
    final storeId = (p['store_id'] ?? p['storeId'] ?? '').toString().trim();
    final sellerId = (p['seller_id'] ?? p['sellerId'] ?? '').toString().trim();

    return sid == id || bid == id || storeId == id || sellerId == id;
  }

  /// ✅ Best: business profile posts endpoint (if exists)
  Future<List<Map<String, dynamic>>?> _fetchBusinessPostsIfPossible({
    required int page,
    required int limit,
  }) async {
    if (_postsTriedBusinessEndpoint && !_postsUseBusinessEndpoint) return null;

    _postsTriedBusinessEndpoint = true;

    // ✅ Try multiple likely endpoints (no crash if backend doesn't have them)
    final candidates = <Future<List<Map<String, dynamic>>>>[
      // common patterns:
      FeedAPI.fetchByHashtag("business_$businessId", page: page, limit: limit), // harmless fallback
    ];

    // ✅ OPTIONAL (strong): if you add an endpoint later, just plug here:
    // Example:
    // candidates.insert(0, FeedAPI.fetchBusinessPosts(businessId, page: page, limit: limit));

    for (final f in candidates) {
      try {
        final list = await f;
        // If server actually returns business posts, they should match.
        // We'll accept only if at least 1 item matches business to avoid wrong hashtag fallback.
        if (list.isNotEmpty) {
          final anyMatch = list.any(_matchBusiness);
          if (anyMatch) return list;
        }
      } catch (_) {}
    }

    return null;
  }

  /// ✅ Fallback mode: global feed page -> filter by businessId
  Future<List<Map<String, dynamic>>> _fetchFromGlobalFeedAndFilter({
    required int page,
    required int limit,
  }) async {
    final feed = await FeedAPI.fetchFeed(page: page, limit: limit);

    final filtered = feed.where((p) {
      if (p is! Map<String, dynamic>) return false;
      return _matchBusiness(p);
    }).map((e) => Map<String, dynamic>.from(e)).toList();

    // ✅ apply blocked filter
    return BlockHelper.filterBlockedUsers(filtered);
  }

  // -------------------- getters --------------------

  List<Map<String, dynamic>> get products => productsPager.items;
  List<Map<String, dynamic>> get services => servicesPager.items;
  List<Map<String, dynamic>> get posts => postsPager.items;
  List<Map<String, dynamic>> get friends => friendsPager.items;

  bool get hasValidBusinessId {
    final s = businessId.trim();
    if (s.isEmpty) return false;
    final low = s.toLowerCase();
    return low != 'null' && low != 'undefined' && low != '0';
  }

  Future<void> loadAll({bool forceRefresh = false}) async {
    final int seq = ++_seq;

    if (!hasValidBusinessId) {
      errorHeader = 'Invalid business id';
      business = <String, dynamic>{};
      loadingHeader = false;
      notifyListeners();
      return;
    }

    final cacheKey = 'bp:$businessId';

    if (!forceRefresh) {
      final cached = MemoryCache.get<Map<String, Object>>(cacheKey);
      if (cached != null) {
        business = Map<String, dynamic>.from(cached['business'] as Map);
        isOwner = (cached['isOwner'] as bool?) ?? false;

        final p = cached['products'] as List?;
        final s = cached['services'] as List?;
        final po = cached['posts'] as List?;
        final f = cached['friends'] as List?;

        if (p != null) {
          productsPager.items
            ..clear()
            ..addAll(p.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
        }
        if (s != null) {
          servicesPager.items
            ..clear()
            ..addAll(s.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
        }
        if (po != null) {
          postsPager.items
            ..clear()
            ..addAll(po.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
        }
        if (f != null) {
          friendsPager.items
            ..clear()
            ..addAll(f.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
        }

        notifyListeners();
      }
    }

    loadingHeader = true;
    errorHeader = '';
    notifyListeners();

    try {
      final res = await BusinessAPI.fetchBusiness(businessId);
      if (seq != _seq) return;

      business = (res['business'] is Map)
          ? Map<String, dynamic>.from(res['business'])
          : Map<String, dynamic>.from(res);

      _normalizeBusinessMedia();

      final backendOwner =
          res['isOwner'] ?? res['is_owner'] ?? business['isOwner'] ?? business['is_owner'];

      if (backendOwner is bool) {
        isOwner = backendOwner;
      } else {
        await _computeOwnerFallback();
      }

      await Future.wait([
        productsPager.loadFirst(),
        servicesPager.loadFirst(),
        postsPager.loadFirst(),
        friendsPager.loadFirst(),
      ]);

      MemoryCache.set<Map<String, Object>>(cacheKey, {
        'business': business,
        'isOwner': isOwner,
        'products': List<Map<String, dynamic>>.from(productsPager.items),
        'services': List<Map<String, dynamic>>.from(servicesPager.items),
        'posts': List<Map<String, dynamic>>.from(postsPager.items),
        'friends': List<Map<String, dynamic>>.from(friendsPager.items),
      });
    } catch (e) {
      if (seq != _seq) return;
      errorHeader = e.toString();
    } finally {
      if (seq == _seq) {
        loadingHeader = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() => loadAll(forceRefresh: true);

  void updateLocalBusiness(Map<String, dynamic> updated) {
    if (updated.isEmpty) return;
    business = Map<String, dynamic>.from(updated);
    _normalizeBusinessMedia();
    notifyListeners();
  }

  void _normalizeBusinessMedia() {
    if (business.isEmpty) return;

    final logoRaw = business['logo'] ??
        business['logo_url'] ??
        business['shop_logo'] ??
        business['profile_pic'] ??
        business['profile_image'] ??
        business['image'] ??
        business['photo'];

    final coverRaw = business['cover'] ??
        business['cover_url'] ??
        business['banner'] ??
        business['cover_photo'] ??
        business['cover_image'] ??
        business['cover_pic'] ??
        business['background'];

    final logo = BusinessAPI.toPublicUrl((logoRaw ?? '').toString());
    final cover = BusinessAPI.toPublicUrl((coverRaw ?? '').toString());

    if (logo.isNotEmpty) {
      business['logo'] = logo;
      business['logo_url'] = logo;
      business['profile_pic'] = logo;
    }
    if (cover.isNotEmpty) {
      business['cover'] = cover;
      business['cover_url'] = cover;
    }
  }

  int _asInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim()) ?? fallback;
  }

  Future<void> _computeOwnerFallback() async {
    try {
      final ownerUserId =
      _asInt(business['user_id'] ?? business['userId'] ?? business['owner_id']);
      if (ownerUserId <= 0) {
        isOwner = false;
        return;
      }
      await BusinessAPI.cacheMe();
      final me = await BusinessAPI.fetchMe();
      final myUserId = _asInt(me['id'] ?? me['_id'] ?? me['user_id']);
      isOwner = myUserId > 0 && myUserId == ownerUserId;
    } catch (_) {
      isOwner = false;
    }
  }

  // ------------------------------------------------------------
  // Optimistic / cache updates (avoid full refresh after add/edit)
  // ------------------------------------------------------------
  int _itemId(dynamic m) {
    if (m is Map) {
      final v = m['id'] ?? m['_id'] ?? m['product_id'] ?? m['service_id'];
      if (v is int) return v;
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }
    return 0;
  }

  void upsertProduct(Map<String, dynamic> product) {
    if (product.isEmpty) return;
    final id = _itemId(product);
    if (id <= 0) return;
    final list = productsPager.items;
    final idx = list.indexWhere((e) => _itemId(e) == id);
    if (idx >= 0) {
      list[idx] = product;
    } else {
      list.insert(0, product);
    }
    notifyListeners();
  }

  void removeProduct(int id) {
    if (id <= 0) return;
    productsPager.items.removeWhere((e) => _itemId(e) == id);
    notifyListeners();
  }

  void upsertService(Map<String, dynamic> service) {
    if (service.isEmpty) return;
    final id = _itemId(service);
    if (id <= 0) return;
    final list = servicesPager.items;
    final idx = list.indexWhere((e) => _itemId(e) == id);
    if (idx >= 0) {
      list[idx] = service;
    } else {
      list.insert(0, service);
    }
    notifyListeners();
  }

  void removeService(int id) {
    if (id <= 0) return;
    servicesPager.items.removeWhere((e) => _itemId(e) == id);
    notifyListeners();
  }

  // ------------------------------------------------------------
  // Delete helpers (for tabs) - uses backend endpoints
  // ------------------------------------------------------------
  Future<bool> deleteProduct(String productId) async {
    final pid = productId.trim();
    if (pid.isEmpty) return false;

    final ok = await BusinessAPI.deleteProduct(pid);
    if (ok) {
      final id = int.tryParse(pid) ?? _itemId({'id': pid});
      if (id > 0) removeProduct(id);
    }
    return ok;
  }

  Future<bool> deleteService(String serviceId) async {
    final sid = serviceId.trim();
    if (sid.isEmpty) return false;

    final res = await ServicesAPI.deleteService(sid);
    final ok = res['success'] == true;
    if (ok) {
      final id = int.tryParse(sid) ?? _itemId({'id': sid});
      if (id > 0) removeService(id);
    }
    return ok;
  }

  // Legacy compatibility for existing UI
  bool get loading => loadingHeader;
  String get error => errorHeader;

  Future<void> loadBusiness() => loadAll();
}
