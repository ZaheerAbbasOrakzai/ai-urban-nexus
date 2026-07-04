// lib/models/energy_prediction_model.dart
class EnergyPredictionModel {
  final double predictedLoad;
  final String status; // "Low", "Moderate", "High", "Critical"
  final DateTime timestamp;
  final String date; // yyyy-MM-dd
  final double mwh; // convenience for UI

  EnergyPredictionModel({
    required this.predictedLoad,
    required this.status,
    required this.timestamp,
    required this.date,
    required this.mwh,
  });

  factory EnergyPredictionModel.fromJson(Map<String, dynamic> json) {
    final load = (json['predicted_load'] as num).toDouble();
    final now = DateTime.now();
    return EnergyPredictionModel(
      predictedLoad: load,
      status: json['status'] ?? 'Unknown',
      timestamp: now,
      date: now.add(const Duration(days: 1)).toIso8601String().split('T').first,
      mwh: load,
    );
  }
}
