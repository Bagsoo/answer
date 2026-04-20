import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter/rendering.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/group_provider.dart';
import 'schedule_form_screen.dart';
import 'schedule_detail_screen.dart';

class SchedulesTab extends StatefulWidget {
  final bool isDesktopMode;
  final String? selectedScheduleId;
  final ValueChanged<Map<String, dynamic>>? onScheduleSelected;

  const SchedulesTab({
    super.key,
    this.isDesktopMode = false,
    this.selectedScheduleId,
    this.onScheduleSelected,
  });

  @override
  State<SchedulesTab> createState() => _SchedulesTabState();
}

class _SchedulesTabState extends State<SchedulesTab> {
  final ScrollController _scrollController = ScrollController();
  bool _fabVisible = true;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _showCalendar = true;

  // 드래그로 조절되는 캘린더 높이 (null이면 기본값 사용)
  double? _calendarHeight;
  // 캘린더 최소/최대 높이
  static const double _calendarMinHeight = 80;

  String get currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final isScrollingDown = _scrollController.position.userScrollDirection
        == ScrollDirection.reverse;
    final isScrollingUp = _scrollController.position.userScrollDirection
        == ScrollDirection.forward;

    if (isScrollingDown && _fabVisible) {
      setState(() => _fabVisible = false);
    } else if (isScrollingUp && !_fabVisible) {
      setState(() => _fabVisible = true);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Stream<List<Map<String, dynamic>>> _schedulesStream(String groupId) {
    if (groupId.isEmpty) return Stream.value([]);

    return FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('schedules')
        .snapshots()
        .map((snap) {
          final all = <Map<String, dynamic>>[];
          for (var doc in snap.docs) {
            final data = doc.data() as Map<String, dynamic>;
            data['id'] = doc.id;
            all.add(data);
          }
          all.sort((a, b) {
            final t1 = a['start_time'] as Timestamp?;
            final t2 = b['start_time'] as Timestamp?;
            if (t1 == null || t2 == null) return 0;
            return t1.compareTo(t2);
          });
          return all;
        });
  }

  List<Map<String, dynamic>> _eventsForDay(
      DateTime day, List<Map<String, dynamic>> all) {
    return all.where((s) {
      final start = (s['start_time'] as Timestamp?)?.toDate();
      if (start == null) return false;
      return isSameDay(start, day);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    final gp = context.watch<GroupProvider>();
    final groupId = gp.groupId;
    final canCreateSchedule = gp.canPostSchedule;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _schedulesStream(groupId),
      builder: (context, snap) {
        final all = snap.data ?? [];
        final selectedEvents = _selectedDay != null
            ? _eventsForDay(_selectedDay!, all)
            : <Map<String, dynamic>>[];

        // 날짜별 이벤트 맵 (점 표시용 — 있으면 1개, 없으면 빈 리스트)
        Map<DateTime, List<Map<String, dynamic>>> eventMap = {};
        for (final s in all) {
          final start = (s['start_time'] as Timestamp?)?.toDate();
          if (start == null) continue;
          final key = DateTime(start.year, start.month, start.day);
          // 이미 key가 있으면 추가하지 않음 → 항상 1개짜리 리스트 유지
          eventMap[key] = [s];
        }

        return Scaffold(
          backgroundColor: colorScheme.surface,
          floatingActionButton: canCreateSchedule
            ? AnimatedSlide(
                offset: _fabVisible ? Offset.zero : const Offset(0, 2),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: AnimatedOpacity(
                  opacity: _fabVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: FloatingActionButton(
                    onPressed: () {
                      final gp = context.read<GroupProvider>();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChangeNotifierProvider.value(
                            value: gp,
                            child: ScheduleFormScreen(groupId: groupId),
                          ),
                        ),
                      );
                    },
                    child: const Icon(Icons.add),
                  ),
                ),
              )
            : null,
          body: Column(
            children: [
              // ── 캘린더 / 리스트 토글 ─────────────────────────────
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
                      onSelectionChanged: (v) =>
                          setState(() => _showCalendar = v.first),
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),

              // ── 캘린더 뷰 ────────────────────────────────────────
              if (_showCalendar)
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final totalHeight = constraints.maxHeight;
                      // 기본 캘린더 높이: 전체의 70% (달력 전체가 보이도록)
                      final defaultCalHeight = totalHeight * 0.70;
                      final calHeight = (_calendarHeight ?? defaultCalHeight)
                          .clamp(_calendarMinHeight, totalHeight - 80);
                      final listHeight = totalHeight - calHeight - 12; // 12 = divider 영역

                      return Column(
                        children: [
                          // 캘린더
                          SizedBox(
                            height: calHeight,
                            child: SingleChildScrollView(
                              physics: const NeverScrollableScrollPhysics(),
                              child: TableCalendar(
                                firstDay: DateTime.utc(2020, 1, 1),
                                lastDay: DateTime.utc(2030, 12, 31),
                                focusedDay: _focusedDay,
                                selectedDayPredicate: (day) =>
                                    isSameDay(_selectedDay, day),
                                // 이벤트 로더: 있으면 [dummy] 1개, 없으면 []
                                eventLoader: (day) {
                                  final key = DateTime(
                                      day.year, day.month, day.day);
                                  return eventMap[key] ?? [];
                                },
                                onDaySelected: (selected, focused) {
                                  setState(() {
                                    _selectedDay = selected;
                                    _focusedDay = focused;
                                  });
                                },
                                onPageChanged: (focused) =>
                                    setState(() => _focusedDay = focused),
                                calendarStyle: CalendarStyle(
                                  todayDecoration: BoxDecoration(
                                    color: colorScheme.primary
                                        .withOpacity(0.3),
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
                                  // 날짜 셀 여백 축소
                                  cellMargin: const EdgeInsets.all(2),
                                  cellPadding: EdgeInsets.zero,
                                ),
                                daysOfWeekStyle: const DaysOfWeekStyle(
                                  // 요일 행 높이 축소
                                  decoration: BoxDecoration(),
                                ),
                                headerStyle: HeaderStyle(
                                  formatButtonVisible: false,
                                  titleCentered: true,
                                  // 헤더 여백 축소
                                  headerPadding: const EdgeInsets.symmetric(vertical: 0),
                                  titleTextStyle: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // ── 드래그 가능한 Divider ─────────────────
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onVerticalDragUpdate: (details) {
                              setState(() {
                                _calendarHeight = (calHeight +
                                        details.delta.dy)
                                    .clamp(
                                        _calendarMinHeight, totalHeight - 80);
                              });
                            },
                            onDoubleTap: () {
                              setState(() => _calendarHeight = null);
                            },
                            child: Container(
                              height: 12, // 20 → 12으로 축소
                              color: Colors.transparent,
                              child: Center(
                                child: Container(
                                  width: 36,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: colorScheme.outline
                                        .withOpacity(0.4),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // ── 선택된 날의 일정 목록 ─────────────────
                          SizedBox(
                            height: listHeight,
                            child: _selectedDay == null
                                ? Center(
                                    child: Text(
                                      l.selectDayToSeeSchedules,
                                      style: TextStyle(
                                          color: colorScheme.onSurface
                                              .withOpacity(0.4)),
                                    ),
                                  )
                                : selectedEvents.isEmpty
                                    ? Center(
                                        child: Text(
                                          l.noSchedulesOnDay,
                                          style: TextStyle(
                                              color: colorScheme.onSurface
                                                  .withOpacity(0.4)),
                                        ),
                                      )
                                    : _ScheduleList(
                                        schedules: selectedEvents,
                                        groupId: groupId,
                                        currentUserId: currentUserId,
                                        canCreateSchedule: canCreateSchedule,
                                        isDesktopMode: widget.isDesktopMode,
                                        selectedScheduleId: widget.selectedScheduleId,
                                        onScheduleSelected: widget.onScheduleSelected,
                                        scrollController: _scrollController,
                                      ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

              // ── 리스트 뷰 ────────────────────────────────────────
              if (!_showCalendar)
                Expanded(
                  child: all.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.event_note,
                                  size: 64,
                                  color:
                                      colorScheme.onSurface.withOpacity(0.2)),
                              const SizedBox(height: 16),
                              Text(l.noSchedules,
                                  style: TextStyle(
                                      color: colorScheme.onSurface
                                          .withOpacity(0.4))),
                            ],
                          ),
                        )
                      : _ScheduleList(
                          schedules: all,
                          groupId: groupId,
                          currentUserId: currentUserId,
                          canCreateSchedule: canCreateSchedule,
                          isDesktopMode: widget.isDesktopMode,
                          selectedScheduleId: widget.selectedScheduleId,
                          onScheduleSelected: widget.onScheduleSelected,
                          scrollController: _scrollController,
                        ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── 일정 리스트 ──────────────────────────────────────────────────────────────
class _ScheduleList extends StatelessWidget {
  final List<Map<String, dynamic>> schedules;
  final String groupId;
  final String currentUserId;
  final bool canCreateSchedule;
  final bool isDesktopMode;
  final String? selectedScheduleId;
  final ValueChanged<Map<String, dynamic>>? onScheduleSelected;
  final ScrollController? scrollController;

  const _ScheduleList({
    required this.schedules,
    required this.groupId,
    required this.currentUserId,
    required this.canCreateSchedule,
    this.isDesktopMode = false,
    this.selectedScheduleId,
    this.onScheduleSelected,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: schedules.length,
      itemBuilder: (context, index) {
        final s = schedules[index];
        final start = (s['start_time'] as Timestamp?)?.toDate();
        final end = (s['end_time'] as Timestamp?)?.toDate();
        final title = s['title'] as String? ?? '';
        final rsvps = s['rsvp'] as Map<String, dynamic>? ?? {};
        final myRsvp = rsvps[currentUserId] as String?;
        final isUpcoming =
            start != null && start.isAfter(DateTime.now());

        return Container(
          color: selectedScheduleId == (s['id'] as String? ?? '')
              ? colorScheme.primary.withOpacity(0.08)
              : null,
          child: ListTile(
          onTap: () {
            if (isDesktopMode && onScheduleSelected != null) {
              onScheduleSelected!({
                ...s,
                'can_edit': canCreateSchedule ||
                    s['created_by'] == currentUserId,
              });
              return;
            }
            final gp = context.read<GroupProvider>();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChangeNotifierProvider.value(
                  value: gp,
                  child: ScheduleDetailScreen(
                    groupId: groupId,
                    scheduleId: s['id'] as String,
                    canEdit: canCreateSchedule ||
                        s['created_by'] == currentUserId,
                  ),
                ),
              ),
            );
          },
          leading: Container(
            width: 48,
            decoration: BoxDecoration(
              color: isUpcoming
                  ? colorScheme.primaryContainer
                  : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: start != null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${start.month}/${start.day}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isUpcoming
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                      Text(
                        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isUpcoming
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  )
                : Icon(Icons.event,
                    color: colorScheme.onSurface.withOpacity(0.4)),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isUpcoming
                  ? colorScheme.onSurface
                  : colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          subtitle: end != null
              ? Text(
                  '~ ${end.month}/${end.day} ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 12),
                )
              : null,
          trailing: _RsvpBadge(rsvp: myRsvp, colorScheme: colorScheme),
          ),
        );
      },
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
    );
  }
}

// ── RSVP 뱃지 ────────────────────────────────────────────────────────────────
class _RsvpBadge extends StatelessWidget {
  final String? rsvp;
  final ColorScheme colorScheme;

  const _RsvpBadge({this.rsvp, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    if (rsvp == null) return const SizedBox.shrink();
    final (icon, color) = switch (rsvp) {
      'yes' => (Icons.check_circle, Colors.green),
      'no' => (Icons.cancel, Colors.red),
      'maybe' => (Icons.help, Colors.orange),
      _ => (Icons.circle_outlined, colorScheme.onSurface),
    };
    return Icon(icon, color: color, size: 20);
  }
}
