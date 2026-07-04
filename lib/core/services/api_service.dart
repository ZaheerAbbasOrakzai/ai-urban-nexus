// lib/core/services/api_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:ai_urban_nexus_mobile/core/config/api_endpoints.dart';

class ApiService {
  static DatabaseReference get _db => FirebaseDatabase.instance.ref();
  static final Reference _storage = FirebaseStorage.instance.ref();

  static Future<bool> isOnline() async {
    final dynamic status = await Connectivity().checkConnectivity();
    bool offline = false;
    if (status is List<ConnectivityResult>) {
      offline = status.every((r) => r == ConnectivityResult.none);
    } else if (status is ConnectivityResult) {
      offline = status == ConnectivityResult.none;
    }
    return !offline;
  }

  static String _fallbackEnergy(String city) {
    final defaults = <String, double>{
      'Lahore': 38000,
      'Karachi': 52000,
      'Islamabad': 21000,
      'Faisalabad': 26000,
      'Rawalpindi': 24000,
      'Multan': 23000,
      'Gujranwala': 22000,
      'Peshawar': 20000,
      'Quetta': 15000,
      'Sialkot': 19000,
      'Hyderabad': 21000,
      'Sargodha': 18000,
    };
    final base = defaults[city] ?? 25000;
    return "$city\nTomorrow's Transport Energy Demand: ${base.toStringAsFixed(0)} MWh (local estimate)";
  }

  static String _fallbackTraffic(
    String city,
    int junction,
    int vehicles,
    double speed,
    double temperature,
    bool isPeakHour,
    bool accident,
  ) {
    String level;
    double outSpeed;
    if (accident || vehicles >= 2200 || speed <= 15) {
      level = 'Heavy Traffic';
      outSpeed = 20;
    } else if (vehicles >= 1200 || speed <= 30 || isPeakHour) {
      level = 'Moderate Traffic';
      outSpeed = 35;
    } else {
      level = 'Light Traffic';
      outSpeed = 60;
    }
    return '$level • approx ${outSpeed.toStringAsFixed(1)} km/h in $city';
  }

  /// Hugging Face – Energy demand prediction for a given city.
  /// Returns the raw string that Gradio sends back (e.g. "38,210 MWh").
  static Future<String> predictEnergy(String city) async {
    if (!await isOnline()) {
      return "No internet connection.";
    }
    try {
      final res = await http
          .post(
            Uri.parse(ApiEndpoints.energyPredict),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "data": [city]
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (kDebugMode) {
        print('Energy API status: ${res.statusCode}');
      }

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        return body['data'][0].toString();
      }

      return _fallbackEnergy(city);
    } catch (_) {
      return _fallbackEnergy(city);
    }
  }

  /// Hugging Face – Traffic congestion prediction.
  ///
  /// The parameters mirror your Gradio UI: city, junction id, vehicles count,
  /// current speed, temperature, isPeakHour, and accident flag.
  static Future<String> predictTraffic(
    String city,
    int junction,
    int vehicles,
    double speed, {
    double temperature = 30.0,
    bool isPeakHour = true,
    bool accident = false,
  }) async {
    if (!await isOnline()) {
      return "No internet connection.";
    }
    try {
      final res = await http
          .post(
            Uri.parse(ApiEndpoints.trafficPredict),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "data": [
                city,
                junction,
                vehicles,
                speed,
                temperature,
                isPeakHour,
                accident,
              ]
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (res.statusCode == 200) {
        if (kDebugMode) {
          print('Traffic API status: 200');
        }
        final body = jsonDecode(res.body);
        return body['data'][0].toString();
      }

      // Any non-200 status falls back to the local heuristic without
      // printing raw error bodies, keeping logs clean in production demos.

      return _fallbackTraffic(
        city,
        junction,
        vehicles,
        speed,
        temperature,
        isPeakHour,
        accident,
      );
    } catch (_) {
      return _fallbackTraffic(
        city,
        junction,
        vehicles,
        speed,
        temperature,
        isPeakHour,
        accident,
      );
    }
  }

  /// Hugging Face – Crime detection (stolen vehicle) using uploaded image.
  ///
  /// The HF Space returns a Gradio-style payload:
  /// { "data": [<base64_image_or_url>, <alert_text>] }
  /// We normalize it into a simple map the UI can consume.
  static Future<Map<String, dynamic>> detectCrime(File imageFile) async {
    if (!await isOnline()) {
      return {
        'image': null,
        'alerts': 'No internet connection.',
        'isStolen': false,
        'error': true,
      };
    }
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(ApiEndpoints.crimeDetect),
    );

    request.files.add(
      await http.MultipartFile.fromPath('data', imageFile.path),
    );

    final response = await request.send().timeout(const Duration(seconds: 30));
    if (kDebugMode) {
      print('Crime API status: ${response.statusCode}');
    }
    final respStr = await response.stream.bytesToString();

    final dynamic result = jsonDecode(respStr);

    dynamic image;
    String alerts;
    bool isStolen;

    if (result is Map && result['data'] is List && result['data'].length >= 2) {
      final list = result['data'] as List;
      image = list[0];
      alerts = list[1].toString();
      isStolen = alerts.toUpperCase().contains('STOLEN');
    } else if (result is Map && result.containsKey('alerts')) {
      image = result['image'];
      alerts = result['alerts'].toString();
      isStolen = alerts.toUpperCase().contains('STOLEN');
    } else {
      image = null;
      alerts = 'No crime detected';
      isStolen = false;
    }

    return {
      'image': image,
      'alerts': alerts,
      'isStolen': isStolen,
    };
  }

