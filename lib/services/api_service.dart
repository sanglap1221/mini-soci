import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'auth_token_provider.dart';
import 'app_cache_managers.dart';
import 'base_url_resolver.dart';

class ApiService {
  ApiService._internal()
    : _baseUrlResolver = BaseUrlResolver(),
      _authTokenProvider = AuthTokenProvider(),
      _apiCache = AppCacheManagers.apiCache,
      _firestore = FirebaseFirestore.instance {
    _log('ApiService singleton instance created');
  }

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  final BaseUrlResolver _baseUrlResolver;
  final AuthTokenProvider _authTokenProvider;
  final CacheManager _apiCache;
  final FirebaseFirestore _firestore;

  static const String _postsCacheKey = 'api.posts';

  String _profileCacheKey(String userId) => 'api.profile.$userId';
  String _commentsCacheKey(String postId) => 'api.comments.$postId';
  String _relationshipSummaryCacheKey(String userId) =>
      'api.relationship.summary.$userId';

  CollectionReference<Map<String, dynamic>> get _notificationsCollection =>
      _firestore.collection('notifications');

  Future<void> _enqueueNotification({
    required String toUserId,
    required String type,
    Map<String, dynamic>? payload,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw Exception('Not authenticated');
    }

    if (toUserId.isEmpty || toUserId == currentUser.uid) {
      return;
    }

    final fromDisplayName = currentUser.displayName;
    final fromPhotoUrl = currentUser.photoURL;

    final notificationData = <String, dynamic>{
      'fromUserId': currentUser.uid,
      'toUserId': toUserId,
      'type': type,
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
      'readAt': null,
      if (payload != null && payload.isNotEmpty) 'payload': payload,
      if (fromDisplayName != null && fromDisplayName.trim().isNotEmpty)
        'fromUserName': fromDisplayName.trim(),
      if (fromPhotoUrl != null && fromPhotoUrl.trim().isNotEmpty)
        'fromUserAvatar': fromPhotoUrl.trim(),
    };

    try {
      await _notificationsCollection.add(notificationData);
    } catch (error, stackTrace) {
      _log('Failed to enqueue notification ($type -> $toUserId): $error');
      _log(stackTrace.toString());
    }
  }

  Future<void> _maybeNotifyPostComment({
    required String postId,
    required String? postOwnerId,
    required dynamic response,
    required String commentText,
  }) async {
    if (postOwnerId == null || postOwnerId.isEmpty) {
      return;
    }

    final commenter = FirebaseAuth.instance.currentUser;
    if (commenter == null || commenter.uid == postOwnerId) {
      return;
    }

    final commentId = _extractCommentIdFromResponse(response);
    final trimmed = commentText.trim();
    final preview = trimmed.length > 120
        ? '${trimmed.substring(0, 117).trimRight()}...'
        : trimmed;

    final payload = <String, dynamic>{'postId': postId};
    if (commentId != null) {
      payload['commentId'] = commentId;
    }
    if (preview.isNotEmpty) {
      payload['commentPreview'] = preview;
    }

    await _enqueueNotification(
      toUserId: postOwnerId,
      type: 'post_comment',
      payload: payload,
    );
  }

  Future<void> _maybeNotifyPostLike({
    required String postId,
    required String? postOwnerId,
    required dynamic response,
  }) async {
    if (postOwnerId == null || postOwnerId.isEmpty) {
      return;
    }

    final liker = FirebaseAuth.instance.currentUser;
    if (liker == null || liker.uid == postOwnerId) {
      return;
    }

    final likeCount = _extractLikeCountFromResponse(response);
    final payload = <String, dynamic>{'postId': postId};
    if (likeCount != null) {
      payload['likeCount'] = likeCount;
    }

    await _enqueueNotification(
      toUserId: postOwnerId,
      type: 'post_like',
      payload: payload,
    );
  }

  String? _extractCommentIdFromResponse(dynamic response) {
    final root = _normalizeToMap(response);
    if (root == null) {
      return null;
    }

    final scopes = <Map<String, dynamic>>[];
    scopes.add(root);

    final data = root['data'];
    if (data is Map<String, dynamic>) {
      scopes.add(data);
    }

    final comment = root['comment'];
    if (comment is Map<String, dynamic>) {
      scopes.add(comment);
    }

    final raw = root['raw'];
    if (raw is Map<String, dynamic>) {
      scopes.add(raw);
    }

    for (final scope in scopes) {
      final candidates = [
        scope['id'],
        scope['_id'],
        scope['commentId'],
        scope['uuid'],
      ];
      for (final candidate in candidates) {
        if (candidate is String && candidate.isNotEmpty) {
          return candidate;
        }
        if (candidate is int) {
          return candidate.toString();
        }
      }
    }

    return null;
  }

