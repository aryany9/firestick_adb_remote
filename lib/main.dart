// main.dart
import 'package:firestick_adb_remote/presentation/screens/log_viewer_screen.dart';
import 'package:firestick_adb_remote/presentation/screens/settings_screen.dart';
import 'package:firestick_adb_remote/presentation/state/remote_controller.dart';
import 'package:firestick_adb_remote/services/log_service.dart';
import 'package:firestick_adb_remote/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'data/adb/adb_manager.dart';
import 'presentation/screens/splash_screen.dart';
import 'presentation/screens/remote_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations (optional - portrait only)
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF1F4788),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  await LogService.instance.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RemoteController(AdbManager())),
        ChangeNotifierProvider(create: (_) => AdbManager()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Firestick ADB Remote',
      routes: {
        "/settings": (_) => const SettingsScreen(),
        "/logs": (_) => const LogViewerScreen(),
      },
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      home: const SplashScreen(nextScreen: RemoteScreen()),
    );
  }
}
