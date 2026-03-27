import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geocoding/geocoding.dart';
import '../../l10n/app_localizations.dart';

class LocationMessageBubble extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isMe;
  final bool isContinuous;
  final int unreadCount;
  final ColorScheme colorScheme;

  const LocationMessageBubble({
    super.key,
    required this.data,
    required this.isMe,
    required this.isContinuous,
    required this.unreadCount,
    required this.colorScheme,
  });

  // ── 구글맵 열기 ─────────────────────────────────────
  Future<void> _openMap(double lat, double lng) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── 좌표 → 주소 변환 ────────────────────────────────
  Future<String> _getAddress(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);

      if (placemarks.isEmpty) return '';

      final place = placemarks.first;

      return [
        place.locality,
        place.subLocality,
        place.thoroughfare,
        place.name,
      ].where((e) => e != null && e.isNotEmpty).join(' ');
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lat = (data['location_lat'] as num).toDouble();
    final lng = (data['location_lng'] as num).toDouble();
    final type = data['location_type'] ?? 'current';

    final isDestination = type == 'destination';

    final title = isDestination ? l.locationDestination : l.locationCurrent;
    final icon = isDestination ? Icons.place : Icons.my_location;
    final accentColor = isDestination ? Colors.red : Colors.blue;

    final timeStr = ''; // 필요하면 기존 로직 연결

    final topPadding = isContinuous ? 2.0 : 8.0;

    return Padding(
      padding: EdgeInsets.only(
        top: topPadding,
        bottom: 2,
        left: 8,
        right: 8,
      ),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── 내 메시지 ─────────────────────────────
          if (isMe) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (unreadCount > 0)
                  Text(
                    unreadCount.toString(),
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
          ],

          // ── 위치 버블 ─────────────────────────────
          GestureDetector(
            onTap: () => _openMap(lat, lng),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.62,
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isMe
                    ? colorScheme.primary.withOpacity(0.15)
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: Radius.circular(isContinuous ? 16 : 4),
                  bottomLeft: const Radius.circular(16),
                  bottomRight: const Radius.circular(16),
                ),
                border: Border.all(
                  color: colorScheme.outline.withOpacity(0.15),
                ),
              ),
              child: Row(
                children: [
                  // 아이콘
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: accentColor, size: 18),
                  ),
                  const SizedBox(width: 10),

                  // 텍스트 영역
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),

                        /// 🔥 핵심: 주소 변환
                        FutureBuilder<String>(
                          future: _getAddress(lat, lng),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return Text(
                                l.loadingAddress,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurface
                                      .withOpacity(0.5),
                                ),
                              );
                            }

                            final address = snapshot.data;

                            if (address == null || address.isEmpty) {
                              return Text(
                                '$lat, $lng',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurface
                                      .withOpacity(0.5),
                                ),
                              );
                            }

                            return Text(
                              address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurface
                                    .withOpacity(0.5),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  Icon(
                    Icons.open_in_new,
                    size: 16,
                    color: colorScheme.onSurface.withOpacity(0.4),
                  ),
                ],
              ),
            ),
          ),

          // ── 상대 메시지 시간 ─────────────────────
          if (!isMe) ...[
            const SizedBox(width: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (unreadCount > 0)
                  Text(
                    unreadCount.toString(),
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
