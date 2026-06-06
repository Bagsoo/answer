import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:messenger/l10n/app_localizations.dart';
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
    final l = AppLocalizations.of(context);
    // debugPrint('DEBUG: AiMinutesBubble listening to jobId: $jobId');
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('ai_jobs').doc(jobId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingState(l.aiMinutesLoading, l);
        }

        if (snapshot.hasError) {
          debugPrint('DEBUG: AiMinutesBubble error: ${snapshot.error}');
          return _buildErrorState(l.aiMinutesError, l);
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          debugPrint('DEBUG: AiMinutesBubble: Document does not exist or no data');
          return _buildLoadingState(l.aiMinutesChecking, l);
        }

        final data = snapshot.data!.data();
        final currentStatus = data?['status'] as String? ?? 'processing';
        debugPrint('DEBUG: AiMinutesBubble currentStatus: $currentStatus');

        if (currentStatus == 'processing') {
          return _buildLoadingState(l.aiMinutesAnalyzing, l);
        } else if (currentStatus == 'failed') {
          return _buildErrorState(data?['errorMessage'] ?? l.aiMinutesFailed, l);
        } else if (currentStatus == 'completed') {
          final result = data?['result'] as Map<String, dynamic>?;
          return _buildCompletedState(result?['summary'] ?? l.aiMinutesNoSummary, l);
        }

        return _buildLoadingState(l.aiMinutesWaiting, l);
      },
    );
  }

  Widget _buildLoadingState(String message, AppLocalizations l) {
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

  Widget _buildErrorState(String message, AppLocalizations l) {
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

  Widget _buildCompletedState(String summary, AppLocalizations l) {
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
          Text(l.meetingMinutesSummary, style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onPrimaryContainer)),
          const SizedBox(height: 8),
          Text(summary, style: TextStyle(fontSize: 13, color: colorScheme.onPrimaryContainer)),
        ],
      ),
    );
  }
}
