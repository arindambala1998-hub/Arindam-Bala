// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'pages/cart_page.dart';
import 'pages/product_offers_page.dart';

// 🛒 CONTROLLERS
import 'pages/business_profile/controllers/product_controller.dart';
import 'pages/business_profile/controllers/service_controller.dart';
import 'pages/business_profile/controllers/cart_controller.dart';

// 📱 CORE PAGES
import 'pages/feed_page.dart';
import 'pages/shop_page.dart';
import 'pages/notifications/notification_page.dart';
import 'pages/search_page.dart';
import 'pages/splash_screen.dart';
import 'pages/settings_page.dart';
import 'pages/conversations_list_page.dart';
import 'pages/friend_requests_page.dart';

// 👤 PROFILE & BUSINESS
import 'pages/profile/profile_page.dart';
import 'pages/business_profile/business_profile_page.dart';
import 'pages/business_profile/payment_page.dart';

// 🔐 AUTH
import 'login_page.dart';
import 'signup_step1_auth.dart';
import 'signup_email_page.dart';
import 'signup_otp_page.dart';

// 🎨 UI
import 'widgets/troonky_logo.dart';

// ✅ Reels/Home page
import 'pages/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ BIG FIX: image cache limit (prevents RAM spike + GC kill)
  PaintingBinding.instance.imageCache.maximumSize = 150; // count
  PaintingBinding.instance.imageCache.maximumSizeBytes = 60 << 20; // 60MB

  runApp(const RootApp());
}

// =============================================================
// ROOT APP
// =============================================================
class RootApp extends StatelessWidget {
  const RootApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProductController()),
        ChangeNotifierProvider(create: (_) => ServiceController()),
        ChangeNotifierProvider(create: (_) => CartController()),
      ],
      child: MaterialApp(
        title: 'Troonky',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          primarySwatch: Colors.deepPurple,
          scaffoldBackgroundColor: Colors.white,
          textTheme: GoogleFonts.poppinsTextTheme(),
        ),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en'),
          Locale('bn'),
        ],
        home: const SplashScreen(),

        // ✅ Robust route parsing + businessId missing হলে crash/blank না হয়ে gate handle করবে
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case '/signup-otp':
              final email = settings.arguments as String;
              return MaterialPageRoute(
                builder: (_) => SignupOtpPage(email: email),
              );

            case '/payment':
              final rawArgs = settings.arguments;
              final args = (rawArgs is Map) ? rawArgs : <dynamic, dynamic>{};

              final totalAny = args['total'] ?? args['totalAmount'] ?? 0;
              final total = (totalAny is num)
                  ? totalAny.toDouble()
                  : double.tryParse(totalAny.toString()) ?? 0.0;

              final orderAny = args['order'] ?? args['orderData'] ?? {};
              final order = (orderAny is Map)
                  ? Map<String, dynamic>.from(orderAny)
                  : <String, dynamic>{};

              final token = (args['token'] ?? args['authToken'])?.toString();

              return MaterialPageRoute(
                builder: (_) => PaymentPage(
                  totalAmount: total,
                  orderData: order,
                  authToken: token,
                ),
              );

            case '/profile':
              final rawArgs = settings.arguments;
              final args = (rawArgs is Map) ? rawArgs : <dynamic, dynamic>{};

              final userId = (args['userId'] ?? args['id'] ?? args['uid'] ?? 'me')
                  .toString()
                  .trim();

              return MaterialPageRoute(
                builder: (_) => ProfilePage(userId: userId.isEmpty ? 'me' : userId),
              );

            case '/business_profile':
              final rawArgs = settings.arguments;
              final args = (rawArgs is Map) ? rawArgs : <dynamic, dynamic>{};

              final businessId = (args['businessId'] ??
                  args['business_id'] ??
                  args['shopId'] ??
                  args['shop_id'] ??
                  args['storeId'] ??
                  args['store_id'] ??
                  args['id'] ??
                  '')
                  .toString()
                  .trim();

              final isOwner = (args['isOwner'] == true);

              // ✅ Gate: businessId empty হলেও SharedPreferences থেকে তুলে try করবে
              return MaterialPageRoute(
                builder: (_) => BusinessProfileGate(
                  initialBusinessId: businessId,
                  isOwner: isOwner,
                ),
              );
          }
          return null;
        },

        onUnknownRoute: (_) => MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text("Route not found")),
          ),
        ),

        routes: {
          '/login': (_) => const LoginPage(),
          '/signup': (_) => const SignupStep1Auth(),
          '/signup-email': (_) => const SignupEmailPage(),
          '/main_app': (_) => const TroonkyMain(),

          // ✅ UPDATED: new notifications page
          '/notifications': (_) => const NotificationsPage(),

          '/messages': (_) => const ConversationsListPage(),
          '/search': (_) => SearchPage(),
          '/settings': (_) => const SettingsPage(),
          '/friend_requests': (_) => const FriendRequestsPage(),
        },
      ),
    );
  }
}

