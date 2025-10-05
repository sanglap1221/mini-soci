import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/api_service.dart';
import '../utils/time_formatter.dart';

class CommentsSheet extends StatefulWidget {
  const CommentsSheet({
    super.key,
    required this.apiService,
    required this.postId,
    this.initialCommentCount = 0,
    this.onCountUpdated,
  });

  final ApiService apiService;
  final String postId;
  final int initialCommentCount;
  final ValueChanged<int>? onCountUpdated;

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  final List<dynamic> _comments = <dynamic>[];
  int _commentCount = 0;
  final Set<String> _deletingCommentIds = <String>{};

  @override
  void initState() {
    super.initState();
    _commentCount = widget.initialCommentCount;
    _loadComments();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await widget.apiService.getComments(
        widget.postId,
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
      });
      widget.onCountUpdated?.call(_commentCount);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshComments() => _loadComments();

  Future<void> _submitComment() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSubmitting) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final result = await widget.apiService.addComment(widget.postId, text);
      final comment = _extractComment(result) ?? _fallbackComment(text);

      if (!mounted) return;
      setState(() {
        _comments.insert(0, comment);
        _controller.clear();
        _commentCount += 1;
      });
      widget.onCountUpdated?.call(_commentCount);
      _focusNode.requestFocus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add comment: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
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
      await widget.apiService.deleteComment(commentId);
      if (!mounted) return;
      setState(() {
        _comments.removeWhere(
          (element) => _extractCommentId(element) == commentId,
        );
        _commentCount = (_commentCount - 1).clamp(0, 1 << 30);
      });
      widget.onCountUpdated?.call(_commentCount);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete comment: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _deletingCommentIds.remove(commentId);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return FractionallySizedBox(
      heightFactor: 0.85,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(height: 16),
              Text('Comments', style: Theme.of(context).textTheme.titleMedium),
              Text(
                '$_commentCount total',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildCommentsList()),
              const Divider(height: 1),
              _buildComposer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommentsList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _comments.isEmpty) {
      return Center(
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
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadComments,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_comments.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshComments,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 80),
            Icon(Icons.mode_comment_outlined, size: 40, color: Colors.grey),
            SizedBox(height: 12),
            Center(child: Text('Be the first to comment.')),
            SizedBox(height: 200),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshComments,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _comments.length,
        separatorBuilder: (_, __) => const Divider(height: 16),
        itemBuilder: (context, index) {
          final comment = _comments[index];
          return _buildCommentTile(comment);
        },
      ),
    );
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

  Widget _buildComposer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
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
            onPressed: _isSubmitting ? null : _submitComment,
            icon: _isSubmitting
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

  List<dynamic> _extractItems(Map<String, dynamic> payload) {
    final items = payload['items'] ?? payload['comments'] ?? payload['data'];
    if (items is List) {
      return items;
    }
    if (items == null) {
      // Some APIs may return the list at the top level.
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
    if (comment is Map<String, dynamic>) {
      final author = comment['author'];
      if (author is Map<String, dynamic>) {
        final candidate = author['username'] ?? author['name'];
        if (candidate is String && candidate.trim().isNotEmpty) {
          return candidate.trim();
        }
      }
      final user = comment['user'];
      if (user is Map<String, dynamic>) {
        final candidate = user['username'] ?? user['name'];
        if (candidate is String && candidate.trim().isNotEmpty) {
          return candidate.trim();
        }
      }
      final direct = comment['username'] ?? comment['userName'];
      if (direct is String && direct.trim().isNotEmpty) {
        return direct.trim();
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
