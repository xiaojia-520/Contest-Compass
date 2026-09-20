import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'app_state.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/app_config.dart';
import 'services/desktop_service.dart';
import 'services/notification_service.dart';
import 'services/token_storage.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  await DesktopService.instance.initialize(preferences);
  await NotificationService.instance.initialize();
  runApp(SaizhijianApp(preferences: preferences));
}

class SaizhijianApp extends StatefulWidget {
  const SaizhijianApp({super.key, required this.preferences});

  final SharedPreferences preferences;

  @override
  State<SaizhijianApp> createState() => _SaizhijianAppState();
}

class _SaizhijianAppState extends State<SaizhijianApp> {
  late final AppState state;

  @override
  void initState() {
    super.initState();
    final tokenStorage = TokenStorage(widget.preferences);
    state = AppState(ApiClient(widget.preferences, tokenStorage));
    state.restoreSession();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '赛智荐',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          if (!AppConfig.hasApiBase) {
            return const _ServerNotConfiguredScreen();
          }
          if (state.booting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return state.isLoggedIn
              ? HomeScreen(state: state)
              : AuthScreen(state: state);
        },
      ),
    );
  }
}

class _ServerNotConfiguredScreen extends StatelessWidget {
  const _ServerNotConfiguredScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 52, color: coral),
                const SizedBox(height: 20),
                Text(
                  '服务器地址尚未配置',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                const Text(
                  '请在构建应用时通过 API_BASE_URL 注入正式 HTTPS 后端地址。\n'
                  '例如：--dart-define=API_BASE_URL=https://api.example.com/api',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
