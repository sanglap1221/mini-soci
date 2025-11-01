import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/call_model.dart';
import '../services/api_service.dart';
import '../services/call_service.dart';
import 'call_history_detail_page.dart';
import 'call_screen.dart';

class CallHistoryPage extends StatefulWidget {
  const CallHistoryPage({Key? key}) : super(key: key);

  @override
  State<CallHistoryPage> createState() => _CallHistoryPageState();
}

class _CallHistoryPageState extends State<CallHistoryPage> {
  final CallService _callService = CallService();
  final ApiService _apiService = ApiService();
  String? _currentUserId;
  final Map<String, Map<String, dynamic>> _userDataCache = {};

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _currentUserId = null;
      });
      return;
    }

    await _callService.initializeLocalCache();
    _callService.startCallHistorySync(user.uid);

    if (mounted) {
      setState(() {
        _currentUserId = user.uid;
      });
    }
  }

  /// ✅ FIXED: Removed setState() here — this was causing infinite rebuilds.
  /// Now the cache updates silently, no UI trigger unless necessary.
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
        _userDataCache[userId] = data; // ✅ Cache without triggering rebuild
        return data;
      }
    } catch (e) {
      debugPrint('Error fetching user data for $userId: $e');
    }
    return {};
  }

  @override
  void dispose() {
    _callService.stopCallHistorySync();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUserId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Call History'),
        actions: [
          // IconButton(
          //   onPressed: () async {
          //     final confirm = await showDialog<bool>(
          //       context: context,
          //       builder: (context) => AlertDialog(
          //         title: const Text('Clear Call History'),
          //         content: const Text(
          //           'Are you sure you want to delete all call history?',
          //         ),
          //         actions: [
          //           TextButton(
          //             onPressed: () => Navigator.pop(context, false),
          //             child: const Text('Cancel'),
          //           ),
          //           TextButton(
          //             onPressed: () => Navigator.pop(context, true),
          //             child: const Text('Yes, Clear'),
          //           ),
          //         ],
          //       ),
          //     );
          //     if (confirm == true) {
          //       await _callService.clearCallHistory(_currentUserId!);
          //     }
          //   },
          //   icon: const Icon(Icons.delete_forever),
          //   tooltip: 'Clear All',
          // ),
        ],
      ),

      body: ValueListenableBuilder<Box<CallModel>>(
        valueListenable: _callService.callHistoryListenable(),
        builder: (context, box, _) {
          final calls = _currentUserId == null
              ? const <CallModel>[]
              : _callService.getLocalCallHistory(_currentUserId!);
          final summaries = _buildContactSummaries(calls);

          if (summaries.isEmpty) {
            return const Center(child: Text('No call history found.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: summaries.length,
            itemBuilder: (context, index) {
              final summary = summaries[index];

              return FutureBuilder<Map<String, dynamic>>(
                future: _getOtherUserData(summary.otherUserId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const ListTile(
                      leading: CircleAvatar(child: Icon(Icons.person)),
                      title: Text('Loading user...'),
                    );
                  }

                  final data = snapshot.data ?? {};
                  final displayName = _resolveDisplayName(
                    data,
                    fallback: summary.otherUserId,
                  );
                  final avatarUrl = _resolveAvatarUrl(data);

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ListTile(
                      onTap: () => _openDetailPage(
                        summary: summary,
                        displayName: displayName,
                        avatarUrl: avatarUrl,
                      ),
                      leading: CircleAvatar(
                        backgroundImage: avatarUrl != null
                            ? NetworkImage(avatarUrl)
                            : null,
                        child: avatarUrl == null
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _buildSummarySubtitle(summary),
                            style: TextStyle(
                              color: _callColor(summary.latestCall),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${summary.completedCalls} completed • ${summary.missedCalls} missed',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                      trailing: SizedBox(
                        width: 112,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _formatTimestamp(summary.latestCall.timestamp),
                              style: const TextStyle(fontSize: 12),
                              textAlign: TextAlign.right,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  _formatDuration(summary.totalDuration),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(width: 6),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => _startCall(
                                      isVideoCall:
                                          summary.latestCall.isVideoCall,
                                      otherUserId: summary.otherUserId,
                                      otherUserName: displayName,
                                      avatarUrl: avatarUrl,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(
                                        summary.latestCall.isVideoCall
                                            ? Icons.videocam
                                            : Icons.call,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Color _callColor(CallModel call) {
    if (call.status == 'cancelled' || call.status == 'rejected') {
      return Colors.grey;
    }
    if (call.status == 'missed') {
      return Colors.red;
    }
    return Colors.green;
  }

  // ✅ Helper: Format time
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

  List<_CallContactSummary> _buildContactSummaries(List<CallModel> calls) {
    if (_currentUserId == null) {
      return const [];
    }

    final Map<String, List<CallModel>> grouped = {};
    for (final call in calls) {
      final otherId = call.callerId == _currentUserId
          ? call.calleeId
          : call.callerId;
      grouped.putIfAbsent(otherId, () => <CallModel>[]).add(call);
    }

    final summaries = grouped.entries.map((entry) {
      final sortedCalls = List<CallModel>.from(entry.value)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final latest = sortedCalls.first;
      final totalDuration = sortedCalls.fold<Duration>(
        Duration.zero,
        (acc, call) => acc + _callDuration(call),
      );
      final lastDuration = _callDuration(latest);
      final completed = sortedCalls.where((c) => c.status == 'ended').length;
      final missed = sortedCalls
          .where((c) => c.status == 'cancelled' || c.status == 'rejected')
          .length;

      return _CallContactSummary(
        otherUserId: entry.key,
        calls: sortedCalls,
        latestCall: latest,
        totalDuration: totalDuration,
        lastDuration: lastDuration,
        completedCalls: completed,
        missedCalls: missed,
      );
    }).toList();

    summaries.sort(
      (a, b) => b.latestCall.timestamp.compareTo(a.latestCall.timestamp),
    );

    return summaries;
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

  String _buildSummarySubtitle(_CallContactSummary summary) {
    final latest = summary.latestCall;
    final isOutgoing = latest.callerId == _currentUserId;
    final directionLabel = isOutgoing ? 'Outgoing' : 'Incoming';
    final typeLabel = latest.isVideoCall ? 'video' : 'audio';
    final durationLabel = _formatDuration(summary.lastDuration);

    if (latest.status == 'cancelled') {
      return isOutgoing
          ? 'Cancelled $typeLabel call'
          : 'Missed $typeLabel call';
    }
    if (latest.status == 'rejected') {
      return 'Rejected $typeLabel call';
    }
    if (latest.status == 'ended') {
      return '$directionLabel $typeLabel • $durationLabel';
    }
    return '$directionLabel $typeLabel';
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
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }

  String _resolveDisplayName(
    Map<String, dynamic> data, {
    required String fallback,
  }) {
    return data['username'] as String? ??
        data['displayName'] as String? ??
        data['name'] as String? ??
        fallback;
  }

  String? _resolveAvatarUrl(Map<String, dynamic> data) {
    final raw =
        data['profileImageUrl'] ??
        data['profilePicUrl'] ??
        data['profilePicture'] ??
        data['avatar'];
    if (raw is String && raw.isNotEmpty) {
      return _apiService.getFullImageUrl(raw);
    }
    return null;
  }

  Future<void> _openDetailPage({
    required _CallContactSummary summary,
    required String displayName,
    required String? avatarUrl,
  }) async {
    if (!mounted || _currentUserId == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CallHistoryDetailPage(
          currentUserId: _currentUserId!,
          otherUserId: summary.otherUserId,
          contactName: displayName,
          contactAvatarUrl: avatarUrl,
          calls: summary.calls,
        ),
      ),
    );
  }

  Future<void> _startCall({
    required bool isVideoCall,
    required String otherUserId,
    required String otherUserName,
    required String? avatarUrl,
  }) async {
    if (_currentUserId == null) return;

    try {
      final callId = await _callService.createCall(
        callerId: _currentUserId!,
        calleeId: otherUserId,
        isVideoCall: isVideoCall,
      );

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CallScreen(
            callId: callId,
            callerId: _currentUserId!,
            receiverId: otherUserId,
            isInitiator: true,
            isVideoCall: isVideoCall,
            otherUserName: otherUserName,
            otherUserAvatarUrl: avatarUrl,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to start call: $error')));
    }
  }
}

class _CallContactSummary {
  _CallContactSummary({
    required this.otherUserId,
    required this.calls,
    required this.latestCall,
    required this.totalDuration,
    required this.lastDuration,
    required this.completedCalls,
    required this.missedCalls,
  });

  final String otherUserId;
  final List<CallModel> calls;
  final CallModel latestCall;
  final Duration totalDuration;
  final Duration lastDuration;
  final int completedCalls;
  final int missedCalls;
}
