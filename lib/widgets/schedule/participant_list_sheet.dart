import 'package:flutter/material.dart';
import 'package:messenger/l10n/app_localizations.dart';
import 'package:messenger/screens/user_profile_detail_screen.dart';
import 'package:messenger/utils/user_display.dart';

class ParticipantListSheet extends StatelessWidget {
  final List<dynamic> participants;
  final AppLocalizations l;

  const ParticipantListSheet({
    super.key,
    required this.participants,
    required this.l,
  });

  // 상태 뱃지 생성 로직 (위젯 내부로 캡슐화)
  Widget _buildStatusBadge(String? status, ColorScheme colorScheme) {
    Color color;
    String text;
    switch (status) {
      case 'accepted':
        color = Colors.green;
        text = l.rsvpYes;
        break;
      case 'pending':
        color = Colors.orange;
        text = l.rsvpMaybe;
        break;
      default:
        color = Colors.grey;
        text = l.rsvpNo;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      // 높이를 화면의 60% 정도로 제한하거나 내용에 맞게 조절
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 상단 핸들 (BottomSheet 느낌 가미)
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "${l.participants} (${participants.length})",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: participants.length,
              itemBuilder: (context, index) {
                final p = participants[index];
                final photoUrl = p['photo_url'];
                final version = p['photo_version'] ?? 0;
                final peerUid = p['uid'] as String? ?? '';
                final fallbackName = p['display_name'] as String? ?? l.unknown;
                return FutureBuilder<UserDisplayData>(
                  future: UserDisplay.resolve(
                    peerUid,
                    fallbackName: fallbackName,
                    fallbackPhotoUrl: photoUrl as String?,
                  ),
                  builder: (context, snapshot) {
                    final user =
                        snapshot.data ??
                        UserDisplay.fromStored(
                          uid: peerUid,
                          name: fallbackName,
                          photoUrl: photoUrl as String?,
                        );
                    final name = user.displayName(l, fallback: fallbackName);
                    final resolvedPhoto = user.isDeleted ? '' : user.photoUrl;
                    final hasPhoto = resolvedPhoto.isNotEmpty;

                    return ListTile(
                      onTap: () {
                        if (peerUid.isEmpty) return;

                        Navigator.pop(context);

                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => UserProfileDetailScreen(
                              uid: peerUid,
                              displayName: name,
                              photoUrl: resolvedPhoto,
                            ),
                          ),
                        );
                      },
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      leading: CircleAvatar(
                        backgroundColor: colorScheme.primaryContainer,
                        backgroundImage: hasPhoto
                            ? NetworkImage('$resolvedPhoto?v=$version')
                            : null,
                        child: hasPhoto
                            ? null
                            : user.isDeleted
                            ? const Icon(Icons.person_off_outlined)
                            : Text(
                                user.initial(l, fallback: '?'),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: colorScheme.outline,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
