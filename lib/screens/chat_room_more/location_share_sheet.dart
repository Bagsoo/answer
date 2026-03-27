import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../l10n/app_localizations.dart';
import 'location_picker_map_screen.dart';

class LocationShareResult {
  final double lat;
  final double lng;
  final String type; // 'current' or 'destination'

  const LocationShareResult({
    required this.lat,
    required this.lng,
    required this.type,
  });
}

class LocationShareSheet extends StatefulWidget {
  const LocationShareSheet({super.key});

  @override
  State<LocationShareSheet> createState() => _LocationShareSheetState();
}

class _LocationShareSheetState extends State<LocationShareSheet> {
  bool _loading = false;
  String? _error;

  Future<void> _shareCurrentLocation() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1. 위치 서비스 확인
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _error = AppLocalizations.of(context).locationServiceDisabled;
          _loading = false;
        });
        return;
      }

      // 2. 권한 체크
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();

        if (permission == LocationPermission.denied) {
          setState(() {
            _error = AppLocalizations.of(context).locationPermissionRequired;
            _loading = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _error = AppLocalizations.of(context).locationPermissionOpenSettings;
          _loading = false;
        });
        return;
      }

      // 3. 위치 가져오기 (빠르게)
      Position? position = await Geolocator.getLastKnownPosition();

      position ??= await Geolocator.getCurrentPosition(
        locationSettings: Platform.isAndroid
            ? AndroidSettings(
                accuracy: LocationAccuracy.medium,
              )
            : AppleSettings(
                accuracy: LocationAccuracy.medium,
              ),
      );

      // 4. 결과 반환
      if (mounted) {
        Navigator.pop(
          context,
          LocationShareResult(
            lat: position.latitude,
            lng: position.longitude,
            type: 'current',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context).locationFetchFailed;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 핸들
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // 제목
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.attachLocation,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // 현재 위치 공유 버튼
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.my_location, color: Colors.blue),
              ),
              title: Text(l.locationCurrent),
              subtitle: Text(
                l.locationShareCurrentDesc,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withOpacity(0.5),
                ),
              ),
              trailing: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _loading ? null : _shareCurrentLocation,
            ),

            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.place, color: Colors.red),
              ),
              title: Text(l.locationDestination),
              subtitle: Text(
                l.locationShareDestinationDesc,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withOpacity(0.5),
                ),
              ),
              onTap: () async {
                final result = await Navigator.push<LocationShareResult>(
                    context,
                    MaterialPageRoute(
                    builder: (_) => const LocationPickerMapScreen(),
                    ),
                );

                if (result != null && mounted) {
                    Navigator.pop(context, result);
                }
              },
            ),

            // 에러 메시지
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: cs.error,
                    fontSize: 12,
                  ),
                ),
              ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
