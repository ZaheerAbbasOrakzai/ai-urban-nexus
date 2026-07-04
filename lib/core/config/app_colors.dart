// lib/core/config/app_colors.dart
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF5E35B1);
  static const Color primaryDark = Color(0xFF4527A0);
  static const Color secondary = Color(0xFF00897B);
  static const Color accent = Color(0xFF26A69A);

  // Background & Surface
  static const Color background = Color(0xFFF7F7FA);
  static const Color surface = Colors.white;
  static const Color cardBackground = Color(0xFFFFFFFF);

  // Text
  static const Color textPrimary = Color(0xFF222B45);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textLight = Color(0xFF9CA3AF);

  // Severity Colors (Notifications)
  static const Color critical = Color(0xFFDC3545);
  static const Color high = Color(0xFFFD7E14);
  static const Color medium = Color(0xFFFFC107);
  static const Color low = Color(0xFF28A745);
  static const Color info = Color(0xFF17A2B8);

  // Vehicle Type Colors
  static const Color car = Color(0xFF3B82F6);
  static const Color bus = Color(0xFF10B981);
  static const Color truck = Color(0xFFEF4444);
  static const Color taxi = Color(0xFFF59E0B);
}
