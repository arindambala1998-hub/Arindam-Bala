/// Standard wrapper for backend responses.
/// Expected server shape:
/// { success: true/false, message: string, data: any, meta?: any }
class ApiResponse<T> {
  final bool success;
  final String message;
  final T? data;
  final Map<String, dynamic>? meta;

  ApiResponse({
    required this.success,
    required this.message,
    required this.data,
    required this.meta,
  });
}
