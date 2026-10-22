import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String keyGeminiApiKey = 'gemini_api_key';
  static const String keyGeminiApiKeys = 'gemini_api_keys_list';
  static const String keyTtsEndpoint = 'khmer_tts_endpoint';
  static const String keyTtsApiToken = 'khmer_tts_api_token';
  static const String keyVoicePrasithId = 'voice_prasith_id';
  static const String keyVoiceSreymomId = 'voice_sreymom_id';
  static const String keyDefaultDucking = 'default_ducking_volume';
  static const String keyRemoveChineseVocals = 'remove_chinese_vocals';
  static const String keyAudioSyncDelay = 'audio_sync_delay_ms';
  static const String keyWatermarkEnabled = 'watermark_enabled';
  static const String keyWatermarkText = 'watermark_text';
  static const String keyWatermarkFont = 'watermark_font';
  static const String keyWatermarkColor = 'watermark_color';
  static const String keyWatermarkOpacity = 'watermark_opacity';
  static const String keySubtitleEnabled = 'subtitle_enabled';
  static const String keySubtitleColor = 'subtitle_color';
  static const String keySubtitleFontSize = 'subtitle_font_size';
  static const String keySelectedBgmTrack = 'selected_bgm_track';
  static const String keyBgmVolume = 'bgm_volume';

  // Default values
  static const String defaultTtsEndpoint = 'https://api.khmervoice.ai/v1/tts';
  static const String defaultPrasithId = 'km-KH-PisethNeural';
  static const String defaultSreymomId = 'km-KH-SreymomNeural';
  static const String defaultWatermarkText = 'ដោយ.B.T.movie';
  static const String defaultWatermarkFont = 'Moul';
  static const String defaultWatermarkColor = 'gold';
  static const double defaultWatermarkOpacity = 0.40;

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

  double get defaultDuckingVolume =>
      _prefs.getDouble(keyDefaultDucking) ?? 0.80; // Default 80% for rich cinematic BGM/SFX
  set defaultDuckingVolume(double val) =>
      _prefs.setDouble(keyDefaultDucking, val);

  /// Automatically filters out center Chinese speech, leaving BGM/SFX background track (default true)
  bool get removeChineseVocals =>
      _prefs.getBool(keyRemoveChineseVocals) ?? true;
  set removeChineseVocals(bool val) =>
      _prefs.setBool(keyRemoveChineseVocals, val);

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

  /// Khmer font family for video watermark logo (e.g. 'Moul', 'Preahvihear', etc.)
  String get watermarkFont =>
      _prefs.getString(keyWatermarkFont) ?? defaultWatermarkFont;
  set watermarkFont(String val) => _prefs.setString(keyWatermarkFont, val);

  /// Color for watermark logo (e.g. 'gold', 'white', 'cyan', etc.)
  String get watermarkColor =>
      _prefs.getString(keyWatermarkColor) ?? defaultWatermarkColor;
  set watermarkColor(String val) => _prefs.setString(keyWatermarkColor, val);

  /// Watermark opacity / shadow level (default 40% = 0.40)
  double get watermarkOpacity =>
      _prefs.getDouble(keyWatermarkOpacity) ?? defaultWatermarkOpacity;
  set watermarkOpacity(double val) =>
      _prefs.setDouble(keyWatermarkOpacity, val);

  /// On-video Khmer subtitle display toggle (disabled per user request)
  bool get subtitleEnabled => false;
  set subtitleEnabled(bool val) => _prefs.setBool(keySubtitleEnabled, false);

  /// Subtitle color: 'yellow' (default), 'white', 'cyan', 'green'
  String get subtitleColor =>
      _prefs.getString(keySubtitleColor) ?? 'yellow';
  set subtitleColor(String val) => _prefs.setString(keySubtitleColor, val);

  /// Subtitle font size: 'small' (compact, 9:16 optimized), 'medium'
  String get subtitleFontSize =>
      _prefs.getString(keySubtitleFontSize) ?? 'small';
  set subtitleFontSize(String val) =>
      _prefs.setString(keySubtitleFontSize, val);

  /// Selected background music track ID for movie recaps ('original', 'action', 'suspense', 'none', etc.)
  String get selectedBgmTrack =>
      _prefs.getString(keySelectedBgmTrack) ?? 'original';
  set selectedBgmTrack(String val) =>
      _prefs.setString(keySelectedBgmTrack, val);

  /// Background music volume (0.0 to 1.0, default 0.70 for punchy cinematic recap music)
  double get bgmVolume => _prefs.getDouble(keyBgmVolume) ?? 0.70;
  set bgmVolume(double val) => _prefs.setDouble(keyBgmVolume, val);
}
