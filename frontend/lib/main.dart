import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'app_state.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
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
    state = AppState(ApiClient(widget.preferences));
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
