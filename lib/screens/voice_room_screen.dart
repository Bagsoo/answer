import 'dart:async';
import 'dart:convert';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../l10n/app_localizations.dart';
import '../services/callkit_service.dart';
import '../services/voice_call_service.dart';
import '../utils/user_display.dart';

class VoiceRoomScreen extends StatefulWidget {
  const VoiceRoomScreen({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.callId,
    required this.token,
    required this.appId,
    required this.channelName,
    required this.agoraUid,
  });

  final String roomId;
  final String roomName;
  final String callId;
  final String token;
  final String appId;
  final String channelName;
  final int agoraUid;

  @override
  State<VoiceRoomScreen> createState() => _VoiceRoomScreenState();
}

class _VoiceRoomScreenState extends State<VoiceRoomScreen>
    with WidgetsBindingObserver {
  static const _heartbeatInterval = Duration(seconds: 15);

  final Set<int> _speakingAgoraUids = <int>{};

  RtcEngine? _engine;
  Timer? _heartbeatTimer;
  bool _joining = true;
  bool _leaving = false;
  bool _joined = false;
  bool _muted = false;
  bool _speakerOn = true;
  String _statusText = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    context.read<VoiceCallService>().isInVoiceRoom.value = true;
    context.read<VoiceCallService>().endVoiceRoomTransition();
    CallkitService.instance.bindEndCallback(() async {
      if (!_leaving) {
        await _leaveVoiceRoom();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _statusText = AppLocalizations.of(context).voiceRoomConnecting;
      });
      _initializeVoiceRoom();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    context.read<VoiceCallService>().isInVoiceRoom.value = false;
    context.read<VoiceCallService>().endVoiceRoomTransition();
    unawaited(CallkitService.instance.unbind());
    if (!_leaving) {
      unawaited(_leaveVoiceRoom(popAfterLeave: false));
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handlePendingSystemAction();
    }
  }

  Future<void> _initializeVoiceRoom() async {
    final l = AppLocalizations.of(context);
    final recorder = AudioRecorder();
    final hasPermission = await recorder.hasPermission();
    await recorder.dispose();

    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.voiceRoomMicPermissionRequired)),
      );
      Navigator.of(context).pop();
      return;
    }

    final engine = createAgoraRtcEngine();
    _engine = engine;

    engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          if (!mounted) return;
          setState(() {
            _joining = false;
            _joined = true;
            _statusText = '';
          });
          final voiceCallService = context.read<VoiceCallService>();
          unawaited(
            voiceCallService.saveActiveSession(
              roomId: widget.roomId,
              callId: widget.callId,
              roomName: widget.roomName,
              appId: widget.appId,
              channelName: widget.channelName,
              agoraUid: widget.agoraUid,
            ),
          );
          unawaited(
            voiceCallService.startSystemCallNotification(
              roomName: widget.roomName,
              roomId: widget.roomId,
              callId: widget.callId,
              ongoingText: l.voiceCallOngoing,
              returnActionLabel: l.voiceCallRejoin,
              endActionLabel: l.leave,
            ),
          );
          unawaited(
            CallkitService.instance.startOutgoingVoiceCall(
              callId: widget.callId,
              roomName: widget.roomName,
            ),
          );
          _startHeartbeat();
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
        },
        onUserOffline: (
          RtcConnection connection,
          int remoteUid,
          UserOfflineReasonType reason,
        ) {
          if (!mounted) return;
          setState(() {
            _speakingAgoraUids.remove(remoteUid);
          });
        },
        onConnectionLost: (RtcConnection connection) {
          if (!mounted) return;
          setState(() {
            _statusText = l.voiceRoomConnectionLost;
          });
        },
        onConnectionStateChanged: (
          RtcConnection connection,
          ConnectionStateType state,
          ConnectionChangedReasonType reason,
        ) {
          if (!mounted) return;
          if (state == ConnectionStateType.connectionStateReconnecting) {
            setState(() => _statusText = l.voiceRoomReconnecting);
          } else if (state == ConnectionStateType.connectionStateConnected) {
            setState(() => _statusText = '');
          }
        },
        onTokenPrivilegeWillExpire: (
          RtcConnection connection,
          String token,
        ) async {
          final refreshed = await context.read<VoiceCallService>().refreshVoiceToken(
                roomId: widget.roomId,
                callId: widget.callId,
              );
          await _engine?.renewToken(refreshed.token);
        },
        onAudioVolumeIndication: (
          RtcConnection connection,
          List<AudioVolumeInfo> speakers,
          int speakerNumber,
          int totalVolume,
        ) {
          if (!mounted) return;
          final active = <int>{};
          for (final speaker in speakers) {
            if ((speaker.volume ?? 0) > 5) {
              active.add(speaker.uid ?? 0);
            }
          }
          setState(() {
            _speakingAgoraUids
              ..clear()
              ..addAll(active);
          });
        },
      ),
    );

    await engine.initialize(
      RtcEngineContext(
        appId: widget.appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );
    await engine.enableAudio();
    await engine.setEnableSpeakerphone(_speakerOn);
    await engine.enableAudioVolumeIndication(
      interval: 300,
      smooth: 3,
      reportVad: true,
    );
    await engine.joinChannel(
      token: widget.token,
      channelId: widget.channelName,
      uid: widget.agoraUid,
      options: const ChannelMediaOptions(
        autoSubscribeAudio: true,
        publishMicrophoneTrack: true,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    await _engine?.muteLocalAudioStream(next);
    if (!mounted) return;
    setState(() => _muted = next);
    await context.read<VoiceCallService>().setMuted(
          roomId: widget.roomId,
          callId: widget.callId,
          uid: _myUid,
          isMuted: next,
        );
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speakerOn;
    await _engine?.setEnableSpeakerphone(next);
    if (!mounted) return;
    setState(() => _speakerOn = next);
  }

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _sendHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      _sendHeartbeat();
    });
  }

  Future<void> _sendHeartbeat() async {
    if (!_joined || _leaving) return;
    await context.read<VoiceCallService>().updateHeartbeat(
          roomId: widget.roomId,
          callId: widget.callId,
          uid: _myUid,
        );
  }

  Future<void> _handlePendingSystemAction() async {
    final action =
        await context.read<VoiceCallService>().getAndClearPendingSystemAction();
    if (action == 'end' && mounted && !_leaving) {
      await _leaveVoiceRoom();
    }
  }

  Future<void> _leaveVoiceRoom({bool popAfterLeave = true}) async {
    if (_leaving) return;
    _leaving = true;
    _heartbeatTimer?.cancel();
    final engine = _engine;
    _engine = null;

    try {
      await engine?.leaveChannel();
    } catch (_) {}

    try {
      await context.read<VoiceCallService>().leaveVoiceCall(
            roomId: widget.roomId,
            callId: widget.callId,
          );
    } catch (_) {}

    try {
      await engine?.release();
    } catch (_) {}

    await context.read<VoiceCallService>().clearActiveSession();
    await context.read<VoiceCallService>().stopSystemCallNotification();
    await CallkitService.instance.endCall(widget.callId);
    await CallkitService.instance.unbind();
    context.read<VoiceCallService>().isInVoiceRoom.value = false;
    context.read<VoiceCallService>().endVoiceRoomTransition();

    if (mounted && popAfterLeave) {
      Navigator.of(context).pop();
    }
  }

  int _toAgoraUid(String uid) {
    final bytes = sha256.convert(utf8.encode(uid)).bytes;
    final value = (bytes[0] << 24) |
        (bytes[1] << 16) |
        (bytes[2] << 8) |
        bytes[3];
    return value & 0x7fffffff;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return WillPopScope(
      onWillPop: () async {
        await _leaveVoiceRoom();
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.voiceRoomTitle),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _leaving ? null : _leaveVoiceRoom,
          ),
        ),
        body: Column(
          children: [
            if (_statusText.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: colorScheme.surfaceContainerHighest,
                child: Text(
                  _statusText,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('chat_rooms')
                    .doc(widget.roomId)
                    .collection('calls')
                    .doc(widget.callId)
                    .collection('participants')
                    .where('left_at', isNull: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  final docs = snapshot.data?.docs ??
                      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                  return GridView.builder(
                    padding: const EdgeInsets.all(20),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.9,
                    ),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data();
                      final uid = docs[index].id;
                      final isSpeaking = _speakingAgoraUids.contains(_toAgoraUid(uid));
                      final isMe = uid == _myUid;
                      final isMuted = data['is_muted'] == true;
                      return FutureBuilder<UserDisplayData>(
                        future: UserDisplay.resolve(uid),
                        builder: (context, userSnapshot) {
                          final user = userSnapshot.data ??
                              UserDisplay.fromStored(uid: uid, name: uid);
                          return _VoiceParticipantCard(
                            display: user,
                            isSpeaking: isSpeaking,
                            isMuted: isMuted,
                            isMe: isMe,
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _joined && !_leaving ? _toggleMute : null,
                        icon: Icon(
                          _muted ? Icons.mic_off_outlined : Icons.mic_none_outlined,
                        ),
                        label: Text(l.voiceRoomMute),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _joined && !_leaving ? _toggleSpeaker : null,
                        icon: Icon(
                          _speakerOn
                              ? Icons.volume_up_outlined
                              : Icons.hearing_disabled_outlined,
                        ),
                        label: Text(l.voiceRoomSpeaker),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.error,
                          foregroundColor: colorScheme.onError,
                        ),
                        onPressed: _leaving ? null : _leaveVoiceRoom,
                        icon: const Icon(Icons.call_end),
                        label: Text(l.leave),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceParticipantCard extends StatelessWidget {
  const _VoiceParticipantCard({
    required this.display,
    required this.isSpeaking,
    required this.isMuted,
    required this.isMe,
  });

  final UserDisplayData display;
  final bool isSpeaking;
  final bool isMuted;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final photoUrl = display.photoUrl;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isSpeaking ? colorScheme.primary : colorScheme.outlineVariant,
          width: isSpeaking ? 3 : 1,
        ),
        boxShadow: isSpeaking
            ? [
                BoxShadow(
                  color: colorScheme.primary.withOpacity(0.24),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: colorScheme.primaryContainer,
            backgroundImage:
                photoUrl.isNotEmpty ? CachedNetworkImageProvider(photoUrl) : null,
            child: photoUrl.isEmpty
                ? Text(
                    display.initial(l),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          Text(
            isMe ? '${display.displayName(l)} (${l.me})' : display.displayName(l),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Icon(
            isMuted ? Icons.mic_off_outlined : Icons.graphic_eq,
            color: isMuted
                ? colorScheme.error
                : (isSpeaking ? colorScheme.primary : colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
