import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_service.dart';

void _log(String message) {
  if (kDebugMode) {
    debugPrint('NotificationService: $message');
  }
}

// Top-level function for background message handling
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  _log('Handling background message: ${message.messageId}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final StreamController<Map<String, dynamic>> _notificationClickController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get notificationClicks =>
      _notificationClickController.stream;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Request permission for iOS
      NotificationSettings settings = await _firebaseMessaging
          .requestPermission(
            alert: true,
            announcement: false,
            badge: true,
            carPlay: false,
            criticalAlert: false,
            provisional: false,
            sound: true,
          );

      _log('User granted permission: ${settings.authorizationStatus}');

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Set up background message handler
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _log('Got a message whilst in the foreground!');
        _log('Message data: ${message.data}');

        if (message.notification != null) {
          _log(
            'Message also contained a notification: ${message.notification}',
          );
          _showLocalNotification(message);
        }
      });

      // Handle notification clicks when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _log('A new onMessageOpenedApp event was published!');
        _handleNotificationClick(message.data);
      });

      // Check if app was opened from a terminated state via notification
      RemoteMessage? initialMessage = await _firebaseMessaging
          .getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationClick(initialMessage.data);
      }

      _initialized = true;
    } catch (e) {
      _log('Error initializing notifications: $e');
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null) {
          // Parse the payload and emit the notification click event
          try {
            final parts = response.payload!.split('|');
            if (parts.length >= 2) {
              _notificationClickController.add({
                'type': parts[0],
                'id': parts[1],
              });
            }
          } catch (e) {
            _log('Error parsing notification payload: $e');
          }
        }
      },
    );

    // Create notification channels for Android
    if (Platform.isAndroid) {
      final plugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      // Channel for chat messages
      const chatChannel = AndroidNotificationChannel(
        'chat_messages',
        'Chat Messages',
        description: 'Notifications for new chat messages',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      // Channel for social interactions (likes, comments)
      const socialChannel = AndroidNotificationChannel(
        'social_interactions',
        'Social Interactions',
        description: 'Notifications for likes and comments',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      // Channel for friend requests
      const friendRequestChannel = AndroidNotificationChannel(
        'friend_requests',
        'Friend Requests',
        description: 'Notifications for friend requests',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      // Channel for incoming calls
      const callChannel = AndroidNotificationChannel(
        'incoming_calls',
        'Incoming Calls',
        description: 'Notifications for incoming calls',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );

      await plugin?.createNotificationChannel(chatChannel);
      await plugin?.createNotificationChannel(socialChannel);
      await plugin?.createNotificationChannel(friendRequestChannel);
      await plugin?.createNotificationChannel(callChannel);
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    // DON'T show notification if the current user is the sender
    final currentUserId = getCurrentUserId();
    final senderId = message.data['senderId'] as String?;

    if (currentUserId != null &&
        senderId != null &&
        currentUserId == senderId) {
      _log('Skipping notification: current user is the sender');
      return;
    }

    // Determine notification type and channel
    final notificationType = message.data['type'] ?? 'chat_message';
    String channelId;
    String channelName;

    switch (notificationType) {
      case 'friend_request':
        channelId = 'friend_requests';
        channelName = 'Friend Requests';
        break;
      case 'like':
      case 'comment':
        channelId = 'social_interactions';
        channelName = 'Social Interactions';
        break;
      case 'call':
        channelId = 'incoming_calls';
        channelName = 'Incoming Calls';
        break;
      case 'chat_message':
      default:
        channelId = 'chat_messages';
        channelName = 'Chat Messages';
    }

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: 'Notifications for $channelName',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Create payload from message data
    String? payload;
    final type = message.data['type'];

    if (type == 'chat_message' && message.data.containsKey('chatId')) {
      payload = '$type|${message.data['chatId']}';
    } else if (type == 'friend_request' &&
        message.data.containsKey('requestId')) {
      payload = '$type|${message.data['requestId']}';
    } else if (type == 'like' && message.data.containsKey('postId')) {
      payload = '$type|${message.data['postId']}';
    } else if (type == 'comment' && message.data.containsKey('postId')) {
      payload = '$type|${message.data['postId']}';
    } else if (type == 'call' && message.data.containsKey('callId')) {
      payload = '$type|${message.data['callId']}';
    }

    // Extract sender name from data or notification title
    String notificationTitle =
        message.notification?.title ?? 'New Notification';
    final senderName = message.data['senderName'] as String?;
    final senderUsername = message.data['senderUsername'] as String?;

    // If backend provides senderName/senderUsername, use it; otherwise use notification title
    if (senderName != null && senderName.isNotEmpty) {
      notificationTitle = senderName;
    } else if (senderUsername != null && senderUsername.isNotEmpty) {
      notificationTitle = senderUsername;
    }

    await _localNotifications.show(
      message.hashCode,
      notificationTitle,
      message.notification?.body ?? '',
      details,
      payload: payload,
    );
  }

  void _handleNotificationClick(Map<String, dynamic> data) {
    _log('Notification clicked with data: $data');
    _notificationClickController.add(data);
  }

  Future<String?> getToken() async {
    try {
      String? token = await _firebaseMessaging.getToken();
      _log('FCM Token: $token');
      return token;
    } catch (e) {
      _log('Error getting FCM token: $e');
      return null;
    }
  }

  Future<void> sendTokenToServer(ApiService apiService) async {
    try {
      String? token = await getToken();
      if (token != null) {
        // Send token to your backend
        await apiService.updateFCMToken(token);
        _log('FCM token sent to server');
      }
    } catch (e) {
      _log('Error sending FCM token to server: $e');
    }
  }

  String? getCurrentUserId() {
    return FirebaseAuth.instance.currentUser?.uid;
  }

  Future<void> deleteToken() async {
    try {
      await _firebaseMessaging.deleteToken();
      _log('FCM token deleted');
    } catch (e) {
      _log('Error deleting FCM token: $e');
    }
  }

  void dispose() {
    _notificationClickController.close();
  }
}
