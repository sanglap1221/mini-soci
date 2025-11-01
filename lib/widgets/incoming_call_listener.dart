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

  StreamSubscription<List<CallModel>>?
  _incomingCallSub; // ✅ FIX 1: Track the subscription
  StreamSubscription<DocumentSnapshot>? _specificCallSub;
  CallModel? _currentCall;
  String? _currentUserId;
  bool _isDialogShowing = false; // Add this flag

  @override
  void initState() {
    super.initState();
    _initializeListener(); // ✅ Cleaner async setup
  }

  Future<void> _initializeListener() async {
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;

    print('🔍 Current user ID: $_currentUserId'); // ✅ Debugging visibility

    if (_currentUserId == null) return;

    // ✅ FIX 2: Assign the subscription and listen to updates
    _incomingCallSub = _callService.listenToIncomingCalls(_currentUserId!).listen((
      calls,
    ) async {
      print('📞 Incoming call stream triggered. Calls found: ${calls.length}');

      if (calls.isNotEmpty) {
        final ringingCall = calls.first;
        print(
          '📞 Found call: ${ringingCall.callId}, calleeId: ${ringingCall.calleeId}, status: ${ringingCall.status}',
        );

        // If we are already showing a dialog for this specific call, ignore the event.
        if (_isDialogShowing && _currentCall?.callId == ringingCall.callId) {
          print(
            "🔁 Already showing dialog for call ${ringingCall.callId}, ignoring duplicate event.",
          );
          return;
        }

        // If no dialog is showing, proceed to show one for the new call.
        if (!_isDialogShowing && mounted) {
          _currentCall = ringingCall;
          _showAndMonitorCall(context, ringingCall);
        }
      }
    });
  }

  void _dismissIncomingCallDialog() {
    if (_isDialogShowing) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
      _stopSystemRingtone();

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
  void dispose() {
    _incomingCallSub
        ?.cancel(); // ✅ FIX 4: Cancel stream to prevent memory leaks
    _specificCallSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  void _showAndMonitorCall(BuildContext context, CallModel call) {
    // Start listening to this specific call for cancellations
    _specificCallSub?.cancel();
    _specificCallSub = _callService.listenToCall(call.callId).listen((
      snapshot,
    ) {
      if (!snapshot.exists) {
        print('📞 Call document ${call.callId} deleted. Dismissing dialog.');
        _dismissIncomingCallDialog();
        return;
      }
      final data = snapshot.data() as Map<String, dynamic>?;
      final status = data?['status'] as String?;

      // If caller cancels or rejects before we answer, dismiss the dialog.
      if (status == 'cancelled' || status == 'rejected') {
        print('📞 Call ${call.callId} was $status. Dismissing dialog.');
        _dismissIncomingCallDialog();
      }
    });

    if (call.status == 'ringing') {
      _callService.scheduleRingingTimeout(
        call.callId,
        // startedAtMillis: call.timestamp,
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

    if (!mounted) return; // ✅ Safety check

    showDialog(
      // Use the root navigator's context to show dialog over everything
      context: context,
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
            TextButton.icon(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await _callService.rejectCall(call.callId);
                } on FirebaseException catch (error) {
                  final message =
                      error.message ??
                      'Unable to reject call. Please try again.';
                  messenger.showSnackBar(SnackBar(content: Text(message)));
                } finally {
                  _stopSystemRingtone();
                  if (mounted) {
                    Navigator.of(context, rootNavigator: true).maybePop();
                  }
                }
              },
              icon: const Icon(Icons.call_end, color: Colors.red),
              label: const Text('Reject', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                await _callService.acceptCall(call.callId);
                _stopSystemRingtone();

                Navigator.of(
                  dialogContext,
                ).pop(); // Dismiss this specific dialog
                if (context.mounted) {
                  Navigator.push(
                    context,
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
                }
              },
              icon: const Icon(Icons.call),
              label: const Text('Accept'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    ).then((_) {
      // This block runs after the dialog is popped.
      _stopSystemRingtone();

      _specificCallSub?.cancel(); // Stop listening to the specific call
      _currentCall = null;
      _isDialogShowing = false;
    });
    _isDialogShowing = true;
  }
}
