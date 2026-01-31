import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:troonky_link/services/message_api.dart';
import 'package:troonky_link/services/feed_api.dart';
import 'package:troonky_link/services/chat_socket_service.dart';
import 'package:troonky_link/services/chat_socket_service.dart';
import 'package:troonky_link/services/chat_socket_service.dart';

// =========================
// ✅ Troonky Official Theme
// =========================
const Color troonkyColor = Color(0xFF333399);
const Color troonkyGradA = Color(0xFF7C2AE8);
const Color troonkyGradB = Color(0xFFFF2DAA);

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

enum _MsgStatus { none, sending, sent, delivered, seen, failed }

class MessagesPage extends StatefulWidget {
  final String friendId;
  final String friendName;
  final String friendAvatarUrl;

  const MessagesPage({
    super.key,
    required this.friendId,
    required this.friendName,
    this.friendAvatarUrl = '',
  });

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> with WidgetsBindingObserver {
  final List<Map<String, dynamic>> _messages = [];

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  String? _token;
  int _myUserId = 0;

  bool _loading = true;
  bool _sending = false;

  // real-time
  int _conversationId = 0;
  bool _socketReady = false;
  bool _isFriendOnline = false;
  bool _isFriendTyping = false;

  // pagination
  static const int _pageSize = 30;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _oldestServerMessageId = 0; // for before=<id>

  // typing debounce
  Timer? _typingTimer;
  bool _sentTypingTrue = false;

  // fallback polling (only if socket not connected)
  Timer? _fallbackTimer;

  // backend base
  static const String apiBase = 'https://adminapi.troonky.in/api';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _controller.addListener(_onTypingChanged);
    _initChat();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _typingTimer?.cancel();
    _fallbackTimer?.cancel();

    if (_conversationId > 0) {
      ChatSocketService.I.leaveConversation(_conversationId);
    }

    _controller.removeListener(_onTypingChanged);
    _controller.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((_token ?? '').isEmpty || _myUserId <= 0) return;

    if (state == AppLifecycleState.resumed) {
      ChatSocketService.I.connect(token: _token!, myUserId: _myUserId);
      _bindSocketOnce();
      if (_conversationId > 0) ChatSocketService.I.joinConversation(_conversationId);
      _refreshMessagesInitial(silent: true);
      _markSeenBestEffort();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // ✅ pause socket (battery + background)
      ChatSocketService.I.disconnect();
      _socketReady = false;
    }
  }

  // -----------------------------------------------------------------
  Future<void> _initChat() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token')?.trim();
    _myUserId = int.tryParse((prefs.getString('userId') ?? '').trim()) ?? 0;

    if ((_token ?? '').isEmpty || _myUserId <= 0) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      await _refreshOnline();

      // ✅ socket connect (foreground only)
      await ChatSocketService.I.connect(token: _token!, myUserId: _myUserId);
      _bindSocketOnce();

      await _refreshMessagesInitial(silent: false);
      await _markSeenBestEffort();

