import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pay_go/services/api_service.dart';
import 'package:pay_go/services/app_cache_managers.dart';
import 'package:pay_go/utils/time_formatter.dart';
import 'package:pay_go/widgets/comments_sheet.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'profile_page.dart';

class PostDetailPage extends StatefulWidget {
  final String postId;

  const PostDetailPage({super.key, required this.postId});

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  final ApiService _apiService = ApiService();
  final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;

  Map<String, dynamic>? _post;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isLiked = false;
  int _likeCount = 0;
  int _commentCount = 0;
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    _loadPost();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _loadPost() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Fetch all posts and find the specific one
      final posts = await _apiService.getPosts(forceRefresh: true);
      final post = posts.firstWhere(
        (p) => p['id'] == widget.postId || p['_id'] == widget.postId,
        orElse: () => null,
      );

      if (post == null) {
        throw Exception('Post not found');
      }

      if (!mounted) return;

      setState(() {
        _post = post;
        _isLiked = post['isLiked'] == true;
        _likeCount = post['likesCount'] ?? post['likes'] ?? 0;
        _commentCount = post['commentsCount'] ?? post['comments'] ?? 0;
        _isLoading = false;
      });

      // Initialize video if present
      _initializeVideo();
    } catch (e) {
      debugPrint('Error loading post: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _initializeVideo() {
    if (_post == null) return;

    final videoUrl = _post!['videoUrl'] as String?;
    if (videoUrl != null && videoUrl.isNotEmpty) {
      final fullVideoUrl = _apiService.getFullImageUrl(videoUrl);
      _videoController =
          VideoPlayerController.networkUrl(Uri.parse(fullVideoUrl))
            ..initialize().then((_) {
              if (mounted) {
                setState(() {
                  _isVideoInitialized = true;
                });
              }
            });
    }
  }

  Future<void> _toggleLike() async {
    if (_post == null) return;

    final postId = _post!['id'] ?? _post!['_id'];
    if (postId == null) return;

    final wasLiked = _isLiked;
    final previousCount = _likeCount;

    // Optimistic update
    setState(() {
      _isLiked = !_isLiked;
      _likeCount = _isLiked ? _likeCount + 1 : _likeCount - 1;
    });

    try {
      if (wasLiked) {
        await _apiService.unlikePost(postId);
      } else {
        final postOwnerId = _post!['userId'];
        await _apiService.likePost(postId, postOwnerId: postOwnerId);
      }
    } catch (e) {
      debugPrint('Error toggling like: $e');
      // Revert on error
      if (mounted) {
        setState(() {
          _isLiked = wasLiked;
          _likeCount = previousCount;
        });
      }
      _showSnackBar('Failed to ${wasLiked ? 'unlike' : 'like'} post');
    }
  }

  void _showComments() {
    if (_post == null) return;

    final postId = _post!['id'] ?? _post!['_id'];
    final postOwnerId = _post!['userId'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: CommentsSheet(
            apiService: _apiService,
            postId: postId,
            postOwnerId: postOwnerId,
            initialCommentCount: _commentCount,
            onCountUpdated: (count) {
              if (mounted) {
                setState(() {
                  _commentCount = count;
                });
              }
            },
          ),
        ),
      ),
    );
  }

  void _sharePost() {
    if (_post == null) return;
    final caption = _post!['caption'] ?? '';
    Share.share('Check out this post: $caption');
  }

  void _navigateToProfile(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ProfilePage(userId: userId)),
    );
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
        title: const Text('Post'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
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
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'Error',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadPost, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_post == null) {
      return const Center(child: Text('Post not found'));
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPostHeader(),
          _buildPostMedia(),
          _buildPostActions(),
          _buildLikesCount(),
          _buildCaption(),
          _buildTimestamp(),
          const Divider(),
          _buildCommentsButton(),
        ],
      ),
    );
  }

  Widget _buildPostHeader() {
    final author = _post!['author'] as Map<String, dynamic>?;
    final username = author?['username'] ?? 'Unknown User';
    final profilePicUrl = author?['profilePicUrl'] as String?;
    final userId = _post!['userId'] as String?;

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        children: [
          GestureDetector(
            onTap: userId != null ? () => _navigateToProfile(userId) : null,
            child: CircleAvatar(
              radius: 20,
              backgroundColor: Colors.grey[300],
              backgroundImage: profilePicUrl != null && profilePicUrl.isNotEmpty
                  ? CachedNetworkImageProvider(
                      _apiService.getFullImageUrl(profilePicUrl),
                    )
                  : null,
              child: profilePicUrl == null || profilePicUrl.isEmpty
                  ? Text(
                      username.isNotEmpty ? username[0].toUpperCase() : 'U',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: userId != null ? () => _navigateToProfile(userId) : null,
              child: Text(
                username,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostMedia() {
    final imageUrl = _post!['imageUrl'] as String?;
    final videoUrl = _post!['videoUrl'] as String?;

    if (videoUrl != null && videoUrl.isNotEmpty) {
      return _buildVideoPlayer();
    } else if (imageUrl != null && imageUrl.isNotEmpty) {
      return _buildImage(imageUrl);
    }

    return const SizedBox.shrink();
  }

  Widget _buildVideoPlayer() {
    if (_videoController == null || !_isVideoInitialized) {
      return Container(
        width: double.infinity,
        height: 400,
        color: Colors.black,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          if (_videoController!.value.isPlaying) {
            _videoController!.pause();
          } else {
            _videoController!.play();
          }
        });
      },
      child: AspectRatio(
        aspectRatio: _videoController!.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(_videoController!),
            if (!_videoController!.value.isPlaying)
              const Icon(
                Icons.play_circle_outline,
                size: 64,
                color: Colors.white,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(String imageUrl) {
    final fullUrl = _apiService.getFullImageUrl(imageUrl);

    return CachedNetworkImage(
      cacheManager: AppCacheManagers.imageCache,
      imageUrl: fullUrl,
      width: double.infinity,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        height: 400,
        color: Colors.grey[200],
        child: const Center(child: CircularProgressIndicator()),
      ),
      errorWidget: (context, url, error) => Container(
        height: 400,
        color: Colors.grey[300],
        child: const Center(
          child: Icon(Icons.error_outline, size: 64, color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildPostActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              _isLiked ? Icons.favorite : Icons.favorite_border,
              color: _isLiked ? Colors.red : Colors.black,
            ),
            onPressed: _toggleLike,
          ),
          IconButton(
            icon: const Icon(Icons.comment_outlined),
            onPressed: _showComments,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: _sharePost,
          ),
        ],
      ),
    );
  }

  Widget _buildLikesCount() {
    if (_likeCount == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Text(
        '$_likeCount ${_likeCount == 1 ? 'like' : 'likes'}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildCaption() {
    final caption = _post!['caption'] as String?;
    if (caption == null || caption.isEmpty) return const SizedBox.shrink();

    final author = _post!['author'] as Map<String, dynamic>?;
    final username = author?['username'] ?? 'Unknown User';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black, fontSize: 14),
          children: [
            TextSpan(
              text: username,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const TextSpan(text: ' '),
            TextSpan(text: caption),
          ],
        ),
      ),
    );
  }

  Widget _buildTimestamp() {
    final createdAt = _post!['createdAt'];
    if (createdAt == null) return const SizedBox.shrink();

    String? formattedTime;
    if (createdAt is String) {
      final date = DateTime.tryParse(createdAt);
      if (date != null) {
        formattedTime = formatTimestamp(date);
      }
    }

    if (formattedTime == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: Text(
        formattedTime,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
    );
  }

  Widget _buildCommentsButton() {
    return ListTile(
      leading: const Icon(Icons.comment_outlined),
      title: Text(
        'View all ${_commentCount > 0 ? _commentCount : ''} comments',
        style: TextStyle(color: Colors.grey[600]),
      ),
      onTap: _showComments,
    );
  }
}
