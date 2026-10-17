import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String keyGeminiApiKey = 'gemini_api_key';
  static const String keyGeminiApiKeys = 'gemini_api_keys_list';
  static const String keyTtsEndpoint = 'khmer_tts_endpoint';
  static const String keyTtsApiToken = 'khmer_tts_api_token';
  static const String keyVoicePrasithId = 'voice_prasith_id';
  static const String keyVoiceSreymomId = 'voice_sreymom_id';
  static const String keyDefaultDucking = 'default_ducking_volume';
  static const String keyAudioSyncDelay = 'audio_sync_delay_ms';
  static const String keyWatermarkEnabled = 'watermark_enabled';
  static const String keyWatermarkText = 'watermark_text';

  // Default values
  static const String defaultTtsEndpoint = 'https://api.khmervoice.ai/v1/tts';
  static const String defaultPrasithId = 'km-KH-PisethNeural';
  static const String defaultSreymomId = 'km-KH-SreymomNeural';
  static const String defaultWatermarkText = 'ដោយ.B.T.movie';

  final SharedPreferences _prefs;

  SettingsService(this._prefs);

  static Future<SettingsService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }

  /// Primary single key for backwards compatibility
  String get geminiApiKey {
    final keys = geminiApiKeys;
    if (keys.isNotEmpty) return keys.first;
    return _prefs.getString(keyGeminiApiKey) ?? '';
  }

  set geminiApiKey(String val) {
    _prefs.setString(keyGeminiApiKey, val.trim());
    if (val.trim().isNotEmpty) {
      final list = geminiApiKeys;
      if (!list.contains(val.trim())) {
        list.insert(0, val.trim());
        geminiApiKeys = list;
      }
    }
  }

  /// List of multiple Gemini API keys in the pool
  List<String> get geminiApiKeys {
    final stored = _prefs.getStringList(keyGeminiApiKeys);
    if (stored != null && stored.isNotEmpty) {
      final clean = stored
          .map((k) => k.trim())
          .where((k) => k.isNotEmpty)
          .toSet()
          .toList();
      return clean;
    }
    final single = _prefs.getString(keyGeminiApiKey)?.trim() ?? '';
    if (single.isNotEmpty) {
      return [single];
    }
    return [];
  }

  set geminiApiKeys(List<String> keys) {
    final clean =
        keys.map((k) => k.trim()).where((k) => k.isNotEmpty).toSet().toList();
    _prefs.setStringList(keyGeminiApiKeys, clean);
    if (clean.isNotEmpty) {
      _prefs.setString(keyGeminiApiKey, clean.first);
    } else {
      _prefs.setString(keyGeminiApiKey, '');
    }
  }

  /// Adds one or multiple API keys separated by commas, newlines, or semicolons
  void addGeminiKeys(String rawInput) {
    final current = List<String>.from(geminiApiKeys);
    final incoming = rawInput
        .split(RegExp(r'[\r\n,;]+'))
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty);

    for (final key in incoming) {
      if (!current.contains(key)) {
        current.add(key);
      }
    }
    geminiApiKeys = current;
  }

  /// Removes a specific key from the pool
  void removeGeminiKey(String keyToRemove) {
    final current = List<String>.from(geminiApiKeys);
    current.remove(keyToRemove.trim());
    geminiApiKeys = current;
  }

  String get ttsEndpoint =>
      _prefs.getString(keyTtsEndpoint) ?? defaultTtsEndpoint;
  set ttsEndpoint(String val) => _prefs.setString(keyTtsEndpoint, val);

  String get ttsApiToken => _prefs.getString(keyTtsApiToken) ?? '';
  set ttsApiToken(String val) => _prefs.setString(keyTtsApiToken, val);

  String get voicePrasithId =>
      _prefs.getString(keyVoicePrasithId) ?? defaultPrasithId;
  set voicePrasithId(String val) => _prefs.setString(keyVoicePrasithId, val);

  String get voiceSreymomId =>
      _prefs.getString(keyVoiceSreymomId) ?? defaultSreymomId;
  set voiceSreymomId(String val) => _prefs.setString(keyVoiceSreymomId, val);

  double get defaultDuckingVolume => _prefs.getDouble(keyDefaultDucking) ?? 0.0;
  set defaultDuckingVolume(double val) =>
      _prefs.setDouble(keyDefaultDucking, val);

  /// Delay in seconds to shift audio forward/backward to align with mouth movements (default 0.0s)
  double get audioSyncDelay => _prefs.getDouble(keyAudioSyncDelay) ?? 0.0;
  set audioSyncDelay(double val) => _prefs.setDouble(keyAudioSyncDelay, val);

  /// Moving watermark text overlay on generated video (e.g. "ដោយ.B.T.movie")
  bool get watermarkEnabled => _prefs.getBool(keyWatermarkEnabled) ?? true;
  set watermarkEnabled(bool val) => _prefs.setBool(keyWatermarkEnabled, val);

  String get watermarkText =>
      _prefs.getString(keyWatermarkText) ?? defaultWatermarkText;
  set watermarkText(String val) =>
      _prefs.setString(keyWatermarkText, val.trim());
}
