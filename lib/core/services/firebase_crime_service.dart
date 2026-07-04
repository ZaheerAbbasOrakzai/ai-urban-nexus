// lib/core/services/firebase_crime_service.dart
// Helper for writing crime alerts to Firebase Realtime Database

import 'package:firebase_database/firebase_database.dart';

class FirebaseCrimeService {
  FirebaseCrimeService._();

  static DatabaseReference get _alertsRef =>
      FirebaseDatabase.instance.ref('crime_alerts');

  /// Saves a crime alert entry in Realtime Database.
  ///
  /// Example structure in DB:
  /// crime_alerts/{push_id} -> {
  ///   plate: "LEB-1234",
  ///   city: "Lahore",
  ///   location: "Unknown" | custom,
  ///   timestamp: ISO8601 string,
  ///   status: "active"
  /// }
  static Future<void> saveCrimeAlert({
    required String plate,
    String city = 'Lahore',
    String location = 'Unknown',
    double? latitude,
    double? longitude,
  }) async {
    final now = DateTime.now();
    final Map<String, dynamic> payload = {
      'plate': plate,
      'city': city,
      'location': location,
      'timestamp': now.toIso8601String(),
      'status': 'active',
    };
    if (latitude != null && longitude != null) {
      payload['latitude'] = latitude;
      payload['longitude'] = longitude;
    }
    await _alertsRef.push().set(payload);
  }
}
