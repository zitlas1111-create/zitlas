/// Thrown by [ApiClient] for any non-2xx response or transport failure.
///
/// The backend's response envelope is not uniform (see
/// docs/MIGRATION_INVENTORY.md §1) — callers should not assume `body` has a
/// consistent shape beyond FastAPI's default `{"detail": ...}` on errors.
class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.statusCode,
    this.body,
  });

  final String message;
  final int? statusCode;
  final Object? body;

  bool get isNetworkError => statusCode == null;
  bool get isUnauthorized => statusCode == 401 || statusCode == 403;
  bool get isServerError => statusCode != null && statusCode! >= 500;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
