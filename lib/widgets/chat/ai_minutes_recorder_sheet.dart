import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../l10n/app_localizations.dart';

class AiMinutesRecorderSheet extends StatefulWidget {
  final Function(File file, int durationSeconds) onCompleted;

  const AiMinutesRecorderSheet({super.key, required this.onCompleted});

  @override
  State<AiMinutesRecorderSheet> createState() => _AiMinutesRecorderSheetState();
}

class _AiMinutesRecorderSheetState extends State<AiMinutesRecorderSheet> {
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  int _seconds = 0;
  Timer? _timer;
  String? _filePath;
  
  static const int maxSeconds = 30 * 60; // 30분
  static const int maxSizeInBytes = 50 * 1024 * 1024; // 50MB

  @override
  void initState() {
    super.initState();
    _startRecording();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      if (await _recorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/ai_minutes_${const Uuid().v4()}.m4a';
        _filePath = path;

        const config = RecordConfig(encoder: AudioEncoder.aacLc);
        await _recorder.start(config, path: path);

        setState(() {
          _isRecording = true;
        });

        _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
          setState(() {
            _seconds++;
          });

          // 1. 시간 제한 체크 (30분)
          if (_seconds >= maxSeconds) {
            _stopAndComplete(reason: 'time');
            return;
          }

          // 2. 용량 제한 체크 (50MB) - 5초마다 체크 (오버헤드 방지)
          if (_seconds % 5 == 0 && _filePath != null) {
            final file = File(_filePath!);
            if (await file.exists()) {
              final size = await file.length();
              if (size >= maxSizeInBytes) {
                _stopAndComplete(reason: 'size');
              }
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error starting AI minutes recording: $e');
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _stopAndComplete({String? reason}) async {
    _timer?.cancel();
    final path = await _recorder.stop();
    if (path != null && mounted) {
      if (reason != null) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.aiMinutesLimitReached)),
        );
      }
      widget.onCompleted(File(path), _seconds);
      Navigator.pop(context);
    }
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.aiMinutesRecording,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              _formatDuration(_seconds),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: cs.onPrimaryContainer,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'MAX: 30:00 / 50MB',
            style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5)),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filled(
                onPressed: () => _stopAndComplete(),
                iconSize: 40,
                icon: const Icon(Icons.stop_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            l.confirm, // "완료하려면 정지 버튼을 누르세요" 같은 의미로 사용
            style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }
}
