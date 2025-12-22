import 'package:flutter/material.dart';
import 'package:kinet_composer/ui/home_screen.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:kinet_composer/state/show_state.dart';
import 'package:kinet_composer/services/discovery_service.dart';
import 'package:kinet_composer/services/pixel_engine.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:kinet_composer/ui/intro_screen.dart';

import 'package:bitsdojo_window/bitsdojo_window.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  
  final prefs = await SharedPreferences.getInstance();
  final showIntro = prefs.getBool('show_intro') ?? true;
  
  runApp(KinetComposerApp(showIntro: showIntro));

  doWhenWindowReady(() {
    const initialSize = Size(1280, 720);
    appWindow.minSize = const Size(800, 600);
    appWindow.size = initialSize;
    appWindow.alignment = Alignment.center;
    appWindow.title = "LT Composer";
    appWindow.show();
  });
}

class KinetComposerApp extends StatelessWidget {
  final bool showIntro;
  const KinetComposerApp({super.key, required this.showIntro});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ShowState()),
        Provider(create: (_) => DiscoveryService()),
        ProxyProvider<DiscoveryService, PixelEngine>(
          update: (_, discovery, prev) => prev ?? PixelEngine(discovery),
        ),
      ],
      child: MaterialApp(
        title: 'Kinet Composer',
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Roboto', // Global default
          scaffoldBackgroundColor: Colors.transparent,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6200EE),
            brightness: Brightness.dark,
            secondary: Colors.cyanAccent,
            surface: const Color(0x0DFFFFFF), // Very transparent white
          ),
          textTheme: const TextTheme(
             // Slicker defaults
             displayLarge: TextStyle(fontWeight: FontWeight.w300, letterSpacing: -1.5),
             displayMedium: TextStyle(fontWeight: FontWeight.w300, letterSpacing: -0.5),
             displaySmall: TextStyle(fontWeight: FontWeight.w400),
             headlineMedium: TextStyle(fontWeight: FontWeight.w300),
             headlineSmall: TextStyle(fontWeight: FontWeight.w400),
             titleLarge: TextStyle(fontWeight: FontWeight.w500),
             bodyLarge: TextStyle(fontWeight: FontWeight.w400),
             bodyMedium: TextStyle(fontWeight: FontWeight.w400),
          ),
          appBarTheme: const AppBarTheme(
             backgroundColor: Colors.transparent,
             elevation: 0,
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        home: showIntro ? const IntroScreen() : const HomeScreen(),
      ),
    );
  }
}