// =============================================================
// ✅ BUSINESS PROFILE GATE
// - route args এ businessId না এলে prefs থেকে read করে resolve করবে
// - "Invalid business id" blank screen এ যাওয়ার আগেই handle করবে
// =============================================================
class BusinessProfileGate extends StatefulWidget {
  final String initialBusinessId;
  final bool isOwner;

  const BusinessProfileGate({
    super.key,
    required this.initialBusinessId,
    required this.isOwner,
  });

  @override
  State<BusinessProfileGate> createState() => _BusinessProfileGateState();
}

class _BusinessProfileGateState extends State<BusinessProfileGate> {
  late Future<String?> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolveBusinessId();
  }

  String _norm(Object? v) => (v ?? "").toString().trim().toLowerCase();

  bool _isValidId(String? v) {
    final s = _norm(v);
    return s.isNotEmpty &&
        s != "0" &&
        s != "null" &&
        s != "undefined" &&
        s != "nan";
  }

  String? _firstValid(List<String?> candidates) {
    for (final c in candidates) {
      if (_isValidId(c)) return c!.trim();
    }
    return null;
  }

  String? _getStringSafe(SharedPreferences prefs, String key) {
    final v = prefs.get(key);
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }

  Future<String?> _resolveBusinessId() async {
    // 1) args এ valid businessId থাকলে সেটাই
    if (_isValidId(widget.initialBusinessId)) return widget.initialBusinessId.trim();

    // 2) prefs fallback
    try {
      final prefs = await SharedPreferences.getInstance();
      final resolved = _firstValid([
        _getStringSafe(prefs, "businessId"),
        _getStringSafe(prefs, "business_id"),
        _getStringSafe(prefs, "shopId"),
        _getStringSafe(prefs, "shop_id"),
        _getStringSafe(prefs, "storeId"),
        _getStringSafe(prefs, "store_id"),
      ]);

      // ignore: avoid_print
      print("🟣 BUSINESS GATE => argsId='${widget.initialBusinessId}' resolved='$resolved'");
      return resolved;
    } catch (e) {
      // ignore: avoid_print
      print("❌ BUSINESS GATE PREFS ERROR => $e");
      return null;
    }
  }

  Future<void> _reload() async {
    setState(() {
      _future = _resolveBusinessId();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _future,
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final businessId = snap.data;

        if (_isValidId(businessId)) {
          return BusinessProfilePage(
            businessId: businessId!.trim(),
            isOwner: widget.isOwner,
          );
        }

        // ✅ graceful fallback UI
        return Scaffold(
          appBar: AppBar(title: const Text("Business Profile")),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.store_mall_directory_outlined, size: 44),
                  const SizedBox(height: 10),
                  const Text(
                    "Business profile id missing.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Please login again or retry.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: _reload,
                        child: const Text("Retry"),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () =>
                            Navigator.pushNamedAndRemoveUntil(context, "/login", (r) => false),
                        child: const Text("Go to Login"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// =============================================================
// MAIN APP WITH BOTTOM NAV (5 tabs)
// 1) Feed  2) Offers  3) Shops  4) Reels(Home icon label)  5) Profile
// =============================================================
class TroonkyMain extends StatefulWidget {
  const TroonkyMain({super.key});

  @override
  State<TroonkyMain> createState() => _TroonkyMainState();
}

class _TroonkyMainState extends State<TroonkyMain> {
  int _currentIndex = 0; // ✅ Feed first

  // ═══════════════════════════════════════════════════════════════
  // ✅ LAZY LOADING FIX (CRASH FIX)
  // ═══════════════════════════════════════════════════════════════
  // আগে সব 5টা পেজ একসাথে IndexedStack এ build হচ্ছিল:
  // - FeedPage (API + images)
  // - ProductOffersPage (API)
  // - ShopPage (API)
  // - HomePageShortVideo (BetterPlayer + HLS video controllers) 🔴 HEAVY!
  // - ProfilePage (API)
  //
  // সমস্যা: IndexedStack সব children কে memory তে রাখে।
  // HomePageShortVideo এর video controllers + buffers সব একসাথে init
  // হচ্ছিল → OOM (Out of Memory) / ANR crash হচ্ছিল।
  //
  // Fix: Lazy loading - শুধু visited tabs build করো।
  // প্রথমে শুধু Feed load হবে। Reels tab এ tap করলে তখন video init হবে।
  // ═══════════════════════════════════════════════════════════════
  final Set<int> _loadedTabs = {0}; // শুধু Feed দিয়ে শুরু

  void _onTabChange(int index) {
    setState(() {
      _currentIndex = index;
      _loadedTabs.add(index); // Mark tab as visited for lazy loading
    });
  }

  // ✅ Build page only if it has been visited (lazy load)
  // Unvisited tabs return empty placeholder to save memory
  Widget _buildPage(int index, Widget page) {
    if (_loadedTabs.contains(index)) {
      return page;
    }
    // Return lightweight placeholder for unvisited tabs
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: TroonkyLogo(size: 34, showText: true),
        actions: [
          // 🔍 SEARCH
          IconButton(
            icon: const Icon(Icons.search, color: Colors.deepPurple),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => SearchPage()),
              );
            },
          ),

          // 🛒 CART
          Consumer<CartController>(
            builder: (_, cart, __) => Badge(
              label: Text("${cart.cart.length}"),
              isLabelVisible: cart.cart.isNotEmpty,
              child: IconButton(
                icon: const Icon(Icons.shopping_cart_outlined, color: Colors.deepPurple),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CartPage()),
                  );
                },
              ),
            ),
          ),

          const _MainMenuButton(),
        ],
      ),
      // ✅ LAZY LOADED IndexedStack - prevents OOM/ANR crash
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildPage(0, const FeedPage()),              // 1) Feed - loads immediately
          _buildPage(1, const ProductOffersPage()),     // 2) Offers - loads on tap
          _buildPage(2, const ShopPage()),              // 3) Shops - loads on tap
          _buildPage(3, const HomePageShortVideo()),    // 4) Reels - loads on tap (heavy!)
          _buildPage(4, const DynamicProfileWrapper()), // 5) Profile - loads on tap
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: _onTabChange,
        selectedItemColor: Colors.deepPurple,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_rounded),
            label: "Feed",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_offer_outlined),
            label: "Offers",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.store),
            label: "Shops",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.play_circle_fill_rounded),
            label: "Reels",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: "Profile",
          ),
        ],
      ),
    );
  }
}

