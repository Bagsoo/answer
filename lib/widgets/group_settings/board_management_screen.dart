import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/group_service.dart';
import '../../providers/group_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/group_tabs/plan_screen.dart';
import 'board_form_screen.dart';

class BoardManagementScreen extends StatelessWidget {
  final String groupId;
  const BoardManagementScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final service = context.read<GroupService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l.manageBoardsSection),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () =>
                _showBoardForm(context, l, colorScheme, service, groupId),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: service.getBoards(groupId),
        builder: (context, snap) {
          final boards = snap.data ?? [];
          if (boards.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.article_outlined,
                      size: 64,
                      color: colorScheme.onSurface.withOpacity(0.2)),
                  const SizedBox(height: 16),
                  Text(l.noBoards,
                      style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.4))),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () =>
                        _showBoardForm(context, l, colorScheme, service, groupId),
                    icon: const Icon(Icons.add),
                    label: Text(l.createBoard),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            itemCount: boards.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final board = boards[i];
              final boardType =
                  board['board_type'] as String? ?? 'free';
              return ListTile(
                leading: Icon(_boardIcon(boardType),
                    color: colorScheme.primary),
                title: Text(board['name'] as String? ?? ''),
                subtitle: Text(_boardTypeLabel(boardType, l)),
                trailing:
                    Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: Icon(Icons.edit_outlined,
                        size: 18,
                        color: colorScheme.onSurface.withOpacity(0.5)),
                    onPressed: () => _showBoardForm(
                        context, l, colorScheme, service, groupId,
                        board: board),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        size: 18, color: colorScheme.error),
                    onPressed: () => _confirmDelete(
                        context, l, colorScheme, service, board, groupId),
                  ),
                ]),
              );
            },
          );
        },
      ),
    );
  }

  IconData _boardIcon(String type) {
    switch (type) {
      case 'notice':
        return Icons.campaign_outlined;
      case 'greeting':
        return Icons.waving_hand_outlined;
      case 'sub':
        return Icons.label_outlined;
      default:
        return Icons.article_outlined;
    }
  }

  String _boardTypeLabel(String type, AppLocalizations l) {
    switch (type) {
      case 'notice':
        return l.boardTypeNotice;
      case 'greeting':
        return l.boardTypeGreeting;
      case 'sub':
        return l.boardTypeSub;
      default:
        return l.boardTypeFree;
    }
  }

  void _showBoardForm(BuildContext context, AppLocalizations l,
      ColorScheme colorScheme, GroupService service, String groupId,
      {Map<String, dynamic>? board}) {
    final groupProvider = context.read<GroupProvider>();
    if (!groupProvider.loaded) return;
    // 새 게시판 생성 시에 한도 체크
    if (board == null) {
      if (groupProvider.boardCount >= groupProvider.getMaxBoards()){
        _showUpgradeDialog(context, groupProvider.plan, l, groupId);
        return;
      }
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BoardFormScreen(groupId: groupId, board: board),
    ));
  }

  // 다이얼로그 함수를 메서드로 분리
  void _showUpgradeDialog(BuildContext context, String currentPlan, AppLocalizations l, String groupId) {
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.unfold_more_double_outlined, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(l.limitReached), 
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.boardLimitReachedMsg(currentPlan.toUpperCase(), currentPlan == 'free' ? 3 : 5),              
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(l.upgradePlanPrompt),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.cancel, style: TextStyle(color: colorScheme.onSurfaceVariant)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              elevation: 0,
            ),
            onPressed: () {
              final groupProvider = context.read<GroupProvider>();
              // 다이얼로그 닫기
              Navigator.pop(ctx);
              // 결제 페이지 이동 로직 추가 가능
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ChangeNotifierProvider.value(
                  value: groupProvider,
                  child: PlanScreen(groupId: groupId),
                ),
              ));
            },
            child: Text(l.viewPlans),
          ),
        ],
      ),
    );
  }


  void _confirmDelete(
      BuildContext context,
      AppLocalizations l,
      ColorScheme colorScheme,
      GroupService service,
      Map<String, dynamic> board, String groupId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteBoard),
        content: Text(l.deleteBoardConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await service.deleteBoard(
                  groupId, board['id'] as String);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        ok ? l.boardDeleted : l.boardSaveFailed)));
              }
            },
            child: Text(l.delete),
          ),
        ],
      ),
    );
  }
}
