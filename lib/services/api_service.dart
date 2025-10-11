import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'auth_token_provider.dart';
import 'base_url_resolver.dart';

class ApiService {
  ApiService._internal()
    : _baseUrlResolver = BaseUrlResolver(),
      _authTokenProvider = AuthTokenProvider() {
    _log('ApiService singleton instance created');
  }

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  final BaseUrlResolver _baseUrlResolver;
  final AuthTokenProvider _authTokenProvider;

  Future<void> initialize({String? overrideBaseUrl}) async {
    await _baseUrlResolver.initialize(overrideBaseUrl: overrideBaseUrl);
  }

  void overrideBaseUrl(String baseUrl) =>
      _baseUrlResolver.overrideBaseUrl(baseUrl);

  String get baseUrl => _baseUrlResolver.baseUrl;
  String get serverBaseUrl => _baseUrlResolver.serverBaseUrl;

  String getFullImageUrl(String relativePath) =>
      _baseUrlResolver.getFullImageUrl(relativePath);

  Future<String?> getFirebaseToken({bool forceRefresh = false}) =>
      _authTokenProvider.getToken(forceRefresh: forceRefresh);

  Future<String> _prepareBaseUrl() => _baseUrlResolver.prepareBaseUrl();

  Future<Map<String, dynamic>> createPost(
    String caption,
    File imageFile,
  ) async {
    final token = await getFirebaseToken();
    if (token == null) throw Exception('Not authenticated');
    final resolvedBaseUrl = await _prepareBaseUrl();

    final ext = imageFile.path.toLowerCase().split('.').last;
    if (!['jpg', 'jpeg', 'png'].contains(ext)) {
      throw Exception('Only JPG and PNG images are allowed');
    }

    _log('Creating post...');

    final request =
        http.MultipartRequest('POST', Uri.parse('$resolvedBaseUrl/posts'))
          ..headers['Authorization'] = 'Bearer $token'
          ..headers['Accept'] = 'application/json'
          ..fields['caption'] = caption.trim().isEmpty ? ' ' : caption.trim()
          ..files.add(
            await http.MultipartFile.fromPath(
              'image',
              imageFile.path,
              contentType: MediaType('image', ext == 'png' ? 'png' : 'jpeg'),
            ),
          );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    _log('Create Post Response Status: ${response.statusCode}');
    _log('Create Post Response Body: ${response.body}');

    if (response.statusCode == 201) {
      return json.decode(response.body) as Map<String, dynamic>;
    }

    throw Exception(
      'Failed to create post: ${response.statusCode} ${response.body}',
    );
  }

  Future<List<dynamic>> getPosts() async {
    final result = await _authorizedRequest(_HttpMethod.get, '/posts');
    final data = result.json;
    if (data is List<dynamic>) {
      return sortPostsByNewest(data);
    }
    throw Exception('Unexpected response format for posts');
  }

  Future<List<dynamic>> getUserPosts(String userId) async {
    final result = await _authorizedRequest(
      _HttpMethod.get,
      '/users/$userId/posts',
    );
    final data = result.json;
    if (data is List<dynamic>) {
      return sortPostsByNewest(data);
    }
    throw Exception('Unexpected response format for user posts');
  }

  Future<Map<String, dynamic>> getProfile(String userId) async {
    final result = await _authorizedRequest(
      _HttpMethod.get,
      '/users/$userId/profile',
      acceptedStatus: const [200, 404],
    );

    if (result.statusCode == 200) {
      final data = result.json;
      if (data is Map<String, dynamic>) {
        return data;
      }
      throw Exception('Unexpected profile response format');
    }

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (result.statusCode == 404) {
      if (userId == currentUserId) {
        _log('Profile not found, creating new profile...');
        return updateProfile(
          username:
              FirebaseAuth.instance.currentUser?.displayName ?? 'New User',
          bio: '',
        );
      }
      return <String, dynamic>{};
    }

    throw Exception(
      'Failed to load profile: ${result.statusCode} ${result.body}',
    );
  }

  Future<Map<String, dynamic>> updateProfile({
    required String username,
    String? bio,
  }) async {
    final result = await _authorizedRequest(
      _HttpMethod.put,
      '/users/me',
      jsonBody: {'username': username, 'bio': bio},
    );

    final data = result.json;
    if (data is Map<String, dynamic>) {
      return data;
    }
    throw Exception(
      'Failed to update profile: ${result.statusCode} ${result.body}',
    );
  }

  Future<Map<String, dynamic>> updateProfilePicture(File imageFile) async {
    final token = await getFirebaseToken();
    if (token == null) throw Exception('Not authenticated');

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) throw Exception('Not authenticated');
    final resolvedBaseUrl = await _prepareBaseUrl();

    final ext = imageFile.path.toLowerCase().split('.').last;
    if (!['jpg', 'jpeg', 'png'].contains(ext)) {
      throw Exception('Only JPG and PNG images are allowed');
    }

    _log('Uploading profile picture...');

