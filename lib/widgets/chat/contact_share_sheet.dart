import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/friend_service.dart';
import '../../utils/user_display.dart';

class ContactShareResult {
  final String uid;
  final String displayName;
  final String photoUrl;

  const ContactShareResult({
    required this.uid,
    required this.displayName,
    required this.photoUrl,
  });
}

class ContactShareSheet extends StatefulWidget {
  final Color? shareButtonColor;
  final Color? shareButtonForegroundColor;

  const ContactShareSheet({
    super.key,
    this.shareButtonColor,
    this.shareButtonForegroundColor,
  });

  @override
  State<ContactShareSheet> createState() => _ContactShareSheetState();
}

class _ContactShareSheetState extends State<ContactShareSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final shareButtonColor = widget.shareButtonColor ?? colorScheme.primary;
    final shareButtonForegroundColor =
        widget.shareButtonForegroundColor ?? colorScheme.onPrimary;

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l.attachContact,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              l.friendsList,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: InputDecoration(
                hintText: l.searchPlaceholder,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: context.read<FriendService>().getFriends(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final allFriends = snapshot.data ?? const [];
                  final lowerQuery = _query.toLowerCase();
                  final friends = lowerQuery.isEmpty
                      ? allFriends
                      : allFriends.where((friend) {
                          final name = (friend['display_name'] as String? ?? '')
                              .toLowerCase();
                          return name.contains(lowerQuery);
                        }).toList();

                  if (friends.isEmpty) {
                    return Center(
                      child: Text(
                        allFriends.isEmpty ? l.noFriends : l.noSearchResults,
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.55),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: friends.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: colorScheme.outline.withOpacity(0.12),
                    ),
                    itemBuilder: (context, index) {
                      final friend = friends[index];
                      final uid = friend['uid'] as String? ?? '';
                      final user = UserDisplay.fromStored(
                        uid: uid,
                        name: friend['display_name'] as String? ?? l.unknown,
                        photoUrl: friend['profile_image'] as String? ?? '',
                      );
                      final name = user.displayName(
                        l,
                        fallback:
                            friend['display_name'] as String? ?? l.unknown,
                      );
                      final photoUrl = user.photoUrl;
                      final hasPhoto = photoUrl.isNotEmpty;

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 22,
                          backgroundColor: colorScheme.primaryContainer,
                          backgroundImage: hasPhoto
                              ? CachedNetworkImageProvider(photoUrl)
                              : null,
                          onBackgroundImageError: hasPhoto ? (_, __) {} : null,
                          child: hasPhoto
                              ? null
                              : Text(
                                  user.initial(l, fallback: '?'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                        ),
                        title: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: shareButtonColor,
                            foregroundColor: shareButtonForegroundColor,
                          ),
                          onPressed: uid.isEmpty
                              ? null
                              : () => Navigator.of(context).pop(
                                  ContactShareResult(
                                    uid: uid,
                                    displayName: name,
                                    photoUrl: photoUrl,
                                  ),
                                ),
                          child: Text(l.shareMessage),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
