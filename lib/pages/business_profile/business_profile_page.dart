import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Controller
import 'controllers/business_profile_controller.dart';

// Widgets
import 'widgets/bp_tabbar.dart';

// Tabs
import 'tabs/bp_products_tab.dart';
import 'tabs/bp_services_tab.dart';
import 'tabs/bp_posts_tab.dart';
import 'tabs/bp_about_tab.dart';
import 'tabs/bp_friends_tab.dart';

// Pages (owner actions)
import 'edit_business_page.dart';
import 'business_dashboard_page.dart';

// ✅ for cover/logo normalize
import '../../services/business_api.dart';

class BusinessProfilePage extends StatefulWidget {
  final String businessId;
  final bool isOwner;
  final Map<String, dynamic>? shop;

  const BusinessProfilePage({
    super.key,
    required this.businessId,
    required this.isOwner,
    this.shop,
  });

  @override
  State<BusinessProfilePage> createState() => _BusinessProfilePageState();
}

class _BusinessProfilePageState extends State<BusinessProfilePage>
    with SingleTickerProviderStateMixin {
  static const Color _gStart = Color(0xFFFF00CC);
  static const Color _gEnd = Color(0xFF333399);
  static const Color _grayBG = Color(0xFFE6E6E6);

  static const int _tabCount = 5;

  late final BusinessProfileController ctrl;
  late final TabController _tabController;

  late final VoidCallback _ctrlListener;
  bool _startedLoad = false;

  // ✅ NEW: owner user pics fallback (when businesses.logo/cover = NULL)
  String _ownerProfilePic = "";
  String _ownerCoverPic = "";
  bool _ownerFetched = false;

  @override
  void initState() {
    super.initState();

    debugPrint("✅ BP OPENED id='${widget.businessId}' owner=${widget.isOwner}");

    _tabController = TabController(length: _tabCount, vsync: this);
    ctrl = BusinessProfileController(businessId: widget.businessId);

    _ctrlListener = () {
      if (!mounted) return;
      setState(() {});
    };
    ctrl.addListener(_ctrlListener);

    // ✅ parent passed shop map -> show instantly
    final passed = widget.shop;
    if (passed != null && passed.isNotEmpty) {
      try {
        ctrl.updateLocalBusiness(Map<String, dynamic>.from(passed));
        debugPrint("🟩 BP received shop map keys=${passed.keys.toList()}");
      } catch (_) {}
    }

    _kickoffLoad();
  }

  @override
  void dispose() {
    ctrl.removeListener(_ctrlListener);
    ctrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ---------------------------
  // Helpers
  // ---------------------------
  String _s(dynamic v) => (v ?? "").toString().trim();

  bool _isValidValue(String v) {
    final s = v.trim();
    final low = s.toLowerCase();
    return s.isNotEmpty &&
        low != "null" &&
        low != "undefined" &&
        low != "0" &&
        low != "nan";
  }

  bool _isValidId(String id) => _isValidValue(id);

  // ✅ first valid from list
  String _pickFirst(List<dynamic> candidates) {
    for (final c in candidates) {
      final s = _s(c);
      if (_isValidValue(s)) return s;
    }
    return "";
  }

  // ✅ safe toPublicUrl
  String _toPublicUrl(String raw) {
    final s = raw.trim();
    if (!_isValidValue(s)) return "";

    if (s.startsWith("http://") || s.startsWith("https://")) {
      return Uri.encodeFull(s);
    }
    if (s.startsWith("adminapi.troonky.in/")) {
      return Uri.encodeFull("https://$s");
    }
    if (s.startsWith("//")) {
      return Uri.encodeFull("https:$s");
    }
    return BusinessAPI.toPublicUrl(s);
  }

  // ✅ NEW: fetch owner user's profile_pic & cover_pic for fallback
  Future<void> _getOwnerUserPicsIfNeeded(Map<String, dynamic> data) async {
    if (_ownerFetched) return;

    // business API response এ user_id আছে (owner)
    final ownerId = _pickFirst([data["user_id"], data["owner_id"], data["ownerId"]]);
    if (!_isValidValue(ownerId)) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = (prefs.getString("token") ?? "").trim();
      if (token.isEmpty) return;

      final url = Uri.parse("https://adminapi.troonky.in/api/users/$ownerId");
      final res = await http.get(url, headers: {
        "Authorization": "Bearer $token",
        "Accept": "application/json",
      }).timeout(const Duration(seconds: 20));

      if (res.statusCode != 200) {
        _ownerFetched = true;
        return;
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(res.body);
      } catch (_) {
        decoded = {};
      }

      Map<String, dynamic> u = {};
      if (decoded is Map) {
        final any = decoded["user"] ?? decoded["data"] ?? decoded["result"] ?? decoded;
        if (any is Map) u = Map<String, dynamic>.from(any);
      }

      final p = _toPublicUrl(_s(u["profile_pic"] ?? u["avatar"]));
      final c = _toPublicUrl(_s(u["cover_pic"] ?? u["cover"]));

// ✅ তুমি চাও: cover_pic = shop logo
      _ownerProfilePic = c;   // logo fallback now uses cover_pic
      _ownerCoverPic = c;     // cover fallback (if needed) also cover_pic

      _ownerFetched = true;

      if (mounted) setState(() {});
      debugPrint("✅ owner pics fetched -> profile='$p' cover='$c' (logo uses cover_pic)");
    } catch (e) {
      _ownerFetched = true;
      debugPrint("❌ owner pics fetch error: $e");
    }
  }

  void _kickoffLoad() {
    if (_startedLoad) return;
    _startedLoad = true;

    if (_isValidId(widget.businessId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await ctrl.loadBusiness();

        // ✅ after business loaded, try fetch owner user pics
        if (mounted && ctrl.business.isNotEmpty) {
          await _getOwnerUserPicsIfNeeded(ctrl.business);
        }
      });
    } else {
      debugPrint("❌ BP invalid businessId='${widget.businessId}'");
    }
  }

  Future<void> _retry() async {
    if (!_isValidId(widget.businessId)) return;
    _ownerFetched = false; // ✅ allow refresh to refetch
    _ownerProfilePic = "";
    _ownerCoverPic = "";
    await ctrl.loadBusiness();

    if (mounted && ctrl.business.isNotEmpty) {
      await _getOwnerUserPicsIfNeeded(ctrl.business);
    }
  }

  PreferredSizeWidget _appBarBasic() {
    return AppBar(
      elevation: 0,
      centerTitle: true,
      foregroundColor: Colors.white,
      title: const Text(
        "Business Profile",
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      flexibleSpace: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [_gStart, _gEnd]),
        ),
      ),
    );
  }

  Widget _coverFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_gStart, _gEnd],
        ),
      ),
      child: const Center(
        child: Icon(Icons.image, color: Colors.white70, size: 44),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1) invalid id
    if (!_isValidId(widget.businessId)) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: _appBarBasic(),
        body: Center(
          child: Text(
            "Invalid business id",
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    // 2) loading (only if nothing cached)
    if (ctrl.loading && ctrl.business.isEmpty) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: _gEnd, strokeWidth: 3),
        ),
      );
    }

    // 3) empty state
    if (ctrl.business.isEmpty) {
      final err = (ctrl.error).trim();
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: _appBarBasic(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.storefront_outlined,
                  size: 60,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 10),
                Text(
                  "Failed to load business profile",
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (err.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    err,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _retry,
                  child: Ink(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(colors: [_gStart, _gEnd]),
                    ),
                    child: const Text(
                      "Retry",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
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

    // 4) main UI
    final data = ctrl.business;

    // ✅ super stable key mapping
    final coverRaw = _pickFirst([
      data["cover_url"],
      data["coverUrl"],
      data["cover"],
      data["banner"],
      data["cover_pic"],
      data["coverPic"],
      data["cover_image"],
      data["cover_photo"],
      data["coverImage"],
      data["bg"],
      data["background"],
      data["background_url"],
      data["backgroundUrl"],
    ]);

    final logoRaw = _pickFirst([
      // ✅ highest priority: use cover_pic as shop logo
      data["shop_logo"],
      data["shopLogo"],
      data["cover_pic"],
      data["coverPic"],
      data["user_cover_pic"],
      data["userCoverPic"],

      // existing fallbacks
      data["logo_url"],
      data["logoUrl"],
      data["logo"],
      data["profile"],
      data["profile_image"],
      data["profileImage"],
      data["image"],
      data["photo"],
      data["avatar"],
    ]);

    // ✅ normalize
    String cover = _toPublicUrl(coverRaw);
    String logo = _toPublicUrl(logoRaw);

    // ✅ FINAL: fallback to owner user pics when business cover/logo missing
    if (!_isValidValue(cover)) cover = _ownerCoverPic;
    if (!_isValidValue(logo)) logo = _ownerProfilePic;

    // ✅ if still empty -> try once to fetch owner pics
    if ((!_isValidValue(cover) || !_isValidValue(logo)) && !_ownerFetched) {
      // fire and forget (safe)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _getOwnerUserPicsIfNeeded(data);
      });
    }

    final name = _pickFirst([
      data["shop_name"],
      data["shopName"],
      data["business_name"],
      data["businessName"],
      data["name"], // fallback only
      "Business",
    ]);
    final tagline = _pickFirst([
      data["tagline"],
      data["bio"],
      data["about"],
      data["description"],
    ]);

    final isVerified = data["is_verified"] == true || _s(data["verified"]) == "1";

    // ✅ owner flag (parent OR controller)
    final bool ownerNow = widget.isOwner || ctrl.isOwner;

    debugPrint("🧾 BP id=${widget.businessId} cover='$cover' logo='$logo' owner=$ownerNow");

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: RefreshIndicator(
        color: _gEnd,
        onRefresh: _retry,
        child: NestedScrollView(
          physics: const BouncingScrollPhysics(),
          headerSliverBuilder: (_, __) => [
            SliverToBoxAdapter(
              child: Stack(
                children: [
                  SizedBox(
                    height: 275,
                    width: double.infinity,
                    child: cover.isNotEmpty
                        ? Image.network(
                      cover,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(color: _grayBG),
                            const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _gEnd,
                              ),
                            ),
                          ],
                        );
                      },
                      errorBuilder: (_, e, __) {
                        debugPrint("❌ COVER LOAD ERROR => $e URL=$cover raw=$coverRaw");
                        return _coverFallback();
                      },
                    )
                        : _coverFallback(),
                  ),

                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withAlpha(26),
                            Colors.black.withAlpha(72),
                          ],
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: _BusinessHeaderOverlay(
                      logoUrl: logo,
                      name: name,
                      tagline: tagline,
                      isVerified: isVerified,
                      isOwner: ownerNow,
                      onEdit: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EditBusinessPage(business: ctrl.business),
                          ),
                        );
                        await ctrl.loadBusiness();
                        if (mounted) await _getOwnerUserPicsIfNeeded(ctrl.business);
                      },
                      onDashboard: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BusinessDashboardPage(business: ctrl.business),
                          ),
                        );
                      },
                    ),
                  ),

                  // ✅ BACK ARROW (TOP LEFT)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: SafeArea(
                      child: Material(
                        color: Colors.black.withAlpha(90),
                        shape: const CircleBorder(),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.of(context).maybePop(),
                          tooltip: "Back",
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SliverToBoxAdapter(
              child: BPTabBar(
                controller: _tabController,
                labels: const ["Products", "Services", "Posts", "About", "Friends"],
              ),
            ),
            if (ctrl.loading)
              const SliverToBoxAdapter(
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              BPProductsTab(ctrl: ctrl, isOwnerOverride: ownerNow),
              BPServicesTab(ctrl: ctrl, isOwnerOverride: ownerNow),
              BPPostsTab(ctrl: ctrl),
              BPAboutTab(ctrl: ctrl),
              BPFriendsTab(ctrl: ctrl),
            ],
          ),
        ),
      ),
    );
  }
}
class _BusinessHeaderOverlay extends StatelessWidget {
  final String logoUrl;
  final String name;
  final String tagline;
  final bool isVerified;
  final bool isOwner;
  final VoidCallback onEdit;
  final VoidCallback onDashboard;

