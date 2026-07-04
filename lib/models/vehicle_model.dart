// lib/models/vehicle_model.dart

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../core/config/app_colors.dart';

enum VehicleType {
  car,
  bus,
  truck,
  taxi,
}

@immutable
class VehicleModel {
  final String id;
  final VehicleType type;
  final LatLng position;
  final double speed; // km/h
  final double heading; // degrees (0-360)
  final bool isStolen;
  final String? licensePlate;

  const VehicleModel({
    required this.id,
    required this.type,
    required this.position,
    required this.speed,
    required this.heading,
    this.isStolen = false,
    this.licensePlate,
  });

  // Factory from JSON
  factory VehicleModel.fromJson(Map<String, dynamic> json) {
    return VehicleModel(
      id: json['id'] as String? ?? '',
      type: _parseType(json['type'] as String? ?? 'car'),
      position: LatLng(
        (json['lat'] as num).toDouble(),
        (json['lon'] as num).toDouble(),
      ),
      speed: (json['speed'] as num?)?.toDouble() ?? 0.0,
      heading: (json['heading'] as num?)?.toDouble() ?? 0.0,
      isStolen: _parseIsStolen(json['is_stolen']),
      licensePlate: json['license_plate'] as String?,
    );
  }

  static bool _parseIsStolen(dynamic value) {
    return value == true ||
        value == 'true' ||
        value == '1' ||
        value == 1;
  }

  static VehicleType _parseType(String type) {
    return switch (type.toLowerCase()) {
      'bus' => VehicleType.bus,
      'truck' => VehicleType.truck,
      'taxi' => VehicleType.taxi,
      _ => VehicleType.car,
    };
  }

  // Color based on vehicle type — fully matches your current AppColors
  Color get color => switch (type) {
    VehicleType.car => AppColors.car,
    VehicleType.bus => AppColors.bus,
    VehicleType.truck => AppColors.truck,
    VehicleType.taxi => AppColors.taxi,
  };

  // Icon path — stolen vehicles show police icon
  String get iconPath => isStolen
      ? 'assets/icons/police_car.png'
      : switch (type) {
    VehicleType.car => 'assets/icons/car.png',
    VehicleType.bus => 'assets/icons/bus.png',
    VehicleType.truck => 'assets/icons/truck.png',
    VehicleType.taxi => 'assets/icons/taxi.png',
  };

  // Optional: Human-readable name
  String get displayName => switch (type) {
    VehicleType.car => 'Car',
    VehicleType.bus => 'Bus',
    VehicleType.truck => 'Truck',
    VehicleType.taxi => 'Taxi',
  };
}