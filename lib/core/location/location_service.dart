import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// `zitlas_location` — the exact shape `geo-location.js`'s `saveLocation()`
/// writes to `users/{uid}.location`. City/state come from reverse geocoding
/// and are what `location_food_engine.resolve_state()` actually reads;
/// lat/lng/timezone are kept for parity but never required.
class ResolvedLocation {
  const ResolvedLocation({
    this.latitude,
    this.longitude,
    this.timezone,
    this.city = '',
    this.district = '',
    this.state = '',
    this.country = '',
    this.pincode = '',
    this.savedAt,
  });

  final double? latitude;
  final double? longitude;
  final String? timezone;
  final String city;
  final String district;
  final String state;
  final String country;
  final String pincode;
  final DateTime? savedAt;

  bool get hasRegion => city.isNotEmpty || state.isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (timezone != null) 'timezone': timezone,
      'city': city,
      'district': district,
      'state': state,
      'country': country,
      'pincode': pincode,
      'savedAt': (savedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  factory ResolvedLocation.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const ResolvedLocation();
    return ResolvedLocation(
      latitude: (m['latitude'] as num?)?.toDouble(),
      longitude: (m['longitude'] as num?)?.toDouble(),
      timezone: m['timezone'] as String?,
      city: (m['city'] as String?) ?? '',
      district: (m['district'] as String?) ?? '',
      state: (m['state'] as String?) ?? '',
      country: (m['country'] as String?) ?? '',
      pincode: (m['pincode'] as String?) ?? '',
      savedAt: DateTime.tryParse((m['savedAt'] as String?) ?? ''),
    );
  }

  /// `AssessmentInput.location` on the backend just needs *a* dict — city/
  /// district/state is all `location_food_engine.resolve_state()` reads.
  Map<String, dynamic> toAssessmentPayload() => toMap();
}

enum LocationOutcome { granted, denied, deniedForever, serviceDisabled, timeout, error }

class LocationResult {
  const LocationResult(this.outcome, this.location);
  final LocationOutcome outcome;
  final ResolvedLocation? location;
}

/// Native port of `geo-location.js` — one-time, low-accuracy position fetch
/// (never a continuous watch) + the same free, no-key Nominatim reverse-geocode
/// call the website uses, so `state` resolves to a value
/// `location_food_engine.resolve_state()` already recognizes.
class LocationService {
  static const _nominatimUrl = 'https://nominatim.openstreetmap.org/reverse';

  Future<LocationOutcome> checkPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationOutcome.serviceDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return LocationOutcome.deniedForever;
    if (permission == LocationPermission.denied) return LocationOutcome.denied;
    return LocationOutcome.granted;
  }

  /// Mirrors `requestLocation()` (geo-location.js:91-123): coarse accuracy,
  /// 8s timeout, best-effort reverse geocode — a geocode failure still
  /// returns usable lat/lng rather than failing the whole call.
  Future<LocationResult> resolveCurrentLocation() async {
    final permissionOutcome = await checkPermission();
    if (permissionOutcome != LocationOutcome.granted) {
      return LocationResult(permissionOutcome, null);
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 8)),
      );
      final addr = await _reverseGeocode(pos.latitude, pos.longitude);
      final loc = ResolvedLocation(
        latitude: pos.latitude,
        longitude: pos.longitude,
        timezone: DateTime.now().timeZoneName,
        city: addr['city'] ?? '',
        district: addr['district'] ?? '',
        state: addr['state'] ?? '',
        country: addr['country'] ?? '',
        pincode: addr['pincode'] ?? '',
        savedAt: DateTime.now(),
      );
      return LocationResult(LocationOutcome.granted, loc);
    } on TimeoutException catch (_) {
      return const LocationResult(LocationOutcome.timeout, null);
    } catch (_) {
      return const LocationResult(LocationOutcome.error, null);
    }
  }

  Future<Map<String, String>> _reverseGeocode(double lat, double lon) async {
    try {
      final uri = Uri.parse('$_nominatimUrl?format=jsonv2&lat=$lat&lon=$lon&zoom=10&addressdetails=1');
      final res = await http
          .get(uri, headers: {'Accept': 'application/json', 'User-Agent': 'ZitlasMobile/1.0'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return const {};
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final addr = (data['address'] as Map?)?.cast<String, dynamic>() ?? const {};
      return {
        'city': (addr['city'] ?? addr['town'] ?? addr['village'] ?? addr['county'] ?? '').toString(),
        'district': (addr['county'] ?? addr['state_district'] ?? '').toString(),
        'state': (addr['state'] ?? '').toString(),
        'country': (addr['country'] ?? '').toString(),
        'pincode': (addr['postcode'] ?? '').toString(),
      };
    } catch (_) {
      return const {};
    }
  }
}
