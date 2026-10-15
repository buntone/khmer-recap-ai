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
      final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$cleanKey');
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
      throw Exception('សូមកំណត់ Gemini API Key យ៉ាងហោចណាស់ ១ នៅក្នុង Settings ជាមុនសិន!');
    }

    final file = File(mediaPath);
    if (!await file.exists()) {
      throw Exception('រកមិនឃើញឯកសារមេឌៀសម្រាប់វិភាគឡើយ: $mediaPath');
    }

    final bytes = await file.readAsBytes();

    final durationMinutes = (videoDurationSeconds ~/ 60).toString().padLeft(2, '0');
    final durationSecs = (videoDurationSeconds.toInt() % 60).toString().padLeft(2, '0');
    final durationFormatted = '$durationMinutes:$durationSecs';

    final promptText = '''
អ្នកគឺជាអ្នកជំនាញបកប្រែ និងបញ្ចូលសំឡេងភាពយន្តចិន-ខ្មែរអាជីព (Professional Chinese-to-Khmer Movie Dubbing Specialist)។
ភារកិច្ចចម្បងរបស់អ្នក៖
១. **ពិនិត្យមើលវីដេអូ អានអក្សររត់ពីក្រោម (Subtitles) ភាសាចិនលើផ្ទាំងរូបភាព និងស្ដាប់ការសន្ទនារបស់តួអង្គឱ្យបានច្បាស់លាស់ ១០០%**។
២. **បកប្រែសាច់រឿង និងការសន្ទនាជាភាសាខ្មែរ ដោយកត់ត្រាពេលវេលា [MM:SS] ឱ្យចំពេលដែលតួអង្គនិយាយ ឬពេលឈុតឆាកកើតឡើងជាក់ស្ដែង**។

🎥 ព័ត៌មានវីដេអូ៖
- រយៈពេលវីដេអូសរុប៖ $durationFormatted (${videoDurationSeconds.toStringAsFixed(1)} វិនាទី)

🎯 គោលការណ៍កំណត់ពេលវេលា និងបកប្រែ (CRITICAL RULES):
១. **ចំនួនបន្ទាត់ និងប្រវែងប្រយោគខ្លីល្មមសមរម្យ (Concise Dialogue - 5 to 10 Lines per minute)**:
   - ត្រូវបកប្រែជាប្រយោគខ្លីល្មម ធម្មជាតិ ស្ដាប់ទៅពីរោះរអិល ដូចអ្នកបញ្ចូលសំឡេងរឿងកុនអាជីព។
   - ហាមដាច់ខាតកុំសរសេរប្រយោគវែងអូសបន្លាយជ្រុល! ត្រូវសរសេរខ្លីល្មមឱ្យសមស្របតាមរយៈពេលនៃឈុតឆាក ដើម្បីឱ្យសំឡេងអានបញ្ចប់ទាន់ពេលវេលា មុនពេលតួអង្គបន្ទាប់និយាយ។
   - បើសិនជាតួអង្គម្នាក់និយាយ ២-៣ ឃ្លាក្នុងឈុតតែមួយ ត្រូវសរសេរចូលគ្នាក្នុងបន្ទាត់តែមួយ។

២. **ពេលវេលា [MM:SS] ត្រឹមត្រូវតាមនាទីវិនាទីជាក់ស្ដែង (Accurate Scene Timestamps)**:
   - ត្រូវកត់ត្រា [MM:SS] ឬ [MM:SS - MM:SS] ឱ្យចំពេលដែលតួអង្គចាប់ផ្ដើមនិយាយពិតប្រាកដ។
   - បើនៅដើមវីដេអូ (ឧទាហរណ៍ ០ ដល់ ៤ វិនាទី) មានភ្លេង ឬតួអង្គមិនទាន់និយាយទេ ហាមដាច់ខាតកុំដាក់ [00:00]! ត្រូវដាក់ពេលវេលាដែលតួអង្គចាប់ផ្ដើមនិយាយជាក់ស្ដែង (ឧទាហរណ៍៖ [00:04])។
   - ពេលណាដែលគ្មានការនិយាយ (ចន្លោះស្ងាត់ ឬភ្លេង) មិនត្រូវដាក់អត្ថបទឡើយ ដើម្បីកុំឱ្យសំឡេងនិយាយមុនសាច់រឿង។

៣. **ហៅឈ្មោះ និងសព្វនាមញាតិមិត្តឱ្យចំៗ (STRICT KINSHIP & FAMILY ADDRESSING - ហៅឈ្មោះ ពុកម៉ែ មាមីង យាយតា បងប្អូន ឱ្យចំៗ)**:
   - ត្រូវបកប្រែពាក្យហៅញាតិសន្តានចិនឱ្យចេញជាពាក្យខ្មែរចំៗ និងត្រឹមត្រូវ ១០០% តាមសាច់រឿង ហាមកាត់ចោល ឬប្រើពាក្យទូទៅ (ដូចជា "អ្នក", "នាង", "គាត់"):
     * ឪពុក/ម្តាយ (爸/妈/父亲/母亲/爹/娘): ត្រូវហៅ "ពុក", "ម៉ែ", "ប៉ា", "ម៉ាក់", "ឪពុក", ឬ "ម្ដាយ" ឱ្យចំៗ!
     * ជីដូន/ជីតា (爷爷/奶奶/外公/外婆/姥姥/姥爷): ត្រូវហៅ "លោកតា", "លោកយាយ", "តា", ឬ "យាយ" ឱ្យចំៗ!
     * ពូមីង/អ៊ំ/មាមីង (叔叔/阿姨/舅舅/姑姑/婶婶/伯父/伯母): ត្រូវហៅ "ពូ", "មីង", "មាមីង", ឬ "អ៊ំ" ឱ្យចំៗ!
     * បងប្អូន/ប្ដីប្រពន្ធ (哥/姐/弟/妹/老公/老婆): ត្រូវហៅ "បង", "ប្អូន", "បងប្រុស", "បងស្រី", "ប្អូនប្រុស", "ប្អូនស្រី", "ប្តី", "ប្រពន្ធ" ឱ្យចំៗ!
     * កូន/ចៅ (儿子/女儿/孩子/孙子/孙女/外孙): ត្រូវហៅ "កូន", "កូនប្រុស", "កូនស្រី", ឬ "ចៅ" ឱ្យចំៗ!
   - ពេលតួអង្គនិយាយឆ្លើយឆ្លងគ្នា ត្រូវរក្សាសព្វនាមគោរព និងស្និទ្ធស្នាលតាមទំនាក់ទំនងគ្រួសារជាក់ស្តែងជានិច្ច!

៤. **កំណត់ភេទតួអង្គ (STRICT TAGS - ONLY USE [ប្រុស]: OR [ស្រី]:)**:
   - ត្រូវពិនិត្យមើលរូបភាពតួអង្គដែលកំពុងកម្រើកមាត់និយាយ ឬស្ដាប់សំនៀងសំឡេងឱ្យច្បាស់លាស់បំផុត៖
   - ហាមដាច់ខាតកុំប្រើពាក្យ [ស្រីចាស់]:, [ប្រុសចាស់]:, [យាយ]:, [តា]:, [ម៉ាក់]:, [កូន]: ឬឈ្មោះតួអង្គផ្សេងៗនៅពីមុខឃ្លា!
   - ត្រូវប្រើតែ ២ ម៉ាត់នេះគត់នៅពីមុខឃ្លានីមួយៗ៖
     * [ប្រុស]: សម្រាប់តួអង្គប្រុស ឬមនុស្សប្រុសនិយាយ
     * [ស្រី]: សម្រាប់តួអង្គស្រី ឬមនុស្សស្រីនិយាយ
   - ហាមដាច់ខាតកុំច្រឡំភេទតួអង្គ ជាពិសេសនៅចុងវីដេអូ ត្រូវមើលឱ្យច្បាស់ថាតួអង្គប្រុស ឬតួអង្គស្រីជាអ្នកនិយាយ។

៥. **ទម្រង់លទ្ធផល (STRICT PLAIN TEXT OUTPUT - NO JSON, NO MARKDOWN CODE BLOCKS)**:
សូមសរសេរចេញមកជាបន្ទាត់ៗផ្ទាល់ ដោយមិនប្រើ JSON ឬ Markdown code block ឡើយ៖
[00:04] [ប្រុស]: ពុកម៉ែ! ហេតុអ្វីបានជាពុកម៉ែមកទីនេះ?
[00:11] [ស្រី]: កូន! ម៉ែមកដើម្បីយករបស់របរឱ្យកូនវិញ។
[00:19] [ប្រុស]: លោកយាយលោកតា និងមាមីងទាំងអស់គ្នា ក៏បារម្ភពីកូនដែរ!
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
      throw Exception('មិនអាចចាប់សំឡេងសន្ទនាភាសាចិនក្នុងវីដេអូដើម្បីបកប្រែបានឡើយ។');
    }

    return _parseScriptFromResponse(rawScript);
  }

  /// Parses response into formatted script lines [MM:SS] [ប្រុស]: Text
  String _parseScriptFromResponse(String rawResponse) {
    // 1. If response is wrapped in JSON, extract dialogue items cleanly
    final trimmed = rawResponse.trim();
    if (trimmed.startsWith('{') || trimmed.startsWith('[') || trimmed.contains('"speaker":') || trimmed.contains('"text":')) {
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
              final rawTime = item['time'] ?? item['timestamp'] ?? item['start_time'] ?? item['start'];
              final time = _formatTimestamp(rawTime);

              String speaker = (item['speaker'] ?? item['gender'] ?? 'ប្រុស').toString().trim();
              final isFemale = speaker.toLowerCase().contains('female') ||
                  speaker.toLowerCase().contains('ស្រី') ||
                  speaker.toLowerCase().contains('woman') ||
                  speaker == 'F';
              final speakerTag = isFemale ? '[ស្រី]:' : '[ប្រុស]:';

              String text = (item['text'] ?? item['khmer'] ?? item['dialogue'] ?? '').toString().trim();
              if (text.isNotEmpty && RegExp(r'[\u1780-\u17FF]').hasMatch(text)) {
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
    var s = rawTime.toString().trim().replaceAll('[', '').replaceAll(']', '').replaceAll('(', '').replaceAll(')', '');
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
      final sec = int.tryParse(parts[1].split('.').first)?.toString().padLeft(2, '0') ?? '00';
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
      r'\[?\(?(\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d+)?)(?:\s*(?:-->|[-–])\s*(\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d+)?))?\)?\]?'
    );

    String? pendingTimeTag;
    bool hasSeenFirstTimestamp = false;

    for (final line in lines) {
      var trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (RegExp(r'^\d+$').hasMatch(trimmed)) continue; // Skip SRT block number lines

      // Skip lines that are purely code or JSON symbols
      if (trimmed == '{' || trimmed == '}' || trimmed == '[' || trimmed == ']' || trimmed == '},') continue;
      if (RegExp(r'^"(?:time|speaker|gender|text|dialogue|segments)":', caseSensitive: false).hasMatch(trimmed)) {
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

      // Strip conversational preamble headers before first timestamp
      if (!hasSeenFirstTimestamp && hasKhmer && tMatch == null) {
        if (trimmed.contains('ការបកប្រែ') ||
            trimmed.contains('ខាងក្រោមនេះ') ||
            trimmed.contains('សាច់រឿង') ||
            trimmed.contains('បញ្ចូលសំឡេង') ||
            trimmed.contains('Timestamp') ||
            trimmed.endsWith('៖') ||
            trimmed.endsWith(':')) {
          continue;
        }
      }

      if (!hasKhmer) continue;

      var lineText = trimmed.replaceAll(timePattern, '').trim();

      bool isFemale = false;
      // 1. Match any bracketed tag at the start e.g. [ស្រីចាស់], [ប្រុសចាស់], [ស្រី], [ប្រុស], [F], [M], [យាយ], [ម៉ាក់]
      final bracketMatch = RegExp(r'^\s*\[([^\]]+)\]\s*[:៖\-–\s]*').firstMatch(lineText);
      if (bracketMatch != null) {
        final tagContent = bracketMatch.group(1)!.trim();
        if (RegExp(r'(?:ស្រី|នារី|ស្ត្រី|ម្ដាយ|ម៉ាក់|យាយ|female|woman|girl|\bF\b)', caseSensitive: false).hasMatch(tagContent)) {
          isFemale = true;
        } else if (RegExp(r'(?:ប្រុស|បុរស|ឪពុក|ប៉ា|តា|អ្នករៀបរាប់|male|man|boy|narrator|\bM\b)', caseSensitive: false).hasMatch(tagContent)) {
          isFemale = false;
        }
        lineText = lineText.replaceFirst(RegExp(r'^\s*\[([^\]]+)\]\s*[:៖\-–\s]*'), '');
      } else {
        // 2. Match unbracketed tag at start e.g. ស្រីចាស់: or ប្រុស: or F:
        final plainMatch = RegExp(r'^\s*([^\s:៖\-–]{1,12})\s*[:៖\-–\s]+').firstMatch(lineText);
        if (plainMatch != null) {
          final tagContent = plainMatch.group(1)!.trim();
          if (RegExp(r'(?:ស្រី|នារី|ស្ត្រី|ម្ដាយ|ម៉ាក់|យាយ|female|woman|girl|^F$)', caseSensitive: false).hasMatch(tagContent)) {
            isFemale = true;
            lineText = lineText.replaceFirst(RegExp(r'^\s*([^\s:៖\-–]{1,12})\s*[:៖\-–\s]+'), '');
          } else if (RegExp(r'(?:ប្រុស|បុរស|ឪពុក|ប៉ា|តា|អ្នករៀបរាប់|male|man|boy|narrator|^M$)', caseSensitive: false).hasMatch(tagContent)) {
            isFemale = false;
            lineText = lineText.replaceFirst(RegExp(r'^\s*([^\s:៖\-–]{1,12})\s*[:៖\-–\s]+'), '');
          }
        }
      }

      final speakerTag = isFemale ? '[ស្រី]:' : '[ប្រុស]:';

      var clean = lineText
          .replaceAll(RegExp(r'["{}\[\]]'), '')
          .replaceAll(RegExp(r'^[:៖\-–\s]+'), '')
          .trim();

      if (clean.isNotEmpty && RegExp(r'[\u1780-\u17FF]').hasMatch(clean)) {
        final timeTag = pendingTimeTag ?? '[00:00]';
        pendingTimeTag = null;
        buffer.writeln('$timeTag $speakerTag $clean');
      }
    }

    final result = buffer.toString().trim();
    if (result.isNotEmpty) return result;

    return rawText
        .replaceAll(RegExp(r'["{}\[\]]'), '')
        .trim();
  }
}
