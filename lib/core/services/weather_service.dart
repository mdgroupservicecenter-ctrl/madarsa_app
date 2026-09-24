import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'salat_time_service.dart';

class WeatherData {
  final String cityName;
  final double temperature;
  final String condition;
  final IconData icon;
  final int humidity;
  final double windSpeed;
  final bool isDay;
  final DateTime lastUpdated;

  const WeatherData({
    required this.cityName,
    required this.temperature,
    required this.condition,
    required this.icon,
    required this.humidity,
    required this.windSpeed,
    required this.isDay,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
        'cityName': cityName,
        'temperature': temperature,
        'condition': condition,
        'humidity': humidity,
        'windSpeed': windSpeed,
        'isDay': isDay,
        'lastUpdated': lastUpdated.toIso8601String(),
      };

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    final condition = json['condition'] as String? ?? 'Clear';
    final isDay = json['isDay'] as bool? ?? true;
    return WeatherData(
      cityName: json['cityName'] as String? ?? 'Local Area',
      temperature: (json['temperature'] as num?)?.toDouble() ?? 28.0,
      condition: condition,
      icon: WeatherService.getConditionIcon(condition, isDay),
      humidity: (json['humidity'] as num?)?.toInt() ?? 50,
      windSpeed: (json['windSpeed'] as num?)?.toDouble() ?? 10.0,
      isDay: isDay,
      lastUpdated: DateTime.tryParse(json['lastUpdated'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class WeatherService {
  static const _cacheKey = 'dashboard_cached_weather';
  static const _cityKey = 'dashboard_weather_city';
  static const _latKey = 'dashboard_weather_lat';
  static const _lonKey = 'dashboard_weather_lon';

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  /// Load cached weather data from SharedPreferences
  static Future<WeatherData?> getCachedWeather() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return WeatherData.fromJson(map);
      }
    } catch (_) {}
    return null;
  }

  /// Get current saved city or default
  static Future<String> getSavedCity() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cityKey) ?? 'Deoband';
  }

  /// Fetch live weather from free open API
  static Future<WeatherData> fetchWeather({String? cityOverride}) async {
    final prefs = await SharedPreferences.getInstance();
    String city = cityOverride ?? prefs.getString(_cityKey) ?? 'Deoband';
    double lat = prefs.getDouble(_latKey) ?? 29.6976;
    double lon = prefs.getDouble(_lonKey) ?? 77.6749;

    // If city changed or coordinates not found, geocode the city name
    if (cityOverride != null && cityOverride.trim().isNotEmpty) {
      city = cityOverride.trim();

      // Check standard preset city first for instant exact resolution
      final preset = SalatTimeService.findPresetCity(city);
      if (preset != null) {
        lat = preset.latitude;
        lon = preset.longitude;
        city = preset.name;
        await prefs.setString(_cityKey, city);
        await prefs.setDouble(_latKey, lat);
        await prefs.setDouble(_lonKey, lon);
        await SalatTimeService.setCityAndCoordinates(city, lat, lon, tz: preset.timeZone);
      } else {
        final geo = await geocodeCity(city);
        if (geo != null) {
          lat = geo['lat']!;
          lon = geo['lon']!;
          city = geo['name']!;
          final tz = geo['tz'] as double? ?? 5.5;
          await prefs.setString(_cityKey, city);
          await prefs.setDouble(_latKey, lat);
          await prefs.setDouble(_lonKey, lon);
          await SalatTimeService.setCityAndCoordinates(city, lat, lon, tz: tz);
        }
      }
    } else if (!prefs.containsKey(_latKey)) {
      // First time: default Deoband coordinates
      await prefs.setString(_cityKey, 'Deoband');
      await prefs.setDouble(_latKey, 29.6976);
      await prefs.setDouble(_lonKey, 77.6749);
    }

    try {
      final url =
          'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m,is_day,weather_code,wind_speed_10m';
      final res = await _dio.get(url);

      if (res.statusCode == 200 && res.data is Map) {
        final current = res.data['current'] as Map<String, dynamic>;
        final temp = (current['temperature_2m'] as num).toDouble();
        final humidity = (current['relative_humidity_2m'] as num).toInt();
        final isDay = (current['is_day'] as num? ?? 1) == 1;
        final weatherCode = (current['weather_code'] as num? ?? 0).toInt();
        final wind = (current['wind_speed_10m'] as num? ?? 0.0).toDouble();

        final condition = _wmoCodeToCondition(weatherCode);
        final weather = WeatherData(
          cityName: city,
          temperature: temp,
          condition: condition,
          icon: getConditionIcon(condition, isDay),
          humidity: humidity,
          windSpeed: wind,
          isDay: isDay,
          lastUpdated: DateTime.now(),
        );

        await prefs.setString(_cacheKey, jsonEncode(weather.toJson()));
        return weather;
      }
    } catch (e) {
      // Offline fallback: try cache
      final cached = await getCachedWeather();
      if (cached != null) return cached;
    }

    // Default fallback
    return WeatherData(
      cityName: city,
      temperature: 28.0,
      condition: 'Clear Sky',
      icon: Icons.wb_sunny_rounded,
      humidity: 55,
      windSpeed: 12.0,
      isDay: true,
      lastUpdated: DateTime.now(),
    );
  }

