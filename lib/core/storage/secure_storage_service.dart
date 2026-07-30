import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage for secrets — auth tokens, anything that must not live in plain
/// SharedPreferences. Firebase Auth manages its own session persistence,
/// but this is available for anything the backend integration needs to
/// cache (e.g. a cached ID token) once auth is wired up in Phase 2.
class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<String?> read(String key) => _storage.read(key: key);
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  Future<void> delete(String key) => _storage.delete(key: key);
  Future<void> deleteAll() => _storage.deleteAll();
}