// =============================================================
// TOP RIGHT MENU
// =============================================================
class _MainMenuButton extends StatelessWidget {
  const _MainMenuButton();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.deepPurple),
      onSelected: (route) => Navigator.pushNamed(context, route),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: '/notifications',
          child: ListTile(
            leading: Icon(Icons.notifications),
            title: Text("Notifications"),
          ),
        ),
        PopupMenuItem(
          value: '/messages',
          child: ListTile(
            leading: Icon(Icons.message),
            title: Text("Messages"),
          ),
        ),
        PopupMenuItem(
          value: '/friend_requests',
          child: ListTile(
            leading: Icon(Icons.group_add),
            title: Text("Friend Requests"),
          ),
        ),
        PopupMenuItem(
          value: '/settings',
          child: ListTile(
            leading: Icon(Icons.settings),
            title: Text("Settings"),
          ),
        ),
      ],
    );
  }
}

// =============================================================
// PROFILE SWITCHER (USER / BUSINESS)
// =============================================================
class DynamicProfileWrapper extends StatefulWidget {
  const DynamicProfileWrapper({super.key});

  @override
  State<DynamicProfileWrapper> createState() => _DynamicProfileWrapperState();
}

class _DynamicProfileWrapperState extends State<DynamicProfileWrapper> {
  late Future<Map<String, String?>> _future;