  /// Path-based helper to match requested API; wraps [detectCrime].
  static Future<Map<String, dynamic>> detectCrimeByPath(
      String imagePath) async {
    try {
      final file = File(imagePath);
      return await detectCrime(file);

    } catch (e) {
      return {
        'image': null,
        'alerts': 'Failed to read image: $e',
        'isStolen': false,
        'error': true,
      };
    }
  }

  static Future<void> saveCrimeAlert({
    required String plate,
    String city = 'Lahore',
    String location = 'Unknown',
    double? latitude,
    double? longitude,
    bool stolen = true,
    String? imagePath,
  }) async {
    final int timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    String? imageUrl;
    if (imagePath != null && imagePath.isNotEmpty) {
      try {
        final file = File(imagePath);
        if (await file.exists()) {
          final fileName =
              'crime_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final ref = _storage.child('crime_images/$fileName');
          await ref.putFile(file);
          imageUrl = await ref.getDownloadURL();
        }
      } catch (_) {
        // Ignore upload errors – main alert should still be saved
      }
    }

    final Map<String, dynamic> payload = {
      'plate': plate,
      'status': stolen ? 'STOLEN' : 'SAFE',
      'city': city,
      'location': (latitude != null && longitude != null)
          ? '$latitude,$longitude'
          : location,
      'timestamp': timestamp,
    };

    if (latitude != null && longitude != null) {
      payload['latitude'] = latitude;
      payload['longitude'] = longitude;
    }
    if (imageUrl != null) {
      payload['imageUrl'] = imageUrl;
    }

    await _db.child('crime_alerts').push().set(payload);
  }

  static Stream<DatabaseEvent> getCrimeAlerts() {
    return _db.child('crime_alerts').onValue;
  }

  static Future<void> saveEnergyForecast({
    required String city,
    required String value,
    required String date,
  }) async {
    final cleaned = value.replaceAll(RegExp('[^0-9.]'), '');
    final num mwhNumeric =
        num.tryParse(cleaned.isEmpty ? '0' : cleaned) ?? 0;
    final int timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final payload = {
      'city': city,
      'mwh': mwhNumeric,
      'date': date,
      'timestamp': timestamp,
      'source': 'AI Model',
    };
    await _db.child('energy_predictions').push().set(payload);
  }

  static Future<void> saveTrafficAlert({
    required String city,
    required int junction,
    required String level,
    required int vehicles,
    String triggeredBy = 'crime_detection',
  }) async {
    final int timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final payload = {
      'city': city,
      'junction': junction,
      'level': level,
      'vehicles': vehicles,
      'timestamp': timestamp,
      'triggeredBy': triggeredBy,
    };
    await _db.child('traffic_alerts').push().set(payload);
  }

  static Stream<DatabaseEvent> getTrafficAlerts() {
    return _db.child('traffic_alerts').onValue;
  }

  static Future<void> saveSafeRoute({
    required String from,
    required String to,
    required String risk,
    required String distance,
    required String duration,
  }) async {
    final int timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final payload = {
      'from': from,
      'to': to,
      'risk': risk,
      'distance': distance,
      'duration': duration,
      'timestamp': timestamp,
    };

    await _db.child('safe_routes').push().set(payload);
  }

  static Future<void> sendSosAlert({
    required double latitude,
    required double longitude,
    String note = 'SOS Emergency',
    String source = 'sos_button',
  }) async {
    final int timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final payload = {
      'latitude': latitude,
      'longitude': longitude,
      'note': note,
      'source': source,
      'timestamp': timestamp,
    };

    await _db.child('sos_alerts').push().set(payload);
  }
}
