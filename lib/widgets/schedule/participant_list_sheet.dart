import 'package:flutter/material.dart';
import 'package:messenger/l10n/app_localizations.dart';
import 'package:messenger/screens/user_profile_detail_screen.dart';

class ParticipantListSheet extends StatelessWidget {
  final List<dynamic> participants;
  final AppLocalizations l;

  const ParticipantListSheet({super.key, required this.participants, required this.l});

  // 상태 뱃지 생성 로직 (위젯 내부로 캡슐화)
  Widget _buildStatusBadge(String? status, ColorScheme colorScheme) {
    Color color;
    String text;
    switch (status) {
      case 'accepted': color = Colors.green; text = l.rsvpYes; break;
      case 'pending': color = Colors.orange; text = l.rsvpMaybe; break;
      default: color = Colors.grey; text = l.rsvpNo; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      // 높이를 화면의 60% 정도로 제한하거나 내용에 맞게 조절
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
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
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              )
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

                return ListTile(
                  onTap: () {
                    final String peerUid = p['uid'] ?? '';
                    final String peerName = p['display_name'] ?? l.unknown;
                    if (peerUid.isEmpty) return;
                    
                    Navigator.pop(context);

                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => UserProfileDetailScreen(
                            uid: peerUid,
                            displayName: peerName,
                            photoUrl: photoUrl,
                        ),
                    ));
                  },
                
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  leading: CircleAvatar(
                    backgroundColor: colorScheme.primaryContainer,
                    backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                        ? NetworkImage('$photoUrl?v=$version')
                        : null,
                    child: (p['photo_url'] == null || p['photo_url'].toString().isEmpty)
                        ? Text(p['display_name'] != null && p['display_name'].toString().isNotEmpty ? p['display_name'].toString()[0].toUpperCase() : '?', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold ))
                        : null,
                  ),
                  title: Text(p['display_name'] ?? l.unknown, style: const TextStyle(fontWeight: FontWeight.w500)),
                  trailing: Icon(Icons.chevron_right, color: colorScheme.outline),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}