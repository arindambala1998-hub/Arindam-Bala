import 'package:flutter/material.dart';
import 'package:troonky_link/services/friends_api.dart';
import 'package:troonky_link/pages/profile/profile_page.dart'; // ✅ ADD THIS

// =========================
// ✅ Troonky Official Theme
// =========================
const Color troonkyColor = Color(0xFF333399); // brand base
const Color troonkyGradA = Color(0xFF7C2AE8); // purple
const Color troonkyGradB = Color(0xFFFF2DAA); // pink

LinearGradient troonkyGradient({
  Alignment begin = Alignment.centerLeft,
  Alignment end = Alignment.centerRight,
  double opacity = 1.0,
}) {
  return LinearGradient(
    begin: begin,
    end: end,
    colors: [
      troonkyGradA.withOpacity(opacity),
      troonkyGradB.withOpacity(opacity),
    ],
  );
}

// ------------ Model ------------
class FriendUser {
  final String id;        // request_id for pending/sent, user_id for suggestions
  final String userId;    // actual target user id
  final String name;
  final String? avatar;
  final int mutualCount;
  final String? location;

  FriendUser({
    required this.id,
    required this.userId,
    required this.name,
    this.avatar,
    this.mutualCount = 0,
    this.location,
  });

  static FriendUser fromMap(Map<String, dynamic> m) {
    final id = (m['id'] ?? '').toString();

    String uId = id;
    if (m.containsKey('sender_id')) uId = m['sender_id'].toString();
    else if (m.containsKey('receiver_id')) uId = m['receiver_id'].toString();

    // ✅ some APIs send user_id directly
    final directUid = (m['user_id'] ?? m['uid'] ?? m['userId'])?.toString();
    if (directUid != null && directUid.trim().isNotEmpty) {
      uId = directUid.trim();
    }

    final name = (m['name'] ?? m['username'] ?? 'Unknown').toString();
    String? avatar = m['profile_pic']?.toString();

    if (avatar != null && avatar.isNotEmpty && !avatar.startsWith('http')) {
      avatar = "https://adminapi.troonky.in/$avatar";
    }

    return FriendUser(
      id: id,
      userId: uId,
      name: name,
      avatar: avatar,
      mutualCount: 0,
      location: null,
    );
  }
}

// ------------ Common UI: Paged List ------------
class _PagedList extends StatefulWidget {
  final Future<List<dynamic>> Function() loader;
  final Widget Function(FriendUser u, VoidCallback remove) itemBuilder;
  final String emptyMessage;

  const _PagedList({
    required this.loader,
    required this.itemBuilder,
    required this.emptyMessage,
  });

  @override
  State<_PagedList> createState() => _PagedListState();
}

class _PagedListState extends State<_PagedList> {
  List<FriendUser> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final rawList = await widget.loader();
      final mapped = rawList.map((e) => FriendUser.fromMap(e)).toList();
      if (mounted) setState(() => _items = mapped);
    } catch (e) {
      debugPrint("Error loading list: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _removeItem(String id) {
    setState(() {
      _items.removeWhere((element) => element.id == id || element.userId == id);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_items.isEmpty) {
      return Center(
        child: Text(
          widget.emptyMessage,
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final user = _items[i];
          return widget.itemBuilder(user, () => _removeItem(user.id));
        },
      ),
    );
  }
}

// ✅ common helper: open profile
void _openUserProfile(BuildContext context, FriendUser user) {
  final uid = user.userId.trim();
  if (uid.isEmpty || uid == "0" || uid.toLowerCase() == "null") return;

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ProfilePage(userId: uid),
    ),
  );
}

// ------------ Cards ------------

// 1) Incoming Request Card (Confirm / Delete)
class _RequestCard extends StatelessWidget {
  final FriendUser user;
  final VoidCallback onRemoved;

  const _RequestCard({required this.user, required this.onRemoved});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => _openUserProfile(context, user), // ✅ FIX
      leading: CircleAvatar(
        radius: 24,
        backgroundImage: user.avatar != null ? NetworkImage(user.avatar!) : null,
        child: user.avatar == null ? const Icon(Icons.person) : null,
      ),
      title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: const Text("Sent you a friend request"),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionButton(
            label: "Confirm",
            kind: _ActionKind.solidBrand,
            onTap: () async {
              try {
                await FriendsAPI.acceptRequest(user.id);
                onRemoved();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Request Accepted")),
                );
              } catch (_) {}
            },
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: "Delete",
            kind: _ActionKind.gray,
            onTap: () async {
              try {
                await FriendsAPI.rejectRequest(user.id);
                onRemoved();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Request Removed")),
                );
              } catch (_) {}
            },
          ),
        ],
      ),
    );
  }
}

