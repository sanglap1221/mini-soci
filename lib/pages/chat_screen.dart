import 'package:cached_network_image/cached_network_image.dart';
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

  @override
  void initState() {
    super.initState();
    _markMessagesAsRead();
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
        title: FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(widget.otherUserId)
              .get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Text('Loading...');
            }
            if (!snapshot.hasData) {
              return const Text('Unknown User');
            }
            final userData =
                snapshot.data?.data() as Map<String, dynamic>? ?? {};
            final displayName =
                userData['username'] as String? ?? 'Unknown User';

            // Store the display name for call screen
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _otherUserName != displayName) {
                setState(() {
                  _otherUserName = displayName;
                });
              }
            });

            final avatarUrl = _toFullImageUrl(_extractAvatarPath(userData));

            return InkWell(
              onTap: () {
                // Navigate to user profile
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        ProfilePage(userId: widget.otherUserId),
                  ),
                );
              },
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: avatarUrl != null
                        ? CachedNetworkImageProvider(
                            avatarUrl,
                            cacheManager: AppCacheManagers.imageCache,
                          )
                        : null,
                    child: avatarUrl == null
                        ? const Icon(Icons.person, size: 20)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(displayName),
                ],
              ),
            );
          },
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
                          color: isMe ? Colors.blue : Colors.grey[300],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          message['message'],
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.black,
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

      if (!mounted) return;

      // Navigate to CallScreen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CallScreen(
            callId: callId,
            callerId: currentUserId!,
            receiverId: widget.otherUserId,
            isInitiator: true,
            otherUserName: _otherUserName,
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
