class ServerConfig {
  const ServerConfig._();

  static String normalize(String raw) {
    var value = raw.trim();
    if (value.isEmpty) {
      throw const FormatException('Alamat server wajib diisi.');
    }

    if (value.contains(RegExp(r'\s'))) {
      throw const FormatException(
        'Gunakan alamat http:// atau https:// yang valid.',
      );
    }

    if (!value.contains('://')) {
      value = 'http://$value';
    }

    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const FormatException(
        'Gunakan alamat http:// atau https:// yang valid.',
      );
    }
    if (uri.userInfo.isNotEmpty) {
      throw const FormatException(
        'Alamat server tidak boleh berisi kredensial.',
      );
    }

    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
    ).toString();
  }

  static String normalizeOrDefault(String? raw, String fallback) {
    try {
      return normalize(raw ?? fallback);
    } on FormatException {
      return normalize(fallback);
    }
  }

  static String displayLabel(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || uri.host.isEmpty) return baseUrl;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.host}$port';
  }
}
