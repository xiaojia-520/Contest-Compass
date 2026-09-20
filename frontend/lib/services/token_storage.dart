import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  TokenStorage(this.preferences);

  static const _key = 'access_token';
  final SharedPreferences preferences;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Future<String?> read() async {
    if (kIsWeb) return preferences.getString(_key);
    final secured = await _secureStorage.read(key: _key);
    if (secured != null) return secured;

    final legacy = preferences.getString(_key);
    if (legacy != null) {
      await _secureStorage.write(key: _key, value: legacy);
      await preferences.remove(_key);
    }
    return legacy;
  }

  Future<void> write(String value) async {
    if (kIsWeb) {
      await preferences.setString(_key, value);
      return;
    }
    await _secureStorage.write(key: _key, value: value);
    await preferences.remove(_key);
  }

  Future<void> clear() async {
    await preferences.remove(_key);
    if (!kIsWeb) await _secureStorage.delete(key: _key);
  }
}
