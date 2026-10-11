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

    // Use Gemini 1.5 Flash for ultra-fast, high-capacity multimodal video/audio comprehension
    final model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.75,
        topP: 0.95,
        maxOutputTokens: 4096,
      ),
    );

    final durationMinutes = (videoDurationSeconds / 60).toStringAsFixed(1);

    final promptText = '''
អ្នកគឺជាអ្នកសម្រាយរឿងភាពយន្តអាជីព (Professional Movie Recap Narrator) ដ៏ល្បីប្រចាំប្រទេសកម្ពុជា។
ចូរវិភាគសំឡេង និងទិដ្ឋភាពនៃវីដេអូរឿងកុននេះ (ដែលជាភាសាចិន ឬភាសាដើម) ហើយសរសេរអត្ថបទសម្រាយរឿងជាភាសាខ្មែរសុទ្ធសាធ (Khmer Movie Recap Narration Script)។

🎯 លក្ខខណ្ឌតឹងរ៉ឹងនៃការសរសេរសម្រាយរឿង៖
1. **រចនាប័ទ្មសំឡេង និងភាសា (Tone & Flow)**:
   - ត្រូវសរសេរបែប "សម្រាយរឿងកុន មិនរឹង មិនកកស្ទះ" (រអិល ជក់ចិត្ត រំភើប បង្កប់ការលេងសើច ឬតានតឹងតាមសាច់រឿង)។
   - ប្រើពាក្យពេចន៍ទាក់ទាញ ដូចជាអ្នកសម្រាយរឿងកំពូលៗលើ TikTok និង YouTube (ឧទាហរណ៍៖ "សូមស្វាគមន៍មកកាន់ការសម្រាយរឿង...", "កាលពីដើមឡើយ...", "ស្រាប់តែពេលនោះ...", "រឿងរ៉ាវកាន់តែរន្ធត់នៅពេលដែល...")។
   - ហាមប្រើពាក្យបកប្រែពាក្យទល់ពាក្យ (Literal Translation) ដែលធ្វើឲ្យឆ្គង ឬស្តាប់ទៅដូចម៉ាស៊ីន។

2. **រយៈពេល និងចង្វាក់ (Pacing & Duration)**:
   - វីដេអូនេះមានប្រវែងប្រហែល $durationMinutes នាទី ($videoDurationSeconds វិនាទី)។
   - ចំនួនពាក្យ និងប្រយោគត្រូវតែល្មមសមរម្យសម្រាប់អានក្នុងរយៈពេលនេះ (ល្បឿនអានជាមធ្យម ១២០-១៤០ ពាក្យក្នុងមួយនាទី)។

3. **រចនាសម្ព័ន្ធអត្ថបទ (Structure)**:
   - ផ្ដើមរឿងទាក់ទាញ (Hooking Intro)
   - សាច់រឿងចម្បង និងចំណុចកំពូល (Climax & Conflicts)
   - បញ្ចប់រឿងដោយគំនិតអប់រំ ឬសំណួរបើកចំហ (Ending & Wrap-up)

4. **ទម្រង់លទ្ធផល (Output Format)**:
   - ផ្ដល់ត្រឹមតែអត្ថបទសំឡេងសម្រាយ (Narration text) សុទ្ធសាធជាភាសាខ្មែរ។
   - កុំដាក់ចំណងជើង "Intro:", "Scene 1:" ឬ Markdown Headers ដូចជា ###, **, [], () ព្រោះអត្ថបទនេះនឹងត្រូវបញ្ជូនទៅម៉ាស៊ីនអានសំឡេង Khmer TTS ផ្ទាល់។
''';

    final content = [
      Content.multi([
        TextPart(promptText),
        DataPart(mimeType, bytes),
      ]),
    ];

    final response = await model.generateContent(content);
    final script = response.text?.trim() ?? '';

    if (script.isEmpty) {
      throw Exception('Gemini មិនអាចបង្កើតអត្ថបទសម្រាយរឿងបានទេ។ សូមសាកល្បងម្ដងទៀត។');
    }

    // Clean up any remaining formatting tags so TTS reads cleanly
    return _sanitizeScriptForTts(script);
  }

  /// Removes timestamps, brackets, stage directions like [សើច], and markdown symbols
  String _sanitizeScriptForTts(String rawText) {
    var cleaned = rawText
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .replaceAll(RegExp(r'[*#_~`]'), '')
        .replaceAll(RegExp(r'^(Intro|Scene \d+|Outro|Hook|Narrator):\s*', multiLine: true), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return cleaned;
  }
}
