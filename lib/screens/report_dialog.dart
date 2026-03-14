import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/report_service.dart';

/// 신고 다이얼로그
/// [onSubmit] — 선택한 사유와 기타 텍스트를 받아 신고 처리 후 [ReportResult] 반환
Future<void> showReportDialog({
  required BuildContext context,
  required Future<ReportResult> Function(ReportReason reason, String otherText) onSubmit,
}) async {
  final l = AppLocalizations.of(context);
  final colorScheme = Theme.of(context).colorScheme;

  ReportReason? selected;
  final otherController = TextEditingController();
  bool submitting = false;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setS) {
          final reasons = [
            (ReportReason.spam, l.reportReasonSpam),
            (ReportReason.hateSpeech, l.reportReasonHate),
            (ReportReason.obscene, l.reportReasonObscene),
            (ReportReason.fraud, l.reportReasonFraud),
            (ReportReason.other, l.reportReasonOther),
          ];

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 핸들
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 4),
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.onSurface.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // 제목
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Text(
                      l.reportTitle,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),

                  // 사유 목록
                  ...reasons.map((r) {
                    final (reason, label) = r;
                    return RadioListTile<ReportReason>(
                      value: reason,
                      groupValue: selected,
                      title: Text(label),
                      dense: true,
                      onChanged: (v) => setS(() => selected = v),
                      activeColor: colorScheme.primary,
                    );
                  }),

                  // 기타 입력
                  if (selected == ReportReason.other)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                      child: TextField(
                        controller: otherController,
                        autofocus: true,
                        maxLines: 3,
                        maxLength: 200,
                        decoration: InputDecoration(
                          hintText: l.reportOtherHint,
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                    ),

                  // 제출 버튼
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (selected == null || submitting)
                            ? null
                            : () async {
                                setS(() => submitting = true);
                                final result = await onSubmit(
                                  selected!,
                                  otherController.text.trim(),
                                );
                                if (!ctx.mounted) return;
                                Navigator.pop(ctx);

                                String msg;
                                switch (result) {
                                  case ReportResult.success:
                                    msg = l.reportSuccess;
                                  case ReportResult.duplicate:
                                    msg = l.reportDuplicate;
                                  case ReportResult.isMine:
                                    msg = l.reportIsMine;
                                  case ReportResult.error:
                                    msg = l.reportError;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(msg)),
                                );
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.error,
                          foregroundColor: colorScheme.onError,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: submitting
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Text(l.reportSubmit,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  otherController.dispose();
}