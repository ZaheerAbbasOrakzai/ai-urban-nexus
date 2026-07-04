// lib/core/services/traffic_service.dart
// Traffic prediction client for AI Urban Nexus

import 'package:dio/dio.dart';
import 'package:ai_urban_nexus_mobile/core/config/api_endpoints.dart';

class TrafficService {
  TrafficService._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: ApiEndpoints.connectTimeout,
      receiveTimeout: ApiEndpoints.receiveTimeout,
    ),
  );

  /// Calls the backend /traffic/predict API.
  ///
  /// Request body (matches your FastAPI spec):
  /// {
  ///   "hour_of_day": 17,
  ///   "road_type": "main_road",
  ///   "trigger_from_crime_model": true,
  ///   "nearby_routes": [ ... ]
  /// }
  static Future<Map<String, dynamic>> predictTraffic({
    required int hour,
    required String roadType,
    required bool crimeAlertTriggered,
    required List<String> nearbyRoutes,
  }) async {
    final body = <String, dynamic>{
      'hour_of_day': hour,
      'road_type': roadType,
      'trigger_from_crime_model': crimeAlertTriggered,
      'nearby_routes': nearbyRoutes,
    };

    try {
      final response = await _dio.post(
        ApiEndpoints.predictTraffic,
        data: body,
      );

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      return {
        'error': true,
        'message': 'Traffic API Error: ${response.statusCode}',
      };
    } catch (e) {
      return {
        'error': true,
        'message': 'No internet or server down',
        'details': e.toString(),
      };
    }
  }
}
