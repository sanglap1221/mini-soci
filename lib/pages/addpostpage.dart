import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:pay_go/utils/image_crop_helper.dart';
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
        _videoController?.dispose();
        setState(() {
          _mediaFile = file;
          _mediaType = PostMediaType.image;
          _videoController = null;
        });
        break;
      case PostMediaType.video:
        final file = await ImageCropHelper.pickPostVideo(context);
        if (file == null) return;

        final controller = VideoPlayerController.file(file);
        await controller.initialize();

        _videoController?.dispose();
        setState(() {
          _mediaFile = file;
          _mediaType = PostMediaType.video;
          _videoController = controller
            ..setLooping(true)
            ..play();
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
