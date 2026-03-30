import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/group_provider.dart';
import '../../services/group_qr_service.dart';
import 'plan_screen.dart';

class GroupQrScreen extends StatefulWidget {
  const GroupQrScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupQrScreen> createState() => _GroupQrScreenState();
}

class _GroupQrScreenState extends State<GroupQrScreen> {
  final GroupQrService _groupQrService = GroupQrService();

  bool _busy = false;

  bool get _mounted => mounted;

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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

  Future<void> _setQrEnabled(bool enabled) async {
    final l = AppLocalizations.of(context);
    final gp = context.read<GroupProvider>();

    setState(() => _busy = true);
    try {
      await _groupQrService.setEnabled(gp.groupId, enabled);
      if (!_mounted) return;
      _showSnackBar(l.qrSettingsUpdated);
    } catch (error) {
      if (!_mounted) return;
      _showSnackBar(_messageFromFunctionError(error, l));
    } finally {
      if (_mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _regenerateQr() async {
    final l = AppLocalizations.of(context);
    final gp = context.read<GroupProvider>();

    setState(() => _busy = true);
    try {
      await _groupQrService.regenerate(gp.groupId);
      if (!_mounted) return;
      _showSnackBar(l.qrRegenerated);
    } catch (error) {
      if (!_mounted) return;
      _showSnackBar(_messageFromFunctionError(error, l));
    } finally {
      if (_mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final gp = context.watch<GroupProvider>();
    final canManageQr =
        gp.isOwner || gp.canEditGroupInfo || gp.canManagePermissions;

    return Scaffold(
      appBar: AppBar(title: Text(l.groupQr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!gp.isPaidPlan) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.upgradePlanPrompt,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        final groupProvider = context.read<GroupProvider>();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChangeNotifierProvider.value(
                              value: groupProvider,
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
            ),
          ] else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.groupQrDescription,
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l.qrEnableJoin),
                      value: gp.qrEnabled,
                      onChanged: canManageQr && !_busy ? _setQrEnabled : null,
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: colorScheme.outline.withOpacity(0.3),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: gp.inviteToken.isNotEmpty
                                ? Opacity(
                                    opacity: gp.qrEnabled ? 1 : 0.35,
                                    child: QrImageView(
                                      data: _groupQrService
                                          .buildQrData(gp.inviteToken),
                                      eyeStyle: const QrEyeStyle(
                                        eyeShape: QrEyeShape.square,
                                        color: Colors.black,
                                      ),
                                      dataModuleStyle: const QrDataModuleStyle(
                                        color: Colors.black,
                                        dataModuleShape:
                                            QrDataModuleShape.square,
                                      ),
                                    ),
                                  )
                                : Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Text(
                                        l.qrNotGenerated,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: colorScheme.onSurface
                                              .withOpacity(0.6),
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                canManageQr && !_busy ? _regenerateQr : null,
                            icon: const Icon(Icons.refresh),
                            label: Text(l.qrRegenerate),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ],
      ),
    );
  }
}
