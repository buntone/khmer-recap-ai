import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:khmer_recap_ai/services/khmer_tts_service.dart';
import 'package:khmer_recap_ai/services/ffmpeg_service.dart';

void main() {
  test('KhmerVoice.prasith mode guarantees 100% male voice for all dialogue',
      () {
    final tts = KhmerTtsService(
      endpoint: '',
      apiToken: '',
      prasithVoiceId: 'male_prasith',
      sreymomVoiceId: 'female_sreymom',
    );

    const script = '''
[00:01] [ប្រុស]: សម្រាយសាច់រឿង៖ បីឆ្នាំមុន នាងត្រូវបានគេបណ្តេញចេញពីត្រកូល។
[00:06] [ស្រី]: (ក្នុងចិត្ត) ថ្ងៃនេះខ្ញុំត្រលប់មកវិញ ដើម្បីទាមទារភាពយុត្តិធម៌!
[00:11] [ស្រី]: កូន! ម៉ែមកដើម្បីយករបស់របរឱ្យកូនវិញ។
[00:16] [ប្រុស]: ម៉ែ! កូនជាប់រវល់ការងារនៅទីនេះ។
''';

    final segments =
        tts.parseDialogueSegmentsForTesting(script, KhmerVoice.prasith);
    expect(segments.length, 4);
    for (final seg in segments) {
      expect(seg.voiceId, 'male_prasith',
          reason: 'All lines must use male voice in KhmerVoice.prasith mode');
    }
  });

  test(
      'AutoDialogue mode accurately matches male and female voices for both speech and inner thoughts',
      () {
    final tts = KhmerTtsService(
      endpoint: '',
      apiToken: '',
      prasithVoiceId: 'male_prasith',
      sreymomVoiceId: 'female_sreymom',
    );

    const script = '''
[00:01] [ប្រុស]: សម្រាយសាច់រឿង៖ បីឆ្នាំមុន នាងត្រូវបានគេបណ្តេញចេញពីត្រកូល។
[00:06] [ស្រី]: (ក្នុងចិត្ត) ថ្ងៃនេះខ្ញុំត្រលប់មកវិញ ដើម្បីទាមទារភាពយុត្តិធម៌!
[00:11] [ស្រី]: កូន! ម៉ែមកដើម្បីយករបស់របរឱ្យកូនវិញ។
[00:16] [ប្រុស]: (ក្នុងចិត្ត) ហេតុអ្វីបានជាម៉ែមកទីនេះនៅពេលនេះ?
[00:20] [ប្រុស]: ម៉ែ! កូនជាប់រវល់ការងារនៅទីនេះ។
''';

    final segments =
        tts.parseDialogueSegmentsForTesting(script, KhmerVoice.autoDialogue);
    expect(segments.length, 5);
    // Line 1: Intro recap narration -> Male and "សម្រាយសាច់រឿង" is stripped cleanly
    expect(segments[0].voiceId, 'male_prasith');
    expect(segments[0].text, 'បីឆ្នាំមុន នាងត្រូវបានគេបណ្តេញចេញពីត្រកូល។');
    // Line 2: Female thinking in her mind -> Female
    expect(segments[1].voiceId, 'female_sreymom');
    // Line 3: Female speaking out loud -> Female
    expect(segments[2].voiceId, 'female_sreymom');
    // Line 4: Male thinking in his mind -> Male
    expect(segments[3].voiceId, 'male_prasith');
    // Line 5: Male speaking out loud -> Male
    expect(segments[4].voiceId, 'male_prasith');
  });

  testWidgets(
      'createWatermarkImage generates a valid PNG file with shadow text',
      (tester) async {
    await tester.runAsync(() async {
      final ffmpeg = FFmpegService();
      final tempDir = Directory.systemTemp;
      final outPath =
          '${tempDir.path}/test_watermark_${DateTime.now().millisecondsSinceEpoch}.png';

      final resultPath = await ffmpeg.createWatermarkImage(
        text: 'ដោយ.B.T.movie',
        outputPath: outPath,
      );

      final file = File(resultPath);
      expect(await file.exists(), isTrue);
      final bytes = await file.readAsBytes();
      expect(bytes.length, greaterThan(100));
      // PNG magic bytes header: 0x89, 0x50, 0x4E, 0x47
      expect(bytes[0], 0x89);
      expect(bytes[1], 0x50);
      expect(bytes[2], 0x4E);
      expect(bytes[3], 0x47);

      // Clean up
      try {
        await file.delete();
      } catch (_) {}
    });
  });
}
