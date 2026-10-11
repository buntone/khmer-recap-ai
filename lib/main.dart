import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/settings_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set immersive dark navigation and status bars
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0F172A),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final settingsService = await SettingsService.init();

  runApp(KhmerRecapApp(settingsService: settingsService));
}

class KhmerRecapApp extends StatelessWidget {
  final SettingsService settingsService;

  const KhmerRecapApp({Key? key, required this.settingsService}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Elegant Khmer Typography using Kantumruy Pro & Battambang
    final textTheme = GoogleFonts.kantumruyProTextTheme(
      ThemeData.dark().textTheme,
    );

    return MaterialApp(
      title: 'Khmer Recap AI Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE11D48),
          secondary: Color(0xFFF59E0B),
          surface: Color(0xFF1E293B),
          background: const Color(0xFF0F172A),
        ),
        textTheme: textTheme,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E293B),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: HomeScreen(settingsService: settingsService),
    );
  }
}
