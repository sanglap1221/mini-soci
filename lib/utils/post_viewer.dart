import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/api_service.dart';
import '../services/app_cache_managers.dart';
import '../utils/time_formatter.dart';

class PostViewer {
  const PostViewer._();

  static Future<void> show({
    required BuildContext context,
    required ApiService apiService,
    String? mediaType,
    String? relativeImagePath,
    String? relativeVideoPath,
    String? absoluteImageUrl,
    String? caption,
    String? infoText,
    String? postId,
    String? postOwnerId,
    int? initialLikeCount,
    int? initialCommentCount,
    bool? initialIsLiked,
    PostViewerInteractionCallback? onInteractionChanged,
  }) async {
    final imageUrl = _resolveImageUrl(
      apiService: apiService,
      absoluteImageUrl: absoluteImageUrl,
      relativeImagePath: relativeImagePath,
    );

    final videoUrl = _resolveVideoUrl(
      apiService: apiService,
      relativeVideoPath: relativeVideoPath,
    );

    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: _PostViewerDialog(
          mediaType: mediaType,
          imageUrl: imageUrl,
          videoUrl: videoUrl,
          caption: caption,
          infoText: infoText,
          postId: postId,
          postOwnerId: postOwnerId,
          apiService: apiService,
          initialLikeCount: initialLikeCount,
          initialCommentCount: initialCommentCount,
          initialIsLiked: initialIsLiked,
          onInteractionChanged: onInteractionChanged,
        ),
      ),
    );
  }

  static String? _resolveImageUrl({
    required ApiService apiService,
    String? relativeImagePath,
    String? absoluteImageUrl,
  }) {
    if (absoluteImageUrl != null && absoluteImageUrl.isNotEmpty) {
      return absoluteImageUrl;
    }
    if (relativeImagePath != null && relativeImagePath.isNotEmpty) {
      return apiService.getFullImageUrl(relativeImagePath);
    }
    return null;
  }

  static String? _resolveVideoUrl({
    required ApiService apiService,
    String? relativeVideoPath,
  }) {
    if (relativeVideoPath != null && relativeVideoPath.isNotEmpty) {
      return apiService.getFullImageUrl(relativeVideoPath);
    }
    return null;
  }

  static Widget _buildImageContent(String? imageUrl) {
    if (imageUrl == null) {
      return Container(
        color: Colors.grey[200],
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported, color: Colors.grey),
      );
    }

    return CachedNetworkImage(
      cacheManager: AppCacheManagers.imageCache,
      imageUrl: imageUrl,
      fit: BoxFit.contain,
      placeholder: (context, url) => Container(
        color: Colors.grey[200],
        alignment: Alignment.center,
        child: const SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: Colors.grey[200],
        alignment: Alignment.center,
        child: const Icon(Icons.error_outline, color: Colors.grey),
      ),
    );
  }
}

class _PostViewerDialog extends StatefulWidget {
  const _PostViewerDialog({
    required this.apiService,
    this.mediaType,
    this.imageUrl,
    this.videoUrl,
    this.caption,
    this.infoText,
    this.postId,
    this.postOwnerId,
    this.initialLikeCount,
    this.initialCommentCount,
    this.initialIsLiked,
    this.onInteractionChanged,
  });

  final ApiService apiService;
  final String? mediaType;
  final String? imageUrl;
  final String? videoUrl;
  final String? caption;
  final String? infoText;
  final String? postId;
  final String? postOwnerId;
  final int? initialLikeCount;
  final int? initialCommentCount;
  final bool? initialIsLiked;
  final PostViewerInteractionCallback? onInteractionChanged;

  bool get _isInteractable => postId != null && postId!.isNotEmpty;

  @override
  State<_PostViewerDialog> createState() => _PostViewerDialogState();
}

class _PostViewerDialogState extends State<_PostViewerDialog> {
  late int _likeCount;
  late int _commentCount;
  late bool _isLiked;

  bool _isLikeBusy = false;
  bool _isCommentsLoading = true;
  bool _isSubmittingComment = false;

  String? _commentsError;

  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  final List<dynamic> _comments = <dynamic>[];
  final Set<String> _deletingCommentIds = <String>{};

