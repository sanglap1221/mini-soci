import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;

  BuildContext? _dialogContext;
  String? _activeCallId;
  bool _dialogOpen = false;

  @override
  Widget build(BuildContext context) {
    if (_currentUserId == null) {
      return widget.child;
    }

    return StreamBuilder<List<CallModel>>(
      stream: _callService.listenToIncomingCalls(_currentUserId),
      builder: (context, snapshot) {
        // Show incoming call dialog if there's a ringing call
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          final incomingCall = snapshot.data!.first;

          // If dialog is not open or callId changed, show dialog
          if (!_dialogOpen || _activeCallId != incomingCall.callId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showIncomingCallDialog(context, incomingCall);
            });
          }

          // If call status is not ringing, close dialog if open
          if (_dialogOpen &&
              _activeCallId == incomingCall.callId &&
              (incomingCall.status == 'ended' ||
                  incomingCall.status == 'rejected' ||
                  incomingCall.status == 'accepted')) {
            if (_dialogContext != null) {
              Navigator.of(_dialogContext!).pop();
              _dialogOpen = false;
              _activeCallId = null;
              _dialogContext = null;
            }
          }
        } else {
          // No incoming call, close dialog if open
          if (_dialogOpen && _dialogContext != null) {
            Navigator.of(_dialogContext!).pop();
            _dialogOpen = false;
            _activeCallId = null;
            _dialogContext = null;
          }
        }

        return widget.child;
      },
    );
  }

  void _showIncomingCallDialog(BuildContext context, CallModel call) async {
    if (!mounted) return;
    if (_dialogOpen && _activeCallId == call.callId) return;
    _dialogOpen = true;
    _activeCallId = call.callId;

    // Get caller name and avatar
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
      debugPrint('Error fetching caller info: $e');
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        _dialogContext = dialogContext;
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
              CircleAvatar(
                radius: 40,
                backgroundColor: Colors.grey[300],
                backgroundImage: callerAvatar != null
                    ? CachedNetworkImageProvider(
                        ApiService().getFullImageUrl(callerAvatar),
                      )
                    : null,
                child: callerAvatar == null
                    ? const Icon(Icons.person, size: 40)
                    : null,
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
            // Reject button
            TextButton.icon(
              onPressed: () async {
                await _callService.rejectCall(call.callId);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                  _dialogOpen = false;
                  _activeCallId = null;
                  _dialogContext = null;
                }
              },
              icon: const Icon(Icons.call_end, color: Colors.red),
              label: const Text('Reject', style: TextStyle(color: Colors.red)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
            // Accept button
            ElevatedButton.icon(
              onPressed: () async {
                // Accept the call
                await _callService.acceptCall(call.callId);

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                  _dialogOpen = false;
                  _activeCallId = null;
                  _dialogContext = null;
                }

                if (context.mounted) {
                  // Navigate to call screen
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CallScreen(
                        callId: call.callId,
                        callerId: call.callerId,
                        receiverId: _currentUserId!,
                        isInitiator: false,
                        otherUserName: callerName,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
