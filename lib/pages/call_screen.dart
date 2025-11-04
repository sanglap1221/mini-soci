import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:pay_go/services/webrtc_helper.dart';
import 'package:pay_go/services/api_service.dart';
import 'package:pay_go/services/call_service.dart';

class CallScreen extends StatefulWidget {
  final String callId;
  final String callerId;
  final String receiverId;
  final bool isInitiator;
  final bool isVideoCall;
  final String otherUserName;
  final String? otherUserAvatarUrl;

  const CallScreen({
    super.key,
    required this.callId,
    required this.callerId,
    required this.receiverId,
    required this.isInitiator,
    required this.isVideoCall,
    required this.otherUserName,
    this.otherUserAvatarUrl,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  StreamSubscription<DocumentSnapshot>? _callDocSub;
  late WebRTCHelper _webrtcHelper;
  final CallService _callService = CallService();
  bool _isAudioOn = true;
  bool _isVideoOn = true;
  bool _isSpeakerOn = false;
  bool _isOnHold = false;
  bool _isInitialized = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isClosing = false; // Flag to prevent multiple pops
  final ApiService _apiService = ApiService();
  Timer? _callTimer;
  Stopwatch? _callStopwatch;
  Duration _callDuration = Duration.zero;
  String _callStatus = 'Connecting...';
  bool _hasStartedTimer = false;
  bool _hasClosedRemote = false;

  @override
  void initState() {
    super.initState();
    _listenToCallStatus();
    _initializeWebRTC();

    // Start ringing sound if this user is the one making the call
    if (widget.isInitiator) {
      _startRingingSound();
      _callStatus = 'Ringing...';
    }
  }

  void _listenToCallStatus() {
    _callDocSub = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callId)
        .snapshots()
        .listen((snapshot) async {
          if (!snapshot.exists) {
            await _handleRemoteHangup('Call ended');
            return;
          }

          final data = snapshot.data();
          if (data == null) {
            return;
          }

          final status = data['status'] as String?;
          if (status == null) {
            return;
          }

          if (status != 'ringing') {
            _callService.cancelRingingTimeout(widget.callId);
          }

          switch (status) {
            case 'accepted':
              _stopRingingSound();
              break;
            case 'cancelled':
              await _handleRemoteHangup('Call was cancelled');
              break;
            case 'rejected':
              await _handleRemoteHangup('Call was rejected');
              break;
            case 'ended':
              await _handleRemoteHangup('Call ended');
              break;
          }
        });
  }

  Future<void> _handleRemoteHangup(String message) async {
    if (_hasClosedRemote) {
      return;
    }
    _hasClosedRemote = true;
    _callDocSub?.cancel();
    _callService.cancelRingingTimeout(widget.callId);
    _stopRingingSound();
    _callTimer?.cancel();
    _callStopwatch?.stop();
    _hasStartedTimer = false;

    if (_isInitialized) {
      try {
        await _webrtcHelper.dispose();
      } catch (error) {
        debugPrint('CallScreen: dispose failed after remote hangup: $error');
      }
    }

    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));

    final navigator = Navigator.of(context);
    if (navigator.mounted) {
      final didPop = await navigator.maybePop();
      if (didPop) {
        return;
      }
    }

