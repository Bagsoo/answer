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

class _VideoRoomScreenState extends State<VideoRoomScreen> {
  late RtcEngine _engine;
  bool _localUserJoined = false;
  List<int> _remoteUids = []; // 참여 중인 원격 사용자 ID 목록
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isFrontCamera = true;
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    _initAgora();
    _startHeartbeat();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _leaveChannel();
    super.dispose();
  }

  Future<void> _initAgora() async {
    // 권한 요청
    await [Permission.microphone, Permission.camera].request();

    // 엔진 생성
    _engine = createAgoraRtcEngine();
    await _engine.initialize(RtcEngineContext(
      appId: widget.appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    _engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          debugPrint("Local user joined: ${connection.localUid}");
          if (mounted) {
            setState(() => _localUserJoined = true);
          }
          _updateFirestoreStatus(joined: true);
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          debugPrint("Remote user joined: $remoteUid");
          if (mounted) {
            setState(() {
              if (!_remoteUids.contains(remoteUid)) {
                _remoteUids.add(remoteUid);
              }
            });
          }
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          debugPrint("Remote user offline: $remoteUid");
          if (mounted) {
            setState(() {
              _remoteUids.remove(remoteUid);
            });
          }
        },
        onLeaveChannel: (RtcConnection connection, RtcStats stats) {
          debugPrint("Local user left channel");
          if (mounted) {
            setState(() {
              _localUserJoined = false;
              _remoteUids.clear();
            });
          }
        },
      ),
    );

    await _engine.enableVideo();
    await _engine.startPreview();

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

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _updateFirestoreStatus();
    });
  }

  Future<void> _updateFirestoreStatus({bool joined = false}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final batch = FirebaseFirestore.instance.batch();
    final callRef = FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(widget.roomId)
        .collection('calls')
        .doc(widget.callId);

    final participantRef = callRef.collection('participants').doc(uid);

    if (joined) {
      batch.set(participantRef, {
        'joined_at': FieldValue.serverTimestamp(),
        'last_heartbeat': FieldValue.serverTimestamp(),
        'left_at': null,
        'agora_uid': widget.agoraUid,
      }, SetOptions(merge: true));
    } else {
      batch.update(participantRef, {
        'last_heartbeat': FieldValue.serverTimestamp(),
      });
    }

    try {
      await batch.commit();
    } catch (e) {
      debugPrint("Firestore update failed: $e");
    }
  }

  Future<void> _leaveChannel() async {
    _heartbeatTimer?.cancel();
    
    // Firestore 상태 업데이트 (참가자 수 감소 및 종료 처리)
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final callRef = FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.roomId)
          .collection('calls')
          .doc(widget.callId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final callSnap = await transaction.get(callRef);
        if (!callSnap.exists) return;

        final currentCount = (callSnap.data()?['participant_count'] as num?)?.toInt() ?? 0;
        final newCount = (currentCount - 1).clamp(0, 100);

        transaction.update(callRef.collection('participants').doc(uid), {
          'left_at': FieldValue.serverTimestamp(),
        });

        transaction.update(callRef, {
          'participant_count': newCount,
          if (newCount == 0) 'status': 'ended',
          if (newCount == 0) 'ended_at': FieldValue.serverTimestamp(),
        });

        if (newCount == 0) {
          transaction.update(FirebaseFirestore.instance.collection('chat_rooms').doc(widget.roomId), {
            'active_call_id': null,
          });
        }
      });
    }

    // 아고라 리소스 해제
    try {
      await _engine.stopPreview();
      await _engine.leaveChannel();
      await _engine.release();
    } catch (e) {
      debugPrint("Agora release error: $e");
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _engine.muteLocalAudioStream(_isMuted);
  }

  void _toggleCamera() {
    setState(() => _isCameraOff = !_isCameraOff);
    _engine.enableLocalVideo(!_isCameraOff);
  }

  void _switchCamera() {
    setState(() => _isFrontCamera = !_isFrontCamera);
    _engine.switchCamera();
  }

  // ── 비디오 레이아웃 빌드 ──────────────────────────────────────────────────
  Widget _buildVideoLayout() {
    final List<Widget> views = [];
    
    // 1. 내 영상 (좌측 상단 혹은 격자)
    if (_localUserJoined) {
      views.add(_buildLocalView());
    }

    // 2. 상대방 영상들
    for (var uid in _remoteUids) {
      views.add(_buildRemoteView(uid));
    }

    if (views.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // 참여자 수에 따른 격자 구성
    int count = views.length;
    if (count == 1) {
      return views[0];
    } else if (count == 2) {
      return Column(
        children: [
          Expanded(child: views[0]),
          Expanded(child: views[1]),
        ],
      );
    } else if (count <= 4) {
      return Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: views[0]),
                Expanded(child: views[1]),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(child: views[2]),
                if (count == 4) Expanded(child: views[3]) else const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ],
      );
    } else {
      // 5명 이상일 경우 (현재는 최대 4명 가정)
      return GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2),
        itemCount: views.length,
        itemBuilder: (context, index) => views[index],
      );
    }
  }

  Widget _buildLocalView() {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          _isCameraOff
              ? const Center(child: Icon(Icons.videocam_off, color: Colors.white, size: 50))
              : AgoraVideoView(
                  controller: VideoViewController(
                    rtcEngine: _engine,
                    canvas: const VideoCanvas(uid: 0),
                  ),
                ),
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: Colors.black54,
              child: const Text("Me", style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemoteView(int remoteUid) {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          AgoraVideoView(
            controller: VideoViewController.remote(
              rtcEngine: _engine,
              canvas: VideoCanvas(uid: remoteUid),
              connection: RtcConnection(channelId: widget.channelName),
            ),
          ),
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: Colors.black54,
              child: Text("User $remoteUid", style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 비디오 영역
          _buildVideoLayout(),

          // 상단바
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10, bottom: 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      widget.roomName,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 48), // 대칭용
                ],
              ),
            ),
          ),

          // 하단 컨트롤 바 및 종료 버튼
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // 마이크 토글
                    _buildControlButton(
                      onPressed: _toggleMute,
                      icon: _isMuted ? Icons.mic_off : Icons.mic,
                      color: _isMuted ? Colors.red : Colors.white24,
                    ),
                    // 종료 버튼 (빨간색)
                    GestureDetector(
                      onTap: _leaveChannel,
                      child: Container(
                        width: 70,
                        height: 70,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
                        ),
                        child: const Icon(Icons.call_end, color: Colors.white, size: 36),
                      ),
                    ),
                    // 카메라 토글
                    _buildControlButton(
                      onPressed: _toggleCamera,
                      icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
                      color: _isCameraOff ? Colors.red : Colors.white24,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // 카메라 전환 버튼
                _buildControlButton(
                  onPressed: _switchCamera,
                  icon: Icons.flip_camera_ios,
                  color: Colors.white24,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required VoidCallback onPressed,
    required IconData icon,
    required Color color,
  }) {
    return CircleAvatar(
      radius: 28,
      backgroundColor: color,
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 28),
        onPressed: onPressed,
      ),
    );
  }
}
