import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http_parser/http_parser.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal() {
    print('ApiService singleton instance created'); // Debug log
  }

  final String baseUrl = 'http://10.0.2.2:3000/api'; // For Android Emulator
  // Use 'http://localhost:3000/api' for iOS Simulator

  String get serverBaseUrl {
    // for base url
    final uri = Uri.parse(baseUrl);
    return '${uri.scheme}://${uri.host}:${uri.port}';
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

      // Validate image file type
      String ext = imageFile.path.toLowerCase().split('.').last;
      if (!['jpg', 'jpeg', 'png'].contains(ext)) {
        throw Exception('Only JPG and PNG images are allowed');
      }

      print('Creating post...'); // Debug log

      // Create post with metadata and image together
      // The backend gets the userId from the JWT token, not from the form fields.
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/posts'))
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

      print('Fetching posts...'); // Debug log
      final response = await http.get(
        Uri.parse('$baseUrl/posts'),
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

      print('Fetching posts for user: $userId'); // Debug log
      final response = await http.get(
        Uri.parse('$baseUrl/users/$userId/posts'),
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

      print('Fetching profile for user: $userId'); // Debug log
      final response = await http.get(
        Uri.parse('$baseUrl/users/$userId/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('Profile Response Status: ${response.statusCode}'); // Debug log
      print('Profile Response Body: ${response.body}'); // Debug log

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 404 &&
          userId == FirebaseAuth.instance.currentUser?.uid) {
        // If this is the current user's profile and it doesn't exist, create it
        print('Profile not found, creating new profile...'); // Debug log
        return await updateProfile(
          username:
              FirebaseAuth.instance.currentUser?.displayName ?? 'New User',
          bio: '',
        );
      } else {
        throw Exception('Failed to load profile: ${response.statusCode}');
      }
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

      print('Updating profile...'); // Debug log
      final response = await http.put(
        Uri.parse('$baseUrl/users/me'),
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
              Uri.parse('$baseUrl/users/$userId/profile-pic'),
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

      print('Deleting profile picture...');
      final response = await http.delete(
        Uri.parse('$baseUrl/users/$userId/profile-pic'),
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
      print('Deleting post: $postId');
      final response = await http.delete(
        Uri.parse('$baseUrl/posts/$postId'),
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
}
