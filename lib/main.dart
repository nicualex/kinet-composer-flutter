import 'package:flutter/material.dart';
import 'package:kinet_composer/ui/home_screen.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:kinet_composer/state/show_state.dart';
import 'package:kinet_composer/services/discovery_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const KinetComposerApp());
}

class KinetComposerApp extends StatelessWidget {
  const KinetComposerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ShowState()),
        Provider(create: (_) => DiscoveryService()),
      ],
      child: MaterialApp(
        title: 'Kinet Composer',
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.transparent,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6200EE),
            brightness: Brightness.dark,
            secondary: Colors.cyanAccent,
            surface: const Color(0x0DFFFFFF), // Very transparent white
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
        home: const HomeScreen(),
      ),
    );
  }
}

