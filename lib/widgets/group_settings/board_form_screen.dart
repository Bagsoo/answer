import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/group_service.dart';
import '../../l10n/app_localizations.dart';

class BoardFormScreen extends StatefulWidget {
  final String groupId;
  final Map<String, dynamic>? board;

  const BoardFormScreen({super.key, required this.groupId, this.board});

  @override
  State<BoardFormScreen> createState() => _BoardFormScreenState();
}

class _BoardFormScreenState extends State<BoardFormScreen> {
  final _nameCtrl = TextEditingController();
  String _boardType = 'free';
  String _writePermission = 'all';
  List<String> _allowedTags = [];
  bool _saving = false;

  bool get isEditing => widget.board != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      final b = widget.board!;
      _nameCtrl.text = b['name'] as String? ?? '';
      _boardType = b['board_type'] as String? ?? 'free';
      _writePermission = b['write_permission'] as String? ?? 'all';
      _allowedTags =
          List<String>.from(b['allowed_tags'] as List? ?? []);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _onBoardTypeChanged(String? val) {
    if (val == null) return;
    setState(() {
      _boardType = val;
      if (val == 'notice') _writePermission = 'owner_only';
      if (val == 'free' || val == 'greeting') _writePermission = 'all';
    });
  }

  Future<void> _save(AppLocalizations l) async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.postTitleRequired)));
      return;
    }
    setState(() => _saving = true);

    final service = context.read<GroupService>();
    final data = {
      'name': name,
      'board_type': _boardType,
      'write_permission': _writePermission,
      'allowed_tags': _boardType == 'sub' ? _allowedTags : [],
    };

    bool ok;
    if (isEditing) {
      ok = await service.updateBoard(
          widget.groupId, widget.board!['id'] as String, data);
    } else {
      ok = await service.createBoard(widget.groupId, data);
    }

    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? (isEditing ? l.boardUpdated : l.boardCreated)
              : l.boardSaveFailed)));
      if (ok) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final groupService = context.read<GroupService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? l.editBoard : l.createBoard),
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child:
                      CircularProgressIndicator(strokeWidth: 2))
              : TextButton(
                  onPressed: () => _save(l),
                  child: Text(l.save,
                      style:
                          TextStyle(color: colorScheme.primary))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: l.boardName,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Text(l.boardType,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...[
            ('notice', l.boardTypeNotice, Icons.campaign_outlined),
            ('free', l.boardTypeFree, Icons.article_outlined),
            ('greeting', l.boardTypeGreeting,
                Icons.waving_hand_outlined),
            ('sub', l.boardTypeSub, Icons.label_outlined),
          ].map((e) => RadioListTile<String>(
                value: e.$1,
                groupValue: _boardType,
                onChanged: _onBoardTypeChanged,
                title: Text(e.$2),
                secondary: Icon(e.$3, color: colorScheme.primary),
                dense: true,
              )),
          const SizedBox(height: 16),
          Text(l.boardWritePermission,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          RadioListTile<String>(
            value: 'owner_only',
            groupValue: _writePermission,
            onChanged: (v) => setState(() => _writePermission = v!),
            title: Text(l.boardWriteOwnerOnly),
            dense: true,
          ),
          RadioListTile<String>(
            value: 'all',
            groupValue: _writePermission,
            onChanged: (v) => setState(() => _writePermission = v!),
            title: Text(l.boardWriteAll),
            dense: true,
          ),
          if (_boardType == 'sub') ...[
            const SizedBox(height: 16),
            Text(l.boardAllowedTags,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(l.boardAllowedTagsHint,
                style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withOpacity(0.5))),
            const SizedBox(height: 8),
            StreamBuilder<List<String>>(
              stream: groupService.getGroupTags(widget.groupId),
              builder: (context, snap) {
                final tags = snap.data ?? [];
                if (tags.isEmpty) {
                  return Text(l.noTags,
                      style: TextStyle(
                          color:
                              colorScheme.onSurface.withOpacity(0.4)));
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: tags.map((tag) {
                    final selected = _allowedTags.contains(tag);
                    return FilterChip(
                      label: Text(tag),
                      selected: selected,
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            _allowedTags.add(tag);
                          } else {
                            _allowedTags.remove(tag);
                          }
                        });
                      },
                      selectedColor:
                          colorScheme.primary.withOpacity(0.2),
                      checkmarkColor: colorScheme.primary,
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
