import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pay_go/services/api_service.dart';
import 'package:pay_go/services/app_cache_managers.dart';
import 'package:pay_go/utils/time_formatter.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _apiService = ApiService();
  List<Map<String, dynamic>> _notifications = const [];
  String? _errorMessage;
  bool _isLoading = false;
  final Set<String> _actionInProgress = <String>{};

  @override
  void initState() {
    super.initState();
    _loadNotifications(initial: true);
  }

  Future<void> _loadNotifications({bool initial = false}) async {
    if (initial) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final notifications = await _apiService.getNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshNotifications() async {
    await _loadNotifications(initial: true);
  }

  Future<void> _handleAcceptRequest(Map<String, dynamic> notification) async {
    final requestId =
        _readString(notification, 'requestId') ??
        _readNestedString(notification, ['payload', 'requestId']);
    final notificationId = _readString(notification, 'id');

    if (requestId == null || notificationId == null) {
      _showSnackBar('Unable to accept this request. Missing metadata.');
      return;
    }

    setState(() {
      _actionInProgress.add(notificationId);
    });

    try {
      await _apiService.acceptFriendRequest(requestId);
      await _apiService.markNotificationAsRead(notificationId);
      if (!mounted) return;
      setState(() {
        _notifications = _notifications
            .where((item) => item['id'] != notificationId)
            .toList(growable: false);
      });
      _showSnackBar('Friend request accepted.');
    } catch (e) {
      _showSnackBar('Failed to accept friend request: $e');
    } finally {
      if (mounted) {
        setState(() {
          _actionInProgress.remove(notificationId);
        });
      }
    }
  }

  Future<void> _handleDeclineRequest(Map<String, dynamic> notification) async {
    final requestId =
        _readString(notification, 'requestId') ??
        _readNestedString(notification, ['payload', 'requestId']);
    final notificationId = _readString(notification, 'id');

    if (requestId == null || notificationId == null) {
      _showSnackBar('Unable to decline this request. Missing metadata.');
      return;
    }

    setState(() {
      _actionInProgress.add(notificationId);
    });

    try {
      await _apiService.declineFriendRequest(requestId);
      await _apiService.markNotificationAsRead(notificationId);
      if (!mounted) return;
      setState(() {
        _notifications = _notifications
            .where((item) => item['id'] != notificationId)
            .toList(growable: false);
      });
      _showSnackBar('Friend request declined.');
    } catch (e) {
      _showSnackBar('Failed to decline request: $e');
    } finally {
      if (mounted) {
        setState(() {
          _actionInProgress.remove(notificationId);
        });
      }
    }
  }

  Future<void> _handleMarkAsRead(Map<String, dynamic> notification) async {
    final notificationId = _readString(notification, 'id');
    if (notificationId == null) {
      return;
    }

    if ((notification['isRead'] as bool?) == true) {
      return;
    }

    try {
      await _apiService.markNotificationAsRead(notificationId);
      if (!mounted) return;
      setState(() {
        final index = _notifications.indexWhere(
          (n) => n['id'] == notificationId,
        );
        if (index != -1) {
          final updated = Map<String, dynamic>.from(_notifications[index])
            ..['isRead'] = true;
          _notifications = List<Map<String, dynamic>>.from(_notifications)
            ..[index] = updated;
        }
      });
    } catch (e) {
      _showSnackBar('Failed to mark as read: $e');
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      await _apiService.markAllNotificationsAsRead();
      if (!mounted) return;
      setState(() {
        _notifications = _notifications
            .map((item) => <String, dynamic>{...item, 'isRead': true})
            .toList(growable: false);
      });
      _showSnackBar('All notifications marked as read');
    } catch (e) {
      _showSnackBar('Failed to mark all as read: $e');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading
                ? null
                : () => _loadNotifications(initial: true),
            tooltip: 'Reload notifications',
          ),
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Mark all as read',
            onPressed: _notifications.any((n) => (n['isRead'] as bool?) != true)
                ? _markAllAsRead
                : null,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshNotifications,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 180),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    return _buildNotificationList();
  }

  Widget _buildErrorState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(
          Icons.notifications_off_outlined,
          size: 64,
          color: Colors.grey[400],
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Unable to load notifications',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton(
            onPressed: () => _loadNotifications(initial: true),
            child: const Text('Try Again'),
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationList() {
    if (_notifications.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 160),
          Icon(Icons.notifications_none_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Center(child: Text('No notifications yet')),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _notifications.length,
      itemBuilder: (context, index) {
        final notification = _notifications[index];
        return _buildNotificationCard(notification);
      },
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> notification) {
    final isRead = (notification['isRead'] as bool?) ?? false;
    final createdAt = _formatTimestamp(notification['createdAt']);
    final type = (_readString(notification, 'type') ?? 'notification')
        .toLowerCase();
    final fromName =
        _readString(notification, 'fromUserName') ??
        _readNestedString(notification, ['fromUser', 'username']) ??
        'Someone';
    final message =
        notification['message'] as String? ??
        _defaultMessage(type: type, fromUserName: fromName);

    final avatarUrl =
        _readString(notification, 'fromUserAvatar') ??
        _readNestedString(notification, ['fromUser', 'profilePicUrl']);

    final accentColor = Theme.of(context).colorScheme.primary;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: isRead ? 1 : 3,
      child: InkWell(
        onTap: () => _handleMarkAsRead(notification),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAvatar(avatarUrl, fromName, accentColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                fontWeight: isRead
                                    ? FontWeight.w500
                                    : FontWeight.w600,
                              ),
                        ),
                        if (createdAt != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            createdAt,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.grey[600]),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!isRead)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              if (type == 'friend_request') ...[
                const SizedBox(height: 12),
                _buildFriendRequestActions(notification),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(String? url, String name, Color accentColor) {
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          cacheManager: AppCacheManagers.imageCache,
          imageUrl: ApiService().getFullImageUrl(url),
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          placeholder: (context, _) => _avatarPlaceholder(accentColor),
          errorWidget: (context, _, __) => _avatarFallback(name, accentColor),
        ),
      );
    }

    return _avatarFallback(name, accentColor);
  }

  Widget _avatarPlaceholder(Color accentColor) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
      ),
    );
  }

  Widget _avatarFallback(String name, Color accentColor) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: 22,
      backgroundColor: accentColor.withValues(alpha: 0.1),
      child: Text(
        initial,
        style: TextStyle(color: accentColor, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildFriendRequestActions(Map<String, dynamic> notification) {
    final notificationId = _readString(notification, 'id');
    final isProcessing =
        notificationId != null && _actionInProgress.contains(notificationId);

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isProcessing
                ? null
                : () => _handleAcceptRequest(notification),
            icon: const Icon(Icons.check),
            label: const Text('Accept'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isProcessing
                ? null
                : () => _handleDeclineRequest(notification),
            icon: const Icon(Icons.close),
            label: const Text('Decline'),
          ),
        ),
      ],
    );
  }

  String? _formatTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) {
      return formatTimestamp(value.toDate());
    }
    if (value is DateTime) {
      return formatTimestamp(value);
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return formatTimestamp(parsed);
      }
    }
    return null;
  }

  String? _readString(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  String? _readNestedString(Map<String, dynamic> map, List<String> path) {
    dynamic current = map;
    for (final segment in path) {
      if (current is Map<String, dynamic> && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return null;
      }
    }
    return current is String && current.isNotEmpty ? current : null;
  }

  String _defaultMessage({required String type, required String fromUserName}) {
    switch (type) {
      case 'friend_request':
        return '$fromUserName sent you a friend request';
      case 'friend_accept':
        return '$fromUserName accepted your friend request';
      case 'like':
        return '$fromUserName liked your post';
      case 'comment':
        return '$fromUserName commented on your post';
      default:
        return '$fromUserName sent a notification';
    }
  }
}
