import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/settings_service.dart';
import 'screens/home_screen.dart';
import 'theme/studio_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set immersive dark navy status and navigation bars matching UI reference
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF030712),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final settingsService = await SettingsService.init();

  runApp(KhmerDubbingStudioApp(
    settingsService: settingsService,
  ));
}

class KhmerDubbingStudioApp extends StatelessWidget {
  final SettingsService settingsService;

  const KhmerDubbingStudioApp({
    super.key,
    required this.settingsService,
  });

  @override
  Widget build(BuildContext context) {
    // Beautiful Khmer Typography using Kantumruy Pro
    final textTheme = GoogleFonts.kantumruyProTextTheme(
      StudioTheme.themeData.textTheme,
    );

    return MaterialApp(
      title: 'Khmer Dubbing Studio',
      debugShowCheckedModeBanner: false,
      theme: StudioTheme.themeData.copyWith(
        textTheme: textTheme,
      ),
      home: HomeScreen(
        settingsService: settingsService,
      ),
    );
  }
}
