import 'package:flutter/material.dart';
import 'package:pay_go/services/notification_service.dart';
import 'package:pay_go/pages/chat_screen.dart';
import 'package:pay_go/pages/post_detail_page.dart';
import 'package:pay_go/pages/notifications_page.dart';

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

      default:
        print('Unknown notification type: $type');
    }
  }

  void _navigateToChat(String chatId) {
    // Extract otherUserId from chatId (format: userId1_userId2)
    final parts = chatId.split('_');
    if (parts.length != 2) {
      print('Invalid chatId format: $chatId');
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

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
