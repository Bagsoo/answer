import 'dart:convert';

import 'package:flutter/material.dart';
import '../../config/env_config.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../../l10n/app_localizations.dart';
import 'location_share_sheet.dart';

class LocationPickerMapScreen extends StatefulWidget {
  const LocationPickerMapScreen({super.key});

  @override
  State<LocationPickerMapScreen> createState() =>
      _LocationPickerMapScreenState();
}

class _LocationPickerMapScreenState
    extends State<LocationPickerMapScreen> {
  final TextEditingController _searchController = TextEditingController();
  LatLng _selected = const LatLng(37.5665, 126.9780); // 서울 기본
  String? _selectedName;
  String? _selectedAddress;
  GoogleMapController? _controller;
  bool _searching = false;

  void _onTap(LatLng latLng) {
    setState(() {
      _selected = latLng;
      _selectedName = null;
      _selectedAddress = null;
    });
    _reverseGeocode(latLng);
  }

  Future<void> _reverseGeocode(LatLng latLng) async {
    final apiKey = EnvConfig.mapsApiKey;
    if (apiKey.isEmpty) return;

    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/geocode/json',
        {
          'latlng': '${latLng.latitude},${latLng.longitude}',
          'key': apiKey,
          'language': Localizations.localeOf(context).languageCode,
        },
      );

      final response = await http.get(uri);
      final data = jsonDecode(response.body);

      if (data['status'] == 'OK') {
        final results = data['results'] as List;
        if (results.isNotEmpty) {
          setState(() {
            _selectedAddress = results.first['formatted_address'];
            // 이름은 보통 첫번째 결과의 name이나 특정 컴포넌트인데 geocoding은 주소 위주임.
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchLocation() async {
    final l = AppLocalizations.of(context);
    final query = _searchController.text.trim();
    final apiKey = EnvConfig.mapsApiKey;

    if (query.isEmpty || apiKey.isEmpty) return;

    setState(() => _searching = true);

    try {
      // ── Google Places Text Search 사용 (가게 이름 등으로 검색 가능) ──
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/textsearch/json',
        {
          'query': query,
          'key': apiKey,
          'language': Localizations.localeOf(context).languageCode,
        },
      );

      final response = await http.get(uri);
      if (!mounted) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List? ?? [];

      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.noSearchResults)),
        );
        return;
      }

      final first = results.first;
      final location = first['geometry']?['location'] as Map<String, dynamic>?;
      if (location == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.noSearchResults)),
        );
        return;
      }

      final latLng = LatLng(
        (location['lat'] as num).toDouble(),
        (location['lng'] as num).toDouble(),
      );

      setState(() {
        _selected = latLng;
        _selectedAddress = first['formatted_address'];
        _selectedName = first['name']; // 장소 이름 (예: 스타벅스 강남점)
      });
      await _controller?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: latLng, zoom: 16),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.locationFetchFailed)),
      );
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  void _confirm() {
    Navigator.pop(
      context,
      LocationShareResult(
        lat: _selected.latitude,
        lng: _selected.longitude,
        type: 'destination',
        name: _selectedName,
        address: _selectedAddress,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.locationDestination),
        actions: [
          TextButton(
            onPressed: _confirm,
            child: Text(
              l.shareMessage,
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          )
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _selected,
              zoom: 14,
            ),
            onTap: _onTap,
            onMapCreated: (controller) {
              _controller = controller;
            },
            markers: {
              Marker(
                markerId: const MarkerId('selected'),
                position: _selected,
              ),
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(14),
                color: cs.surface,
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _searchLocation(),
                  decoration: InputDecoration(
                    hintText: l.searchLocationHint,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.arrow_forward),
                            onPressed: _searchLocation,
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: cs.surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
