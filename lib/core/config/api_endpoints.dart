// lib/core/config/api_endpoints.dart
import 'package:flutter/foundation.dart';

class ApiEndpoints {
  ApiEndpoints._();

  // Optional override for deployment (e.g. Render):
  // flutter run --dart-define=BACKEND_BASE=https://your-app.onrender.com
  static const String backendBaseOverride =
      String.fromEnvironment('BACKEND_BASE', defaultValue: '');

  static String _resolveHost() {
    const hostOverride = String.fromEnvironment('API_HOST', defaultValue: '');
    if (hostOverride.isNotEmpty) return hostOverride;
    if (kIsWeb) {
      final h = Uri.base.host;
      return h.isEmpty ? 'localhost' : h;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return '10.0.2.2';
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return '127.0.0.1';
      default:
        return '127.0.0.1';
    }
  }

  static final String baseHost = _resolveHost();
  static final String baseUrl = (kIsWeb && Uri.base.scheme == 'https')
      ? 'https://$baseHost'
      : 'http://$baseHost';

  static String get _base8000 {
    if (backendBaseOverride.isNotEmpty) {
      return backendBaseOverride;
    }
    return '$baseUrl:8000';
  }

  // Orchestrator (Central Controller) - Port 8000, mounted at /orch
  static final String orchestratorBase = '$_base8000/orch';
  static final String orchestrateCrimeResponse =
      '$orchestratorBase/orchestrate_crime_response';
  static final String orchestrateEnergyPrediction =
      '$orchestratorBase/orchestrate_energy_prediction';

  // Crime Detection API (Local) - Port 8001
  static final String crimeLocalBase = '$_base8000/crime';
  static final String detectStolenVehicle =
      '$crimeLocalBase/detect_stolen_vehicle';

  // Traffic Prediction API - Port 8002
  static final String trafficBase = '$_base8000/traffic';
  static final String predictTraffic = '$trafficBase/predict';
  static final String simulateTraffic = '$trafficBase/simulate_traffic';

  // Energy Forecasting API - Port 8003
  static final String energyBase = '$_base8000/energy';
  static final String predictEnergy = '$energyBase/predict_energy';

  // Hugging Face Spaces
  static const String baseMain =
      'https://abbasorakzai777-ai-urban-nexus-pakistan.hf.space';
  static const String crimeBase =
      'https://abbasorakzai777-crime-detection.hf.space';
  static const String energyPredict = '$baseMain/gradio_api/predict_energy';
  static const String trafficPredict = '$baseMain/gradio_api/predict_congestion';
  static const String crimeDetect = '$crimeBase/run/predict';

  // WebSocket URL uses wss for https pages
  static final bool _isHttps = kIsWeb && Uri.base.scheme == 'https';
  static final String _wsScheme = _isHttps ? 'wss' : 'ws';
  static final String socketUrl = backendBaseOverride.isNotEmpty
      ? (() {
          final uri = Uri.parse(backendBaseOverride);
          final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
          final port = uri.hasPort
              ? uri.port
              : (uri.scheme == 'https' ? 443 : 80);
          return '$scheme://${uri.host}:$port/ws/vehicles';
        })()
      : '$_wsScheme://$baseHost:8000/ws/vehicles';

  // Timeout Settings
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
