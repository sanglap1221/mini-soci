import 'dart:async';

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

enum _FriendRequestResolution { accepted, declined }

class _NotificationsPageState extends State<NotificationsPage> {
  final _apiService = ApiService();
  List<Map<String, dynamic>> _notifications = const [];
  String? _errorMessage;
  bool _isLoading = false;
  final Set<String> _actionInProgress = <String>{};
  final Map<String, _FriendRequestResolution> _friendRequestResolutions =
      <String, _FriendRequestResolution>{};
  final Set<String> _resolutionFetchInProgress = <String>{};

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
      final idSet = notifications
          .map((item) => item['id'])
          .whereType<String>()
          .toSet();
      if (!mounted) return;
      setState(() {
        _friendRequestResolutions.removeWhere((key, _) => !idSet.contains(key));
        _notifications = notifications;
        _isLoading = false;
      });
      if (notifications.isNotEmpty) {
        unawaited(_prefetchFriendRequestResolutions(notifications));
      }
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

  Future<void> _prefetchFriendRequestResolutions(
    List<Map<String, dynamic>> notifications,
  ) async {
    final futures = <Future<void>>[];
    for (final notification in notifications) {
      final type = _readString(notification, 'type')?.toLowerCase();
      final notificationId = _readString(notification, 'id');
      final fromUserId = _readString(notification, 'fromUserId');
      if (type == 'friend_request' &&
          notificationId != null &&
          fromUserId != null &&
          !_friendRequestResolutions.containsKey(notificationId) &&
          !_resolutionFetchInProgress.contains(notificationId)) {
        _resolutionFetchInProgress.add(notificationId);
        futures.add(_fetchFriendRequestResolution(notificationId, fromUserId));
      }
    }

    if (futures.isEmpty) {
      return;
    }

    await Future.wait(futures);
  }