  static double timezoneNameToHours(String? tzName) {
    if (tzName == null) return 5.5;
    if (tzName.contains('Kolkata') || tzName.contains('Calcutta')) return 5.5;
    if (tzName.contains('Karachi')) return 5.0;
    if (tzName.contains('Dhaka')) return 6.0;
    if (tzName.contains('Riyadh')) return 3.0;
    if (tzName.contains('Dubai')) return 4.0;
    if (tzName.contains('London')) return 0.0;
    if (tzName.contains('Cairo')) return 2.0;
    if (tzName.contains('Istanbul')) return 3.0;
    if (tzName.contains('Jakarta')) return 7.0;
    if (tzName.contains('Kuala_Lumpur')) return 8.0;
    if (tzName.contains('New_York')) return -5.0;
    return 5.5;
  }

  static Future<Map<String, dynamic>?> geocodeCity(String query) async {
    // Check preset first
    final preset = SalatTimeService.findPresetCity(query);
    if (preset != null) {
      return {
        'lat': preset.latitude,
        'lon': preset.longitude,
        'name': preset.name,
        'tz': preset.timeZone,
      };
    }

    try {
      final url = 'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(query)}&count=1&language=en&format=json';
      final res = await _dio.get(url);
      if (res.statusCode == 200 && res.data is Map && res.data['results'] != null) {
        final list = res.data['results'] as List;
        if (list.isNotEmpty) {
          final first = list.first as Map<String, dynamic>;
          final tzName = first['timezone'] as String?;
          return {
            'lat': (first['latitude'] as num).toDouble(),
            'lon': (first['longitude'] as num).toDouble(),
            'name': first['name'] as String,
            'tz': timezoneNameToHours(tzName),
          };
        }
      }
    } catch (_) {}
    return null;
  }

  static String _wmoCodeToCondition(int code) {
    if (code == 0) return 'Clear Sky';
    if (code == 1) return 'Mainly Clear';
    if (code == 2) return 'Partly Cloudy';
    if (code == 3) return 'Overcast';
    if (code >= 45 && code <= 48) return 'Foggy';
    if (code >= 51 && code <= 55) return 'Light Drizzle';
    if (code >= 61 && code <= 65) return 'Rain';
    if (code >= 71 && code <= 77) return 'Snow Flurries';
    if (code >= 80 && code <= 82) return 'Rain Showers';
    if (code >= 95 && code <= 99) return 'Thunderstorm';
    return 'Partly Cloudy';
  }

  static IconData getConditionIcon(String condition, bool isDay) {
    switch (condition.toLowerCase()) {
      case 'clear sky':
      case 'mainly clear':
        return isDay ? Icons.wb_sunny_rounded : Icons.nightlight_round;
      case 'partly cloudy':
        return isDay ? Icons.wb_cloudy_rounded : Icons.nights_stay_rounded;
      case 'overcast':
        return Icons.cloud_rounded;
      case 'foggy':
        return Icons.foggy;
      case 'light drizzle':
      case 'rain':
      case 'rain showers':
        return Icons.water_drop_rounded;
      case 'snow flurries':
        return Icons.ac_unit_rounded;
      case 'thunderstorm':
        return Icons.thunderstorm_rounded;
      default:
        return isDay ? Icons.wb_sunny_rounded : Icons.nightlight_round;
    }
  }
}
