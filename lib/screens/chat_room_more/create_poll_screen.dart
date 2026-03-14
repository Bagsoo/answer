import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/poll_service.dart';
import '../../services/chat_service.dart';

class CreatePollScreen extends StatefulWidget {
  final String roomId;

  const CreatePollScreen({super.key, required this.roomId});

  @override
  State<CreatePollScreen> createState() => _CreatePollScreenState();
}

class _CreatePollScreenState extends State<CreatePollScreen> {
  final _titleController = TextEditingController();
  String _type = 'regular'; // 'regular' | 'date'
  bool _isAnonymous = false;
  bool _isMultiple = false;
  bool _hasDeadline = false;
  DateTime? _endsAt;

  // 일반 투표 선택지
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  // 날짜 투표 선택지
  final List<DateTime> _dateOptions = [];

  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    for (final c in _optionControllers) c.dispose();
    super.dispose();
  }

  // ── 날짜 선택지 추가 ──────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null || !mounted) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() => _dateOptions.add(dt));
  }

  // ── 마감 시간 선택 ────────────────────────────────────────────────────────
  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 23, minute: 59),
    );
    if (time == null || !mounted) return;
    setState(() {
      _endsAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  // ── 제출 ─────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    List<String> options;
    if (_type == 'date') {
      if (_dateOptions.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.pollMinOptions)),
        );
        return;
      }
      options = _dateOptions.map((d) => d.toIso8601String()).toList();
    } else {
      final filled = _optionControllers.map((c) => c.text.trim()).toList();
      if (filled.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.pollMinOptions)),
        );
        return;
      }
      if (filled.any((o) => o.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.pollEmptyOption)),
        );
        return;
      }
      options = filled;
    }

    setState(() => _submitting = true);
    final myName = context.read<UserProvider>().name;
    final pollService = context.read<PollService>();
    final chatService = context.read<ChatService>();

    final pollId = await pollService.createPoll(
      roomId: widget.roomId,
      title: title,
      type: _type,
      isAnonymous: _isAnonymous,
      isMultiple: _isMultiple,
      options: options,
      endsAt: _hasDeadline ? _endsAt : null,
      creatorName: myName,
    );

    if (!mounted) return;
    if (pollId == null) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('투표 생성에 실패했습니다.')),
      );
      return;
    }

    // 채팅방에 투표 메시지 전송
    final emoji = _type == 'date' ? '📅' : '📊';
    await chatService.sendMessage(
      widget.roomId,
      '$emoji $title',
      senderName: myName,
      pollId: pollId,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.pollCreated)),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.createPoll),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l.pollSubmit,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    )),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── 질문 입력 ───────────────────────────────────────────────────
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: l.pollTitle,
                hintText: l.pollTitleHint,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
              ),
              maxLength: 100,
              maxLines: 2,
              minLines: 1,
            ),
            const SizedBox(height: 20),

            // ── 투표 타입 ────────────────────────────────────────────────────
            _SectionLabel(label: '투표 유형'),
            Row(children: [
              Expanded(
                child: _TypeChip(
                  label: l.pollTypeRegular,
                  icon: Icons.poll_outlined,
                  selected: _type == 'regular',
                  onTap: () => setState(() {
                    _type = 'regular';
                    _dateOptions.clear();
                  }),
                  colorScheme: colorScheme,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TypeChip(
                  label: l.pollTypeDate,
                  icon: Icons.calendar_today_outlined,
                  selected: _type == 'date',
                  onTap: () => setState(() {
                    _type = 'date';
                    for (final c in _optionControllers) c.clear();
                  }),
                  colorScheme: colorScheme,
                ),
              ),
            ]),
            const SizedBox(height: 20),

            // ── 옵션 설정 ────────────────────────────────────────────────────
            Row(children: [
              Expanded(
                child: SwitchListTile(
                  value: _isAnonymous,
                  onChanged: (v) => setState(() => _isAnonymous = v),
                  title: Text(l.pollAnonymous, style: const TextStyle(fontSize: 14)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: colorScheme.primary,
                ),
              ),
              Expanded(
                child: SwitchListTile(
                  value: _isMultiple,
                  onChanged: (v) => setState(() => _isMultiple = v),
                  title: Text(l.pollMultiple, style: const TextStyle(fontSize: 14)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: colorScheme.primary,
                ),
              ),
            ]),
            const SizedBox(height: 20),

            // ── 선택지 ───────────────────────────────────────────────────────
            _SectionLabel(label: l.pollOptions),
            const SizedBox(height: 8),

            if (_type == 'regular') ...[
              // 일반 투표 선택지
              ...List.generate(_optionControllers.length, (i) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _optionControllers[i],
                        decoration: InputDecoration(
                          hintText: '선택지 ${i + 1}',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        maxLength: 60,
                        buildCounter: (_, {required currentLength,
                                required isFocused, maxLength}) => null,
                      ),
                    ),
                    if (_optionControllers.length > 2)
                      IconButton(
                        icon: Icon(Icons.remove_circle_outline,
                            color: colorScheme.error),
                        onPressed: () => setState(() {
                          _optionControllers[i].dispose();
                          _optionControllers.removeAt(i);
                        }),
                      ),
                  ]),
                );
              }),
              if (_optionControllers.length < 10)
                TextButton.icon(
                  onPressed: () => setState(
                      () => _optionControllers.add(TextEditingController())),
                  icon: const Icon(Icons.add),
                  label: Text(l.pollAddOption),
                ),
            ] else ...[
              // 날짜 투표 선택지
              ..._dateOptions.asMap().entries.map((e) {
                final dt = e.value;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(Icons.event, color: colorScheme.primary),
                    title: Text(_formatDateTime(dt)),
                    trailing: IconButton(
                      icon: Icon(Icons.close, color: colorScheme.error, size: 18),
                      onPressed: () => setState(() => _dateOptions.removeAt(e.key)),
                    ),
                  ),
                );
              }),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.add),
                label: Text(l.pollAddDate),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ── 마감 시간 ─────────────────────────────────────────────────────
            _SectionLabel(label: l.pollEndsAt),
            SwitchListTile(
              value: _hasDeadline,
              onChanged: (v) => setState(() {
                _hasDeadline = v;
                if (!v) _endsAt = null;
              }),
              title: Text(
                _hasDeadline && _endsAt != null
                    ? _formatDateTime(_endsAt!)
                    : l.pollNoDeadline,
                style: const TextStyle(fontSize: 14),
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: colorScheme.primary,
            ),
            if (_hasDeadline)
              TextButton.icon(
                onPressed: _pickDeadline,
                icon: const Icon(Icons.schedule),
                label: Text(_endsAt != null ? _formatDateTime(_endsAt!) : '날짜 선택'),
              ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final pad = (int n) => n.toString().padLeft(2, '0');
    return '${dt.year}.${pad(dt.month)}.${pad(dt.day)} '
        '${pad(dt.hour)}:${pad(dt.minute)}';
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) => Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
        ),
      );
}

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const _TypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? Border.all(color: colorScheme.primary, width: 2)
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurface.withOpacity(0.5)),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    selected ? FontWeight.bold : FontWeight.normal,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}