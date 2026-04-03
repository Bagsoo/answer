import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../l10n/app_localizations.dart';

class VoiceMessageRecordResult {
  final File file;
  final int durationMs;
  final String fileName;
  final String mimeType;

  const VoiceMessageRecordResult({
    required this.file,
    required this.durationMs,
    required this.fileName,
    required this.mimeType,
  });
}

class VoiceMessageRecorderSheet extends StatefulWidget {
  const VoiceMessageRecorderSheet({super.key});

  @override
  State<VoiceMessageRecorderSheet> createState() =>
      _VoiceMessageRecorderSheetState();
}

class _VoiceMessageRecorderSheetState extends State<VoiceMessageRecorderSheet> {
  static const int _maxDurationSeconds = 120;

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  Timer? _timer;
  bool _recording = false;
  bool _readyToPreview = false;
  bool _playing = false;
  bool _busy = true;
  int _elapsedSeconds = 0;
  String? _recordedPath;
  String? _errorText;
  String _statusText = '';

  @override
  void initState() {
    super.initState();
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _playing = state.playing;
      });
    });
    _busy = false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _player.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _recording = false;
      _readyToPreview = false;
      _recordedPath = null;
      _elapsedSeconds = 0;
      _errorText = null;
      _statusText = l.voiceRecordingHint;
    });
    try {
      if (mounted) {
        setState(() => _statusText = l.voiceMicPermissionRequired);
      }
      final hasPermission = await _recorder
          .hasPermission()
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (!hasPermission) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.voiceMicPermissionRequired)),
        );
        Navigator.pop(context);
        return;
      }

      var encoder = AudioEncoder.aacLc;
      if (mounted) {
        setState(() => _statusText = l.loading);
      }
      if (!await _recorder
          .isEncoderSupported(encoder)
          .timeout(const Duration(seconds: 5))) {
        encoder = AudioEncoder.aacHe;
      }

      final tempDir =
          await getTemporaryDirectory().timeout(const Duration(seconds: 5));
      final path =
          '${tempDir.path}${Platform.pathSeparator}voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      if (mounted) {
        setState(() => _statusText = l.voiceRecordingNow);
      }
      await _recorder
          .start(
        RecordConfig(
          encoder: encoder,
          bitRate: 64000,
          sampleRate: 24000,
          numChannels: 1,
        ),
        path: path,
      )
          .timeout(const Duration(seconds: 8));

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        final next = timer.tick;
        if (next >= _maxDurationSeconds) {
          _stopRecording(showLimitMessage: true);
          return;
        }
        setState(() => _elapsedSeconds = next);
      });

      if (!mounted) return;
      setState(() {
        _recording = true;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = _formatError(error, fallback: l.saveFailed);
      });
    }
  }

  Future<void> _stopRecording({bool showLimitMessage = false}) async {
    if (!_recording) return;
    final l = AppLocalizations.of(context);
    try {
      setState(() => _busy = true);
      _timer?.cancel();
      final path = await _recorder.stop();
      if (!mounted) return;

      if (showLimitMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.voiceMaxDurationReached)),
        );
      }

      if (path == null || path.isEmpty) {
        Navigator.pop(context);
        return;
      }

      await _player.setFilePath(path);

      setState(() {
        _recording = false;
        _readyToPreview = true;
        _recordedPath = path;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _recording = false;
        _readyToPreview = false;
        _errorText = _formatError(error, fallback: l.saveFailed);
      });
    }
  }

  Future<void> _togglePlayback() async {
    if (_recordedPath == null) return;
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.seek(Duration.zero);
      await _player.play();
    }
  }

  Future<void> _send() async {
    final l = AppLocalizations.of(context);
    if (_recordedPath == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.attachVoice),
        content: Text(l.voiceSendConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.voiceSendAction),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final file = File(_recordedPath!);
    Navigator.pop(
      context,
      VoiceMessageRecordResult(
        file: file,
        durationMs: _elapsedSeconds * 1000,
        fileName: file.uri.pathSegments.last,
        mimeType: 'audio/mp4',
      ),
    );
  }

  Future<void> _cancelRecording() async {
    if (_recording) {
      await _recorder.stop();
    }
    if (_recordedPath != null) {
      final file = File(_recordedPath!);
      if (await file.exists()) {
        await file.delete();
      }
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _rerecord() async {
    if (_recordedPath != null) {
      final file = File(_recordedPath!);
      if (await file.exists()) {
        await file.delete();
      }
    }
    await _player.stop();
    await _startRecording();
  }

  String _formatDuration(int seconds) {
    final min = (seconds ~/ 60).toString().padLeft(2, '0');
    final sec = (seconds % 60).toString().padLeft(2, '0');
    return '$min:$sec';
  }

  String _formatError(Object error, {required String fallback}) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    if (message.isEmpty) return fallback;
    return message;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _recording
                  ? l.voiceRecordingNow
                  : l.voicePreviewTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(
                    _recording ? Icons.mic : Icons.mic_none_rounded,
                    size: 40,
                    color: _recording ? Colors.red : cs.onSurface,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _formatDuration(_elapsedSeconds),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: _recording ? cs.primary : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _recording
                        ? l.voiceRecordingHint
                        : _readyToPreview
                            ? l.voicePreviewHint(
                                _formatDuration(_elapsedSeconds),
                              )
                            : l.attachVoice,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withOpacity(0.6),
                    ),
                  ),
                  if (_busy && _statusText.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      _statusText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withOpacity(0.55),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(),
              )
            else if (_errorText != null)
              Column(
                children: [
                  Text(
                    _errorText!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: _cancelRecording,
                          child: Text(l.cancel),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: _startRecording,
                          child: Text(l.voiceRerecord),
                        ),
                      ),
                    ],
                  ),
                ],
              )
            else if (!_recording && !_readyToPreview)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _startRecording,
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.surfaceContainerHighest,
                    foregroundColor: cs.onSurface,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: Icon(
                    Icons.mic,
                    color: cs.onSurface,
                  ),
                  label: Text(l.attachVoice),
                ),
              )
            else if (_recording)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _stopRecording,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(l.voiceStopRecording),
                ),
              )
            else if (_readyToPreview)
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _togglePlayback,
                      icon: Icon(
                        _playing ? Icons.pause_circle_outline : Icons.play_arrow,
                      ),
                      label: Text(
                        _playing ? l.voicePausePreview : l.voicePlayPreview,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: _cancelRecording,
                          child: Text(l.cancel),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _rerecord,
                          child: Text(l.voiceRerecord),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: _send,
                          child: Text(l.voiceSendAction),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
