class ApiException implements Exception {
  const ApiException(this.message, {this.code = 'unknown', this.statusCode});

  final String message;
  final String code;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  bool get isForbidden => statusCode == 403;

  bool get isNotFound => statusCode == 404;

  bool get isConflict => statusCode == 409;

  bool get isValidation => statusCode == 422;

  @override
  String toString() => message;
}
