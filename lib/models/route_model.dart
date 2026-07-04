// lib/models/route_model.dart
import 'package:latlong2/latlong.dart';

class AlternativeRoute {
  final String routeId;
  final List<LatLng> polyline;
  final double distanceKm;
  final int durationMin;
  final double trafficScore;     // 0-100 (lower = better)
  final double safetyScore;      // 0-100 (higher = safer)
  final double energySavedKwh;
  final bool recommended;
  final double? congestionScore; // optional 0-100
  final double? crimeRisk;       // optional 0-100

  AlternativeRoute({
    required this.routeId,
    required this.polyline,
    required this.distanceKm,
    required this.durationMin,
    required this.trafficScore,
    required this.safetyScore,
    required this.energySavedKwh,
    this.recommended = false,
    this.congestionScore,
    this.crimeRisk,
  });

  factory AlternativeRoute.fromJson(Map<String, dynamic> json) {
    return AlternativeRoute(
      routeId: json['route_id'],
      polyline: (json['polyline'] as List)
          .map((p) => LatLng(p['lat'] as double, p['lon'] as double))
          .toList(),
      distanceKm: (json['distance_km'] as num).toDouble(),
      durationMin: json['duration_min'],
      trafficScore: (json['traffic_score'] as num).toDouble(),
      safetyScore: (json['safety_score'] as num).toDouble(),
      energySavedKwh: (json['energy_saved_kwh'] as num).toDouble(),
      recommended: json['recommended'] == true,
      congestionScore: (json['congestion_score'] as num?)?.toDouble(),
      crimeRisk: (json['crime_risk'] as num?)?.toDouble(),
    );
  }
}
