import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'models.dart';

class AppState extends ChangeNotifier {
  AppState(this.api);
  final ApiClient api;

  bool booting = true;
  bool busy = false;
  Map<String, dynamic>? user;
  List<AppProject> projects = [];
  Map<String, dynamic>? modelConfig;

  bool get isLoggedIn => user != null;

  Future<void> restoreSession() async {
    api.token = api.preferences.getString('access_token');
    if (api.token != null) {
      try {
        user = Map<String, dynamic>.from(await api.get('/auth/me'));
        await loadProjects();
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
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await api.clearToken();
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
}
