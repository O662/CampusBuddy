import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../data/local_store.dart';
import '../../state/app_state.dart';

/// A place for the weather widget. Found via automatic IP geolocation, or by
/// searching a city. Stored locally — no account.
class WeatherLocation {
  const WeatherLocation(this.name, this.lat, this.lon);
  final String name;
  final double lat;
  final double lon;

  Map<String, dynamic> toJson() => {'name': name, 'lat': lat, 'lon': lon};
  factory WeatherLocation.fromJson(Map j) => WeatherLocation(
        j['name'] as String,
        (j['lat'] as num).toDouble(),
        (j['lon'] as num).toDouble(),
      );
}

class WeatherData {
  const WeatherData({
    required this.tempC,
    required this.hiC,
    required this.loC,
    required this.code,
    required this.place,
    required this.fetchedAt,
    this.provider = 'om',
  });

  final double tempC;
  final double hiC;
  final double loC;
  final int code;
  final String place;
  final DateTime fetchedAt;

  /// 'om' = Open-Meteo (WMO codes), 'owm' = OpenWeatherMap (its own codes).
  final String provider;

  (String, IconData) get _desc =>
      provider == 'owm' ? _owm(code) : _wmo(code);
  String get description => _desc.$1;
  IconData get icon => _desc.$2;

  Map<String, dynamic> toJson() => {
        'tempC': tempC,
        'hiC': hiC,
        'loC': loC,
        'code': code,
        'place': place,
        'fetchedAt': fetchedAt.millisecondsSinceEpoch,
        'provider': provider,
      };
  factory WeatherData.fromJson(Map j) => WeatherData(
        tempC: (j['tempC'] as num).toDouble(),
        hiC: (j['hiC'] as num).toDouble(),
        loC: (j['loC'] as num).toDouble(),
        code: (j['code'] as num).toInt(),
        place: j['place'] as String,
        fetchedAt:
            DateTime.fromMillisecondsSinceEpoch(j['fetchedAt'] as int),
        provider: j['provider'] as String? ?? 'om',
      );
}

/// WMO weather code → (label, icon) — Open-Meteo.
(String, IconData) _wmo(int c) {
  if (c == 0) return ('Clear sky', Icons.wb_sunny_rounded);
  if (c <= 2) return ('Partly cloudy', Icons.wb_cloudy_outlined);
  if (c == 3) return ('Overcast', Icons.cloud_rounded);
  if (c <= 48) return ('Fog', Icons.foggy);
  if (c <= 57) return ('Drizzle', Icons.grain_rounded);
  if (c <= 67) return ('Rain', Icons.umbrella_rounded);
  if (c <= 77) return ('Snow', Icons.ac_unit_rounded);
  if (c <= 82) return ('Rain showers', Icons.umbrella_rounded);
  if (c <= 86) return ('Snow showers', Icons.ac_unit_rounded);
  return ('Thunderstorm', Icons.thunderstorm_rounded);
}

/// OpenWeatherMap condition id → (label, icon).
(String, IconData) _owm(int id) {
  if (id >= 200 && id < 300) {
    return ('Thunderstorm', Icons.thunderstorm_rounded);
  }
  if (id >= 300 && id < 400) return ('Drizzle', Icons.grain_rounded);
  if (id >= 500 && id < 600) return ('Rain', Icons.umbrella_rounded);
  if (id >= 600 && id < 700) return ('Snow', Icons.ac_unit_rounded);
  if (id >= 700 && id < 800) return ('Fog', Icons.foggy);
  if (id == 800) return ('Clear sky', Icons.wb_sunny_rounded);
  if (id == 801 || id == 802) {
    return ('Partly cloudy', Icons.wb_cloudy_outlined);
  }
  return ('Overcast', Icons.cloud_rounded);
}

class WeatherService {
  static const _geo = 'https://geocoding-api.open-meteo.com/v1/search';
  static const _om = 'https://api.open-meteo.com/v1/forecast';
  static const _owmBase =
      'https://api.openweathermap.org/data/2.5/weather';
  static const _ip = 'https://ipwho.is/';
  static const _timeout = Duration(seconds: 9);

  static String _placeName(Map r) => [
        r['name'] ?? r['city'],
        r['admin1'] ?? r['region'],
        r['country_code'] ?? r['country'],
      ]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .take(2)
          .join(', ');

