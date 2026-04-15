import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/user_provider.dart';
import '../../utils/user_display.dart';
import '../../services/chat_service.dart';
import 'settlement_detail_screen.dart';

class SettlementFormScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String? scheduleId;
  final String? scheduleTitle;
  final List<Map<String, dynamic>> defaultMembers;
  final Map<String, dynamic>? existing;

  const SettlementFormScreen({
    super.key,
    required this.groupId,
    this.groupName = '',
    this.scheduleId,
    this.scheduleTitle,
    this.defaultMembers = const [],
    this.existing,
  });

  @override
  State<SettlementFormScreen> createState() => _SettlementFormScreenState();
}

class _SettlementFormScreenState extends State<SettlementFormScreen> {
  final _titleController = TextEditingController();
  final _totalCostController = TextEditingController();
  final _bankInfoController = TextEditingController();
  
  bool _isEqualSplit = true;
  bool _saving = false;
  
  List<Map<String, dynamic>> _members = [];
  final Map<String, TextEditingController> _amountControllers = {};

  String get currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _titleController.text = widget.existing!['title'] as String? ?? '';
      _totalCostController.text = widget.existing!['total_cost'] as String? ?? '';
      _bankInfoController.text = widget.existing!['bank_info'] as String? ?? '';
      _isEqualSplit = widget.existing!['is_equal_split'] as bool? ?? true;
      _members = List<Map<String, dynamic>>.from(
        (widget.existing!['participants'] as List? ?? []).map((p) => Map<String, dynamic>.from(p))
      );
    } else {
      _titleController.text = widget.scheduleTitle ?? '';
      _members = List.from(widget.defaultMembers);
      
      // Ensure current user (creator) is in the list
      if (!_members.any((m) => m['uid'] == currentUserId)) {
        final userProvider = context.read<UserProvider>();
        _members.insert(0, {
          'uid': currentUserId,
          'display_name': userProvider.name ?? FirebaseAuth.instance.currentUser?.displayName ?? '',
          'photo_url': userProvider.photoUrl ?? FirebaseAuth.instance.currentUser?.photoURL ?? '',
        });
      }
    }

    _initControllers();
    if (widget.existing != null) {
      for (var m in _members) {
        _amountControllers[m['uid']]?.text = m['amount'] as String? ?? '';
      }
    }

    _totalCostController.addListener(_onTotalCostChanged);
  }

  void _initControllers() {
    for (var m in _members) {
      final uid = m['uid'] as String;
      if (!_amountControllers.containsKey(uid)) {
        _amountControllers[uid] = TextEditingController();
      }
    }
  }

  void _onTotalCostChanged() {
    if (_isEqualSplit) {
      _calculateEqualSplit();
    }
  }

  void _calculateEqualSplit() {
    if (_members.isEmpty) return;
    final totalText = _totalCostController.text.replaceAll(',', '');
    final total = int.tryParse(totalText) ?? 0;
    
    if (total == 0) {
      for (var ctrl in _amountControllers.values) {
        ctrl.text = '';
      }
      return;
    }

    final perPerson = total ~/ _members.length;
    for (var m in _members) {
      _amountControllers[m['uid']]?.text = perPerson.toString();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _totalCostController.dispose();
    _bankInfoController.dispose();
    for (var ctrl in _amountControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _handleSave(AppLocalizations l) async {
    final title = _titleController.text.trim();
    final totalCost = _totalCostController.text.trim();
    
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.titleRequired)));
      return;
    }
    if (totalCost.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.settlementTotalCostRequired)));
      return;
    }

    // Check if any amount is empty
    bool hasEmptyAmount = false;
    for (var m in _members) {
      if ((_amountControllers[m['uid']]?.text.trim() ?? '').isEmpty) {
        hasEmptyAmount = true;
        break;
      }
    }
    if (hasEmptyAmount) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.settlementEnterAllAmounts)));
      return;
    }

    setState(() => _saving = true);

    try {
      final col = FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('settlements');

      final List<Map<String, dynamic>> participants = [];
      for (var m in _members) {
        participants.add({
          'uid': m['uid'],
          'display_name': m['display_name'] ?? '',
          'photo_url': m['photo_url'] ?? '',
          'amount': _amountControllers[m['uid']]?.text.trim() ?? '',
          'status': m['uid'] == currentUserId ? 'confirmed' : 'pending',
        });
      }

      final data = {
        'title': title,
        'creator_uid': widget.existing?['creator_uid'] ?? currentUserId,
        'total_cost': totalCost,
        'bank_info': _bankInfoController.text.trim(),
        'schedule_id': widget.scheduleId ?? widget.existing?['schedule_id'],
        'is_equal_split': _isEqualSplit,
        'updated_at': FieldValue.serverTimestamp(),
        'participants': participants,
      };
      
      if (widget.existing == null) {
        data['created_at'] = FieldValue.serverTimestamp();
      }

      String settlementId;
      if (widget.existing != null) {
        settlementId = widget.existing!['id'] as String;
        await col.doc(settlementId).update(data);
      } else {
        final ref = await col.add(data);
        settlementId = ref.id;
      }
      
      if (mounted) {
        if (widget.existing != null) {
          Navigator.pop(context); // 수정인 경우 상세 화면으로 돌아감
        } else {
          // 신규인 경우 상세 화면으로 교체
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => SettlementDetailScreen(
                groupId: widget.groupId,
                settlementId: settlementId,
                groupName: widget.groupName,
              ),
            ),
          );
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.existing != null ? l.settingsSaved : l.settlementCreated)),
        );
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.settlementCreateFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.createSettlement),
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
            // 정산 제목
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: l.settlementTitle,
                prefixIcon: const Icon(Icons.title),
              ),
            ),
            const SizedBox(height: 16),

            // 총 비용
            TextField(
              controller: _totalCostController,
              keyboardType: _isEqualSplit ? TextInputType.number : TextInputType.text,
              inputFormatters: _isEqualSplit ? [FilteringTextInputFormatter.digitsOnly] : null,
              decoration: InputDecoration(
                labelText: l.settlementTotalCost,
                hintText: _isEqualSplit ? l.settlementTotalCostHint : l.settlementAmountHint,
                prefixIcon: const Icon(Icons.wallet_outlined),
              ),
            ),
            const SizedBox(height: 16),

            // 계좌 정보
            TextField(
              controller: _bankInfoController,
              decoration: InputDecoration(
                labelText: l.settlementBankInfo,
                hintText: l.settlementBankInfoHint,
                prefixIcon: const Icon(Icons.account_balance_outlined),
              ),
            ),
            const SizedBox(height: 24),
            
            const Divider(),
            const SizedBox(height: 16),

            // 분배 방식 토글
            Text(l.settlementSplitMode, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: true, 
                  label: Text(l.settlementSplitEqual),
                  icon: const Icon(Icons.pie_chart_outline),
                ),
                ButtonSegment(
                  value: false, 
                  label: Text(l.settlementSplitManual),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
              selected: {_isEqualSplit},
              onSelectionChanged: (Set<bool> newSelection) {
                setState(() {
                  _isEqualSplit = newSelection.first;
                  if (_isEqualSplit) {
                    _calculateEqualSplit();
                  }
                });
              },
            ),
            
            const SizedBox(height: 24),

            // 참여자 목록 및 낼 금액
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "${l.settlementMembers} (${_members.length})", 
                  style: const TextStyle(fontWeight: FontWeight.bold)
                ),
                // TODO: 참여자 추가/삭제 버튼
              ],
            ),
            const SizedBox(height: 12),

            ..._members.map((m) {
              final uid = m['uid'] as String;
              final user = UserDisplay.resolveCached(uid, fallbackName: m['display_name']) ?? 
                 UserDisplay.fromStored(uid: uid, name: m['display_name'] ?? '');

               return Padding(
                 padding: const EdgeInsets.only(bottom: 12.0),
                 child: Row(
                   children: [
                     CircleAvatar(
                        radius: 16,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        backgroundImage: user.photoUrl.isNotEmpty ? NetworkImage(user.photoUrl) : null,
                        child: user.photoUrl.isEmpty ? Text(user.initial(l), style: const TextStyle(fontSize: 12)) : null,
                     ),
                     const SizedBox(width: 12),
                     Expanded(
                       child: Text(
                         user.nameOrInitial(l),
                         style: const TextStyle(fontWeight: FontWeight.w500),
                         overflow: TextOverflow.ellipsis,
                       ),
                     ),
                     const SizedBox(width: 12),
                     SizedBox(
                       width: 120, // 금액 입력 필드 너비
                       child: TextField(
                         controller: _amountControllers[uid],
                         enabled: !_isEqualSplit, // 균등분배면 비활성화
                         textAlign: TextAlign.end,
                         decoration: InputDecoration(
                           hintText: l.settlementAmountHint,
                           isDense: true,
                           contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                           border: OutlineInputBorder(
                             borderRadius: BorderRadius.circular(8),
                           ),
                         ),
                       ),
                     ),
                   ],
                 ),
               );
            }),
          ],
        ),
      ),
    );
  }
}
