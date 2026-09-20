import 'package:flutter/foundation.dart';

class AppConfig {
  static const configuredApiBase = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static bool get hasApiBase => configuredApiBase.trim().isNotEmpty || kIsWeb;

  static String get apiBase {
    final configured = configuredApiBase.trim().replaceAll(RegExp(r'/+$'), '');
    if (configured.isNotEmpty) return configured;
    if (kIsWeb) return '${Uri.base.origin}/api';
    throw const AppConfigurationException(
      '服务器地址尚未配置。请在构建时传入 '
      '--dart-define=API_BASE_URL=https://你的域名/api',
    );
  }
}

class AppConfigurationException implements Exception {
  const AppConfigurationException(this.message);
  final String message;

  @override
  String toString() => message;
}
