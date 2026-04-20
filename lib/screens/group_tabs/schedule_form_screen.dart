import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../config/env_config.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import '../../services/notification_service.dart';
import '../../providers/group_provider.dart';
import '../../providers/user_provider.dart';
import '../../l10n/app_localizations.dart';
import 'plan_screen.dart';

class ScheduleFormScreen extends StatefulWidget {
  final String groupId;
  final Map<String, dynamic>? existing;

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
  final _costController = TextEditingController();
  final _locationNameController = TextEditingController();

  DateTime _startTime = DateTime.now().add(const Duration(hours: 1));
  DateTime _endTime = DateTime.now().add(const Duration(hours: 2));
  bool _saving = false;

  Map<String, dynamic>? _selectedLocation;

  bool get isEdit => widget.existing != null;
  String get currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    if (isEdit) {
      final e = widget.existing!;
      _titleController.text = e['title'] as String? ?? '';
      _descController.text = e['description'] as String? ?? '';
      _costController.text = e['cost'] as String? ?? '';
      _startTime = (e['start_time'] as Timestamp?)?.toDate() ?? _startTime;
      _endTime = (e['end_time'] as Timestamp?)?.toDate() ?? _endTime;

      if (e['location'] != null && e['location'] is Map) {
        _selectedLocation = Map<String, dynamic>.from(e['location']);
        _locationNameController.text =
            _selectedLocation!['name'] as String? ?? '';
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _costController.dispose();
    _locationNameController.dispose();
    super.dispose();
  }

  // ── locale 코드 → Google Places 언어 코드 변환 ──────────────────────
  String _toGoogleLocale(String locale) {
    const map = {
      'ko': 'ko',
      'en': 'en',
      'ja': 'ja',
      'zh': 'zh-CN',
      'fr': 'fr',
      'de': 'de',
      'es': 'es',
    };
    return map[locale] ?? 'ko';
  }

  // ── 장소 필드 빌더 ───────────────────────────────────────────────────
  Widget _buildLocationField(AppLocalizations l, bool isPro) {
    if (!isPro) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _locationNameController,
            enabled: false,
            decoration: InputDecoration(
              labelText: l.location,
              prefixIcon: const Icon(Icons.location_on_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  l.locationPro,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () {
                  final gp = context.read<GroupProvider>();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChangeNotifierProvider.value(
                        value: gp,
                        child: PlanScreen(groupId: widget.groupId),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.upgrade, size: 18),
                label: Text(l.upgradePlan),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      );
    }

    // Pro 플랜: 사용자 locale에 맞는 자동완성
    final rawLocale = context.read<UserProvider>().locale;
    final googleLocale = _toGoogleLocale(rawLocale);

    return _LocationAutocompleteField(
      controller: _locationNameController,
      apiKey: EnvConfig.mapsApiKey,
      label: l.location,
      locale: googleLocale,
      onLocationSelected: (location) {
        setState(() => _selectedLocation = location);
      },
    );
  }

  // ── 저장 로직 ────────────────────────────────────────────────────────
  Future<void> _handleSave(AppLocalizations l) async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.titleRequired)));
      return;
    }
    if (_endTime.isBefore(_startTime)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.endBeforeStart)));
      return;
    }

    setState(() => _saving = true);

    try {
      final col = FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('schedules');

      Map<String, dynamic>? finalLocation;
      if (_locationNameController.text.isNotEmpty) {
        if (_selectedLocation != null &&
            _selectedLocation!['place_id'] != 'manual') {
          finalLocation = _selectedLocation;
        } else {
          finalLocation = {
            'name': _locationNameController.text.trim(),
            'address': '',
            'place_id': 'manual',
            'lat': 0.0,
            'lng': 0.0,
          };
        }
      }

      final data = {
        'title': title,
        'description': _descController.text.trim(),
        'cost': _costController.text.trim(),
        'start_time': Timestamp.fromDate(_startTime),
        'end_time': Timestamp.fromDate(_endTime),
        'location': finalLocation,
        'updated_at': FieldValue.serverTimestamp(),
      };

      String scheduleId;
      if (isEdit) {
        scheduleId = widget.existing!['id'];
        await col.doc(scheduleId).update(data);
        context.read<NotificationService>().cancelNotification(
            NotificationService.notificationId(scheduleId));
      } else {
        data['created_by'] = currentUserId;
        data['created_at'] = FieldValue.serverTimestamp();
        data['rsvp'] = <String, String>{};
        final ref = await col.add(data);
        scheduleId = ref.id;
      }

      await context.read<NotificationService>().scheduleNotification(
        id: NotificationService.notificationId(scheduleId),
        title: title,
        body: l.scheduleStartingSoon,
        scheduledTime: _startTime,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(isEdit ? l.scheduleUpdated : l.scheduleCreated)),
        );
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.saveFailed)));
      }
    }
  }

  // ── 날짜/시간 선택 ───────────────────────────────────────────────────
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

    final picked =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);

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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final groupProvider = context.watch<GroupProvider>();
    final bool isPro = groupProvider.plan == 'pro';

    String fmt(DateTime dt) =>
        '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? l.editSchedule : l.addSchedule),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _handleSave(l),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
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
            ),
            const SizedBox(height: 16),

            // 설명
            TextField(
              controller: _descController,
              decoration: InputDecoration(
                labelText: l.scheduleDescription,
                prefixIcon: const Icon(Icons.notes),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // 비용
            TextField(
              controller: _costController,
              decoration: InputDecoration(
                labelText: l.scheduleCost,
                hintText: l.scheduleCostHint,
                prefixIcon: const Icon(Icons.wallet_outlined),
              ),
            ),
            const SizedBox(height: 24),

            // 시작 시간
            _DateTimeTile(
              label: l.startTime,
              value: fmt(_startTime),
              icon: Icons.play_circle_outline,
              colorScheme: colorScheme,
              onTap: () => _pickDateTime(isStart: true),
            ),
            const SizedBox(height: 12),

            // 종료 시간
            _DateTimeTile(
              label: l.endTime,
              value: fmt(_endTime),
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
                      color: colorScheme.onSurface.withOpacity(0.4)),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 장소 필드
            _buildLocationField(l, isPro),
          ],
        ),
      ),
    );
  }
}

