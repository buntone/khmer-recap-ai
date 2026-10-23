import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiRecapService {
  final List<String> apiKeys;

  GeminiRecapService({String? apiKey, List<String>? apiKeys})
      : apiKeys = (apiKeys != null && apiKeys.isNotEmpty)
            ? apiKeys.map((k) => k.trim()).where((k) => k.isNotEmpty).toList()
            : (apiKey != null && apiKey.trim().isNotEmpty)
                ? [apiKey.trim()]
                : [];

  /// Dynamically queries Google's ModelService.ListModels endpoint
  /// to discover the exact models active and supported for the given API key.
  Future<List<String>> _discoverAvailableModels(String cleanKey) async {
    try {
      final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models?key=$cleanKey');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final modelsList = data['models'] as List<dynamic>? ?? [];
        final available = <String>[];

        for (final m in modelsList) {
          final methods = (m['supportedGenerationMethods'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
          if (methods.contains('generateContent')) {
            final rawName = m['name'] as String? ?? '';
            final name = rawName.replaceFirst('models/', '');
            // Filter out text-embedding, image generation, and omni/live preview models
            if (name.isNotEmpty &&
                !name.contains('embedding') &&
                !name.contains('imagen') &&
                !name.contains('aqa') &&
                !name.contains('omni') &&
                !name.contains('live') &&
                !name.contains('realtime')) {
              available.add(name);
            }
          }
        }

        if (available.isNotEmpty) {
          // Explicit priority: standard production models with high free-tier quotas and video support
          const priorityOrder = [
            'gemini-1.5-flash',
            'gemini-2.0-flash',
            'gemini-1.5-flash-8b',
            'gemini-2.0-flash-lite',
            'gemini-1.5-pro',
          ];

          available.sort((a, b) {
            final aIdx = priorityOrder.indexOf(a);
            final bIdx = priorityOrder.indexOf(b);
            if (aIdx != -1 && bIdx != -1) return aIdx.compareTo(bIdx);
            if (aIdx != -1) return -1;
            if (bIdx != -1) return 1;
            final aFlash = a.contains('flash');
            final bFlash = b.contains('flash');
            if (aFlash && !bFlash) return -1;
            if (!aFlash && bFlash) return 1;
            return b.compareTo(a);
          });

          return available;
        }
      }
    } catch (_) {}

    // Modern fallback candidate models in case ListModels is offline
    return const [
      'gemini-1.5-flash',
      'gemini-2.0-flash',
      'gemini-1.5-flash-8b',
      'gemini-1.5-pro',
    ];
  }

  /// Analyzes Chinese dialogue in video/audio and translates accurately into spoken Khmer with timestamps.
  Future<String> generateKhmerRecapScript({
    required String mediaPath,
    required double videoDurationSeconds,
    String mimeType = 'audio/mp3',
    String? tonePreference,
  }) async {
    if (apiKeys.isEmpty) {
      throw Exception(
          'សូមកំណត់ Gemini API Key យ៉ាងហោចណាស់ ១ នៅក្នុង Settings ជាមុនសិន!');
    }

    final file = File(mediaPath);
    if (!await file.exists()) {
      throw Exception('រកមិនឃើញឯកសារមេឌៀសម្រាប់វិភាគឡើយ: $mediaPath');
    }

    final bytes = await file.readAsBytes();

    final durationMinutes =
        (videoDurationSeconds ~/ 60).toString().padLeft(2, '0');
    final durationSecs =
        (videoDurationSeconds.toInt() % 60).toString().padLeft(2, '0');
    final durationFormatted = '$durationMinutes:$durationSecs';

    final promptText = '''
អ្នកគឺជាអ្នកជំនាញបកប្រែ និងបញ្ចូលសំឡេងភាពយន្តចិន-ខ្មែរអាជីព (Professional Chinese-to-Khmer Movie Dubbing Specialist)។
ភារកិច្ចចម្បងរបស់អ្នក៖
១. **ពិនិត្យមើលវីដេអូ អានអក្សររត់ពីក្រោម (Subtitles) ភាសាចិនលើផ្ទាំងរូបភាព និងស្ដាប់ការសន្ទនារបស់តួអង្គឱ្យបានច្បាស់លាស់ ១០០%**។
២. **បកប្រែសាច់រឿង ការសម្រាយរឿង និងការសន្ទនាជាភាសាខ្មែរ ដោយកត់ត្រាពេលវេលា [MM:SS - MM:SS] ឬ [MM:SS] ឱ្យចំពេលដែលតួអង្គកម្រើកមាត់និយាយ និងអក្សររត់ចិនបង្ហាញលើអេក្រង់ ឱ្យត្រូវគ្នានឹងមាត់តួអង្គ ១០០%**។

🎥 ព័ត៌មានវីដេអូ៖
- រយៈពេលវីដេអូសរុប៖ $durationFormatted (${videoDurationSeconds.toStringAsFixed(1)} វិនាទី)

🎯 គោលការណ៍កំណត់ពេលវេលា និងបកប្រែ (CRITICAL RULES - 100% DIALOGUE COVERAGE & PERFECT LIP-SYNC):

១. **ហាមដាច់ខាតកុំរំលង ឬចោលឃ្លាសន្ទនាណាមួយ (STRICT ZERO MISSED DIALOGUE - គ្រប់ឃ្លាទាំងអស់ត្រូវតែបកប្រែ)**:
   - គ្រប់ពេលដែលតួអង្គកម្រើកមាត់និយាយ ឬមានអក្សររត់ចិន (Subtitles) បង្ហាញលើវីដេអូ ឬមានសំឡេងនិយាយក្នុងសាច់រឿង ចាប់ពីវិនាទីដំបូង [00:00] រហូតដល់វិនាទីចុងក្រោយនៃវីដេអូ ត្រូវតែបកប្រែជាភាសាខ្មែរទាំងអស់ ១០០%!
   - ហាមដាច់ខាតកុំទុកឱ្យវីដេអូស្ងាត់ ឬរំលងឃ្លាសន្ទនាណាឡើយ ទោះជាឃ្លាខ្លីៗក៏ដោយ។

២. **កំណត់ពេលវេលាត្រូវនឹងមាត់តួអង្គបើក និងបិទ (PERFECT LIP-SYNC & INSTANT TRIGGER TIMESTAMPS)**:
   - **គ្រាន់តែតួអង្គកម្រើកហើបមាត់និយាយ ឬអក្សររត់ចិនចាប់ផ្ដើមលោតឡើងលើផ្ទាំងរូបភាពភ្លាម សំឡេងខ្មែរត្រូវចាប់ផ្ដើមនិយាយភ្លាម (Instant Trigger)**: ត្រូវកត់ត្រា Timestamp ចាប់ផ្ដើម [MM:SS] ឱ្យចំវិនាទីដំបូងបង្អស់ដែលតួអង្គហើបមាត់និយាយ ឬអក្សររត់ចិនចាប់ផ្ដើមលោតឡើង ហាមដាច់ខាតកុំដាក់យឺតពេលជាងមាត់តួអង្គ! (បើតួចិនចាប់ផ្ដើមនិយាយនៅ 00:03 ត្រូវដាក់ `[00:03 - ...]` ហាមដាក់ 00:04 ឬ 00:05 ដែលធ្វើឱ្យឮសំឡេងចិនមុនសំឡេងខ្មែរ)។
   - **Timestamp បញ្ចប់ ត្រូវដាក់ឱ្យដល់វិនាទីចុងក្រោយបង្អស់ដែលតួចិនបិទមាត់ឈប់និយាយ (STRICT END-OF-SPEECH TIMING)**: ហាមដាច់ខាតកុំដាក់ Timestamp បញ្ចប់មុនពេលតួចិនឈប់និយាយ (បើតួចិននិយាយដល់ 00:08 ត្រូវដាក់រហូតដល់ 00:08 ដាច់ខាត កុំដាក់ត្រឹម 00:06 ដែលនាំឱ្យនៅសល់សំឡេងចិន ៣-៤ ម៉ាត់នៅចុង)។
   - ត្រូវកត់ត្រាពេលវេលាចាប់ផ្ដើម និងបញ្ចប់ឱ្យច្បាស់លាស់៖ `[MM:SS - MM:SS]` ឬ `[MM:SS]`។

៣. **បកប្រែឃ្លាខ្មែរឱ្យវែង និងពេញលេញ ដើម្បីគ្របដណ្ដប់សំឡេងចិនដល់ចុងបញ្ចប់ (ELONGATE KHMER SENTENCES TO FULLY COVER CHINESE SPEECH)**:
   - **សេចក្ដីណែនាំពិសេស**៖ សំឡេងខ្មែរច្រើនតែអានលឿនជាងចិន ដូច្នេះត្រូវបកប្រែប្រយោគខ្មែរឱ្យ**វែង រណ្ដំ និងពេញលេញជាងមុន (បន្ថែមពាក្យអធិប្បាយ ឬពាក្យសន្ទនាឱ្យពិរោះ ក្បោះក្បាយ)** ដើម្បីឱ្យសំឡេងខ្មែរអានរហូតដល់ចុងបញ្ចប់នៃប្រយោគចិន!
   - **ហាមដាច់ខាតកុំឱ្យសំឡេងខ្មែរចប់មុនសំឡេងចិន ៣-៤ ម៉ាត់ចុងក្រោយ**!
   - ក្នុង ១ វិនាទីនៃវីដេអូ ត្រូវបកប្រែពាក្យខ្មែរប្រមាណ ៤ ទៅ ៥ ម៉ាត់៖
     * ប្រសិនបើតួអង្គចិននិយាយ ៣ ទៅ ៥ វិនាទី ត្រូវបកប្រែប្រយោគខ្មែរឱ្យមានប្រវែងវែងពេញលេញ (ប្រហែល ១៤ ទៅ ២២ ម៉ាត់) ដើម្បីឱ្យសំឡេងខ្មែរអានជាប់រហូតដល់តួចិនបិទមាត់!
     * ហាមដាច់ខាតកុំបកប្រែត្រឹម ៣-៤ ម៉ាត់ខ្លីកំបុត ខណៈដែលតួចិនកំពុងនិយាយប្រយោគវែង!
   - សំឡេងខ្មែរត្រូវតែចាប់ផ្ដើមស្របពេលចិនហើបមាត់ និងបញ្ចប់ទៅវិញស្របពេលចិនបិទមាត់ឈប់និយាយ កុំឱ្យនៅសល់សំឡេងចិននៅចុងប្រយោគឡើយ!

៤. **បែងចែកភេទតួអង្គ និងសំឡេងឱ្យត្រូវគ្នានឹងតួអង្គ ១០០% (STRICT GENDER ACCURACY - ហាមច្រឡំប្រុស/ស្រី)**:
   - ត្រូវពិនិត្យមើលរូបភាពតួអង្គក្នុងវីដេអូ ឬស្ដាប់សំឡេងជាក់ស្ដែងឱ្យបានច្បាស់លាស់៖
   - **តួអង្គមនុស្សស្រីនិយាយ ឬគិតក្នុងចិត្ត** (ស្ត្រី, នារី, ម្ដាយ, ម៉ាក់, កូនស្រី, ប្អូនស្រី, ភរិយា, ប្រពន្ធ, យាយ, មីង, អ្នកនាង, កញ្ញា) ត្រូវតែប្រើស្លាក `[ស្រី]:` ដាច់ខាត!
   - ហាមដាច់ខាតកុំប្រើស្លាក `[ប្រុស]:` លើឈុតឆាក ឬឃ្លាដែលតួស្រីកំពុងនិយាយ!
   - **តួអង្គមនុស្សប្រុសនិយាយ ឬគិតក្នុងចិត្ត** (បុរស, ឪពុក, ប៉ា, កូនប្រុស, ប្អូនប្រុស, ប្ដី, តា, ពូ) ត្រូវតែប្រើស្លាក `[ប្រុស]:`!
   - សម្គាល់តាមពាក្យហៅ និងសព្វនាម៖ បើនិយាយទៅកាន់ប្ដី ឬបង ("បង...", "លោកប្ដី...", "បងសម្លាញ់...") ឬនិយាយក្នុងនាមជាម្ដាយ ("ម៉ាក់ប្រាប់...", "ម៉ែ...") ឬជាកូនស្រី/ភរិយា គឺច្បាស់ជាតួស្រីនិយាយ ត្រូវដាក់ `[ស្រី]:`! បើនិយាយទៅកាន់ប្រពន្ធ ឬអូន ("អូន...", "អូនសម្លាញ់...") ឬក្នុងនាមជាឪពុក/ប្ដី គឺច្បាស់ជា `[ប្រុស]:`!
   - ករណីការនិទានដំណើររឿង (Voiceover Narration)៖ បើជាអ្នករៀបរាប់ទូទៅ ប្រើ `[ប្រុស]:` ប៉ុន្តែបើសាច់រឿងជារៀបរាប់ដោយតួឯកស្រី (Female POV) ត្រូវប្រើ `[ស្រី]:`!

៥. **មនុស្សនិយាយក្នុងចិត្ត / គិតក្នុងចិត្ត (INNER MONOLOGUE / CHARACTER THOUGHTS)**:
   - ប្រសិនបើតួអង្គមិនកម្រើកមាត់ ប៉ុន្តែមានអក្សររត់ក្នុងវង់ក្រចក (内心/心想/独白) ឬមានសំឡេងបន្លឺក្នុងចិត្ត ត្រូវបកប្រែ និងដាក់ Timestamp ឱ្យចំពេលនោះ ហាមកាត់ចោល។
   - បើសិនជាតួប្រុសគិត ដាក់ `[ប្រុស]: (ក្នុងចិត្ត) ...`
   - បើសិនជាតួស្រីគិត ដាក់ `[ស្រី]: (ក្នុងចិត្ត) ...`
   - **សំខាន់បំផុត**៖ ស្លាក `(ក្នុងចិត្ត)` គ្រាន់តែជាសញ្ញាសម្គាល់បច្ចេកទេសសម្រាប់ប្រព័ន្ធបញ្ចូល Effect សំឡេងរណ្ដំរងំក្នុងចិត្តប៉ុណ្ណោះ។ ហាមដាច់ខាតកុំសរសេរពាក្យថា "សំឡេងក្នុងចិត្ត" ឬ "គិតក្នុងចិត្ត" ឬ "និយាយក្នុងចិត្ត" ចូលទៅក្នុងឃ្លាសន្ទនាដែលត្រូវនិយាយ គឺសរសេរតែពាក្យគិតផ្ទាល់ប៉ុណ្ណោះ!

៦. **១ បន្ទាត់ សម្រាប់តួអង្គតែ ១ នាក់គត់ (STRICT SINGLE SPEAKER PER LINE)**:
   - រាល់បន្ទាត់ទាំងអស់ ដាច់ខាតត្រូវតែមានស្លាក [ប្រុស]: ឬ [ស្រី]: នៅខាងមុខជានិច្ច ហាមដាច់ខាតកុំចោលបន្ទាត់ណាដោយគ្មានស្លាក!
   - ហាមដាក់ [ប្រុស] និង [ស្រី] ក្នុងបន្ទាត់តែមួយ! បើឆ្លើយឆ្លងគ្នា ត្រូវចុះបន្ទាត់ថ្មីដាច់ដោយឡែក។

៧. **ហៅឈ្មោះ និងសព្វនាមញាតិមិត្តឱ្យចំៗ (STRICT KINSHIP & FAMILY ADDRESSING)**:
   - ត្រូវបកប្រែពាក្យហៅញាតិសន្តានចិនឱ្យចេញជាពាក្យខ្មែរចំៗ និងត្រឹមត្រូវ ១០០% តាមសាច់រឿង៖ ពុក, ម៉ែ, ប៉ា, ម៉ាក់, លោកតា, លោកយាយ, ពូ, មីង, បង, ប្អូន, ប្ដី, ប្រពន្ធ, កូន, ចៅ ឱ្យចំៗ!

៨. **ទម្រង់លទ្ធផល (STRICT PLAIN TEXT OUTPUT - NO JSON, NO MARKDOWN CODE BLOCKS)**:
សូមសរសេរចេញមកជាបន្ទាត់ៗផ្ទាល់ ដោយបញ្ជាក់ពេលវេលា [MM:SS - MM:SS] ឬ [MM:SS] ដូចខាងក្រោម៖
[00:01 - 00:04] [ប្រុស]: បីឆ្នាំមុន នាងត្រូវបានគេបណ្តេញចេញពីត្រកូលយ៉ាងអយុត្តិធម៌។
[00:04 - 00:07] [ស្រី]: (ក្នុងចិត្ត) ថ្ងៃនេះខ្ញុំត្រលប់មកវិញ ដើម្បីទាមទារភាពយុត្តិធម៌!
[00:07 - 00:09] [ស្រី]: ម៉ែមកដើម្បីយករបស់របរឱ្យកូនវិញ។
[00:10 - 00:13] [ប្រុស]: ម៉ែ! កូនជាប់រវល់ការងារនៅទីនេះ។
១០. **🛑 លក្ខខណ្ឌកំហិតដាច់ខាត (CRITICAL MANDATORY ZERO-CHINESE TRANSLATION RULE)**:
    - គ្រប់ឃ្លាសន្ទនាទាំងអស់ ត្រូវតែបកប្រែជា «អក្សរខ្មែរ» ១០០% (ALL OUTPUT MUST BE 100% IN KHMER SCRIPT)!
    - ហាមដាច់ខាត ហាមសរសេរអក្សរចិន (汉字) សូម្បីតែមួយតួក្នុងចម្លើយ! (ABSOLUTELY ZERO CHINESE CHARACTERS ALLOWED).
    - ហាមចម្លងអក្សររត់ចិន (Do NOT transcribe or output Chinese characters/subtitles).
    - ត្រូវបកប្រែចេញជាភាសាខ្មែរដែលពិរោះ រលូន និងទាក់ទាញបែបសម្រាយរឿងកុនភ្លាមៗ។
''';

    final normalizedMime = mimeType == 'audio/mpeg' ? 'audio/mp3' : mimeType;

    final content = [
      Content.multi([
        TextPart(promptText),
        DataPart(normalizedMime, bytes),
      ]),
    ];

    String rawScript = '';
    Object? lastError;

    // Iterate through API key pool with automatic failover
    for (int keyIdx = 0; keyIdx < apiKeys.length; keyIdx++) {
      final currentKey = apiKeys[keyIdx];
      final candidateModels = await _discoverAvailableModels(currentKey);

      for (final modelName in candidateModels) {
        try {
          final model = GenerativeModel(
            model: modelName,
            apiKey: currentKey,
            generationConfig: GenerationConfig(
              temperature: 0.0, // 0.0 for mathematically accurate timestamps
              maxOutputTokens: 8192,
            ),
          );

          GenerateContentResponse response;
          try {
            response = await model.generateContent(content);
          } catch (_) {
            if (normalizedMime.contains('mp3')) {
              final fallbackContent = [
                Content.multi([
                  TextPart(promptText),
                  DataPart('audio/mpeg', bytes),
                ]),
              ];
              response = await model.generateContent(fallbackContent);
            } else {
              rethrow;
            }
          }

          final text = response.text?.trim() ?? '';
          if (text.isNotEmpty) {
            final khmerCount =
                RegExp(r'[\u1780-\u17B3]').allMatches(text).length;
            final chineseCount =
                RegExp(r'[\u4E00-\u9FFF]').allMatches(text).length;

            // If Gemini output contains ANY Chinese or has insufficient Khmer characters:
            // Trigger multi-model/multi-key second-pass text-to-text translation!
            if (chineseCount > 0 || khmerCount < 20) {
              final translated = await _translateChineseOrRawScriptToKhmer(
                rawText: text,
                modelName: modelName,
                apiKey: currentKey,
              );
              final transKhmerCount =
                  RegExp(r'[\u1780-\u17B3]').allMatches(translated).length;
              final transChineseCount =
                  RegExp(r'[\u4E00-\u9FFF]').allMatches(translated).length;
              if (translated.isNotEmpty &&
                  transKhmerCount >= 20 &&
                  transChineseCount == 0) {
                rawScript = translated;
                break;
              }
            } else if (khmerCount >= 20 && chineseCount == 0) {
              rawScript = text;
              break;
            }
          }
        } catch (e) {
          lastError = e;
          // Continue testing next candidate model
          continue;
        }
      }

      if (rawScript.isNotEmpty) {
        break; // Successfully generated script!
      }
    }

    if (rawScript.isEmpty) {
      if (lastError != null) {
        final errStr = lastError.toString().toLowerCase();
        if (errStr.contains('429') ||
            errStr.contains('resource_exhausted') ||
            errStr.contains('quota')) {
          throw Exception(
              'Gemini API Key របស់អ្នកបានដល់កម្រិតកំណត់ (Google Gemini Quota Limit 429)។ សូមចូលទៅកាន់ Settings (⚙️) រួចបញ្ចូល API Key បន្ថែម (Google AI Studio Key) ដើម្បីដំណើរការបន្ត!');
        }
        throw Exception('Gemini AI បរាជ័យក្នុងការបកប្រែ: $lastError');
      }
      throw Exception(
          'មិនអាចចាប់សំឡេងសន្ទនា ឬបកប្រែជាភាសាខ្មែរបានឡើយ។ សូមចុចបង្កើតម្ដងទៀត។');
    }

    return _parseScriptFromResponse(rawScript);
  }

  /// Instant secondary pass: translates Chinese subtitles or raw dialogue directly into spoken Khmer
  Future<String> _translateChineseOrRawScriptToKhmer({
    required String rawText,
    required String modelName,
    required String apiKey,
  }) async {
    final candidateModels = [
      modelName,
      'gemini-1.5-flash',
      'gemini-2.0-flash',
      'gemini-1.5-flash-8b',
    ];

    final keys = [apiKey, ...apiKeys.where((k) => k != apiKey)];

    for (final k in keys) {
      for (final m in candidateModels) {
        try {
          final model = GenerativeModel(
            model: m,
            apiKey: k,
            generationConfig: GenerationConfig(
              temperature: 0.1,
              maxOutputTokens: 8192,
            ),
          );

          final translationPrompt = '''
You are an expert Chinese-to-Khmer film dubbing translator.
The following script was extracted from a Chinese video, but it contains Chinese characters or needs translation into natural Khmer narration.

CRITICAL RULES:
1. Translate 100% into natural, rhythmic spoken Khmer script (ភាសាខ្មែរ / អក្សរខ្មែរ).
2. DO NOT output ANY Chinese characters (汉字). Outputting Chinese is strictly prohibited!
3. Keep the exact timestamps [MM:SS - MM:SS] or [MM:SS] at the start of each line.
4. Keep or assign speaker tags [ប្រុស]: for male or [ស្រី]: for female.
5. Elongate sentences slightly so the Khmer voice sounds complete and matches character mouth movements.

SCRIPT TO TRANSLATE:
$rawText

OUTPUT (Plain text only, 100% Khmer script, absolutely zero Chinese):
''';

          final resp =
              await model.generateContent([Content.text(translationPrompt)]);
          final out = resp.text?.trim() ?? '';
          final chCount = RegExp(r'[\u4E00-\u9FFF]').allMatches(out).length;
          final khCount = RegExp(r'[\u1780-\u17B3]').allMatches(out).length;
          if (out.isNotEmpty && khCount >= 20 && chCount == 0) {
            return out;
          }
        } catch (_) {}
      }
    }
    return '';
  }

  /// Parses response into formatted script lines [MM:SS] [ប្រុស]: Text
  String _parseScriptFromResponse(String rawResponse) {
    // 1. If response is wrapped in JSON, extract dialogue items cleanly
    final trimmed = rawResponse.trim();
    if (trimmed.startsWith('{') ||
        trimmed.startsWith('[') ||
        trimmed.contains('"speaker":') ||
        trimmed.contains('"text":')) {
      try {
        var cleanedJson = trimmed;
        if (cleanedJson.startsWith('```json')) {
          cleanedJson = cleanedJson.replaceFirst(RegExp(r'^```json\s*'), '');
        }
        if (cleanedJson.endsWith('```')) {
          cleanedJson = cleanedJson.replaceFirst(RegExp(r'\s*```$'), '');
        }

        final decoded = jsonDecode(cleanedJson);
        List<dynamic> items = [];
        if (decoded is List) {
          items = decoded;
        } else if (decoded is Map) {
          for (final val in decoded.values) {
            if (val is List) {
              items = val;
              break;
            }
          }
        }

        if (items.isNotEmpty) {
          final buffer = StringBuffer();
          for (final item in items) {
            if (item is Map) {
              final rawTime = item['time'] ??
                  item['timestamp'] ??
                  item['start_time'] ??
                  item['start'];
              final time = _formatTimestamp(rawTime);

              String speaker = (item['speaker'] ?? item['gender'] ?? 'ប្រុស')
                  .toString()
                  .trim();
              final isFemale = speaker.toLowerCase().contains('female') ||
                  speaker.toLowerCase().contains('ស្រី') ||
                  speaker.toLowerCase().contains('woman') ||
                  speaker == 'F';
              final speakerTag = isFemale ? '[ស្រី]:' : '[ប្រុស]:';

              String text =
                  (item['text'] ?? item['khmer'] ?? item['dialogue'] ?? '')
                      .toString()
                      .trim();
              text = text
                  .replaceFirst(
                      RegExp(
                          r'^(?:ការសម្រាយរឿង|សម្រាយសាច់រឿង|សម្រាយរឿង|អ្នកសម្រាយរឿង|សម្រាយ)\s*[:៖\-–\s]*',
                          caseSensitive: false),
                      '')
                  .trim();
              if (text.isNotEmpty &&
                  RegExp(r'[\u1780-\u17FF]').hasMatch(text)) {
                buffer.writeln('$time $speakerTag $text');
              }
            }
          }
          if (buffer.isNotEmpty) {
            return buffer.toString().trim();
          }
        }
      } catch (_) {}
    }

    // 2. Parse direct plain text lines and filter out any JSON artifacts
    return _sanitizeScriptForTts(rawResponse);
  }

  /// Converts any time input (e.g. "00:00:02.800", "00:00:02", 4, "4", "0:04", "00:04.5") into [MM:SS] or [MM:SS.s]
  String _formatSingleTime(dynamic rawTime) {
    if (rawTime == null) return '00:00';
    var s = rawTime
        .toString()
        .trim()
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll('(', '')
        .replaceAll(')', '');
    if (s.isEmpty) return '00:00';
    s = s.replaceAll(',', '.');

    final parts = s.split(':');
    if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = (int.tryParse(parts[1]) ?? 0) + h * 60;
      final secParts = parts[2].split('.');
      final sec = int.tryParse(secParts.first) ?? 0;
      final ms = (secParts.length > 1 && secParts[1].isNotEmpty && secParts[1] != '0')
          ? '.${secParts[1].substring(0, 1)}'
          : '';
      return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}$ms';
    } else if (parts.length == 2) {
      final m = int.tryParse(parts[0])?.toString().padLeft(2, '0') ?? '00';
      final secParts = parts[1].split('.');
      final sec =
          int.tryParse(secParts.first)?.toString().padLeft(2, '0') ?? '00';
      final ms = (secParts.length > 1 && secParts[1].isNotEmpty && secParts[1] != '0')
          ? '.${secParts[1].substring(0, 1)}'
          : '';
      return '$m:$sec$ms';
    } else if (parts.length == 1) {
      final numSec = double.tryParse(parts[0]);
      if (numSec != null) {
        final m = (numSec ~/ 60).toString().padLeft(2, '0');
        final sec = (numSec.toInt() % 60).toString().padLeft(2, '0');
        final dec = ((numSec - numSec.toInt()) * 10).round();
        final ms = dec > 0 ? '.$dec' : '';
        return '$m:$sec$ms';
      }
    }
    return s;
  }

  /// Converts any time input (e.g. "00:00:02,800", "00:00:02", 4, "4", "0:04", "00:04") into [MM:SS] or [MM:SS - MM:SS]
  String _formatTimestamp(dynamic rawTime, [dynamic rawEndTime]) {
    final startStr = _formatSingleTime(rawTime);
    if (rawEndTime != null) {
      final endStr = _formatSingleTime(rawEndTime);
      return '[$startStr - $endStr]';
    }
    return '[$startStr]';
  }

  /// Removes markdown fences, JSON boilerplate, AI preambles, and parses SRT multi-line blocks into clean dialogue lines
  String _sanitizeScriptForTts(String rawText) {
    final lines = rawText.split('\n');
    final buffer = StringBuffer();
    final timePattern = RegExp(
        r'\[?\(?(\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d+)?)(?:\s*(?:-->|[-–])\s*(\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d+)?))?\)?\]?');

    String? pendingTimeTag;
    bool hasSeenFirstTimestamp = false;

    for (final line in lines) {
      var trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (RegExp(r'^\d+$').hasMatch(trimmed)) {
        continue; // Skip SRT block number lines
      }

      // Skip lines that are purely code or JSON symbols
      if (trimmed == '{' ||
          trimmed == '}' ||
          trimmed == '[' ||
          trimmed == ']' ||
          trimmed == '},') {
        continue;
      }
      if (RegExp(r'^"(?:time|speaker|gender|text|dialogue|segments)":',
              caseSensitive: false)
          .hasMatch(trimmed)) {
        final valMatch = RegExp(r':\s*"(.*)"?,?$').firstMatch(trimmed);
        if (valMatch != null) {
          trimmed = valMatch.group(1) ?? '';
        } else {
          continue;
        }
      }

      // Check if line contains a timestamp (e.g. SRT "00:00:02,800 --> 00:00:08,200" or "[00:04]")
      final tMatch = timePattern.firstMatch(trimmed);
      if (tMatch != null) {
        final startRaw = tMatch.group(1);
        final endRaw = tMatch.group(2);
        if (startRaw != null) {
          if (endRaw != null) {
            pendingTimeTag = _formatTimestamp(startRaw, endRaw);
          } else {
            pendingTimeTag = _formatTimestamp(startRaw);
          }
          hasSeenFirstTimestamp = true;
        }
      }

      // Check if line contains any Khmer script
      final hasKhmer = RegExp(r'[\u1780-\u17FF]').hasMatch(trimmed);

      // Filter out pure AI meta headers e.g. "ខាងក្រោមនេះជាការបកប្រែ:"
      if (!hasSeenFirstTimestamp && hasKhmer && tMatch == null) {
        if (RegExp(r'^(?:នេះជា|ខាងក្រោមនេះជា)?\s*(?:ការបកប្រែ|តារាងបកប្រែ|បញ្ជីបកប្រែ)\s*[:៖]?$',
                    caseSensitive: false)
                .hasMatch(trimmed) ||
            trimmed.startsWith('```') ||
            trimmed.startsWith('Translation:') ||
            trimmed.startsWith('Here is')) {
          continue;
        }
        // If it's actual story narration or inner thoughts at the start without timestamp, assign [00:01]
        pendingTimeTag = '[00:01]';
        hasSeenFirstTimestamp = true;
      }

      if (!hasKhmer) continue;

      var lineText = trimmed.replaceAll(timePattern, '').trim();

      bool isFemale = false;
      // 1. Match any bracketed tag at the start e.g. [ស្រី], [ប្រុស], [អ្នករៀបរាប់], [សម្រាយ], [ក្នុងចិត្ត]
      final bracketMatch =
          RegExp(r'^\s*\[([^\]]+)\]\s*[:៖\-–\s]*').firstMatch(lineText);
      if (bracketMatch != null) {
        final tagContent = bracketMatch.group(1)!.trim();
        if (RegExp(
                r'(?:ស្រី|នារី|ស្ត្រី|ម្ដាយ|ម៉ាក់|យាយ|female|woman|girl|\bF\b)',
                caseSensitive: false)
            .hasMatch(tagContent)) {
          isFemale = true;
        } else if (RegExp(
                r'(?:ប្រុស|បុរស|ឪពុក|ប៉ា|តា|អ្នករៀបរាប់|អ្នកសម្រាយ|សម្រាយ|male|man|boy|narrator|\bM\b)',
                caseSensitive: false)
            .hasMatch(tagContent)) {
          isFemale = false;
        }
        lineText =
            lineText.replaceFirst(RegExp(r'^\s*\[([^\]]+)\]\s*[:៖\-–\s]*'), '');
      } else {
        // 2. Match unbracketed tag at start e.g. ស្រី: or ប្រុស: or សម្រាយ:
        final plainMatch =
            RegExp(r'^\s*([^\s:៖\-–]{1,12})\s*[:៖\-–\s]+').firstMatch(lineText);
        if (plainMatch != null) {
          final tagContent = plainMatch.group(1)!.trim();
          if (RegExp(
                  r'(?:ស្រី|នារី|ស្ត្រី|ម្ដាយ|ម៉ាក់|យាយ|female|woman|girl|^F$)',
                  caseSensitive: false)
              .hasMatch(tagContent)) {
            isFemale = true;
            lineText = lineText.replaceFirst(
                RegExp(r'^\s*([^\s:៖\-–]{1,12})\s*[:៖\-–\s]+'), '');
          } else if (RegExp(
                  r'(?:ប្រុស|បុរស|ឪពុក|ប៉ា|តា|អ្នករៀបរាប់|អ្នកសម្រាយ|សម្រាយ|male|man|boy|narrator|^M$)',
                  caseSensitive: false)
              .hasMatch(tagContent)) {
            isFemale = false;
            lineText = lineText.replaceFirst(
                RegExp(r'^\s*([^\s:៖\-–]{1,12})\s*[:៖\-–\s]+'), '');
          }
        }
      }

      final speakerTag = isFemale ? '[ស្រី]:' : '[ប្រុស]:';

      var clean = lineText
          .replaceAll(RegExp(r'["{}\[\]]'), '')
          .replaceAll(RegExp(r'^[:៖\-–\s]+'), '')
          .trim();

      // Eliminate any unwanted "សម្រាយរឿង" / "សម្រាយសាច់រឿង" intro narration prefixes
      clean = clean
          .replaceFirst(
              RegExp(
                  r'^(?:ការសម្រាយរឿង|សម្រាយសាច់រឿង|សម្រាយរឿង|អ្នកសម្រាយរឿង|សម្រាយ)\s*[:៖\-–\s]*',
                  caseSensitive: false),
              '')
          .trim();

      if (clean.isNotEmpty &&
          clean != 'ប្រុស' &&
          clean != 'ស្រី' &&
          clean != 'តួប្រុស' &&
          clean != 'តួស្រី' &&
          RegExp(r'[\u1780-\u17B3]').allMatches(clean).length >= 3) {
        final timeTag = pendingTimeTag ?? '[00:01]';
        pendingTimeTag = null;
        buffer.writeln('$timeTag $speakerTag $clean');
      }
    }

    final result = buffer.toString().trim();
    if (result.isNotEmpty) return result;

    final khmerCount = RegExp(r'[\u1780-\u17B3]').allMatches(rawText).length;
    final chineseCount = RegExp(r'[\u4E00-\u9FFF]').allMatches(rawText).length;
    if (khmerCount < 10 || chineseCount > 0) {
      throw Exception(
          'Gemini មិនបានបកប្រែជាភាសាខ្មែរឡើយ (គ្មានអត្ថបទជាភាសាខ្មែរ)។ សូមចុចបង្កើតវីដេអូសម្រាយរឿងម្ដងទៀត។');
    }

    return rawText
        .replaceAll(RegExp(r'[\u4E00-\u9FFF]'), '')
        .replaceAll(RegExp(r'["{}\[\]]'), '')
        .trim();
  }
}
