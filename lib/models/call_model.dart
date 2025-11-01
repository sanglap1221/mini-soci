import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

part 'call_model.g.dart';

@HiveType(typeId: 1)
class CallModel {
  CallModel({
    required this.callId,
    required this.callerId,
    required this.calleeId,
    required this.status,
    required this.timestamp,
    required this.isVideoCall,
    required this.participants,
    this.offer,
    this.answer,
    this.callerCandidates,
    this.calleeCandidates,
    this.endedAt,
    this.endReason,
    Duration? duration,
    int? durationSeconds,
  }) : durationSeconds = durationSeconds ?? duration?.inSeconds;

  @HiveField(0)
  final String callId;
  @HiveField(1)
  final String callerId;
  @HiveField(2)
  final String calleeId;
  @HiveField(3)
  final String status;
  @HiveField(4)
  final DateTime timestamp;
  @HiveField(5)
  final bool isVideoCall;
  @HiveField(6)
  final List<String> participants;
  @HiveField(7)
  final Map<String, dynamic>? offer;
  @HiveField(8)
  final Map<String, dynamic>? answer;
  @HiveField(9)
  final List<dynamic>? callerCandidates;
  @HiveField(10)
  final List<dynamic>? calleeCandidates;
  @HiveField(11)
  final DateTime? endedAt;
  @HiveField(12)
  final String? endReason;
  @HiveField(13)
  final int? durationSeconds;

  Duration? get duration =>
      durationSeconds != null ? Duration(seconds: durationSeconds!) : null;

  factory CallModel.fromFirestore(Map<String, dynamic> data, String id) {
    return CallModel(
      callId: id,
      callerId: data['callerId'] as String? ?? '',
      calleeId: data['calleeId'] as String? ?? '',
      status: data['status'] as String? ?? 'ringing',
      timestamp: _decodeDateTime(data['timestamp']),
      isVideoCall: (data['isVideoCall'] as bool?) ?? false,
      participants: _decodeParticipants(data['participants']),
      offer: _decodeMap(data['offer']),
      answer: _decodeMap(data['answer']),
      callerCandidates: _decodeList(data['callerCandidates']),
      calleeCandidates: _decodeList(data['calleeCandidates']),
      endedAt: _decodeNullableDateTime(data['endedAt']),
      endReason: data['endReason'] as String?,
      duration: _decodeDuration(
        data['duration'],
        startedAt: _decodeDateTime(data['timestamp']),
        endedAt: _decodeNullableDateTime(data['endedAt']),
      ),
    );
  }

  CallModel copyWith({
    String? callId,
    String? callerId,
    String? calleeId,
    String? status,
    DateTime? timestamp,
    bool? isVideoCall,
    List<String>? participants,
    Map<String, dynamic>? offer,
    Map<String, dynamic>? answer,
    List<dynamic>? callerCandidates,
    List<dynamic>? calleeCandidates,
    DateTime? endedAt,
    String? endReason,
    Duration? duration,
    int? durationSeconds,
  }) {
    final int? resolvedDurationSeconds;
    if (durationSeconds != null) {
      resolvedDurationSeconds = durationSeconds;
    } else if (duration != null) {
      resolvedDurationSeconds = duration.inSeconds;
    } else {
      resolvedDurationSeconds = this.durationSeconds;
    }
    return CallModel(
      callId: callId ?? this.callId,
      callerId: callerId ?? this.callerId,
      calleeId: calleeId ?? this.calleeId,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      isVideoCall: isVideoCall ?? this.isVideoCall,
      participants: participants ?? this.participants,
      offer: offer ?? this.offer,
      answer: answer ?? this.answer,
      callerCandidates: callerCandidates ?? this.callerCandidates,
      calleeCandidates: calleeCandidates ?? this.calleeCandidates,
      endedAt: endedAt ?? this.endedAt,
      endReason: endReason ?? this.endReason,
      durationSeconds: resolvedDurationSeconds,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'callId': callId,
      'callerId': callerId,
      'calleeId': calleeId,
      'status': status,
      'timestamp': Timestamp.fromDate(timestamp),
      'isVideoCall': isVideoCall,
      'participants': participants,
      'offer': offer ?? <String, dynamic>{},
      'answer': answer ?? <String, dynamic>{},
      'callerCandidates': callerCandidates ?? <dynamic>[],
      'calleeCandidates': calleeCandidates ?? <dynamic>[],
      'endedAt': endedAt != null ? Timestamp.fromDate(endedAt!) : null,
      'endReason': endReason,
      if (durationSeconds != null) 'duration': durationSeconds,
    };
  }

  static DateTime _decodeDateTime(dynamic raw) {
    if (raw is Timestamp) {
      return raw.toDate();
    }
    if (raw is DateTime) {
      return raw;
    }
    if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    }
    return DateTime.now();
  }

  static Duration? _decodeDuration(
    dynamic raw, {
    required DateTime startedAt,
    DateTime? endedAt,
  }) {
    if (raw is Duration) {
      return raw;
    }
    if (raw is num) {
      return Duration(seconds: raw.toInt());
    }
    if (endedAt != null) {
      final diff = endedAt.difference(startedAt);
      return diff.isNegative ? null : diff;
    }
    return null;
  }

  static DateTime? _decodeNullableDateTime(dynamic raw) {
    if (raw == null) {
      return null;
    }
    return _decodeDateTime(raw);
  }

  static Map<String, dynamic>? _decodeMap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw.cast<String, dynamic>());
    }
    return null;
  }

  static List<String> _decodeParticipants(dynamic raw) {
    if (raw is Iterable) {
      return raw.map((entry) => entry.toString()).toList(growable: false);
    }
    return const <String>[];
  }

  static List<dynamic>? _decodeList(dynamic raw) {
    if (raw is Iterable) {
      return List<dynamic>.from(raw);
    }
    return null;
  }
}

// HiveAdapter is now generated via build_runner (call_model.g.dart).
