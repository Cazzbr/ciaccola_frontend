import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ciaccola_frontend/screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // On Flutter web, hot restart leaves a requestAnimationFrame already queued
  // in the browser that fires after EngineFlutterView.dispose() completes.
  // The resulting "Trying to render a disposed EngineFlutterView" assertion is
  // a development-only engine artifact — it cannot be prevented from app code.
  // Filter it out specifically so it doesn't obscure real errors.
  if (kIsWeb) {
    final original = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exceptionAsString().contains('disposed EngineFlutterView')) {
        return;
      }
      original?.call(details);
    };
  }

  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0C1027),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF4F6EF7),
        secondary: Color(0xFF06D6A0),
        surface: Color(0xFF161D3F),
        tertiary: Color(0xFF9333EA),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0C1027),
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFF4F6EF7),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1C2447),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF06D6A0), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF06D6A0), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4F6EF7), width: 2),
        ),
        labelStyle: const TextStyle(color: Color(0xFF06D6A0)),
      ),
    );

    return MaterialApp(
      title: 'Ciaccola',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: const SplashScreen(),
    );
  }
}
