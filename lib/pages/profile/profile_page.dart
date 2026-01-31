import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/profile_api.dart';
import '../../services/friends_api.dart';

import '../messages_page.dart';

import 'profile_header.dart';
import 'profile_posts_tab.dart';
import 'profile_about_tab.dart';
import 'profile_friends_tab.dart';
import 'edit_profile_page.dart';

class ProfilePage extends StatefulWidget {
  final String userId; // "me" or actual id
  const ProfilePage({super.key, required this.userId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  Map<String, dynamic>? user;
  List<dynamic> posts = [];
  List<dynamic> friends = [];

  bool loading = true;
  bool isMyProfile = false;

  final Color gradientEnd = const Color(0xFF333399);
  final Color grayBG = const Color(0xFFE6E6E6);

  String? _token;
  String? _myUserId;

  String _friendStatus = "none"; // none | sent | received | friends
  String _friendRequestId = "";
  bool _friendBusy = false;

  static const String _apiRoot = "https://adminapi.troonky.in";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadProfileData();
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _loadProfileData();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _normId(Object? v) => (v ?? "").toString().trim();

  // ✅ Public URL builder (uploads/... -> https://adminapi.troonky.in/uploads/...)
  String _toPublicUrl(dynamic path) {
    final raw = (path ?? "").toString().trim();
    if (raw.isEmpty) return "";

    if (raw.startsWith("http://") || raw.startsWith("https://")) return raw;

    var p = raw.replaceAll("\\", "/");
    p = p.replaceFirst(RegExp(r'^/'), "");
    p = p.replaceFirst(RegExp(r'^(public/)+'), ""); // public/ থাকলে বাদ

    return "$_apiRoot/$p";
  }

  // ✅ Normalize user keys + ensure URLs are absolute
  Map<String, dynamic> _normalizeUser(Map<String, dynamic> u) {
    final profile = _toPublicUrl(
      u["profilePic"] ??
          u["profile_pic"] ??
          u["profile_picture"] ??
          u["avatar"] ??
          u["profile_pic_url"],
    );

    final cover = _toPublicUrl(
      u["coverPic"] ??
          u["cover_pic"] ??
          u["cover_picture"] ??
          u["cover_pic_url"],
    );

    // UI যেন যেকোনো key থেকেই consistent পায়
    if (profile.isNotEmpty) {
      u["profilePic"] = profile;
      u["profile_pic"] = profile;
    }
    if (cover.isNotEmpty) {
      u["coverPic"] = cover;
      u["cover_pic"] = cover;
    }

    return u;
  }

  Future<void> _loadProfileData() async {
    if (!mounted) return;

    setState(() {
      loading = true;
      user = null;
      posts = [];
      friends = [];
      isMyProfile = false;
      _friendStatus = "none";
      _friendRequestId = "";
      _friendBusy = false;
    });

    final prefs = await SharedPreferences.getInstance();

    // ✅ token multi-key fallback
    _token = (prefs.getString("token") ??
        prefs.getString("auth_token") ??
        prefs.getString("access_token") ??
        prefs.getString("jwt"))
        ?.trim();

    // ✅ userId fallback (string + int both)
    _myUserId = (prefs.getString("userId") ??
        prefs.getString("user_id") ??
        prefs.getString("id") ??
        prefs.getInt("user_id")?.toString() ??
        prefs.getInt("id")?.toString())
        ?.trim();

    if (_token == null || _token!.isEmpty) {
      if (!mounted) return;
      setState(() => loading = false);
      return;
    }

    isMyProfile = widget.userId == "me" ||
        (_myUserId != null &&
            _myUserId!.isNotEmpty &&
            widget.userId.trim() == _myUserId);

    Map<String, dynamic>? response;
    try {
      response = isMyProfile
          ? await ProfileAPI.getMyProfile(_token!)
          : await ProfileAPI.getProfileById(widget.userId, token: _token);
    } catch (_) {
      response = null;
    }

    if (!mounted) return;

    if (response == null || response["success"] != true) {
      setState(() => loading = false);
      return;
    }

    final loadedUser0 = Map<String, dynamic>.from(response["user"] ?? {});
    final loadedUser = _normalizeUser(loadedUser0);

    final loadedPosts = response["posts"] is List ? response["posts"] : [];
    final loadedFriends = response["friends"] is List ? response["friends"] : [];

    setState(() {
      user = loadedUser;
      posts = loadedPosts;
      friends = loadedFriends;
      loading = false;
    });

    if (!isMyProfile) {
      _loadFriendStatus();
    }
  }

  Future<void> _loadFriendStatus() async {
    if (!mounted || isMyProfile) return;

    final targetId = (user?["id"] ?? widget.userId).toString().trim();
    if (targetId.isEmpty) return;

    try {
      final st = await FriendsAPI.getFriendStatus(targetId);
      if (!mounted) return;

      setState(() {
        _friendStatus = (st["status"] ?? "none").toString();
        _friendRequestId = (st["requestId"] ?? "").toString();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _friendStatus = "none";
        _friendRequestId = "";
      });
    }
  }

  String get _friendButtonText {
    switch (_friendStatus) {
      case "friends":
        return "Friend";
      case "sent":
        return "Pending";
      case "received":
        return "Respond";
      default:
        return "Add Friend";
    }
  }

  IconData get _friendButtonIcon {
    switch (_friendStatus) {
      case "friends":
        return Icons.people;
      case "sent":
        return Icons.schedule;
      case "received":
        return Icons.mark_email_unread_outlined;
      default:
        return Icons.person_add;
    }
  }

  Future<void> _onFriendButtonTap() async {
    if (!mounted || isMyProfile || _friendBusy) return;

    final targetId = (user?["id"] ?? widget.userId).toString().trim();
    if (targetId.isEmpty) return;

    setState(() => _friendBusy = true);

    try {
      if (_friendStatus == "none") {
        await FriendsAPI.sendRequest(targetId);

        if (!mounted) return;
        setState(() => _friendStatus = "sent");

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Friend request sent ✅")),
        );

        await _loadFriendStatus();
      } else if (_friendStatus == "sent") {
        await FriendsAPI.cancelRequest(targetId);

        if (!mounted) return;
        setState(() {
          _friendStatus = "none";
          _friendRequestId = "";
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Request cancelled ✅")),
        );

        await _loadFriendStatus();
      } else if (_friendStatus == "received") {
        if (_friendRequestId.isEmpty) {
          await _loadFriendStatus();
        }
        if (!mounted) return;

        final action = await showDialog<String>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Friend Request"),
            content: const Text("Accept this friend request?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, "reject"),
                child: const Text("Reject"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, "accept"),
                child: const Text("Accept"),
              ),
            ],
          ),
        );

        if (!mounted) return;

        if (action == "accept") {
          if (_friendRequestId.isNotEmpty) {
            await FriendsAPI.acceptRequest(_friendRequestId);
          }

          if (!mounted) return;
          setState(() {
            _friendStatus = "friends";
            _friendRequestId = "";
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Friend added ✅")),
          );

          await _loadFriendStatus();
        } else if (action == "reject") {
          if (_friendRequestId.isNotEmpty) {
            await FriendsAPI.rejectRequest(_friendRequestId);
          }

          if (!mounted) return;
          setState(() {
            _friendStatus = "none";
            _friendRequestId = "";
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Request rejected ✅")),
          );

          await _loadFriendStatus();
        }
      }
    } catch (e) {
      if (!mounted) return;

      final msg = e.toString();
      if (msg.contains("Request already exists")) {
        setState(() => _friendStatus = "sent");
        await _loadFriendStatus();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Action failed ❌ $msg")),
      );
    } finally {
      if (mounted) setState(() => _friendBusy = false);
    }
  }

  Future<void> _openEditPage() async {
    if (!isMyProfile || user == null) return;

    final updated = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditProfilePage(user: user!)),
    );

