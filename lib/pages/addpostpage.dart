import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';
import 'package:pay_go/utils/image_crop_helper.dart';
import 'package:pay_go/utils/image_compress_helper.dart';
import 'package:pay_go/utils/file_utils.dart';
import 'package:pay_go/utils/video_compress_helper.dart';

import '../services/api_service.dart';

class Addpostpage extends StatefulWidget {
  const Addpostpage({super.key});

  @override
  State<Addpostpage> createState() => _AddpostpageState();
}

class _AddpostpageState extends State<Addpostpage> {
  final _apiService = ApiService();
  final _captionController = TextEditingController();

  File? _mediaFile;
  PostMediaType? _mediaType;
  VideoPlayerController? _videoController;

  bool _isLoading = false;

  @override
  void dispose() {
    _captionController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    final choice = await showModalBottomSheet<PostMediaType>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Photo'),
              onTap: () => Navigator.pop(context, PostMediaType.image),
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Video'),
              onTap: () => Navigator.pop(context, PostMediaType.video),
            ),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return;

    switch (choice) {
      case PostMediaType.image:
        final file = await ImageCropHelper.pickPostImage(context);
        if (file == null) return;
        // Compute original diagnostics and then compress image before upload.
        _videoController?.dispose();
        final originalDiag = await FileUtils.diagnostics(file);
        final compressed = await ImageCompressHelper.compressImageFile(
          file,
          quality: 85,
          maxWidth: 1080,
          maxHeight: 1080,
        );
        final compressedDiag = await FileUtils.diagnostics(compressed);
        // Save compressed file and store diagnostics as metadata on the media file
        // We'll pass diagnostics to ApiService.createPost when uploading.
        setState(() {
          _mediaFile = compressed;
          _mediaType = PostMediaType.image;
          _videoController = null;
        });
        // Store diagnostics temporarily on the ApiService instance for the upload
        _apiService.setLatestClientDiagnostics(<String, String>{
          'originalLength': originalDiag['length'].toString(),
          'originalMd5': originalDiag['md5'] as String,
          'compressedLength': compressedDiag['length'].toString(),
          'compressedMd5': compressedDiag['md5'] as String,
          'wasCompressed': (originalDiag['md5'] != compressedDiag['md5'])
              .toString(),
        });
        break;
      case PostMediaType.video:
        final file = await ImageCropHelper.pickPostVideo(context);
        if (file == null) return;
        // Compute diagnostics, compress video (non-blocking native), compute compressed diagnostics
        setState(() => _isLoading = true);
        final originalDiag = await FileUtils.diagnostics(file);
        final compressedFile = await VideoCompressHelper.compressVideoFile(
          file,
          quality: VideoQuality.MediumQuality,
        );
        File finalFile;
        Map<String, dynamic> compressedDiag;
        if (compressedFile == null) {
          // compression failed or not available; fall back to original
          finalFile = file;
          compressedDiag = await FileUtils.diagnostics(file);
        } else {
          finalFile = compressedFile;
          compressedDiag = await FileUtils.diagnostics(compressedFile);
        }

        final controller = VideoPlayerController.file(finalFile);
        await controller.initialize();

        _videoController?.dispose();
        setState(() {
          _mediaFile = finalFile;
          _mediaType = PostMediaType.video;
          _videoController = controller
            ..setLooping(true)
            ..play();
          _isLoading = false;
        });

        _apiService.setLatestClientDiagnostics(<String, String>{
          'originalLength': originalDiag['length'].toString(),
          'originalMd5': originalDiag['md5'] as String,
          'compressedLength': compressedDiag['length'].toString(),
          'compressedMd5': compressedDiag['md5'] as String,
          'wasCompressed': (originalDiag['md5'] != compressedDiag['md5'])
              .toString(),
        });
        break;
    }
  }

  Future<void> _createPost() async {
    if (_mediaFile == null || _mediaType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a photo or video')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _apiService.createPost(
        _captionController.text.trim(),
        _mediaFile!,
        mediaType: _mediaType!,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Post created successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaPreview = () {
      if (_mediaFile == null || _mediaType == null) {
        return const Icon(Icons.add_to_photos, size: 50);
      }
      if (_mediaType == PostMediaType.image) {
        return Image.file(_mediaFile!, fit: BoxFit.cover);
      }
      if (_videoController == null || !_videoController!.value.isInitialized) {
        return const Center(child: CircularProgressIndicator());
      }
      return AspectRatio(
        aspectRatio: _videoController!.value.aspectRatio,
        child: VideoPlayer(_videoController!),
      );
    }();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Post'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _isLoading ? null : _createPost,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickMedia,
                    child: Container(
                      height: 220,
                      width: double.infinity,
                      color: Colors.grey[300],
                      alignment: Alignment.center,
                      child: mediaPreview,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _captionController,
                    decoration: const InputDecoration(
                      hintText: 'Write a caption...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
    );
  }
}