  @override
  void initState() {
    super.initState();
    _likeCount = widget.initialLikeCount ?? 0;
    _commentCount = widget.initialCommentCount ?? 0;
    _isLiked = widget.initialIsLiked ?? false;

    if (widget._isInteractable) {
      _loadComments();
    } else {
      _isCommentsLoading = false;
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    if (!widget._isInteractable || widget.postId == null) {
      setState(() {
        _isCommentsLoading = false;
        _commentsError = null;
        _comments.clear();
      });
      return;
    }

    setState(() {
      _isCommentsLoading = true;
      _commentsError = null;
    });

    try {
      final result = await widget.apiService.getComments(
        widget.postId!,
        limit: 50,
      );
      final items = _extractItems(result);
      final total = _extractTotalCount(result) ?? items.length;
      if (!mounted) return;
      setState(() {
        _comments
          ..clear()
          ..addAll(items);
        _commentCount = total;
        _isCommentsLoading = false;
      });
      _notifyInteractionChanged();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isCommentsLoading = false;
        _commentsError = error.toString();
      });
    }
  }

  Future<void> _submitComment() async {
    if (!widget._isInteractable || widget.postId == null) return;

    final text = _commentController.text.trim();
    if (text.isEmpty || _isSubmittingComment) return;

    setState(() {
      _isSubmittingComment = true;
      _commentsError = null;
    });

    try {
      final result = await widget.apiService.addComment(
        widget.postId!,
        text,
        postOwnerId: widget.postOwnerId,
      );
      final comment = _extractComment(result) ?? _fallbackComment(text);
      if (!mounted) return;
      setState(() {
        _comments.insert(0, comment);
        _commentController.clear();
        _commentCount += 1;
        _isSubmittingComment = false;
      });
      _notifyInteractionChanged();
      _commentFocusNode.requestFocus();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmittingComment = false;
        _commentsError = error.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add comment: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteComment(dynamic comment) async {
    final commentId = _extractCommentId(comment);
    if (commentId == null || _deletingCommentIds.contains(commentId)) {
      return;
    }

    setState(() {
      _deletingCommentIds.add(commentId);
    });

    try {
      await widget.apiService.deleteComment(commentId, postId: widget.postId);
      if (!mounted) return;
      setState(() {
        _comments.removeWhere(
          (element) => _extractCommentId(element) == commentId,
        );
        _commentCount = (_commentCount - 1).clamp(0, 1 << 30);
        _deletingCommentIds.remove(commentId);
      });
      _notifyInteractionChanged();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _deletingCommentIds.remove(commentId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete comment: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _toggleLike() async {
    if (!widget._isInteractable || widget.postId == null || _isLikeBusy) {
      return;
    }

    setState(() {
      _isLikeBusy = true;
      _isLiked = !_isLiked;
      final delta = _isLiked ? 1 : -1;
      _likeCount = (_likeCount + delta).clamp(0, 1 << 30);
    });
    _notifyInteractionChanged();

    try {
      if (_isLiked) {
        await widget.apiService.likePost(
          widget.postId!,
          postOwnerId: widget.postOwnerId,
        );
      } else {
        await widget.apiService.unlikePost(widget.postId!);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLiked = !_isLiked;
        final delta = _isLiked ? 1 : -1;
        _likeCount = (_likeCount + delta).clamp(0, 1 << 30);
      });
      _notifyInteractionChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update like: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLikeBusy = false;
        });
      }
    }
  }

  void _notifyInteractionChanged() {
    widget.onInteractionChanged?.call(
      PostViewerInteraction(
        likeCount: _likeCount,
        commentCount: _commentCount,
        isLiked: _isLiked,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaSize = MediaQuery.of(context).size;
    final theme = Theme.of(context);
    final dialogColor =
        theme.dialogTheme.backgroundColor ?? theme.colorScheme.surface;

    final constrainedWidth = (mediaSize.width * 0.95).clamp(320.0, 520.0);
    final maxHeight = mediaSize.height * 0.95;
    final imageHeight = (maxHeight * 0.55).clamp(220.0, maxHeight);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: constrainedWidth,
          maxHeight: maxHeight,
        ),
        child: Material(
          color: dialogColor,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: widget._isInteractable
                      ? _loadComments
                      : () async {},
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 10, bottom: 6),
                          child: Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade400,
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SliverAppBar(
                        automaticallyImplyLeading: false,
                        backgroundColor: dialogColor,
                        collapsedHeight: imageHeight,
                        expandedHeight: imageHeight,
                        flexibleSpace: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: _buildMediaContent(context),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (widget.caption != null &&
                                  widget.caption!.trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    widget.caption!,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                              if (widget.infoText != null &&
                                  widget.infoText!.trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                    widget.infoText!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ),
                              _buildLikeRow(),
                              const Divider(height: 24),
                            ],
                          ),
                        ),
                      ),
                      ..._buildCommentSlivers(),
                      const SliverToBoxAdapter(child: SizedBox(height: 12)),
                    ],
                  ),
                ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget._isInteractable)
                      _buildComposer(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      ),
                    _buildCloseButton(padding: EdgeInsets.zero),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaContent(BuildContext context) {
    final mediaType = widget.mediaType?.toLowerCase().trim();
    final hasVideo = widget.videoUrl != null && widget.videoUrl!.isNotEmpty;
    final isVideo = hasVideo && (mediaType == null || mediaType == 'video');

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final side = size.shortestSide > 0 ? size.shortestSide : 320.0;
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: isVideo
                  ? PostViewerVideoPlayer(
                      key: ValueKey(widget.videoUrl!),
                      videoUrl: widget.videoUrl!,
                      autoplay: true,
                    )
                  : InteractiveViewer(
                      clipBehavior: Clip.none,
                      minScale: 1,
                      child: PostViewer._buildImageContent(widget.imageUrl),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLikeRow() {
    return Row(
      children: [
        IconButton(
          icon: Icon(
            _isLiked ? Icons.favorite : Icons.favorite_border,
            color: _isLiked ? Colors.red : null,
          ),
          onPressed: (!widget._isInteractable || _isLikeBusy)
              ? null
              : _toggleLike,
        ),
        Text(
          '$_likeCount likes',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 16),
        Text(
          '$_commentCount comments',
          style: TextStyle(color: Colors.grey[700]),
        ),
        const Spacer(),
        if (_isLikeBusy)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );
  }

  List<Widget> _buildCommentSlivers() {
    if (!widget._isInteractable) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Comments are unavailable for this post.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ];
    }

    if (_isCommentsLoading) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    final slivers = <Widget>[];

    if (_commentsError != null && _comments.isEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 40,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 12),
                Text(
                  'Failed to load comments',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _commentsError!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loadComments,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
      return slivers;
    }

    if (_comments.isEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.mode_comment_outlined, size: 40, color: Colors.grey),
                SizedBox(height: 12),
                Text('Be the first to comment.'),
              ],
            ),
          ),
        ),
      );
      return slivers;
    }

    if (_commentsError != null) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Material(
              color: Colors.redAccent.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _commentsError!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _loadComments,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    slivers.add(
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.builder(
          itemCount: _comments.length,
          itemBuilder: (context, index) {
            final comment = _comments[index];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCommentTile(comment),
                const SizedBox(height: 12),
              ],
            );
          },
        ),
      ),
    );

    return slivers;
  }

  Widget _buildCommentTile(dynamic comment) {
    final authorName = _extractAuthorName(comment) ?? 'Unknown';
    final createdAt = formatTimestamp(_extractCreatedAt(comment));
    final text = _extractCommentText(comment) ?? '';
    final commentId = _extractCommentId(comment);
    final canDelete = _canDelete(comment);
    final isDeleting =
        commentId != null && _deletingCommentIds.contains(commentId);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        authorName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(text),
          if (createdAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                createdAt,
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ),
        ],
      ),
      trailing: canDelete
          ? IconButton(
              icon: isDeleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: isDeleting ? null : () => _deleteComment(comment),
            )
          : null,
    );
  }

  Widget _buildComposer({
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 10, 16, 10),
  }) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              focusNode: _commentFocusNode,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submitComment(),
              decoration: InputDecoration(
                hintText: 'Add a comment...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _isSubmittingComment ? null : _submitComment,
            icon: _isSubmittingComment
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send, size: 18),
            label: const Text('Send'),
            style: ElevatedButton.styleFrom(
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloseButton({
    EdgeInsetsGeometry padding = const EdgeInsets.only(top: 8),
  }) {
    return Padding(
      padding: padding,
      child: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ),
    );
  }

  List<dynamic> _extractItems(Map<String, dynamic> payload) {
    final items = payload['items'] ?? payload['comments'] ?? payload['data'];
    if (items is List) {
      return items;
    }
    if (items == null) {
      if (payload['0'] != null) {
        return payload.values.whereType<Map<String, dynamic>>().toList();
      }
    }
    return <dynamic>[];
  }

  int? _extractTotalCount(Map<String, dynamic> payload) {
    final candidates = [
      payload['total'],
      payload['count'],
      payload['commentCount'],
      payload['totalCount'],
    ];
    for (final candidate in candidates) {
      if (candidate is int) return candidate;
      if (candidate is num) return candidate.toInt();
    }
    return null;
  }

  Map<String, dynamic>? _extractComment(Map<String, dynamic> response) {
    if (response.containsKey('comment') &&
        response['comment'] is Map<String, dynamic>) {
      return response['comment'] as Map<String, dynamic>;
    }
    if (response.containsKey('data') &&
        response['data'] is Map<String, dynamic>) {
      return response['data'] as Map<String, dynamic>;
    }
    if (response['raw'] is Map<String, dynamic>) {
      return response['raw'] as Map<String, dynamic>;
    }
    final candidate = Map<String, dynamic>.from(response);
    candidate.remove('raw');
    if (candidate.isNotEmpty) {
      return candidate;
    }
    return null;
  }

  Map<String, dynamic> _fallbackComment(String text) {
    final user = FirebaseAuth.instance.currentUser;
    final now = DateTime.now().toIso8601String();
    return <String, dynamic>{
      '_id': 'local-${DateTime.now().millisecondsSinceEpoch}',
      'text': text,
      'createdAt': now,
      'userId': user?.uid,
      'author': <String, dynamic>{'username': user?.displayName ?? 'You'},
    };
  }

  String? _extractCommentId(dynamic comment) {
    if (comment is Map<String, dynamic>) {
      final candidates = [
        comment['id'],
        comment['_id'],
        comment['commentId'],
        comment['uuid'],
      ];
      for (final candidate in candidates) {
        if (candidate == null) continue;
        if (candidate is String && candidate.isNotEmpty) return candidate;
        if (candidate is int) return candidate.toString();
      }
    }
    return null;
  }

  String? _extractAuthorName(dynamic comment) {
    if (comment is! Map<String, dynamic>) return null;

    String? pullName(Map<String, dynamic> scope) {
      final candidates = [
        scope['displayName'],
        scope['username'],
        scope['userName'],
        scope['name'],
        scope['fullName'],
        scope['nickname'],
      ];
      for (final candidate in candidates) {
        if (candidate is String && candidate.trim().isNotEmpty) {
          return candidate.trim();
        }
      }
      final first = scope['firstName'];
      final last = scope['lastName'];
      if (first is String && first.trim().isNotEmpty) {
        if (last is String && last.trim().isNotEmpty) {
          return '${first.trim()} ${last.trim()}';
        }
        return first.trim();
      }
      if (last is String && last.trim().isNotEmpty) {
        return last.trim();
      }
      return null;
    }

    final scopes = <Map<String, dynamic>>[];
    for (final key in ['author', 'user', 'owner', 'createdBy', 'profile']) {
      final value = comment[key];
      if (value is Map<String, dynamic>) {
        scopes.add(value);
      }
    }

    for (final scope in scopes) {
      final resolved = pullName(scope);
      if (resolved != null) {
        return resolved;
      }
    }

    final flat = pullName(comment);
    if (flat != null) {
      return flat;
    }

    final email = comment['email'] ?? comment['authorEmail'];
    if (email is String && email.isNotEmpty) {
      final prefix = email.split('@').first;
      if (prefix.isNotEmpty) {
        return prefix;
      }
    }

    return null;
  }

  dynamic _extractCreatedAt(dynamic comment) {
    if (comment is Map<String, dynamic>) {
      return comment['createdAt'] ?? comment['timestamp'];
    }
    return null;
  }

  String? _extractCommentText(dynamic comment) {
    if (comment is Map<String, dynamic>) {
      final candidates = [comment['text'], comment['content'], comment['body']];
      for (final candidate in candidates) {
        if (candidate is String && candidate.trim().isNotEmpty) {
          return candidate.trim();
        }
      }
    }
    return null;
  }

  bool _canDelete(dynamic comment) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return false;
    if (comment is Map<String, dynamic>) {
      final candidates = [
        comment['userId'],
        comment['ownerId'],
        comment['authorId'],
        comment['createdBy'],
      ];
      for (final candidate in candidates) {
        if (candidate is String && candidate == currentUserId) {
          return true;
        }
        if (candidate is int && candidate.toString() == currentUserId) {
          return true;
        }
      }
      final author = comment['author'];
      if (author is Map<String, dynamic>) {
        final authorId = author['id'] ?? author['uid'];
        if (authorId is String && authorId == currentUserId) {
          return true;
        }
        if (authorId is int && authorId.toString() == currentUserId) {
          return true;
        }
      }
      final user = comment['user'];
      if (user is Map<String, dynamic>) {
        final userId = user['id'] ?? user['uid'];
        if (userId is String && userId == currentUserId) {
          return true;
        }
        if (userId is int && userId.toString() == currentUserId) {
          return true;
        }
      }
    }
    return false;
  }
}

