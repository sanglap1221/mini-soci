import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/api_service.dart';
import '../utils/image_crop_helper.dart';
import '../utils/post_viewer.dart';
import '../utils/time_formatter.dart';
import 'chat_screen.dart';

class ProfilePage extends StatefulWidget {
  final String? userId;
  const ProfilePage({super.key, this.userId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
  late final String profileUserId;
  late final bool isCurrentUserProfile;

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
    final cUserId = FirebaseAuth.instance.currentUser?.uid;
    profileUserId = widget.userId ?? cUserId!;
    isCurrentUserProfile = profileUserId == cUserId;

    _loadProfile();
    _refreshUserPosts();
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    try {
      final data = await _apiService.getProfile(profileUserId);
      debugPrint('Profile data loaded: $data');
      if (!mounted) return;
      setState(() {
        _userData = data;
      });
      _refreshUserPosts();
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to load profile')));
    }
  }

  void _refreshUserPosts() {
    setState(() {
      _userPostsFuture = _apiService.getUserPosts(profileUserId);
    });
  }

  Future<void> _editBio(BuildContext context, String currentBio) async {
    final TextEditingController controller = TextEditingController(
      text: currentBio,
    );

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (currentUserId != null && _userData != null) {
                await _apiService.updateProfile(
                  username: _userData!['username'],
                  bio: controller.text.trim(),
                );
                if (!mounted) return;
                setState(() {
                  _userData = {..._userData!, 'bio': controller.text.trim()};
                });
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
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
      builder: (dialogContext) => AlertDialog(
        title: Text('Edit Username'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => {Navigator.pop(dialogContext)},
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty && _userData != null) {
                final newUsername = controller.text.trim();
                await _apiService.updateProfile(
                  username: newUsername,
                  bio: _userData!['bio'] ?? '',
                );

                final currentUser = FirebaseAuth.instance.currentUser;
                try {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(profileUserId)
                      .set({'username': newUsername}, SetOptions(merge: true));
                } catch (e) {
                  debugPrint('Failed to sync username to Firestore: $e');
                }

                if (currentUser != null) {
                  try {
                    await currentUser.updateDisplayName(newUsername);
                  } catch (e) {
                    debugPrint('Failed to update auth display name: $e');
                  }
                }
                if (!mounted) return;
                setState(() {
                  _userData = {..._userData!, 'username': newUsername};
                });
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
              }
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    File? previousLocalImage = _localProfileImage;

    try {
      final croppedFile = await ImageCropHelper.pickAvatar(context);
      if (croppedFile == null) return;

      if (!mounted) return;
      final confirmed = await _showAvatarConfirmationSheet(croppedFile);
      if (confirmed != true || !mounted) return;

      setState(() {
        _localProfileImage = croppedFile;
      });

      await _uploadProfilePicture(croppedFile);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _localProfileImage = previousLocalImage;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool?> _showAvatarConfirmationSheet(File croppedFile) {
    return showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Use this profile picture?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),
            CircleAvatar(
              radius: 70,
              backgroundColor: Colors.grey[300],
              child: ClipOval(
                child: Image.file(
                  croppedFile,
                  width: 140,
                  height: 140,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                    child: const Text('Retake'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    child: const Text('Use Photo'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadProfilePicture(File file) async {
    final messenger = ScaffoldMessenger.of(context);

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(width: 16),
            Text('Uploading profile picture...'),
          ],
        ),
        duration: const Duration(seconds: 1),
      ),
    );

    final result = await _apiService.updateProfilePicture(file);

    await FirebaseFirestore.instance
        .collection('users')
        .doc(profileUserId)
        .update({'profilePicUrl': result['profilePicUrl']});

    if (!mounted) return;
    setState(() {
      _userData = {...?_userData, 'profilePicUrl': result['profilePicUrl']};
    });

    messenger.showSnackBar(
      const SnackBar(
        content: Text('Profile picture updated successfully'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildProfilePicture(Map<String, dynamic>? userData) {
    return Stack(
      children: [
        GestureDetector(
          onTap: isCurrentUserProfile ? _showProfileOptions : null,
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
        if (isCurrentUserProfile)
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

  Widget _buildProfileHeader() {
    final username = _userData?['username'] ?? 'Username';
    final bio = _userData?['bio'] as String?;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          _buildProfilePicture(_userData),
          const SizedBox(height: 16),
          if (isCurrentUserProfile)
            GestureDetector(
              onTap: () => _editUsername(context, username),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    username,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.edit, size: 20),
                ],
              ),
            )
          else
            Text(
              username,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          const SizedBox(height: 8),
          if (isCurrentUserProfile)
            GestureDetector(
              onTap: () => _editBio(context, bio ?? ''),
              child: Container(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    Text(
                      bio?.isNotEmpty == true ? bio! : 'Tap to add bio',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: bio == null || bio.isEmpty
                            ? Colors.grey
                            : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Icon(Icons.edit, size: 16),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                bio?.isNotEmpty == true ? bio! : 'No bio available.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          if (!isCurrentUserProfile)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: ElevatedButton.icon(
                onPressed: _startChat,
                icon: const Icon(Icons.message_outlined),
                label: const Text('Message'),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPostsSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'Posts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          FutureBuilder<List<dynamic>>(
            future: _userPostsFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32.0),
                  child: Center(
                    child: Text('Error loading posts: ${snapshot.error}'),
                  ),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32.0),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final posts = snapshot.data ?? const [];
              if (posts.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32.0),
                  child: Center(
                    child: Text(
                      'No posts yet',
                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
                    ),
                  ),
                );
              }

              return _buildPostGrid(posts);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPostGrid(List<dynamic> posts) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final rawPost = posts[index];
        final post = rawPost is Map<String, dynamic>
            ? rawPost
            : <String, dynamic>{'imageUrl': '', 'caption': '', 'createdAt': ''};
        return _buildPostTile(context, post);
      },
    );
  }

  Widget _buildPostTile(BuildContext context, Map<String, dynamic> post) {
    final imagePath = post['imageUrl'] as String?;
    final caption = post['caption']?.toString();
    final createdAt = post['createdAt'];
    final formattedInfo = formatTimestamp(createdAt);
    final postId = _extractPostId(post);
    final likeCount = _readLikeCount(post) ?? 0;
    final commentCount = _readCommentCount(post) ?? 0;
    final isLiked = _readIsLiked(post) ?? false;

    return GestureDetector(
      onTap: () {
        PostViewer.show(
          context: context,
          apiService: _apiService,
          relativeImagePath: imagePath,
          caption: caption,
          infoText: formattedInfo != null ? 'Posted $formattedInfo' : null,
          postId: postId,
          initialLikeCount: likeCount,
          initialCommentCount: commentCount,
          initialIsLiked: isLiked,
          onInteractionChanged: postId == null
              ? null
              : (interaction) {
                  if (!mounted) return;
                  setState(() {
                    final currentLikeCount = _readLikeCount(post) ?? likeCount;
                    final currentCommentCount =
                        _readCommentCount(post) ?? commentCount;
                    final currentIsLiked = _readIsLiked(post) ?? isLiked;

                    final nextLikeCount = interaction.likeCount != null
                        ? _clampNonNegative(interaction.likeCount!)
                        : currentLikeCount;
                    final nextCommentCount = interaction.commentCount != null
                        ? _clampNonNegative(interaction.commentCount!)
                        : currentCommentCount;
                    final nextIsLiked = interaction.isLiked ?? currentIsLiked;

                    _applyInteractionUpdatesToPost(
                      post,
                      likeCount: nextLikeCount,
                      commentCount: nextCommentCount,
                      isLiked: nextIsLiked,
                    );
                  });
                },
        );
      },
      onLongPress: isCurrentUserProfile
          ? () => _showPostOptions(context, post)
          : null,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey[300]!, width: 0.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildPostImageWidget(imagePath),
              _buildPostTileOverlay(likeCount, commentCount),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPostImageWidget(
    String? relativeUrl, {
    BoxFit fit = BoxFit.cover,
  }) {
    final resolvedUrl = _resolvePostImageUrl(relativeUrl);
    if (resolvedUrl == null) {
      return Container(
        color: Colors.grey[200],
        child: const Icon(Icons.image, color: Colors.grey),
      );
    }

    return Image.network(
      resolvedUrl,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: Colors.grey[200],
          child: Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                  : null,
              strokeWidth: 2,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.grey[200],
          child: const Icon(Icons.error_outline, color: Colors.grey),
        );
      },
    );
  }

  String? _resolvePostImageUrl(String? relativeUrl) {
    if (relativeUrl == null || relativeUrl.isEmpty) {
      return null;
    }
    return _apiService.getFullImageUrl(relativeUrl);
  }

  Widget _buildPostTileOverlay(int likeCount, int commentCount) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.favorite, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            Text(
              '$likeCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            const Icon(
              Icons.mode_comment_outlined,
              color: Colors.white,
              size: 14,
            ),
            const SizedBox(width: 4),
            Text(
              '$commentCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
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

  void _applyInteractionUpdatesToPost(
    Map<String, dynamic> post, {
    int? likeCount,
    int? commentCount,
    bool? isLiked,
  }) {
    if (likeCount != null) {
      post['likeCount'] = likeCount;
      post['likes'] = likeCount;
      post['likesCount'] = likeCount;
      post['totalLikes'] = likeCount;
    }

    if (commentCount != null) {
      post['commentCount'] = commentCount;
      post['comments'] = commentCount;
      post['commentsCount'] = commentCount;
      post['totalComments'] = commentCount;
    }

    if (isLiked != null) {
      post['viewerHasLiked'] = isLiked;
      post['likedByCurrentUser'] = isLiked;
      post['isLiked'] = isLiked;
      post['liked'] = isLiked;
      post['hasLiked'] = isLiked;
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

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _apiService.deleteProfilePicture();
      if (!mounted) return;
      navigator.pop();
      setState(() {
        if (_userData != null) {
          _userData = {..._userData!, 'profilePicUrl': null};
        }
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Profile picture removed'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(
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

  Future<void> _startChat() async {
    if (currentUserId == null) return;

    final participants = [currentUserId, profileUserId]..sort();
    final chatId = participants.join('_');

    final chatDoc = FirebaseFirestore.instance.collection('chats').doc(chatId);
    final chatSnapshot = await chatDoc.get();

    if (!chatSnapshot.exists) {
      await chatDoc.set({
        'participants': participants,
        'lastMessage': 'Chat started',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unreadCount': 0,
      });
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ChatScreen(chatId: chatId, otherUserId: profileUserId),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(isCurrentUserProfile ? 'My Profile' : 'Profile'),
        actions: [
          if (isCurrentUserProfile)
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
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadProfile,
              child: ListView(
                children: [
                  _buildProfileHeader(),
                  const Divider(),
                  _buildPostsSection(),
                ],
              ),
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
                  child: SizedBox(
                    width: 60,
                    height: 60,
                    child: _buildPostImageWidget(
                      post['imageUrl'] as String?,
                      fit: BoxFit.cover,
                    ),
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
                        () {
                          final formatted = formatTimestamp(post['createdAt']);
                          return formatted != null
                              ? 'Posted $formatted'
                              : 'Posted date unavailable';
                        }(),
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
              child: SizedBox(
                width: 120,
                height: 120,
                child: _buildPostImageWidget(
                  post['imageUrl'] as String?,
                  fit: BoxFit.cover,
                ),
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
}
