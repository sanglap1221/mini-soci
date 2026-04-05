import 'package:flutter/material.dart';
import 'package:pay_go/services/notification_service.dart';
import 'package:pay_go/pages/chat_screen.dart';
import 'package:pay_go/pages/post_detail_page.dart';
import 'package:pay_go/pages/notifications_page.dart';
import 'package:pay_go/pages/call_screen.dart';

class NotificationHandler extends StatefulWidget {
  final Widget child;

  const NotificationHandler({super.key, required this.child});

  @override
  State<NotificationHandler> createState() => _NotificationHandlerState();
}

class _NotificationHandlerState extends State<NotificationHandler> {
  @override
  void initState() {
    super.initState();
    _setupNotificationListener();
  }

  void _setupNotificationListener() {
    NotificationService().notificationClicks.listen((data) {
      _handleNotificationClick(data);
    });
  }

  void _handleNotificationClick(Map<String, dynamic> data) {
    final type = data['type'];
    final id = data['id'];

    if (!mounted) return;

    switch (type) {
      case 'chat_message':
        // Navigate to chat page
        _navigateToChat(id);
        break;

      case 'friend_request':
        // Navigate to friend requests page
        _navigateToFriendRequests();
        break;

      case 'like':
      case 'comment':
        // Navigate to post detail page
        _navigateToPost(id);
        break;

      case 'call':
        // Navigate to call screen
        _navigateToCall(id);
        break;

      default:
        debugPrint('Unknown notification type: $type');
    }
  }

  void _navigateToChat(String chatId) {
    // Extract otherUserId from chatId (format: userId1_userId2)
    final parts = chatId.split('_');
    if (parts.length != 2) {
      debugPrint('Invalid chatId format: $chatId');
      return;
    }

    // Determine which ID is the other user
    final currentUserId = NotificationService().getCurrentUserId();
    final otherUserId = parts[0] == currentUserId ? parts[1] : parts[0];

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            ChatScreen(chatId: chatId, otherUserId: otherUserId),
      ),
    );
  }

  void _navigateToFriendRequests() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const NotificationsPage()));
  }

  void _navigateToPost(String postId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => PostDetailPage(postId: postId)),
    );
  }

  void _navigateToCall(String callId) {
    // For call notifications, since the call might be ongoing or missed,
    // we can navigate to the call screen or perhaps just show a message
    // For now, let's navigate to the call screen assuming it can handle the callId
    // In a real scenario, you might want to check if the call is still active
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CallScreen(
          callId: callId,
          callerId: '', // Placeholder, ideally fetch from call data
          receiverId: NotificationService().getCurrentUserId() ?? '',
          isInitiator: false,
          otherUserName: 'Unknown Caller',
          isVideoCall: false,
          otherUserAvatarUrl: null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
