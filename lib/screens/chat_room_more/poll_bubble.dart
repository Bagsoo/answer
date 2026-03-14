import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/user_provider.dart';
import '../../services/poll_service.dart';

class PollBubble extends StatelessWidget {
  final String roomId;
  final String pollId;
  final String? refGroupId; // 날짜투표 종료 시 스케줄 저장용
  final ColorScheme colorScheme;

  const PollBubble({
    super.key,
    required this.roomId,
    required this.pollId,
    required this.colorScheme,
    this.refGroupId,
  });

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final service = PollService();

    return StreamBuilder<DocumentSnapshot>(
      stream: service.pollStream(roomId, pollId),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const SizedBox.shrink();
        }

        final poll = snap.data!.data() as Map<String, dynamic>;
        final title = poll['title'] as String? ?? '';
        final type = poll['type'] as String? ?? 'regular';
        final isAnonymous = poll['is_anonymous'] as bool? ?? false;
        final isMultiple = poll['is_multiple'] as bool? ?? false;
        final isClosed = poll['is_closed'] as bool? ?? false;
        final scheduleSaved = poll['schedule_saved'] as bool? ?? false;
        final createdBy = poll['created_by'] as String? ?? '';
        final options =
            List<Map<String, dynamic>>.from(poll['options'] as List? ?? []);

        final isDatePoll = type == 'date';
        final isCreator = createdBy == _myUid;

        // 내가 투표한 옵션 ID 목록 (anonymous_voter_ids로 중복 체크 — 익명/실명 모두)
        final myVotes = <String>{};
        for (final opt in options) {
          final anonVoters =
              List<String>.from(opt['anonymous_voter_ids'] as List? ?? []);
          if (anonVoters.contains(_myUid)) myVotes.add(opt['id'] as String);
        }
        final hasVoted = myVotes.isNotEmpty;

        // 전체 투표 수
        final allVoters = <String>{};
        int totalVoteCount = 0;
        for (final opt in options) {
          final anonVoters =
              List<String>.from(opt['anonymous_voter_ids'] as List? ?? []);
          allVoters.addAll(anonVoters);
          totalVoteCount += opt['vote_count'] as int? ?? 0;
        }
        // 익명: 투표 수 합산, 실명: unique voter 수
        final totalDisplay = isAnonymous ? totalVoteCount : allVoters.length;