    final rootNavigator = Navigator.of(context, rootNavigator: true);
    if (rootNavigator.mounted) {
      await rootNavigator.maybePop();
    }
  }

  @override
  void dispose() {
    _callDocSub?.cancel();
    _callTimer?.cancel();
    _callStopwatch?.stop();
    _hasStartedTimer = false;
    _hasClosedRemote = false;
    _webrtcHelper.dispose();
    super.dispose();
  }

  Future<void> _initializeWebRTC() async {
    _hasClosedRemote = false;
    _webrtcHelper = WebRTCHelper(
      callId: widget.callId,
      isVideoCall: widget.isVideoCall,
      isCaller: widget.isInitiator,
      onCallStateChanged: (state) {
        if (mounted) {
          setState(() {
            _callStatus = state;
          });
          if (state == 'Connected' && !_hasStartedTimer) {
            _stopRingingSound();
            _startCallTimer();
          }
        }
      },
      onCallEnded: () {
        if (!mounted || _isClosing) {
          return;
        }
        if (mounted) {
          _endCall(showSnackbar: true);
        }
      },
    );
    try {
      await _webrtcHelper.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        // Route audio based on call type:
        // - Video calls: enable speakerphone by default
        // - Audio calls: keep speakerphone off by default (earpiece)
        if (widget.isVideoCall) {
          await _webrtcHelper.setSpeakerphoneOn(true);
          if (mounted) {
            setState(() {
              _isSpeakerOn = true;
            });
          }
        } else {
          await _webrtcHelper.setSpeakerphoneOn(false);
          if (mounted) {
            setState(() {
              _isSpeakerOn = false;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('WebRTC initialization failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize call: $e')),
        );
        Navigator.of(context).pop();
      }
      return;
    }
  }

  void _toggleAudio() {
    setState(() {
      if (!_isOnHold) {
        _isAudioOn = !_isAudioOn;
        _webrtcHelper.toggleAudio();
      }
    });
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
      _webrtcHelper.setSpeakerphoneOn(_isSpeakerOn);
    });
  }

  void _toggleHold() {
    setState(() {
      _isOnHold = !_isOnHold;
      _webrtcHelper.setHold(_isOnHold);
      // When going on hold, mute the mic. When coming off hold, restore mic state.
      _isAudioOn = !_isOnHold;
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

  Future<void> _endCall({bool showSnackbar = false}) async {
    if (_isClosing) return; // Prevent re-entry
    _isClosing = true;
    _hasClosedRemote = true;
    final navigator = Navigator.of(context);
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    _callDocSub?.cancel();
    _callService.cancelRingingTimeout(widget.callId);

    if (_isInitialized) {
      _stopRingingSound();
      final actorId = widget.isInitiator ? widget.callerId : widget.receiverId;
      try {
        await _webrtcHelper.endCall(actorId: actorId);
      } catch (error) {
        debugPrint('CallScreen: failed to end call cleanly: $error');
      }
    }
    _callTimer?.cancel();
    _callStopwatch?.stop();
    _hasStartedTimer = false;
    if (mounted) {
      if (showSnackbar) {
        messenger?.showSnackBar(const SnackBar(content: Text('Call ended')));
      }
      if (navigator.mounted) {
        final didPop = await navigator.maybePop();
        if (didPop) {
          return;
        }
      }
      if (rootNavigator != navigator && rootNavigator.mounted) {
        await rootNavigator.maybePop();
      }
    }
  }

  void _startCallTimer() {
    _hasStartedTimer = true;
    _callTimer?.cancel();
    _callStopwatch?.stop();
    _callDuration = Duration.zero;
    _callStopwatch = Stopwatch()..start();
    _callTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        _callStopwatch?.stop();
        return;
      }
      setState(() {
        _callDuration = _callStopwatch?.elapsed ?? Duration.zero;
      });
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return duration.inHours > 0
        ? '$hours:$minutes:$seconds'
        : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: Colors.blueGrey.shade900,
      body: Stack(
        children: [
          // Background View
          _buildBackgroundView(),

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
          // Call Status / Timer
          Positioned(
            top: 100,
            left: 20,
            right: 20,
            child: Center(
              child: Text(
                _callDuration > Duration.zero
                    ? _formatDuration(_callDuration)
                    : _callStatus,
                style: const TextStyle(color: Colors.white70, fontSize: 18),
              ),
            ),
          ),
          if (widget.isVideoCall &&
              _webrtcHelper.localRenderer.srcObject != null)
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
                // Speaker Button
                IconButton(
                  icon: Icon(
                    _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                  ),
                  onPressed: _toggleSpeaker,
                ),
                // Mute/Unmute Button
                IconButton(
                  icon: Icon(
                    _isOnHold || !_isAudioOn ? Icons.mic_off : Icons.mic,
                  ),
                  onPressed: _toggleAudio,
                ),
                // Hold Button
                IconButton(
                  icon: Icon(_isOnHold ? Icons.play_arrow : Icons.pause),
                  onPressed: _toggleHold,
                ),
                if (widget.isVideoCall)
                  IconButton(
                    icon: Icon(
                      _isVideoOn ? Icons.videocam : Icons.videocam_off,
                    ),
                    onPressed: _toggleVideo,
                  ),
                if (widget.isVideoCall)
                  IconButton(
                    icon: const Icon(Icons.switch_camera),
                    onPressed: _switchCamera,
                  ),
                IconButton(
                  icon: const Icon(Icons.call_end, color: Colors.red),
                  onPressed: () => _endCall(showSnackbar: false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundView() {
    if (widget.isVideoCall) {
      // For video calls, show the remote video stream
      return Positioned.fill(
        child: (_webrtcHelper.remoteRenderer.srcObject != null)
            ? RTCVideoView(
                _webrtcHelper.remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            : const Center(child: CircularProgressIndicator()),
      );
    } else {
      // For audio calls, show the user's avatar
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 80,
              backgroundColor: Colors.white24,
              child: ClipOval(
                child: widget.otherUserAvatarUrl != null
                    ? CachedNetworkImage(
                        imageUrl: _apiService.getFullImageUrl(
                          widget.otherUserAvatarUrl!,
                        ),
                        fit: BoxFit.cover,
                        width: 160,
                        height: 160,
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                        errorWidget: (context, url, error) =>
                            _buildFallbackAvatar(),
                      )
                    : _buildFallbackAvatar(),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
    }
  }

  Widget _buildFallbackAvatar() {
    return Container(
      width: 160,
      height: 160,
      alignment: Alignment.center,
      child: Text(
        widget.otherUserName.isNotEmpty
            ? widget.otherUserName[0].toUpperCase()
            : 'U',
        style: const TextStyle(
          fontSize: 80,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _stopRingingSound() {
    _audioPlayer.stop();
  }

  void _startRingingSound() async {
    // This sound is for the person making the call
    if (widget.isInitiator) {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(AssetSource('sounds/calling.mp3'));
    }
  }
}
