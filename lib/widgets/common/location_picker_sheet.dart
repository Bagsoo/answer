import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../l10n/app_localizations.dart';
import '../../services/local_preferences_service.dart';
import 'dart:io';

/// 위치 선택 결과
class LocationResult {
  final double latitude;
  final double longitude;
  final String name;
  final String address;

  const LocationResult({
    required this.latitude,
    required this.longitude,
    required this.name,
    required this.address,
  });
}

/// 위치 선택 바텀시트
class LocationPickerSheet extends StatefulWidget {
  final String googleApiKey;
  final String languageCode;
  final LocationResult? initialLocation;
  final bool showCurrentLocation;
  final bool showGroupHint;

  const LocationPickerSheet({
    super.key,
    required this.googleApiKey,
    this.languageCode = 'ko',
    this.initialLocation,
    this.showCurrentLocation = true,
    this.showGroupHint = false,
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

  String get _searchKey => LocalPreferencesService.groupLocationSearchKey(
        FirebaseAuth.instance.currentUser?.uid ?? 'guest',
      );

  @override
  void initState() {
    super.initState();
    _restoreRecentSearch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _restoreRecentSearch() async {
    if (!widget.showGroupHint) return;
    final saved = await LocalPreferencesService.getString(_searchKey);
    if (!mounted || saved == null || saved.isEmpty) return;
    _searchCtrl.text = saved;
    _searchCtrl.selection = TextSelection.collapsed(offset: saved.length);
    await _searchPlaces(saved);
  }

  Future<void> _saveRecentSearch(String query) async {
    if (!widget.showGroupHint) return;
    await LocalPreferencesService.setString(_searchKey, query);
  }

  // ── Google Places Autocomplete (Cloud Functions Proxy) ──────────────────
  Future<void> _searchPlaces(String input) async {
    if (input.trim().isEmpty) {
      setState(() => _predictions = []);
      return;
    }
    setState(() {
      _searching = true;
      _errorMsg = null;
    });

    try {
      // 클라이언트에서 직접 호출 대신 Firebase Cloud Functions 호출
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('getGooglePlacesAutocomplete');
      
      final response = await callable.call({
        'input': input,
        'language': widget.languageCode,
      });

      if (!mounted) return;

      // 타입을 명시적으로 변환 (Map<Object?, Object?> -> Map<String, dynamic>)
      final Map<String, dynamic> data = Map<String, dynamic>.from(response.data as Map);
      
      if (data['status'] != 'OK' && data['status'] != 'ZERO_RESULTS') {
        final String? msg = data['error_message'] as String?;
        debugPrint('Cloud Function Google Places Error: ${data['status']} - $msg');
        if (mounted) {
          setState(() {
            _searching = false;
            _errorMsg = msg ?? 'API Error: ${data['status']}';
          });
        }
        return;
      }

      final predictions = (data['predictions'] as List? ?? [])
          .map((p) {
            final map = Map<String, dynamic>.from(p as Map);
            final structured = map['structured_formatting'] != null 
                ? Map<String, dynamic>.from(map['structured_formatting'] as Map)
                : null;
            
            return _PlacePrediction(
              placeId: map['place_id'] as String,
              mainText: (structured?['main_text'] as String?) ?? (map['description'] as String),
              secondaryText: (structured?['secondary_text'] as String?) ?? '',
              fullAddress: map['description'] as String,
            );
          })
          .toList();

      setState(() {
        _predictions = predictions;
        _searching = false;
      });
    } catch (e) {
      debugPrint('Call Cloud Function error: $e');
      if (mounted) {
        setState(() {
          _searching = false;
          _errorMsg = AppLocalizations.of(context).locationSearchFailed;
        });
      }
    }
  }

  // ── Geocoding (Native SDK) 를 사용하여 주소를 좌표로 변환 ─────────────────────
  Future<LocationResult?> _getPlaceDetails(
      String placeId, String name, String fullAddress) async {
    try {
      // 1. Native Geocoding 시도 (가장 안전)
      List<Location> locations = await locationFromAddress(fullAddress);
      if (locations.isNotEmpty) {
        final loc = locations.first;
        return LocationResult(
          latitude: loc.latitude,
          longitude: loc.longitude,
          name: name,
          address: fullAddress,
        );
      }
    } catch (e) {
      debugPrint('Native Geocoding failed, falling back to Cloud Functions: $e');
    }

    // 2. Fallback: Cloud Functions Proxy for Place Details
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('getGooglePlaceDetails');
      
      final response = await callable.call({
        'placeId': placeId,
        'language': widget.languageCode,
      });

      final Map<String, dynamic> data = Map<String, dynamic>.from(response.data as Map);
      final resultRaw = data['result'];
      if (resultRaw == null) return null;
      final result = Map<String, dynamic>.from(resultRaw as Map);
      
      final geometryRaw = result['geometry'];
      if (geometryRaw == null) return null;
      final geometry = Map<String, dynamic>.from(geometryRaw as Map);
      
      final locRaw = geometry['location'];
      if (locRaw == null) return null;
      final loc = Map<String, dynamic>.from(locRaw as Map);

      return LocationResult(
        latitude: (loc['lat'] as num).toDouble(),
        longitude: (loc['lng'] as num).toDouble(),
        name: name,
        address: result['formatted_address'] as String? ?? '',
      );
    } catch (e) {
      debugPrint('Cloud Function Place Details error: $e');
      return null;
    }
  }

  // ── 현재 위치 (Geolocator + Geocoding Native SDK) ─────────────────────────
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
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _errorMsg = '위치 권한이 필요해요. 설정에서 허용해주세요.';
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

      // Native SDK Geocoding 사용
      final address =
          await _reverseGeocodeNative(position.latitude, position.longitude);
      await _saveRecentSearch(address);

      if (mounted) {
        Navigator.pop(
          context,
          LocationResult(
            latitude: position.latitude,
            longitude: position.longitude,
            name: address,
            address: address,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = '위치를 가져오지 못했어요. 다시 시도해주세요.';
          _loadingCurrentLocation = false;
        });
      }
    }
  }

