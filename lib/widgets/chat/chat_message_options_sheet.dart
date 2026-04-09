import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/report_service.dart';
import '../../utils/message_share_formatter.dart';
import '../../screens/report_dialog.dart';

class ChatMessageOptionsSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  final String messageId;
  final bool isMe;
  final String roomId;
  final VoidCallback onReply;
  final VoidCallback onPin;
  final VoidCallback onMemo;
  final bool canHideMessage;
  final VoidCallback? onHide;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const ChatMessageOptionsSheet({
    super.key,
    required this.data,
    required this.messageId,
    required this.isMe,
    required this.roomId,
    required this.onReply,
    required this.onPin,
    required this.onMemo,
    this.canHideMessage = false,
    this.onHide,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final text = data['text'] as String? ?? '';

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (text.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:
                      colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withOpacity(0.7)),
                ),
              ),
            ListTile(
              leading:
                  Icon(Icons.reply_outlined, color: colorScheme.primary),
              title: Text(l.replyMessage),
              onTap: () {
                Navigator.pop(context);
                onReply();
              },
            ),
            ListTile(
              leading: Icon(Icons.campaign_outlined,
                  color: colorScheme.primary),
              title: Text(l.pinAsNotice),
              onTap: () {
                Navigator.pop(context);
                onPin();
              },
            ),
            ListTile(
              leading: Icon(Icons.copy_outlined,
                  color: colorScheme.onSurface.withOpacity(0.7)),
              title: Text(l.copyMessage),
              onTap: () {
                Clipboard.setData(ClipboardData(text: text));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.messageCopied)));
              },
            ),
            ListTile(
              leading: Icon(Icons.note_outlined,
                  color: colorScheme.onSurface.withOpacity(0.7)),
              title: Text(l.memoMessage),
              onTap: () {
                Navigator.pop(context);
                onMemo();
              },
            ),
            ListTile(
              leading: Icon(Icons.share_outlined,
                  color: colorScheme.onSurface.withOpacity(0.7)),
              title: Text(l.shareMessage),
              onTap: () {
                Navigator.pop(context);
                final shareText = MessageShareFormatter.format(data, l);
                Share.share(shareText);
              },
            ),
            if (isMe && data['is_deleted'] != true && data['is_hidden'] != true) ...[
              if (data['type'] == 'text')
                ListTile(
                  leading: Icon(Icons.edit_outlined,
                      color: colorScheme.onSurface.withOpacity(0.7)),
                  title: Text(l.editMessage),
                  onTap: () {
                    Navigator.pop(context);
                    if (onEdit != null) onEdit!();
                  },
                ),
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: colorScheme.error),
                title: Text(l.deleteMessage, style: TextStyle(color: colorScheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  if (onDelete != null) onDelete!();
                },
              ),
            ],
            if (!isMe)
              ListTile(
                leading:
                    Icon(Icons.flag_outlined, color: colorScheme.error),
                title: Text(l.reportMessage,
                    style: TextStyle(color: colorScheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  showReportDialog(
                    context: context,
                    onSubmit: (reason, otherText) =>
                        context.read<ReportService>().reportMessage(
                      messageId: messageId,
                      targetOwnerId:
                          data['sender_id'] as String? ?? '',
                      roomId: roomId,
                      reason: reason,
                      otherText: otherText,
                    ),
                  );
                },
              ),
            if (canHideMessage)
              ListTile(
                leading: Icon(Icons.visibility_off_outlined,
                    color: colorScheme.error),
                title: Text(l.hideMessage,
                    style: TextStyle(color: colorScheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  if (onHide != null) onHide!();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
