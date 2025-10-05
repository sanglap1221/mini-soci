import 'dart:io';
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class ImageCropHelper {
  const ImageCropHelper._();

  static Future<File?> pickAvatar(BuildContext context) =>
      pickAndCrop(context: context, isCircle: true, aspectRatio: 1.0);

  static Future<File?> pickPostImage(BuildContext context) => pickAndCrop(
    context: context,
    isCircle: false,
    aspectRatio: null, // Free aspect ratio
  );

  static Future<File?> pickAndCrop({
    required BuildContext context,
    required bool isCircle,
    double? aspectRatio,
  }) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Choose from Gallery'),
            onTap: () => Navigator.of(context).pop(ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Take a Photo'),
            onTap: () => Navigator.of(context).pop(ImageSource.camera),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );

    if (source == null) {
      return null;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );

    if (picked == null) return null;

    final imageBytes = await picked.readAsBytes();

    // ignore: use_build_context_synchronously
    if (!context.mounted) return null;

    final croppedData = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (context) => _CropScreen(
          imageBytes: imageBytes,
          isCircle: isCircle,
          aspectRatio: aspectRatio,
        ),
      ),
    );

    if (croppedData == null) return null;

    final tempDir = await getTemporaryDirectory();
    final fileExtension = isCircle ? 'png' : 'jpg';
    final file = await File(
      '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.$fileExtension',
    ).create();
    await file.writeAsBytes(croppedData);

    return file;
  }
}

class _CropScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final bool isCircle;
  final double? aspectRatio;

  const _CropScreen({
    required this.imageBytes,
    this.isCircle = false,
    this.aspectRatio,
  });

  @override
  State<_CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<_CropScreen> {
  final _cropController = CropController();
  bool _isLoading = false;
  bool _ignoreInitialScale = true;

  bool _handleWillUpdateScale(double nextScale) {
    if (_ignoreInitialScale) {
      _ignoreInitialScale = false;
      return false;
    }

    return true;
  }

  void _handleCropStatusChanged(CropStatus status) {
    if (status == CropStatus.loading) {
      _ignoreInitialScale = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crop Image'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Column(
        children: [
          Expanded(
            child: Crop(
              image: widget.imageBytes,
              controller: _cropController,
              interactive: true,
              initialRectBuilder: InitialRectBuilder.withSizeAndRatio(
                size: widget.isCircle ? 0.85 : 0.9,
                aspectRatio: widget.aspectRatio,
              ),
              onCropped: (cropResult) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() {
                    _isLoading = false;
                  });

                  if (cropResult is CropSuccess) {
                    Navigator.of(context).pop(cropResult.croppedImage);
                  } else if (cropResult is CropFailure) {
                    final messenger = ScaffoldMessenger.of(context);
                    messenger
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            'Failed to crop image. Please try again.',
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                  }
                });
              },
              aspectRatio: widget.aspectRatio,
              withCircleUi: widget.isCircle,
              baseColor: Colors.grey.shade900,
              maskColor: Colors.white.withAlpha(100),
              cornerDotBuilder: (size, edgeAlignment) =>
                  const DotControl(color: Colors.blue),
              willUpdateScale: _handleWillUpdateScale,
              onStatusChanged: _handleCropStatusChanged,
              scrollZoomSensitivity: 0.035,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Text(
              'Pinch with two fingers to zoom and drag the photo to focus on the exact spot you want to crop.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.black),
                  ),
                ),
                ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          setState(() {
                            _isLoading = true;
                          });
                          if (widget.isCircle) {
                            _cropController.cropCircle();
                          } else {
                            _cropController.crop();
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Confirm'),
                ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