  /// Approximate (city-level) location from the device's IP — no key, no
  /// permissions, works on every platform.
  static Future<WeatherLocation?> ipLocate() async {
    final res = await http.get(Uri.parse(_ip)).timeout(_timeout);
    if (res.statusCode != 200) return null;
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    if (j['success'] == false) return null;
    final lat = (j['latitude'] as num?)?.toDouble();
    final lon = (j['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    return WeatherLocation(_placeName(j), lat, lon);
  }

  /// Up to [limit] matching places for a typed query — surfacing several
  /// results so smaller towns are selectable, not just big cities.
  static Future<List<WeatherLocation>> search(String query,
      {int limit = 6}) async {
    final uri = Uri.parse(
        '$_geo?name=${Uri.encodeQueryComponent(query)}&count=$limit'
        '&language=en&format=json');
    final res = await http.get(uri).timeout(_timeout);
    if (res.statusCode != 200) return const [];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final results = body['results'] as List?;
    if (results == null) return const [];
    return [
      for (final r in results.cast<Map<String, dynamic>>())
        WeatherLocation(
          _placeName(r),
          (r['latitude'] as num).toDouble(),
          (r['longitude'] as num).toDouble(),
        ),
    ];
  }

  static Future<WeatherData> fetch(WeatherLocation loc,
      {String apiKey = ''}) async {
    return apiKey.trim().isEmpty
        ? _fetchOpenMeteo(loc)
        : _fetchOwm(loc, apiKey.trim());
  }

  static Future<WeatherData> _fetchOpenMeteo(WeatherLocation loc) async {
    final uri = Uri.parse('$_om?latitude=${loc.lat}&longitude=${loc.lon}'
        '&current=temperature_2m,weather_code'
        '&daily=temperature_2m_max,temperature_2m_min,weather_code'
        '&timezone=auto&forecast_days=1');
    final res = await http.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('Weather request failed (${res.statusCode})');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final cur = j['current'] as Map<String, dynamic>;
    final daily = j['daily'] as Map<String, dynamic>;
    return WeatherData(
      tempC: (cur['temperature_2m'] as num).toDouble(),
      code: (cur['weather_code'] as num).toInt(),
      hiC: ((daily['temperature_2m_max'] as List).first as num).toDouble(),
      loC: ((daily['temperature_2m_min'] as List).first as num).toDouble(),
      place: loc.name,
      fetchedAt: DateTime.now(),
      provider: 'om',
    );
  }

  static Future<WeatherData> _fetchOwm(
      WeatherLocation loc, String key) async {
    final uri = Uri.parse('$_owmBase?lat=${loc.lat}&lon=${loc.lon}'
        '&units=metric&appid=$key');
    final res = await http.get(uri).timeout(_timeout);
    if (res.statusCode == 401) {
      throw Exception('Invalid OpenWeatherMap API key.');
    }
    if (res.statusCode != 200) {
      throw Exception('Weather request failed (${res.statusCode})');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final main = j['main'] as Map<String, dynamic>;
    final w = (j['weather'] as List).first as Map<String, dynamic>;
    final name = (j['name'] as String?) ?? loc.name;
    return WeatherData(
      tempC: (main['temp'] as num).toDouble(),
      hiC: (main['temp_max'] as num).toDouble(),
      loC: (main['temp_min'] as num).toDouble(),
      code: (w['id'] as num).toInt(),
      place: name.isEmpty ? loc.name : name,
      fetchedAt: DateTime.now(),
      provider: 'owm',
    );
  }
}

// --- Providers --------------------------------------------------------------

class WeatherLocationNotifier extends Notifier<WeatherLocation?> {
  static const _key = 'weatherLocation';
  dynamic get _box => ref.read(localStoreProvider).box(LocalStore.settings);

  @override
  WeatherLocation? build() {
    final raw = _box.get(_key);
    return raw is Map ? WeatherLocation.fromJson(raw) : null;
  }

  Future<void> set(WeatherLocation loc) async {
    await _box.put(_key, loc.toJson());
    state = loc;
  }

  /// Detect via IP and save. Returns the detected location, or null on
  /// failure (so callers can keep showing the manual options).
  Future<WeatherLocation?> detectFromIp() async {
    try {
      final loc = await WeatherService.ipLocate();
      if (loc != null) await set(loc);
      return loc;
    } catch (_) {
      return null;
    }
  }
}

final weatherLocationProvider =
    NotifierProvider<WeatherLocationNotifier, WeatherLocation?>(
        WeatherLocationNotifier.new);

class UnitNotifier extends Notifier<bool> {
  static const _key = 'weatherFahrenheit';
  dynamic get _box => ref.read(localStoreProvider).box(LocalStore.settings);

  @override
  bool build() => _box.get(_key) == true;

  Future<void> toggle() async {
    final next = !state;
    await _box.put(_key, next);
    state = next;
  }
}

/// true == show °F, false == °C.
final weatherFahrenheitProvider =
    NotifierProvider<UnitNotifier, bool>(UnitNotifier.new);

/// Optional OpenWeatherMap API key. Empty → use Open-Meteo (no key).
class OwmKeyNotifier extends Notifier<String> {
  static const _key = 'owmApiKey';
  dynamic get _box => ref.read(localStoreProvider).box(LocalStore.settings);

  @override
  String build() => (_box.get(_key) as String?) ?? '';

  Future<void> save(String value) async {
    await _box.put(_key, value.trim());
    state = value.trim();
  }
}

final owmKeyProvider =
    NotifierProvider<OwmKeyNotifier, String>(OwmKeyNotifier.new);

/// Fetches weather for the saved location (auto-detecting via IP the first
/// time if none is set), caching the last good result for offline display.
final weatherProvider = FutureProvider<WeatherData?>((ref) async {
  final apiKey = ref.watch(owmKeyProvider);
  var loc = ref.watch(weatherLocationProvider);
  loc ??= await ref.read(weatherLocationProvider.notifier).detectFromIp();
  if (loc == null) return null;

  final box = ref.read(localStoreProvider).box(LocalStore.settings);
  try {
    final data = await WeatherService.fetch(loc, apiKey: apiKey);
    await box.put('weatherCache', data.toJson());
    return data;
  } catch (_) {
    final cached = box.get('weatherCache');
    if (cached is Map) return WeatherData.fromJson(cached);
    rethrow;
  }
});
