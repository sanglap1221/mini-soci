import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:async/async.dart';
import 'package:uuid/uuid.dart';
import '../models/call_model.dart';

class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  /// Create a new call document in Firestore
  Future<String> createCall({
    required String callerId,
    required String calleeId,
    required bool isVideoCall,
  }) async {
    final callId = _uuid.v4();

    await _firestore.collection('calls').doc(callId).set({
      'callId': callId,
      'callerId': callerId,
      'calleeId': calleeId,
      'status': 'ringing',
      'isVideoCall': isVideoCall,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'participants': [callerId, calleeId],
      'offer': null,
      'answer': null,
      'callerCandidates': [],
      'calleeCandidates': [],
    });

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

  /// Accept the call
  Future<void> acceptCall(String callId) {
    return _firestore.collection('calls').doc(callId).update({
      'status': 'accepted',
    });
  }

  /// End the call
  Future<void> endCall(String callId) async {
    await _firestore.collection('calls').doc(callId).update({
      'status': 'ended',
    });

    // Delete the call document after a delay
    Future.delayed(const Duration(seconds: 5), () {
      _firestore.collection('calls').doc(callId).delete();
    });
  }

  /// Reject the call
  Future<void> rejectCall(String callId) async {
    await _firestore.collection('calls').doc(callId).update({
      'status': 'rejected',
    });

    // Delete the call document after a delay
    Future.delayed(const Duration(seconds: 2), () {
      _firestore.collection('calls').doc(callId).delete();
    });
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
    return CallModel.fromMap(doc.data()!, doc.id);
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
              .map((doc) => CallModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  /// Listen to the call history for a user.
  /// Fetches calls where the user was either the caller or the callee.
  /// This now uses a single, more efficient query.
  Stream<List<CallModel>> getCallHistory(String userId) {
    return _firestore
        .collection('calls')
        .where('participants', arrayContains: userId)
        .where('status', whereIn: ['ended', 'rejected', 'cancelled'])
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => CallModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  /// Deletes all call history for a given user.
  Future<void> clearCallHistory(String userId) async {
    final WriteBatch batch = _firestore.batch();

    // Query for calls where the user was the caller
    final callerQuery = _firestore
        .collection('calls')
        .where('callerId', isEqualTo: userId);

    // Query for calls where the user was the callee
    final calleeQuery = _firestore
        .collection('calls')
        .where('calleeId', isEqualTo: userId);

    final callerSnapshot = await callerQuery.get();
    for (final doc in callerSnapshot.docs) {
      batch.delete(doc.reference);
    }

    final calleeSnapshot = await calleeQuery.get();
    for (final doc in calleeSnapshot.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
  }
}
