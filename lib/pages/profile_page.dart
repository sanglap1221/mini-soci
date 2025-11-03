import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../services/app_cache_managers.dart';
import '../utils/image_crop_helper.dart';
import '../utils/post_viewer.dart';
import '../utils/time_formatter.dart';
import 'chat_screen.dart';
import '../services/theme_controller.dart';
import 'friends_list_page.dart';

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
  bool _isRelationshipActionInFlight = false;
  RelationshipStatus _relationshipStatus = RelationshipStatus.none;
  String? _pendingRequestId;

  bool get _hasProfileImage =>
      _localProfileImage != null ||
      ((_userData?['profilePicUrl'] as String?)?.isNotEmpty ?? false);

  String? get _remoteProfileImageUrl =>
      (_userData?['profilePicUrl'] as String?)?.isNotEmpty == true
      ? _userData!['profilePicUrl'] as String
      : null;

  int get _followerCount => (_userData?['followerCount'] as num?)?.toInt() ?? 0;

  int get _followingCount =>
      (_userData?['followingCount'] as num?)?.toInt() ?? 0;

  int get _friendCount => (_userData?['friendCount'] as num?)?.toInt() ?? 0;

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
      final profile = await _apiService.getProfile(
        profileUserId,
        forceRefresh: true,
      );

      debugPrint('Profile data loaded: $profile');
      final summary = await _refreshRelationshipSummary();
      if (!mounted) return;
      setState(() {
        _userData = {
          ...profile,
          'followerCount': summary.followerCount,
          'followingCount': summary.followingCount,
          'friendCount': summary.friendCount,
        };
        _setRelationshipSummaryState(summary);
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

  Future<RelationshipSummary> _refreshRelationshipSummary() async {
    try {
      var summary = await _apiService.getRelationshipSummary(
        profileUserId,
        forceRefresh: true,
      );
      if (summary.status == RelationshipStatus.pendingIncoming &&
          summary.pendingRequestId == null) {
        try {
          final incoming = await _apiService.getIncomingFriendRequests();
          final pendingId = _findMatchingRequestId(incoming);
          if (pendingId != null) {
            summary = summary.copyWith(pendingRequestId: pendingId);
          }
        } catch (e, stack) {
          debugPrint('Failed to load incoming requests: $e');
          debugPrint('$stack');
        }
      }
      return summary;
    } catch (e, stack) {
      debugPrint('Failed to refresh relationship summary: $e');
      debugPrint('$stack');
      return RelationshipSummary(
        status: RelationshipStatus.none,
        pendingRequestId: null,
        followerCount: _asInt(_userData?['followerCount']) ?? 0,
        followingCount: _asInt(_userData?['followingCount']) ?? 0,
        friendCount: _asInt(_userData?['friendCount']) ?? 0,
      );
    }
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
                await _syncUserDocument({'username': newUsername});

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

    await _syncUserDocument({'profilePicUrl': result['profilePicUrl']});

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

  Future<void> _syncUserDocument(Map<String, dynamic> data) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(profileUserId)
          .set(data, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        debugPrint('Firestore sync skipped: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Profile saved, but Firestore permissions blocked the sync.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        debugPrint('Unexpected Firestore error: $e');
      }
    } catch (e) {
      debugPrint('Failed to sync user document: $e');
    }
  }

  Widget _buildProfilePicture(Map<String, dynamic>? userData) {
    return Stack(
      children: [
        Container(
          decoration: isCurrentUserProfile
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).primaryColor,
                    width: 2.5,
                  ),
                )
              : null,
          child: GestureDetector(
            onTap: isCurrentUserProfile ? _showProfileOptions : null,
            child: CircleAvatar(
              radius: 60,
              backgroundColor: Colors.grey[300],
              child: _localProfileImage != null
                  ? ClipOval(
                      child: Image.file(
                        _localProfileImage!,
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                      ),
                    )
                  : _remoteProfileImageUrl != null
                  ? ClipOval(
                      child: CachedNetworkImage(
                        cacheManager: AppCacheManagers.imageCache,
                        imageUrl: _apiService.getFullImageUrl(
                          _remoteProfileImageUrl!,
                        ),
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          width: 120,
                          height: 100,
                          alignment: Alignment.center,
                          color: Colors.grey[300],
                          child: const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: 120,
                          height: 100,
                          color: Colors.grey[300],
                          child: Icon(
                            Icons.person,
                            size: 40,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    )
                  : Text(
                      (userData?['username'] ?? '?')[0].toUpperCase(),
                      style: TextStyle(
                        fontSize: 48,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
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
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_alt,
                  size: 22,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProfileHeader() {
    final username = _userData?['username'] ?? 'Username';
    final bio = _userData?['bio'] as String?;
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                  Icon(Icons.edit, size: 20, color: Colors.grey[600]),
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
                        color: (bio == null || bio.isEmpty)
                            ? (isDark ? Colors.white60 : Colors.grey)
                            : (isDark ? Colors.white : Colors.black),
                      ),
                    ),
                    const SizedBox(height: 6),
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
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.grey[600],
                ),
              ),
            ),
          _buildFriendCountRow(),
          if (!isCurrentUserProfile) ...[
            if (_relationshipStatus == RelationshipStatus.pendingIncoming)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: _buildPendingRequestBanner(),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: _buildActionSection(),
            ),
          ],
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildFollowStatsRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildFollowMetric(_followerCount, 'Followers'),
          const SizedBox(width: 32),
          _buildFollowMetric(_followingCount, 'Following'),
        ],
      ),
    );
  }

  Widget _buildFriendCountRow() {
    return InkWell(
      onTap: () {
        debugPrint('Friends count tapped! userId: $profileUserId');
        _navigateToFriendsList();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatCount(_friendCount),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text('Friends', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Widget _buildFollowMetric(int count, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatCount(count),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildActionSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 360;

        if (_relationshipStatus == RelationshipStatus.pendingIncoming) {
          // Only show Message; make sure it fills width and doesn't collide
          return SizedBox(
            width: double.infinity,
            child: _buildMessageButton(isOutlined: false),
          );
        }

        if (narrow) {
          // Stack vertically on narrow screens to avoid overlap between
          // relationship button and message button.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildRelationshipButton(),
              const SizedBox(height: 10),
              _buildMessageButton(isOutlined: true),
            ],
          );
        }

        // Default side-by-side
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(child: _buildRelationshipButton()),
            const SizedBox(width: 12),
            Expanded(child: _buildMessageButton(isOutlined: true)),
          ],
        );
      },
    );
  }

  Widget _buildPendingRequestBanner() {
    final username = _userData?['username'] as String? ?? 'This user';
    final avatarPath = _remoteProfileImageUrl;
    final accent = Theme.of(context).colorScheme.primary;
    final hasRequestId = _pendingRequestId != null;

    Widget buildAvatar() {
      if (avatarPath != null && avatarPath.isNotEmpty) {
        return CircleAvatar(
          radius: 24,
          backgroundImage: CachedNetworkImageProvider(
            _apiService.getFullImageUrl(avatarPath),
          ),
        );
      }
      return CircleAvatar(
        radius: 24,
        backgroundColor: accent.withValues(alpha: 0.1),
        child: Text(
          username.isNotEmpty ? username[0].toUpperCase() : '?',
          style: TextStyle(color: accent, fontWeight: FontWeight.bold),
        ),
      );
    }

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                buildAvatar(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$username sent you a friend request',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Respond to connect and start chatting.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isRelationshipActionInFlight
                        ? null
                        : hasRequestId
                        ? _declinePendingRequest
                        : null,
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isRelationshipActionInFlight
                        ? null
                        : hasRequestId
                        ? _acceptPendingRequest
                        : null,
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRelationshipButton() {
    const height = 40.0;
    switch (_relationshipStatus) {
      case RelationshipStatus.none:
        return SizedBox(
          height: height,
          child: ElevatedButton.icon(
            onPressed: _isRelationshipActionInFlight
                ? null
                : _sendFriendRequest,
            style: ElevatedButton.styleFrom(
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            icon: const Icon(Icons.person_add, size: 18),
            label: const Text(
              'Add Friend',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        );
      case RelationshipStatus.pendingOutgoing:
        return SizedBox(
          height: height,
          child: OutlinedButton.icon(
            onPressed:
                _isRelationshipActionInFlight || _pendingRequestId == null
                ? null
                : _cancelPendingRequest,
            style: OutlinedButton.styleFrom(
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(Icons.hourglass_bottom, size: 18),
            label: const Text('Cancel Request', style: TextStyle(fontSize: 13)),
          ),
        );
      case RelationshipStatus.pendingIncoming:
        return const SizedBox.shrink();
      case RelationshipStatus.friends:
        return SizedBox(
          height: height,
          child: OutlinedButton.icon(
            onPressed: _isRelationshipActionInFlight ? null : _confirmUnfriend,
            style: OutlinedButton.styleFrom(
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Friends', style: TextStyle(fontSize: 14)),
          ),
        );
    }
  }

  Future<void> _confirmUnfriend() async {
    if (_isRelationshipActionInFlight) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Friend?'),
        content: const Text(
          'You will no longer follow each other or be able to chat. Do you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Unfriend'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _unfriend();
    }
  }

  Widget _buildMessageButton({required bool isOutlined}) {
    if (isOutlined) {
      return SizedBox(
        height: 40,
        child: OutlinedButton.icon(
          onPressed: _startChat,
          icon: const Icon(Icons.message_outlined, size: 18),
          label: const Text('Message'),
          style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
        ),
      );
    }
    return SizedBox(
      height: 40,
      child: ElevatedButton.icon(
        onPressed: _startChat,
        icon: const Icon(Icons.message_outlined, size: 18),
        label: const Text('Message'),
      ),
    );
  }

  void _setRelationshipSummaryState(RelationshipSummary summary) {
    _relationshipStatus = isCurrentUserProfile
        ? RelationshipStatus.friends
        : summary.status;
    _pendingRequestId = summary.pendingRequestId;
    if (_userData != null) {
      _userData = {
        ..._userData!,
        'followerCount': summary.followerCount,
        'followingCount': summary.followingCount,
        'friendCount': summary.friendCount,
      };
    }
  }

  void _applyRelationshipSummary(RelationshipSummary summary) {
    if (!mounted) return;
    setState(() {
      _setRelationshipSummaryState(summary);
    });
  }

  String? _findMatchingRequestId(List<Map<String, dynamic>> requests) {
    String? readString(Map<String, dynamic> source, String key) {
      final value = source[key];
      if (value is String && value.isNotEmpty) {
        return value;
      }
      return null;
    }

    String? readNested(Map<String, dynamic> source, List<String> path) {
      dynamic current = source;
      for (final segment in path) {
        if (current is Map<String, dynamic> && current.containsKey(segment)) {
          current = current[segment];
        } else {
          return null;
        }
      }
      return current is String && current.isNotEmpty ? current : null;
    }

    for (final request in requests) {
      final fromId =
          readString(request, 'fromUserId') ??
          readNested(request, ['fromUser', 'id']) ??
          readNested(request, ['fromUser', '_id']);
      final toId = readString(request, 'toUserId');

      if (fromId == profileUserId || toId == profileUserId) {
        return readString(request, 'id') ??
            readString(request, '_id') ??
            readString(request, 'requestId');
      }
    }
    return null;
  }

  void _showRelationshipError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showRelationshipInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sendFriendRequest() async {
    if (_isRelationshipActionInFlight) return;
    setState(() {
      _isRelationshipActionInFlight = true;
    });
    try {
      RelationshipSummary summary = await _apiService.sendFriendRequest(
        profileUserId,
      );
      if (summary.pendingRequestId == null) {
        try {
          final refreshed = await _apiService.getRelationshipSummary(
            profileUserId,
            forceRefresh: true,
          );
          if (refreshed.pendingRequestId != null) {
            summary = refreshed;
          }
        } catch (refreshError, stack) {
          debugPrint('ProfilePage: refresh after send failed: $refreshError');
          debugPrint('$stack');
        }
      }

      _applyRelationshipSummary(summary);

      switch (summary.status) {
        case RelationshipStatus.pendingOutgoing:
          _showRelationshipInfo('Friend request sent.');
          break;
        case RelationshipStatus.pendingIncoming:
          _showRelationshipInfo('Respond to the pending friend request.');
          break;
        default:
          break;
      }
    } catch (e) {
      _showRelationshipError('Failed to send friend request: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isRelationshipActionInFlight = false;
        });
      }
    }
  }

  Future<void> _cancelPendingRequest() async {
    final requestId = _pendingRequestId;
    if (requestId == null || _isRelationshipActionInFlight) return;
    final previousStatus = _relationshipStatus;
    final previousPendingId = _pendingRequestId;
    debugPrint(
      'ProfilePage: cancelling request $requestId while status=$previousStatus',
    );
    setState(() {
      _isRelationshipActionInFlight = true;
      _relationshipStatus = RelationshipStatus.none;
      _pendingRequestId = null;
    });
    try {
      final summary = previousStatus == RelationshipStatus.pendingIncoming
          ? await _apiService.declineFriendRequest(
              requestId,
              targetUserId: profileUserId,
            )
          : await _apiService.cancelFriendRequest(
              requestId,
              targetUserId: profileUserId,
            );
      debugPrint(
        'ProfilePage: cancel response status=${summary.status} pending=${summary.pendingRequestId}',
      );
      final clearedSummary = RelationshipSummary(
        status: RelationshipStatus.none,
        pendingRequestId: null,
        followerCount: summary.followerCount,
        followingCount: summary.followingCount,
        friendCount: summary.friendCount,
      );
      _applyRelationshipSummary(clearedSummary);
      if (previousStatus == RelationshipStatus.pendingIncoming) {
        _showRelationshipInfo('Friend request declined.');
      } else {
        _showRelationshipInfo('Friend request canceled.');
      }
    } catch (e) {
      setState(() {
        _relationshipStatus = previousStatus;
        _pendingRequestId = previousPendingId;
      });
      _showRelationshipError('Failed to cancel request: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isRelationshipActionInFlight = false;
        });
      }
    }
  }

  Future<void> _acceptPendingRequest() async {
    final requestId = _pendingRequestId;
    if (requestId == null || _isRelationshipActionInFlight) return;
    setState(() {
      _isRelationshipActionInFlight = true;
    });
    try {
      final summary = await _apiService.acceptFriendRequest(
        requestId,
        targetUserId: profileUserId,
      );
      _applyRelationshipSummary(summary);
      _showRelationshipInfo('Friend request accepted.');
    } catch (e) {
      _showRelationshipError('Failed to accept request: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isRelationshipActionInFlight = false;
        });
      }
    }
  }

  Future<void> _declinePendingRequest() async {
    final requestId = _pendingRequestId;
    if (requestId == null || _isRelationshipActionInFlight) return;
    setState(() {
      _isRelationshipActionInFlight = true;
    });
    try {
      final summary = await _apiService.declineFriendRequest(
        requestId,
        targetUserId: profileUserId,
      );
      _applyRelationshipSummary(summary);
      _showRelationshipInfo('Friend request declined.');
    } catch (e) {
      _showRelationshipError('Failed to decline request: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isRelationshipActionInFlight = false;
        });
      }
    }
  }

  Future<void> _unfriend() async {
    if (_isRelationshipActionInFlight) return;
    setState(() {
      _isRelationshipActionInFlight = true;
    });
    try {
      final summary = await _apiService.unfriend(profileUserId);
      _applyRelationshipSummary(summary);
    } catch (e) {
      _showRelationshipError('Failed to remove friend: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isRelationshipActionInFlight = false;
        });
      }
    }
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      final value = count / 1000000;
      return value >= 10 ? '${value.floor()}M' : '${value.toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      final value = count / 1000;
      return value >= 10 ? '${value.floor()}K' : '${value.toStringAsFixed(1)}K';
    }
    return count.toString();
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
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
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
    final mediaType = (post['mediaType'] as String?)?.toLowerCase().trim();
    final rawImagePath = post['imageUrl'] as String?;
    final thumbnailPath = post['thumbnailUrl'] as String?;
    final videoPath = post['videoUrl'] as String?;
    final imagePath = (rawImagePath != null && rawImagePath.isNotEmpty)
        ? rawImagePath
        : (thumbnailPath != null && thumbnailPath.isNotEmpty
              ? thumbnailPath
              : null);
    final caption = post['caption']?.toString() ?? '';
    final createdAt = post['createdAt'];
    final formattedInfo = formatTimestamp(createdAt);
    final postId = _extractPostId(post);
    final likeCount = _readLikeCount(post) ?? 0;
    final commentCount = _readCommentCount(post) ?? 0;
    final isLiked = _readIsLiked(post) ?? false;
    final postOwnerId = _resolvePostOwnerId(post);

    return GestureDetector(
      onTap: () {
        PostViewer.show(
          context: context,
          apiService: _apiService,
          mediaType: mediaType,
          relativeImagePath: imagePath,
          relativeVideoPath: videoPath,
          caption: caption,
          infoText: formattedInfo != null ? 'Posted $formattedInfo' : null,
          postId: postId,
          postOwnerId: postOwnerId,
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
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildPostMediaWidget(post),
              _buildPostTileOverlay(likeCount, commentCount),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPostMediaWidget(Map<String, dynamic> post) {
    final mediaType = (post['mediaType'] as String?)?.toLowerCase().trim();
    final videoPath = post['videoUrl'] as String?;
    final thumbnailPath = post['thumbnailUrl'] as String?;
    final imagePath = post['imageUrl'] as String?;

    if (mediaType == 'video' && videoPath != null && videoPath.isNotEmpty) {
      final resolvedThumbUrl = thumbnailPath != null && thumbnailPath.isNotEmpty
          ? _apiService.getFullImageUrl(thumbnailPath)
          : null;
      final videoUrl = _apiService.getFullImageUrl(videoPath);

      return Stack(
        fit: StackFit.expand,
        children: [
          if (resolvedThumbUrl != null)
            CachedNetworkImage(
              cacheManager: AppCacheManagers.imageCache,
              imageUrl: resolvedThumbUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: Colors.black12,
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (context, url, error) => _VideoThumbnailGenerator(
                videoUrl: videoUrl,
                fallback: _buildVideoFallback(),
              ),
            )
          else
            _VideoThumbnailGenerator(
              videoUrl: videoUrl,
              fallback: _buildVideoFallback(),
            ),
          // Gradient overlay for better icon visibility
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.3)],
              ),
            ),
          ),
          // Play icon overlay
          const Positioned(
            top: 8,
            right: 8,
            child: Icon(
              Icons.play_circle_filled,
              color: Colors.white,
              size: 32,
              shadows: [Shadow(blurRadius: 4, color: Colors.black45)],
            ),
          ),
          // Video duration indicator (optional - can be added if backend provides duration)
          const Positioned(
            bottom: 8,
            right: 8,
            child: Icon(
              Icons.videocam_rounded,
              color: Colors.white,
              size: 20,
              shadows: [Shadow(blurRadius: 4, color: Colors.black45)],
            ),
          ),
        ],
      );
    }

    final resolvedImageUrl = imagePath != null && imagePath.isNotEmpty
        ? _apiService.getFullImageUrl(imagePath)
        : null;

    if (resolvedImageUrl == null) {
      return Container(
        color: Colors.grey[200],
        child: const Icon(Icons.image, color: Colors.grey),
      );
    }

    return CachedNetworkImage(
      cacheManager: AppCacheManagers.imageCache,
      imageUrl: resolvedImageUrl,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: Colors.grey[200],
        alignment: Alignment.center,
        child: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: Colors.grey[200],
        child: const Icon(Icons.error_outline, color: Colors.grey),
      ),
    );
  }

  Widget _buildVideoFallback() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.purple.shade900,
            Colors.purple.shade700,
            Colors.pink.shade700,
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.video_library_rounded,
            color: Colors.white.withOpacity(0.9),
            size: 48,
          ),
          const SizedBox(height: 8),
          Text(
            'Video',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
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

  String? _resolvePostOwnerId(Map<String, dynamic> post) {
    final directCandidates = [
      post['userId'],
      post['ownerId'],
      post['authorId'],
      post['creatorId'],
    ];
    for (final candidate in directCandidates) {
      if (candidate is String && candidate.isNotEmpty) {
        return candidate;
      }
      if (candidate is int) {
        return candidate.toString();
      }
    }

    final author = post['author'];
    if (author is Map<String, dynamic>) {
      final authorId = author['id'] ?? author['uid'];
      if (authorId is String && authorId.isNotEmpty) {
        return authorId;
      }
      if (authorId is int) {
        return authorId.toString();
      }
    }

    final user = post['user'];
    if (user is Map<String, dynamic>) {
      final userId = user['id'] ?? user['uid'];
      if (userId is String && userId.isNotEmpty) {
        return userId;
      }
      if (userId is int) {
        return userId.toString();
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
                    ? CachedNetworkImage(
                        cacheManager: AppCacheManagers.imageCache,
                        imageUrl: _apiService.getFullImageUrl(
                          _remoteProfileImageUrl!,
                        ),
                        fit: BoxFit.contain,
                        placeholder: (context, url) => Container(
                          padding: const EdgeInsets.all(32),
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          padding: const EdgeInsets.all(32),
                          alignment: Alignment.center,
                          child: const Icon(Icons.error_outline, size: 48),
                        ),
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
        const SnackBar(
          content: Text('Profile picture removed'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
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
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to sign out')));
    }
  }

  Future<void> _startChat() async {
    if (currentUserId == null) return;

    final participants = [currentUserId, profileUserId]..sort();
    final chatId = participants.join('_');

    final chatDoc = FirebaseFirestore.instance.collection('chats').doc(chatId);
    bool chatExists = false;
    try {
      final snapshot = await chatDoc.get();
      chatExists = snapshot.exists;
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      debugPrint(
        'ProfilePage: chat lookup denied, treating as missing (chatId=$chatId)',
      );
    }

    if (!chatExists) {
      await chatDoc.set({
        'participants': participants,
        'lastMessage': 'Chat started',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unreadCount': 0,
      }, SetOptions(merge: true));
    } else {
      await chatDoc.set({
        'participants': participants,
      }, SetOptions(merge: true));
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

  void _navigateToFriendsList() {
    debugPrint('Navigating to friends list...');
    final userName =
        _userData?['userName'] as String? ??
        _userData?['displayName'] as String? ??
        'User';

    debugPrint('userName: $userName, profileUserId: $profileUserId');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            FriendsListPage(userId: profileUserId, userName: userName),
      ),
    );
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
            // Appearance / Theme
            ListTile(
              leading: const Icon(Icons.brightness_6_outlined),
              title: const Text('Appearance'),
              subtitle: Text(() {
                final m = ThemeController.instance.mode.value;
                return m == ThemeMode.system
                    ? 'Use system'
                    : (m == ThemeMode.light ? 'Light' : 'Dark');
              }()),
              onTap: () => _showAppearanceSheet(context),
            ),
            const Divider(height: 1),
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

  void _showAppearanceSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        final current = ThemeController.instance.mode.value;
        void select(ThemeMode m) {
          ThemeController.instance.setMode(m);
          Navigator.pop(sheetContext);
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  'Appearance',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              RadioListTile<ThemeMode>(
                title: const Text('Use system'),
                value: ThemeMode.system,
                groupValue: current,
                onChanged: (m) => select(ThemeMode.system),
              ),
              RadioListTile<ThemeMode>(
                title: const Text('Light'),
                value: ThemeMode.light,
                groupValue: current,
                onChanged: (m) => select(ThemeMode.light),
              ),
              RadioListTile<ThemeMode>(
                title: const Text('Dark'),
                value: ThemeMode.dark,
                groupValue: current,
                onChanged: (m) => select(ThemeMode.dark),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
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
                    child: _buildPostMediaWidget(post),
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
                child: _buildPostMediaWidget(post),
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

/// Widget that generates a video thumbnail from the first frame
class _VideoThumbnailGenerator extends StatefulWidget {
  final String videoUrl;
  final Widget fallback;

  const _VideoThumbnailGenerator({
    required this.videoUrl,
    required this.fallback,
  });

  @override
  State<_VideoThumbnailGenerator> createState() =>
      _VideoThumbnailGeneratorState();
}

class _VideoThumbnailGeneratorState extends State<_VideoThumbnailGenerator> {
  String? _thumbnailPath;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _generateThumbnail();
  }

  Future<void> _generateThumbnail() async {
    try {
      final thumbnail = await VideoThumbnail.thumbnailFile(
        video: widget.videoUrl,
        thumbnailPath: (await getTemporaryDirectory()).path,
        imageFormat: ImageFormat.PNG,
        maxWidth: 300,
        quality: 75,
      );

      if (mounted) {
        setState(() {
          _thumbnailPath = thumbnail;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error generating video thumbnail: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: Colors.black12,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_hasError || _thumbnailPath == null) {
      return widget.fallback;
    }

    return Image.file(
      File(_thumbnailPath!),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => widget.fallback,
    );
  }
}
