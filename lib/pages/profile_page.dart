import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final String? userId = FirebaseAuth.instance.currentUser?.uid;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final _apiService = ApiService();
  File? _localProfileImage;
  Map<String, dynamic>? _userData;
  Future<List<dynamic>>? _userPostsFuture;

  bool get _hasProfileImage =>
      _localProfileImage != null ||
      ((_userData?['profilePicUrl'] as String?)?.isNotEmpty ?? false);

  String? get _remoteProfileImageUrl =>
      (_userData?['profilePicUrl'] as String?)?.isNotEmpty == true
      ? _userData!['profilePicUrl'] as String
      : null;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _refreshUserPosts();
  }

  Future<void> _loadProfile() async {
    try {
      if (userId != null) {
        final data = await _apiService.getProfile(userId!);
        print('Profile data loaded: $data'); // Debug log
        if (mounted) {
          setState(() {
            _userData = data;
          });
          _refreshUserPosts();
        }
      }
    } catch (e) {
      print('Error loading profile: $e'); // Debug log
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load profile')));
      }
    }
  }

  void _refreshUserPosts() {
    if (userId == null) return;
    setState(() {
      _userPostsFuture = _apiService.getUserPosts(userId!);
    });
  }

  Future<void> _editBio(BuildContext context, String currentBio) async {
    final TextEditingController controller = TextEditingController(
      text: currentBio,
    );

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Bio'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Write something about yourself...',
          ),
          maxLength: 1000,
          maxLines: 5,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (userId != null && _userData != null) {
                await _apiService.updateProfile(
                  username: _userData!['username'],
                  bio: controller.text.trim(),
                );
                setState(() {
                  _userData = {..._userData!, 'bio': controller.text.trim()};
                });
                Navigator.pop(context);
              }
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _editUsername(
    BuildContext context,
    String currentUsername,
  ) async {
    final TextEditingController controller = TextEditingController(
      text: currentUsername,
    );

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Username'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => {Navigator.pop(context)},
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty && _userData != null) {
                await _apiService.updateProfile(
                  username: controller.text.trim(),
                  bio: _userData!['bio'] ?? '',
                );
                setState(() {
                  _userData = {
                    ..._userData!,
                    'username': controller.text.trim(),
                  };
                });
                Navigator.pop(context);
              }
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxHeight: 1024,
        maxWidth: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _localProfileImage = File(image.path);
        });

        // Show loading indicator
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(width: 16),
                Text('Uploading profile picture...'),
              ],
            ),
            duration: Duration(seconds: 1),
          ),
        );

        // Upload profile picture using the API service
        final result = await _apiService.updateProfilePicture(
          _localProfileImage!,
        );

        // Update the UI with the new profile picture URL
        if (mounted) {
          setState(() {
            _userData = {
              ..._userData!,
              'profilePicUrl': result['profilePicUrl'],
            };
          });
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Profile picture updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      // Show error message with specific error details
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildProfilePicture(Map<String, dynamic>? userData) {
    return Stack(
      children: [
        GestureDetector(
          onTap: _showProfileOptions,
          child: CircleAvatar(
            radius: 50,
            backgroundColor: Colors.grey[300],
            child: _localProfileImage != null
                ? ClipOval(
                    child: Image.file(
                      _localProfileImage!,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                    ),
                  )
                : _remoteProfileImageUrl != null
                ? ClipOval(
                    child: Image.network(
                      _apiService.getFullImageUrl(_remoteProfileImageUrl!),
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 100,
                          height: 100,
                          color: Colors.grey[300],
                          child: Icon(
                            Icons.person,
                            size: 40,
                            color: Colors.grey[600],
                          ),
                        );
                      },
                    ),
                  )
                : Text(
                    (userData?['username'] ?? '?')[0].toUpperCase(),
                    style: TextStyle(fontSize: 40, color: Colors.blue),
                  ),
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: GestureDetector(
            onTap: _pickImage,
            child: Container(
              padding: EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.camera_alt, size: 20, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  void _showProfileOptions() {
    if (!_hasProfileImage) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No profile picture to display')));
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.visibility),
            title: Text("View Picture"),
            onTap: () {
              Navigator.pop(context);
              _showProfilePictureViewer();
            },
          ),
          ListTile(
            leading: Icon(Icons.delete, color: Colors.red),
            title: Text("Remove Picture", style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _removeProfilePicture();
            },
          ),
        ],
      ),
    );
  }

  void _showProfilePictureViewer() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: EdgeInsets.all(16),
        child: InteractiveViewer(
          child: _localProfileImage != null
              ? Image.file(_localProfileImage!, fit: BoxFit.contain)
              : (_remoteProfileImageUrl != null
                    ? Image.network(
                        _apiService.getFullImageUrl(_remoteProfileImageUrl!),
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            padding: EdgeInsets.all(32),
                            alignment: Alignment.center,
                            child: Icon(Icons.error_outline, size: 48),
                          );
                        },
                      )
                    : SizedBox.shrink()),
        ),
      ),
    );
  }

  Future<void> _removeProfilePicture() async {
    if (_localProfileImage != null) {
      setState(() {
        _localProfileImage = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Profile picture removed')));
      return;
    }

    if (_remoteProfileImageUrl == null) {
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Removing picture...'),
          ],
        ),
      ),
    );

    try {
      await _apiService.deleteProfilePicture();
      if (!mounted) return;
      Navigator.of(context).pop();
      setState(() {
        if (_userData != null) {
          _userData = {..._userData!, 'profilePicUrl': null};
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Profile picture removed'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to remove profile picture'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to sign out')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (userId == null) {
      return Center(child: Text('Please login to view profile'));
    }

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text('Profile'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              _scaffoldKey.currentState?.openEndDrawer();
            },
          ),
        ],
      ),
      endDrawer: Drawer(
        child: ListView(
          children: [
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.all(Radius.elliptical(5, 10)),
              ),
              child: Center(
                child: Text(
                  "Settings",
                  style: TextStyle(color: Colors.white, fontSize: 24),
                ),
              ),
            ),
            ListTile(
              //let ne
              leading: Icon(Icons.logout, color: Colors.red),
              title: Text("Sign Out", style: TextStyle(color: Colors.red)),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Sign Out'),
                    content: Text('Are you sure you want to sign out?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.pop(context);
                          _signOut();
                        },
                        child: Text(
                          'Sign Out',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),

      body: _userData == null
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadProfile,
                    child: ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              _buildProfilePicture(_userData),
                              SizedBox(height: 16),
                              GestureDetector(
                                onTap: () => _editUsername(
                                  context,
                                  _userData?['username'] ?? 'Username',
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _userData?['username'] ?? 'Username',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(Icons.edit, size: 20),
                                  ],
                                ),
                              ),
                              SizedBox(height: 8),
                              GestureDetector(
                                onTap: () =>
                                    _editBio(context, _userData?['bio'] ?? ''),
                                child: Container(
                                  padding: EdgeInsets.all(8),
                                  child: Column(
                                    children: [
                                      Text(
                                        _userData?['bio'] ?? 'Tap to add bio',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: _userData?['bio'] == null
                                              ? Colors.grey
                                              : Colors.black,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Icon(Icons.edit, size: 16),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Posts grid
                        // Posts grid
                        FutureBuilder<List<dynamic>>(
                          future: _userPostsFuture,
                          builder: (context, postsSnapshot) {
                            if (postsSnapshot.hasError) {
                              return Center(
                                child: Text(
                                  'Error loading posts: ${postsSnapshot.error}',
                                ),
                              );
                            }

                            if (postsSnapshot.connectionState ==
                                ConnectionState.waiting) {
                              return Center(child: CircularProgressIndicator());
                            }

                            final posts = postsSnapshot.data ?? [];

                            if (posts.isEmpty) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Text(
                                    'No posts yet',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              );
                            }

                            return GridView.builder(
                              shrinkWrap: true,
                              physics: NeverScrollableScrollPhysics(),
                              padding: EdgeInsets.all(4),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 4,
                                    mainAxisSpacing: 4,
                                  ),
                              itemCount: posts.length,
                              itemBuilder: (context, index) {
                                final post = posts[index];
                                return GestureDetector(
                                  onTap: () {
                                    // TODO: Navigate to post detail page
                                  },
                                  onLongPress: () {
                                    _showPostOptions(context, post);
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: Colors.grey[300]!,
                                        width: 0.5,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Image.network(
                                        _apiService.getFullImageUrl(
                                          post['imageUrl'] ?? '',
                                        ),
                                        fit: BoxFit.cover,
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) {
                                            return child;
                                          }
                                          return Container(
                                            color: Colors.grey[200],
                                            child: Center(
                                              child: CircularProgressIndicator(
                                                value:
                                                    loadingProgress
                                                            .expectedTotalBytes !=
                                                        null
                                                    ? loadingProgress
                                                              .cumulativeBytesLoaded /
                                                          loadingProgress
                                                              .expectedTotalBytes!
                                                    : null,
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          );
                                        },
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                              return Container(
                                                color: Colors.grey[200],
                                                child: Icon(
                                                  Icons.error_outline,
                                                  color: Colors.grey[400],
                                                ),
                                              );
                                            },
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  void _showPostOptions(BuildContext context, Map<String, dynamic> post) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    _apiService.getFullImageUrl(post['imageUrl'] ?? ''),
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 60,
                        height: 60,
                        color: Colors.grey[300],
                        child: Icon(Icons.image, color: Colors.grey[600]),
                      );
                    },
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post['caption']?.toString().isNotEmpty == true
                            ? post['caption']
                            : 'No caption',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Posted ${_formatDate(post['createdAt'])}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1),
          ListTile(
            leading: Icon(Icons.delete, color: Colors.red),
            title: Text('Delete Post', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _showDeleteConfirmation(post);
            },
          ),
          ListTile(
            leading: Icon(Icons.close),
            title: Text('Cancel'),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(Map<String, dynamic> post) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Post'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                _apiService.getFullImageUrl(post['imageUrl'] ?? ''),
                width: 120,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 120,
                    height: 120,
                    color: Colors.grey[300],
                    child: Icon(Icons.image, color: Colors.grey[600]),
                  );
                },
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Are you sure you want to delete this post? This action cannot be undone.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deletePost(post);
            },
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePost(Map<String, dynamic> post) async {
    try {
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

      await _apiService.deletePost(post['_id']);

      if (mounted) {
        Navigator.of(context).pop();
        _refreshUserPosts();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Post deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete post: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'just now';
    try {
      final date = DateTime.parse(dateString).toLocal();
      final difference = DateTime.now().difference(date);

      if (difference.inDays >= 1) {
        return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
      }
      if (difference.inHours >= 1) {
        return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
      }
      if (difference.inMinutes >= 1) {
        return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
      }
      return 'Just now';
    } catch (_) {
      return 'Just now';
    }
  }
}
