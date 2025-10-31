import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'profile_page.dart';

class FriendsListPage extends StatefulWidget {
  final String userId;
  final String userName;

  const FriendsListPage({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<FriendsListPage> createState() => _FriendsListPageState();
}

class _FriendsListPageState extends State<FriendsListPage> {
  final _apiService = ApiService();
  List<Map<String, dynamic>>? _friends;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final friends = await _apiService.getFriends(widget.userId);

      if (!mounted) return;
      setState(() {
        _friends = friends;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading friends: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load friends\n${e.toString()}';
        _isLoading = false;
      });
    }
  }

  void _navigateToProfile(String userId, String userName) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ProfilePage(userId: userId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.userName}\'s Friends'),
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
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadFriends,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_friends == null || _friends!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No friends yet',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFriends,
      child: ListView.builder(
        itemCount: _friends!.length,
        itemBuilder: (context, index) {
          final friend = _friends![index];
          return _buildFriendItem(friend);
        },
      ),
    );
  }

  Widget _buildFriendItem(Map<String, dynamic> friend) {
    // Backend returns: { id, userId, username, profilePicUrl, since }
    final userId = friend['userId'] as String? ?? friend['id'] as String? ?? '';
    final userName =
        friend['username'] as String? ??
        friend['userName'] as String? ??
        'Unknown User';
    final displayName = friend['displayName'] as String? ?? userName;
    final profilePicUrl = friend['profilePicUrl'] as String?;
    final bio = friend['bio'] as String?;

    // Convert relative URL to full URL
    final fullProfilePicUrl = profilePicUrl != null && profilePicUrl.isNotEmpty
        ? _apiService.getFullImageUrl(profilePicUrl)
        : null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: SizedBox(
        width: 56,
        height: 56,
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: fullProfilePicUrl ?? '',
            fit: BoxFit.cover,
            placeholder: (context, url) => const CircularProgressIndicator(),
            errorWidget: (context, url, error) => CircleAvatar(
              radius: 28,
              backgroundColor: Colors.grey[300],
              child: Text(
                userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
      title: Text(
        displayName,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
      subtitle: bio != null && bio.isNotEmpty
          ? Text(
              bio,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            )
          : Text(
              '@$userName',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () => _navigateToProfile(userId, userName),
    );
  }
}
