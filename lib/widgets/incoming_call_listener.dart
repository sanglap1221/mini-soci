import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/call_service.dart';
import '../models/call_model.dart';
import '../pages/call_screen.dart';
import '../services/api_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class IncomingCallListener extends StatefulWidget {
  final Widget child;

  const IncomingCallListener({super.key, required this.child});

  @override
  State<IncomingCallListener> createState() => _IncomingCallListenerState();
}

class _IncomingCallListenerState extends State<IncomingCallListener> {
  final CallService _callService = CallService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  static const MethodChannel _platform = MethodChannel('com.paygo/ringtone');

  StreamSubscription<List<CallModel>>? _incomingCallSub;
  StreamSubscription<DocumentSnapshot>? _specificCallSub;
  CallModel? _currentCall;
  String? _currentUserId;
  // A flag to prevent duplicate dialogs for the same call.
  bool _isDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _initializeListener(); // ✅ Cleaner async setup
  }

  @override
  void dispose() {
    _incomingCallSub?.cancel();
    _specificCallSub?.cancel();
    _audioPlayer.dispose();
    _stopSystemRingtone(); // Ensure ringtone is stopped if widget is disposed.
    super.dispose();
  }

  Future<void> _initializeListener() async {
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;

    debugPrint('🔍 Current user ID: $_currentUserId'); // ✅ Debugging visibility

    if (_currentUserId == null) return;

    _incomingCallSub = _callService.listenToIncomingCalls(_currentUserId!).listen((
      calls,
    ) async {
      debugPrint(
        '📞 Incoming call stream triggered. Calls found: ${calls.length}',
      );

      if (calls.isNotEmpty) {
        final ringingCall = calls.first;
        debugPrint(
          '📞 Found call: ${ringingCall.callId}, calleeId: ${ringingCall.calleeId}, status: ${ringingCall.status}',
        );

        // If a dialog for this call is already showing, ignore the event.
        if (_isDialogShowing && _currentCall?.callId == ringingCall.callId) {
          debugPrint(
            "🔁 Already showing dialog for call ${ringingCall.callId}, ignoring duplicate event.",
          );
          return;
        }

        // If no dialog is active, show one for the new incoming call.
        if (!_isDialogShowing && mounted) {
          _currentCall = ringingCall;
          _showAndMonitorCall(context, ringingCall);
        }
      }
    });
  }

  /// Dismisses the currently active incoming call dialog and cleans up resources.
  void _dismissIncomingCallDialog() {
    if (_isDialogShowing) {
      if (mounted) {
        // Use rootNavigator to pop the dialog which is shown on top of everything.
        Navigator.of(context, rootNavigator: true).maybePop();
      }
      _stopSystemRingtone(); // This is called again in .then(), but it's safe.

      _currentCall = null;
      _specificCallSub?.cancel();
      _isDialogShowing = false;
    }
  }

  void _startSystemRingtone() async {
    try {
      await _platform.invokeMethod('playRingtone');
    } catch (e) {
      debugPrint('⚠️ Error playing system ringtone: $e');
    }
  }

  void _stopSystemRingtone() async {
    try {
      await _platform.invokeMethod('stopRingtone');
    } catch (e) {
      debugPrint('⚠️ Error stopping system ringtone: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  /// Shows the incoming call dialog and starts a listener to monitor
  /// the call's status for cancellations or rejections by the caller.
  void _showAndMonitorCall(BuildContext context, CallModel call) {
    // Start listening to this specific call for cancellations
    _specificCallSub?.cancel();
    _specificCallSub = _callService.listenToCall(call.callId).listen((
      snapshot,
    ) {
      if (!snapshot.exists) {
        debugPrint(
          '📞 Call document ${call.callId} deleted. Dismissing dialog.',
        );
        _dismissIncomingCallDialog();
        return;
      }
      final data = snapshot.data() as Map<String, dynamic>?;
      final status = data?['status'] as String?;

      // If caller cancels or the call is rejected remotely, dismiss the dialog.
      if (status == 'cancelled' || status == 'rejected') {
        debugPrint('📞 Call ${call.callId} was $status. Dismissing dialog.');
        _dismissIncomingCallDialog();
      }
    });

    if (call.status == 'ringing') {
      _callService.scheduleRingingTimeout(
        call.callId,
        startedAt: call.timestamp,
      );
    }

    _showIncomingCallDialog(context, call);
  }

  Future<void> _showIncomingCallDialog(
    BuildContext context,
    CallModel call,
  ) async {
    _startSystemRingtone();
    // Capture a navigator that is safe to use across async gaps.
    // The root navigator is used to show the dialog over all other content.
    final dialogHost = Navigator.of(context, rootNavigator: true);

    String callerName = 'Unknown User';
    String? callerAvatar;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(call.callerId)
          .get();

      if (doc.exists) {
        final data = doc.data();
        callerName =
            data?['username'] as String? ??
            data?['displayName'] as String? ??
            data?['name'] as String? ??
            'Unknown User';
        callerAvatar =
            data?['profilePicUrl'] as String? ??
            data?['profilePicture'] as String? ??
            data?['avatar'] as String?;
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching caller info: $e');
    }

    if (!mounted) return;

    showDialog(
      // Use the captured navigator's context to ensure it's valid.
      context: dialogHost.context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                call.isVideoCall ? Icons.videocam : Icons.call,
                color: Colors.green,
              ),
              const SizedBox(width: 8),
              const Text('Incoming Call'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: callerAvatar != null
                        ? ApiService().getFullImageUrl(callerAvatar)
                        : '',
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        const CircularProgressIndicator(),
                    errorWidget: (context, url, error) => CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.grey[300],
                      child: Text(
                        callerName.isNotEmpty
                            ? callerName[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(fontSize: 40),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                callerName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                call.isVideoCall ? 'Video Call' : 'Voice Call',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: [
            // Reject circular button with label
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RawMaterialButton(
                  onPressed: () async {
                    // Capture UI controllers before the async gap
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    final rootNavigator = Navigator.of(
                      context,
                      rootNavigator: true,
                    );
                    try {
                      await _callService.rejectCall(call.callId);
                    } on FirebaseException catch (error) {
                      final message =
                          error.message ??
                          'Unable to reject call. Please try again.';
                      messenger?.showSnackBar(
                        SnackBar(
                          content: Text(message),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    } finally {
                      _stopSystemRingtone();
                      if (rootNavigator.mounted) {
                        rootNavigator.maybePop();
                      }
                    }
                  },
                  fillColor: Colors.red.shade600,
                  elevation: 2,
                  constraints: const BoxConstraints.tightFor(
                    width: 64,
                    height: 64,
                  ),
                  shape: const CircleBorder(),
                  child: const Icon(Icons.call_end, color: Colors.white),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Reject',
                  style: TextStyle(fontSize: 12, color: Colors.red),
                ),
              ],
            ),
            // Accept circular button with label
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RawMaterialButton(
                  onPressed: () async {
                    // Capture navigators/contexts before awaiting
                    final navigator = Navigator.of(context);
                    final dialogNavigator = Navigator.of(dialogContext);
                    try {
                      await _callService.acceptCall(call.callId);
                    } finally {
                      _stopSystemRingtone();
                    }

                    // Use the captured NavigatorState to pop the dialog safely
                    if (dialogNavigator.mounted) {
                      dialogNavigator.pop();
                    }

                    if (!navigator.mounted) {
                      return;
                    }

                    navigator.push(
                      MaterialPageRoute(
                        builder: (context) => CallScreen(
                          callId: call.callId,
                          callerId: call.callerId,
                          receiverId: _currentUserId!,
                          isInitiator: false,
                          otherUserName: callerName,
                          isVideoCall: call.isVideoCall,
                          otherUserAvatarUrl: callerAvatar,
                        ),
                      ),
                    );
                  },
                  fillColor: Colors.green.shade600,
                  elevation: 2,
                  constraints: const BoxConstraints.tightFor(
                    width: 64,
                    height: 64,
                  ),
                  shape: const CircleBorder(),
                  child: const Icon(Icons.call, color: Colors.white),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Accept',
                  style: TextStyle(fontSize: 12, color: Colors.green),
                ),
              ],
            ),
          ],
        );
      },
    ).then((_) {
      // This block runs after the dialog is popped, for any reason.
      // This is a crucial cleanup step.
      _stopSystemRingtone();
      _specificCallSub?.cancel();
      _currentCall = null;
      _isDialogShowing = false;
    });
    _isDialogShowing = true;
  }
}
