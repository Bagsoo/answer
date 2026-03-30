import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/group_qr_service.dart';

class GroupQrJoinPreviewScreen extends StatefulWidget {
  const GroupQrJoinPreviewScreen({
    super.key,
    required this.rawValue,
  });

  final String rawValue;

  @override
  State<GroupQrJoinPreviewScreen> createState() =>
      _GroupQrJoinPreviewScreenState();
}

class _GroupQrJoinPreviewScreenState extends State<GroupQrJoinPreviewScreen> {
  final GroupQrService _groupQrService = GroupQrService();

  Map<String, dynamic>? _preview;
  bool _loading = true;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  String _messageFromFunctionError(
    Object error,
    AppLocalizations l,
  ) {
    if (error is FirebaseFunctionsException) {
      return error.message ?? l.saveFailed;
    }
    return l.saveFailed;
  }

  Future<void> _loadPreview() async {
    try {
      final preview = await _groupQrService.fetchPreview(widget.rawValue);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _preview = {'status': 'invalid'};
        _loading = false;
      });
    }
  }

  Future<void> _join() async {
    final l = AppLocalizations.of(context);
    final preview = _preview;
    if (preview == null) return;

    final token = preview['token'] as String? ?? '';
    if (token.isEmpty) return;

    setState(() => _joining = true);
    try {
      final result = await _groupQrService.joinByQr(token);
      if (!mounted) return;

      final status = result['status'] as String? ?? '';
      String message;
      switch (status) {
        case 'joined':
          message = l.joinedSuccess;
          break;
        case 'requested':
          message = l.joinRequestSent;
          break;
        case 'already_member':
          message = l.alreadyJoined;
          break;
        case 'full':
          message = l.groupFull;
          break;
        case 'banned':
          message = l.bannedFromGroup;
          break;
        case 'disabled':
          message = l.qrDisabled;
          break;
        default:
          message = l.joinFailed;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );

      if (status == 'joined' || status == 'requested') {
        Navigator.of(context).pop(true);
        return;
      }

      final refreshed = await _groupQrService.fetchPreview(token);
      if (!mounted) return;
      setState(() => _preview = refreshed);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageFromFunctionError(error, l))),
      );
    } finally {
      if (mounted) {
        setState(() => _joining = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l.qrPreviewTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _QrJoinPreviewCard(
                  preview: _preview ?? {'status': 'invalid'},
                  joining: _joining,
                  onJoin: _join,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(l.qrScan),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.primary,
                  ),
                ),
              ],
            ),
    );
  }
}

class _QrJoinPreviewCard extends StatelessWidget {
  const _QrJoinPreviewCard({
    required this.preview,
    required this.joining,
    required this.onJoin,
  });

  final Map<String, dynamic> preview;
  final bool joining;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final status = preview['status'] as String? ?? 'invalid';

    Widget body;
    if (status == 'invalid') {
      body = Text(
        l.qrInvalid,
        style: TextStyle(color: colorScheme.error),
      );
    } else if (status == 'disabled') {
      body = Text(
        l.qrDisabled,
        style: TextStyle(color: colorScheme.error),
      );
    } else {
      final group = Map<String, dynamic>.from(
        preview['group'] as Map? ?? const <String, dynamic>{},
      );
      final imageUrl = group['profile_image'] as String? ?? '';
      final memberCount = group['member_count'] as int? ?? 0;
      final memberLimit = group['member_limit'] as int? ?? 0;
      final requireApproval = group['require_approval'] as bool? ?? false;
      final isMember = group['is_member'] as bool? ?? false;

      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: colorScheme.primary.withOpacity(0.12),
                backgroundImage:
                    imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
                child: imageUrl.isEmpty
                    ? Icon(Icons.group, color: colorScheme.primary)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group['name'] as String? ?? '',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$memberCount / $memberLimit ${l.people}',
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (requireApproval) ...[
            const SizedBox(height: 12),
            Text(
              l.requiresApproval,
              style: TextStyle(color: colorScheme.primary),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: isMember || joining ? null : onJoin,
              child: joining
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      isMember
                          ? l.alreadyJoined
                          : (requireApproval ? l.requestJoin : l.joinNow),
                    ),
            ),
          ),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.qrPreviewTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            body,
          ],
        ),
      ),
    );
  }
}
