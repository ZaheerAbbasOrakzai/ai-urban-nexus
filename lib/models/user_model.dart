// lib/models/user_model.dart
enum UserRole { admin, trafficOfficer, securityLead, energyManager, viewer }

class UserModel {
  final String id;
  final String fullName;
  final String username;
  final UserRole role;
  final String? token;
  final String crimeStatus; // 'Safe' | 'Alert'

  UserModel({
    required this.id,
    required this.fullName,
    required this.username,
    required this.role,
    this.token,
    this.crimeStatus = 'Safe',
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      fullName: json['fullName'] ?? '',
      username: json['username'] ?? '',
      role: _parseRole(json['role'] ?? 'viewer'),
      token: json['token'],
      crimeStatus: json['crime_status'] ?? 'Safe',
    );
  }

  static UserRole _parseRole(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return UserRole.admin;
      case 'traffic_officer':
        return UserRole.trafficOfficer;
      case 'security_lead':
        return UserRole.securityLead;
      case 'energy_manager':
        return UserRole.energyManager;
      default:
        return UserRole.viewer;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fullName': fullName,
      'username': username,
      'role': role.toString().split('.').last,
      'token': token,
      'crime_status': crimeStatus,
    };
  }
}
