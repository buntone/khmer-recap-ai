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
២. **បកប្រែសាច់រឿង ការសម្រាយរឿង និងការសន្ទនាជាភាសាខ្មែរ ដោយកត់ត្រាពេលវេលា [MM:SS] ឱ្យចំពេលដែលឈុតឆាកកើតឡើងជាក់ស្ដែង**។

🎥 ព័ត៌មានវីដេអូ៖
- រយៈពេលវីដេអូសរុប៖ $durationFormatted (${videoDurationSeconds.toStringAsFixed(1)} វិនាទី)

🎯 គោលការណ៍កំណត់ពេលវេលា និងបកប្រែ (CRITICAL RULES - STRICT ANTI-OVERLAP & RECAP DUBBING):

១. **រៀបរាប់ដំណើររឿងនៅដើមវីដេអូ (STORY INTRO / RECAP NARRATION)**:
   - វីដេអូភាពយន្តជាច្រើនតែងតែមានការរៀបរាប់ដំណើររឿងនៅដើមវីដេអូ (Intro Voiceover) ដើម្បីពន្យល់ពីដើមហេតុ ឬសាច់រឿងសង្ខេប។
   - **ត្រូវតែបកប្រែ និងចាប់ផ្ដើមអានតាំងពីដើមវីដេអូ [00:01] មកភ្លាម! ហាមដាច់ខាតកុំទុកឱ្យស្ងាត់!**
   - **ហាមដាច់ខាតកុំនិយាយ ឬសរសេរពាក្យថា "សម្រាយរឿង" ឬ "សម្រាយសាច់រឿង" ឬ "អ្នកសម្រាយ" នៅដើមវីដេអូ ឬក្នុងប្រយោគឡើយ!** ត្រូវចូលរៀបរាប់ដំណើររឿងផ្ទាល់តែម្ដង ហាមនិយាយពាក្យថា សម្រាយរឿង!
   - ប្រើស្លាក [ប្រុស]: សម្រាប់អ្នករៀបរាប់ដំណើររឿង (ឧទាហរណ៍៖ [00:01] [ប្រុស]: បីឆ្នាំមុន នាងត្រូវបានគេបណ្តេញចេញពីត្រកូលយ៉ាងអយុត្តិធម៌។)

២. **មនុស្សនិយាយក្នុងចិត្ត / គិតក្នុងចិត្ត (INNER MONOLOGUE / CHARACTER THOUGHTS - ត្រូវតែចាប់ភេទឱ្យចំ ១០០%)**:
   - ក្នុងឈុតឆាកភាពយន្តមួយចំនួន តួអង្គមិនកម្រើកមាត់ទេ ប៉ុន្តែគាត់កំពុង**និយាយក្នុងចិត្ត គិតក្នុងចិត្ត ឬមានពាក្យសារក្នុងចិត្ត** (ឧទាហរណ៍៖ អក្សររត់ចិនដាក់ក្នុងវង់ក្រចក (内心/心想/独白) ឬមានសំឡេងបន្លឺឡើងក្នុងចិត្តរបស់តួអង្គ)។
   - **ត្រូវតែបកប្រែពាក្យក្នុងចិត្តនេះ និងកំណត់ Timestamp [MM:SS] ឱ្យអានសំឡេងខ្មែរចេញមក ហាមដាច់ខាតកុំកាត់ចោល!**
   - **សំខាន់បំផុត៖ ត្រូវកំណត់ភេទឱ្យចំថាអ្នកណាជាអ្នកគិតក្នុងចិត្ត៖**
     * **បើសិនជាតួប្រុសគិតក្នុងចិត្ត** ត្រូវតែដាក់ស្លាក **[ប្រុស]: (ក្នុងចិត្ត) ...** (ដើម្បីឱ្យចេញសំឡេងប្រុស)
     * **បើសិនជាតួស្រីគិតក្នុងចិត្ត** ត្រូវតែដាក់ស្លាក **[ស្រី]: (ក្នុងចិត្ត) ...** (ដើម្បីឱ្យចេញសំឡេងស្រី)

