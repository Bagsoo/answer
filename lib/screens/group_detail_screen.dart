import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/group_provider.dart';
import 'group_tabs/members_tab.dart';
import 'group_tabs/boards_tab.dart';
import 'group_tabs/schedules_tab.dart';
import 'group_tabs/chats_tab.dart';
import 'group_tabs/settings_tab.dart';
import 'group_tabs/group_profile_screen.dart';

class GroupDetailScreen extends StatelessWidget {
  final String groupId;
  final String groupName;
  final Map<String, dynamic>? initialGroupData;

  const GroupDetailScreen(
      {super.key,
      required this.groupId,
      required this.groupName,
      this.initialGroupData});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => GroupProvider(groupId, initialData: initialGroupData),
      child: _GroupDetailBody(groupName: groupName),
    );
  }
}

class _GroupDetailBody extends StatelessWidget {
  final String groupName;

  const _GroupDetailBody({required this.groupName});

  void _showMembersModal(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final gp = context.read<GroupProvider>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => ChangeNotifierProvider.value(
        // 모달에도 동일한 GroupProvider 인스턴스 전달
        value: gp,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (_, scrollController) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colorScheme.onSurface.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.people_outline,
                            color: colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          groupName,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              const Expanded(child: MembersTab()),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // loaded 되기 전엔 로딩 표시
    final loaded = context.select<GroupProvider, bool>((gp) => gp.loaded);
    if (!loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    // AppBar에 필요한 값만 select → 해당 값 바뀔 때만 rebuild
    final memberCount =
        context.select<GroupProvider, int>((gp) => gp.memberCount);
    final likes =
        context.select<GroupProvider, List<String>>((gp) => gp.likes);
    final isLiked =
        context.select<GroupProvider, bool>((gp) => gp.isLiked);
    final name =
        context.select<GroupProvider, String>((gp) => gp.name);
    final profileImageUrl =
        context.select<GroupProvider, String>((gp) => gp.profileImageUrl);

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          leading: GestureDetector(
            onTap: () {
              final gp = context.read<GroupProvider>();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChangeNotifierProvider.value(
                    value: gp,
                    child: GroupProfileScreen(groupId: gp.groupId),
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: colorScheme.primaryContainer,
                backgroundImage: profileImageUrl.isNotEmpty
                    ? NetworkImage(profileImageUrl)
                    : null,
                child: profileImageUrl.isEmpty
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      )
                    : null,
              ),
            ),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  name.isNotEmpty ? name : groupName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (memberCount > 0) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 1),
                  child: GestureDetector(
                    onTap: () => _showMembersModal(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline,
                              size: 13,
                              color:
                                  colorScheme.onSurface.withOpacity(0.6)),
                          const SizedBox(width: 3),
                          Text(
                            '$memberCount',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color:
                                  colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () =>
                    context.read<GroupProvider>().toggleLike(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 8),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        isLiked
                            ? Icons.favorite
                            : Icons.favorite_border,
                        size: 24,
                        color: isLiked
                            ? Colors.red
                            : colorScheme.onSurface.withOpacity(0.45),
                      ),
                      if (likes.isNotEmpty)
                        Positioned(
                          right: -5,
                          bottom: -7,
                          child: Text(
                            '${likes.length}',
                            style: TextStyle(
                              fontSize: 10,
                              color: isLiked
                                  ? Colors.red
                                  : colorScheme.onSurface.withOpacity(0.5),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          bottom: TabBar(
            labelColor: colorScheme.primary,
            unselectedLabelColor: colorScheme.onSurface.withOpacity(0.4),
            indicatorColor: colorScheme.primary,
            tabs: const [
              Tab(icon: Icon(Icons.people)),
              Tab(icon: Icon(Icons.article_outlined)),
              Tab(icon: Icon(Icons.calendar_month)),
              Tab(icon: Icon(Icons.chat_bubble)),
              Tab(icon: Icon(Icons.settings)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const MembersTab(),
            const BoardsTab(),
            const SchedulesTab(),
            ChatsTab(groupName: groupName),
            const SettingsTab(),
          ],
        ),
      ),
    );
  }
}
