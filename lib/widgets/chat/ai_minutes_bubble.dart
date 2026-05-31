import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AiMinutesBubble extends StatelessWidget {
  final String jobId;
  final String status; // 초기 상태
  final ColorScheme colorScheme;

  const AiMinutesBubble({
    super.key,
    required this.jobId,
    required this.status,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    debugPrint('DEBUG: AiMinutesBubble listening to jobId: $jobId');
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('ai_jobs').doc(jobId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingState('데이터를 불러오는 중...');
        }

        if (snapshot.hasError) {
          debugPrint('DEBUG: AiMinutesBubble error: ${snapshot.error}');
          return _buildErrorState('오류가 발생했습니다.');
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          debugPrint('DEBUG: AiMinutesBubble: Document does not exist or no data');
          return _buildLoadingState('요청을 확인 중입니다...');
        }

        final data = snapshot.data!.data();
        final currentStatus = data?['status'] as String? ?? 'processing';
        debugPrint('DEBUG: AiMinutesBubble currentStatus: $currentStatus');

        if (currentStatus == 'processing') {
          return _buildLoadingState('AI가 회의록을 분석 중입니다... (약 1~2분 소요)');
        } else if (currentStatus == 'failed') {
          return _buildErrorState(data?['errorMessage'] ?? '회의록 생성에 실패했습니다.');
        } else if (currentStatus == 'completed') {
          final result = data?['result'] as Map<String, dynamic>?;
          return _buildCompletedState(result?['summary'] ?? '요약 내용이 없습니다.');
        }

        return _buildLoadingState('대기 중...');
      },
    );
  }

  Widget _buildLoadingState(String message) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(message, style: TextStyle(fontSize: 13, color: colorScheme.onErrorContainer)),
    );
  }

  Widget _buildCompletedState(String summary) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🎤 회의록 요약', style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onPrimaryContainer)),
          const SizedBox(height: 8),
          Text(summary, style: TextStyle(fontSize: 13, color: colorScheme.onPrimaryContainer)),
        ],
      ),
    );
  }
}