៣. **១ បន្ទាត់ សម្រាប់តួអង្គតែ ១ នាក់គត់ (STRICT SINGLE SPEAKER PER LINE)**:
   - ហាមដាច់ខាតកុំដាក់ [ប្រុស] និង [ស្រី] ក្នុងបន្ទាត់តែមួយ!
   - បើសិនជាតួប្រុស និងតួស្រីនិយាយឆ្លើយឆ្លងគ្នា ត្រូវចុះបន្ទាត់ថ្មីដាច់ដោយឡែកពីគ្នាជានិច្ច ជាមួយ Timestamp រៀងៗខ្លួន។

៤. **ប្រយោគខ្លីខ្លឹមល្មមសមស្របតាមវិនាទី (ULTRA-CONCISE DIALOGUE - ហាមសរសេរវែងអូសបន្លាយ)**:
   - ក្នុង ១ វិនាទី សំឡេងអានបានប្រហែល ៣ ទៅ ៤ ម៉ាត់ប៉ុណ្ណោះ។ បើសិនជាឈុតឆាកមានត្រឹមតែ ៣ វិនាទី ត្រូវបកប្រែប្រយោគខ្លីល្មមត្រឹម ៧ ទៅ ១០ ម៉ាត់ប៉ុណ្ណោះ!
   - ហាមដាច់ខាតកុំសរសេរប្រយោគវែងៗអូសបន្លាយ! ត្រូវតែសរសេរឱ្យខ្លីល្មម ដើម្បីឱ្យសំឡេងអានចប់ទាន់ពេលវេលា មុនពេលតួអង្គបន្ទាប់ចាប់ផ្ដើមនិយាយ។
   - មិនត្រូវបន្ថែមពាក្យពន្យល់វែងអន្លាយដែលគ្មានក្នុងសាច់រឿងឡើយ។

៥. **ពេលវេលា [MM:SS] ត្រឹមត្រូវតាមនាទីវិនាទីជាក់ស្ដែង (Accurate Scene Timestamps)**:
   - ត្រូវកត់ត្រា [MM:SS] ឱ្យចំពេលដែលតួអង្គចាប់ផ្ដើមនិយាយ ឬពេលសម្រាយសាច់រឿងចាប់ផ្ដើម។
   - បើនៅដើមវីដេអូមានសម្រាយសាច់រឿង ឬការគិតក្នុងចិត្ត ត្រូវដាក់ [00:01] ភ្លាម ដើម្បីឱ្យមានសំឡេងនិយាយតាំងពីដើមវីដេអូ។
   - រវាងបន្ទាត់មួយទៅបន្ទាត់មួយ ត្រូវទុកចន្លោះយ៉ាងតិច ២ ទៅ ៣ វិនាទី (ហាមដាក់ Timestamp ជិតគ្នាពេក ដូចជា [00:04] និង [00:05])។

៦. **ហៅឈ្មោះ និងសព្វនាមញាតិមិត្តឱ្យចំៗ (STRICT KINSHIP & FAMILY ADDRESSING)**:
   - ត្រូវបកប្រែពាក្យហៅញាតិសន្តានចិនឱ្យចេញជាពាក្យខ្មែរចំៗ និងត្រឹមត្រូវ ១០០% តាមសាច់រឿង៖ ពុក, ម៉ែ, ប៉ា, ម៉ាក់, លោកតា, លោកយាយ, ពូ, មីង, បង, ប្អូន, ប្ដី, ប្រពន្ធ, កូន, ចៅ ឱ្យចំៗ!