  // ── 역지오코딩 (Native SDK 사용) ──────────────────────────────────────────
  Future<String> _reverseGeocodeNative(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        // 한글 주소 조합 (예: 서울특별시 강남구 역삼동)
        final parts = [p.administrativeArea, p.locality, p.subLocality, p.thoroughfare]
            .where((s) => s != null && s.isNotEmpty)
            .toList();
        return parts.join(' ');
      }
    } catch (e) {
      debugPrint('Native Reverse Geocoding failed: $e');
    }
    return '현재 위치';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85),
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
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
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

            // ── 그룹 위치 안내 문구 ───────────────────────────────────
            if (widget.showGroupHint)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: cs.primary.withOpacity(0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l.groupLocationHint,
                          style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withOpacity(0.75),
                              height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── 검색창 ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: _searchPlaces,
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

            // ── 현재 위치 버튼 (유저 전용) ───────────────────────────
            if (widget.showCurrentLocation)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: InkWell(
                  onTap: _loadingCurrentLocation
                      ? null
                      : _useCurrentLocation,
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
                    style:
                        TextStyle(color: cs.error, fontSize: 12)),
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
                                    color: cs.onSurface
                                        .withOpacity(0.4))),
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
                                await _saveRecentSearch(
                                  _searchCtrl.text.trim(),
                                );
                                final result =
                                    await _getPlaceDetails(
                                        p.placeId, p.mainText, p.fullAddress);
                                if (result != null &&
                                    context.mounted) {
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
  final String mainText;
  final String secondaryText;
  final String fullAddress;

  _PlacePrediction({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
    required this.fullAddress,
  });
}
