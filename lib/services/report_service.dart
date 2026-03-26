import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:messenger/l10n/app_localizations.dart';

enum ReportReason {
  spam,
  hateSpeech,
  obscene,
  fraud,
  other,
}

class ReportService {
  final _db = FirebaseFirestore.instance;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  // ── 신고 사유 레이블 ────────────────────────────────────────────────────────
  static String reasonLabel(ReportReason reason, BuildContext context) {
    final l = AppLocalizations.of(context);
    switch (reason) {
      case ReportReason.spam:       return l.reportReasonSpam;
      case ReportReason.hateSpeech: return l.reportReasonHate;
      case ReportReason.obscene:    return l.reportReasonObscene;
      case ReportReason.fraud:      return l.reportReasonFraud;
      case ReportReason.other:      return l.reportReasonOther;
    }
  }

  // ── 메시지 신고 ─────────────────────────────────────────────────────────────
  Future<ReportResult> reportMessage({
    required String messageId,
    required String targetOwnerId,
    required String roomId,
    required ReportReason reason,
    String otherText = '',
  }) async {
    if (_myUid.isEmpty) return ReportResult.error;
    if (_myUid == targetOwnerId) return ReportResult.isMine;

    final docId = '${_myUid}_$messageId';
    final ref = _db.collection('reports').doc(docId);

    try {
      final existing = await ref.get();
      if (existing.exists) return ReportResult.duplicate;

      await ref.set({
        'reporter_id': _myUid,
        'target_type': 'message',
        'target_id': messageId,
        'target_owner_id': targetOwnerId,
        'room_id': roomId,
        'reason': reason.name,
        'other_text': reason == ReportReason.other ? otherText : '',
        'created_at': FieldValue.serverTimestamp(),
        'status': 'pending',
      });
      return ReportResult.success;
    } catch (e) {
      debugPrint('reportMessage error: $e');
      return ReportResult.error;
    }
  }

  // ── 게시글 신고 ─────────────────────────────────────────────────────────────
  Future<ReportResult> reportPost({
    required String postId,
    required String targetOwnerId,
    required String groupId,
    required ReportReason reason,
    String otherText = '',
  }) async {
    if (_myUid.isEmpty) return ReportResult.error;
    if (_myUid == targetOwnerId) return ReportResult.isMine;

    final docId = '${_myUid}_$postId';
    final ref = _db.collection('reports').doc(docId);

    try {
      final existing = await ref.get();
      if (existing.exists) return ReportResult.duplicate;

      await ref.set({
        'reporter_id': _myUid,
        'target_type': 'post',
        'target_id': postId,
        'target_owner_id': targetOwnerId,
        'group_id': groupId,
        'reason': reason.name,
        'other_text': reason == ReportReason.other ? otherText : '',
        'created_at': FieldValue.serverTimestamp(),
        'status': 'pending',
      });
      return ReportResult.success;
    } catch (e) {
      debugPrint('reportPost error: $e');
      return ReportResult.error;
    }
  }
}

enum ReportResult {
  success,
  duplicate,
  isMine,
  error,
}