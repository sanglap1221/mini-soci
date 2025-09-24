import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

class Addpostpage extends StatefulWidget {
  const Addpostpage({super.key});

  @override
  State<Addpostpage> createState() => _AddpostpageState();
}

class _AddpostpageState extends State<Addpostpage> {
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
    if (_image == null) return;
    setState(() {
      _isLoading = true;
    });
    try {
      // Upload image to Firebase Storage
      final storageRef = FirebaseStorage.instance.ref().child(
        'posts/${DateTime.now().toString()}',
      );
      await storageRef.putFile(_image!);
      final imageUrl = await storageRef.getDownloadURL();

      // Save post data to Firestore
      await FirebaseFirestore.instance.collection('posts').add({
        'userId': FirebaseAuth.instance.currentUser?.uid,
        'imageUrl': imageUrl,
        'caption': _captionController.text,
        'timestamp': FieldValue.serverTimestamp(),
      });

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() {
        _isLoading = false;
      });
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
