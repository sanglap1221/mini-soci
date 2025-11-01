import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/call_model.dart';

class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  static const String callHistoryBoxName = 'call_history';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();
  final Map<String, Timer> _ringingTimeouts = <String, Timer>{};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _historySubscription;

  static void registerAdapters() {
    final adapter = CallModelAdapter();
    if (!Hive.isAdapterRegistered(adapter.typeId)) {
      Hive.registerAdapter(adapter);
    }
  }

  Future<void> initializeLocalCache() async {
    if (!Hive.isBoxOpen(callHistoryBoxName)) {
      try {
        await Hive.openBox<CallModel>(callHistoryBoxName);
      } catch (error) {
        debugPrint('Failed to open Hive box $callHistoryBoxName: $error');
        await Hive.deleteBoxFromDisk(callHistoryBoxName);
        await Hive.openBox<CallModel>(callHistoryBoxName);
      }
    }
  }

  ValueListenable<Box<CallModel>> callHistoryListenable() {
    return Hive.box<CallModel>(callHistoryBoxName).listenable();
  }

  List<CallModel> getLocalCallHistory(String userId) {
    final box = Hive.box<CallModel>(callHistoryBoxName);
    final calls = box.values
        .where((call) => call.participants.contains(userId))
        .toList(growable: false);
    calls.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return calls;
  }

  void startCallHistorySync(String userId) {
    _historySubscription?.cancel();
    _historySubscription = _firestore
        .collection('calls')
        .where('participants', arrayContains: userId)
        .where('status', whereIn: ['ended', 'rejected', 'cancelled'])
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen(
          (snapshot) async {
            final box = Hive.box<CallModel>(callHistoryBoxName);
            final idsInSnapshot = <String>{};
            for (final doc in snapshot.docs) {
              final model = CallModel.fromFirestore(doc.data(), doc.id);
              idsInSnapshot.add(model.callId);
              await box.put(model.callId, model);
            }

            final staleIds = box.values
                .where((call) => call.participants.contains(userId))
                .where((call) => !idsInSnapshot.contains(call.callId))
                .map((call) => call.callId)
                .toList(growable: false);

            if (staleIds.isNotEmpty) {
              await box.deleteAll(staleIds);
            }
          },
          onError: (Object error, StackTrace stack) {
            if (error is FirebaseException &&
                error.code == 'permission-denied') {
              debugPrint(
                'Call history sync permission denied for user $userId: ${error.message}',
              );
            } else {
              debugPrint('Call history sync error: $error');
            }
          },
        );
  }

  void stopCallHistorySync() {
    _historySubscription?.cancel();
    _historySubscription = null;
  }

  /// Create a new call document in Firestore
  Future<String> createCall({
    required String callerId,
    required String calleeId,
    required bool isVideoCall,
  }) async {
    final callId = _uuid.v4();
    final now = DateTime.now();
    final call = CallModel(
      callId: callId,
      callerId: callerId,
      calleeId: calleeId,
      status: 'ringing',
      timestamp: now,
      isVideoCall: isVideoCall,
      participants: <String>[callerId, calleeId],
      offer: <String, dynamic>{},
      answer: <String, dynamic>{},
      callerCandidates: <dynamic>[],
      calleeCandidates: <dynamic>[],
      endedAt: null,
      endReason: null,
    );

    await _firestore.collection('calls').doc(callId).set(call.toFirestore());

    scheduleRingingTimeout(callId, startedAt: now);
    return callId;
  }

  /// Listen to call document changes
  Stream<DocumentSnapshot> listenToCall(String callId) {
    return _firestore.collection('calls').doc(callId).snapshots();
  }

  /// Update call document
  Future<void> updateCall(String callId, Map<String, dynamic> data) {
    return _firestore.collection('calls').doc(callId).update(data);
  }

  void scheduleRingingTimeout(
    String callId, {
    Duration timeout = const Duration(seconds: 30),
    DateTime? startedAt,
  }) {
    Duration delay = timeout;
    if (startedAt != null) {
      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed >= timeout) {
        delay = Duration.zero;
      } else {
        delay = timeout - elapsed;
      }
    }

    _ringingTimeouts[callId]?.cancel();
    _ringingTimeouts[callId] = Timer(delay, () async {
      try {
        final snapshot = await _firestore.collection('calls').doc(callId).get();
        if (!snapshot.exists) {
          return;
        }
        final data = snapshot.data();
        final status = data?['status'] as String? ?? 'ringing';
        if (status == 'ringing') {
          await _firestore.collection('calls').doc(callId).update({
            'status': 'cancelled',
            'endReason': 'timeout',
            'endedAt': FieldValue.serverTimestamp(),
          });
          await _persistEndedCall(callId);
        }
      } catch (error) {
        debugPrint('Error auto-cancelling call $callId: $error');
      } finally {
        cancelRingingTimeout(callId);
      }
    });
  }

  void cancelRingingTimeout(String callId) {
    final timer = _ringingTimeouts.remove(callId);
    timer?.cancel();
  }

  /// Accept the call
  Future<void> acceptCall(String callId) {
    cancelRingingTimeout(callId);
    return _firestore.collection('calls').doc(callId).update({
      'status': 'accepted',
    });
  }

  /// End the call. Adjusts the resulting status based on current call state
  /// so that security rules allow the transition (e.g., caller cancelling while
  /// still ringing).
  Future<void> endCall(String callId, {String? actorId}) async {
    cancelRingingTimeout(callId);

    final doc = await _firestore.collection('calls').doc(callId).get();
    if (!doc.exists) {
      return;
    }

    final data = doc.data()!;
    final currentStatus = data['status'] as String? ?? 'ringing';
    final callerId = data['callerId'] as String?;
    final calleeId = data['calleeId'] as String?;
    final uid = actorId ?? FirebaseAuth.instance.currentUser?.uid;

    String nextStatus = 'ended';
    if (currentStatus == 'ringing') {
      if (uid != null && uid == callerId) {
        nextStatus = 'cancelled';
      } else if (uid != null && uid == calleeId) {
        nextStatus = 'rejected';
      } else {
        nextStatus = 'cancelled';
      }
    }

    await _firestore.collection('calls').doc(callId).update({
      'status': nextStatus,
      'endedAt': FieldValue.serverTimestamp(),
      'endReason': nextStatus == 'cancelled' ? 'caller_cancelled' : null,
    });
    await _persistEndedCall(callId);
  }

  /// Reject the call
  Future<void> rejectCall(String callId) async {
    cancelRingingTimeout(callId);
    try {
      await _firestore.collection('calls').doc(callId).update({
        'status': 'rejected',
      });
      await _persistEndedCall(callId);
    } on FirebaseException catch (error) {
      debugPrint('Error rejecting call $callId: ${error.message}');
      rethrow;
    }
  }

  /// Save WebRTC offer
  Future<void> setOffer(String callId, Map<String, dynamic> offer) {
    return _firestore.collection('calls').doc(callId).update({'offer': offer});
  }

  /// Save WebRTC answer
  Future<void> setAnswer(String callId, Map<String, dynamic> answer) {
    return _firestore.collection('calls').doc(callId).update({
      'answer': answer,
    });
  }

  /// Add ICE candidate for caller
  Future<void> addCallerCandidate(
    String callId,
    Map<String, dynamic> candidate,
  ) {
    return _firestore.collection('calls').doc(callId).update({
      'callerCandidates': FieldValue.arrayUnion([candidate]),
    });
  }

  /// Add ICE candidate for callee
  Future<void> addCalleeCandidate(
    String callId,
    Map<String, dynamic> candidate,
  ) {
    return _firestore.collection('calls').doc(callId).update({
      'calleeCandidates': FieldValue.arrayUnion([candidate]),
    });
  }

  /// Get call by ID
  Future<CallModel?> getCall(String callId) async {
    final doc = await _firestore.collection('calls').doc(callId).get();
    if (!doc.exists) return null;
    return CallModel.fromFirestore(doc.data()!, doc.id);
  }

  /// Listen to incoming calls for a user
  Stream<List<CallModel>> listenToIncomingCalls(String userId) {
    return _firestore
        .collection('calls')
        .where('calleeId', isEqualTo: userId)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => CallModel.fromFirestore(doc.data(), doc.id))
              .toList(),
        );
  }

  /// Deletes all call history for a given user.
  Future<void> clearCallHistory(String userId) async {
    final WriteBatch batch = _firestore.batch();

    // Use a single query on the 'participants' array to find all calls for the user.
    final query = _firestore
        .collection('calls')
        .where('participants', arrayContains: userId);

    final snapshot = await query.get();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();

    final box = Hive.box<CallModel>(callHistoryBoxName);
    final idsToDelete = snapshot.docs.map((doc) => doc.id).toList();
    if (idsToDelete.isNotEmpty) {
      await box.deleteAll(idsToDelete);
    }
  }

  Future<void> _persistEndedCall(String callId) async {
    try {
      final doc = await _firestore.collection('calls').doc(callId).get();
      if (!doc.exists) return;
      final model = CallModel.fromFirestore(doc.data()!, doc.id);
      final box = Hive.box<CallModel>(callHistoryBoxName);
      await box.put(model.callId, model);
    } catch (error) {
      debugPrint('Failed to persist ended call $callId: $error');
    }
  }
}
