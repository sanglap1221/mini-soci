import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:pay_go/models/post_interaction_state.dart';
import 'package:pay_go/pages/profile_page.dart';
import 'package:pay_go/services/api_service.dart';
import 'package:pay_go/services/app_cache_managers.dart';
import 'package:pay_go/utils/time_formatter.dart';
import 'package:pay_go/widgets/comments_sheet.dart';
import 'package:share_plus/share_plus.dart';

class ReelsPage extends StatefulWidget {
  const ReelsPage({super.key, this.refreshTrigger});

  final Object? refreshTrigger;

  @override
  State<ReelsPage> createState() => _ReelsPageState();
}

class _ReelsPageState extends State<ReelsPage> {
  final ApiService _apiService = ApiService();
  final PageController _pageController = PageController();

  final Map<String, PostInteractionState> _postInteractions =
      <String, PostInteractionState>{};
  final Set<String> _failedImageUrls = <String>{};

  List<dynamic>? _reels;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadReels();
  }

  @override
  void didUpdateWidget(covariant ReelsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshTrigger != oldWidget.refreshTrigger) {
      _loadReels(forceRefresh: true);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadReels({bool forceRefresh = false}) async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final posts = await _apiService.getPosts(forceRefresh: forceRefresh);

      if (!mounted) return;
      setState(() {
        _reels = posts;
        _syncPostInteractions(posts);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reels'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadReels(forceRefresh: true),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.movie_filter_outlined,
              size: 48,
              color: Colors.grey,
            ),
            const SizedBox(height: 12),
            Text(
              'Failed to load reels',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadReels(forceRefresh: true),
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    if (_reels == null || _reels!.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.video_library_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('No reels yet'),
            SizedBox(height: 4),
            Text('Pull down to refresh after creating a post'),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () {},
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _reels!.length,
        itemBuilder: (context, index) {
          final reel = _reels![index];
          if (reel is! Map<String, dynamic>) {
            return const SizedBox.shrink();
          }
          return GestureDetector(
            onDoubleTap: () => _toggleLike(reel),
            child: _buildReel(reel),
          );
        },
      ),
    );
  }

  Widget _buildReel(Map<String, dynamic> reel) {
    final rawPath = (reel['imageUrl'] as String?) ?? '';
    final imageUrl = rawPath.isNotEmpty
        ? _apiService.getFullImageUrl(rawPath)
        : null;
    final caption = reel['caption']?.toString().trim() ?? '';
    final username = _resolveUsername(reel);
    final timestamp = _buildPostInfo(reel['createdAt']);
    final postId = _extractPostId(reel);
    final interaction = postId != null
        ? _postInteractions[postId] ?? _createStateFromPost(reel)
        : _createStateFromPost(reel);

    final likeCount = interaction.likeCount;
    final commentCount = interaction.commentCount;
    final isLiked = interaction.isLiked;
    final isLikeLoading = interaction.isLikeLoading;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: _buildBackgroundImage(imageUrl)),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.65),
                    Colors.black.withValues(alpha: 0.1),
                  ],
                  stops: const [0.0, 0.7],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          bottom: 32,
          right: 96,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (username.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    final userId = reel['userId'] as String?;
                    if (userId != null && userId.isNotEmpty) {
                      _navigateToUserProfile(userId);
                    }
                  },
                  child: Text(
                    '@$username',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              if (caption.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    caption,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              if (timestamp != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    timestamp,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        Positioned(
          right: 20,
          bottom: 32,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildVerticalAction(
                icon: isLiked ? Icons.favorite : Icons.favorite_border,
                color: isLiked ? Colors.redAccent : Colors.white,
                label: '$likeCount',
                onTap: () => _toggleLike(reel),
                isBusy: isLikeLoading,
              ),
              const SizedBox(height: 16),
              _buildVerticalAction(
                icon: Icons.mode_comment_outlined,
                color: Colors.white,
                label: '$commentCount',
                onTap: () => _openComments(reel),
              ),
              const SizedBox(height: 16),
              _buildVerticalAction(
                icon: Icons.share_outlined,
                color: Colors.white,
                label: 'Share',
                onTap: () => _shareReel(reel),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBackgroundImage(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const Icon(Icons.videocam_off, color: Colors.white38, size: 56),
      );
    }

    if (_failedImageUrls.contains(imageUrl)) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const Icon(Icons.videocam_off, color: Colors.white38, size: 56),
      );
    }

    return CachedNetworkImage(
      cacheManager: AppCacheManagers.imageCache,
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      ),
      errorWidget: (context, url, error) {
        _failedImageUrls.add(imageUrl);
        return Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: const Icon(
            Icons.videocam_off,
            color: Colors.white38,
            size: 56,
          ),
        );
      },
    );
  }

  Widget _buildVerticalAction({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
    bool isBusy = false,
  }) {
    return GestureDetector(
      onTap: isBusy ? null : onTap,
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, color: color, size: 32),
              if (isBusy)
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleLike(Map<String, dynamic> reel) async {
    final postId = _extractPostId(reel);
    if (postId == null) return;

    final currentState = _postInteractions.putIfAbsent(
      postId,
      () => _createStateFromPost(reel),
    );

    if (currentState.isLikeLoading) {
      return;
    }

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
      _updatePostInteractionFieldsInList(
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
        _updatePostInteractionFieldsInList(
          postId,
          likeCount: resolvedCount,
          isLiked: resolvedLiked,
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _postInteractions[postId] = currentState.copyWith(isLikeLoading: false);
        _updatePostInteractionFieldsInList(
          postId,
          likeCount: currentState.likeCount,
          isLiked: currentState.isLiked,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update like: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openComments(Map<String, dynamic> reel) async {
    final postId = _extractPostId(reel);
    if (postId == null) return;

    final interaction = _postInteractions.putIfAbsent(
      postId,
      () => _createStateFromPost(reel),
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
                _postInteractions[postId] ?? _createStateFromPost(reel);
            _postInteractions[postId] = existing.copyWith(
              commentCount: safeCount,
            );
            _updatePostInteractionFieldsInList(postId, commentCount: safeCount);
          });
        },
      ),
    );
  }

  Future<void> _shareReel(Map<String, dynamic> reel) async {
    final caption = reel['caption']?.toString().trim() ?? '';
    final rawPath = (reel['imageUrl'] as String?) ?? '';
    final resolvedImageUrl = rawPath.isNotEmpty
        ? _apiService.getFullImageUrl(rawPath)
        : null;
    final postId = _extractPostId(reel);

    final buffer = StringBuffer();
    var hasContent = false;

    if (caption.isNotEmpty) {
      buffer.writeln(caption);
      hasContent = true;
    }
    if (resolvedImageUrl != null && resolvedImageUrl.isNotEmpty) {
      if (hasContent) buffer.writeln();
      buffer.writeln(resolvedImageUrl);
      hasContent = true;
    }
    if (postId != null) {
      if (hasContent) buffer.writeln();
      buffer.writeln('Shared via Pay Go (Post ID: $postId)');
      hasContent = true;
    } else if (!hasContent) {
      buffer.write('Check out this reel on Pay Go!');
      hasContent = true;
    }

    final shareContent = buffer.toString().trim();
    if (shareContent.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to share for this reel')),
      );
      return;
    }

    try {
      await Share.share(shareContent);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to share reel: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _syncPostInteractions(List<dynamic> posts) {
    final next = <String, PostInteractionState>{};
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
          PostInteractionState(
            likeCount: likeCount,
            commentCount: commentCount,
            isLiked: isLiked,
          );
    }

    _postInteractions
      ..clear()
      ..addAll(next);
  }

  void _updatePostInteractionFieldsInList(
    String postId, {
    int? likeCount,
    bool? isLiked,
    int? commentCount,
  }) {
    if (_reels == null) return;
    for (final item in _reels!) {
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

  PostInteractionState _createStateFromPost(Map<String, dynamic> post) {
    return PostInteractionState(
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

  String? _buildPostInfo(dynamic createdAt) {
    final formatted = formatTimestamp(createdAt);
    if (formatted == null || formatted.isEmpty) {
      return null;
    }
    return 'Posted $formatted';
  }

  String _resolveUsername(Map<String, dynamic> post) {
    final author = post['author'];
    if (author is Map<String, dynamic>) {
      final candidates = [
        author['username'],
        author['displayName'],
        author['name'],
        author['fullName'],
      ];
      for (final candidate in candidates) {
        if (candidate is String && candidate.trim().isNotEmpty) {
          return candidate.trim();
        }
      }
    }

    final directUsername = post['username'];
    if (directUsername is String && directUsername.trim().isNotEmpty) {
      return directUsername.trim();
    }

    final user = post['user'];
    if (user is Map<String, dynamic>) {
      final candidates = [user['username'], user['displayName'], user['name']];
      for (final candidate in candidates) {
        if (candidate is String && candidate.trim().isNotEmpty) {
          return candidate.trim();
        }
      }
    }

    return 'Unknown';
  }

  void _navigateToUserProfile(String userId) {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ProfilePage(userId: userId)),
    );
  }
}
