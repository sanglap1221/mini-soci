import 'package:flutter/material.dart';
import 'package:pay_go/services/api_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  @override
  void initState() {
    super.initState();
    print('FeedPage initState called'); // Debug log
    _loadPosts();
  }

  @override
  void didUpdateWidget(covariant FeedPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshTrigger != oldWidget.refreshTrigger) {
      print('FeedPage refresh trigger updated');
      _loadPosts();
    }
  }

  Future<void> _loadPosts() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      print('Loading posts...'); // Debug log
      final posts = await _apiService.getPosts();

      if (mounted) {
        setState(() {
          _posts = posts;
          _isLoading = false;
        });
        print('Posts loaded successfully: ${posts.length} posts'); // Debug log
      }
    } catch (e) {
      print('Error loading posts: $e'); // Debug log
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
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

      // Remove post from local list
      setState(() {
        _posts!.removeAt(index);
      });

      // Close loading dialog
      Navigator.of(context).pop();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Post deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Close loading dialog
      Navigator.of(context).pop();

      // Show error message
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
    print('refreshPosts called externally'); // Debug log
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
    print(
      'FeedPage build method called - isLoading: $_isLoading, postsCount: ${_posts?.length}',
    ); // Debug log
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
        final isOwnPost = post['userId'] == currentUserId;

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
                      child: post['author']?['profilePicUrl'] != null
                          ? ClipOval(
                              child: Image.network(
                                _apiService.getFullImageUrl(
                                  post['author']['profilePicUrl'],
                                ),
                                width: 32,
                                height: 32,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Icon(
                                    Icons.person,
                                    size: 16,
                                    color: Colors.grey[600],
                                  );
                                },
                              ),
                            )
                          : Text(
                              (post['author']?['username'] ?? 'U')[0]
                                  .toUpperCase(),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue,
                              ),
                            ),
                    ),
                    GestureDetector(
                      onTap: () => _navigateToUserProfile(post['userId']),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Row(
                          children: [
                            // Author name
                            Text(
                              post['author']?['username'] ?? 'Unknown User',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
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
                          if (value == 'delete') {
                            _showDeleteConfirmation(post['_id'], index);
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
              _buildPostImage(post),
              // Post caption
              Padding(
                padding: EdgeInsets.all(8),
                child: Text(post['caption'] ?? ''),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPostImage(Map<String, dynamic> post) {
    final imageUrl = _apiService.getFullImageUrl(post['imageUrl'] ?? '');
    print('Loading image with URL: $imageUrl'); // Debug log

    return Image.network(
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
        print('Error loading image: $error'); // Debug log
        return Container(
          height: 200,
          color: Colors.grey[300],
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 40, color: Colors.grey[600]),
              SizedBox(height: 8),
              Text(
                'Failed to load image',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        );
      },
    );
  }
}