  int? _extractLikeCountFromResponse(dynamic response) {
    final root = _normalizeToMap(response);
    if (root == null) {
      return null;
    }

    final scopes = <Map<String, dynamic>>[];
    scopes.add(root);

    final data = root['data'];
    if (data is Map<String, dynamic>) {
      scopes.add(data);
    }

    final meta = root['meta'] ?? root['metadata'];
    if (meta is Map<String, dynamic>) {
      scopes.add(meta);
    }

    final payload = root['payload'];
    if (payload is Map<String, dynamic>) {
      scopes.add(payload);
    }

    final raw = root['raw'];
    if (raw is Map<String, dynamic>) {
      scopes.add(raw);
    }

    for (final scope in scopes) {
      final candidates = [
        scope['likeCount'],
        scope['likes'],
        scope['likesCount'],
        scope['totalLikes'],
      ];
      for (final candidate in candidates) {
        final parsed = _tryParseInt(candidate);
        if (parsed != null) {
          return parsed;
        }
      }
    }

    return null;
  }

  Future<void> initialize({String? overrideBaseUrl}) async {
    await _baseUrlResolver.initialize(overrideBaseUrl: overrideBaseUrl);
  }

  void overrideBaseUrl(String baseUrl) =>
      _baseUrlResolver.overrideBaseUrl(baseUrl);

  String get baseUrl => _baseUrlResolver.baseUrl;
  String get serverBaseUrl => _baseUrlResolver.serverBaseUrl;

  String getFullImageUrl(String relativePath) =>
      _baseUrlResolver.getFullImageUrl(relativePath);

  Future<String?> getFirebaseToken({bool forceRefresh = false}) =>
      _authTokenProvider.getToken(forceRefresh: forceRefresh);

  Future<String> _prepareBaseUrl() => _baseUrlResolver.prepareBaseUrl();

  Future<Map<String, dynamic>> createPost(
    String caption,
    File mediaFile, {
    required PostMediaType mediaType,
  }) async {
    final token = await getFirebaseToken();
    if (token == null) throw Exception('Not authenticated');
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) throw Exception('Not authenticated');
    final resolvedBaseUrl = await _prepareBaseUrl();

    final ext = mediaFile.path.split('.').last.toLowerCase();

    if (mediaType == PostMediaType.image) {
      if (!['jpg', 'jpeg', 'png'].contains(ext)) {
        throw Exception('Only JPG and PNG images are allowed');
      }
    } else {
      if (!['mp4', 'mov', 'avi'].contains(ext)) {
        throw Exception('Only MP4, MOV, or AVI videos are allowed');
      }
    }

    await getProfile(currentUser.uid);

    final fieldName = mediaType == PostMediaType.image ? 'image' : 'video';
    final mediaTypeHeader = mediaType == PostMediaType.image
        ? (ext == 'png'
              ? MediaType('image', 'png')
              : MediaType('image', 'jpeg'))
        : MediaType('video', ext == 'mov' ? 'quicktime' : ext);

    final request =
        http.MultipartRequest('POST', Uri.parse('$resolvedBaseUrl/posts'))
          ..headers['Authorization'] = 'Bearer $token'
          ..headers['Accept'] = 'application/json'
          ..fields['caption'] = caption.trim().isEmpty ? ' ' : caption.trim()
          ..files.add(
            await http.MultipartFile.fromPath(
              fieldName,
              mediaFile.path,
              contentType: mediaTypeHeader,
            ),
          );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    _log('Create Post Response Status: ${response.statusCode}');
    _log('Create Post Response Body: ${response.body}');

    if (response.statusCode == 201) {
      final decoded = json.decode(response.body) as Map<String, dynamic>;
      unawaited(_invalidateCacheKey(_postsCacheKey));
      return decoded;
    }

