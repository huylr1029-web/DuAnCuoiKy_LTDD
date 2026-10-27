
import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';
import '../models/app_user.dart';
import '../services/call_service.dart';
import '../services/chat_service.dart';
import '../widgets/avatar.dart';

class CallScreen extends StatefulWidget {
  final String callId;
  final AppUser peer;
  final bool isVideo;
  final bool isCaller;

  const CallScreen({
    super.key,
    required this.callId,
    required this.peer,
    required this.isVideo,
    required this.isCaller,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  RtcEngine? _engine;

  bool _joined = false;
  int? _remoteUid;
  bool _remoteVideoOff = false;

  bool _micOn = true;
  late bool _camOn = widget.isVideo;
  late bool _speakerOn = widget.isVideo;

  Timer? _durationTimer;
  Timer? _timeoutTimer;

  int _seconds = 0;
  bool _everConnected = false;

  StreamSubscription? _callSub;
  bool _closing = false;

  @override
  void initState() {
    super.initState();

    CallService.inCall = true;

    _callSub = CallService()
        .callStream(widget.callId)
        .listen((snap) {
      final status = snap.data()?['status'];

      if (status == 'accepted') {
        _timeoutTimer?.cancel();
      }

      if (status == 'rejected' ||
          status == 'ended' ||
          status == 'missed') {
        _hangUp(status, updateRemote: false);
      }
    });

    if (widget.isCaller) {
      _timeoutTimer = Timer(
        const Duration(seconds: 30),
            () {
          if (!_everConnected && !_closing) {
            _hangUp('missed');
          }
        },
      );
    }

    _startAgora();
  }

  Future<void> _startAgora() async {
    final perms = await [
      Permission.microphone,
      if (widget.isVideo) Permission.camera,
    ].request();

    if (perms.values.any((status) => !status.isGranted)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cần cấp quyền micro/camera để gọi',
            ),
          ),
        );
      }