    if (updated == true) {
      await _loadProfileData();
    }
  }

  void _message() {
    if (isMyProfile) return;

    final friendId = (user?["id"] ?? widget.userId).toString().trim();
    if (friendId.isEmpty) return;

    final friendName = (user?["name"] ?? "User").toString();

    // ✅ avatar normalize
    final friendAvatar = _toPublicUrl(
      user?["profile_pic"] ?? user?["profilePic"] ?? "",
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessagesPage(
          friendId: friendId,
          friendName: friendName,
          friendAvatarUrl: friendAvatar,
        ),
      ),
    );
  }

  void _openFriendProfile(String friendId) {
    final fid = friendId.trim();
    final currentId = (user?["id"] ?? widget.userId).toString().trim();
    if (fid.isEmpty || fid == "me" || fid == currentId) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProfilePage(userId: fid)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading || user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final name = (user!["name"] ?? "User").toString();

    // ✅ always use normalized absolute URLs
    final profilePic = _toPublicUrl(user!["profile_pic"] ?? user!["profilePic"]);
    final coverPic = _toPublicUrl(user!["cover_pic"] ?? user!["coverPic"]);

    final profileUserIdInt = int.tryParse(
      _normId(
        user!["id"] ??
            user!["user_id"] ??
            user!["uid"] ??
            (isMyProfile ? _myUserId : widget.userId),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        color: gradientEnd,
        onRefresh: _loadProfileData,
        child: NestedScrollView(
          physics: const BouncingScrollPhysics(),
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              expandedHeight: 280,
              pinned: true,
              elevation: 0,
              backgroundColor: Colors.white,
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  children: [
                    Positioned.fill(
                      child: (coverPic.isNotEmpty)
                          ? Image.network(coverPic, fit: BoxFit.cover)
                          : Container(color: grayBG),
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 20,
                      child: ProfileHeader(
                        name: name,
                        profilePic: profilePic,
                        coverPic: coverPic,
                        isMyProfile: isMyProfile,
                        friendButtonText: _friendButtonText,
                        friendButtonIcon: _friendButtonIcon,
                        friendButtonDisabled:
                        (_friendStatus == "friends") || _friendBusy,
                        onAddFriend: isMyProfile ? null : _onFriendButtonTap,
                        onMessage: isMyProfile ? null : _message,
                        onEditPhotoTap: isMyProfile ? _openEditPage : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Container(
                height: 55,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: gradientEnd,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: gradientEnd,
                  tabs: const [
                    Tab(text: "Posts"),
                    Tab(text: "About"),
                    Tab(text: "Friends"),
                  ],
                ),
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              ProfilePostsTab(
                posts: posts,
                profileUserId: profileUserIdInt,
                profileName: name,
                profilePic: profilePic,
              ),
              ProfileAboutTab(user: user!),
              ProfileFriendsTab(
                friends: friends,
                isMyProfile: isMyProfile,
                onSeeAll: () {},
                onFriendTap: _openFriendProfile,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