    final request =
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

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    _log('Upload Profile Picture Response Status: ${response.statusCode}');
    _log('Upload Profile Picture Response Body: ${response.body}');

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }

    throw Exception(
      'Failed to upload profile picture: ${response.statusCode} ${response.body}',
    );
  }

  Future<void> deleteProfilePicture() async {
    await _authorizedRequest(
      _HttpMethod.delete,
      '/users/${FirebaseAuth.instance.currentUser?.uid}/profile-pic',
      acceptedStatus: const [200, 204],
      parseJson: false,
    );
  }

  Future<void> deletePost(String postId) async {
    final result = await _authorizedRequest(
      _HttpMethod.delete,
      '/posts/$postId',
      acceptedStatus: const [200],
      parseJson: false,
    );
    _log('The post is deleted (${result.statusCode})');
  }

  Future<Map<String, dynamic>> likePost(String postId) async {
    final result = await _authorizedRequest(
      _HttpMethod.post,
      '/posts/$postId/like',
      acceptedStatus: const [200, 201],
    );

    final data = result.json;
    if (data is Map<String, dynamic>) {
      return data;
    }

    if (data == null) {
      return <String, dynamic>{};
    }

    return <String, dynamic>{'raw': data};
  }

  Future<Map<String, dynamic>> unlikePost(String postId) async {
    final result = await _authorizedRequest(
      _HttpMethod.delete,
      '/posts/$postId/like',
      acceptedStatus: const [200, 204],
    );

    final data = result.json;
    if (data == null) {
      return <String, dynamic>{};
    }

    if (data is Map<String, dynamic>) {
      return data;
    }

    return <String, dynamic>{'raw': data};
  }

  Future<Map<String, dynamic>> getComments(
    String postId, {
    int? limit,
    String? cursor,
  }) async {
    final queryParams = <String, String>{};
    if (limit != null) queryParams['limit'] = '$limit';
    if (cursor != null && cursor.isNotEmpty) queryParams['cursor'] = cursor;

    final result = await _authorizedRequest(
      _HttpMethod.get,
      '/posts/$postId/comments',
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );

    final data = result.json;
    if (data == null) {
      return <String, dynamic>{'items': <dynamic>[]};
    }

    if (data is List) {
      final items = List<dynamic>.from(data);
      return <String, dynamic>{
        'items': items,
        'total': items.length,
        'cursor': null,
      };
    }

    if (data is Map<String, dynamic>) {
      return data;
    }

    return <String, dynamic>{'items': <dynamic>[], 'raw': data};
  }

  Future<Map<String, dynamic>> addComment(String postId, String text) async {
    final result = await _authorizedRequest(
      _HttpMethod.post,
      '/posts/$postId/comments',
      jsonBody: {'text': text},
      acceptedStatus: const [200, 201],
    );

    final data = result.json;
    if (data is Map<String, dynamic>) {
      return data;
    }

    if (data == null) {
      return <String, dynamic>{};
    }

    return <String, dynamic>{'raw': data};
  }

  Future<void> deleteComment(String commentId) async {
    await _authorizedRequest(
      _HttpMethod.delete,
      '/comments/$commentId',
      acceptedStatus: const [200, 204],
      parseJson: false,
    );
  }

  List<dynamic> sortPostsByNewest(List<dynamic> posts) {
    final sortedPosts = List<dynamic>.from(posts);
    sortedPosts.sort((a, b) => _parsePostDate(b).compareTo(_parsePostDate(a)));
    return sortedPosts;
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

  static Future<_ApiResponse> _authorizedRequest(
    _HttpMethod method,
    String path, {
    Map<String, String>? queryParameters,
    Map<String, dynamic>? jsonBody,
    List<int> acceptedStatus = const [200],
    bool parseJson = true,
  }) async {
    final instance = ApiService();
    final token = await instance.getFirebaseToken();
    if (token == null) throw Exception('Not authenticated');
    final base = await instance._prepareBaseUrl();

    final uri = Uri.parse('$base$path').replace(
      queryParameters: queryParameters == null || queryParameters.isEmpty
          ? null
          : queryParameters,
    );

    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      if (jsonBody != null) 'Content-Type': 'application/json',
    };

    http.Response response;
    switch (method) {
      case _HttpMethod.get:
        response = await http.get(uri, headers: headers);
        break;
      case _HttpMethod.post:
        response = await http.post(
          uri,
          headers: headers,
          body: jsonBody == null ? null : json.encode(jsonBody),
        );
        break;
      case _HttpMethod.put:
        response = await http.put(
          uri,
          headers: headers,
          body: jsonBody == null ? null : json.encode(jsonBody),
        );
        break;
      case _HttpMethod.delete:
        response = await http.delete(
          uri,
          headers: headers,
          body: jsonBody == null ? null : json.encode(jsonBody),
        );
        break;
    }

    _log('${method.name.toUpperCase()} $uri => ${response.statusCode}');
    if (response.body.isNotEmpty) {
      _log('Response Body: ${response.body}');
    }

    if (!acceptedStatus.contains(response.statusCode)) {
      throw Exception(
        'Request to $path failed: ${response.statusCode} ${response.body}',
      );
    }

    dynamic decoded;
    if (parseJson && response.body.isNotEmpty) {
      try {
        decoded = json.decode(response.body);
      } catch (e) {
        _log('Failed to decode JSON for $path: $e');
      }
    }

    return _ApiResponse(
      statusCode: response.statusCode,
      body: response.body,
      json: decoded,
    );
  }

  static void _log(String message) {
    if (kDebugMode) {
      debugPrint('ApiService: $message');
    }
  }
}

enum _HttpMethod { get, post, put, delete }

class _ApiResponse {
  const _ApiResponse({required this.statusCode, required this.body, this.json});

  final int statusCode;
  final String body;
  final dynamic json;
}
