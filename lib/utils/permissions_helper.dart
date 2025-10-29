import 'package:permission_handler/permission_handler.dart';

class PermissionsHelper {
  /// Request camera and microphone permissions for WebRTC calls
  /// Returns true if both permissions are granted, false otherwise
  static Future<bool> requestCallPermissions() async {
    // Request both camera and microphone permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    // Check if both permissions are granted
    bool cameraGranted = statuses[Permission.camera]?.isGranted ?? false;
    bool micGranted = statuses[Permission.microphone]?.isGranted ?? false;

    return cameraGranted && micGranted;
  }

  /// Check if camera and microphone permissions are already granted
  static Future<bool> hasCallPermissions() async {
    bool cameraGranted = await Permission.camera.isGranted;
    bool micGranted = await Permission.microphone.isGranted;

    return cameraGranted && micGranted;
  }

  /// Request only microphone permission (for audio-only calls)
  static Future<bool> requestMicrophonePermission() async {
    PermissionStatus status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Check if microphone permission is granted
  static Future<bool> hasMicrophonePermission() async {
    return await Permission.microphone.isGranted;
  }

  /// Open app settings if permissions are permanently denied
  static Future<void> openSettings() async {
    await openAppSettings();
  }
}
