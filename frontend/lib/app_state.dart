import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'models.dart';
import 'services/notification_service.dart';
import 'services/update_service.dart';

class AppState extends ChangeNotifier {
  AppState(this.api, {NotificationService? notifications})
    : notifications = notifications ?? NotificationService.instance,
      updates = UpdateService(api);
  final ApiClient api;
  final NotificationService notifications;
  final UpdateService updates;

  bool booting = true;
  bool busy = false;
  Map<String, dynamic>? user;
  List<AppProject> projects = [];
  Map<String, dynamic>? modelConfig;
  bool remindersEnabled = true;

  bool get isLoggedIn => user != null;

  Future<void> restoreSession() async {
    if (!api.hasConfiguredServer) {
      booting = false;
      notifyListeners();
      return;
    }
    api.token = await api.tokenStorage.read();
    if (api.token != null) {
      try {
        user = Map<String, dynamic>.from(await api.get('/auth/me'));
        await loadProjects();
        await loadPreferences();
        await syncReminders();
      } catch (_) {
        await api.clearToken();
      }
    }
    booting = false;
    notifyListeners();
  }

  Future<void> authenticate({
    required bool register,
    required String account,
    required String password,
    String? email,
  }) async {
    busy = true;
    notifyListeners();
    try {
      final data = register
          ? await api.post('/auth/register', {
              'username': account.trim(),
              'email': email?.trim().isEmpty == true ? null : email?.trim(),
              'password': password,
            })
          : await api.post('/auth/login', {
              'account': account.trim(),
              'password': password,
            });
      await api.saveToken(data['access_token'] as String);
      user = Map<String, dynamic>.from(data['user'] as Map);
      await loadProjects();
      await loadPreferences();
      await syncReminders(requestPermission: remindersEnabled);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await api.clearToken();
    await notifications.clear();
    user = null;
    projects = [];
    notifyListeners();
  }

  Future<void> loadProjects() async {
    final data = await api.get('/projects') as List<dynamic>;
    projects = data
        .map(
          (item) => AppProject.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    notifyListeners();
  }

  Future<AppProject> createProject(Map<String, dynamic> payload) async {
    final data = await api.post('/projects', payload);
    final project = AppProject.fromJson(Map<String, dynamic>.from(data as Map));
    projects.insert(0, project);
    notifyListeners();
    return project;
  }

  Future<AppProject> saveProject(AppProject project) async {
    final data = await api.put('/projects/${project.id}', project.toPayload());
    final saved = AppProject.fromJson(Map<String, dynamic>.from(data as Map));
    final index = projects.indexWhere((item) => item.id == saved.id);
    if (index >= 0) projects[index] = saved;
    notifyListeners();
    return saved;
  }

  Future<Map<String, dynamic>?> loadModelConfig() async {
    final data = await api.get('/model-config');
    modelConfig = data == null ? null : Map<String, dynamic>.from(data as Map);
    notifyListeners();
    return modelConfig;
  }

  Future<void> saveModelConfig(Map<String, dynamic> payload) async {
    final data = await api.put('/model-config', payload);
    modelConfig = Map<String, dynamic>.from(data as Map);
    notifyListeners();
  }

  Future<void> loadPreferences() async {
    final data = await api.get('/preferences') as Map<String, dynamic>;
    remindersEnabled = data['reminders_enabled'] as bool? ?? true;
    notifyListeners();
  }

  Future<void> setRemindersEnabled(bool enabled) async {
    final data = await api.put('/preferences', {'reminders_enabled': enabled});
    remindersEnabled = (data as Map)['reminders_enabled'] as bool? ?? enabled;
    if (remindersEnabled) {
      await syncReminders(requestPermission: true);
    } else {
      await notifications.clear();
    }
    notifyListeners();
  }

  Future<void> syncReminders({bool requestPermission = false}) async {
    if (user == null || !remindersEnabled) return;
    try {
      await notifications.sync(api, requestPermission: requestPermission);
    } catch (_) {
      // Reminder synchronisation must not block login or report generation.
    }
  }
}
