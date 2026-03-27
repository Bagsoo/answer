import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

class ChatScheduledMessageSheet extends StatefulWidget {
  final String roomId;
  final String currentUserId;
  final String senderName;
  final String initialText;

  const ChatScheduledMessageSheet({
    super.key,
    required this.roomId,
    required this.currentUserId,
    required this.senderName,
    this.initialText = '',
  });

  @override
  State<ChatScheduledMessageSheet> createState() =>
      _ChatScheduledMessageSheetState();
}

class _ChatScheduledMessageSheetState
    extends State<ChatScheduledMessageSheet> {
  final _controller = TextEditingController();
  DateTime? _selectedDateTime;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialText;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final l = AppLocalizations.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today.subtract(const Duration(days: 1)),
      lastDate: today.add(const Duration(days: 30)),
      selectableDayPredicate: (day) => !day.isBefore(today),
    );
    if (date == null || !mounted) return;
    final time =
        await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null || !mounted) return;

    final picked = DateTime(
        date.year, date.month, date.day, time.hour, time.minute);
    if (picked.isBefore(now.add(const Duration(minutes: 1)))) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.scheduledTimeMin)));
      return;
    }
    setState(() => _selectedDateTime = picked);
  }

  String _formatDateTime(DateTime dt) =>
      '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(children: [
              Icon(Icons.schedule_send_outlined,
                  color: colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(l.scheduledMessage,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 4,
              minLines: 2,
              maxLength: 2000,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              decoration: InputDecoration(
                hintText: l.scheduledMessageHint,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor:
                    colorScheme.surfaceContainerHighest.withOpacity(0.4),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDateTime,
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text(_selectedDateTime != null
                  ? _formatDateTime(_selectedDateTime!)
                  : l.selectSendTime),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                foregroundColor: _selectedDateTime != null
                    ? colorScheme.primary
                    : colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final text = _controller.text.trim();
                if (text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.scheduledMessageEmpty)));
                  return;
                }
                if (_selectedDateTime == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.scheduledTimeEmpty)));
                  return;
                }
                await FirebaseFirestore.instance
                    .collection('chat_rooms')
                    .doc(widget.roomId)
                    .collection('scheduled_messages')
                    .add({
                  'text': text,
                  'sender_id': widget.currentUserId,
                  'sender_name': widget.senderName,
                  'scheduled_at': Timestamp.fromDate(_selectedDateTime!),
                  'sent': false,
                  'created_at': FieldValue.serverTimestamp(),
                });
                if (context.mounted) {
                  Navigator.pop(context, true);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(l.scheduledAt(_formatDateTime(_selectedDateTime!))),
                  ));
                }
              },
              child: Text(l.scheduledRegister),
            ),
          ],
        ),
      ),
    );
  }
}
