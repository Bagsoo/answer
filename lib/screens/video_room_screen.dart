import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/voice_call_service.dart';

class VideoRoomScreen extends StatefulWidget {
  final String roomId;
  final String roomName;
  final String callId;
  final String token;
  final String appId;
  final String channelName;
  final int agoraUid;

  const VideoRoomScreen({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.callId,
    required this.token,
    required this.appId,
    required this.channelName,
    required this.agoraUid,
  });

  @override
  State<VideoRoomScreen> createState() => _VideoRoomScreenState();
}

class _VideoRoomScreenState extends State<VideoRoomScreen> with WidgetsBindingObserver {
  late RtcEngine _engine;
  bool _localUserJoined = false;
  bool _isMuted = false;
  bool _isVideoEnabled = true;
  bool _isFrontCamera = true;
  List<int> _remoteUids = [];
  Map<int, bool> _remoteVideoStates = {};
  Map<int, String> _uidToName = {};

  StreamSubscription? _participantsSub;
  Timer? _heartbeatTimer;

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAgora();
    _setupParticipantsListener();
    _startHeartbeat();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _participantsSub?.cancel();
    _leaveChannel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_isVideoEnabled) {
        _toggleVideo(forceOff: true);
      }
    }
  }

  Future<void> _initAgora() async {
    await [Permission.microphone, Permission.camera].request();

    _engine = createAgoraRtcEngine();
    await _engine.initialize(RtcEngineContext(
      appId: widget.appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    _engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          if (!mounted) return;
          setState(() => _localUserJoined = true);
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          if (!mounted) return;
          setState(() {
            _remoteUids.add(remoteUid);
            _updateVideoQuality();
          });
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          if (!mounted) return;
          setState(() {
            _remoteUids.remove(remoteUid);
            _remoteVideoStates.remove(remoteUid);
            _updateVideoQuality();
          });
        },
        onRemoteVideoStateChanged: (RtcConnection connection, int remoteUid, RemoteVideoState state, RemoteVideoStateReason reason, int elapsed) {
          if (!mounted) return;
          setState(() {
            _remoteVideoStates[remoteUid] = (state == RemoteVideoState.remoteVideoStateDecoding);
          });
        },
        onNetworkQuality: (RtcConnection connection, int remoteUid, QualityType txQuality, QualityType rxQuality) {
          // 6. 네트워크 품질 대응 (0은 로컬 사용자)
          if (remoteUid == 0 && txQuality.index >= QualityType.qualityPoor.index) {
            _showNetworkWarning();
          }
        },
      ),
    );

    await _engine.enableVideo();
    await _updateVideoQuality();

    await _engine.joinChannel(
      token: widget.token,
      channelId: widget.channelName,
      uid: widget.agoraUid,
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        publishCameraTrack: true,
        publishMicrophoneTrack: true,
      ),
    );
  }

  Future<void> _updateVideoQuality() async {
    int totalCount = _remoteUids.length + 1;
    VideoEncoderConfiguration config;

    if (totalCount <= 2) {
      config = const VideoEncoderConfiguration(
        dimensions: VideoDimensions(width: 720, height: 1280),
        frameRate: 30,
        bitrate: 1500,
      );
    } else {
      config = const VideoEncoderConfiguration(
        dimensions: VideoDimensions(width: 360, height: 640),
        frameRate: 15,
        bitrate: 600,
      );
    }
    await _engine.setVideoEncoderConfiguration(config);
  }

  void _showNetworkWarning() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).networkUnstable),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _setupParticipantsListener() {
    _participantsSub = FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(widget.roomId)
        .collection('calls')
        .doc(widget.callId)
        .collection('participants')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final newUidToName = <int, String>{};

      for (var doc in snap.docs) {
        final data = doc.data();
        final uidStr = data['uid'] as String? ?? '';
        if (uidStr.isEmpty) continue;
        
        // Agora UID 매핑 로직 (단순화: 실제로는 서버와 맞춰야 함)
        // 여기서는 임시로 전달받은 agoraUid를 기준으로 처리하거나 로직 보강 필요
      }

      setState(() {
        _uidToName = newUidToName;
      });
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      context.read<VoiceCallService>().updateHeartbeat(
        roomId: widget.roomId,
        callId: widget.callId,
        uid: _currentUid,
      );
    });
  }

  Future<void> _leaveChannel() async {
    await _engine.leaveChannel();
    await _engine.release();
    if (mounted) {
      context.read<VoiceCallService>().leaveVoiceCall(
        roomId: widget.roomId,
        callId: widget.callId,
      );
    }
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _engine.muteLocalAudioStream(_isMuted);
    context.read<VoiceCallService>().setMuted(
      roomId: widget.roomId,
      callId: widget.callId,
      uid: _currentUid,
      isMuted: _isMuted,
    );
  }

  void _toggleVideo({bool forceOff = false}) {
    if (!mounted) return;
    setState(() {
      _isVideoEnabled = forceOff ? false : !_isVideoEnabled;
    });
    _engine.enableLocalVideo(_isVideoEnabled);
    FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(widget.roomId)
        .collection('calls')
        .doc(widget.callId)
        .collection('participants')
        .doc(_currentUid)
        .update({'is_video_enabled': _isVideoEnabled});
  }

  void _flipCamera() {
    _engine.switchCamera();
    setState(() => _isFrontCamera = !_isFrontCamera);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildVideoLayout(),
          _buildTopBar(l),
          _buildBottomControls(l),
        ],
      ),
    );
  }

  Widget _buildVideoLayout() {
    if (!_localUserJoined) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    final allViews = <Widget>[
      _buildLocalVideo(),
      ..._remoteUids.map((uid) => _buildRemoteVideo(uid)),
    ];

    if (allViews.length == 1) return allViews[0];
    if (allViews.length == 2) {
      return Column(children: [
        Expanded(child: allViews[0]),
        Expanded(child: allViews[1]),
      ]);
    }
    
    return GridView.count(
      crossAxisCount: 2,
      children: allViews.map((v) => Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.black54, width: 0.5)),
        child: v,
      )).toList(),
    );
  }

  Widget _buildLocalVideo() {
    return Stack(
      children: [
        if (_isVideoEnabled)
          AgoraVideoView(
            controller: VideoViewController(
              rtcEngine: _engine,
              canvas: const VideoCanvas(uid: 0),
            ),
          )
        else
          _buildPlaceholder(null),
        _buildInfoOverlay("Me"),
      ],
    );
  }

  Widget _buildRemoteVideo(int uid) {
    bool isVideoOn = _remoteVideoStates[uid] ?? true;
    return Stack(
      children: [
        if (isVideoOn)
          AgoraVideoView(
            controller: VideoViewController.remote(
              rtcEngine: _engine,
              canvas: VideoCanvas(uid: uid),
              connection: RtcConnection(channelId: widget.channelName),
            ),
          )
        else
          _buildPlaceholder(uid),
        _buildInfoOverlay(_uidToName[uid] ?? "User"),
      ],
    );
  }

  Widget _buildPlaceholder(int? uid) {
    return Container(
      color: Colors.grey[900],
      child: Center(
        child: CircleAvatar(
          radius: 40,
          backgroundColor: Colors.grey[800],
          child: const Icon(Icons.person, size: 40, color: Colors.white54),
        ),
      ),
    );
  }

  Widget _buildInfoOverlay(String label) {
    return Positioned(
      bottom: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ),
    );
  }

  Widget _buildTopBar(AppLocalizations l) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 30),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              widget.roomName,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildBottomControls(AppLocalizations l) {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 20,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _controlButton(
            icon: _isMuted ? Icons.mic_off : Icons.mic,
            color: _isMuted ? Colors.red : Colors.white24,
            onPressed: _toggleMute,
          ),
          _controlButton(
            icon: _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
            color: _isVideoEnabled ? Colors.white24 : Colors.red,
            onPressed: () => _toggleVideo(),
          ),
          _controlButton(
            icon: Icons.flip_camera_ios,
            color: Colors.white24,
            onPressed: _flipCamera,
          ),
          _controlButton(
            icon: Icons.call_end,
            color: Colors.red,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _controlButton({required IconData icon, required Color color, required VoidCallback onPressed}) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }
}
