import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:pay_go/services/api_service.dart';
import 'package:pay_go/services/app_cache_managers.dart';
import 'profile_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _hasSearched = false;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _hasSearched = true;
    });

    try {
      final results = await _apiService.searchUsers(query);

      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      debugPrint('Search error: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isSearching = false;
        _searchResults = [];
      });
    }
  }

  void _navigateToProfile(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ProfilePage(userId: userId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Users'),
        elevation: isDark ? 0 : 1,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: 'Search by name or username...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white70 : Colors.grey[600],
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: isDark ? Colors.white70 : Colors.grey,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: isDark ? Colors.white70 : Colors.grey,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          _performSearch('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark ? const Color(0xFF1F2937) : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              onChanged: (value) {
                setState(() {}); // Update UI for clear button
                // Debounce search - only search after user stops typing
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (_searchController.text == value) {
                    _performSearch(value);
                  }
                });
              },
              onSubmitted: _performSearch,
            ),
          ),

          // Results area
          Expanded(child: _buildResultsArea()),
        ],
      ),
    );
  }

  Widget _buildResultsArea() {
    if (_isSearching) {
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
                'Search Error',
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
              ElevatedButton(
                onPressed: () => _performSearch(_searchController.text),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'Search for users',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter a name or username to find people',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No users found',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try searching with a different keyword',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        return _buildUserTile(user);
      },
    );
  }

  Widget _buildUserTile(Map<String, dynamic> user) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userId = user['id'] as String? ?? user['userId'] as String? ?? '';
    final username = user['username'] as String? ?? 'Unknown User';

    // Try to get displayName from multiple possible fields
    final displayName =
        user['displayName'] as String? ??
        user['name'] as String? ??
        user['fullName'] as String? ??
        username;

    final bio = user['bio'] as String?;
    final profilePicUrl =
        user['profilePicUrl'] as String? ??
        user['profilePicture'] as String? ??
        user['avatar'] as String?;

    final fullProfilePicUrl = profilePicUrl != null && profilePicUrl.isNotEmpty
        ? _apiService.getFullImageUrl(profilePicUrl)
        : null;

    // Debug print to see what data we're receiving
    debugPrint('Search result user: $user');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: Colors.grey[300],
        backgroundImage: fullProfilePicUrl != null
            ? CachedNetworkImageProvider(
                fullProfilePicUrl,
                cacheManager: AppCacheManagers.imageCache,
              )
            : null,
        child: fullProfilePicUrl == null
            ? Text(
                username.isNotEmpty ? username[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              )
            : null,
      ),
      title: Text(
        displayName,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '@$username',
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.grey[600],
              fontSize: 14,
            ),
          ),
          if (bio != null && bio.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              bio,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.grey[500],
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: isDark ? Colors.white70 : Colors.grey,
      ),
      onTap: () => _navigateToProfile(userId),
    );
  }
}
