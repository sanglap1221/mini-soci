import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pay_go/services/api_service.dart';
import '../services/app_cache_managers.dart';
import '../services/call_service.dart';
import 'profile_page.dart';
import 'call_screen.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String otherUserId;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.otherUserId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  final _apiService = ApiService();
  final _callService = CallService();
  String _otherUserName = 'User';
  String? _otherUserAvatarUrl;

  // Track current call status and callId if a call is initiated
  String? _activeCallId;
  String? _activeCallStatus;
  StreamSubscription<DocumentSnapshot>? _callStatusSubscription;
  @override
  void dispose() {
    _cancelCallIfNotAnswered();
    super.dispose();
    _callStatusSubscription?.cancel();
  }

  void _cancelCallIfNotAnswered() async {
    // If a call was started and is still ringing, cancel it
    if (_activeCallId != null && _activeCallStatus == 'ringing') {
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(_activeCallId)
          .update({'status': 'cancelled'});
    }
  }

  @override
  void initState() {
    super.initState();
    _loadOtherUserData();
    _markMessagesAsRead();
  }

  Future<void> _loadOtherUserData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.otherUserId)
          .get();
      if (mounted && doc.exists) {
        final userData = doc.data() ?? {};
        _updateOtherUserInfo(userData);
      }
    } catch (e) {
      debugPrint('Error loading other user data: $e');
    }
  }

  Future<void> _markMessagesAsRead() async {
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .update({'unreadCount': 0});
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final message = _messageController.text;
    _messageController.clear();

    try {
      // Send message through backend API to trigger push notification
      await _apiService.sendChatMessage(
        chatId: widget.chatId,
        recipientUserId: widget.otherUserId,
        message: message,
      );

      // Also update Firestore for real-time chat updates
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .add({
            'senderId': currentUserId,
            'message': message,
            'timestamp': FieldValue.serverTimestamp(),
          });

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({
            'lastMessage': message,
            'lastMessageTime': FieldValue.serverTimestamp(),
            'unreadCount': FieldValue.increment(1),
          });
    } catch (e) {
      debugPrint('Error sending message: $e');
      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () {
            // Navigate to user profile
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProfilePage(userId: widget.otherUserId),
              ),
            );
          },
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: _otherUserAvatarUrl ?? '',
                    cacheManager: AppCacheManagers.imageCache,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        const CircularProgressIndicator(),
                    errorWidget: (context, url, error) => CircleAvatar(
                      radius: 20,
                      child: Text(
                        _otherUserName.isNotEmpty
                            ? _otherUserName[0].toUpperCase()
                            : 'U',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(_otherUserName),
            ],
          ),
        ),
        actions: [
          // Audio call button
          IconButton(
            icon: const Icon(Icons.call),
            tooltip: 'Voice Call',
            onPressed: () => _startCall(false),
          ),
          // Video call button
          IconButton(
            icon: const Icon(Icons.videocam),
            tooltip: 'Video Call',
            onPressed: () => _startCall(true),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Something went wrong'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data?.docs ?? [];

                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message =
                        messages[index].data() as Map<String, dynamic>;
                    final isMe = message['senderId'] == currentUserId;

                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Theme.of(context).primaryColor
                              : Colors.grey[200],
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: isMe
                                ? const Radius.circular(20)
                                : const Radius.circular(4),
                            bottomRight: isMe
                                ? const Radius.circular(4)
                                : const Radius.circular(20),
                          ),
                        ),
                        child: Text(
                          message['message'],
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startCall(bool isVideoCall) async {
    if (currentUserId == null) return;

    try {
      // Create call document in Firestore
      final callId = await _callService.createCall(
        callerId: currentUserId!,
        calleeId: widget.otherUserId,
        isVideoCall: isVideoCall,
      );

      // Track the active call
      _activeCallId = callId;
      _activeCallStatus = 'ringing';

      if (!mounted) return;

      // Listen for call status updates (for incoming call cancellation)
      _callStatusSubscription = FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .snapshots()
          .listen((snapshot) {
            final data = snapshot.data();
            if (data != null && data['status'] != null) {
              // This status is used to cancel the call if user navigates away
              _activeCallStatus = data['status'];
            }
          });

      // Navigate to CallScreen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CallScreen(
            callId: callId,
            callerId: currentUserId!,
            receiverId: widget.otherUserId,
            isInitiator: true,
            isVideoCall: isVideoCall,
            otherUserName: _otherUserName,
            otherUserAvatarUrl: _otherUserAvatarUrl,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error starting call: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start call: $e')));
      }
    }
  }

  void _updateOtherUserInfo(Map<String, dynamic> userData) {
    final displayName = userData['username'] as String? ?? 'Unknown User';
    final avatarUrl = _toFullImageUrl(_extractAvatarPath(userData));

    if (mounted &&
        (_otherUserName != displayName || _otherUserAvatarUrl != avatarUrl)) {
      setState(() {
        _otherUserName = displayName;
        _otherUserAvatarUrl = avatarUrl;
      });
    }
  }

  String? _toFullImageUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    return _apiService.getFullImageUrl(path);
  }

  String? _extractAvatarPath(
    Map<String, dynamic> userData, {
    bool checkNested = true,
  }) {
    dynamic raw =
        userData['profilePicUrl'] ??
        userData['profilePicture'] ??
        userData['photoUrl'] ??
        userData['avatar'];

    if (raw == null && checkNested) {
      final profileSection = userData['profile'];
      if (profileSection is Map<String, dynamic>) {
        final nested = _extractAvatarPath(profileSection, checkNested: false);
        if (nested != null) {
          raw = nested;
        }
      }

      if (raw == null) {
        final authorSection = userData['author'];
        if (authorSection is Map<String, dynamic>) {
          final nested = _extractAvatarPath(authorSection, checkNested: false);
          if (nested != null) {
            raw = nested;
          }
        }
      }
    }

    if (raw == null) return null;

    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      return trimmed;
    }

    if (raw is Map) {
      final dynamic candidate =
          [
            raw['secureUrl'],
            raw['secure_url'],
            raw['url'],
            raw['path'],
            raw['downloadUrl'],
            raw['downloadURL'],
          ].firstWhere(
            (value) => value is String && value.trim().isNotEmpty,
            orElse: () => null,
          );

      if (candidate is String) {
        return candidate.trim();
      }
    }

    return null;
  }
}
