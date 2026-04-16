import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../services/my_schedule_service.dart';
import '../models/schedule.dart';
import '../l10n/app_localizations.dart';
import '../widgets/schedule/participant_list_sheet.dart';
import '../providers/group_provider.dart';
import 'group_tabs/schedule_detail_screen.dart';
import 'personal_schedule_form_screen.dart';

class MySchedulesScreen extends StatefulWidget {
  final bool isDesktopMode;
  const MySchedulesScreen({super.key, this.isDesktopMode = false});

  @override
  State<MySchedulesScreen> createState() => _MySchedulesScreenState();
}

class _MySchedulesScreenState extends State<MySchedulesScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _showCalendar = true;
  double? _calendarHeight;
  static const double _calendarMinHeight = 80;

  late Stream<List<Schedule>> _schedulesStream;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;

    // Stream 초기화
    _schedulesStream = context.read<MyScheduleService>().getMySchedules();

    // 기기 변경 등을 고려하여 다가오는 개인 일정 알림 동기화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        context.read<MyScheduleService>().syncPersonalNotifications(l.scheduleStartingSoon);
      }
    });
  }

  List<Schedule> _eventsForDay(DateTime day, List<Schedule> all) {
    return all.where((s) => isSameDay(s.startTime, day)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final service = context.watch<MyScheduleService>();

    return StreamBuilder<List<Schedule>>(
      stream: _schedulesStream,
      builder: (context, snap) {
        final all = snap.data ?? [];
        final selectedEvents = _selectedDay != null
            ? _eventsForDay(_selectedDay!, all)
            : <Schedule>[];

        Map<DateTime, List<Schedule>> eventMap = {};
        for (final s in all) {
          final key = DateTime.utc(s.startTime.year, s.startTime.month, s.startTime.day);
          eventMap.putIfAbsent(key, () => []).add(s);
        }

        return Scaffold(
          backgroundColor: colorScheme.surface,
          floatingActionButton: FloatingActionButton.small(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PersonalScheduleFormScreen()),
            ),
            child: const Icon(Icons.add),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: true,
                          icon: const Icon(Icons.calendar_month, size: 16),
                          label: Text(l.calendar),
                        ),
                        ButtonSegment(
                          value: false,
                          icon: const Icon(Icons.list, size: 16),
                          label: Text(l.list),
                        ),
                      ],
                      selected: {_showCalendar},
                      onSelectionChanged: (v) => setState(() => _showCalendar = v.first),
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    ),
                  ],
                ),
              ),
              if (_showCalendar)
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final totalHeight = constraints.maxHeight;
                      final defaultCalHeight = totalHeight * 0.65;
                      final calHeight = (_calendarHeight ?? defaultCalHeight)
                          .clamp(_calendarMinHeight, totalHeight - 80);
                      final listHeight = totalHeight - calHeight - 12;

                      return Column(
                        children: [
                          SizedBox(
                            height: calHeight,
                            child: SingleChildScrollView(
                              physics: const NeverScrollableScrollPhysics(),
                              child: TableCalendar(
                                firstDay: DateTime.utc(2020, 1, 1),
                                lastDay: DateTime.utc(2030, 12, 31),
                                focusedDay: _focusedDay,
                                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                                eventLoader: (day) => eventMap[DateTime.utc(day.year, day.month, day.day)] ?? [],
                                onDaySelected: (selected, focused) {
                                  setState(() {
                                    _selectedDay = selected;
                                    _focusedDay = focused;
                                  });
                                },
                                onPageChanged: (focused) => setState(() => _focusedDay = focused),
                                calendarStyle: CalendarStyle(
                                  todayDecoration: BoxDecoration(
                                    color: colorScheme.primary.withOpacity(0.3),
                                    shape: BoxShape.circle,
                                  ),
                                  selectedDecoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  markerDecoration: BoxDecoration(
                                    color: colorScheme.tertiary,
                                    shape: BoxShape.circle,
                                  ),
                                  markersMaxCount: 1,
                                  cellMargin: const EdgeInsets.all(2),
                                ),
                                headerStyle: const HeaderStyle(
                                  formatButtonVisible: false,
                                  titleCentered: true,
                                ),
                              ),
                            ),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onVerticalDragUpdate: (details) {
                              setState(() {
                                _calendarHeight = (calHeight + details.delta.dy)
                                    .clamp(_calendarMinHeight, totalHeight - 80);
                              });
                            },
                            onDoubleTap: () => setState(() => _calendarHeight = null),
                            child: Container(
                              height: 12,
                              color: Colors.transparent,
                              child: Center(
                                child: Container(
                                  width: 36,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: colorScheme.outline.withOpacity(0.4),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            height: listHeight,
                            child: _selectedDay == null
                                ? Center(child: Text(l.selectDayToSeeSchedules, style: TextStyle(color: colorScheme.onSurface.withOpacity(0.4))))
                                : selectedEvents.isEmpty
                                    ? Center(child: Text(l.noSchedulesOnDay, style: TextStyle(color: colorScheme.onSurface.withOpacity(0.4))))
                                    : _ScheduleListView(schedules: selectedEvents),
                          ),
                        ],
                      );
                    },
                  ),
                )
              else
                Expanded(
                  child: all.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.event_note, size: 64, color: colorScheme.onSurface.withOpacity(0.2)),
                              const SizedBox(height: 16),
                              Text(l.noSchedules, style: TextStyle(color: colorScheme.onSurface.withOpacity(0.4))),
                            ],
                          ),
                        )
                      : _ScheduleListView(schedules: all),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ScheduleListView extends StatelessWidget {
  final List<Schedule> schedules;
  const _ScheduleListView({required this.schedules});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: schedules.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        final s = schedules[index];
        final isPersonal = s.type == ScheduleType.personal;
        final isUpcoming = s.startTime.isAfter(DateTime.now());

        return ListTile(
          onTap: () {
            if (isPersonal) {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => PersonalScheduleFormScreen(existing: s)),
              );
            } else {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChangeNotifierProvider(
                    create: (_) => GroupProvider(s.groupId ?? ''),
                    child: ScheduleDetailScreen(
                      groupId: s.groupId ?? '',
                      scheduleId: s.id,
                      canEdit: false, // Group schedules from here are view-only usually, or depends on rsvp
                    ),
                  ),
                ),
              );
            }
          },
          leading: Container(
            width: 48,
            decoration: BoxDecoration(
              color: isUpcoming ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${s.startTime.month}/${s.startTime.day}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isUpcoming ? colorScheme.onPrimaryContainer : colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
                Text(
                  '${s.startTime.hour.toString().padLeft(2, '0')}:${s.startTime.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isUpcoming ? colorScheme.onPrimaryContainer : colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          title: Text(
            s.title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isUpcoming ? colorScheme.onSurface : colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          subtitle: Text(
            isPersonal ? l.personalSchedule : (s.groupName ?? l.groupSchedule),
            style: TextStyle(
              fontSize: 12,
              color: isPersonal ? colorScheme.secondary : colorScheme.tertiary,
            ),
          ),
          trailing: isPersonal ? const Icon(Icons.person_outline, size: 16) : const Icon(Icons.groups_outlined, size: 16),
        );
      },
    );
  }
}
