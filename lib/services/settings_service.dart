import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String keyGeminiApiKey = 'gemini_api_key';
  static const String keyTtsEndpoint = 'khmer_tts_endpoint';
  static const String keyTtsApiToken = 'khmer_tts_api_token';
  static const String keyVoicePrasithId = 'voice_prasith_id';
  static const String keyVoiceSreymomId = 'voice_sreymom_id';
  static const String keyDefaultDucking = 'default_ducking_volume';

  // Default values
  static const String defaultTtsEndpoint = 'https://api.khmervoice.ai/v1/tts';
  static const String defaultPrasithId = 'prasith_male_natural_v2';
  static const String defaultSreymomId = 'sreymom_female_expressive_v2';

  final SharedPreferences _prefs;

  SettingsService(this._prefs);

  static Future<SettingsService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }

  String get geminiApiKey => _prefs.getString(keyGeminiApiKey) ?? '';
  set geminiApiKey(String val) => _prefs.setString(keyGeminiApiKey, val);

  String get ttsEndpoint => _prefs.getString(keyTtsEndpoint) ?? defaultTtsEndpoint;
  set ttsEndpoint(String val) => _prefs.setString(keyTtsEndpoint, val);

  String get ttsApiToken => _prefs.getString(keyTtsApiToken) ?? '';
  set ttsApiToken(String val) => _prefs.setString(keyTtsApiToken, val);

  String get voicePrasithId => _prefs.getString(keyVoicePrasithId) ?? defaultPrasithId;
  set voicePrasithId(String val) => _prefs.setString(keyVoicePrasithId, val);

  String get voiceSreymomId => _prefs.getString(keyVoiceSreymomId) ?? defaultSreymomId;
  set voiceSreymomId(String val) => _prefs.setString(keyVoiceSreymomId, val);

  double get defaultDuckingVolume => _prefs.getDouble(keyDefaultDucking) ?? 0.15;
  set defaultDuckingVolume(double val) => _prefs.setDouble(keyDefaultDucking, val);
}
