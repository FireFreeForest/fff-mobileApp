import '../core/utils/json_utils.dart';

enum UserRole {
  admin,
  petugas,
  viewer;

  static UserRole fromApi(dynamic value) {
    switch (value?.toString().toLowerCase()) {
      case 'admin':
        return UserRole.admin;
      case 'petugas':
        return UserRole.petugas;
      default:
        return UserRole.viewer;
    }
  }

  String get apiValue => name;

  String get label {
    switch (this) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.petugas:
        return 'Petugas';
      case UserRole.viewer:
        return 'Viewer';
    }
  }

  bool get canOperate => this == UserRole.admin || this == UserRole.petugas;

  bool get canResolve => this == UserRole.petugas;

  bool get canManageDevices => this == UserRole.admin;
}

class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String email;
  final UserRole role;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayName => name.trim().isEmpty ? email : name;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: UserRole.fromApi(json['role']),
      isActive: json['is_active'] == true,
      createdAt: parseDateTime(json['created_at']),
      updatedAt: parseDateTime(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'role': role.apiValue,
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}
