import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pay_go/models/call_model.dart';
import 'package:pay_go/pages/call_screen.dart';
import 'package:pay_go/services/api_service.dart';
import 'package:pay_go/services/call_service.dart';
import 'package:pay_go/pages/user_call_log_page.dart';
import 'package:pay_go/utils/time_formatter.dart';

class CallHistoryPage extends StatefulWidget {
  const CallHistoryPage({super.key});

  @override
  State<CallHistoryPage> createState() => _CallHistoryPageState();
}

class _CallHistoryPageState extends State<CallHistoryPage> {
  final CallService _callService = CallService();
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;
  final Map<String, Map<String, dynamic>> _userDataCache = {};
  bool _isClearingHistory = false;

  Future<void> _showClearHistoryConfirmation(List<CallModel> calls) async {
    if (calls.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Call History?'),
        content: const Text(
          'Are you sure you want to permanently delete all call records? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && _currentUserId != null) {
      setState(() => _isClearingHistory = true);
      try {
        await _callService.clearCallHistory(_currentUserId!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Call history cleared.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to clear history: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isClearingHistory = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _currentUserId == null
          ? const Center(child: Text('Please log in to see call history.'))
          : StreamBuilder<List<CallModel>>(
              stream: _callService.getCallHistory(_currentUserId!),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final calls = snapshot.data ?? [];

                return Scaffold(
                  appBar: AppBar(
                    title: const Text('Call History'),
                    actions: [
                      if (calls.isNotEmpty && !_isClearingHistory)
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'clear') {
                              _showClearHistoryConfirmation(calls);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'clear',
                              child: Text('Clear all history'),
                            ),
                          ],
                        ),
                      if (_isClearingHistory)
                        const Padding(
                          padding: EdgeInsets.only(right: 16.0),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          ),
                        ),
                    ],
                  ),
                  body: calls.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.call_missed,
                                size: 64,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'No recent calls',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: calls.length,
                          itemBuilder: (context, index) {
                            final call = calls[index];
                            return _buildCallHistoryTile(call);
                          },
                        ),
                );
              },
            ),
    );
  }

  Widget _buildCallHistoryTile(CallModel call) {
    final isOutgoing = call.callerId == _currentUserId;
    final otherUserId = isOutgoing ? call.calleeId : call.callerId;

    return FutureBuilder<Map<String, dynamic>>(
      future: _getOtherUserData(otherUserId),
      builder: (context, snapshot) {
        final otherUserData = snapshot.data ?? {};
        final otherUserName = otherUserData['username'] as String? ?? 'Unknown';
        final otherUserAvatar = otherUserData['profilePicUrl'] as String?;

        return ListTile(
          leading: SizedBox(
            width: 48,
            height: 48,
            child: ClipOval(
              child: CachedNetworkImage(
                imageUrl: ApiService().getFullImageUrl(otherUserAvatar!),
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    const CircularProgressIndicator(),
                errorWidget: (context, url, error) => CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.grey[300],
                  child: Text(
                    otherUserName.isNotEmpty ? otherUserName[0] : 'U',
                  ),
                ),
              ),
            ),
          ),
          title: Text(
            otherUserName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Row(
            children: [
              _getCallStatusIcon(call, isOutgoing),
              const SizedBox(width: 4),
              Text(
                formatTimestamp(call.timestamp, detail: true) ??
                    'some time ago',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
          trailing: IconButton(
            icon: Icon(
              call.isVideoCall ? Icons.videocam : Icons.call,
              color: Theme.of(context).primaryColor,
            ),
            onPressed: () => _startCall(
              otherUserId,
              otherUserName,
              otherUserAvatar,
              call.isVideoCall,
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _getOtherUserData(String userId) async {
    if (_userDataCache.containsKey(userId)) {
      return _userDataCache[userId]!;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _userDataCache[userId] = data;
          });
        }
        return data;
      }
    } catch (e) {
      debugPrint('Error fetching user data for $userId: $e');
    }
    return {};
  }

  Icon _getCallStatusIcon(CallModel call, bool isOutgoing) {
    Color iconColor;
    IconData iconData;

    if (isOutgoing) {
      iconData = Icons.call_made;
      iconColor = Colors.green;
    } else {
      // Incoming call
      if (call.status == 'ended') {
        iconData = Icons.call_received;
        iconColor = Colors.blue;
      } else {
        // Missed, rejected, or cancelled
        iconData = Icons.call_missed;
        iconColor = Colors.red;
      }
    }

    return Icon(iconData, color: iconColor, size: 16);
  }

  Future<void> _startCall(
    String otherUserId,
    String otherUserName,
    String? otherUserAvatarUrl,
    bool isVideoCall,
  ) async {
    if (_currentUserId == null) return;

    try {
      // Create call document in Firestore
      final callId = await _callService.createCall(
        callerId: _currentUserId,
        calleeId: otherUserId,
        isVideoCall: isVideoCall,
      );

      if (!mounted) return;

      // Navigate to CallScreen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CallScreen(
            callId: callId,
            callerId: _currentUserId,
            receiverId: otherUserId,
            isInitiator: true,
            isVideoCall: isVideoCall,
            otherUserName: otherUserName,
            otherUserAvatarUrl: otherUserAvatarUrl,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error starting call: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start call: $e')));
      }
    }
  }
}

/// A utility extension on DateTime to format timestamps for the call history.
extension DateTimeFormatting on DateTime {
  String toCallHistoryString() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOfCall = DateTime(year, month, day);

    final timeString =
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

    if (dateOfCall == today) {
      return 'Today, $timeString';
    } else if (dateOfCall == yesterday) {
      return 'Yesterday, $timeString';
    } else {
      return '${day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}/${year.toString().substring(2)}';
    }
  }
}

String? formatTimestamp(dynamic timestamp, {bool detail = false}) {
  DateTime? dateTime;
  if (timestamp is Timestamp) {
    dateTime = timestamp.toDate();
  } else if (timestamp is DateTime) {
    dateTime = timestamp;
  } else if (timestamp is int) {
    dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
  } else if (timestamp is String) {
    dateTime = DateTime.tryParse(timestamp);
  }

  if (dateTime == null) return null;

  if (detail) {
    return dateTime.toCallHistoryString();
  }

  final now = DateTime.now();
  final difference = now.difference(dateTime);

  if (difference.inSeconds < 60) {
    return 'Just now';
  } else if (difference.inMinutes < 60) {
    return '${difference.inMinutes}m ago';
  } else if (difference.inHours < 24) {
    return '${difference.inHours}h ago';
  } else if (difference.inDays < 7) {
    return '${difference.inDays}d ago';
  } else {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }
}
