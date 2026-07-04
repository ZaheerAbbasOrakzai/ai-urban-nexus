// lib/core/services/hf_space_service.dart
// Helper for calling the AI Urban Nexus Hugging Face Space API safely.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ai_urban_nexus_mobile/core/config/api_endpoints.dart';

class HFSpaceService {
  // Primary Space API URL for AI Urban Nexus Pakistan.
  // Correct owner-space pattern: https://<owner>-<space>.hf.space
  // This matches ApiEndpoints.baseMain and avoids 404 errors.
  // Space: https://huggingface.co/spaces/abbasorakzai777/ai-urban-nexus-pakistan
  static const String _spaceApiUrl =
      'https://abbasorakzai777-ai-urban-nexus-pakistan.hf.space/run/predict';

  // Optional token for private / gated Spaces. Read from a Dart define so it
  // is not hardcoded in source:
  // flutter run --dart-define=HF_SPACE_TOKEN=hf_your_token_here
  static const String _tokenEnv =
      String.fromEnvironment('HF_SPACE_TOKEN', defaultValue: '');

  static String? get _token => _tokenEnv.isEmpty ? null : _tokenEnv;

  /// Generic text prediction against the Space.
  ///
  /// This uses the standard Gradio format: {"data": [input]} and returns the
  /// first element from the "data" array if present, or a friendly error
  /// string. It is wrapped in try/catch to avoid crashes on network errors.
  static Future<String?> predictText(String input) async {
    // Use the Space's generic /run/predict endpoint.
    final uri = Uri.parse(_spaceApiUrl);

    for (int retry = 0; retry < 5; retry++) {
      try {
        final res = await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                if (_token != null) 'Authorization': 'Bearer $_token',
              },
              body: jsonEncode({
                'data': [input],
              }),
            )
            .timeout(const Duration(seconds: 120));

        if (res.statusCode == 200) {
          final dynamic body = jsonDecode(res.body);
          if (body is Map && body['data'] is List && body['data'].isNotEmpty) {
            return body['data'][0].toString();
          }
          return 'No output received from Space.';
        } else if (res.statusCode == 503) {
          debugPrint('HF Space 503 (loading), retry=$retry body=${res.body}');
          if (retry < 4) {
            await Future.delayed(Duration(seconds: 15 * (retry + 1)));
            continue;
          }
          return 'Server busy (Code 503) – Retry later';
        } else if (res.statusCode == 404) {
          // Space does not expose this text endpoint; fall back silently.
          return null;
        } else {
          debugPrint('HF Space API error: ${res.statusCode} - ${res.body}');
          return 'Server busy (Code ${res.statusCode}) – Retry later';
        }
      } catch (e) {
        debugPrint('HF Space network error on retry=$retry: $e');
        if (retry == 4) {
          return 'No internet – Check VPN or connection.';
        }
        await Future.delayed(Duration(seconds: 4 * (retry + 1)));
      }
    }

    return 'Failed after retries';
  }

  /// Structured traffic prediction using the Space's `app.py` schema.
  ///
  /// Expects the Space to return a JSON object of the form:
  /// {
  ///   "congestion_level": "High" | "Medium" | "Low",
  ///   "average_speed_kmh": <number>,
  ///   "predicted_delay_minutes": <number>,
  ///   "ai_recommendation": "...",
  /// }
  /// wrapped as the first element of the usual Gradio `data` list.
  static Future<Map<String, dynamic>> predictTrafficStructured({
    required String city,
    required String timeOfDay,
    required String dayOfWeek,
  }) async {
    Map<String, dynamic> _error(String message) => {'error': message};

    final uri = Uri.parse(_spaceApiUrl);

    for (int retry = 0; retry < 5; retry++) {
      try {
        final res = await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                if (_token != null) 'Authorization': 'Bearer $_token',
              },
              body: jsonEncode({
                'data': [city, timeOfDay, dayOfWeek],
              }),
            )
            .timeout(const Duration(seconds: 120));

        if (res.statusCode == 200) {
          final dynamic body = jsonDecode(res.body);
          if (body is Map && body['data'] is List && body['data'].isNotEmpty) {
            final dynamic first = (body['data'] as List).first;

            // app.py may return a dict directly or a JSON string.
            if (first is Map<String, dynamic>) {
              return first;
            }
            if (first is Map) {
              return Map<String, dynamic>.from(first);
            }
            if (first is String) {
              try {
                final dynamic decoded = jsonDecode(first);
                if (decoded is Map<String, dynamic>) {
                  return decoded;
                }
                if (decoded is Map) {
                  return Map<String, dynamic>.from(decoded);
                }
                debugPrint(
                    'HF Space traffic: decoded string but not a Map: $decoded');
              } catch (e) {
                debugPrint(
                    'HF Space traffic: failed to jsonDecode string response: $e');
              }
              return _error('Unexpected string response from Space.');
            }

            return _error('Unexpected response format from Space.');
          }
          return _error('No output received from Space.');
        } else if (res.statusCode == 503) {
          debugPrint('HF Space 503 (loading), retry=$retry body=${res.body}');
          if (retry < 4) {
            await Future.delayed(Duration(seconds: 15 * (retry + 1)));
            continue;
          }
          return _error('Server busy (Code 503) – Retry later');
        } else if (res.statusCode == 404) {
          // Space does not expose this structured traffic endpoint; fall back silently.
          return _error('Space traffic endpoint unavailable.');
        } else {
          debugPrint(
              'HF Space traffic API error: ${res.statusCode} - ${res.body}');
          return _error('Server busy (Code ${res.statusCode}) – Retry later');
        }
      } catch (e) {
        debugPrint('HF Space traffic network error on retry=$retry: $e');
        if (retry == 4) {
          return _error('No internet or server down');
        }
        await Future.delayed(Duration(seconds: 4 * (retry + 1)));
      }
    }

    return _error('Failed after retries');
  }

  /// Image-based prediction helper for Spaces that accept image inputs.
  ///
  /// This sends image bytes as a multipart "data" field. Not used by default
  /// but available for future crime / plate detection integrations.
  static Future<String?> predictImage(
    Uint8List imageBytes, {
    String? textInput,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse(_spaceApiUrl));
    if (_token != null) {
      request.headers['Authorization'] = 'Bearer $_token';
    }

    // Optional text field some Spaces accept alongside image input.
    if (textInput != null && textInput.isNotEmpty) {
      request.fields['data'] = textInput;
    }

    request.files.add(
      http.MultipartFile.fromBytes('data', imageBytes, filename: 'input.jpg'),
    );

    try {
      final streamed =
          await request.send().timeout(const Duration(seconds: 90));
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode == 200) {
        final dynamic body = jsonDecode(res.body);
        if (body is Map && body['data'] is List && body['data'].isNotEmpty) {
          return body['data'][0].toString();
        }
        return 'No output received from Space.';
      }
      debugPrint('HF Space image API error: ${res.statusCode} - ${res.body}');
      return 'Space error: HTTP ${res.statusCode}';
    } catch (e) {
      debugPrint('HF Space image network error: $e');
      return 'Image prediction failed due to network error.';
    }
  }
}
