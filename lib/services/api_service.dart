import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal() {
    print('ApiService singleton instance created'); // Debug log
  }

  static const String _dartDefineGlobalBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static const String _dartDefineDeviceBaseUrl = String.fromEnvironment(
    'API_DEVICE_BASE_URL',
    defaultValue: '',
  );

  static const String _dartDefineEmulatorBaseUrl = String.fromEnvironment(
    'API_EMULATOR_BASE_URL',
    defaultValue: '',
  );

  static const String _dartDefineWebBaseUrl = String.fromEnvironment(
    'API_WEB_BASE_URL',
    defaultValue: '',
  );

  // Defaults when no dart-define overrides are supplied.
  static const String _androidEmulatorDefault = 'http://10.0.2.2:3000/api';
  static const String _androidPhysicalDefault =
      'http://192.168.29.103:3000/api';
  static const String _iosSimulatorDefault = 'http://localhost:3000/api';
  static const String _desktopDefault = 'http://localhost:3000/api';

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  AndroidDeviceInfo? _cachedAndroidInfo;
  IosDeviceInfo? _cachedIosInfo;

  String? _baseUrl;
  Future<String>? _baseUrlFuture;

  Future<void> initialize({String? overrideBaseUrl}) async {
    if (overrideBaseUrl != null && overrideBaseUrl.isNotEmpty) {
      _baseUrl = _normalizeBaseUrl(overrideBaseUrl);
      _baseUrlFuture = Future.value(_baseUrl);
      return;
    }

    if (_baseUrl != null) {
      return;
    }

    _baseUrlFuture ??= _resolveBaseUrl();
    _baseUrl = await _baseUrlFuture!;
  }

  void overrideBaseUrl(String baseUrl) {
    _baseUrl = _normalizeBaseUrl(baseUrl);
    _baseUrlFuture = Future.value(_baseUrl);
  }

  Future<String> _prepareBaseUrl() async {
    if (_baseUrl != null) {
      return _baseUrl!;
    }

    await initialize();
    return _baseUrl!;
  }

  String get baseUrl {
    if (_baseUrl != null) {
      return _baseUrl!;
    }

    final fallback = _defaultBaseUrlSync;
    debugPrint(
      'ApiService: baseUrl accessed before initialization. Using fallback "$fallback". Call initialize() at app startup for accurate environment detection.',
    );
    return fallback;
  }

  String get serverBaseUrl {
    final uri = Uri.parse(_baseUrl ?? _defaultBaseUrlSync);
    final portSegment = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$portSegment';
  }

  Future<String> _resolveBaseUrl() async {
    if (_dartDefineGlobalBaseUrl.isNotEmpty) {
      return _normalizeBaseUrl(_dartDefineGlobalBaseUrl);
    }

    if (kIsWeb) {
      if (_dartDefineWebBaseUrl.isNotEmpty) {
        return _normalizeBaseUrl(_dartDefineWebBaseUrl);
      }
      return _normalizeBaseUrl(_desktopDefault);
    }

    if (Platform.isAndroid) {
      final androidInfo = await _safeAndroidInfo();
      final isPhysicalDevice = androidInfo?.isPhysicalDevice ?? false;

      if (isPhysicalDevice) {
        if (_dartDefineDeviceBaseUrl.isNotEmpty) {
          return _normalizeBaseUrl(_dartDefineDeviceBaseUrl);
        }
        debugPrint(
          'ApiService: Running on a physical Android device without an API_DEVICE_BASE_URL override. '
          'Defaulting to $_androidPhysicalDefault.',
        );
        return _normalizeBaseUrl(_androidPhysicalDefault);
      } else if (_dartDefineEmulatorBaseUrl.isNotEmpty) {
        return _normalizeBaseUrl(_dartDefineEmulatorBaseUrl);
      }

      return _normalizeBaseUrl(_androidEmulatorDefault);
    }

    if (Platform.isIOS) {
      final iosInfo = await _safeIosInfo();
      final isPhysicalDevice = iosInfo?.isPhysicalDevice ?? false;

      if (isPhysicalDevice) {
        if (_dartDefineDeviceBaseUrl.isNotEmpty) {
          return _normalizeBaseUrl(_dartDefineDeviceBaseUrl);
        }
        debugPrint(
          'ApiService: Running on a physical iOS device but no API_DEVICE_BASE_URL was provided. '
          'Defaulting to simulator host $_iosSimulatorDefault which will only work when the server is publicly reachable.',
        );
      }

      return _normalizeBaseUrl(_iosSimulatorDefault);
    }

    return _normalizeBaseUrl(_desktopDefault);
  }

  Future<AndroidDeviceInfo?> _safeAndroidInfo() async {
    try {
      return _cachedAndroidInfo ??= await _deviceInfo.androidInfo;
    } catch (e) {
      debugPrint('ApiService: Failed to read Android device info: $e');
      return null;
    }
  }

  Future<IosDeviceInfo?> _safeIosInfo() async {
    try {
      return _cachedIosInfo ??= await _deviceInfo.iosInfo;
    } catch (e) {
      debugPrint('ApiService: Failed to read iOS device info: $e');
      return null;
    }
  }

  String get _defaultBaseUrlSync {
    if (_dartDefineGlobalBaseUrl.isNotEmpty) {
      return _normalizeBaseUrl(_dartDefineGlobalBaseUrl);
    }

    if (kIsWeb) {
      if (_dartDefineWebBaseUrl.isNotEmpty) {
        return _normalizeBaseUrl(_dartDefineWebBaseUrl);
      }
      return _normalizeBaseUrl(_desktopDefault);
    }

    if (Platform.isAndroid) {
      if (_dartDefineDeviceBaseUrl.isNotEmpty) {
        return _normalizeBaseUrl(_dartDefineDeviceBaseUrl);
      }
      if (_dartDefineEmulatorBaseUrl.isNotEmpty) {
        return _normalizeBaseUrl(_dartDefineEmulatorBaseUrl);
      }
      final androidInfo = _cachedAndroidInfo;
      if (androidInfo != null) {
        if (androidInfo.isPhysicalDevice) {
          return _normalizeBaseUrl(_androidPhysicalDefault);
        }
      }
      return _normalizeBaseUrl(_androidEmulatorDefault);
    }

    if (Platform.isIOS) {
      return _normalizeBaseUrl(_iosSimulatorDefault);
    }

    return _normalizeBaseUrl(_desktopDefault);
  }

  String _normalizeBaseUrl(String value) {
    var trimmed = value.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }

    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'http://$trimmed';
    }

    final uri = Uri.parse(trimmed);
    final normalizedPath = uri.path.isEmpty
        ? ''
        : uri.path.replaceAll(RegExp(r'/+$'), '');

    var sanitized = uri.replace(path: normalizedPath).toString();
    if (sanitized.endsWith('/')) {
      sanitized = sanitized.substring(0, sanitized.length - 1);
    }
    return sanitized;
  }

  // for convert relative urls

  String getFullImageUrl(String relativePath) {
    print('getFullImageUrl called with: $relativePath'); // Debug log
    if (relativePath.startsWith('http')) {
      print('URL is already absolute: $relativePath'); // Debug log
      return relativePath;
    }
    final cleanPath = relativePath.startsWith('/')
        ? relativePath.substring(1)
        : relativePath;
    final fullUrl = '$serverBaseUrl/$cleanPath';
    print('Converted to full URL: $fullUrl'); // Debug log
    return fullUrl;
  }

  DateTime _parsePostDate(dynamic post) {
    if (post is Map<String, dynamic>) {
      final createdAt = post['createdAt'];
      if (createdAt is String) {
        return DateTime.tryParse(createdAt)?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      }
      if (createdAt is int) {
        return DateTime.fromMillisecondsSinceEpoch(createdAt, isUtc: true);
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  List<dynamic> sortPostsByNewest(List<dynamic> posts) {
    final sortedPosts = List<dynamic>.from(posts);
    sortedPosts.sort((a, b) => _parsePostDate(b).compareTo(_parsePostDate(a)));
    return sortedPosts;
  }

  // Get Firebase ID token
  Future<String?> getFirebaseToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      return await user.getIdToken();
    }
    return null;
  }

  // Create a new post with image
  Future<Map<String, dynamic>> createPost(
    String caption,
    File imageFile,
  ) async {
    try {
      final token = await getFirebaseToken();
      if (token == null) throw Exception('Not authenticated');
      final resolvedBaseUrl = await _prepareBaseUrl();

      // Validate image file type
      String ext = imageFile.path.toLowerCase().split('.').last;
      if (!['jpg', 'jpeg', 'png'].contains(ext)) {
        throw Exception('Only JPG and PNG images are allowed');
      }

      print('Creating post...'); // Debug log

      // Create post with metadata and image together
      // The backend gets the userId from the JWT token, not from the form fields.
      var request =
          http.MultipartRequest('POST', Uri.parse('$resolvedBaseUrl/posts'))
            ..headers['Authorization'] = 'Bearer $token'
            ..headers['Accept'] = 'application/json'
            ..fields['caption'] = caption.trim().isEmpty ? ' ' : caption.trim()
            ..files.add(
              await http.MultipartFile.fromPath(
                'image', // Backend expects field name 'image' for req.file
                imageFile.path,
                contentType: MediaType('image', ext == 'png' ? 'png' : 'jpeg'),
              ),
            );

      print('Sending multipart request with image file'); // Debug log

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      print('Create Post Response Status: ${response.statusCode}'); // Debug log
      print('Create Post Response Body: ${response.body}'); // Debug log

      if (response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to create post: ${response.statusCode}');
      }
    } catch (e) {
      print('Error creating post: $e'); // Debug log
      rethrow;
    }
  }

  // Get all posts for the main feed
  Future<List<dynamic>> getPosts() async {
    try {
      final token = await getFirebaseToken();
      if (token == null) throw Exception('Not authenticated');
      final resolvedBaseUrl = await _prepareBaseUrl();

      print('Fetching posts...'); // Debug log
      final response = await http.get(
        Uri.parse('$resolvedBaseUrl/posts'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('Posts Response Status: ${response.statusCode}'); // Debug log
      print('Posts Response Body: ${response.body}'); // Debug log

      if (response.statusCode == 200) {
        return sortPostsByNewest(json.decode(response.body));
      } else {
        throw Exception('Failed to load posts: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching posts: $e'); // Debug log
      rethrow;
    }
  }

  // Get posts for a specific user
  Future<List<dynamic>> getUserPosts(String userId) async {
    try {
      final token = await getFirebaseToken();
      if (token == null) throw Exception('Not authenticated');
      final resolvedBaseUrl = await _prepareBaseUrl();

      print('Fetching posts for user: $userId'); // Debug log
      final response = await http.get(
        Uri.parse('$resolvedBaseUrl/users/$userId/posts'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('User Posts Response Status: ${response.statusCode}'); // Debug log
      print('User Posts Response Body: ${response.body}'); // Debug log

      if (response.statusCode == 200) {
        return sortPostsByNewest(json.decode(response.body));
      } else {
        throw Exception('Failed to load user posts: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching user posts: $e'); // Debug log
      rethrow;
    }
  }

  // Get user profile
  Future<Map<String, dynamic>> getProfile(String userId) async {
    try {
      final token = await getFirebaseToken();
      if (token == null) throw Exception('Not authenticated');
      final resolvedBaseUrl = await _prepareBaseUrl();

      print('Fetching profile for user: $userId'); // Debug log
      final response = await http.get(
        Uri.parse('$resolvedBaseUrl/users/$userId/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('Profile Response Status: ${response.statusCode}'); // Debug log
      print('Profile Response Body: ${response.body}'); // Debug log

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }

      final currentUserId = FirebaseAuth.instance.currentUser?.uid;

      if (response.statusCode == 404) {
        if (userId == currentUserId) {
          // If this is the current user's profile and it doesn't exist, create it
          print('Profile not found, creating new profile...'); // Debug log
          return await updateProfile(
            username:
                FirebaseAuth.instance.currentUser?.displayName ?? 'New User',
            bio: '',
          );
        }

        // For other users, allow the caller to handle missing profile gracefully
        print(
          'Profile not found for user $userId, returning empty profile map',
        );
        return <String, dynamic>{};
      }

      throw Exception('Failed to load profile: ${response.statusCode}');
    } catch (e) {
      print('Error fetching profile: $e'); // Debug log
      rethrow;
    }
  }

  // Update profile information
  Future<Map<String, dynamic>> updateProfile({
    required String username,
    String? bio,
  }) async {
    try {
      final token = await getFirebaseToken();
      if (token == null) throw Exception('Not authenticated');
      final resolvedBaseUrl = await _prepareBaseUrl();

      print('Updating profile...'); // Debug log
      final response = await http.put(
        Uri.parse('$resolvedBaseUrl/users/me'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'username': username, 'bio': bio}),
      );

      print(
        'Update Profile Response Status: ${response.statusCode}',
      ); // Debug log
      print('Update Profile Response Body: ${response.body}'); // Debug log

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to update profile: ${response.statusCode}');
      }
    } catch (e) {
      print('Error updating profile: $e'); // Debug log
      rethrow;
    }
  }

  // Upload or change profile picture
  Future<Map<String, dynamic>> updateProfilePicture(File imageFile) async {
    try {
      final token = await getFirebaseToken();
      if (token == null) throw Exception('Not authenticated');

      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) throw Exception('Not authenticated');
      final resolvedBaseUrl = await _prepareBaseUrl();

      print('Uploading profile picture...'); // Debug log

      // Validate image file type
      String ext = imageFile.path.toLowerCase().split('.').last;
      if (!['jpg', 'jpeg', 'png'].contains(ext)) {
        throw Exception('Only JPG and PNG images are allowed');
      }

      // Create multipart request
      var request =
          http.MultipartRequest(
              'POST',
              Uri.parse('$resolvedBaseUrl/users/$userId/profile-pic'),
            )
            ..headers['Authorization'] = 'Bearer $token'
            ..headers['Accept'] = 'application/json'
            ..files.add(
              await http.MultipartFile.fromPath(
                'profilePic',
                imageFile.path,
                contentType: ext == 'png'
                    ? MediaType('image', 'png')
                    : MediaType('image', 'jpeg'),
              ),
            );

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      print(
        'Upload Profile Picture Response Status: ${response.statusCode}',
      ); // Debug log
      print(
        'Upload Profile Picture Response Body: ${response.body}',
      ); // Debug log

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception(
          'Failed to upload profile picture: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('Error uploading profile picture: $e');
      rethrow;
    }
  }

  Future<void> deleteProfilePicture() async {
    try {
      final token = await getFirebaseToken();
      if (token == null) throw Exception('Not authenticated');

      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) throw Exception('Not authenticated');
      final resolvedBaseUrl = await _prepareBaseUrl();

      print('Deleting profile picture...');
      final response = await http.delete(
        Uri.parse('$resolvedBaseUrl/users/$userId/profile-pic'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('Delete Profile Picture Response Status: ${response.statusCode}');
      print('Delete Profile Picture Response Body: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to delete profile picture: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('Error deleting profile picture: $e');
      rethrow;
    }
  }

  Future<void> deletePost(String postId) async {
    try {
      final token = await getFirebaseToken();
      if (token == null) throw Exception('Not authenticated');
      final resolvedBaseUrl = await _prepareBaseUrl();
      print('Deleting post: $postId');
      final response = await http.delete(
        Uri.parse('$resolvedBaseUrl/posts/$postId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      print('Delete Post Response Status: ${response.statusCode}');
      print('Delete Post Response Body: ${response.body}');

      if (response.statusCode == 200) {
        print('The post is deleted ');
      } else {
        throw Exception('Fails to delete${response.body}');
      }
    } catch (e) {
      print('Error deleting post: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> likePost(String postId) async {
    try {
      final token = await getFirebaseToken();
      if (token == null) throw Exception('Not authenticated');
      final resolvedBaseUrl = await _prepareBaseUrl();
      print('Liking post: $postId');
      final response = await http.post(
        Uri.parse('$resolvedBaseUrl/posts/$postId/like'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      print('Like Post Response Status: ${response.statusCode}');
      print('Like Post Response Body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = response.body.isNotEmpty
            ? json.decode(response.body) as Object
            : <String, dynamic>{};
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        return <String, dynamic>{'raw': decoded};
      }

      throw Exception('Failed to like post: ${response.statusCode}');
    } catch (e) {
      print('Error liking post: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> unlikePost(String postId) async {
    try {
      final token = await getFirebaseToken();
      if (token == null) throw Exception('Not authenticated');
      final resolvedBaseUrl = await _prepareBaseUrl();
      print('Unliking post: $postId');
      final response = await http.delete(
        Uri.parse('$resolvedBaseUrl/posts/$postId/like'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      print('Unlike Post Response Status: ${response.statusCode}');
      print('Unlike Post Response Body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 204) {
        if (response.body.isEmpty) {
          return <String, dynamic>{};
        }
        final decoded = json.decode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        return <String, dynamic>{'raw': decoded};
      }

      throw Exception('Failed to unlike post: ${response.statusCode}');
    } catch (e) {
      print('Error unliking post: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getComments(
    String postId, {
    int? limit,
    String? cursor,
  }) async {
    try {
      final token = await getFirebaseToken();
      if (token == null) throw Exception('Not authenticated');
      final resolvedBaseUrl = await _prepareBaseUrl();

      final queryParams = <String, String>{};
      if (limit != null) queryParams['limit'] = '$limit';
      if (cursor != null && cursor.isNotEmpty) queryParams['cursor'] = cursor;

      final uri = Uri.parse(
        '$resolvedBaseUrl/posts/$postId/comments',
      ).replace(queryParameters: queryParams.isEmpty ? null : queryParams);

      print('Fetching comments for post: $postId');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      print('Get Comments Response Status: ${response.statusCode}');
      print('Get Comments Response Body: ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          return <String, dynamic>{'items': <dynamic>[]};
        }

        final decoded = json.decode(response.body);
        if (decoded is List) {
          return <String, dynamic>{
            'items': decoded,
            'total': decoded.length,
            'cursor': null,
          };
        }
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        return <String, dynamic>{'items': <dynamic>[], 'raw': decoded};
      }

      throw Exception('Failed to load comments: ${response.statusCode}');
    } catch (e) {
      print('Error fetching comments: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> addComment(String postId, String text) async {
    try {
      final token = await getFirebaseToken();
      if (token == null) throw Exception('Not authenticated');
      final resolvedBaseUrl = await _prepareBaseUrl();

      final payload = json.encode({'text': text});
      print('Adding comment to post: $postId');
      final response = await http.post(
        Uri.parse('$resolvedBaseUrl/posts/$postId/comments'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: payload,
      );
      print('Add Comment Response Status: ${response.statusCode}');
      print('Add Comment Response Body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (response.body.isEmpty) {
          return <String, dynamic>{};
        }
        final decoded = json.decode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        return <String, dynamic>{'raw': decoded};
      }

      throw Exception('Failed to add comment: ${response.statusCode}');
    } catch (e) {
      print('Error adding comment: $e');
      rethrow;
    }
  }

  Future<void> deleteComment(String commentId) async {
    try {
      final token = await getFirebaseToken();
      if (token == null) throw Exception('Not authenticated');
      final resolvedBaseUrl = await _prepareBaseUrl();

      print('Deleting comment: $commentId');
      final response = await http.delete(
        Uri.parse('$resolvedBaseUrl/comments/$commentId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      print('Delete Comment Response Status: ${response.statusCode}');
      print('Delete Comment Response Body: ${response.body}');

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Failed to delete comment: ${response.statusCode}');
      }
    } catch (e) {
      print('Error deleting comment: $e');
      rethrow;
    }
  }
}
