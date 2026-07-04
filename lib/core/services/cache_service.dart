// lib/core/services/cache_service.dart
// Simple Hive-based cache for dashboard statistics and key feature outputs.

import 'package:hive_flutter/hive_flutter.dart';

class CacheService {
  static const String _statsBoxName = 'stats_cache';
  static Box<dynamic>? _statsBox;

  static Future<void> init() async {
    await Hive.initFlutter();
    _statsBox = await Hive.openBox<dynamic>(_statsBoxName);
  }

  static Box<dynamic>? get _box => _statsBox;

  // ───────────── Energy ─────────────
  static Future<void> setEnergy(String city, String value, String date) async {
    final box = _box;
    if (box == null) return;
    await box.put('energy_city', city);
    await box.put('energy_value', value);
    await box.put('energy_date', date);
  }

  static Map<String, String>? getEnergy() {
    final box = _box;
    if (box == null) return null;
    final String? value = box.get('energy_value') as String?;
    if (value == null) return null;
    final String city = box.get('energy_city') as String? ?? '';
    final String date = box.get('energy_date') as String? ?? '';
    return {
      'city': city,
      'value': value,
      'date': date,
    };
  }

  // ───────────── Traffic ─────────────
  static Future<void> setTraffic(String city, String value) async {
    final box = _box;
    if (box == null) return;
    await box.put('traffic_city', city);
    await box.put('traffic_value', value);
  }

  static String? getTraffic() {
    final box = _box;
    if (box == null) return null;
    return box.get('traffic_value') as String?;
  }

  // ───────────── Crime Status ─────────────
  static Future<void> setCrimeStatus(String status) async {
    final box = _box;
    if (box == null) return;
    await box.put('crime_status', status);
  }

  static String? getCrimeStatus() {
    final box = _box;
    if (box == null) return null;
    return box.get('crime_status') as String?;
  }
}
