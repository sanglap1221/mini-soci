import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'call_service.dart';

class WebRTCHelper {
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  final String callId;
  final bool isVideoCall;
  final bool isCaller;
  final Function(String)? onCallStateChanged;
  final VoidCallback? onCallEnded;
  final CallService _callService = CallService();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  bool _isDisposed = false;
  final Set<String> _processedCandidates = {};
  StreamSubscription<DocumentSnapshot>? _callSignalSubscription;

  WebRTCHelper({
    required this.callId,
    required this.isVideoCall,
    required this.isCaller,
    this.onCallStateChanged,
    this.onCallEnded,
  });

  Future<void> initialize() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    await start(isVideoCall: isVideoCall);
    onCallStateChanged?.call(isCaller ? 'Calling...' : 'Ringing...');
  }

  Future<void> endCall() async {
    await _callService.endCall(callId);
    await dispose();
    onCallEnded?.call();
  }

  Future<void> start({bool isVideoCall = true}) async {
    // Get user media (audio/video)
    await _getUserMedia(isVideoCall);

    // Create peer connection
    await _createPeerConnection();

    // Listen to call document for signaling
    _listenToCallSignals();

    // If caller, create offer
    if (isCaller) {
      await _createOffer();
    }
  }

  Future<void> _getUserMedia(bool isVideoCall) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': isVideoCall
          ? {
              'facingMode': 'user',
              'width': {'ideal': 640, 'max': 640},
              'height': {'ideal': 480, 'max': 480},
              'frameRate': {'ideal': 30, 'max': 30},
            }
          : false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    localRenderer.srcObject = _localStream;
  }

  Future<void> _createPeerConnection() async {
    // ICE servers configuration (using Google's STUN server)
    final Map<String, dynamic> configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
    };

    final Map<String, dynamic> offerSdpConstraints = {
      'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true},
      'optional': [],
    };

    _peerConnection = await createPeerConnection(
      configuration,
      offerSdpConstraints,
    );

    // Add local stream tracks to peer connection
    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    // Listen for remote stream
    _peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams[0];
      }
    };

    // Handle ICE candidates
    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      if (isCaller) {
        _callService.addCallerCandidate(callId, candidate.toMap());
      } else {
        _callService.addCalleeCandidate(callId, candidate.toMap());
      }
    };

    // Handle connection state changes
    _peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      print('Connection state: $state');
    };
  }

  Future<void> _createOffer() async {
    RTCSessionDescription description = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(description);

    await _callService.setOffer(callId, description.toMap());
  }

  Future<void> _createAnswer() async {
    RTCSessionDescription description = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(description);

    await _callService.setAnswer(callId, description.toMap());
  }

  void _listenToCallSignals() {
    _callSignalSubscription = FirebaseFirestore.instance
        .collection('calls')
        .doc(callId)
        .snapshots()
        .listen((snapshot) {
          if (!snapshot.exists) {
            onCallEnded?.call();
            return;
          }

          final data = snapshot.data()!;

          // Check call status
          final status = data['status'] as String?;
          if (status == 'ended' || status == 'rejected') {
            onCallEnded?.call();
            return;
          } else if (status == 'accepted') {
            onCallStateChanged?.call(
              'Connected',
            ); // This will now trigger the timer
          }

          // Handle offer (for callee)
          if (!isCaller && data['offer'] != null) {
            final offer = data['offer'] as Map<String, dynamic>;
            _handleOffer(offer);
          }

          // Handle answer (for caller)
          if (isCaller && data['answer'] != null) {
            final answer = data['answer'] as Map<String, dynamic>;
            _handleAnswer(answer);
          }

          // Handle ICE candidates
          if (isCaller) {
            final candidates = data['calleeCandidates'] as List<dynamic>? ?? [];
            for (var candidate in candidates) {
              _addIceCandidate(candidate as Map<String, dynamic>);
            }
          } else {
            final candidates = data['callerCandidates'] as List<dynamic>? ?? [];
            for (var candidate in candidates) {
              _addIceCandidate(candidate as Map<String, dynamic>);
            }
          }
        });
  }

  Future<void> _handleOffer(Map<String, dynamic> offerMap) async {
    if (_isDisposed || _peerConnection == null) return;

    RTCSessionDescription offer = RTCSessionDescription(
      offerMap['sdp'],
      offerMap['type'],
    );
    await _peerConnection!.setRemoteDescription(offer);

    // Only create answer if the signaling state is correct
    if (_peerConnection!.signalingState ==
        RTCSignalingState.RTCSignalingStateHaveRemoteOffer) {
      await _createAnswer();
      await _callService.acceptCall(callId);
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> answerMap) async {
    if (_isDisposed || _peerConnection == null) return;

    RTCSessionDescription answer = RTCSessionDescription(
      answerMap['sdp'],
      answerMap['type'],
    );
    await _peerConnection!.setRemoteDescription(answer);
  }

  Future<void> _addIceCandidate(Map<String, dynamic> candidateMap) async {
    // Skip if disposed or peer connection is null
    if (_isDisposed || _peerConnection == null) return;

    // Create unique key for this candidate to avoid duplicates
    final candidateKey =
        '${candidateMap['candidate']}_${candidateMap['sdpMLineIndex']}';
    if (_processedCandidates.contains(candidateKey)) return;

    try {
      RTCIceCandidate candidate = RTCIceCandidate(
        candidateMap['candidate'],
        candidateMap['sdpMid'],
        candidateMap['sdpMLineIndex'],
      );
      await _peerConnection!.addCandidate(candidate);
      _processedCandidates.add(candidateKey);
    } catch (e) {
      print('Error adding ICE candidate: $e');
    }
  }

  Future<void> dispose() async {
    _isDisposed = true;
    await _callSignalSubscription?.cancel();
    await localRenderer.dispose();
    await remoteRenderer.dispose();
    _localStream?.getTracks().forEach((track) {
      track.stop();
    });
    _localStream?.dispose();
    await _peerConnection?.close();
    _peerConnection?.dispose();
    _peerConnection = null;
    _localStream = null;
  }

  void toggleAudio() {
    if (_localStream != null) {
      final audioTrack = _localStream!.getAudioTracks().first;
      audioTrack.enabled = !audioTrack.enabled;
    }
  }

  void toggleVideo() {
    if (_localStream != null) {
      final videoTrack = _localStream!.getVideoTracks().first;
      videoTrack.enabled = !videoTrack.enabled;
    }
  }

  void switchCamera() {
    if (_localStream != null) {
      Helper.switchCamera(_localStream!.getVideoTracks().first);
    }
  }

  Future<void> setSpeakerphoneOn(bool enabled) async {
    if (_localStream != null) {
      // The Helper class from flutter_webrtc can control the speakerphone.
      await Helper.setSpeakerphoneOn(enabled);
    }
  }

  void setHold(bool hold) {
    if (_localStream != null) {
      // We can implement "hold" by disabling the audio track from being sent.
      final audioTracks = _localStream!.getAudioTracks();
      for (var track in audioTracks) {
        track.enabled = !hold;
      }
    }
  }
}