        return Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
            minWidth: 220,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isClosed
                  ? colorScheme.onSurface.withOpacity(0.15)
                  : colorScheme.primary.withOpacity(0.3),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 헤더 ──────────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                decoration: BoxDecoration(
                  color: isClosed
                      ? colorScheme.onSurface.withOpacity(0.05)
                      : colorScheme.primaryContainer.withOpacity(0.4),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16)),
                ),
                child: Row(children: [
                  Icon(
                    isDatePoll
                        ? Icons.calendar_today_outlined
                        : Icons.poll_outlined,
                    size: 16,
                    color: isClosed
                        ? colorScheme.onSurface.withOpacity(0.4)
                        : colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isClosed
                            ? colorScheme.onSurface.withOpacity(0.5)
                            : colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (isClosed)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.onSurface.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        l.pollClosed,
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ),
                ]),
              ),

              // ── 뱃지 (익명/복수선택) ────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                child: Wrap(spacing: 6, children: [
                  if (isAnonymous)
                    _Badge(label: l.pollAnonymous, colorScheme: colorScheme),
                  if (isMultiple)
                    _Badge(label: l.pollMultiple, colorScheme: colorScheme),
                ]),
              ),

              // ── 선택지 ───────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Column(
                  children: options.map((opt) {
                    final id = opt['id'] as String;
                    final text = opt['text'] as String? ?? '';
                    final count = opt['vote_count'] as int? ?? 0;
                    // 실명 투표자 목록 [{uid, name, photo_url}]
                    final voters = List<Map<String, dynamic>>.from(
                      (opt['voters'] as List? ?? [])
                          .map((v) => Map<String, dynamic>.from(v as Map)),
                    );
                    final isSelected = myVotes.contains(id);

                    // 비율 계산
                    final total = isAnonymous ? totalVoteCount : allVoters.length;
                    final pct = total == 0 ? 0.0 : count / total;

                    // 최다 득표 여부 (종료 시 강조)
                    final maxCount = options
                        .map((o) => o['vote_count'] as int? ?? 0)
                        .reduce((a, b) => a > b ? a : b);
                    final isWinner = isClosed && count == maxCount && count > 0;

                    return GestureDetector(
                      onTap: isClosed
                          ? null
                          : () {
                              final myName =
                                  context.read<UserProvider>().name;
                              service.vote(
                                roomId: roomId,
                                pollId: pollId,
                                optionIds: [id],
                                isAnonymous: isAnonymous,
                                isMultiple: isMultiple,
                                currentOptions: options,
                                myName: myName,
                                myPhotoUrl: null, // 나중에 프로필 사진 연동
                              );
                            },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Stack(children: [
                          // 바 배경
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: (hasVoted || isClosed) ? pct : 0,
                              minHeight: 40,
                              backgroundColor:
                                  colorScheme.onSurface.withOpacity(0.06),
                              valueColor: AlwaysStoppedAnimation(
                                isWinner
                                    ? colorScheme.primary.withOpacity(0.25)
                                    : isSelected
                                        ? colorScheme.primary.withOpacity(0.15)
                                        : colorScheme.onSurface
                                            .withOpacity(0.08),
                              ),
                            ),
                          ),
                          // 텍스트 + 득표 수
                          Positioned.fill(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(children: [
                                // 선택 체크
                                if (isSelected)
                                  Icon(Icons.check_circle,
                                      size: 16,
                                      color: colorScheme.primary),
                                if (!isSelected)
                                  Icon(Icons.circle_outlined,
                                      size: 16,
                                      color: colorScheme.onSurface
                                          .withOpacity(0.3)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    isDatePoll
                                        ? _formatDateOption(text)
                                        : text,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isWinner || isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: isWinner
                                          ? colorScheme.primary
                                          : colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                if (hasVoted || isClosed) ...[
                                  Text(
                                    '$count${l.pollTotalVotes}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isWinner
                                          ? colorScheme.primary
                                          : colorScheme.onSurface
                                              .withOpacity(0.5),
                                      fontWeight: isWinner
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${(pct * 100).round()}%',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onSurface
                                          .withOpacity(0.4),
                                    ),
                                  ),
                                ],
                                // 실명 투표 시 투표자 아바타
                                if (!isAnonymous &&
                                    (hasVoted || isClosed) &&
                                    voters.isNotEmpty)
                                  _VoterAvatars(
                                      voters: voters,
                                      colorScheme: colorScheme),
                              ]),
                            ),
                          ),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
              ),

              // ── 하단 정보 + 액션 ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                child: Row(children: [
                  Text(
                    '총 $totalDisplay${l.pollTotalVotes}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                  const Spacer(),

                  // 날짜투표 + 종료 + 그룹 있음 → 일정 저장 버튼
                  if (isDatePoll &&
                      isClosed &&
                      !scheduleSaved &&
                      refGroupId != null &&
                      isCreator)
                    TextButton.icon(
                      onPressed: () =>
                          _saveSchedule(context, poll, options, l),
                      icon: const Icon(Icons.event_available, size: 14),
                      label: Text(l.pollScheduleSave,
                          style: const TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                      ),
                    ),

                  // 일정 저장 완료
                  if (scheduleSaved)
                    Row(children: [
                      Icon(Icons.check_circle,
                          size: 14, color: colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        l.pollScheduleSaved,
                        style: TextStyle(
                            fontSize: 11, color: colorScheme.primary),
                      ),
                    ]),

                  // 투표 종료 버튼 (생성자만, 아직 안 닫힘)
                  if (!isClosed && isCreator)
                    TextButton(
                      onPressed: () => _confirmClose(context, l),
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.error,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                      ),
                      child: Text(l.pollClose,
                          style: const TextStyle(fontSize: 12)),
                    ),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 투표 종료 확인 다이얼로그 ─────────────────────────────────────────────
  Future<void> _confirmClose(BuildContext context, AppLocalizations l) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.pollClose),
        content: Text(l.pollCloseConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: Text(l.pollClose),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await PollService().closePoll(roomId, pollId);
  }

  // ── 일정 저장 ─────────────────────────────────────────────────────────────
  Future<void> _saveSchedule(
    BuildContext context,
    Map<String, dynamic> poll,
    List<Map<String, dynamic>> options,
    AppLocalizations l,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.pollScheduleSave),
        content: Text(l.pollScheduleSaveConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.pollScheduleSave),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final ok = await PollService().saveDatePollAsSchedule(
      roomId: roomId,
      pollId: pollId,
      groupId: refGroupId!,
      title: poll['title'] as String? ?? '',
      options: options,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(ok ? l.pollScheduleSaved : '저장에 실패했습니다.')),
      );
    }
  }

  String _formatDateOption(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final pad = (int n) => n.toString().padLeft(2, '0');
      return '${dt.year}.${pad(dt.month)}.${pad(dt.day)} '
          '${pad(dt.hour)}:${pad(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }
}