  @override
  void initState() {
    super.initState();
    _future = _getUser();
  }

  String _norm(Object? v) => (v ?? "").toString().trim().toLowerCase();

  bool _isValidId(String? v) {
    final s = _norm(v);
    return s.isNotEmpty &&
        s != "0" &&
        s != "null" &&
        s != "undefined" &&
        s != "nan";
  }

  String? _firstValid(List<String?> candidates) {
    for (final c in candidates) {
      if (_isValidId(c)) return c!.trim();
    }
    return null;
  }

  bool _isBusinessType(String? userType) {
    final t = _norm(userType);
    return t == "business" ||
        t == "shop" ||
        t == "seller" ||
        t == "vendor" ||
        t == "service";
  }

  String? _getStringSafe(SharedPreferences prefs, String key) {
    final v = prefs.get(key);
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }

  Future<Map<String, String?>> _getUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final userId = _getStringSafe(prefs, "userId");
      final userType = _getStringSafe(prefs, "userType");

      final businessId = _firstValid([
        _getStringSafe(prefs, "businessId"),
        _getStringSafe(prefs, "shopId"),
        _getStringSafe(prefs, "shop_id"),
        _getStringSafe(prefs, "business_id"),
        _getStringSafe(prefs, "storeId"),
        _getStringSafe(prefs, "store_id"),
      ]);

      // ignore: avoid_print
      print("🟣 PROFILE PREFS => userId=$userId userType=$userType businessId=$businessId");

      return {
        "userId": userId,
        "userType": userType,
        "businessId": businessId,
      };
    } catch (e) {
      // ignore: avoid_print
      print("❌ PREFS READ ERROR => $e");
      return {
        "userId": null,
        "userType": null,
        "businessId": null,
      };
    }
  }

  Future<void> _reload() async {
    setState(() {
      _future = _getUser();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String?>>(
      future: _future,
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Profile load error"),
                const SizedBox(height: 10),
                ElevatedButton(onPressed: _reload, child: const Text("Retry")),
              ],
            ),
          );
        }

        final data = snap.data ?? {};
        final userId = data["userId"];
        final userType = data["userType"];
        final businessId = data["businessId"];

        if (!_isValidId(userId)) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Please login"),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () => Navigator.pushNamed(context, "/login"),
                  child: const Text("Go to Login"),
                ),
              ],
            ),
          );
        }

        if (_isValidId(businessId)) {
          return BusinessProfilePage(
            businessId: businessId!.trim(),
            isOwner: true,
          );
        }

        if (_isBusinessType(userType)) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Business profile id missing. Please login again."),
                const SizedBox(height: 10),
                ElevatedButton(onPressed: _reload, child: const Text("Reload")),
              ],
            ),
          );
        }

        return const ProfilePage(userId: "me");
      },
    );
  }
}