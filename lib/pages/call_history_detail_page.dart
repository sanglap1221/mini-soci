import 'package:flutter/material.dart';

import '../models/call_model.dart';
import '../services/call_service.dart';
import 'call_screen.dart';
import 'profile_page.dart';

class CallHistoryDetailPage extends StatelessWidget {
  const CallHistoryDetailPage({
    super.key,
    required this.currentUserId,
    required this.otherUserId,
    required this.contactName,
    required this.contactAvatarUrl,
    required this.calls,
  });

  final String currentUserId;
  final String otherUserId;
  final String contactName;
  final String? contactAvatarUrl;
  final List<CallModel> calls;

  static final CallService _callService = CallService();

  @override
  Widget build(BuildContext context) {
    final sortedCalls = List<CallModel>.from(calls)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: contactAvatarUrl != null
                  ? NetworkImage(contactAvatarUrl!)
                  : null,
              child: contactAvatarUrl == null
                  ? const Icon(Icons.person, size: 18)
                  : null,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                contactName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'View Profile',
            icon: const Icon(Icons.person_outline),
            onPressed: () => _openProfile(context),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: sortedCalls.length,
        itemBuilder: (context, index) {
          final call = sortedCalls[index];
          final isOutgoing = call.callerId == currentUserId;
          final duration = _callDuration(call);
          final statusLabel = _buildStatusLabel(call, isOutgoing);

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundImage: contactAvatarUrl != null
                    ? NetworkImage(contactAvatarUrl!)
                    : null,
                child: contactAvatarUrl == null
                    ? const Icon(Icons.person)
                    : null,
              ),
              title: Text(statusLabel),
              subtitle: Text(
                '${_formatTimestamp(call.timestamp)} • ${_formatDuration(duration)}',
              ),
              trailing: Icon(
                call.isVideoCall ? Icons.videocam : Icons.call,
                color: _statusColor(call.status),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.call),
                label: const Text('Audio call'),
                onPressed: () => _startCall(context, isVideoCall: false),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.videocam),
                label: const Text('Video call'),
                onPressed: () => _startCall(context, isVideoCall: true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildStatusLabel(CallModel call, bool isOutgoing) {
    final typeLabel = call.isVideoCall ? 'video' : 'audio';
    switch (call.status) {
      case 'cancelled':
        return isOutgoing
            ? 'Cancelled $typeLabel call'
            : 'Missed $typeLabel call';
      case 'rejected':
        return 'Rejected $typeLabel call';
      case 'ended':
        return isOutgoing
            ? 'Outgoing $typeLabel call'
            : 'Incoming $typeLabel call';
      default:
        return isOutgoing
            ? 'Outgoing $typeLabel call'
            : 'Incoming $typeLabel call';
    }
  }

  Duration _callDuration(CallModel call) {
    if (call.duration != null) {
      return call.duration!;
    }
    if (call.endedAt != null) {
      final diff = call.endedAt!.difference(call.timestamp);
      return diff.isNegative ? Duration.zero : diff;
    }
    return Duration.zero;
  }

  String _formatTimestamp(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  String _formatDuration(Duration duration) {
    if (duration == Duration.zero) {
      return '0:00';
    }
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'ended':
        return Colors.green;
      case 'cancelled':
      case 'rejected':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

  void _openProfile(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ProfilePage(userId: otherUserId)));
  }

  Future<void> _startCall(
    BuildContext context, {
    required bool isVideoCall,
  }) async {
    try {
      final callId = await _callService.createCall(
        callerId: currentUserId,
        calleeId: otherUserId,
        isVideoCall: isVideoCall,
      );

      final navigator = Navigator.of(context);
      if (!navigator.mounted) return;

      navigator.push(
        MaterialPageRoute(
          builder: (context) => CallScreen(
            callId: callId,
            callerId: currentUserId,
            receiverId: otherUserId,
            isInitiator: true,
            isVideoCall: isVideoCall,
            otherUserName: contactName,
            otherUserAvatarUrl: contactAvatarUrl,
          ),
        ),
      );
    } catch (error) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(content: Text('Failed to start call: $error')),
      );
    }
  }
}
