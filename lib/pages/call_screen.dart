import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:pay_go/services/webrtc_helper.dart';

class CallScreen extends StatefulWidget {
  final String callId;
  final String callerId;
  final String receiverId;
  final bool isInitiator;
  final String otherUserName;

  const CallScreen({
    super.key,
    required this.callId,
    required this.callerId,
    required this.receiverId,
    required this.isInitiator,
    required this.otherUserName,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late WebRTCHelper _webrtcHelper;
  bool _isAudioOn = true;
  bool _isVideoOn = true;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeWebRTC();
  }

  Future<void> _initializeWebRTC() async {
    _webrtcHelper = WebRTCHelper(
      callId: widget.callId,
      isVideoCall: true, // Assuming video call, adjust as needed
      isCaller: widget.isInitiator,
    );
    await _webrtcHelper.initialize();
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  void dispose() {
    if (_isInitialized) {
      _webrtcHelper.dispose();
    }
    super.dispose();
  }

  void _toggleAudio() {
    setState(() {
      _isAudioOn = !_isAudioOn;
      _webrtcHelper.toggleAudio();
    });
  }

  void _toggleVideo() {
    setState(() {
      _isVideoOn = !_isVideoOn;
      _webrtcHelper.toggleVideo();
    });
  }

  void _switchCamera() {
    _webrtcHelper.switchCamera();
  }

  Future<void> _endCall() async {
    if (_isInitialized) {
      await _webrtcHelper.endCall();
    }
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: (_webrtcHelper.remoteRenderer.srcObject != null)
                ? RTCVideoView(
                    _webrtcHelper.remoteRenderer,
                    objectFit:
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          Positioned(
            top: 60,
            left: 20,
            right: 20,
            child: Text(
              widget.otherUserName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                shadows: <Shadow>[
                  Shadow(
                    offset: Offset(1.0, 1.0),
                    blurRadius: 3.0,
                    color: Color.fromARGB(150, 0, 0, 0),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (_webrtcHelper.localRenderer.srcObject != null)
            Positioned(
              top: 40,
              right: 20,
              child: SizedBox(
                width: 100,
                height: 150,
                child: RTCVideoView(
                  _webrtcHelper.localRenderer,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                ),
              ),
            ),
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: Icon(_isAudioOn ? Icons.mic : Icons.mic_off),
                  onPressed: _toggleAudio,
                ),
                IconButton(
                  icon: Icon(_isVideoOn ? Icons.videocam : Icons.videocam_off),
                  onPressed: _toggleVideo,
                ),
                IconButton(
                  icon: const Icon(Icons.switch_camera),
                  onPressed: _switchCamera,
                ),
                IconButton(
                  icon: const Icon(Icons.call_end, color: Colors.red),
                  onPressed: _endCall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
