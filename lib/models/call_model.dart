class CallModel {
  final String callId;
  final String callerId;
  final String calleeId;
  final String status; // 'ringing', 'accepted', 'ended'
  final int timestamp;
  final bool isVideoCall;
  final Map<String, dynamic>? offer;
  final Map<String, dynamic>? answer;

  CallModel({
    required this.callId,
    required this.callerId,
    required this.calleeId,
    required this.status,
    required this.timestamp,
    this.isVideoCall = false,
    this.offer,
    this.answer,
  });

  Map<String, dynamic> toMap() {
    return {
      'callId': callId,
      'callerId': callerId,
      'calleeId': calleeId,
      'status': status,
      'timestamp': timestamp,
      'isVideoCall': isVideoCall,
      if (offer != null) 'offer': offer,
      if (answer != null) 'answer': answer,
    };
  }

  factory CallModel.fromMap(Map<String, dynamic> map, String id) {
    return CallModel(
      callId: id,
      callerId: map['callerId'] as String? ?? '',
      calleeId: map['calleeId'] as String? ?? '',
      status: map['status'] as String? ?? 'ringing',
      timestamp:
          map['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      isVideoCall: map['isVideoCall'] as bool? ?? false,
      offer: map['offer'] as Map<String, dynamic>?,
      answer: map['answer'] as Map<String, dynamic>?,
    );
  }

  CallModel copyWith({
    String? callId,
    String? callerId,
    String? calleeId,
    String? status,
    int? timestamp,
    bool? isVideoCall,
    Map<String, dynamic>? offer,
    Map<String, dynamic>? answer,
  }) {
    return CallModel(
      callId: callId ?? this.callId,
      callerId: callerId ?? this.callerId,
      calleeId: calleeId ?? this.calleeId,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      isVideoCall: isVideoCall ?? this.isVideoCall,
      offer: offer ?? this.offer,
      answer: answer ?? this.answer,
    );
  }
}
