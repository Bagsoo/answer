import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/chat_service.dart';
import '../../utils/user_display.dart';
import '../../widgets/chat/chat_room_share_sheet.dart';
import 'settlement_form_screen.dart';

class SettlementDetailScreen extends StatelessWidget {
  final String groupId;
  final String settlementId;
  final String groupName;

  const SettlementDetailScreen({
    super.key,
    required this.groupId,
    required this.settlementId,
    this.groupName = '',
  });

  String get currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  DocumentReference get _ref => FirebaseFirestore.instance
      .collection('groups')
      .doc(groupId)
      .collection('settlements')
      .doc(settlementId);

  // ── 내 상태를 '보냈어요'로 마킹 ────────────────────────────────────────────
  Future<void> _markSent(BuildContext context, AppLocalizations l) async {
    try {
      final snap = await _ref.get();
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      final participants = List<dynamic>.from(data['participants'] ?? []);
      final updated = participants.map((p) {
        final map = Map<String, dynamic>.from(p as Map);
        if (map['uid'] == currentUserId) {
          map['status'] = 'sent';
        }
        return map;
      }).toList();
      await _ref.update({'participants': updated, 'updated_at': FieldValue.serverTimestamp()});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.settlementMarkSent)),
        );
      }
    } catch (_) {}
  }

  // ── 생성자가 입금 확인 ────────────────────────────────────────────────────
  Future<void> _markConfirmed(BuildContext context, AppLocalizations l, String targetUid) async {
    try {
      final snap = await _ref.get();
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      final participants = List<dynamic>.from(data['participants'] ?? []);
      final updated = participants.map((p) {
        final map = Map<String, dynamic>.from(p as Map);
        if (map['uid'] == targetUid) {
          map['status'] = 'confirmed';
        }
        return map;
      }).toList();
      await _ref.update({'participants': updated, 'updated_at': FieldValue.serverTimestamp()});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.settlementMarkConfirmed)),
        );
      }
    } catch (_) {}
  }

  // ── 계좌번호 복사 ──────────────────────────────────────────────────────────
  Future<void> _copyAccount(BuildContext context, AppLocalizations l, String bankInfo) async {
    await Clipboard.setData(ClipboardData(text: bankInfo));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.settlementAccountCopied)),
      );
    }
  }

  // ── 채팅방에 공유 ─────────────────────────────────────────────────────────
  Future<void> _shareToChat(BuildContext context, Map<String, dynamic> data) async {
    final l = AppLocalizations.of(context);
    final roomId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChatRoomShareSheet(groupId: groupId),
    );
    if (roomId == null || !context.mounted) return;

    final chatService = context.read<ChatService>();

    await chatService.sendSettlementMessage(
      roomId,
      groupId: groupId,
      groupName: groupName,
      settlementId: settlementId,
      title: data['title'] as String? ?? '',
      totalCost: data['total_cost'] as String? ?? '',
      bankInfo: data['bank_info'] as String? ?? '',
      creatorUid: data['creator_uid'] as String? ?? '',
      participants: data['participants'] as List<dynamic>? ?? [],
    );
    await chatService.updateLastReadTime(roomId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.settlementSharedToChat)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.settlementDetail),
        actions: [
          StreamBuilder<DocumentSnapshot>(
            stream: _ref.snapshots(),
            builder: (context, snap) {
              if (!snap.hasData || !snap.data!.exists) return const SizedBox.shrink();
              final data = snap.data!.data() as Map<String, dynamic>;
              final creatorUid = data['creator_uid'] as String? ?? '';
              if (currentUserId != creatorUid) return const SizedBox.shrink();

              return IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () {
                  final editData = {...data, 'id': settlementId};
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettlementFormScreen(
                        groupId: groupId,
                        groupName: groupName,
                        existing: editData,
                      ),
                    ),
                  );
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () async {
              final snap = await _ref.get();
              if (!snap.exists || !context.mounted) return;
              _shareToChat(context, snap.data() as Map<String, dynamic>);
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _ref.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !snap.data!.exists) {
            return Center(child: Text(l.settlementNotFound));
          }

          final data = snap.data!.data() as Map<String, dynamic>;
          final title = data['title'] as String? ?? '';
          final totalCost = data['total_cost'] as String? ?? '';
          final bankInfo = data['bank_info'] as String? ?? '';
          final creatorUid = data['creator_uid'] as String? ?? '';
          final participants = List<dynamic>.from(data['participants'] ?? []);

          final isCreator = currentUserId == creatorUid;

          // 내 참여 정보
          Map<String, dynamic>? myEntry;
          for (final p in participants) {
            if ((p as Map)['uid'] == currentUserId) {
              myEntry = Map<String, dynamic>.from(p);
              break;
            }
          }
          final myStatus = myEntry?['status'] as String? ?? 'pending';
          final myAmount = myEntry?['amount'] as String? ?? '';

          // 전체 완료 여부
          final allConfirmed = participants.every(
            (p) => (p as Map)['uid'] == creatorUid || p['status'] == 'confirmed',
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 제목 ──────────────────────────────────────────────────
                Text(
                  title,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                if (allConfirmed)
                  Chip(
                    label: Text(
                      l.settlementCompleted,
                      style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: Colors.green.withOpacity(0.1),
                  ),
                const SizedBox(height: 16),

                // ── 총 금액 카드 ───────────────────────────────────────────
                _InfoCard(
                  icon: Icons.wallet_outlined,
                  label: l.settlementTotalCost,
                  value: l.settlementTotalCostValue(totalCost),
                  colorScheme: colorScheme,
                ),
                const SizedBox(height: 8),

                // ── 계좌 정보 카드 ─────────────────────────────────────────
                if (bankInfo.isNotEmpty)
                  InkWell(
                    onTap: () => _copyAccount(context, l, bankInfo),
                    borderRadius: BorderRadius.circular(12),
                    child: _InfoCard(
                      icon: Icons.account_balance_outlined,
                      label: l.settlementBankInfo,
                      value: bankInfo,
                      colorScheme: colorScheme,
                      trailing: Icon(
                        Icons.copy_outlined,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),

                // ── 내 정산 금액 & 상태 (생성자 제외) ─────────────────────
                if (!isCreator && myEntry != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.primary.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.settlementMyAmount,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface.withOpacity(0.5),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              l.settlementAmountValue(myAmount),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                            const Spacer(),
                            _StatusBadge(status: myStatus, l: l),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── "보냈어요" 버튼 ──────────────────────────────────────
                  if (myStatus == 'pending')
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _markSent(context, l),
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(l.settlementMarkSent),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                ],

                const Divider(),
                const SizedBox(height: 12),

                // ── 참여자 목록 ───────────────────────────────────────────
                Text(
                  '${l.settlementMembers} (${participants.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 12),

                ...participants.map((p) {
                  final pm = p as Map<String, dynamic>;
                  final uid = pm['uid'] as String? ?? '';
                  final amount = pm['amount'] as String? ?? '';
                  final status = pm['status'] as String? ?? 'pending';
                  final isMe = uid == currentUserId;
                  final isThisCreator = uid == creatorUid;

                  final user = UserDisplay.resolveCached(
                    uid,
                    fallbackName: pm['display_name'] as String? ?? '',
                    fallbackPhotoUrl: pm['photo_url'] as String?,
                  ) ?? UserDisplay.fromStored(
                    uid: uid,
                    name: pm['display_name'] as String? ?? '',
                    photoUrl: pm['photo_url'] as String?,
                  );

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isMe
                            ? colorScheme.primary.withOpacity(0.3)
                            : colorScheme.outlineVariant.withOpacity(0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: colorScheme.primaryContainer,
                          backgroundImage: user.photoUrl.isNotEmpty
                              ? NetworkImage(user.photoUrl)
                              : null,
                          child: user.photoUrl.isEmpty
                              ? Text(
                                  user.initial(l, fallback: '?'),
                                  style: const TextStyle(fontSize: 13),
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    user.nameOrInitial(l),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (isMe)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: Text(
                                        '(나)',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  if (isThisCreator)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: Text(
                                        '(생성자)',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: colorScheme.onSurface.withOpacity(0.4),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (!isThisCreator)
                                Text(
                                  l.settlementAmountValue(amount),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colorScheme.onSurface.withOpacity(0.7),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (!isThisCreator) ...[
                          _StatusBadge(status: status, l: l),
                          // 생성자가 'sent' 상태인 참여자에 대해 입금 확인 버튼 표시
                          if (isCreator && status == 'sent') ...[
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () => _markConfirmed(context, l, uid),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                l.settlementMarkConfirmed,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 20),

                // ── 채팅방 공유 버튼 ──────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final snap = await _ref.get();
                      if (!snap.exists || !context.mounted) return;
                      _shareToChat(context, snap.data() as Map<String, dynamic>);
                    },
                    icon: const Icon(Icons.ios_share_outlined),
                    label: Text(l.settlementShareToChat),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                      side: BorderSide(color: colorScheme.outlineVariant),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── 상태 뱃지 ─────────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final String status;
  final AppLocalizations l;

  const _StatusBadge({required this.status, required this.l});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case 'confirmed':
        color = Colors.green;
        label = l.settlementConfirmed;
        icon = Icons.check_circle;
        break;
      case 'sent':
        color = Colors.orange;
        label = l.settlementSent;
        icon = Icons.schedule_send_outlined;
        break;
      default:
        color = Colors.grey;
        label = l.settlementPending;
        icon = Icons.hourglass_empty_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 정보 카드 ─────────────────────────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme colorScheme;
  final Widget? trailing;

  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.colorScheme,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(12),
        color: colorScheme.surfaceContainerLowest,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }
}
