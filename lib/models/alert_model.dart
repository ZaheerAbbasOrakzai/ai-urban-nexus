// lib/models/alert_model.dart

import 'package:flutter/material.dart';
import '../core/config/app_colors.dart';

/// Types of alerts in the AI Urban Nexus system
enum AlertType {
  crime,
  traffic,
  energy,
  system,
}

/// Immutable alert model with full serialization, copyWith, and visual helpers
@immutable
class AlertModel {
  final String id;
  final AlertType type;
  final String title;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final String? crimeSubtype; // e.g., 'stolen_vehicle'

  const AlertModel({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.timestamp,
    this.isRead = false,
    this.crimeSubtype,
  });

  /// Visual color based on alert severity
  Color get color {
    return switch (type) {
      AlertType.crime => AppColors.critical,
      AlertType.traffic => AppColors.high,
      AlertType.energy => AppColors.medium,
      AlertType.system => AppColors.info,
    };
  }

  /// Material icon representing the alert type
  IconData get icon {
    return switch (type) {
      AlertType.crime => Icons.local_police_rounded,
      AlertType.traffic => Icons.traffic_rounded,
      AlertType.energy => Icons.bolt_rounded,
      AlertType.system => Icons.info_rounded,
    };
  }

  /// Priority level for sorting and processing (P0 = highest)
  int get priority {
    return switch (type) {
      AlertType.crime => 0,
      AlertType.traffic => 1,
      AlertType.energy => 2,
      AlertType.system => 3,
    };
  }

  /// Human-readable type name
  String get typeName {
    return switch (type) {
      AlertType.crime => 'Crime Alert',
      AlertType.traffic => 'Traffic Alert',
      AlertType.energy => 'Energy Alert',
      AlertType.system => 'System Notice',
    };
  }

  /// Creates a copy of this alert with optional overrides
  AlertModel copyWith({
    String? id,
    AlertType? type,
    String? title,
    String? message,
    DateTime? timestamp,
    bool? isRead,
  }) {
    return AlertModel(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
    );
  }

  /// Creates an AlertModel from JSON (API or local storage)
  factory AlertModel.fromJson(Map<String, dynamic> json) {
    return AlertModel(
      id: json['id'] as String,
      type: AlertType.values.firstWhere(
            (e) => e.name == json['type'],
        orElse: () => AlertType.system,
      ),
      title: json['title'] as String,
      message: json['message'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isRead: json['isRead'] as bool? ?? false,
      crimeSubtype: json['crimeSubtype'] as String?,
    );
  }

  /// Converts the model to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
      'crimeSubtype': crimeSubtype,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AlertModel &&
        other.id == id &&
        other.type == type &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode => Object.hash(id, type, timestamp);
}