៧. **កំណត់ស្លាកសំឡេងស្វ័យប្រវត្តិតាមភេទតួអង្គ (STRICT AUTO-GENDER SPEAKER TAGS)**:
   - **រាល់បន្ទាត់ទាំងអស់ ដាច់ខាតត្រូវតែមានស្លាក [ប្រុស]: ឬ [ស្រី]: នៅខាងមុខជានិច្ច ហាមដាច់ខាតកុំចោលបន្ទាត់ណាដោយគ្មានស្លាក!**
   - **[ប្រុស]:** សម្រាប់តួអង្គប្រុសនិយាយផ្ទាល់, តួអង្គប្រុសគិតក្នុងចិត្ត `[ប្រុស]: (ក្នុងចិត្ត)`, និងអ្នករៀបរាប់ដំណើររឿង។
   - **[ស្រី]:** សម្រាប់តួអង្គស្រីនិយាយផ្ទាល់, និងតួអង្គស្រីគិតក្នុងចិត្ត `[ស្រី]: (ក្នុងចិត្ត)`។
   - ហាមដាច់ខាតកុំច្រឡំភេទ៖ ប្រុសនិយាយត្រូវតែ [ប្រុស] ស្រីនិយាយត្រូវតែ [ស្រី] ប្រុសគិតត្រូវតែ [ប្រុស] ស្រីគិតត្រូវតែ [ស្រី]។

៨. **ទម្រង់លទ្ធផល (STRICT PLAIN TEXT OUTPUT - NO JSON, NO MARKDOWN CODE BLOCKS)**:
សូមសរសេរចេញមកជាបន្ទាត់ៗផ្ទាល់ ដោយមិនប្រើ JSON ឬ Markdown code block ឡើយ៖
[00:01] [ប្រុស]: បីឆ្នាំមុន នាងត្រូវបានគេបណ្តេញចេញពីត្រកូលយ៉ាងអយុត្តិធម៌។
[00:06] [ស្រី]: (ក្នុងចិត្ត) ថ្ងៃនេះខ្ញុំត្រលប់មកវិញ ដើម្បីទាមទារភាពយុត្តិធម៌!
[00:11] [ស្រី]: កូន! ម៉ែមកដើម្បីយករបស់របរឱ្យកូនវិញ។
[00:16] [ប្រុស]: (ក្នុងចិត្ត) ហេតុអ្វីបានជាម៉ែមកទីនេះនៅពេលនេះ?
[00:20] [ប្រុស]: ម៉ែ! កូនជាប់រវល់ការងារនៅទីនេះ។
[00:25] [ប្រុស]: ម៉ែកុំបារម្ភអី កូនដឹងខ្លួនឯងច្បាស់ហើយ!
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
              maxOutputTokens: 4096,
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
            rawScript = text;
            break;
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
        throw Exception('Gemini AI បរាជ័យក្នុងការបកប្រែ: $lastError');
      }
      throw Exception(
          'មិនអាចចាប់សំឡេងសន្ទនាភាសាចិនក្នុងវីដេអូដើម្បីបកប្រែបានឡើយ។');
    }

    return _parseScriptFromResponse(rawScript);
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

  /// Converts any time input (e.g. "00:00:02,800", "00:00:02", 4, "4", "0:04", "00:04", "00:04 - 00:08") into [MM:SS]
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
      final sec = int.tryParse(parts[2].split('.').first) ?? 0;
      return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    } else if (parts.length == 2) {
      final m = int.tryParse(parts[0])?.toString().padLeft(2, '0') ?? '00';
      final sec =
          int.tryParse(parts[1].split('.').first)?.toString().padLeft(2, '0') ??
              '00';
      return '$m:$sec';
    } else if (parts.length == 1) {
      final numSec = double.tryParse(parts[0]);
      if (numSec != null) {
        final m = (numSec ~/ 60).toString().padLeft(2, '0');
        final sec = (numSec.toInt() % 60).toString().padLeft(2, '0');
        return '$m:$sec';
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

      if (clean.isNotEmpty && RegExp(r'[\u1780-\u17FF]').hasMatch(clean)) {
        final timeTag = pendingTimeTag ?? '[00:01]';
        pendingTimeTag = null;
        buffer.writeln('$timeTag $speakerTag $clean');
      }
    }

    final result = buffer.toString().trim();
    if (result.isNotEmpty) return result;

    return rawText.replaceAll(RegExp(r'["{}\[\]]'), '').trim();
  }
}
