import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:khmer_recap_ai/models/watermark_style.dart';
import 'package:khmer_recap_ai/services/khmer_tts_service.dart';
import 'package:khmer_recap_ai/services/ffmpeg_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

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

  testWidgets(
      'createWatermarkImage renders traditional Khmer ornamental fonts and colors correctly',
      (tester) async {
    await tester.runAsync(() async {
      final ffmpeg = FFmpegService();
      final tempDir = Directory.systemTemp;

      expect(WatermarkStylePresets.fonts.length, greaterThanOrEqualTo(10));
      expect(WatermarkStylePresets.colors.length, greaterThanOrEqualTo(8));

      // Test Moul (អក្សរមូល) with gold color and 40% opacity
      final moulOutPath =
          '${tempDir.path}/test_wm_moul_${DateTime.now().millisecondsSinceEpoch}.png';
      final moulResult = await ffmpeg.createWatermarkImage(
        text: 'ដោយ.B.T.movie',
        fontName: 'Moul',
        colorName: 'gold',
        opacity: 0.40,
        outputPath: moulOutPath,
      );
      final moulFile = File(moulResult);
      expect(await moulFile.exists(), isTrue);
      expect(await moulFile.length(), greaterThan(100));

      // Test Preahvihear (អក្សរព្រះវិហារ) with cyan color
      final preahvihearOutPath =
          '${tempDir.path}/test_wm_pv_${DateTime.now().millisecondsSinceEpoch}.png';
      final pvResult = await ffmpeg.createWatermarkImage(
        text: 'សម្រាយសាច់រឿង',
        fontName: 'Preahvihear',
        colorName: 'cyan',
        opacity: 0.40,
        outputPath: preahvihearOutPath,
      );
      final pvFile = File(pvResult);
      expect(await pvFile.exists(), isTrue);
      expect(await pvFile.length(), greaterThan(100));

      // Clean up
      try {
        await moulFile.delete();
        await pvFile.delete();
      } catch (_) {}
    });
  });

  test(
      'createSubtitlesAssFile generates valid ASS subtitles formatted for 9:16',
      () async {
    final ffmpeg = FFmpegService();
    const script = '''
[00:01 - 00:04] [ប្រុស]: បីឆ្នាំមុន នាងត្រូវបានគេបណ្តេញចេញពីត្រកូល។
[00:04 - 00:07] [ស្រី]: (ក្នុងចិត្ត) ថ្ងៃនេះខ្ញុំត្រលប់មកវិញ ដើម្បីទាមទារភាពយុត្តិធម៌!
''';

    final tempDir = Directory.systemTemp;
    final outPath =
        '${tempDir.path}/test_sub_${DateTime.now().millisecondsSinceEpoch}.ass';

    final assPath = await ffmpeg.createSubtitlesAssFile(
      scriptText: script,
      videoWidth: 720,
      videoHeight: 1280,
      colorTheme: 'yellow',
      outputPath: outPath,
    );

    final file = File(assPath);
    expect(await file.exists(), isTrue);
    final content = await file.readAsString();
    expect(content.contains('[Script Info]'), isTrue);
    expect(content.contains('PlayResX: 720'), isTrue);
    expect(content.contains('PlayResY: 1280'), isTrue);
    expect(
        content.contains('Dialogue: 0,0:00:01.00,0:00:04.00,Default'), isTrue);
    expect(
        content.contains('Dialogue: 0,0:00:04.00,0:00:07.00,Default'), isTrue);
    expect(content.contains('Default,Noto Sans Khmer,'), isTrue); // Bundled Noto Sans Khmer font
    expect(content.contains('&H0000E5FF'), isTrue); // Yellow color

    try {
      await file.delete();
    } catch (_) {}
  });

  test(
      'AutoDialogue mode accurately detects fullwidth brackets, Chinese tags, and content-based female dialogue',
      () {
    final tts = KhmerTtsService(
      endpoint: '',
      apiToken: '',
      prasithVoiceId: 'male_prasith',
      sreymomVoiceId: 'female_sreymom',
    );

    const script = '''
[00:01 - 00:04] 【ស្រី】: ម៉ែមកដើម្បីយករបស់របរឱ្យកូនវិញ។
[00:04 - 00:07] **[ប្រុស]**: ម៉ែកុំបារម្ភអី កូនដឹងខ្លួនឯងច្បាស់ហើយ!
[00:07 - 00:10] (ស្រី): បងសម្លាញ់ កុំទៅចោលខ្ញុំអីណា!
[00:10 - 00:13] ម៉ាក់ប្រាប់កូនហើយ ត្រូវតែប្រយ័ត្នខ្លួន!
[00:13 - 00:16] [ប្រុស]: បាទម៉ាក់ កូនយល់ហើយ!
''';

    final segments =
        tts.parseDialogueSegmentsForTesting(script, KhmerVoice.autoDialogue);
    expect(segments.length, 5);

    // Line 1: 【ស្រី】 fullwidth bracket -> female
    expect(segments[0].voiceId, 'female_sreymom');
    // Line 2: **[ប្រុស]** markdown bold tag -> male
    expect(segments[1].voiceId, 'male_prasith');
    // Line 3: (ស្រី) parentheses + "បងសម្លាញ់" -> female
    expect(segments[2].voiceId, 'female_sreymom');
    // Line 4: Untagged "ម៉ាក់ប្រាប់កូនហើយ" -> inferred female
    expect(segments[3].voiceId, 'female_sreymom');
    // Line 5: [ប្រុស] -> male
    expect(segments[4].voiceId, 'male_prasith');
  });

  test(
      'parseDialogueSegments guarantees no timestamps or speaker tags are left in dialogue text',
      () {
    final tts = KhmerTtsService(
      endpoint: '',
      apiToken: '',
      prasithVoiceId: 'male_prasith',
      sreymomVoiceId: 'female_sreymom',
    );

    const script = '''
[00:01 - 00:04] [ប្រុស]: សួស្តីអ្នកទាំងអស់គ្នា
[00:05 - 00:09] [ស្រី]: (ក្នុងចិត្ត) ថ្ងៃនេះអាកាសធាតុល្អណាស់
''';

    final segments =
        tts.parseDialogueSegmentsForTesting(script, KhmerVoice.autoDialogue);
    expect(segments.length, 2);

    for (final seg in segments) {
      expect(seg.text.contains('['), isFalse);
      expect(seg.text.contains(']'), isFalse);
      expect(seg.text.contains(':'), isFalse);
      expect(seg.text.contains('00:'), isFalse);
      expect(seg.text.startsWith('ប្រុស'), isFalse);
      expect(seg.text.startsWith('ស្រី'), isFalse);
      expect(seg.text.contains('ក្នុងចិត្ត'), isFalse);
    }
    expect(segments[0].text, 'សួស្តីអ្នកទាំងអស់គ្នា');
    expect(segments[1].text, 'ថ្ងៃនេះអាកាសធាតុល្អណាស់');
  });

  test('Chinese dialogue without Khmer returns empty segments', () {
    final tts = KhmerTtsService(
      endpoint: '',
      apiToken: '',
      prasithVoiceId: 'male_prasith',
      sreymomVoiceId: 'female_sreymom',
    );

    const chineseScript = '''
[00:01 - 00:04] [男]: 师傅，我们去哪儿？
[00:04 - 00:07] [女]: 去机场。
''';

    final segments = tts.parseDialogueSegmentsForTesting(
        chineseScript, KhmerVoice.autoDialogue);
    expect(segments.isEmpty, isTrue);
  });

  test('Orphan timestamps and speaker tags without real dialogue are ignored', () {
    final tts = KhmerTtsService(
      endpoint: '',
      apiToken: '',
      prasithVoiceId: 'male_prasith',
      sreymomVoiceId: 'female_sreymom',
    );

    const orphanScript = '''
0001 ប្រុស
0002 ស្រី
[00:01] [ប្រុស]:
[00:04] [ស្រី]:
[00:07] [ប្រុស]: ជំរាបសួរលោកពូ ថ្ងៃនេះសុខសប្បាយទេ?
''';

    final segments = tts.parseDialogueSegmentsForTesting(
        orphanScript, KhmerVoice.autoDialogue);
    expect(segments.length, 1);
    expect(segments[0].text, 'ជំរាបសួរលោកពូ ថ្ងៃនេះសុខសប្បាយទេ?');
    expect(segments[0].voiceId, 'male_prasith');
  });

  test('Inner monologue lines are tagged isInnerMonologue and text is stripped of tags', () {
    final tts = KhmerTtsService(
      endpoint: '',
      apiToken: '',
      prasithVoiceId: 'male_prasith',
      sreymomVoiceId: 'female_sreymom',
    );

    const script = '''
[00:01 - 00:04] [ប្រុស]: បីឆ្នាំមុន នាងត្រូវបានគេបណ្តេញចេញ។
[00:04 - 00:07] [ស្រី]: (ក្នុងចិត្ត) ថ្ងៃនេះខ្ញុំត្រលប់មកវិញ ដើម្បីទាមទារភាពយុត្តិធម៌!
[00:07 - 00:10] [ប្រុស]: (គិតក្នុងចិត្ត) ហេតុអ្វីបានជានាងមកទីនេះ?
[00:10 - 00:13] [ស្រី]: (សំឡេងក្នុងចិត្ត) ខ្ញុំនឹងមិនចុះចាញ់ឡើយ!
''';

    final segments = tts.parseDialogueSegmentsForTesting(
        script, KhmerVoice.autoDialogue);
    expect(segments.length, 4);

    expect(segments[0].isInnerMonologue, isFalse);
    expect(segments[0].text, 'បីឆ្នាំមុន នាងត្រូវបានគេបណ្តេញចេញ។');

    expect(segments[1].isInnerMonologue, isTrue);
    expect(segments[1].text, 'ថ្ងៃនេះខ្ញុំត្រលប់មកវិញ ដើម្បីទាមទារភាពយុត្តិធម៌!');
    expect(segments[1].text.contains('ក្នុងចិត្ត'), isFalse);

    expect(segments[2].isInnerMonologue, isTrue);
    expect(segments[2].text, 'ហេតុអ្វីបានជានាងមកទីនេះ?');
    expect(segments[2].text.contains('គិតក្នុងចិត្ត'), isFalse);

    expect(segments[3].isInnerMonologue, isTrue);
    expect(segments[3].text, 'ខ្ញុំនឹងមិនចុះចាញ់ឡើយ!');
    expect(segments[3].text.contains('សំឡេងក្នុងចិត្ត'), isFalse);
  });
}

