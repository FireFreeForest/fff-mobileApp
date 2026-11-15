class ApiError {
  const ApiError({required this.code, required this.message});

  final String code;
  final String message;

  factory ApiError.fromJson(Map<String, dynamic> json) {
    final error = json['error'];
    if (error is Map) {
      return ApiError(
        code: error['code']?.toString() ?? 'unknown',
        message: error['message']?.toString() ?? 'Terjadi kesalahan.',
      );
    }
    return const ApiError(code: 'unknown', message: 'Terjadi kesalahan.');
  }
}