    throw Exception(
      'Failed to create post: ${response.statusCode} ${response.body}',
    );
  }

  Future<List<dynamic>> getPosts({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await _readCachedJson(_postsCacheKey);
      if (cached is List<dynamic>) {
        return sortPostsByNewest(List<dynamic>.from(cached));
      }
    }

    final result = await _authorizedRequest(_HttpMethod.get, '/posts');
    final data = result.json;
    if (data is List<dynamic>) {
      unawaited(_writeCacheEntry(_postsCacheKey, data));
      return sortPostsByNewest(data);
    }
    throw Exception('Unexpected response format for posts');
  }

  Future<List<dynamic>> getUserPosts(String userId) async {
    final result = await _authorizedRequest(
      _HttpMethod.get,
      '/users/$userId/posts',
    );
    final data = result.json;
    if (data is List<dynamic>) {
      return sortPostsByNewest(data);
    }
    throw Exception('Unexpected response format for user posts');
  }

  Future<Map<String, dynamic>> getProfile(
    String userId, {
    bool forceRefresh = false,
  }) async {
    final cacheKey = _profileCacheKey(userId);
    if (!forceRefresh) {
      final cached = await _readCachedJson(cacheKey);
      if (cached is Map<String, dynamic>) {
        return Map<String, dynamic>.from(cached);
      }
    }

    final result = await _authorizedRequest(
      _HttpMethod.get,
      '/users/$userId/profile',
      acceptedStatus: const [200, 404],
    );

    if (result.statusCode == 200) {
      final data = result.json;
      if (data is Map<String, dynamic>) {
        unawaited(_writeCacheEntry(cacheKey, data));
        return data;
      }
      throw Exception('Unexpected profile response format');
    }

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (result.statusCode == 404) {
      if (userId == currentUserId) {
        _log('Profile not found, creating new profile...');
        final createdProfile = await updateProfile(
          username:
              FirebaseAuth.instance.currentUser?.displayName ?? 'New User',
          bio: '',
        );
        unawaited(_writeCacheEntry(cacheKey, createdProfile));
        return createdProfile;
      }
      return <String, dynamic>{};
    }

    throw Exception(
      'Failed to load profile: ${result.statusCode} ${result.body}',
    );
  }

  Future<Map<String, dynamic>> updateProfile({
    required String username,
    String? bio,
  }) async {
    final result = await _authorizedRequest(
      _HttpMethod.put,
      '/users/me',
      jsonBody: {'username': username, 'bio': bio},
    );

    final data = result.json;
    if (data is Map<String, dynamic>) {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        unawaited(_writeCacheEntry(_profileCacheKey(userId), data));
      }
      return data;
    }
    throw Exception(
      'Failed to update profile: ${result.statusCode} ${result.body}',
    );
  }

  Future<RelationshipSummary> getRelationshipSummary(
    String userId, {
    bool forceRefresh = false,
  }) async {
    final cacheKey = _relationshipSummaryCacheKey(userId);
    if (!forceRefresh) {
      final cached = await _readCachedJson(cacheKey);
      final cachedSummary = _parseRelationshipSummary(cached);
      if (cachedSummary != null) {
        return cachedSummary;
      }
    }

    final result = await _authorizedRequest(
      _HttpMethod.get,
      '/friend/relationship/$userId',
    );

    final summary = _parseRelationshipSummary(result.json);
    if (summary == null) {
      throw Exception('Unexpected relationship summary format');
    }
    _cacheRelationshipSummary(userId, summary);
    return summary;
  }

  Future<RelationshipSummary> sendFriendRequest(String userId) async {
    final result = await _authorizedRequest(
      _HttpMethod.post,
      '/friend/request/$userId',
      acceptedStatus: const [200, 201, 409],
    );

    if (result.statusCode == 409) {
      RelationshipSummary? summary = _parseRelationshipSummary(result.json);
      if (summary == null) {
        try {
          summary = await getRelationshipSummary(userId, forceRefresh: true);
        } catch (e, stack) {
          _log('Failed to refresh summary after 409: $e');
          _log(stack.toString());
        }
      }

      summary ??= RelationshipSummary(
        status: RelationshipStatus.pendingIncoming,
        pendingRequestId: _extractPendingRequestId(result.json),
        followerCount: 0,
        followingCount: 0,
        friendCount: 0,
      );

      if (summary.status == RelationshipStatus.none) {
        summary = summary.copyWith(status: RelationshipStatus.pendingIncoming);
      }

      if (summary.pendingRequestId == null) {
        final pendingId = _extractPendingRequestId(result.json);
        if (pendingId != null) {
          summary = summary.copyWith(pendingRequestId: pendingId);
        }
      }

      _applyRelationshipMutations(userId, summary);
      return summary;
    }

    final pendingRequestId =
        _extractPendingRequestId(result.json) ??
        _extractPendingRequestId(result.body);

    final summary = await _resolveRelationshipFromMutation(
      result,
      fallbackUserId: userId,
      fallbackStatus: RelationshipStatus.pendingOutgoing,
      fallbackPendingRequestId: pendingRequestId,
    );

    final normalizedSummary =
        summary.status == RelationshipStatus.none && pendingRequestId != null
        ? summary.copyWith(
            status: RelationshipStatus.pendingOutgoing,
            pendingRequestId: pendingRequestId,
          )
        : summary.pendingRequestId == null && pendingRequestId != null
        ? summary.copyWith(pendingRequestId: pendingRequestId)
        : summary;

    _applyRelationshipMutations(userId, normalizedSummary);
    if (normalizedSummary.status == RelationshipStatus.pendingOutgoing &&
        normalizedSummary.pendingRequestId != null) {
      unawaited(
        _enqueueNotification(
          toUserId: userId,
          type: 'friend_request',
          payload: <String, dynamic>{
            'requestId': normalizedSummary.pendingRequestId,
            'status': normalizedSummary.status.name,
          },
        ),
      );
    }
    return normalizedSummary;
  }

  Future<RelationshipSummary> cancelFriendRequest(
    String requestId, {
    String? targetUserId,
  }) async {
    _ApiResponse result;
    try {
      result = await _authorizedRequest(
        _HttpMethod.post,
        '/friend/request/$requestId/cancel',
        acceptedStatus: const [200, 204],
      );
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (!message.contains('404') && !message.contains('cannot post')) {
        rethrow;
      }

      result = await _authorizedRequest(
        _HttpMethod.delete,
        '/friend/request/$requestId',
        acceptedStatus: const [200, 202, 204],
      );
    }

    final resolvedTargetUserId =
        _extractTargetUserId(result.json) ?? targetUserId;
    if (resolvedTargetUserId == null) {
      throw Exception('Missing target user id for cancel response');
    }

    final summary = await _resolveRelationshipFromMutation(
      result,
      fallbackUserId: resolvedTargetUserId,
      fallbackStatus: RelationshipStatus.none,
    );
    _applyRelationshipMutations(resolvedTargetUserId, summary);
    return summary;
  }

  Future<RelationshipSummary> acceptFriendRequest(
    String requestId, {
    String? targetUserId,
  }) async {
    final result = await _authorizedRequest(
      _HttpMethod.post,
      '/friend/request/$requestId/accept',
      acceptedStatus: const [200, 201],
    );

    final resolvedTargetUserId =
        _extractTargetUserId(result.json) ?? targetUserId;
    if (resolvedTargetUserId == null) {
      throw Exception('Missing target user id for accept response');
    }

    final summary = await _resolveRelationshipFromMutation(
      result,
      fallbackUserId: resolvedTargetUserId,
      fallbackStatus: RelationshipStatus.friends,
    );
    _applyRelationshipMutations(resolvedTargetUserId, summary);
    unawaited(
      _enqueueNotification(
        toUserId: resolvedTargetUserId,
        type: 'friend_request_accepted',
        payload: <String, dynamic>{
          'requestId': requestId,
          'status': summary.status.name,
        },
      ),
    );
    return summary;
  }

  Future<RelationshipSummary> declineFriendRequest(
    String requestId, {
    String? targetUserId,
  }) async {
    final result = await _authorizedRequest(
      _HttpMethod.post,
      '/friend/request/$requestId/decline',
      acceptedStatus: const [200, 201, 204],
    );

    final resolvedTargetUserId =
        _extractTargetUserId(result.json) ?? targetUserId;
    if (resolvedTargetUserId == null) {
      throw Exception('Missing target user id for decline response');
    }

    final summary = await _resolveRelationshipFromMutation(
      result,
      fallbackUserId: resolvedTargetUserId,
      fallbackStatus: RelationshipStatus.none,
    );
    _applyRelationshipMutations(resolvedTargetUserId, summary);
    unawaited(
      _enqueueNotification(
        toUserId: resolvedTargetUserId,
        type: 'friend_request_declined',
        payload: <String, dynamic>{
          'requestId': requestId,
          'status': summary.status.name,
        },
      ),
    );
    return summary;
  }

  Future<RelationshipSummary> unfriend(String userId) async {
    final result = await _authorizedRequest(
      _HttpMethod.delete,
      '/friend/$userId',
      acceptedStatus: const [200, 204],
    );

    final summary = await _resolveRelationshipFromMutation(
      result,
      fallbackUserId: userId,
      fallbackStatus: RelationshipStatus.none,
    );
    _applyRelationshipMutations(userId, summary);
    return summary;
  }

  /// Fetch notifications for the current user ordered by newest first.
  Future<List<Map<String, dynamic>>> getNotifications({
    int limit = 50,
    bool unreadOnly = false,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');

    Query<Map<String, dynamic>> query = _notificationsCollection.where(
      'toUserId',
      isEqualTo: uid,
    );

    if (unreadOnly) {
      query = query.where('isRead', isEqualTo: false);
    }

    query = query.orderBy('createdAt', descending: true).limit(limit);

    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
        .toList(growable: false);
  }

  /// Mark a single notification as read for the current user.
  Future<void> markNotificationAsRead(String notificationId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');

    final docRef = _notificationsCollection.doc(notificationId);
    final docSnapshot = await docRef.get();
    final data = docSnapshot.data();

    if (!docSnapshot.exists || data == null) {
      return;
    }

    if ((data['toUserId'] as String?) != uid) {
      throw Exception("Not authorized to update this notification");
    }

    await docRef.update(<String, dynamic>{
      'isRead': true,
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  /// Mark all unread notifications as read for the current user.
  Future<void> markAllNotificationsAsRead() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');

    final unreadQuery = await _notificationsCollection
        .where('toUserId', isEqualTo: uid)
        .where('isRead', isEqualTo: false)
        .limit(100)
        .get();

    if (unreadQuery.docs.isEmpty) {
      return;
    }

    final batch = _firestore.batch();
    for (final doc in unreadQuery.docs) {
      batch.update(doc.reference, <String, dynamic>{
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  /// Permanently delete a notification owned by the current user.
  Future<void> deleteNotification(String notificationId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');

    final docRef = _notificationsCollection.doc(notificationId);
    final snapshot = await docRef.get();
    final data = snapshot.data();

    if (!snapshot.exists || data == null) {
      return;
    }

    if ((data['toUserId'] as String?) != uid) {
      throw Exception('Not authorized to delete this notification');
    }

    await docRef.delete();
  }

  /// Fetch incoming friend requests for the authenticated user.
  ///
  /// Assumes the backend exposes an endpoint that returns a list of pending
  /// friend requests addressed to the current user. Each item should be a
  /// JSON object containing at least: `id` (request id), `fromUserId`,
  /// `fromUser` or `author` (author metadata), and `createdAt`.
  Future<List<Map<String, dynamic>>> getIncomingFriendRequests() async {
    final result = await _authorizedRequest(
      _HttpMethod.get,
      '/friend/requests/received',
      acceptedStatus: const [200],
    );

    final data = result.json;
    if (data is List) {
      return List<Map<String, dynamic>>.from(
        data.map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{}),
      );
    }

    // If the backend wraps the list in a `data` or `items` field, try to
    // normalize that here.
    if (data is Map<String, dynamic>) {
      final items = data['items'] ?? data['data'] ?? data['requests'];
      if (items is List) {
        return List<Map<String, dynamic>>.from(
          items.map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{}),
        );
      }
    }

    return <Map<String, dynamic>>[];
  }

  /// Fetch friends list for a specific user.
  ///
  /// Returns a list of friends with their basic information.
  Future<List<Map<String, dynamic>>> getFriends(String userId) async {
    final result = await _authorizedRequest(
      _HttpMethod.get,
      '/friend/friends/$userId',
      acceptedStatus: const [200],
    );

    final data = result.json;

    // Backend returns { friends: [...], count: number }
    if (data is Map<String, dynamic>) {
      final friends = data['friends'];
      if (friends is List) {
        return List<Map<String, dynamic>>.from(
          friends.map(
            (e) => e is Map<String, dynamic> ? e : <String, dynamic>{},
          ),
        );
      }
    }

    // Fallback: if data is directly a list
    if (data is List) {
      return List<Map<String, dynamic>>.from(
        data.map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{}),
      );
    }

    return <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> updateProfilePicture(File imageFile) async {
    final token = await getFirebaseToken();
    if (token == null) throw Exception('Not authenticated');

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) throw Exception('Not authenticated');
    final resolvedBaseUrl = await _prepareBaseUrl();

    final ext = imageFile.path.toLowerCase().split('.').last;
    if (!['jpg', 'jpeg', 'png'].contains(ext)) {
      throw Exception('Only JPG and PNG images are allowed');
    }

    _log('Uploading profile picture...');

    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('$resolvedBaseUrl/users/$userId/profile-pic'),
          )
          ..headers['Authorization'] = 'Bearer $token'
          ..headers['Accept'] = 'application/json'
          ..files.add(
            await http.MultipartFile.fromPath(
              'profilePic',
              imageFile.path,
              contentType: ext == 'png'
                  ? MediaType('image', 'png')
                  : MediaType('image', 'jpeg'),
            ),
          );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    _log('Upload Profile Picture Response Status: ${response.statusCode}');
    _log('Upload Profile Picture Response Body: ${response.body}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      unawaited(_writeCacheEntry(_profileCacheKey(userId), data));
      return data;
    }

    throw Exception(
      'Failed to upload profile picture: ${response.statusCode} ${response.body}',
    );
  }

  Future<void> deleteProfilePicture() async {
    await _authorizedRequest(
      _HttpMethod.delete,
      '/users/${FirebaseAuth.instance.currentUser?.uid}/profile-pic',
      acceptedStatus: const [200, 204],
      parseJson: false,
    );
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      unawaited(_invalidateCacheKey(_profileCacheKey(userId)));
    }
  }

  Future<void> updateFCMToken(String token) async {
    try {
      await _authorizedRequest(
        _HttpMethod.put,
        '/users/fcm-token',
        acceptedStatus: const [200, 201],
        jsonBody: {'fcmToken': token},
        parseJson: false,
      );
      _log('FCM token updated successfully');
    } catch (e) {
      _log('Error updating FCM token: $e');
      rethrow;
    }
  }

  /// Send a chat message through backend API to trigger push notifications
  Future<Map<String, dynamic>> sendChatMessage({
    required String chatId,
    required String recipientUserId,
    required String message,
  }) async {
    try {
      final result = await _authorizedRequest(
        _HttpMethod.post,
        '/chat/messages',
        acceptedStatus: const [200, 201],
        jsonBody: {
          'chatId': chatId,
          'recipientUserId': recipientUserId,
          'message': message,
        },
        parseJson: true,
      );
      _log('Chat message sent successfully');
      return result.json ?? {};
    } catch (e) {
      _log('Error sending chat message: $e');
      rethrow;
    }
  }

  /// Search for users by name or username
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      final result = await _authorizedRequest(
        _HttpMethod.get,
        '/search/users',
        queryParameters: {'query': query.trim()},
        acceptedStatus: const [200],
        parseJson: true,
      );

      final data = result.json;
      if (data == null) return [];

      // Handle different response formats
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      } else if (data is Map && data['users'] != null) {
        final users = data['users'];
        if (users is List) {
          return users.cast<Map<String, dynamic>>();
        }
      }

      return [];
    } catch (e) {
      _log('Error searching users: $e');
      rethrow;
    }
  }

  Future<void> deletePost(String postId) async {
    final result = await _authorizedRequest(
      _HttpMethod.delete,
      '/posts/$postId',
      acceptedStatus: const [200],
      parseJson: false,
    );
    _log('The post is deleted (${result.statusCode})');
    unawaited(_invalidateCacheKey(_postsCacheKey));
  }

  Future<Map<String, dynamic>> likePost(
    String postId, {
    String? postOwnerId,
  }) async {
    final result = await _authorizedRequest(
      _HttpMethod.post,
      '/posts/$postId/like',
      acceptedStatus: const [200, 201],
    );

    final data = result.json;
    unawaited(
      _maybeNotifyPostLike(
        postId: postId,
        postOwnerId: postOwnerId,
        response: data,
      ),
    );
    if (data is Map<String, dynamic>) {
      unawaited(_invalidateCacheKey(_postsCacheKey));
      return data;
    }

    if (data == null) {
      unawaited(_invalidateCacheKey(_postsCacheKey));
      return <String, dynamic>{};
    }

    unawaited(_invalidateCacheKey(_postsCacheKey));
    return <String, dynamic>{'raw': data};
  }

  Future<Map<String, dynamic>> unlikePost(String postId) async {
    final result = await _authorizedRequest(
      _HttpMethod.delete,
      '/posts/$postId/like',
      acceptedStatus: const [200, 204],
    );

    final data = result.json;
    if (data == null) {
      unawaited(_invalidateCacheKey(_postsCacheKey));
      return <String, dynamic>{};
    }

    if (data is Map<String, dynamic>) {
      unawaited(_invalidateCacheKey(_postsCacheKey));
      return data;
    }

    unawaited(_invalidateCacheKey(_postsCacheKey));
    return <String, dynamic>{'raw': data};
  }

  Future<Map<String, dynamic>> getComments(
    String postId, {
    int? limit,
    String? cursor,
    bool forceRefresh = false,
  }) async {
    final queryParams = <String, String>{};
    if (limit != null) queryParams['limit'] = '$limit';
    if (cursor != null && cursor.isNotEmpty) queryParams['cursor'] = cursor;

    final shouldCache = cursor == null;
    final cacheKey = _commentsCacheKey(postId);
    if (shouldCache && !forceRefresh) {
      final cached = await _readCachedJson(cacheKey);
      if (cached is Map<String, dynamic>) {
        return Map<String, dynamic>.from(cached);
      }
    }

    final result = await _authorizedRequest(
      _HttpMethod.get,
      '/posts/$postId/comments',
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );

    final data = result.json;
    Map<String, dynamic> normalized;

    if (data == null) {
      normalized = <String, dynamic>{'items': <dynamic>[], 'total': 0};
    } else if (data is List) {
      final items = List<dynamic>.from(data);
      normalized = <String, dynamic>{
        'items': items,
        'total': items.length,
        'cursor': null,
      };
    } else if (data is Map<String, dynamic>) {
      normalized = Map<String, dynamic>.from(data);
      normalized.putIfAbsent('items', () => <dynamic>[]);
    } else {
      normalized = <String, dynamic>{'items': <dynamic>[], 'raw': data};
    }

    if (shouldCache) {
      unawaited(_writeCacheEntry(cacheKey, normalized));
    }

    return normalized;
  }

  Future<Map<String, dynamic>> addComment(
    String postId,
    String text, {
    String? postOwnerId,
  }) async {
    final result = await _authorizedRequest(
      _HttpMethod.post,
      '/posts/$postId/comments',
      jsonBody: {'text': text},
      acceptedStatus: const [200, 201],
    );

    final data = result.json;
    unawaited(
      _maybeNotifyPostComment(
        postId: postId,
        postOwnerId: postOwnerId,
        response: data,
        commentText: text,
      ),
    );
    if (data is Map<String, dynamic>) {
      unawaited(_invalidateCacheKey(_commentsCacheKey(postId)));
      return data;
    }

    if (data == null) {
      unawaited(_invalidateCacheKey(_commentsCacheKey(postId)));
      return <String, dynamic>{};
    }

    unawaited(_invalidateCacheKey(_commentsCacheKey(postId)));
    return <String, dynamic>{'raw': data};
  }

  Future<void> deleteComment(String commentId, {String? postId}) async {
    await _authorizedRequest(
      _HttpMethod.delete,
      '/comments/$commentId',
      acceptedStatus: const [200, 204],
      parseJson: false,
    );
    if (postId != null) {
      unawaited(_invalidateCacheKey(_commentsCacheKey(postId)));
    }
  }

  List<dynamic> sortPostsByNewest(List<dynamic> posts) {
    final sortedPosts = List<dynamic>.from(posts);
    sortedPosts.sort((a, b) => _parsePostDate(b).compareTo(_parsePostDate(a)));
    return sortedPosts;
  }

  DateTime _parsePostDate(dynamic post) {
    if (post is Map<String, dynamic>) {
      final createdAt = post['createdAt'];
      if (createdAt is String) {
        return DateTime.tryParse(createdAt)?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      }
      if (createdAt is int) {
        return DateTime.fromMillisecondsSinceEpoch(createdAt, isUtc: true);
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  Future<dynamic> _readCachedJson(String key) async {
    try {
      final fileInfo = await _apiCache.getFileFromCache(key);
      if (fileInfo == null) return null;
      if (DateTime.now().isAfter(fileInfo.validTill)) {
        unawaited(_apiCache.removeFile(key));
        return null;
      }
      final contents = await fileInfo.file.readAsString();
      return json.decode(contents);
    } catch (e) {
      _log('Failed to read cache for "$key": $e');
      return null;
    }
  }

  Future<void> _writeCacheEntry(String key, dynamic value) async {
    try {
      final encoded = json.encode(value);
      final bytes = Uint8List.fromList(utf8.encode(encoded));
      await _apiCache.putFile(key, bytes, fileExtension: 'json');
    } catch (e) {
      _log('Failed to write cache for "$key": $e');
    }
  }

  Future<void> _invalidateCacheKey(String key) async {
    try {
      await _apiCache.removeFile(key);
    } catch (e) {
      _log('Failed to invalidate cache for "$key": $e');
    }
  }

  void _cacheRelationshipSummary(String userId, RelationshipSummary summary) {
    unawaited(
      _writeCacheEntry(_relationshipSummaryCacheKey(userId), summary.toMap()),
    );
  }

  void _applyRelationshipMutations(
    String targetUserId,
    RelationshipSummary summary,
  ) {
    _cacheRelationshipSummary(targetUserId, summary);
    unawaited(_invalidateCacheKey(_profileCacheKey(targetUserId)));

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId != null) {
      unawaited(
        _invalidateCacheKey(_relationshipSummaryCacheKey(currentUserId)),
      );
      unawaited(_invalidateCacheKey(_profileCacheKey(currentUserId)));
    }
  }

  Future<RelationshipSummary?> _tryRefreshRelationshipSummary(
    String userId,
  ) async {
    try {
      return await getRelationshipSummary(userId, forceRefresh: true);
    } catch (e, stack) {
      _log('Failed to refresh relationship summary for $userId: $e');
      _log(stack.toString());
      return null;
    }
  }

  Future<RelationshipSummary> _resolveRelationshipFromMutation(
    _ApiResponse response, {
    required String fallbackUserId,
    RelationshipStatus? fallbackStatus,
    String? fallbackPendingRequestId,
  }) async {
    final parsed = _parseRelationshipSummary(response.json);
    if (parsed != null) {
      var adjusted = parsed;
      if (fallbackStatus != null &&
          adjusted.status == RelationshipStatus.none) {
        adjusted = adjusted.copyWith(status: fallbackStatus);
      }
      if (fallbackPendingRequestId != null &&
          adjusted.pendingRequestId == null) {
        adjusted = adjusted.copyWith(
          pendingRequestId: fallbackPendingRequestId,
        );
      }
      return adjusted;
    }

    final refreshed = await _tryRefreshRelationshipSummary(fallbackUserId);
    if (refreshed != null) {
      var adjusted = refreshed;
      if (fallbackStatus != null &&
          adjusted.status == RelationshipStatus.none) {
        adjusted = adjusted.copyWith(status: fallbackStatus);
      }
      if (fallbackPendingRequestId != null &&
          adjusted.pendingRequestId == null) {
        adjusted = adjusted.copyWith(
          pendingRequestId: fallbackPendingRequestId,
        );
      }
      return adjusted;
    }

    return RelationshipSummary(
      status: fallbackStatus ?? RelationshipStatus.none,
      pendingRequestId: fallbackPendingRequestId,
      followerCount: 0,
      followingCount: 0,
      friendCount: 0,
    );
  }

  static String? _extractTargetUserId(dynamic payload) {
    final map = _normalizeToMap(payload);
    if (map == null) return null;

    final direct = map['targetUserId'];
    if (direct is String && direct.isNotEmpty) {
      return direct;
    }

    final summary = map['summary'];
    if (summary is Map<String, dynamic>) {
      final nested = summary['targetUserId'];
      if (nested is String && nested.isNotEmpty) {
        return nested;
      }
    }

    return null;
  }

  static Map<String, dynamic>? _normalizeToMap(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      return payload;
    }
    if (payload is Map) {
      return payload.map((key, value) => MapEntry('$key', value));
    }
    if (payload is String && payload.isNotEmpty) {
      try {
        final decoded = json.decode(payload);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static String? _extractPendingRequestId(dynamic payload) {
    final map = _normalizeToMap(payload);
    if (map == null) {
      return null;
    }

    final direct =
        map['pendingRequestId'] ??
        map['requestId'] ??
        map['outgoingRequestId'] ??
        map['incomingRequestId'];
    if (direct is String && direct.isNotEmpty) {
      return direct;
    }

    final request = map['request'];
    if (request is Map<String, dynamic>) {
      final pending = request['id'] ?? request['_id'];
      if (pending is String && pending.isNotEmpty) {
        return pending;
      }
    }

    final data = map['data'];
    if (data is Map<String, dynamic>) {
      final nested = data['request'];
      if (nested is Map<String, dynamic>) {
        final pending = nested['id'] ?? nested['_id'];
        if (pending is String && pending.isNotEmpty) {
          return pending;
        }
      }
    }

    return null;
  }

  static RelationshipSummary? _parseRelationshipSummary(dynamic payload) {
    if (payload == null) return null;

    final map = _normalizeToMap(payload);
    if (map == null) return null;

    Map<String, dynamic> working = map;
    if (working['summary'] is Map<String, dynamic>) {
      working = Map<String, dynamic>.from(
        working['summary'] as Map<String, dynamic>,
      );
    } else if (working['data'] is Map<String, dynamic>) {
      working = Map<String, dynamic>.from(
        working['data'] as Map<String, dynamic>,
      );
    }

    final statusValue =
        working['status'] ?? working['relationshipStatus'] ?? working['state'];
    final status = _statusFromValue(statusValue);

    String? pendingId;
    final rawPending =
        working['pendingRequestId'] ??
        working['requestId'] ??
        working['outgoingRequestId'] ??
        working['incomingRequestId'];
    if (rawPending is String && rawPending.isNotEmpty) {
      pendingId = rawPending;
    }

    final followerCount =
        _tryParseInt(
          working['followerCount'] ??
              working['followers'] ??
              working['followersCount'],
        ) ??
        0;
    final followingCount =
        _tryParseInt(
          working['followingCount'] ??
              working['following'] ??
              working['followingsCount'],
        ) ??
        0;

    return RelationshipSummary(
      status: status,
      pendingRequestId: pendingId,
      followerCount: followerCount,
      followingCount: followingCount,
      friendCount:
          _tryParseInt(working['friendCount'] ?? working['friendsCount']) ?? 0,
    );
  }

  static int? _tryParseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static RelationshipStatus _statusFromValue(dynamic value) {
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      for (final status in RelationshipStatus.values) {
        final name = status.name.toLowerCase();
        if (normalized == name) {
          return status;
        }
        final compressedNormalized = normalized.replaceAll(
          RegExp(r'[_\s-]'),
          '',
        );
        final compressedName = name.replaceAll(RegExp(r'[_\s-]'), '');
        if (compressedNormalized == compressedName) {
          return status;
        }
      }
    }
    return RelationshipStatus.none;
  }

  static Future<_ApiResponse> _authorizedRequest(
    _HttpMethod method,
    String path, {
    Map<String, String>? queryParameters,
    Map<String, dynamic>? jsonBody,
    List<int> acceptedStatus = const [200],
    bool parseJson = true,
    bool isRetry = false,
  }) async {
    final instance = ApiService();
    final token = await instance.getFirebaseToken(forceRefresh: isRetry);
    if (token == null) throw Exception('Not authenticated');
    final base = await instance._prepareBaseUrl();

    final uri = Uri.parse('$base$path').replace(
      queryParameters: queryParameters == null || queryParameters.isEmpty
          ? null
          : queryParameters,
    );

    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      if (jsonBody != null) 'Content-Type': 'application/json',
    };

    http.Response response;
    switch (method) {
      case _HttpMethod.get:
        response = await http.get(uri, headers: headers);
        break;
      case _HttpMethod.post:
        response = await http.post(
          uri,
          headers: headers,
          body: jsonBody == null ? null : json.encode(jsonBody),
        );
        break;
      case _HttpMethod.put:
        response = await http.put(
          uri,
          headers: headers,
          body: jsonBody == null ? null : json.encode(jsonBody),
        );
        break;
      case _HttpMethod.delete:
        response = await http.delete(
          uri,
          headers: headers,
          body: jsonBody == null ? null : json.encode(jsonBody),
        );
        break;
    }

    _log('${method.name.toUpperCase()} $uri => ${response.statusCode}');
    if (response.body.isNotEmpty) {
      _log('Response Body: ${response.body}');
    }

    // Handle 401 Unauthorized - retry once with fresh token
    if (response.statusCode == 401 && !isRetry) {
      _log('Got 401, refreshing token and retrying...');
      
      // Small delay to ensure Firebase processes the token refresh
      await Future.delayed(const Duration(milliseconds: 100));
      
      return _authorizedRequest(
        method,
        path,
        queryParameters: queryParameters,
        jsonBody: jsonBody,
        acceptedStatus: acceptedStatus,
        parseJson: parseJson,
        isRetry: true,
      );
    }
    
    if (response.statusCode == 401 && isRetry) {
      _log('⚠️ Still got 401 after token refresh. Token might be invalid or backend issue.');
    }

    if (!acceptedStatus.contains(response.statusCode)) {
      throw Exception(
        'Request to $path failed: ${response.statusCode} ${response.body}',
      );
    }

    dynamic decoded;
    if (parseJson && response.body.isNotEmpty) {
      try {
        decoded = json.decode(response.body);
      } catch (e) {
        _log('Failed to decode JSON for $path: $e');
      }
    }

    return _ApiResponse(
      statusCode: response.statusCode,
      body: response.body,
      json: decoded,
    );
  }

  static void _log(String message) {
    if (kDebugMode) {
      debugPrint('ApiService: $message');
    }
  }
}

enum PostMediaType { image, video }

enum _HttpMethod { get, post, put, delete }

class _ApiResponse {
  const _ApiResponse({required this.statusCode, required this.body, this.json});

  final int statusCode;
  final String body;
  final dynamic json;
}

enum RelationshipStatus { none, pendingOutgoing, pendingIncoming, friends }

class RelationshipSummary {
  const RelationshipSummary({
    required this.status,
    required this.pendingRequestId,
    required this.followerCount,
    required this.followingCount,
    required this.friendCount,
  });

  final RelationshipStatus status;
  final String? pendingRequestId;
  final int followerCount;
  final int followingCount;
  final int friendCount;

  RelationshipSummary copyWith({
    RelationshipStatus? status,
    String? pendingRequestId,
    int? followerCount,
    int? followingCount,
    int? friendCount,
  }) {
    return RelationshipSummary(
      status: status ?? this.status,
      pendingRequestId: pendingRequestId ?? this.pendingRequestId,
      followerCount: followerCount ?? this.followerCount,
      followingCount: followingCount ?? this.followingCount,
      friendCount: friendCount ?? this.friendCount,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'status': status.name,
    'pendingRequestId': pendingRequestId,
    'followerCount': followerCount,
    'followingCount': followingCount,
    'friendCount': friendCount,
  };
}
