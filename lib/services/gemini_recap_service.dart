import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiRecapService {
  final String apiKey;

  GeminiRecapService({required this.apiKey});

  /// Analyzes the video/audio and writes an expressive Khmer movie recap script.
  /// [mediaPath]: File path to either extracted audio (.mp3/.aac) or compressed video (.mp4).
  /// [videoDurationSeconds]: Total duration of the video in seconds.
  /// [mimeType]: MIME type of media (e.g., 'audio/mp3', 'video/mp4').
  Future<String> generateKhmerRecapScript({
    required String mediaPath,
    required double videoDurationSeconds,
    String mimeType = 'audio/mp3',
    String? tonePreference,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('សូមកំណត់ Gemini API Key នៅក្នុងទំព័រ Settings ជាមុនសិន! (Gemini API Key is required)');
    }

    final file = File(mediaPath);
    if (!await file.exists()) {
      throw Exception('រកមិនឃើញឯកសារមេឌៀសម្រាប់វិភាគឡើយ: $mediaPath');
    }

    final bytes = await file.readAsBytes();

    final candidateModels = [
      'gemini-2.0-flash',
      'gemini-2.0-flash-lite',
      'gemini-1.5-flash',
      'gemini-1.5-flash-8b',
    ];

    final durationMinutes = (videoDurationSeconds / 60).toStringAsFixed(1);

    final promptText = '''
អ្នកគឺជាអ្នកសម្រាយរឿងភាពយន្តអាជីព (Professional Movie Recap Narrator) ដ៏ល្បីប្រចាំប្រទេសកម្ពុជា។
ចូរវិភាគសំឡេង និងទិដ្ឋភាពនៃវីដេអូរឿងកុននេះ (ដែលជាភាសាចិន ឬភាសាដើម) ហើយសរសេរអត្ថបទសម្រាយរឿងជាភាសាខ្មែរសុទ្ធសាធ (Khmer Movie Recap Narration Script)។

🎯 លក្ខខណ្ឌតឹងរ៉ឹងនៃការសរសេរសម្រាយរឿង៖
1. **រចនាប័ទ្មសំឡេង និងភាសា (Tone & Flow)**:
   - ត្រូវសរសេរបែប "សម្រាយរឿងកុន មិនរឹង មិនកកស្ទះ" (រអិល ជក់ចិត្ត រំភើប បង្កប់ការលេងសើច ឬតានតឹងតាមសាច់រឿង)។
   - ប្រើពាក្យពេចន៍ទាក់ទាញ ដូចជាអ្នកសម្រាយរឿងកំពូលៗលើ TikTok និង YouTube (ឧទាហរណ៍៖ "សូមស្វាគមន៍មកកាន់ការសម្រាយរឿង...", "កាលពីដើមឡើយ...", "ស្រាប់តែពេលនោះ...", "រឿងរ៉ាវកាន់តែរន្ធត់នៅពេលដែល...")។
   - ហាមប្រើពាក្យបកប្រែពាក្យទល់ពាក្យ (Literal Translation) ដែលធ្វើឲ្យឆ្គង ឬស្តាប់ទៅដូចម៉ាស៊ីន។

2. **ការបែងចែកសំឡេងតួអង្គ (Male & Female Dialogue Voice Switching)**:
   - នៅពេលមានការសន្ទនាក្នុងរឿង ឬអ្នករៀបរាប់និយាយ ត្រូវដាក់ស្លាក (Tag) នៅដើមបន្ទាត់នីមួយៗឲ្យច្បាស់៖
     * ប្រើ `[ប្រុស]: ` សម្រាប់អ្នករៀបរាប់ (Narrator) និងតួអង្គប្រុសនិយាយ។
     * ប្រើ `[ស្រី]: ` សម្រាប់តួអង្គស្រីនិយាយ។
   - ឧទាហរណ៍៖
     [ប្រុស]: កាលពីដើមឡើយ នៅភូមិតូចមួយមានបុរសម្នាក់...
     [ស្រី]: បងកុំទៅចោលខ្ញុំអី ទីនោះគ្រោះថ្នាក់ណាស់!
     [ប្រុស]: ឮដូច្នេះ បុរសនោះក៏ញញឹមហើយតបវិញថា...

3. **រយៈពេល និងចង្វាក់ (Pacing & Duration)**:
   - វីដេអូនេះមានប្រវែងប្រហែល $durationMinutes នាទី ($videoDurationSeconds វិនាទី)។
   - ចំនួនពាក្យ និងប្រយោគត្រូវតែល្មមសមរម្យសម្រាប់អានក្នុងរយៈពេលនេះ (ល្បឿនអានជាមធ្យម ១២០-១៤០ ពាក្យក្នុងមួយនាទី)។

4. **ទម្រង់លទ្ធផល (Output Format)**:
   - ផ្ដល់ត្រឹមតែអត្ថបទសំឡេងសម្រាយជាភាសាខ្មែរ ដោយមានស្លាក [ប្រុស]: ឬ [ស្រី]: នៅដើមបន្ទាត់។
   - កុំដាក់ចំណងជើង "Intro:", "Scene 1:" ឬ Markdown Headers ដូចជា ###, **, () ព្រោះអត្ថបទនេះនឹងត្រូវបញ្ជូនទៅម៉ាស៊ីនអានសំឡេង Khmer TTS ផ្ទាល់។
''';

    final content = [
      Content.multi([
        TextPart(promptText),
        DataPart(mimeType, bytes),
      ]),
    ];

    String script = '';
    Exception? lastException;

    for (final modelName in candidateModels) {
      try {
        final model = GenerativeModel(
          model: modelName,
          apiKey: apiKey,
          generationConfig: GenerationConfig(
            temperature: 0.75,
            topP: 0.95,
            maxOutputTokens: 4096,
          ),
        );

        final response = await model.generateContent(content);
        final text = response.text?.trim() ?? '';
        if (text.isNotEmpty) {
          script = text;
          break;
        }
      } catch (e) {
        lastException = Exception(e.toString());
        continue;
      }
    }

    if (script.isEmpty) {
      throw lastException ?? Exception('Gemini មិនអាចបង្កើតអត្ថបទសម្រាយរឿងបានទេ។ សូមពិនិត្យ API Key ឬសាកល្បងម្ដងទៀត។');
    }

    // Clean up any remaining formatting tags while preserving [ប្រុស]: and [ស្រី]:
    return _sanitizeScriptForTts(script);
  }

  /// Removes markdown symbols, while preserving [ប្រុស]: and [ស្រី]: speaker indicators
  String _sanitizeScriptForTts(String rawText) {
    var cleaned = rawText
        .replaceAll(RegExp(r'\[(?!(ប្រុស|ស្រី)\]).*?\]'), '') // remove brackets except [ប្រុស] / [ស្រី]
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .replaceAll(RegExp(r'[*#_~`]'), '')
        .replaceAll(RegExp(r'^(Intro|Scene \d+|Outro|Hook):\s*', multiLine: true), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return cleaned;
  }
}