// 2) Sent Request Card (Cancel)
class _SentCard extends StatelessWidget {
  final FriendUser user;
  final VoidCallback onRemoved;

  const _SentCard({required this.user, required this.onRemoved});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => _openUserProfile(context, user), // ✅ FIX
      leading: CircleAvatar(
        radius: 24,
        backgroundImage: user.avatar != null ? NetworkImage(user.avatar!) : null,
        child: user.avatar == null ? const Icon(Icons.person) : null,
      ),
      title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: const Text("Request Sent"),
      trailing: _ActionButton(
        label: "Cancel",
        kind: _ActionKind.gray,
        onTap: () async {
          try {
            await FriendsAPI.cancelRequest(user.userId);
            onRemoved();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Request Cancelled")),
            );
          } catch (_) {}
        },
      ),
    );
  }
}

// 3) Suggestion Card (Add Friend)
class _SuggestionCard extends StatelessWidget {
  final FriendUser user;
  final VoidCallback onRemoved;

  const _SuggestionCard({required this.user, required this.onRemoved});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => _openUserProfile(context, user), // ✅ FIX
      leading: CircleAvatar(
        radius: 24,
        backgroundImage: user.avatar != null ? NetworkImage(user.avatar!) : null,
        child: user.avatar == null ? const Icon(Icons.person) : null,
      ),
      title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: const Text("Suggested for you"),
      trailing: _ActionButton(
        label: "Add Friend",
        kind: _ActionKind.gradient70,
        onTap: () async {
          try {
            await FriendsAPI.sendRequest(user.id);
            onRemoved();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Request Sent")),
            );
          } catch (_) {}
        },
      ),
    );
  }
}

// ------------ Button Helper ------------
enum _ActionKind { solidBrand, gradient70, gray }

class _ActionButton extends StatelessWidget {
  final String label;
  final _ActionKind kind;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.kind,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(8);

    BoxDecoration deco;
    TextStyle style;

    if (kind == _ActionKind.gray) {
      deco = BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: radius,
      );
      style = const TextStyle(
        color: Colors.black,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      );
    } else if (kind == _ActionKind.gradient70) {
      deco = BoxDecoration(
        gradient: troonkyGradient(opacity: 0.70),
        borderRadius: radius,
        border: Border.all(color: troonkyColor.withOpacity(0.18)),
      );
      style = const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 13,
      );
    } else {
      deco = BoxDecoration(
        gradient: troonkyGradient(opacity: 1.0),
        borderRadius: radius,
      );
      style = const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 13,
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: deco,
        child: Text(label, style: style),
      ),
    );
  }
}

// ------------ Main Page ------------
class FriendRequestsPage extends StatefulWidget {
  const FriendRequestsPage({super.key});

  @override
  State<FriendRequestsPage> createState() => _FriendRequestsPageState();
}

class _FriendRequestsPageState extends State<FriendRequestsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 0);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Friends", style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: troonkyColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: troonkyColor,
          tabs: const [
            Tab(text: "Suggestions"),
            Tab(text: "Sent"),
            Tab(text: "Requests"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _PagedList(
            loader: FriendsAPI.getSuggestions,
            emptyMessage: "No suggestions found.",
            itemBuilder: (user, onRemove) =>
                _SuggestionCard(user: user, onRemoved: onRemove),
          ),
          _PagedList(
            loader: FriendsAPI.getSentRequests,
            emptyMessage: "No sent requests.",
            itemBuilder: (user, onRemove) =>
                _SentCard(user: user, onRemoved: onRemove),
          ),
          _PagedList(
            loader: FriendsAPI.getPendingRequests,
            emptyMessage: "No new friend requests.",
            itemBuilder: (user, onRemove) =>
                _RequestCard(user: user, onRemoved: onRemove),
          ),
        ],
      ),
    );
  }
}