// ── 커스텀 Places 자동완성 위젯 ──────────────────────────────────────
class _LocationAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final String apiKey;
  final String label;
  final String locale;
  final void Function(Map<String, dynamic> location) onLocationSelected;

  const _LocationAutocompleteField({
    required this.controller,
    required this.apiKey,
    required this.label,
    required this.locale,
    required this.onLocationSelected,
  });

  @override
  State<_LocationAutocompleteField> createState() =>
      _LocationAutocompleteFieldState();
}

class _LocationAutocompleteFieldState
    extends State<_LocationAutocompleteField> {
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  final _fieldKey = GlobalKey();
  OverlayEntry? _overlayEntry;

  List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounce;
  bool _loading = false;
  bool _suppressSearch = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _removeOverlay();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    widget.controller.removeListener(_onTextChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_suppressSearch) return;
    final query = widget.controller.text.trim();
    if (query.isEmpty) {
      _removeOverlay();
      setState(() => _suggestions = []);
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchSuggestions(query);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(query)}'
        '&key=${widget.apiKey}'
        '&language=${widget.locale}',
      );
      final res = await http.get(uri);
      if (!mounted) return;

      final json = jsonDecode(res.body);
      if (json['status'] == 'OK') {
        final predictions = json['predictions'] as List;
        setState(() {
          _suggestions = predictions
              .map((p) => {
                    'place_id': p['place_id'],
                    'description': p['description'],
                    'main_text':
                        p['structured_formatting']?['main_text'] ??
                            p['description'],
                    'secondary_text':
                        p['structured_formatting']?['secondary_text'] ?? '',
                  })
              .toList();
        });
        // 빌드 완료 후 오버레이 표시
        WidgetsBinding.instance.addPostFrameCallback((_) => _showOverlay());
      } else {
        setState(() => _suggestions = []);
        _removeOverlay();
      }
    } catch (_) {
      if (mounted) setState(() => _suggestions = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchPlaceDetail(Map<String, dynamic> suggestion) async {
    final placeId = suggestion['place_id'] as String;
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=${Uri.encodeComponent(placeId)}'
        '&key=${widget.apiKey}'
        '&fields=geometry,name,formatted_address'
        '&language=${widget.locale}',
      );
      final res = await http.get(uri);
      final json = jsonDecode(res.body);

      double lat = 0.0, lng = 0.0;
      if (json['status'] == 'OK') {
        final loc = json['result']['geometry']['location'];
        lat = (loc['lat'] as num).toDouble();
        lng = (loc['lng'] as num).toDouble();
      }

      widget.onLocationSelected({
        'name': suggestion['main_text'],
        'address': suggestion['description'],
        'place_id': placeId,
        'lat': lat,
        'lng': lng,
      });
    } catch (_) {
      widget.onLocationSelected({
        'name': suggestion['main_text'],
        'address': suggestion['description'],
        'place_id': placeId,
        'lat': 0.0,
        'lng': 0.0,
      });
    }
  }

  void _onSuggestionTap(Map<String, dynamic> suggestion) {
    _suppressSearch = true;
    widget.controller.text = suggestion['description'];
    _suppressSearch = false;

    _removeOverlay();
    setState(() => _suggestions = []);
    _focusNode.unfocus();
    _fetchPlaceDetail(suggestion);
  }

  void _showOverlay() {
    _removeOverlay();
    if (_suggestions.isEmpty || !mounted) return;

    final renderBox =
        _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final fieldHeight = renderBox.size.height;
    final fieldWidth = renderBox.size.width;

    _overlayEntry = OverlayEntry(
      builder: (ctx) => Positioned(
        width: fieldWidth,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, fieldHeight + 4),
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _suggestions
                    .map(
                      (s) => InkWell(
                        onTap: () => _onSuggestionTap(s),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on,
                                  size: 18, color: Colors.grey),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s['main_text'],
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if ((s['secondary_text'] as String)
                                        .isNotEmpty)
                                      Text(
                                        s['secondary_text'],
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600]),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        key: _fieldKey,
        controller: widget.controller,
        focusNode: _focusNode,
        decoration: InputDecoration(
          labelText: widget.label,
          prefixIcon: const Icon(Icons.location_on_outlined),
          suffixIcon: _loading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : widget.controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _suppressSearch = true;
                        widget.controller.clear();
                        _suppressSearch = false;
                        _removeOverlay();
                        setState(() => _suggestions = []);
                      },
                    )
                  : null,
        ),
      ),
    );
  }
}

// ── _DateTimeTile ────────────────────────────────────────────────────
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
                size: 18,
                color: colorScheme.onSurface.withOpacity(0.4)),
          ],
        ),
      ),
    );
  }
}