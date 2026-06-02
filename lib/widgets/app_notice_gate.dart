import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_notice.dart';
import '../services/app_notice_service.dart';

class AppNoticeGate extends StatefulWidget {
  final Widget child;

  const AppNoticeGate({
    super.key,
    required this.child,
  });

  @override
  State<AppNoticeGate> createState() => _AppNoticeGateState();
}

class _AppNoticeGateState extends State<AppNoticeGate> {
  final AppNoticeService _noticeService = AppNoticeService();
  bool _didCheck = false;

  @override
  void initState() {
    super.initState();
    print('DEBUG: AppNoticeGate initState called');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('DEBUG: AppNoticeGate postFrameCallback triggered');
      _checkAndShowNotice();
    });
  }

  Future<void> _checkAndShowNotice() async {
    if (_didCheck || !mounted) return;
    _didCheck = true;

    print('DEBUG: AppNoticeGate _checkAndShowNotice started');

    try {
      print('DEBUG: AppNoticeGate calling PackageInfo.fromPlatform()...');
      final packageInfo = await PackageInfo.fromPlatform();
      final buildNumberStr = packageInfo.buildNumber;
      final buildNumber = int.tryParse(buildNumberStr) ?? 0;
      
      print('DEBUG: AppNoticeGate: Platform Build Number: "$buildNumberStr" -> $buildNumber');

      final notice = await _noticeService.fetchStartupNotice(
        currentBuildNumber: buildNumber,
      );

      if (!mounted) {
        debugPrint('AppNoticeGate: Widget unmounted after fetch.');
        return;
      }

      if (notice == null) {
        debugPrint('AppNoticeGate: No notice to display.');
        return;
      }

      debugPrint('AppNoticeGate: Showing dialog for notice: "${notice.title}"');
      await _showNoticeDialog(notice);
    } catch (e, stack) {
      debugPrint('AppNoticeGate Error: $e');
      debugPrint('Stack Trace: $stack');
    }
  }

  Future<void> _showNoticeDialog(AppNotice notice) async {
    if (!mounted) return;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  colors: [
                    colorScheme.surface,
                    colorScheme.primaryContainer.withValues(alpha: 0.15),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            notice.noticeType == AppNoticeType.update
                                ? Icons.system_update_alt_rounded
                                : Icons.campaign_rounded,
                            color: colorScheme.onPrimary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      notice.title,
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  _NoticeTypeChip(notice: notice),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                notice.noticeType == AppNoticeType.update
                                    ? '앱 업데이트 안내'
                                    : '새 공지 확인',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: SingleChildScrollView(
                            child: Text(
                              notice.content,
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.6,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _NoticeMetaRow(notice: notice),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  await _noticeService.markAsRead(notice);
                                  if (dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
                                  }
                                },
                                child: Text(
                                  notice.noticeType == AppNoticeType.update
                                      ? '나중에'
                                      : '닫기',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: () async {
                                  await _handlePrimaryAction(
                                    dialogContext,
                                    notice,
                                  );
                                },
                                child: Text(
                                  notice.noticeType == AppNoticeType.update
                                      ? '업데이트'
                                      : '확인',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handlePrimaryAction(
    BuildContext dialogContext,
    AppNotice notice,
  ) async {
    final url = _resolveNoticeUrl(notice);
    await _noticeService.markAsRead(notice);

    if (dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
    }

    if (url == null || url.isEmpty) return;

    final uri = Uri.tryParse(url);
    if (uri == null || !await canLaunchUrl(uri)) {
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String? _resolveNoticeUrl(AppNotice notice) {
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    return notice.resolveUrl(
      isAndroid: isAndroid,
      isIOS: isIOS,
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _NoticeTypeChip extends StatelessWidget {
  final AppNotice notice;

  const _NoticeTypeChip({
    required this.notice,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final map = <AppNoticeType, ({String label, Color bg, Color fg})>{
      AppNoticeType.update: (
        label: '업데이트',
        bg: colorScheme.errorContainer,
        fg: colorScheme.onErrorContainer,
      ),
      AppNoticeType.event: (
        label: '이벤트',
        bg: colorScheme.secondaryContainer,
        fg: colorScheme.onSecondaryContainer,
      ),
      AppNoticeType.maintenance: (
        label: '점검',
        bg: colorScheme.primaryContainer,
        fg: colorScheme.onPrimaryContainer,
      ),
      AppNoticeType.announcement: (
        label: '공지',
        bg: colorScheme.surfaceContainerHighest,
        fg: colorScheme.onSurfaceVariant,
      ),
    };

    final item = map[notice.noticeType]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: item.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        item.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: item.fg,
        ),
      ),
    );
  }
}

class _NoticeMetaRow extends StatelessWidget {
  final AppNotice notice;

  const _NoticeMetaRow({
    required this.notice,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      _MetaChip(
        icon: Icons.sort_rounded,
        label: '우선순위 ${notice.priority}',
      ),
      if (notice.minAppVersion != null)
        _MetaChip(
          icon: Icons.update_rounded,
          label: '최소 빌드 ${notice.minAppVersion}',
        ),
      if (notice.expiredAt != null)
        _MetaChip(
          icon: Icons.schedule_rounded,
          label: '만료 ${_formatDate(notice.expiredAt)}',
        ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips.isEmpty
          ? [
              _MetaChip(
                icon: Icons.info_outline_rounded,
                label: '추가 정보 없음',
              ),
            ]
          : chips,
    );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
