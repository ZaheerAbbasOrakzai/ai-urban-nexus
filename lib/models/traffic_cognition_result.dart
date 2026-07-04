// lib/models/traffic_cognition_result.dart

class TrafficCognitionResult {
  final String congestionLevel; // Light, Moderate, Heavy
  final double predictedSpeedKmh;
  final int? delayMinutes;
  final String suggestion;
  final List<String> contextRoutes;

  const TrafficCognitionResult({
    required this.congestionLevel,
    required this.predictedSpeedKmh,
    required this.suggestion,
    required this.contextRoutes,
    this.delayMinutes,
  });

  bool get isHeavy => congestionLevel == 'Heavy';
  bool get isModerate => congestionLevel == 'Moderate';
  bool get isLight => congestionLevel == 'Light';

  Map<String, dynamic> toMap() {
    return {
      'congestion_level': congestionLevel,
      'predicted_speed': predictedSpeedKmh.toStringAsFixed(1),
      'delay_minutes': delayMinutes?.toString(),
      'suggestion': suggestion,
      'simulated_routes': contextRoutes,
    };
  }

  static TrafficCognitionResult fromRawText(
    String raw,
    List<String> routes, {
    bool includeDelay = false,
  }) {
    final lower = raw.toLowerCase();

    String level;
    if (lower.contains('heavy') ||
        lower.contains('jam') ||
        lower.contains('critical')) {
      level = 'Heavy';
    } else if (lower.contains('moderate') ||
        lower.contains('medium') ||
        lower.contains('slow') ||
        lower.contains('busy')) {
      level = 'Moderate';
    } else {
      level = 'Light';
    }

    double speed;
    final match = RegExp(r'(\d+\.?\d*)').firstMatch(raw);
    if (match != null) {
      speed = double.tryParse(match.group(1)!) ?? 0;
    } else {
      speed = level == 'Heavy'
          ? 20
          : level == 'Moderate'
              ? 35
              : 60;
    }

    String suggestion;
    if (level == 'Heavy') {
      suggestion =
          'Heavy congestion expected. Consider alternate safe routes or different time.';
    } else if (level == 'Moderate') {
      suggestion =
          'Moderate traffic. Allow extra time or consider parallel roads.';
    } else {
      suggestion = 'Traffic is light. Normal travel conditions.';
    }

    int? delay;
    if (includeDelay) {
      if (speed <= 20) {
        delay = 18;
      } else if (speed <= 35) {
        delay = 10;
      } else {
        delay = 3;
      }
    }

    return TrafficCognitionResult(
      congestionLevel: level,
      predictedSpeedKmh: speed,
      suggestion: suggestion,
      contextRoutes: routes,
      delayMinutes: delay,
    );
  }
}
