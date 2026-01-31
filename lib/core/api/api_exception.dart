class ApiException implements Exception {
  final int? statusCode;
  final String message;
  final String? code;

  const ApiException({
    required this.message,
    this.statusCode,
    this.code,
  });

  @override
  String toString() {
    final sc = statusCode == null ? '' : ' ($statusCode)';
    final c = code == null || code!.isEmpty ? '' : '[$code] ';
    return 'ApiException$c$message$sc';
  }
}
