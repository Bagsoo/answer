import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/group_provider.dart';
import '../../providers/user_provider.dart';
import '../../screens/group_tabs/plan_screen.dart';
import '../../services/group_service.dart';
import '../../services/local_preferences_service.dart';

class GroupNoticeSheet extends StatefulWidget {
  final String groupId;

  const GroupNoticeSheet({
    super.key,
    required this.groupId,
  });

  @override
  State<GroupNoticeSheet> createState() => _GroupNoticeSheetState();
}

class _GroupNoticeSheetState extends State<GroupNoticeSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _saving = false;
  late final String _prefsUserId;

  String get _draftKey => LocalPreferencesService.groupNoticeDraftKey(
        _prefsUserId,
        widget.groupId,
      );

  @override
  void initState() {
    super.initState();
    _prefsUserId = context.read<UserProvider>().uid;
    _controller.addListener(_persistDraft);
    _loadDraft();
  }

  @override
  void dispose() {
    _persistDraft();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadDraft() async {
    final draft = await LocalPreferencesService.getString(_draftKey);
    if (!mounted || draft == null || draft.isEmpty) return;
    _controller.text = draft;
    _controller.selection = TextSelection.collapsed(offset: draft.length);
  }

  void _persistDraft() {
    LocalPreferencesService.setString(_draftKey, _controller.text);
  }

  Future<void> _clearDraft() async {
    await LocalPreferencesService.remove(_draftKey);
  }

  Future<void> _submitNotice() async {
    final l = AppLocalizations.of(context);
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.noticeContentRequired)),
      );
      return;
    }

    setState(() => _saving = true);
    final success = await context.read<GroupService>().createGroupNotice(
          groupId: widget.groupId,
          text: text,
          authorName: context.read<UserProvider>().name,
        );
    if (!mounted) return;

    setState(() => _saving = false);
    if (success) {
      _controller.clear();
      await _clearDraft();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.noticePosted)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.noticePostFailed)),
      );
    }
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final gp = context.watch<GroupProvider>();
    final canWriteNotice = gp.plan == 'pro' && gp.canEditGroupInfo;
    final shouldShowUpgrade = gp.plan != 'pro';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: context.read<GroupService>().streamGroupNotices(widget.groupId),
          builder: (context, snapshot) {
            final notices = snapshot.data ?? const <Map<String, dynamic>>[];
            final latest = notices.isNotEmpty ? notices.first : null;

            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 16),
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.onSurface.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(Icons.campaign_outlined,
                          color: colorScheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        l.groupNotice,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (canWriteNotice) ...[
                    Text(
                      l.writeNotice,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _controller,
                      minLines: 3,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: l.noticeInputHint,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _submitNotice,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.campaign),
                        label: Text(l.postNotice),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ] else if (shouldShowUpgrade) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colorScheme.primary.withOpacity(0.12),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.workspace_premium_outlined,
                                  size: 18, color: colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                l.noticeProOnlyTitle,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l.noticeProOnlyDescription,
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onPrimaryContainer
                                  .withOpacity(0.8),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonal(
                            onPressed: () {
                              final gp = context.read<GroupProvider>();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ChangeNotifierProvider.value(
                                    value: gp,
                                    child: PlanScreen(groupId: widget.groupId),
                                  ),
                                ),
                              );
                            },
                            child: Text(l.viewPlans),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        l.noticeNoPermission,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  Text(
                    l.currentNotice,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      latest == null)
                    const Center(child: CircularProgressIndicator())
                  else if (latest == null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        l.noNotices,
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.55),
                        ),
                      ),
                    )
                  else
                    _NoticeCard(
                      text: latest['text'] as String? ?? '',
                      authorName: latest['author_name'] as String? ?? l.unknown,
                      dateText: _formatDate(latest['created_at'] as Timestamp?),
                      highlight: true,
                    ),
                  const SizedBox(height: 18),
                  Text(
                    l.noticeHistory,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (notices.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        l.noNotices,
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.55),
                        ),
                      ),
                    )
                  else
                    ...notices.map(
                      (notice) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _NoticeCard(
                          text: notice['text'] as String? ?? '',
                          authorName:
                              notice['author_name'] as String? ?? l.unknown,
                          dateText:
                              _formatDate(notice['created_at'] as Timestamp?),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final String text;
  final String authorName;
  final String dateText;
  final bool highlight;

  const _NoticeCard({
    required this.text,
    required this.authorName,
    required this.dateText,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlight
            ? colorScheme.primaryContainer.withOpacity(0.45)
            : colorScheme.surfaceContainerHighest.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: highlight
            ? Border.all(color: colorScheme.primary.withOpacity(0.18))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.person_outline,
                size: 14,
                color: colorScheme.onSurface.withOpacity(0.45),
              ),
              const SizedBox(width: 5),
              Text(
                authorName,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withOpacity(0.55),
                ),
              ),
              const Spacer(),
              Text(
                dateText,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurface.withOpacity(0.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
