import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';

class Addpostpage extends StatefulWidget {
  const Addpostpage({super.key});

  @override
  State<Addpostpage> createState() => _AddpostpageState();
}

class _AddpostpageState extends State<Addpostpage> {
  final _apiService = ApiService();
  File? _image;
  final _captionController = TextEditingController();
  bool _isLoading = false;

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _image = File(image.path);
      });
    }
  }

  Future<void> _createPost() async {
    if (_image == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Please select an image')));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Create post using API service
      await _apiService.createPost(_captionController.text.trim(), _image!);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Post created successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Create Post'),
        actions: [
          IconButton(
            icon: Icon(Icons.check),
            onPressed: _isLoading ? null : _createPost,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      height: 200,
                      width: double.infinity,
                      color: Colors.grey[300],
                      child: _image != null
                          ? Image.file(_image!, fit: BoxFit.cover)
                          : Icon(Icons.add_photo_alternate, size: 50),
                    ),
                  ),
                  SizedBox(height: 16),
                  TextField(
                    controller: _captionController,
                    decoration: InputDecoration(
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