      _hangUp('ended');
      return;
    }

    if (_closing || !mounted) return;

    try {
      final engine = createAgoraRtcEngine();
      _engine = engine;

      await engine.initialize(
        const RtcEngineContext(
          appId: agoraAppId,
          channelProfile:
          ChannelProfileType.channelProfileCommunication,
        ),
      );

      engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            if (mounted) {
              setState(() {
                _joined = true;
              });
            }
          },

          onUserJoined: (connection, remoteUid, elapsed) {
            if (!mounted) return;

            setState(() {
              _remoteUid = remoteUid;
            });

            _onConnected();
          },

          onUserOffline: (connection, remoteUid, reason) {
            _hangUp('ended');
          },

          onRemoteVideoStateChanged: (
              connection,
              remoteUid,
              state,
              reason,
              elapsed,
              ) {
            if (!mounted) return;

            setState(() {
              _remoteVideoOff =
                  state ==
                      RemoteVideoState
                          .remoteVideoStateStopped ||
                      reason ==
                          RemoteVideoStateReason
                              .remoteVideoStateReasonRemoteMuted;
            });
          },

          onError: (err, msg) {
            debugPrint('Agora error: $err $msg');
          },
        ),
      );

      if (widget.isVideo) {
        await engine.enableVideo();
        await engine.startPreview();
      } else {
        await engine.disableVideo();
      }

      await engine.setDefaultAudioRouteToSpeakerphone(
        _speakerOn,
      );

      if (_closing || !mounted) return;

      await engine.joinChannel(
        token: '',
        channelId: widget.callId,
        uid: 0,
        options: ChannelMediaOptions(
          clientRoleType:
          ClientRoleType.clientRoleBroadcaster,
          channelProfile:
          ChannelProfileType.channelProfileCommunication,
          publishMicrophoneTrack: true,
          publishCameraTrack: widget.isVideo,
          autoSubscribeAudio: true,
          autoSubscribeVideo: widget.isVideo,
        ),
      );
    } catch (e) {
      debugPrint('Lỗi khởi tạo Agora: $e');
      _hangUp('ended');
    }
  }

  void _onConnected() {
    if (_everConnected) return;

    _everConnected = true;
    _timeoutTimer?.cancel();

    _durationTimer = Timer.periodic(
      const Duration(seconds: 1),
          (_) {
        if (mounted) {
          setState(() {
            _seconds++;
          });
        }
      },
    );
  }

  Future<void> _hangUp(
      String reason, {
        bool updateRemote = true,
      }) async {
    if (_closing) return;

    _closing = true;

    _durationTimer?.cancel();
    _timeoutTimer?.cancel();

    await _callSub?.cancel();

    try {
      if (updateRemote) {
        await CallService().updateStatus(
          widget.callId,
          reason,
        );
      }

      if (widget.isCaller) {
        await ChatService().sendCallLog(
          widget.peer,
          isVideo: widget.isVideo,
          outcome: reason,
          seconds: _everConnected ? _seconds : null,
        );
      }
    } catch (e) {
      debugPrint('Lỗi khi kết thúc cuộc gọi: $e');
    }

    await _releaseEngine();

    CallService.inCall = false;

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _releaseEngine() async {
    final engine = _engine;
    _engine = null;

    if (engine == null) return;

    try {
      await engine.leaveChannel();
      await engine.release();
    } catch (e) {
      debugPrint('Lỗi giải phóng Agora: $e');
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _timeoutTimer?.cancel();

    _callSub?.cancel();

    if (!_closing) {
      _releaseEngine();
    }

    CallService.inCall = false;

    super.dispose();
  }

  void _toggleMic() {
    setState(() {
      _micOn = !_micOn;
    });

    _engine?.muteLocalAudioStream(!_micOn);
  }

  void _toggleCam() {
    setState(() {
      _camOn = !_camOn;
    });

    _engine?.muteLocalVideoStream(!_camOn);

    if (_camOn) {
      _engine?.startPreview();
    } else {
      _engine?.stopPreview();
    }
  }

  void _switchCamera() {
    _engine?.switchCamera();
  }

  void _toggleSpeaker() {
    setState(() {
      _speakerOn = !_speakerOn;
    });

    _engine?.setEnableSpeakerphone(_speakerOn);
  }

  String get _statusText {
    if (_everConnected) {
      final minutes =
      (_seconds ~/ 60).toString().padLeft(2, '0');

      final seconds =
      (_seconds % 60).toString().padLeft(2, '0');

      return '$minutes:$seconds';
    }

    return widget.isCaller
        ? 'Đang gọi...'
        : 'Đang kết nối...';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _hangUp('ended');
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: widget.isVideo
            ? _videoLayout()
            : _audioLayout(),
      ),
    );
  }

  Widget _localView() {
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: _engine!,
        canvas: const VideoCanvas(uid: 0),
      ),
    );
  }

  Widget _remoteView() {
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: _engine!,
        canvas: VideoCanvas(uid: _remoteUid),
        connection: RtcConnection(
          channelId: widget.callId,
        ),
      ),
    );
  }

  Widget _peerPlaceholder() {
    return Container(
      color: const Color(0xFF1C1E21),
      alignment: Alignment.center,
      child: Avatar(
        name: widget.peer.name,
        radius: 56,
      ),
    );
  }

  Widget _videoLayout() {
    final ready = _engine != null && _joined;
    final connected = _remoteUid != null;

    return Stack(
      children: [
        Positioned.fill(
          child: !ready
              ? _peerPlaceholder()
              : connected
              ? (_remoteVideoOff
              ? _peerPlaceholder()
              : _remoteView())
              : (_camOn
              ? _localView()
              : _peerPlaceholder()),
        ),

        if (ready && connected && _camOn)
          Positioned(
            top:
            MediaQuery.of(context).padding.top + 16,
            right: 16,
            width: 110,
            height: 160,
            child: ClipRRect(
              borderRadius:
              BorderRadius.circular(12),
              child: _localView(),
            ),
          ),

        Positioned(
          top:
          MediaQuery.of(context).padding.top + 16,
          left: 16,
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                widget.peer.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(blurRadius: 6),
                  ],
                ),
              ),
              Text(
                _statusText,
                style: const TextStyle(
                  color: Colors.white,
                  shadows: [
                    Shadow(blurRadius: 6),
                  ],
                ),
              ),
            ],
          ),
        ),

        Positioned(
          left: 0,
          right: 0,
          bottom: 40,
          child: _controls(),
        ),
      ],
    );
  }

  Widget _audioLayout() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1C1E21),
            Color(0xFF0B3D91),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 80),

            Avatar(
              name: widget.peer.name,
              radius: 60,
            ),

            const SizedBox(height: 20),

            Text(
              widget.peer.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              _statusText,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),

            const Spacer(),

            Padding(
              padding:
              const EdgeInsets.only(bottom: 40),
              child: _controls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    return Row(
      mainAxisAlignment:
      MainAxisAlignment.spaceEvenly,
      children: [
        if (widget.isVideo) ...[
          _roundButton(
            Icons.cameraswitch,
            _switchCamera,
          ),
          _roundButton(
            _camOn
                ? Icons.videocam
                : Icons.videocam_off,
            _toggleCam,
            active: !_camOn,
          ),
        ] else
          _roundButton(
            _speakerOn
                ? Icons.volume_up
                : Icons.volume_down,
            _toggleSpeaker,
            active: _speakerOn,
          ),

        _roundButton(
          _micOn ? Icons.mic : Icons.mic_off,
          _toggleMic,
          active: !_micOn,
        ),

        _roundButton(
          Icons.call_end,
              () => _hangUp('ended'),
          color: Colors.red,
          size: 34,
        ),
      ],
    );
  }

  Widget _roundButton(
      IconData icon,
      VoidCallback onTap, {
        bool active = false,
        Color? color,
        double size = 28,
      }) {
    return GestureDetector(
      onTap: onTap,
      child: CircleAvatar(
        radius: size,
        backgroundColor:
        color ??
            (active
                ? Colors.white
                : Colors.white24),
        child: Icon(
          icon,
          color: color != null
              ? Colors.white
              : (active
              ? Colors.black
              : Colors.white),
          size: size * 0.9,
        ),
      ),
    );
  }
}