  const _BusinessHeaderOverlay({
    required this.logoUrl,
    required this.name,
    required this.tagline,
    required this.isVerified,
    required this.isOwner,
    required this.onEdit,
    required this.onDashboard,
  });

  static const Color _gStart = Color(0xFFFF00CC);
  static const Color _gEnd = Color(0xFF333399);

  @override
  Widget build(BuildContext context) {
    final hasLogo = logoUrl.trim().isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [_gStart, _gEnd]),
                boxShadow: [
                  BoxShadow(
                    color: _gStart.withAlpha(90),
                    blurRadius: 18,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 55,
                backgroundColor: Colors.white,
                child: ClipOval(
                  child: SizedBox(
                    width: 104,
                    height: 104,
                    child: hasLogo
                        ? Image.network(
                      logoUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _gEnd,
                          ),
                        );
                      },
                      errorBuilder: (_, e, __) {
                        debugPrint("❌ LOGO LOAD ERROR => $e URL=$logoUrl");
                        return const Center(
                          child: Icon(Icons.storefront, size: 50, color: Colors.grey),
                        );
                      },
                    )
                        : const Center(
                      child: Icon(Icons.storefront, size: 50, color: Colors.grey),
                    ),
                  ),
                ),
              ),
            ),
            if (isOwner)
              Positioned(
                right: -2,
                bottom: -2,
                child: InkWell(
                  borderRadius: BorderRadius.circular(50),
                  onTap: onEdit,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _gEnd,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(45),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        )
                      ],
                    ),
                    child: const Icon(Icons.edit, size: 14, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.black.withAlpha(115),
            border: Border.all(color: Colors.white.withAlpha(55), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(70),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              if (isVerified) ...[
                const SizedBox(width: 8),
                const Icon(Icons.verified, size: 18, color: Color(0xFF2A7DE1)),
              ],
            ],
          ),
        ),
        if (tagline.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            tagline,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withAlpha(235),
              fontWeight: FontWeight.w500,
              shadows: const [
                Shadow(
                  color: Colors.black45,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (isOwner)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _gradientBtn("Edit Business", Icons.edit, onEdit),
              const SizedBox(width: 10),
              _outlineBtn("Dashboard", Icons.dashboard_outlined, onDashboard),
            ],
          ),
      ],
    );
  }

  Widget _gradientBtn(String label, IconData icon, VoidCallback onTap) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(colors: [_gStart, _gEnd]),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _outlineBtn(String label, IconData icon, VoidCallback onTap) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gEnd, width: 1.3),
        color: Colors.white,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: _gEnd, size: 18),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: _gEnd,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
