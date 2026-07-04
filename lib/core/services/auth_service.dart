// lib/core/services/auth_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_urban_nexus_mobile/models/user_model.dart';
import 'dart:convert';

class AuthService {
  static const String _keyUser = 'current_user';
  static const String _keyToken = 'auth_token';

  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  UserRole _roleFromUsername(String username) {
    final u = username.toLowerCase().trim();
    if (u.contains('admin') || u == 'zaheer' || u == 'abbas') {
      return UserRole.admin;
    }
    if (u.contains('police') || u.contains('traffic')) {
      return UserRole.trafficOfficer;
    }
    if (u.contains('security')) {
      return UserRole.securityLead;
    }
    if (u.contains('energy')) {
      return UserRole.energyManager;
    }
    return UserRole.viewer;
  }

  Future<void> login(String username, String password) async {
    // Will integrate with your FastAPI auth.py later
    await Future.delayed(const Duration(seconds: 1));

    final user = UserModel(
      id: "165",
      fullName: "Zaheer Abbas",
      username: username,
      role: _roleFromUsername(username),
      token: "dummy_jwt_token_2025",
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUser, jsonEncode(user.toJson()));
    if (user.token != null) {
      await prefs.setString(_keyToken, user.token!);
    }
  }

  Future<UserModel?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_keyUser);
    if (userJson == null) return null;
    try {
      final Map<String, dynamic> map =
          jsonDecode(userJson) as Map<String, dynamic>;
      return UserModel.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> updateUser(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUser, jsonEncode(user.toJson()));
    if (user.token != null) {
      await prefs.setString(_keyToken, user.token!);
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  Future<bool> isLoggedIn() async {
    final user = await getCurrentUser();
    return user != null;
  }
}
