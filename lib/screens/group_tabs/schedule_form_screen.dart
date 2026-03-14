import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/notification_service.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/notification_service.dart';

class ScheduleFormScreen extends StatefulWidget {
  final String groupId;
  final Map<String, dynamic>? existing; // 수정 시 기존 데이터

  const ScheduleFormScreen({
    super.key,
    required this.groupId,
    this.existing,
  });

  @override
  State<ScheduleFormScreen> createState() => _ScheduleFormScreenState();
}

class _ScheduleFormScreenState extends State<ScheduleFormScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  DateTime _startTime = DateTime.now().add(const Duration(hours: 1));
  DateTime _endTime = DateTime.now().add(const Duration(hours: 2));
  bool _saving = false;

  bool get isEdit => widget.existing != null;
  String get currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    if (isEdit) {
      final e = widget.existing!;
      _titleController.text = e['title'] as String? ?? '';
      _descController.text = e['description'] as String? ?? '';
      _startTime = (e['start_time'] as Timestamp?)?.toDate() ?? _startTime;
      _endTime = (e['end_time'] as Timestamp?)?.toDate() ?? _endTime;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final initial = isStart ? _startTime : _endTime;

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

    final picked = DateTime(
        date.year, date.month, date.day, time.hour, time.minute);

    setState(() {
      if (isStart) {
        _startTime = picked;
        if (_endTime.isBefore(_startTime)) {
          _endTime = _startTime.add(const Duration(hours: 1));
        }
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _save(AppLocalizations l) async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.titleRequired)),
      );
      return;
    }
    if (_endTime.isBefore(_startTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.endBeforeStart)),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final col = FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('schedules');

      final data = {
        'title': title,
        'description': _descController.text.trim(),
        'start_time': Timestamp.fromDate(_startTime),
        'end_time': Timestamp.fromDate(_endTime),
        'created_by': currentUserId,
        'updated_at': FieldValue.serverTimestamp(),
      };

      String scheduleId;
      if (isEdit) {
        scheduleId = widget.existing!['id'] as String;
        await col.doc(scheduleId).update(data);
        // 기존 알림 취소
        context.read<NotificationService>().cancelNotification(
            NotificationService.notificationId(scheduleId));
      } else {
        data['created_at'] = FieldValue.serverTimestamp();
        data['rsvp'] = <String, String>{};
        final ref = await col.add(data);
        scheduleId = ref.id;
      }

      // 알림 예약 (15분 전)
      await context.read<NotificationService>().scheduleNotification(
        id: NotificationService.notificationId(scheduleId),
        title: title,
        body: l.scheduleStartingSoon,
        scheduledTime: _startTime,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isEdit ? l.scheduleUpdated : l.scheduleCreated)),
        );
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.saveFailed)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    String _fmt(DateTime dt) =>
        '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}'
        '  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? l.editSchedule : l.addSchedule),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _save(l),
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l.save,
                    style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 제목
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: l.scheduleTitle,
                prefixIcon: const Icon(Icons.title),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),

            // 설명
            TextField(
              controller: _descController,
              decoration: InputDecoration(
                labelText: l.scheduleDescription,
                prefixIcon: const Icon(Icons.notes),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 24),

            // 시작 시간
            _DateTimeTile(
              label: l.startTime,
              value: _fmt(_startTime),
              icon: Icons.play_circle_outline,
              colorScheme: colorScheme,
              onTap: () => _pickDateTime(isStart: true),
            ),
            const SizedBox(height: 12),

            // 종료 시간
            _DateTimeTile(
              label: l.endTime,
              value: _fmt(_endTime),
              icon: Icons.stop_circle_outlined,
              colorScheme: colorScheme,
              onTap: () => _pickDateTime(isStart: false),
            ),

            const SizedBox(height: 12),

            // 알림 안내
            Row(
              children: [
                Icon(Icons.notifications_outlined,
                    size: 14,
                    color: colorScheme.onSurface.withOpacity(0.4)),
                const SizedBox(width: 6),
                Text(
                  l.notificationInfo,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DateTimeTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _DateTimeTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outline.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: colorScheme.primary, size: 20),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurface.withOpacity(0.5))),
                Text(value,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const Spacer(),
            Icon(Icons.edit_calendar_outlined,
                size: 18, color: colorScheme.onSurface.withOpacity(0.4)),
          ],
        ),
      ),
    );
  }
}