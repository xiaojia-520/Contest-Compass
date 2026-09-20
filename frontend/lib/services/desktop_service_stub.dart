import 'package:shared_preferences/shared_preferences.dart';

class DesktopService {
  DesktopService._();
  static final DesktopService instance = DesktopService._();

  bool get supported => false;
  Future<void> initialize(SharedPreferences preferences) async {}
  Future<bool> isLaunchAtStartupEnabled() async => false;
  Future<void> setLaunchAtStartup(bool enabled) async {}
}