class PostViewerInteraction {
  const PostViewerInteraction({
    this.likeCount,
    this.commentCount,
    this.isLiked,
  });

  final int? likeCount;
  final int? commentCount;
  final bool? isLiked;
}

typedef PostViewerInteractionCallback =
    void Function(PostViewerInteraction interaction);

class PostViewerVideoPlayer extends StatefulWidget {
  const PostViewerVideoPlayer({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    this.height,
    this.autoplay = false,
    this.enableFullscreen = true,
    this.borderRadius = 0,
  });

  final String videoUrl;
  final String? thumbnailUrl;
  final double? height;
  final bool autoplay;
  final bool enableFullscreen;
  final double borderRadius;

  @override
  State<PostViewerVideoPlayer> createState() => _PostViewerVideoPlayerState();
}

class _PostViewerVideoPlayerState extends State<PostViewerVideoPlayer> {
  late final VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _initializationFailed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _controller.setLooping(true);
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() {
            _isInitialized = true;
          });
          if (widget.autoplay) {
            unawaited(_controller.play());
          }
        })
        .catchError((error, stackTrace) {
          debugPrint(
            'PostViewerVideoPlayer: failed to load ${widget.videoUrl}: $error',
          );
          if (!mounted) return;
          setState(() {
            _initializationFailed = true;
          });
        });
  }

  @override
  void dispose() {
    unawaited(_controller.pause());
    _controller.dispose();
    super.dispose();
  }

  bool get _isPlaying => _isInitialized && _controller.value.isPlaying;

  void _togglePlay() {
    if (_initializationFailed || !_isInitialized) {
      return;
    }

    if (_controller.value.isPlaying) {
      unawaited(_controller.pause());
    } else {
      unawaited(_controller.play());
    }

    setState(() {});
  }

  Future<void> _openFullscreen() async {
    final wasPlaying = _isPlaying;
    if (wasPlaying) {
      await _controller.pause();
      setState(() {});
    }

    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => _PostViewerFullscreenVideoPage(
          videoUrl: widget.videoUrl,
          thumbnailUrl: widget.thumbnailUrl,
        ),
        fullscreenDialog: true,
      ),
    );

    if (wasPlaying && mounted) {
      unawaited(_controller.play());
      setState(() {});
    }
  }

  Widget _buildVideoLayer() {
    if (_initializationFailed) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const Icon(
          Icons.error_outline,
          color: Colors.redAccent,
          size: 40,
        ),
      );
    }

    if (_isInitialized) {
      final size = _controller.value.size;
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.width == 0 ? 1 : size.width,
          height: size.height == 0 ? 1 : size.height,
          child: VideoPlayer(_controller),
        ),
      );
    }

    if (widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: widget.thumbnailUrl!,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: Colors.black12),
        errorWidget: (context, url, error) => Container(
          color: Colors.black45,
          alignment: Alignment.center,
          child: const Icon(Icons.movie, color: Colors.white54, size: 32),
        ),
      );
    }

    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: const Icon(Icons.movie, color: Colors.white54, size: 32),
    );
  }

  Widget _wrapWithSizing(Widget child) {
    final clippedChild = ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: child,
    );

    if (widget.height != null) {
      return SizedBox(
        height: widget.height,
        width: double.infinity,
        child: clippedChild,
      );
    }

    final aspectRatio = _isInitialized && _controller.value.aspectRatio > 0
        ? _controller.value.aspectRatio
        : 9 / 16;

    return AspectRatio(aspectRatio: aspectRatio, child: clippedChild);
  }

  @override
  Widget build(BuildContext context) {
    final media = Stack(
      fit: StackFit.expand,
      children: [
        _buildVideoLayer(),
        if (!_isInitialized && !_initializationFailed)
          const Center(child: CircularProgressIndicator()),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _togglePlay,
          ),
        ),
        if (!_initializationFailed)
          Center(
            child: AnimatedOpacity(
              opacity: _isPlaying ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(12),
                child: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ),
        if (widget.enableFullscreen && !_initializationFailed)
          Positioned(
            right: 12,
            bottom: 12,
            child: GestureDetector(
              onTap: _openFullscreen,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.all(6),
                child: const Icon(
                  Icons.fullscreen,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
      ],
    );

    return _wrapWithSizing(media);
  }
}

class _PostViewerFullscreenVideoPage extends StatelessWidget {
  const _PostViewerFullscreenVideoPage({
    required this.videoUrl,
    this.thumbnailUrl,
  });

  final String videoUrl;
  final String? thumbnailUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: PostViewerVideoPlayer(
          videoUrl: videoUrl,
          thumbnailUrl: thumbnailUrl,
          height: null,
          autoplay: true,
          enableFullscreen: false,
          borderRadius: 0,
        ),
      ),
    );
  }
}
