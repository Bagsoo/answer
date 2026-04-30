import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../l10n/app_localizations.dart';
import '../utils/user_cache.dart';

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
  Map<int, String> _remoteNames = {}; // uid: name
  List<int> _remoteUids = []; 
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
    await [Permission.microphone, Permission.camera].request();

    _engine = createAgoraRtcEngine();
    await _engine.initialize(RtcEngineContext(
      appId: widget.appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    _engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          if (mounted) setState(() => _localUserJoined = true);
          _updateFirestoreStatus(joined: true);
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          _resolveRemoteName(remoteUid);
          if (mounted) {
            setState(() {
              if (!_remoteUids.contains(remoteUid)) _remoteUids.add(remoteUid);
            });
          }
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          if (mounted) {
            setState(() {
              _remoteUids.remove(remoteUid);
              _remoteNames.remove(remoteUid);
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

  // Firestore에서 아고라 UID를 가진 유저의 이름 조회
  Future<void> _resolveRemoteName(int agoraUid) async {
    final query = await FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(widget.roomId)
        .collection('calls')
        .doc(widget.callId)
        .collection('participants')
        .where('agora_uid', isEqualTo: agoraUid)
        .get();

    if (query.docs.isNotEmpty) {
      final userId = query.docs.first.id;
      final userData = await UserCache.get(userId);
      if (mounted) {
        setState(() => _remoteNames[agoraUid] = userData['name'] as String? ?? 'User');
      }
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _updateFirestoreStatus();
    });
  }

  Future<void> _updateFirestoreStatus({bool joined = false}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final participantRef = FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(widget.roomId)
        .collection('calls')
        .doc(widget.callId)
        .collection('participants')
        .doc(uid);

    if (joined) {
      await participantRef.set({
        'last_heartbeat': FieldValue.serverTimestamp(),
        'agora_uid': widget.agoraUid,
        'left_at': null,
      }, SetOptions(merge: true));
    } else {
      await participantRef.update({'last_heartbeat': FieldValue.serverTimestamp()});
    }
  }

  Future<void> _leaveChannel() async {
    _heartbeatTimer?.cancel();
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

        transaction.update(callRef.collection('participants').doc(uid), {'left_at': FieldValue.serverTimestamp()});
        transaction.update(callRef, {
          'participant_count': newCount,
          if (newCount == 0) 'status': 'ended',
        });
      });
    }

    try {
      await _engine.stopPreview();
      await _engine.leaveChannel();
      await _engine.release();
    } catch (e) {
      debugPrint("Agora release error: $e");
    }

    if (mounted) Navigator.of(context).pop();
  }

  Widget _buildVideoLayout() {
    final List<Widget> views = [];
    if (_localUserJoined) views.add(_buildLocalView());
    for (var uid in _remoteUids) views.add(_buildRemoteView(uid));

    if (views.isEmpty) return const Center(child: CircularProgressIndicator());
    int count = views.length;
    if (count == 1) return views[0];
    if (count == 2) return Column(children: [Expanded(child: views[0]), Expanded(child: views[1])]);
    return Column(
      children: [
        Expanded(child: Row(children: [Expanded(child: views[0]), Expanded(child: views[1])])),
        Expanded(child: Row(children: [Expanded(child: views[2]), count == 4 ? Expanded(child: views[3]) : const Expanded(child: SizedBox())])),
      ],
    );
  }

  Widget _buildLocalView() {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          _isCameraOff ? const Center(child: Icon(Icons.videocam_off, color: Colors.white, size: 50))
              : AgoraVideoView(controller: VideoViewController(rtcEngine: _engine, canvas: const VideoCanvas(uid: 0))),
          Positioned(top: 10, left: 10, child: Container(padding: const EdgeInsets.all(4), color: Colors.black54, child: const Text("Me", style: TextStyle(color: Colors.white)))),
        ],
      ),
    );
  }

  Widget _buildRemoteView(int remoteUid) {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          AgoraVideoView(controller: VideoViewController.remote(rtcEngine: _engine, canvas: VideoCanvas(uid: remoteUid), connection: RtcConnection(channelId: widget.channelName))),
          Positioned(top: 10, left: 10, child: Container(padding: const EdgeInsets.all(4), color: Colors.black54, child: Text(_remoteNames[remoteUid] ?? 'User', style: const TextStyle(color: Colors.white)))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildVideoLayout(),
          Positioned(bottom: 40, left: 0, right: 0, child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _leaveChannel,
                child: Container(width: 70, height: 70, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: const Icon(Icons.call_end, color: Colors.white, size: 36)),
              ),
            ],
          )),
        ],
      ),
    );
  }
}