      // Fallback polling only when socket is not connected
      _fallbackTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        if (!mounted) return;
        if (ChatSocketService.I.isConnected) return;
        _refreshOnline();
        _refreshMessagesInitial(silent: true);
      });
    } catch (e) {
      debugPrint('Init Chat Error: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
      _scrollToBottom(animate: false);
    }
  }

  void _bindSocketOnce() {
    if (_socketReady) return;
    _socketReady = true;

    // new message
    ChatSocketService.I.onNewMessage.listen((payload) {
      if (!mounted) return;

      final convId = _toInt(payload['conversation_id'] ?? payload['conversationId']);
      if (convId <= 0 || (_conversationId > 0 && convId != _conversationId)) return;

      final m = payload['message'];
      if (m is! Map) return;
      final msg = Map<String, dynamic>.from(m);

      // ignore if duplicate exists
      final mid = (msg['id'] ?? '').toString();
      if (mid.isNotEmpty && _messages.any((e) => (e['id'] ?? '').toString() == mid)) {
        return;
      }

      _messages.add(_normalizeServerMessage(msg));
      _messages.sort((a, b) => _msgTime(a).compareTo(_msgTime(b)));

      // delivered ack (optional)
      _emitDeliveredBestEffort(msg);

      setState(() {});

      if (_isAtBottom()) {
        _scrollToBottom(animate: true);
      }
    });

    // typing
    ChatSocketService.I.onTyping.listen((payload) {
      if (!mounted) return;
      final convId = _toInt(payload['conversation_id'] ?? payload['conversationId']);
      if (convId <= 0 || (_conversationId > 0 && convId != _conversationId)) return;

      final uid = _toInt(payload['user_id'] ?? payload['userId']);
      if (uid == _myUserId) return;

      final isTyping = _toBool(payload['is_typing'] ?? payload['typing']);
      setState(() => _isFriendTyping = isTyping);
    });

    // presence
    ChatSocketService.I.onPresence.listen((payload) {
      if (!mounted) return;
      final uid = _toInt(payload['user_id'] ?? payload['userId']);
      final isOnline = _toBool(payload['is_online'] ?? payload['online']);
      if (uid.toString() == widget.friendId.trim()) {
        setState(() => _isFriendOnline = isOnline);
      }
    });

    // receipts (optional)
    ChatSocketService.I.onSeen.listen((payload) {
      if (!mounted) return;
      final convId = _toInt(payload['conversation_id'] ?? payload['conversationId']);
      if (convId <= 0 || (_conversationId > 0 && convId != _conversationId)) return;
      final msgId = (payload['message_id'] ?? payload['messageId'] ?? '').toString();
      if (msgId.isEmpty) return;

      for (final m in _messages) {
        if ((m['id'] ?? '').toString() == msgId) {
          m['seen_at'] = DateTime.now().toIso8601String();
        }
      }
      setState(() {});
    });

    ChatSocketService.I.onDelivered.listen((payload) {
      if (!mounted) return;
      final convId = _toInt(payload['conversation_id'] ?? payload['conversationId']);
      if (convId <= 0 || (_conversationId > 0 && convId != _conversationId)) return;
      final msgId = (payload['message_id'] ?? payload['messageId'] ?? '').toString();
      if (msgId.isEmpty) return;

      for (final m in _messages) {
        if ((m['id'] ?? '').toString() == msgId) {
          m['delivered_at'] = DateTime.now().toIso8601String();
        }
      }
      setState(() {});
    });
  }

  // -----------------------------------------------------------------
  Future<void> _refreshMessagesInitial({required bool silent}) async {
    if ((_token ?? '').isEmpty) return;

    final wasAtBottom = _isAtBottom();

    try {
      final res = await MessageAPI.getConversation(
        token: _token!,
        friendId: int.parse(widget.friendId),
        limit: _pageSize,
      );

      _conversationId = _toInt(res['conversation_id'] ?? res['conversationId']);
      if (_conversationId > 0) {
        ChatSocketService.I.joinConversation(_conversationId);
      }

      final raw = (res['messages'] as List<dynamic>?) ?? (res['data'] as List<dynamic>?) ?? [];
      final serverMsgs = raw.where((e) => e is Map).map((e) => _normalizeServerMessage(Map<String, dynamic>.from(e as Map))).toList();

      // keep pending locals
      final localPending = _messages.where((m) {
        final st = (m['_status'] ?? '').toString();
        return m['_local'] == true && (st == _MsgStatus.sending.name || st == _MsgStatus.failed.name);
      }).toList();

      _messages
        ..clear()
        ..addAll(serverMsgs);

      for (final p in localPending) {
        final id = (p['id'] ?? '').toString();
        if (id.isNotEmpty && _messages.any((s) => (s['id'] ?? '').toString() == id)) continue;
        _messages.add(p);
      }

      _messages.sort((a, b) => _msgTime(a).compareTo(_msgTime(b)));

      // pagination state
      _oldestServerMessageId = _findOldestServerId();
      _hasMore = serverMsgs.length >= _pageSize;

      if (!mounted) return;
      setState(() {});

      if (!silent) {
        _scrollToBottom(animate: false);
      } else if (wasAtBottom) {
        _scrollToBottom(animate: false);
      }
    } catch (e) {
      debugPrint('Refresh Messages Error: $e');
    }
  }

  Future<void> _loadMoreOlder() async {
    if (_loadingMore || !_hasMore) return;
    if ((_token ?? '').isEmpty) return;
    if (_oldestServerMessageId <= 0) return;

    setState(() => _loadingMore = true);

    try {
      final res = await MessageAPI.getConversation(
        token: _token!,
        friendId: int.parse(widget.friendId),
        beforeMessageId: _oldestServerMessageId,
        limit: _pageSize,
      );

      final raw = (res['messages'] as List<dynamic>?) ?? (res['data'] as List<dynamic>?) ?? [];
      final older = raw.where((e) => e is Map).map((e) => _normalizeServerMessage(Map<String, dynamic>.from(e as Map))).toList();

      if (older.isEmpty) {
        _hasMore = false;
      } else {
        // add only new
        for (final m in older) {
          final id = (m['id'] ?? '').toString();
          if (id.isNotEmpty && _messages.any((x) => (x['id'] ?? '').toString() == id)) continue;
          _messages.add(m);
        }

        _messages.sort((a, b) => _msgTime(a).compareTo(_msgTime(b)));
        _oldestServerMessageId = _findOldestServerId();
        _hasMore = older.length >= _pageSize;
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Load More Error: $e');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  int _findOldestServerId() {
    int minId = 0;
    for (final m in _messages) {
      if (m['_local'] == true) continue;
      final id = _toInt(m['id']);
      if (id <= 0) continue;
      if (minId == 0 || id < minId) minId = id;
    }
    return minId;
  }

  // -----------------------------------------------------------------
  Future<void> _refreshOnline() async {
    if ((_token ?? '').isEmpty) return;
    try {
      final uri = Uri.parse('$apiBase/friends/online');
      final client = HttpClient();
      final req = await client.getUrl(uri);
      req.headers.set('Accept', 'application/json');
      req.headers.set('Authorization', 'Bearer $_token');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) return;
      final decoded = jsonDecode(body);

      List list = [];
      if (decoded is List) list = decoded;
      if (decoded is Map) {
        list = (decoded['online'] ?? decoded['users'] ?? decoded['data'] ?? []) as List? ?? [];
      }

      final fid = widget.friendId.trim();
      bool found = false;
      bool online = false;

      for (final e in list) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final id = (m['id'] ?? m['user_id'] ?? m['friend_id'] ?? '').toString().trim();
        if (id == fid) {
          found = true;
          online = _toBool(m['is_online'] ?? m['online'] ?? true);
          break;
        }
      }

      if (!found) online = false;
      if (mounted) setState(() => _isFriendOnline = online);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _markSeenBestEffort() async {
    try {
      if ((_token ?? '').isEmpty) return;
      final fid = int.tryParse(widget.friendId) ?? 0;
      if (fid <= 0) return;
      await MessageAPI.markSeen(token: _token!, friendId: fid);

      // optional socket notify
      if (_conversationId > 0) {
        // backend can ignore
        ChatSocketService.I.joinConversation(_conversationId);
      }
    } catch (_) {}
  }

  void _emitDeliveredBestEffort(Map<String, dynamic> msg) {
    // Only for messages coming to me
    try {
      final sender = (msg['sender_id'] ?? '').toString();
      if (sender == _myUserId.toString()) return;
      if (_conversationId <= 0) return;
      // backend may emit delivered; if not, ignore
      // No explicit REST endpoint exists in your API currently.
    } catch (_) {}
  }

  // -----------------------------------------------------------------
  Future<void> _sendMessage({File? mediaFile}) async {
    final text = _controller.text.trim();
    if (text.isEmpty && mediaFile == null) return;
    if (_sending) return;
    if ((_token ?? '').isEmpty || _myUserId <= 0) return;

    setState(() => _sending = true);

    final clientMsgId = _newClientMsgId();
    final tempId = -DateTime.now().millisecondsSinceEpoch; // negative = temp
    final nowIso = DateTime.now().toIso8601String();

    final tempMsg = <String, dynamic>{
      'id': tempId,
      'client_msg_id': clientMsgId,
      'sender_id': _myUserId,
      'text': text,
      'media_url': mediaFile?.path,
      'created_at': nowIso,
      '_local': true,
      '_status': _MsgStatus.sending.name,
    };

    setState(() {
      _messages.add(tempMsg);
      _controller.clear();
    });

    _messages.sort((a, b) => _msgTime(a).compareTo(_msgTime(b)));
    _scrollToBottom(animate: true);

    try {
      final res = await MessageAPI.sendMessage(
        token: _token!,
        friendId: int.parse(widget.friendId),
        text: text,
        mediaFile: mediaFile,
        clientMsgId: clientMsgId,
      );

      if (!mounted) return;

      final serverMsg = _normalizeSendResponseToMessage(res);

      // replace temp
      final idx = _messages.indexWhere((e) => _toInt(e['id']) == tempId);
      if (idx != -1) {
        _messages[idx] = serverMsg;
      } else {
        _messages.add(serverMsg);
      }

      _messages.sort((a, b) => _msgTime(a).compareTo(_msgTime(b)));
      setState(() {});

      await _markSeenBestEffort();
    } catch (e) {
      debugPrint('Send Message Failed: $e');
      final idx = _messages.indexWhere((e) => _toInt(e['id']) == tempId);
      if (idx != -1) {
        setState(() => _messages[idx]['_status'] = _MsgStatus.failed.name);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message failed. Tap the bubble to retry.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom(animate: true);
    }
  }

  Map<String, dynamic> _normalizeSendResponseToMessage(Map<String, dynamic> res) {
    // backend may return nested message
    final raw = (res['message'] is Map) ? Map<String, dynamic>.from(res['message'] as Map) : res;
    return _normalizeServerMessage(raw)
      ..['_local'] = false
      ..['_status'] = _MsgStatus.sent.name;
  }

  Map<String, dynamic> _normalizeServerMessage(Map<String, dynamic> msg) {
    final m = Map<String, dynamic>.from(msg);

    // normalize ids
    if (m['sender_id'] == null && m['senderId'] != null) m['sender_id'] = m['senderId'];
    if (m['created_at'] == null && m['createdAt'] != null) m['created_at'] = m['createdAt'];

    // normalize media url
    final media = (m['media_url'] ?? m['media'] ?? m['image'] ?? '').toString().trim();
    if (media.isNotEmpty) {
      m['media_url'] = _safePublicUrl(media);
    }

    // status fields
    m['_local'] ??= false;
    m['_status'] ??= _MsgStatus.none.name;

    return m;
  }

  Future<void> _retryFailed(Map<String, dynamic> msg) async {
    final status = (msg['_status'] ?? '').toString();
    if (status != _MsgStatus.failed.name) return;

    final text = (msg['text'] ?? '').toString().trim();
    final media = (msg['media_url'] ?? '').toString().trim();
    File? f;

    if (media.isNotEmpty && !media.startsWith('http')) {
      final file = File(media);
      if (file.existsSync()) f = file;
    }

    setState(() => _messages.remove(msg));
    _controller.text = text;
    await _sendMessage(mediaFile: f);
  }

  Future<void> _pickAndSendMedia() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) {
      await _sendMessage(mediaFile: File(picked.path));
    }
  }

  // -----------------------------------------------------------------
  void _onScroll() {
    if (!_scrollController.hasClients) return;

    // reverse:true => older messages are near maxScrollExtent
    final pos = _scrollController.position;
    if (pos.pixels >= (pos.maxScrollExtent - 120)) {
      _loadMoreOlder();
    }
  }

  bool _isAtBottom() {
    if (!_scrollController.hasClients) return true;
    // reverse:true => bottom == offset 0
    return _scrollController.offset <= 60;
  }

  void _scrollToBottom({required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      const target = 0.0;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  void _onTypingChanged() {
    if (_conversationId <= 0) return;

    // start typing
    if (_controller.text.trim().isNotEmpty && !_sentTypingTrue) {
      ChatSocketService.I.setTyping(conversationId: _conversationId, isTyping: true);
      _sentTypingTrue = true;
    }

    // stop typing after pause
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      if (_sentTypingTrue) {
        ChatSocketService.I.setTyping(conversationId: _conversationId, isTyping: false);
        _sentTypingTrue = false;
      }
    });
  }

  // -----------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final safeAvatarUrl = _safePublicUrl(widget.friendAvatarUrl);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(_AppBarHeights.header),
        child: Container(
          decoration: BoxDecoration(gradient: troonkyGradient()),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: _AppBarHeights.header,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white.withOpacity(0.22),
                    backgroundImage: safeAvatarUrl.isNotEmpty ? NetworkImage(safeAvatarUrl) : null,
                    child: safeAvatarUrl.isEmpty
                        ? Text(
                      widget.friendName.isNotEmpty ? widget.friendName[0].toUpperCase() : 'U',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                    )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.friendName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          _isFriendOnline ? (_isFriendTyping ? 'typing…' : 'Online') : 'Offline',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(_isFriendOnline ? 1.0 : 0.78),
                            fontStyle: _isFriendTyping ? FontStyle.italic : FontStyle.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    onPressed: () => _openChatMenu(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Expanded(child: _buildMessageList()),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return const Center(
        child: Text(
          'Say hello! 👋',
          style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w600),
        ),
      );
    }

    final total = _messages.length + (_loadingMore ? 1 : 0) + (_isFriendTyping ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      reverse: true,
      itemCount: total,
      itemBuilder: (context, index) {
        int cursor = index;

        if (_isFriendTyping) {
          if (cursor == 0) return const _TypingBubble();
          cursor -= 1;
        }

        if (_loadingMore) {
          if (cursor == total - 1) {
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey.shade600),
                ),
              ),
            );
          }
        }

        final reversedIndex = (_messages.length - 1) - cursor;
        if (reversedIndex < 0 || reversedIndex >= _messages.length) return const SizedBox.shrink();

        final msg = _messages[reversedIndex];
        return _buildChatBubble(msg);
      },
    );
  }

  Widget _buildChatBubble(Map<String, dynamic> msg) {
    final isMe = (msg['sender_id'] ?? '').toString() == _myUserId.toString();

    final bubbleGradient = isMe ? troonkyGradient(opacity: 1.0) : null;
    final bubbleColor = isMe ? null : Colors.white;
    final textColor = isMe ? Colors.white : Colors.black87;

    final status = _statusFor(msg, isMe: isMe);

    final mediaUrlRaw = (msg['media_url'] ?? msg['media'] ?? msg['image'] ?? '').toString().trim();
    final hasMedia = mediaUrlRaw.isNotEmpty;

    final isLocalFile = hasMedia && !mediaUrlRaw.startsWith('http') && (msg['_local'] == true);
    final localPath = isLocalFile ? mediaUrlRaw : '';
    final displayUrl = (!isLocalFile && hasMedia) ? _safePublicUrl(mediaUrlRaw) : '';

    final radius = isMe
        ? const BorderRadius.only(
      topLeft: Radius.circular(16),
      bottomLeft: Radius.circular(16),
      topRight: Radius.circular(16),
      bottomRight: Radius.circular(6),
    )
        : const BorderRadius.only(
      topLeft: Radius.circular(6),
      bottomLeft: Radius.circular(16),
      topRight: Radius.circular(16),
      bottomRight: Radius.circular(16),
    );

    final timeText = _fmtTime(_msgTime(msg));

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: () {
          if (status == _MsgStatus.failed) _retryFailed(msg);
        },
        onLongPress: () => _openMessageMenu(msg),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            gradient: bubbleGradient,
            color: bubbleColor,
            borderRadius: radius,
            border: isMe ? null : Border.all(color: Colors.black.withOpacity(0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasMedia)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: GestureDetector(
                      onTap: () {
                        final url = isLocalFile ? localPath : displayUrl;
                        if (url.isEmpty) return;
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            opaque: false,
                            pageBuilder: (_, __, ___) => _FullScreenImageViewer(
                              images: [url],
                              initialIndex: 0,
                              heroTag: 'msg_media_${msg['id']}',
                            ),
                          ),
                        );
                      },
                      child: Hero(
                        tag: 'msg_media_${msg['id']}',
                        child: isLocalFile
                            ? Image.file(
                          File(localPath),
                          width: 210,
                          height: 210,
                          fit: BoxFit.cover,
                        )
                            : CachedNetworkImage(
                          imageUrl: displayUrl,
                          width: 210,
                          height: 210,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            width: 210,
                            height: 210,
                            color: Colors.black12,
                            alignment: Alignment.center,
                            child: const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            width: 210,
                            height: 210,
                            color: Colors.grey.shade300,
                            alignment: Alignment.center,
                            child: Icon(Icons.broken_image, size: 44, color: Colors.grey.shade700),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              if ((msg['text'] ?? msg['message'] ?? '').toString().trim().isNotEmpty)
                Text(
                  (msg['text'] ?? msg['message'] ?? '').toString(),
                  style: TextStyle(color: textColor, fontSize: 15, height: 1.25),
                ),

              const SizedBox(height: 6),

              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeText,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isMe ? Colors.white70 : Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 8),
                    _statusIcon(status),
                  ],
                ],
              ),

              if (status == _MsgStatus.failed) ...[
                const SizedBox(height: 6),
                Text(
                  'Tap to retry',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isMe ? Colors.white70 : Colors.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusIcon(_MsgStatus st) {
    if (st == _MsgStatus.none) return const SizedBox.shrink();

    IconData icon;
    Color color;

    switch (st) {
      case _MsgStatus.sending:
        icon = Icons.access_time;
        color = Colors.white70;
        break;
      case _MsgStatus.sent:
        icon = Icons.check;
        color = Colors.white70;
        break;
      case _MsgStatus.delivered:
        icon = Icons.done_all;
        color = Colors.white70;
        break;
      case _MsgStatus.seen:
        icon = Icons.done_all;
        color = troonkyGradB;
        break;
      case _MsgStatus.failed:
        icon = Icons.error_outline;
        color = Colors.yellowAccent;
        break;
      default:
        return const SizedBox.shrink();
    }

    return Icon(icon, size: 16, color: color);
  }

  Widget _buildInputArea() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.black.withOpacity(0.06))),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.photo, color: troonkyColor),
              onPressed: _pickAndSendMedia,
              splashRadius: 22,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _controller,
                keyboardType: TextInputType.multiline,
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _sendMessage(),
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _sendMessage();
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: troonkyGradient(),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: troonkyGradA.withOpacity(0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.send, color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------
  Future<void> _openMessageMenu(Map<String, dynamic> msg) async {
    final isMe = (msg['sender_id'] ?? '').toString() == _myUserId.toString();
    final messageId = _toInt(msg['id']);

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy'),
                onTap: () => Navigator.pop(context, 'copy'),
              ),
              if (messageId > 0)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete for me'),
                  onTap: () => Navigator.pop(context, 'delete_me'),
                ),
              if (isMe && messageId > 0)
                ListTile(
                  leading: const Icon(Icons.delete_forever),
                  title: const Text('Delete for everyone'),
                  onTap: () => Navigator.pop(context, 'delete_all'),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || choice == null) return;

    if (choice == 'copy') {
      final t = (msg['text'] ?? '').toString();
      if (t.trim().isEmpty) return;
      await Clipboard.setData(ClipboardData(text: t));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
      return;
    }

    if ((_token ?? '').isEmpty) return;

    if (choice == 'delete_me') {
      try {
        await MessageAPI.deleteForMe(token: _token!, messageId: messageId);
        setState(() => _messages.remove(msg));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }

    if (choice == 'delete_all') {
      try {
        await MessageAPI.deleteForEveryone(token: _token!, messageId: messageId);
        setState(() => _messages.remove(msg));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  Future<void> _openChatMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Refresh'),
                onTap: () => Navigator.pop(context, 'refresh'),
              ),
              ListTile(
                leading: const Icon(Icons.mark_chat_read_outlined),
                title: const Text('Mark seen'),
                onTap: () => Navigator.pop(context, 'seen'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || choice == null) return;

    if (choice == 'refresh') {
      _refreshOnline();
      _refreshMessagesInitial(silent: false);
    }

    if (choice == 'seen') {
      _markSeenBestEffort();
    }
  }

  // -----------------------------------------------------------------
  _MsgStatus _statusFor(Map<String, dynamic> msg, {required bool isMe}) {
    final local = (msg['_status'] ?? '').toString().trim();
    if (local == _MsgStatus.sending.name) return _MsgStatus.sending;
    if (local == _MsgStatus.failed.name) return _MsgStatus.failed;

    if (!isMe) return _MsgStatus.none;

    final rawStatus = msg['status'] ?? msg['message_status'] ?? msg['delivery_status'] ?? msg['state'];
    final seenAt = msg['seen_at'] ?? msg['read_at'] ?? msg['readAt'];
    final deliveredAt = msg['delivered_at'] ?? msg['deliveredAt'];

    if (_hasValue(seenAt)) return _MsgStatus.seen;
    if (_hasValue(deliveredAt)) return _MsgStatus.delivered;

    if (rawStatus is int) {
      if (rawStatus <= 0) return _MsgStatus.sent;
      if (rawStatus == 1) return _MsgStatus.delivered;
      return _MsgStatus.seen;
    }

    final s = (rawStatus ?? '').toString().toLowerCase().trim();
    if (s.contains('read') || s.contains('seen')) return _MsgStatus.seen;
    if (s.contains('deliver')) return _MsgStatus.delivered;
    if (s.contains('sent')) return _MsgStatus.sent;

    final id = (msg['id'] ?? '').toString().trim();
    if (id.isNotEmpty) return _MsgStatus.sent;

    return _MsgStatus.none;
  }

  static bool _hasValue(dynamic v) {
    if (v == null) return false;
    final s = v.toString().trim();
    return s.isNotEmpty && s.toLowerCase() != 'null';
  }

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v == 1;
    final s = (v ?? '').toString().toLowerCase().trim();
    return s == 'true' || s == '1' || s == 'yes' || s == 'online';
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse((v ?? '').toString().trim()) ?? 0;
  }

  static DateTime _msgTime(Map<String, dynamic> msg) {
    final v = msg['created_at'] ?? msg['createdAt'] ?? msg['time'] ?? msg['timestamp'];
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);

    if (v is int) {
      if (v > 1000000000000) return DateTime.fromMillisecondsSinceEpoch(v).toLocal();
      return DateTime.fromMillisecondsSinceEpoch(v * 1000).toLocal();
    }

    final raw = v.toString().trim();
    if (raw.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);

    final s = (raw.contains(' ') && !raw.contains('T')) ? raw.replaceFirst(' ', 'T') : raw;
    final dt = DateTime.tryParse(s);
    if (dt == null) return DateTime.fromMillisecondsSinceEpoch(0);
    return dt.isUtc ? dt.toLocal() : dt;
  }

  static String _fmtTime(DateTime dt) {
    if (dt.millisecondsSinceEpoch == 0) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:${two(dt.minute)} $ampm';
  }

  String _safePublicUrl(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    return FeedAPI.toPublicUrl(s);
  }

  String _newClientMsgId() {
    final r = Random.secure();
    final a = DateTime.now().microsecondsSinceEpoch.toString();
    final b = List.generate(6, (_) => r.nextInt(16).toRadixString(16)).join();
    return 'c$a$b';
  }
}

class _AppBarHeights {
  static const double header = 56;
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dot(),
            const SizedBox(width: 4),
            _dot(delay: 150),
            const SizedBox(width: 4),
            _dot(delay: 300),
          ],
        ),
      ),
    );
  }

  Widget _dot({int delay = 0}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.35, end: 1.0),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOut,
      builder: (_, v, __) => Opacity(
        opacity: v,
        child: const CircleAvatar(radius: 4, backgroundColor: Colors.grey),
      ),
      onEnd: () {},
    );
  }
}

class _FullScreenImageViewer extends StatelessWidget {
  final List<String> images;
  final int initialIndex;
  final String heroTag;

  const _FullScreenImageViewer({
    required this.images,
    required this.initialIndex,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.95),
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: PageController(initialPage: initialIndex),
              itemCount: images.length,
              itemBuilder: (_, i) {
                final url = images[i];
                final isLocal = !url.startsWith('http');
                return Center(
                  child: Hero(
                    tag: heroTag,
                    child: InteractiveViewer(
                      child: isLocal
                          ? Image.file(File(url), fit: BoxFit.contain)
                          : CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
