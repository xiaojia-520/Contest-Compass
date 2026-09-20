import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';

class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.buildNumber,
    required this.notes,
    required this.downloadUrl,
    required this.mandatory,
  });

  final String version;
  final int buildNumber;
  final String notes;
  final Uri downloadUrl;
  final bool mandatory;
}

class UpdateService {
  UpdateService(this.api);
  final ApiClient api;

  Future<AppUpdate?> check() async {
    final platform = _platformName;
    if (platform == null) return null;
    final package = await PackageInfo.fromPlatform();
    final response = await api.get(
      '/app/releases/latest?platform=$platform&current_version=${Uri.encodeQueryComponent(package.version)}',
    );
    if (response == null) return null;
    final data = Map<String, dynamic>.from(response as Map);
    final latest = data['version']?.toString() ?? '';
    if (!_isNewer(latest, package.version) && data['mandatory'] != true) {
      return null;
    }
    final url = Uri.tryParse(data['download_url']?.toString() ?? '');
    if (url == null || !url.hasScheme) return null;
    return AppUpdate(
      version: latest,
      buildNumber: data['build_number'] as int? ?? 0,
      notes: data['release_notes']?.toString() ?? '',
      downloadUrl: url,
      mandatory: data['mandatory'] == true,
    );
  }

  Future<void> openDownload(AppUpdate update) async {
    if (!await launchUrl(
      update.downloadUrl,
      mode: LaunchMode.externalApplication,
    )) {
      throw ApiException('无法打开更新下载地址');
    }
  }

  static String? get _platformName {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.windows => 'windows',
      TargetPlatform.macOS => 'macos',
      _ => null,
    };
  }

  static bool _isNewer(String latest, String current) {
    final left = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final right = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var index = 0; index < 3; index++) {
      final a = index < left.length ? left[index] : 0;
      final b = index < right.length ? right[index] : 0;
      if (a != b) return a > b;
    }
    return false;
  }
}