// ── 뱃지 ─────────────────────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  final String label;
  final ColorScheme colorScheme;
  const _Badge({required this.label, required this.colorScheme});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 10, color: colorScheme.onSecondaryContainer),
        ),
      );
}

// ── 실명 투표자 아바타 ─────────────────────────────────────────────────────────
class _VoterAvatars extends StatelessWidget {
  final List<Map<String, dynamic>> voters;
  final ColorScheme colorScheme;
  const _VoterAvatars({required this.voters, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final show = voters.take(3).toList();
    final extra = voters.length - show.length; // 3명 초과 시 +N 표시

    return GestureDetector(
      onTap: voters.isNotEmpty
          ? () => _showVoterList(context)
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: show.length * 14.0 + (extra > 0 ? 20 : 4),
            height: 20,
            child: Stack(
              children: [
                ...show.asMap().entries.map((e) {
                  final voter = e.value;
                  final name = voter['name'] as String? ?? '?';
                  final photoUrl = voter['photo_url'] as String?;
                  return Positioned(
                    left: e.key * 12.0,
                    child: _VoterAvatar(
                      name: name,
                      photoUrl: photoUrl,
                      colorScheme: colorScheme,
                    ),
                  );
                }),
                // 3명 초과 시 +N 표시
                if (extra > 0)
                  Positioned(
                    left: show.length * 12.0,
                    child: CircleAvatar(
                      radius: 9,
                      backgroundColor:
                          colorScheme.onSurface.withOpacity(0.25),
                      child: Text(
                        '+$extra',
                        style: TextStyle(
                          fontSize: 7,
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 투표자 전체 목록 바텀시트
  void _showVoterList(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text('투표자 목록',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            const Divider(height: 1),
            ...voters.map((voter) {
              final name = voter['name'] as String? ?? '?';
              final photoUrl = voter['photo_url'] as String?;
              return ListTile(
                leading: _VoterAvatar(
                  name: name,
                  photoUrl: photoUrl,
                  colorScheme: colorScheme,
                  radius: 18,
                  fontSize: 13,
                ),
                title: Text(name),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// 개별 아바타 (photo_url 있으면 사진, 없으면 이름 첫 글자)
class _VoterAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final ColorScheme colorScheme;
  final double radius;
  final double fontSize;

  const _VoterAvatar({
    required this.name,
    required this.photoUrl,
    required this.colorScheme,
    this.radius = 9,
    this.fontSize = 8,
  });

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(photoUrl!),
        onBackgroundImageError: (_, __) {},
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: colorScheme.primary.withOpacity(0.75),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: fontSize,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}