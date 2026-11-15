import '../core/utils/json_utils.dart';

class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
    this.tokenType = 'Bearer',
    this.accessExpiresAt,
    this.refreshExpiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final DateTime? accessExpiresAt;
  final DateTime? refreshExpiresAt;

  factory TokenPair.fromJson(Map<String, dynamic> json) {
    return TokenPair(
      accessToken: json['access_token']?.toString() ?? '',
      refreshToken: json['refresh_token']?.toString() ?? '',
      tokenType: json['token_type']?.toString() ?? 'Bearer',
      accessExpiresAt: parseDateTime(json['access_expires_at']),
      refreshExpiresAt: parseDateTime(json['refresh_expires_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'token_type': tokenType,
      'access_expires_at': accessExpiresAt?.toIso8601String(),
      'refresh_expires_at': refreshExpiresAt?.toIso8601String(),
    };
  }
}
