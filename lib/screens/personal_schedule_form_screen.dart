import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/my_schedule_service.dart';
import '../services/notification_service.dart';
import '../models/schedule.dart';
import '../l10n/app_localizations.dart';
import '../providers/user_provider.dart';
import '../widgets/common/location_picker_sheet.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class PersonalScheduleFormScreen extends StatefulWidget {
  final Schedule? existing;
  const PersonalScheduleFormScreen({super.key, this.existing});

  @override
  State<PersonalScheduleFormScreen> createState() => _PersonalScheduleFormScreenState();
}

class _PersonalScheduleFormScreenState extends State<PersonalScheduleFormScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _costController = TextEditingController();
  
  DateTime _startTime = DateTime.now().add(const Duration(hours: 1));
  DateTime _endTime = DateTime.now().add(const Duration(hours: 2));
  Map<String, dynamic>? _location;
  bool _saving = false;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (isEdit) {
      final e = widget.existing!;
      _titleController.text = e.title;
      _descController.text = e.description;
      _costController.text = e.cost;
      _startTime = e.startTime;
      _endTime = e.endTime;
      _location = e.location;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _costController.dispose();
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
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;

    setState(() {
      final picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
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

  Future<void> _pickLocation() async {
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
    final locale = context.read<UserProvider>().locale;

    final result = await showModalBottomSheet<LocationResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => LocationPickerSheet(googleApiKey: apiKey, languageCode: locale),
    );

    if (result != null) {
      setState(() {
        _location = {
          'name': result.name,
          'address': result.address,
          'lat': result.latitude,
          'lng': result.longitude,
        };
      });
    }
  }

  Future<void> _handleSave() async {
    final title = _titleController.text.trim();
    final l = AppLocalizations.of(context);
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.titleRequired)));
      return;
    }
    if (_endTime.isBefore(_startTime)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.endBeforeStart)));
      return;
    }

    setState(() => _saving = true);
    try {
      final service = context.read<MyScheduleService>();
      final data = {
        'title': title,
        'description': _descController.text.trim(),
        'cost': _costController.text.trim(),
        'start_time': _startTime,
        'end_time': _endTime,
        'location': _location,
      };
      
      final docId = await service.savePersonalSchedule(data, id: widget.existing?.id);
      
      // 알림 설정
      final notif = NotificationService();
      final id = NotificationService.notificationId(docId);
      await notif.scheduleNotification(
        id: id,
        title: title,
        body: l.scheduleStartingSoon,
        scheduledTime: _startTime,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEdit ? l.personalScheduleUpdated : l.personalScheduleCreated)));
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.saveFailed)));
    }
  }

  Future<void> _handleDelete() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.delete),
        content: Text(l.deleteScheduleConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      final scheduleId = widget.existing!.id;
      await context.read<MyScheduleService>().deletePersonalSchedule(scheduleId);
      
      // 알림 취소
      await NotificationService().cancelNotification(NotificationService.notificationId(scheduleId));

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.personalScheduleDeleted)));
      }
    } catch (_) {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final locale = context.watch<UserProvider>().locale;

    String fmt(DateTime dt) => DateFormat.yMd(locale).add_Hm().format(dt);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? l.editSchedule : l.addSchedule),
        actions: [
          if (isEdit) IconButton(icon: Icon(Icons.delete_outline, color: cs.error), onPressed: _saving ? null : _handleDelete),
          TextButton(
            onPressed: _saving ? null : _handleSave,
            child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(l.save, style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(controller: _titleController, decoration: InputDecoration(labelText: l.scheduleTitle, prefixIcon: const Icon(Icons.title))),
            const SizedBox(height: 16),
            TextField(controller: _descController, decoration: InputDecoration(labelText: l.scheduleDescription, prefixIcon: const Icon(Icons.notes)), maxLines: 3),
            const SizedBox(height: 16),
            TextField(controller: _costController, decoration: InputDecoration(labelText: l.scheduleCost, prefixIcon: const Icon(Icons.wallet_outlined))),
            const SizedBox(height: 24),
            _DateTimeTile(label: l.startTime, value: fmt(_startTime), icon: Icons.play_circle_outline, onTap: () => _pickDateTime(isStart: true)),
            const SizedBox(height: 12),
            _DateTimeTile(label: l.endTime, value: fmt(_endTime), icon: Icons.stop_circle_outlined, onTap: () => _pickDateTime(isStart: false)),
            const SizedBox(height: 24),
            InkWell(
              onTap: _pickLocation,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(border: Border.all(color: cs.outline.withOpacity(0.4)), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Icon(Icons.place_outlined, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_location?['name'] ?? l.location, style: TextStyle(color: _location == null ? cs.onSurface.withOpacity(0.4) : cs.onSurface))),
                    Icon(Icons.chevron_right, color: cs.onSurface.withOpacity(0.4)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: cs.onSurface.withOpacity(0.5)),
                const SizedBox(width: 8),
                Expanded(child: Text(l.notificationInfo, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5)))),
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
  final VoidCallback onTap;
  const _DateTimeTile({required this.label, required this.value, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(border: Border.all(color: cs.outline.withOpacity(0.4)), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, color: cs.primary, size: 20),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5))),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const Spacer(),
            Icon(Icons.edit_calendar_outlined, size: 18, color: cs.onSurface.withOpacity(0.4)),
          ],
        ),
      ),
    );
  }
}
