import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pay_go/services/api_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pay_go/utils/post_viewer.dart';
import 'package:pay_go/utils/time_formatter.dart';
import 'package:pay_go/widgets/comments_sheet.dart';
import 'profile_page.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key, this.refreshTrigger});

  final Object? refreshTrigger;

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final ApiService _apiService = ApiService();
  final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
  List<dynamic>? _posts;
  bool _isLoading = true;
  String? _errorMessage;
  final Set<String> _failedPostImageUrls = <String>{};
  final Set<String> _failedAuthorAvatarUrls = <String>{};
  final Map<String, String> _usernameOverrides = <String, String>{};
  final Map<String, _PostInteractionState> _postInteractions =
      <String, _PostInteractionState>{};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _userSubscription;

  @override
  void initState() {
    super.initState();
    debugPrint('FeedPage initState called');
    _listenForUserUpdates();
    _loadPosts();
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FeedPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshTrigger != oldWidget.refreshTrigger) {
      debugPrint('FeedPage refresh trigger updated');
      _loadPosts();
    }
  }

  Future<void> _loadPosts() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      debugPrint('Loading posts...');
      final posts = await _apiService.getPosts();

      if (!mounted) return;
      setState(() {
        _posts = posts;
        _syncPostInteractions(posts);
        _isLoading = false;
      });
      debugPrint('Posts loaded successfully: ${posts.length} posts');
    } catch (e) {
      debugPrint('Error loading posts: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _listenForUserUpdates() {
    _userSubscription?.cancel();
    _userSubscription = FirebaseFirestore.instance
        .collection('users')
        .snapshots()
        .listen(
          (snapshot) {
            final updates = <String, String>{};
            for (final doc in snapshot.docs) {
              final username = (doc.data()['username'] as String?)?.trim();
              if (username != null && username.isNotEmpty) {
                updates[doc.id] = username;
              }
            }

            if (!mounted) return;
            if (mapEquals(_usernameOverrides, updates)) {
              return;
            }

            setState(() {
              _usernameOverrides
                ..clear()
                ..addAll(updates);
            });
          },
          onError: (error) {
            debugPrint('FeedPage user subscription error: $error');
          },
        );
  }

  Future<void> _deletePost(String postId, int index) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Deleting post...'),
            ],
          ),
        ),
      );

      await _apiService.deletePost(postId);

      if (!mounted) return;

      final removedPost = _posts![index];
      final removedPostId = removedPost is Map<String, dynamic>
          ? _extractPostId(removedPost)
          : null;
      setState(() {
        _posts!.removeAt(index);
        if (removedPostId != null) {
          _postInteractions.remove(removedPostId);
        }
      });

      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Post deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete post: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showDeleteConfirmation(String postId, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Post'),
        content: Text(
          'Are you sure you want to delete this post? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deletePost(postId, index);
            },
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // Method to refresh posts - can be called from other pages
  void refreshPosts() {
    debugPrint('refreshPosts called externally');
    _loadPosts();
  }

  void _navigateToUserProfile(String userId) {
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ProfilePage(userId: userId)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      'FeedPage build method called - isLoading: $_isLoading, postsCount: ${_posts?.length}',
    );
    return Scaffold(
      appBar: AppBar(
        title: Text('Feed'),
        actions: [IconButton(icon: Icon(Icons.refresh), onPressed: _loadPosts)],
      ),
      body: RefreshIndicator(onRefresh: _loadPosts, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            SizedBox(height: 16),
            Text(
              'Failed to load feed',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500]),
            ),
            SizedBox(height: 16),
            ElevatedButton(onPressed: _loadPosts, child: Text('Try Again')),
          ],
        ),
      );
    }

    if (_posts == null || _posts!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            SizedBox(height: 16),
            Text(
              'No posts yet',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            SizedBox(height: 8),
            Text(
              'Pull to refresh or add your first post',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      physics:
          AlwaysScrollableScrollPhysics(), // Enables pull-to-refresh even with few items
      itemCount: _posts!.length,
      itemBuilder: (context, index) {
        final post = _posts![index];
        if (post is! Map<String, dynamic>) {
          return const SizedBox.shrink();
        }
        final postId = _extractPostId(post);
        final isOwnPost = post['userId'] == currentUserId;
        final displayName = _resolveUsername(post);

        return Card(
          margin: EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Post header with author info and menu
              Padding(
                padding: EdgeInsets.all(8),
                child: Row(
                  children: [
                    // Author avatar
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.grey[300],
                      child: _buildAuthorAvatar(post),
                    ),
                    GestureDetector(
                      onTap: () => _navigateToUserProfile(post['userId']),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Author name
                            Text(
                              displayName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            // Timestamp
                            if (post['createdAt'] != null)
                              Text(
                                formatTimestamp(post['createdAt']) ?? '',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(child: Container()), // Pushes menu to the right
                    // Menu button for own posts
                    if (isOwnPost)
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'delete' && postId != null) {
                            _showDeleteConfirmation(postId, index);
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, color: Colors.red, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Delete Post',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ],
                        child: Icon(Icons.more_vert, color: Colors.grey[600]),
                      ),
                  ],
                ),
              ),
              // Post image
              _buildPostImage(context, post),
              // Post caption
              Padding(
                padding: EdgeInsets.all(8),
                child: Text(post['caption'] ?? ''),
              ),
              const Divider(height: 1),
              _buildPostFooter(post),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAuthorAvatar(Map<String, dynamic> post) {
    final profilePic = post['author']?['profilePicUrl'] as String?;
    final username = _resolveUsername(post);

    if (profilePic == null || profilePic.isEmpty) {
      return _buildAuthorInitial(username);
    }

    final avatarUrl = _apiService.getFullImageUrl(profilePic);
    if (_failedAuthorAvatarUrls.contains(avatarUrl)) {
      return _buildAuthorInitial(username);
    }

    return ClipOval(
      child: Image.network(
        avatarUrl,
        width: 32,
        height: 32,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          _failedAuthorAvatarUrls.add(avatarUrl);
          debugPrint('Author avatar load error for $avatarUrl: $error');
          return _buildAuthorInitial(username);
        },
      ),
    );
  }

  Widget _buildAuthorInitial(String? username) {
    final initial = (username != null && username.isNotEmpty)
        ? username[0].toUpperCase()
        : 'U';
    return Center(
      child: Text(initial, style: TextStyle(fontSize: 12, color: Colors.blue)),
    );
  }

  String _resolveUsername(Map<String, dynamic> post) {
    final postUserId = post['userId'] as String?;
    final override = postUserId != null ? _usernameOverrides[postUserId] : null;
    if (override != null && override.trim().isNotEmpty) {
      return override.trim();
    }

    final authorName = (post['author']?['username'] as String?)?.trim();
    if (authorName != null && authorName.isNotEmpty) {
      return authorName;
    }

    if (postUserId == currentUserId) {
      final displayName = FirebaseAuth.instance.currentUser?.displayName;
      if (displayName != null && displayName.trim().isNotEmpty) {
        return displayName.trim();
      }
    }

    return 'Unknown User';
  }

  Widget _buildPostImage(BuildContext context, Map<String, dynamic> post) {
    final rawPath = (post['imageUrl'] as String?) ?? '';
    if (rawPath.isEmpty) {
      return _buildImagePlaceholder();
    }

    final imageUrl = _apiService.getFullImageUrl(rawPath);
    debugPrint('Loading image with URL: $imageUrl');

    if (_failedPostImageUrls.contains(imageUrl)) {
      return _buildImagePlaceholder();
    }

    final caption = post['caption']?.toString();
    final infoText = _buildPostInfo(post['createdAt']);
    final postId = _extractPostId(post);
    final interactionState = postId != null
        ? _postInteractions[postId] ?? _createStateFromPost(post)
        : _createStateFromPost(post);
    final likeCount = interactionState.likeCount;
    final commentCount = interactionState.commentCount;
    final isLiked = interactionState.isLiked;

    final imageWidget = Image.network(
      imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: 200,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return SizedBox(
          height: 200,
          child: Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        _failedPostImageUrls.add(imageUrl);
        debugPrint('Post image load error for $imageUrl: $error');
        return _buildImagePlaceholder();
      },
    );

    return GestureDetector(
      onTap: () {
        PostViewer.show(
          context: context,
          apiService: _apiService,
          relativeImagePath: rawPath,
          caption: caption,
          infoText: infoText,
          postId: postId,
          initialLikeCount: likeCount,
          initialCommentCount: commentCount,
          initialIsLiked: isLiked,
          onInteractionChanged: postId == null
              ? null
              : (interaction) {
                  if (!mounted) return;
                  setState(() {
                    final current =
                        _postInteractions[postId] ?? _createStateFromPost(post);
                    final updatedLikeCount = interaction.likeCount != null
                        ? _clampNonNegative(interaction.likeCount!)
                        : current.likeCount;
                    final updatedCommentCount = interaction.commentCount != null
                        ? _clampNonNegative(interaction.commentCount!)
                        : current.commentCount;
                    final updatedIsLiked =
                        interaction.isLiked ?? current.isLiked;

                    _postInteractions[postId] = current.copyWith(
                      likeCount: updatedLikeCount,
                      commentCount: updatedCommentCount,
                      isLiked: updatedIsLiked,
                      isLikeLoading: false,
                    );

                    _updatePostInteractionFieldsInPostMap(
                      postId,
                      likeCount: updatedLikeCount,
                      commentCount: updatedCommentCount,
                      isLiked: updatedIsLiked,
                    );
                  });
                },
        );
      },
      child: imageWidget,
    );
  }

  String? _buildPostInfo(dynamic createdAt) {
    final formatted = formatTimestamp(createdAt);
    if (formatted == null || formatted.isEmpty) {
      return null;
    }
    return 'Posted $formatted';
  }

  Widget _buildImagePlaceholder() {
    return Container(
      height: 200,
      color: Colors.grey[200],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.image_not_supported, size: 40, color: Colors.grey),
          SizedBox(height: 8),
          Text('Image unavailable', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildPostFooter(Map<String, dynamic> post) {
    final postId = _extractPostId(post);
    final interaction = postId != null ? _postInteractions[postId] : null;
    final likeCount = interaction?.likeCount ?? _readLikeCount(post) ?? 0;
    final commentCount =
        interaction?.commentCount ?? _readCommentCount(post) ?? 0;
    final isLiked = interaction?.isLiked ?? _readIsLiked(post) ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          _buildFooterAction(
            icon: isLiked ? Icons.favorite : Icons.favorite_border,
            color: isLiked ? Colors.redAccent : Colors.grey[700],
            label: '$likeCount',
            onTap: postId != null
                ? () {
                    _toggleLike(post);
                  }
                : null,
          ),
          const SizedBox(width: 12),
          _buildFooterAction(
            icon: Icons.mode_comment_outlined,
            color: Colors.grey[700],
            label: '$commentCount',
            onTap: postId != null
                ? () {
                    _openComments(post);
                  }
                : null,
          ),
          const Spacer(),
          if (interaction?.isLikeLoading ?? false)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildFooterAction({
    required IconData icon,
    required Color? color,
    required String label,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleLike(Map<String, dynamic> post) async {
    final postId = _extractPostId(post);
    if (postId == null) return;

    if (_postInteractions[postId]?.isLikeLoading ?? false) {
      return;
    }

    final currentState = _postInteractions.putIfAbsent(
      postId,
      () => _createStateFromPost(post),
    );

    final nextLiked = !currentState.isLiked;
    final delta = nextLiked ? 1 : -1;
    final optimisticLikeCount = _clampNonNegative(
      currentState.likeCount + delta,
    );

    setState(() {
      _postInteractions[postId] = currentState.copyWith(
        isLiked: nextLiked,
        likeCount: optimisticLikeCount,
        isLikeLoading: true,
      );
      _updatePostInteractionFieldsInPostMap(
        postId,
        likeCount: optimisticLikeCount,
        isLiked: nextLiked,
      );
    });

    try {
      final response = nextLiked
          ? await _apiService.likePost(postId)
          : await _apiService.unlikePost(postId);

      final serverCount = _extractCountFromResponse(response, const [
        'likeCount',
        'likes',
        'likesCount',
        'totalLikes',
      ]);
      final serverLiked = _extractIsLikedFromResponse(response);

      if (!mounted) return;
      setState(() {
        final latest = _postInteractions[postId] ?? currentState;
        final resolvedCount = serverCount ?? latest.likeCount;
        final resolvedLiked = serverLiked ?? nextLiked;
        _postInteractions[postId] = latest.copyWith(
          likeCount: resolvedCount,
          isLiked: resolvedLiked,
          isLikeLoading: false,
        );
        _updatePostInteractionFieldsInPostMap(
          postId,
          likeCount: resolvedCount,
          isLiked: resolvedLiked,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _postInteractions[postId] = currentState.copyWith(isLikeLoading: false);
        _updatePostInteractionFieldsInPostMap(
          postId,
          likeCount: currentState.likeCount,
          isLiked: currentState.isLiked,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update like: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openComments(Map<String, dynamic> post) async {
    final postId = _extractPostId(post);
    if (postId == null) return;

    final interaction = _postInteractions.putIfAbsent(
      postId,
      () => _createStateFromPost(post),
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => CommentsSheet(
        apiService: _apiService,
        postId: postId,
        initialCommentCount: interaction.commentCount,
        onCountUpdated: (updatedCount) {
          if (!mounted) return;
          final safeCount = _clampNonNegative(updatedCount);
          setState(() {
            final existing =
                _postInteractions[postId] ?? _createStateFromPost(post);
            _postInteractions[postId] = existing.copyWith(
              commentCount: safeCount,
            );
            _updatePostInteractionFieldsInPostMap(
              postId,
              commentCount: safeCount,
            );
          });
        },
      ),
    );
  }

  void _syncPostInteractions(List<dynamic> posts) {
    final next = <String, _PostInteractionState>{};
    for (final item in posts) {
      if (item is! Map<String, dynamic>) continue;
      final postId = _extractPostId(item);
      if (postId == null) continue;

      final previous = _postInteractions[postId];
      final likeCount = _readLikeCount(item) ?? previous?.likeCount ?? 0;
      final commentCount =
          _readCommentCount(item) ?? previous?.commentCount ?? 0;
      final isLiked = _readIsLiked(item) ?? previous?.isLiked ?? false;

      next[postId] =
          previous?.copyWith(
            likeCount: likeCount,
            commentCount: commentCount,
            isLiked: isLiked,
            isLikeLoading: false,
          ) ??
          _PostInteractionState(
            likeCount: likeCount,
            commentCount: commentCount,
            isLiked: isLiked,
          );
    }

    _postInteractions
      ..clear()
      ..addAll(next);
  }

  void _updatePostInteractionFieldsInPostMap(
    String postId, {
    int? likeCount,
    bool? isLiked,
    int? commentCount,
  }) {
    if (_posts == null) return;
    for (final item in _posts!) {
      if (item is! Map<String, dynamic>) continue;
      if (_extractPostId(item) != postId) continue;

      if (likeCount != null) {
        item['likeCount'] = likeCount;
        item['likes'] = likeCount;
        item['likesCount'] = likeCount;
        item['totalLikes'] = likeCount;
      }

      if (commentCount != null) {
        item['commentCount'] = commentCount;
        item['commentsCount'] = commentCount;
        item['totalComments'] = commentCount;
      }

      if (isLiked != null) {
        item['viewerHasLiked'] = isLiked;
        item['isLiked'] = isLiked;
        item['likedByCurrentUser'] = isLiked;
        item['liked'] = isLiked;
      }
      break;
    }
  }

  String? _extractPostId(Map<String, dynamic> post) {
    final candidates = [post['_id'], post['id'], post['postId'], post['uuid']];
    for (final candidate in candidates) {
      if (candidate is String && candidate.isNotEmpty) {
        return candidate;
      }
      if (candidate is int) {
        return candidate.toString();
      }
    }
    return null;
  }

  _PostInteractionState _createStateFromPost(Map<String, dynamic> post) {
    return _PostInteractionState(
      likeCount: _readLikeCount(post) ?? 0,
      commentCount: _readCommentCount(post) ?? 0,
      isLiked: _readIsLiked(post) ?? false,
    );
  }

  int? _readLikeCount(Map<String, dynamic> post) {
    final candidates = [
      post['likeCount'],
      post['likes'],
      post['likesCount'],
      post['totalLikes'],
    ];
    for (final candidate in candidates) {
      final parsed = _asInt(candidate);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  int? _readCommentCount(Map<String, dynamic> post) {
    final candidates = [
      post['commentCount'],
      post['comments'],
      post['commentsCount'],
      post['totalComments'],
    ];
    for (final candidate in candidates) {
      final parsed = _asInt(candidate);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  bool? _readIsLiked(Map<String, dynamic> post) {
    final candidates = [
      post['viewerHasLiked'],
      post['likedByCurrentUser'],
      post['isLiked'],
      post['liked'],
      post['hasLiked'],
    ];
    for (final candidate in candidates) {
      final parsed = _asBool(candidate);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  int? _extractCountFromResponse(
    Map<String, dynamic> response,
    List<String> keys,
  ) {
    for (final scope in _responseMaps(response)) {
      for (final key in keys) {
        final parsed = _asInt(scope[key]);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }

  bool? _extractIsLikedFromResponse(Map<String, dynamic> response) {
    const keys = ['viewerHasLiked', 'isLiked', 'liked', 'likedByCurrentUser'];
    for (final scope in _responseMaps(response)) {
      for (final key in keys) {
        final parsed = _asBool(scope[key]);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }

  Iterable<Map<String, dynamic>> _responseMaps(
    Map<String, dynamic> response,
  ) sync* {
    yield response;

    final data = response['data'];
    if (data is Map<String, dynamic>) {
      yield data;
    }

    final meta = response['meta'] ?? response['metadata'];
    if (meta is Map<String, dynamic>) {
      yield meta;
    }

    final payload = response['payload'];
    if (payload is Map<String, dynamic>) {
      yield payload;
    }

    final raw = response['raw'];
    if (raw is Map<String, dynamic>) {
      yield raw;
    }
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  bool? _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return null;
  }

  int _clampNonNegative(int value) => value < 0 ? 0 : value;
}

class _PostInteractionState {
  const _PostInteractionState({
    required this.likeCount,
    required this.commentCount,
    required this.isLiked,
    this.isLikeLoading = false,
  });

  final int likeCount;
  final int commentCount;
  final bool isLiked;
  final bool isLikeLoading;

  _PostInteractionState copyWith({
    int? likeCount,
    int? commentCount,
    bool? isLiked,
    bool? isLikeLoading,
  }) {
    return _PostInteractionState(
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      isLiked: isLiked ?? this.isLiked,
      isLikeLoading: isLikeLoading ?? this.isLikeLoading,
    );
  }
}
