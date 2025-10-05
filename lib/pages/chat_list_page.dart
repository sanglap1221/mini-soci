import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pay_go/services/api_service.dart';
import 'chat_screen.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _apiService = ApiService();

  final Map<String, String?> _avatarCache = {};
  final Map<String, Future<String?>> _avatarFutureCache = {};
  final Set<String> _failedAvatarUrls = <String>{};
  final Map<String, String> _usernameOverrides = <String, String>{};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _userSubscription;

  String _getChatId(String currentUserId, String otherUserId) {
    final ids = [currentUserId, otherUserId];
    ids.sort();
    return ids.join('_');
  }

  String? _otherParticipantId(String currentUserId, List<String> participants) {
    for (final participant in participants) {
      if (participant != currentUserId) {
        return participant;
      }
    }
    return null;
  }

  void _listenForUserUpdates() {
    _userSubscription?.cancel();
    _userSubscription = _firestore.collection('users').snapshots().listen(
      (snapshot) {
        final updates = <String, String>{};
        for (final doc in snapshot.docs) {
          final username = (doc.data()['username'] as String?)?.trim();
          if (username != null && username.isNotEmpty) {
            updates[doc.id] = username;
          }
        }

        if (!mounted) return;
        if (mapEquals(_usernameOverrides, updates)) return;

        setState(() {
          _usernameOverrides
            ..clear()
            ..addAll(updates);
        });
      },
      onError: (err) =>
          debugPrint('ChatListPage user subscription error: $err'),
    );
  }

  @override
  void initState() {
    super.initState();
    _listenForUserUpdates();
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
  }

  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view chats.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _firestore
            .collection('chats')
            .where('participants', arrayContains: currentUser.uid)
            .orderBy('lastMessageTime', descending: true)
            .snapshots(),
        builder: (context, chatSnapshot) {
          if (chatSnapshot.hasError) {
            return _buildStatusMessage(
              icon: Icons.error_outline,
              message: 'Something went wrong loading chats.',
            );
          }

          if (chatSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final chatDocs = chatSnapshot.data?.docs ?? [];
          final Map<String, Map<String, dynamic>> chatDataByUserId = {};

          for (final doc in chatDocs) {
            final data = doc.data();
            final participants = (data['participants'] as List<dynamic>?)
                ?.whereType<String>()
                .toList();
            if (participants == null || participants.isEmpty) {
              continue;
            }

            final otherId = _otherParticipantId(currentUser.uid, participants);
            if (otherId == null) continue;
            chatDataByUserId[otherId] = data;
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _firestore
                .collection('users')
                .orderBy('username')
                .snapshots(),
            builder: (context, userSnapshot) {
              if (userSnapshot.hasError) {
                return _buildStatusMessage(
                  icon: Icons.error_outline,
                  message: 'Something went wrong loading users.',
                );
              }

              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final allUsers =
                  userSnapshot.data?.docs
                      .where((doc) => doc.id != currentUser.uid)
                      .toList() ??
                  [];

              if (allUsers.isEmpty) {
                return _buildStatusMessage(
                  icon: Icons.chat_bubble_outline,
                  message: 'You can start a conversation.',
                );
              }

              final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>>
              userById = {for (final doc in allUsers) doc.id: doc};

              final chatUsers = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              final seenChatUserIds = <String>{};

              for (final doc in chatDocs) {
                final data = doc.data();
                final participants = (data['participants'] as List<dynamic>?)
                    ?.whereType<String>()
                    .toList();
                if (participants == null || participants.isEmpty) {
                  continue;
                }

                final otherId = _otherParticipantId(
                  currentUser.uid,
                  participants,
                );
                if (otherId == null || seenChatUserIds.contains(otherId)) {
                  continue;
                }

                final userDoc = userById[otherId];
                if (userDoc != null) {
                  chatUsers.add(userDoc);
                  seenChatUserIds.add(otherId);
                }
              }

              final nonChatUsers = allUsers
                  .where((doc) => !seenChatUserIds.contains(doc.id))
                  .toList();

              final finalList = [...chatUsers, ...nonChatUsers];

              if (finalList.isEmpty) {
                return _buildStatusMessage(
                  icon: Icons.chat_bubble_outline,
                  message: 'You can start a conversation.',
                );
              }

              return ListView.builder(
                itemCount: finalList.length,
                itemBuilder: (context, index) {
                  final userDoc = finalList[index];
                  final userData = userDoc.data();
                  final otherUserId = userDoc.id;
                  final displayName = _resolveUsernameForUserDoc(
                    userDoc.id,
                    userData,
                  );

                  final chatData = chatDataByUserId[otherUserId];
                  final lastMessage =
                      (chatData?['lastMessage'] as String?) ?? '';
                  final lastMessageTimeText = _formatTimestamp(
                    chatData?['lastMessageTime'],
                  );
                  final participantsList =
                      (chatData?['participants'] as List<dynamic>?)
                          ?.whereType<String>()
                          .toList();

                  return ListTile(
                    leading: _buildAvatarWidget(
                      userId: otherUserId,
                      userData: userData,
                      displayName: displayName,
                    ),
                    trailing: lastMessageTimeText != null
                        ? Text(
                            lastMessageTimeText,
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          )
                        : Icon(
                            Icons.chat_bubble_outline,
                            color: Colors.grey[400],
                            size: 20,
                          ),
                    title: Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fallbackSubtitle(lastMessage),
                          style: _getSubtitleStyle(lastMessage),
                        ),
                      ],
                    ),
                    onTap: () {
                      final chatId = _getChatId(currentUser.uid, otherUserId);
                      final resolvedParticipants =
                          (participantsList != null &&
                              participantsList.isNotEmpty)
                          ? participantsList
                          : [currentUser.uid, otherUserId];
                      _openChat(
                        chatId,
                        otherUserId,
                        participants: resolvedParticipants,
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  static String _fallbackSubtitle(String lastMessage) {
    return lastMessage.isNotEmpty ? lastMessage : 'Start a chat now';
  }

  TextStyle _getSubtitleStyle(String lastMessage) {
    if (lastMessage.isEmpty) {
      // Style for the "Start a chat now" fallback message
      return TextStyle(color: Colors.grey[400], fontSize: 12);
    } else {
      // Style for an actual last message (e.g., normal text color)
      return TextStyle(color: Colors.grey[600], fontSize: 14);
    }
  }

  Widget _buildStatusMessage({
    required IconData icon,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openChat(
    String chatId,
    String otherUserId, {
    required List<String> participants,
  }) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    final resolvedParticipants = List<String>.from(participants);
    if (!resolvedParticipants.contains(currentUserId)) {
      resolvedParticipants.add(currentUserId);
    }
    if (!resolvedParticipants.contains(otherUserId)) {
      resolvedParticipants.add(otherUserId);
    }

    resolvedParticipants.sort();

    final docRef = _firestore.collection('chats').doc(chatId);
    final chatSnapshot = await docRef.get();

    if (!chatSnapshot.exists) {
      await docRef.set({
        'participants': resolvedParticipants,
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unreadCount': 0,
      });
    }

    final resolvedChatId = chatSnapshot.exists ? chatId : docRef.id;

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ChatScreen(chatId: resolvedChatId, otherUserId: otherUserId),
      ),
    );
  }

  Widget _buildAvatarWidget({
    required String userId,
    required Map<String, dynamic> userData,
    String? displayName,
  }) {
    final directPath = _extractAvatarPath(userData);
    final directUrl = _toFullImageUrl(directPath);

    if (directUrl != null &&
        directUrl.isNotEmpty &&
        !_failedAvatarUrls.contains(directUrl)) {
      _avatarCache[userId] = directUrl;
      return _avatarCircleFromUrl(directUrl, displayName);
    }

    final cachedUrl = _avatarCache[userId];
    if (cachedUrl != null && cachedUrl.isNotEmpty) {
      return _avatarCircleFromUrl(cachedUrl, displayName);
    }

    final future = _avatarFutureCache.putIfAbsent(userId, () async {
      try {
        final profileData = await _apiService.getProfile(userId);
        final profilePath = _extractAvatarPath(profileData);
        final resolvedUrl = _toFullImageUrl(profilePath);
        if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
          _avatarCache[userId] = resolvedUrl;
        }
        return resolvedUrl;
      } catch (e) {
        debugPrint('Failed to fetch avatar for $userId: $e');
        _avatarCache[userId] = null;
        return null;
      }
    });

    return FutureBuilder<String?>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _avatarLoadingCircle();
        }

        final resolvedUrl = snapshot.data ?? _avatarCache[userId];
        if (resolvedUrl != null &&
            resolvedUrl.isNotEmpty &&
            !_failedAvatarUrls.contains(resolvedUrl)) {
          return _avatarCircleFromUrl(resolvedUrl, displayName);
        }

        if (snapshot.hasError) {
          debugPrint('Avatar fetch error for $userId: ${snapshot.error}');
        }

        return _avatarFallbackCircle(displayName);
      },
    );
  }

  Widget _avatarCircleFromUrl(String avatarUrl, String? displayName) {
    return CircleAvatar(
      radius: 24,
      backgroundColor: Colors.grey[300],
      child: ClipOval(
        child: Image.network(
          avatarUrl,
          key: ValueKey(avatarUrl),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                      : null,
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            _failedAvatarUrls.add(avatarUrl);
            _avatarCache.removeWhere((key, value) => value == avatarUrl);
            debugPrint('Avatar load error for $avatarUrl: $error');
            return SizedBox.expand(child: _avatarInitial(displayName));
          },
        ),
      ),
    );
  }

  Widget _avatarFallbackCircle(String? displayName) {
    return CircleAvatar(
      radius: 24,
      backgroundColor: Colors.grey[300],
      child: _avatarInitial(displayName),
    );
  }

  Widget _avatarLoadingCircle() {
    return CircleAvatar(
      radius: 24,
      backgroundColor: Colors.grey[200],
      child: const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _avatarInitial(String? displayName) {
    final initial = _initialForDisplayName(displayName);
    return Center(
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.blue,
        ),
      ),
    );
  }

  String _initialForDisplayName(String? displayName) {
    final trimmed = displayName?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed[0].toUpperCase();
    }
    return 'U';
  }

  String? _formatTimestamp(dynamic timestamp) {
    DateTime? dateTime;
    if (timestamp is Timestamp) {
      dateTime = timestamp.toDate();
    } else if (timestamp is DateTime) {
      dateTime = timestamp;
    } else if (timestamp is int) {
      dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    } else if (timestamp is String) {
      dateTime = DateTime.tryParse(timestamp);
    }

    if (dateTime == null) return null;

    final now = DateTime.now();
    final isSameDay =
        dateTime.year == now.year &&
        dateTime.month == now.month &&
        dateTime.day == now.day;

    if (isSameDay) {
      final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
      final minute = dateTime.minute.toString().padLeft(2, '0');
      final suffix = dateTime.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $suffix';
    }

    final difference = now.difference(dateTime);
    if (difference.inDays < 7) {
      const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdayNames[dateTime.weekday - 1];
    }

    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final yearSuffix = dateTime.year == now.year
        ? ''
        : '/${dateTime.year.toString().substring(2)}';
    return '$day/$month$yearSuffix';
  }

  String _resolveUsernameForUserDoc(
    String userId,
    Map<String, dynamic> userData,
  ) {
    final override = _usernameOverrides[userId];
    if (override != null && override.trim().isNotEmpty) return override.trim();

    final name = (userData['username'] as String?)?.trim();
    if (name != null && name.isNotEmpty) return name;

    final displayName = _auth.currentUser?.uid == userId
        ? _auth.currentUser?.displayName
        : null;
    if (displayName != null && displayName.trim().isNotEmpty) {
      return displayName.trim();
    }

    return 'Unknown User';
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