  Future<void> _fetchFriendRequestResolution(
    String notificationId,
    String userId,
  ) async {
    try {
      final summary = await _apiService.getRelationshipSummary(
        userId,
        forceRefresh: true,
      );
      final resolution = _mapRelationshipStatusToResolution(summary.status);
      if (!mounted) return;
      setState(() {
        if (resolution == null) {
          _friendRequestResolutions.remove(notificationId);
        } else {
          _friendRequestResolutions[notificationId] = resolution;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _friendRequestResolutions.remove(notificationId);
      });
    } finally {
      _resolutionFetchInProgress.remove(notificationId);
    }
  }

  _FriendRequestResolution? _mapRelationshipStatusToResolution(
    RelationshipStatus status,
  ) {
    switch (status) {
      case RelationshipStatus.friends:
        return _FriendRequestResolution.accepted;
      case RelationshipStatus.none:
        return _FriendRequestResolution.declined;
      default:
        return null;
    }
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
      _removeNotificationLocally(notificationId);
      _showSnackBar('Friend request accepted.');
    } catch (e) {
      _showSnackBar('Failed to accept friend request: $e');
    } finally {
      if (mounted) {
        if (_actionInProgress.contains(notificationId)) {
          setState(() {
            _actionInProgress.remove(notificationId);
          });
        }
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
      _removeNotificationLocally(notificationId);
      _showSnackBar('Friend request declined.');
    } catch (e) {
      _showSnackBar('Failed to decline request: $e');
    } finally {
      if (mounted) {
        if (_actionInProgress.contains(notificationId)) {
          setState(() {
            _actionInProgress.remove(notificationId);
          });
        }
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

  void _removeNotificationLocally(String notificationId) {
    setState(() {
      _notifications = _notifications
          .where((item) => item['id'] != notificationId)
          .toList(growable: false);
      _friendRequestResolutions.remove(notificationId);
      _resolutionFetchInProgress.remove(notificationId);
      _actionInProgress.remove(notificationId);
    });
  }

  Future<bool?> _confirmDeleteNotification(String notificationId) async {
    try {
      await _apiService.deleteNotification(notificationId);
      return true;
    } catch (e) {
      _showSnackBar('Failed to delete notification: $e');
      return false;
    }
  }

  Widget _buildDeleteBackground() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.redAccent,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.delete_outline, color: Colors.white),
          SizedBox(width: 8),
          Text(
            'Delete',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
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
        final notificationId = _readString(notification, 'id');
        if (notificationId == null) {
          return _buildNotificationCard(notification);
        }

        return Dismissible(
          key: ValueKey(notificationId),
          direction: DismissDirection.endToStart,
          background: Container(),
          secondaryBackground: _buildDeleteBackground(),
          confirmDismiss: (_) => _confirmDeleteNotification(notificationId),
          onDismissed: (_) {
            if (!mounted) return;
            _removeNotificationLocally(notificationId);
            _showSnackBar('Notification deleted.');
          },
          child: _buildNotificationCard(notification),
        );
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
    final payload = _readMap(notification, 'payload');
    final message =
        notification['message'] as String? ??
        _defaultMessage(type: type, fromUserName: fromName, payload: payload);
    final secondaryText = _secondaryDetail(type: type, payload: payload);

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
                        if (secondaryText != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            secondaryText,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Colors.grey[700],
                                  fontStyle: FontStyle.italic,
                                ),
                          ),
                        ],
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
      final lower = url.toLowerCase();
      final isAbsolute =
          lower.startsWith('http://') || lower.startsWith('https://');
      final resolvedUrl = isAbsolute ? url : ApiService().getFullImageUrl(url);
      return ClipOval(
        child: CachedNetworkImage(
          cacheManager: AppCacheManagers.imageCache,
          imageUrl: resolvedUrl,
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

    final resolution = notificationId == null
        ? null
        : _friendRequestResolutions[notificationId];

    if (resolution == _FriendRequestResolution.accepted) {
      return _buildFriendRequestResolvedRow(notification, accepted: true);
    }

    if (resolution == _FriendRequestResolution.declined) {
      return _buildFriendRequestResolvedRow(notification, accepted: false);
    }

    final fromUserId = _readString(notification, 'fromUserId');
    if (notificationId != null &&
        fromUserId != null &&
        !_friendRequestResolutions.containsKey(notificationId) &&
        !_resolutionFetchInProgress.contains(notificationId)) {
      _resolutionFetchInProgress.add(notificationId);
      unawaited(_fetchFriendRequestResolution(notificationId, fromUserId));
    }

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

  Widget _buildFriendRequestResolvedRow(
    Map<String, dynamic> notification, {
    required bool accepted,
  }) {
    final alreadyRead = (notification['isRead'] as bool?) == true;
    final color = accepted ? Colors.green : Colors.orange;
    final icon = accepted ? Icons.check_circle : Icons.cancel_outlined;
    final label = accepted
        ? 'Friend request already accepted'
        : 'Friend request already handled';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        TextButton(
          onPressed: alreadyRead ? null : () => _handleMarkAsRead(notification),
          child: Text(alreadyRead ? 'Read' : 'Mark as read'),
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

  Map<String, dynamic>? _readMap(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, val) => MapEntry('$key', val));
    }
    return null;
  }

  String? _secondaryDetail({
    required String type,
    Map<String, dynamic>? payload,
  }) {
    switch (type) {
      case 'post_comment':
      case 'comment':
        final preview = _readPayloadString(payload, 'commentPreview');
        if (preview != null && preview.isNotEmpty) {
          return '"$preview"';
        }
        return null;
      case 'message':
        final preview =
            _readPayloadString(payload, 'messagePreview') ??
            _readPayloadString(payload, 'textPreview');
        if (preview != null && preview.isNotEmpty) {
          return preview;
        }
        return null;
      default:
        return null;
    }
  }

  String? _readPayloadString(Map<String, dynamic>? payload, String key) {
    final value = payload?[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  String _defaultMessage({
    required String type,
    required String fromUserName,
    Map<String, dynamic>? payload,
  }) {
    switch (type) {
      case 'friend_request':
        return '$fromUserName sent you a friend request';
      case 'friend_accept':
      case 'friend_request_accepted':
        return '$fromUserName accepted your friend request';
      case 'message':
        return '$fromUserName sent you a message';
      case 'like':
      case 'post_like':
        return '$fromUserName liked your post';
      case 'comment':
      case 'post_comment':
        return '$fromUserName commented on your post';
      default:
        return '$fromUserName sent a notification';
    }
  }
}
