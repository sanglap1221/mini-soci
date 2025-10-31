import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/call_model.dart';
import '../services/call_service.dart';

class CallHistoryPage extends StatefulWidget {
  const CallHistoryPage({Key? key}) : super(key: key);

  @override
  State<CallHistoryPage> createState() => _CallHistoryPageState();
}

class _CallHistoryPageState extends State<CallHistoryPage> {
  final CallService _callService = CallService();
  String? _currentUserId;
  final Map<String, Map<String, dynamic>> _userDataCache = {};

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;

    setState(() {
      _currentUserId = user?.uid;
    });
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
  Widget build(BuildContext context) {
    if (_currentUserId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Call History'),
        actions: [
          IconButton(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear Call History'),
                  content: const Text(
                    'Are you sure you want to delete all call history?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Yes, Clear'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await _callService.clearCallHistory(_currentUserId!);
              }
            },
            icon: const Icon(Icons.delete_forever),
            tooltip: 'Clear All',
          ),
        ],
      ),

      /// ✅ Main StreamBuilder now only used once (body)
      /// This prevents redundant rebuilds of AppBar etc.
      body: StreamBuilder<List<CallModel>>(
        stream: _callService.getCallHistory(_currentUserId!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No call history found.'));
          }

          final calls = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: calls.length,
            itemBuilder: (context, index) {
              final call = calls[index];
              final otherUserId = call.callerId == _currentUserId
                  ? call.calleeId
                  : call.callerId;

              /// ✅ Only one FutureBuilder per item for user data.
              return FutureBuilder<Map<String, dynamic>>(
                future: _getOtherUserData(otherUserId),
                builder: (context, userSnapshot) {
                  if (userSnapshot.connectionState == ConnectionState.waiting) {
                    return const ListTile(
                      leading: CircleAvatar(child: Icon(Icons.person)),
                      title: Text('Loading user...'),
                    );
                  }

                  final userData = userSnapshot.data ?? {};
                  final userName = userData['name'] ?? 'Unknown User';
                  final profileUrl = userData['profileImageUrl'] ?? '';

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundImage: profileUrl.isNotEmpty
                            ? NetworkImage(profileUrl)
                            : null,
                        child: profileUrl.isEmpty
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text(userName),
                      subtitle: Text(
                        _formatCallType(call),
                        style: TextStyle(color: _callColor(call)),
                      ),
                      trailing: Text(
                        _formatTimestamp(call.timestamp as Timestamp),
                        style: const TextStyle(fontSize: 12),
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

  // ✅ Helper: Return color for call status
  Color _callColor(CallModel call) {
    if (call.status == 'missed') return Colors.red;
    if (call.status == 'rejected') return Colors.grey;
    return Colors.green;
  }

  // ✅ Helper: Display proper call type
  String _formatCallType(CallModel call) {
    final isOutgoing = call.callerId == _currentUserId;
    final type = call.isVideoCall ? 'Video' : 'Audio';
    if (call.status == 'missed') return 'Missed $type call';
    if (call.status == 'rejected') return 'Rejected $type call';
    return isOutgoing ? 'Outgoing $type call' : 'Incoming $type call';
  }

  // ✅ Helper: Format time
  String _formatTimestamp(Timestamp timestamp) {
    final date = timestamp.toDate();
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
}
