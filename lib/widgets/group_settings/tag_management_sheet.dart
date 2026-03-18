import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/group_service.dart';
import '../../l10n/app_localizations.dart';

class TagManagementSheet extends StatefulWidget {
  final String groupId;
  final AppLocalizations l;
  final ColorScheme colorScheme;

  const TagManagementSheet(
      {super.key, required this.groupId, required this.l, required this.colorScheme});

  @override
  State<TagManagementSheet> createState() => _TagManagementSheetState();
}

class _TagManagementSheetState extends State<TagManagementSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    final colorScheme = widget.colorScheme;
    final groupService = context.read<GroupService>();

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: colorScheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l.manageTags,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  decoration: InputDecoration(
                    hintText: l.tagNameHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () async {
                  final tag = _ctrl.text.trim();
                  if (tag.isEmpty) return;
                  final ok = await groupService.addGroupTag(
                      widget.groupId, tag);
                  if (ok) {
                    _ctrl.clear();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l.tagAdded)));
                    }
                  }
                },
                child: Text(l.addTag),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<String>>(
            stream: groupService.getGroupTags(widget.groupId),
            builder: (context, snap) {
              final tags = snap.data ?? [];
              if (tags.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l.noTags,
                      style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.4))),
                );
              }
              return SizedBox(
                height: 200,
                child: ListView.builder(
                  itemCount: tags.length,
                  itemBuilder: (ctx, i) => ListTile(
                    leading: Icon(Icons.label_outline,
                        color: colorScheme.primary),
                    title: Text(tags[i]),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline,
                          color: colorScheme.error),
                      onPressed: () async {
                        final ok = await groupService.removeGroupTag(
                            widget.groupId, tags[i]);
                        if (ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l.tagDeleted)));
                        }
                      },
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
