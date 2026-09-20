import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'services/app_config.dart';
import 'services/token_storage.dart';

class ApiException implements Exception {
  ApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient(this.preferences, this.tokenStorage);

  final SharedPreferences preferences;
  final TokenStorage tokenStorage;
  String? token;

  bool get hasConfiguredServer => AppConfig.hasApiBase;
  String get baseUrl => AppConfig.apiBase;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json; charset=utf-8',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<dynamic> get(String path) async =>
      _handle(await http.get(Uri.parse('$baseUrl$path'), headers: _headers));

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) async =>
      _handle(
        await http.post(
          Uri.parse('$baseUrl$path'),
          headers: _headers,
          body: jsonEncode(body ?? {}),
        ),
      );

  Future<dynamic> put(String path, Map<String, dynamic> body) async => _handle(
    await http.put(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
      body: jsonEncode(body),
    ),
  );

  Future<dynamic> delete(String path) async =>
      _handle(await http.delete(Uri.parse('$baseUrl$path'), headers: _headers));

  dynamic _handle(http.Response response) {
    final decoded = response.body.isEmpty
        ? null
        : jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;
    final detail = decoded is Map ? decoded['detail'] : null;
    throw ApiException(
      detail?.toString() ?? '请求失败（${response.statusCode}）',
      response.statusCode,
    );
  }

  Future<void> saveToken(String value) async {
    token = value;
    await tokenStorage.write(value);
  }

  Future<void> clearToken() async {
    token = null;
    await tokenStorage.clear();
  }
}
