import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../l10n/app_localizations.dart';
import 'dart:io';

/// 위치 선택 결과
class LocationResult {
  final double latitude;
  final double longitude;
  final String name; // 표시용 이름 (예: "강남역", "Shinjuku Station")

  const LocationResult({
    required this.latitude,
    required this.longitude,
    required this.name,
  });
}

/// 위치 선택 바텀시트
/// - Google Places Autocomplete로 장소 검색
/// - 현재 위치 자동 감지
class LocationPickerSheet extends StatefulWidget {
  final String googleApiKey;
  final String languageCode; // 자동완성 언어 (ko, en, ja 등)
  final LocationResult? initialLocation;

  const LocationPickerSheet({
    super.key,
    required this.googleApiKey,
    this.languageCode = 'ko',
    this.initialLocation,
  });

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  final _searchCtrl = TextEditingController();
  List<_PlacePrediction> _predictions = [];
  bool _searching = false;
  bool _loadingCurrentLocation = false;
  String? _errorMsg;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Google Places Autocomplete ────────────────────────────────────────────
  Future<void> _searchPlaces(String input) async {
    if (input.trim().isEmpty) {
      setState(() => _predictions = []);
      return;
    }

    setState(() => _searching = true);

    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/autocomplete/json',
        {
          'input': input,
          'key': widget.googleApiKey,
          'language': widget.languageCode,
          // 'types': 'geocode|establishment|transit_station',
        },
      );

      final response = await http.get(uri);
      if (!mounted) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final predictions = (data['predictions'] as List? ?? [])
          .map((p) => _PlacePrediction(
                placeId: p['place_id'] as String,
                description: p['description'] as String,
                mainText: (p['structured_formatting']?['main_text'] as String?) ??
                    (p['description'] as String),
                secondaryText:
                    p['structured_formatting']?['secondary_text'] as String? ?? '',
              ))
          .toList();

      setState(() {
        _predictions = predictions;
        _searching = false;
      });
    } catch (e) {
      if (mounted) setState(() => _searching = false);
    }
  }

  // ── Place Details로 좌표 가져오기 ─────────────────────────────────────────
  Future<LocationResult?> _getPlaceDetails(
      String placeId, String name) async {
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/details/json',
        {
          'place_id': placeId,
          'key': widget.googleApiKey,
          'fields': 'geometry,name',
          'language': widget.languageCode,
        },
      );

      final response = await http.get(uri);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final location =
          data['result']?['geometry']?['location'] as Map<String, dynamic>?;

      if (location == null) return null;

      return LocationResult(
        latitude: (location['lat'] as num).toDouble(),
        longitude: (location['lng'] as num).toDouble(),
        name: name,
      );
    } catch (e) {
      return null;
    }
  }

  // ── 현재 위치 감지 ────────────────────────────────────────────────────────
  Future<void> _useCurrentLocation() async {
    setState(() {
      _loadingCurrentLocation = true;
      _errorMsg = null;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _errorMsg = '위치 서비스가 비활성화되어 있어요.';
            _loadingCurrentLocation = false;
          });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _errorMsg = '위치 권한이 필요해요.';
              _loadingCurrentLocation = false;
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _errorMsg = '위치 권한을 설정에서 허용해주세요.';
            _loadingCurrentLocation = false;
          });
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: Platform.isAndroid
            ? AndroidSettings(
                accuracy: LocationAccuracy.medium,
                timeLimit: const Duration(seconds: 30),
              )
            : AppleSettings(
                accuracy: LocationAccuracy.medium,
                timeLimit: const Duration(seconds: 30),
                activityType: ActivityType.other,
              ),
      );

      if (!mounted) return;

      // 역지오코딩으로 장소명 가져오기
      final locationName =
          await _reverseGeocode(position.latitude, position.longitude);

      if (mounted) {
        Navigator.pop(
          context,
          LocationResult(
            latitude: position.latitude,
            longitude: position.longitude,
            name: locationName,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        debugPrint('현재위치 에러: $e');
        setState(() {
          _errorMsg = '위치를 가져오지 못했어요. 다시 시도해주세요.';
          _loadingCurrentLocation = false;
        });
      }
    }
  }

  // ── 역지오코딩 (좌표 → 장소명) ───────────────────────────────────────────
  Future<String> _reverseGeocode(double lat, double lng) async {
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/geocode/json',
        {
          'latlng': '$lat,$lng',
          'key': widget.googleApiKey,
          'language': widget.languageCode,
          'result_type': 'sublocality|locality',
        },
      );
      final response = await http.get(uri);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List?;
      if (results != null && results.isNotEmpty) {
        return results[0]['formatted_address'] as String? ?? '현재 위치';
      }
    } catch (_) {}
    return '현재 위치';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 핸들 바 ──────────────────────────────────────────────
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ── 헤더 ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(children: [
                Expanded(
                  child: Text(l.selectLocation,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  visualDensity: VisualDensity.compact,
                ),
              ]),
            ),

            // ── 검색창 ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (v) => _searchPlaces(v),
                decoration: InputDecoration(
                  hintText: l.searchLocationHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _predictions = []);
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ── 현재 위치 버튼 ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InkWell(
                onTap: _loadingCurrentLocation ? null : _useCurrentLocation,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: cs.primary.withOpacity(0.2)),
                  ),
                  child: Row(children: [
                    _loadingCurrentLocation
                        ? SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: cs.primary))
                        : Icon(Icons.my_location,
                            color: cs.primary, size: 20),
                    const SizedBox(width: 12),
                    Text(l.useCurrentLocation,
                        style: TextStyle(
                            color: cs.primary,
                            fontWeight: FontWeight.w500)),
                  ]),
                ),
              ),
            ),

            // ── 에러 메시지 ──────────────────────────────────────────
            if (_errorMsg != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(_errorMsg!,
                    style: TextStyle(
                        color: cs.error, fontSize: 12)),
              ),

            const SizedBox(height: 8),
            const Divider(height: 1),

            // ── 검색 결과 ────────────────────────────────────────────
            Flexible(
              child: _searching
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _predictions.isEmpty && _searchCtrl.text.isNotEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(l.noSearchResults,
                                style: TextStyle(
                                    color: cs.onSurface.withOpacity(0.4))),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _predictions.length,
                          itemBuilder: (context, i) {
                            final p = _predictions[i];
                            return ListTile(
                              leading: Icon(Icons.place_outlined,
                                  color: cs.primary),
                              title: Text(p.mainText,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500)),
                              subtitle: p.secondaryText.isNotEmpty
                                  ? Text(p.secondaryText,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: cs.onSurface
                                              .withOpacity(0.5)))
                                  : null,
                              onTap: () async {
                                final result = await _getPlaceDetails(
                                    p.placeId, p.mainText);
                                if (result != null && context.mounted) {
                                  Navigator.pop(context, result);
                                }
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

class _PlacePrediction {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  _PlacePrediction({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });
}