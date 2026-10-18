import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

class VideoMetadata {
  final double durationSeconds;
  final int width;
  final int height;
  final String format;
  final int audioChannels;
  final bool hasAudio;

  VideoMetadata({
    required this.durationSeconds,
    required this.width,
    required this.height,
    required this.format,
    this.audioChannels = 2,
    this.hasAudio = true,
  });

  String get resolutionFormatted => '${width}x$height';
  String get durationFormatted {
    final minutes = (durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (durationSeconds.toInt() % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class FFmpegService {
  /// Extracts metadata (duration, width, height, audio channels) from the input video file
  Future<VideoMetadata> probeVideo(String videoPath) async {
    final mediaInfo = await FFprobeKit.getMediaInformation(videoPath);
    final info = mediaInfo.getMediaInformation();

    if (info == null) {
      return VideoMetadata(
        durationSeconds: 60.0,
        width: 1280,
        height: 720,
        format: 'mp4',
        audioChannels: 2,
        hasAudio: true,
      );
    }

    final streams = info.getStreams();
    double duration = double.tryParse(info.getDuration() ?? '') ?? 0.0;
    if (duration <= 0.5) {
      for (final s in streams) {
        final sDur = double.tryParse(s.getStringProperty('duration') ?? '') ??
            (s.getNumberProperty('duration')?.toDouble() ?? 0.0);
        if (sDur > duration) {
          duration = sDur;
        }
      }
    }
    if (duration <= 0.5) {
      duration = 60.0;
    }

    int width = 1280;
    int height = 720;
    int audioChannels = 2;
    bool hasAudio = false;

    for (final s in streams) {
      if (s.getType() == 'video') {
        width = s.getWidth() ?? 1280;
        height = s.getHeight() ?? 720;
      } else if (s.getType() == 'audio') {
        hasAudio = true;
        final ch = s.getNumberProperty('channels')?.toInt() ??
            int.tryParse(s.getStringProperty('channels') ?? '');
        if (ch != null && ch > 0) {
          audioChannels = ch;
        }
      }
    }

    return VideoMetadata(
      durationSeconds: duration,
      width: width,
      height: height,
      format: info.getFormat() ?? 'mp4',
      audioChannels: audioChannels,
      hasAudio: hasAudio,
    );
  }

  /// Prepares lightweight media for Gemini AI:
  /// Compresses the video into a small 480p MP4 (~1.5-3.5 MB) so Gemini has full visual
  /// comprehension of on-screen characters, actions, scene timings, and hardcoded Chinese subtitles!
  /// If video compression fails or file exceeds 18MB, seamlessly falls back to audio extraction (.mp3).
  Future<String> prepareMediaForGemini(String videoPath) async {
    try {
      final compressedVideo = await compressVideoForAnalysis(videoPath);
      final file = File(compressedVideo);
      if (await file.exists()) {
        final length = await file.length();
        // Gemini API inline data limit is 20MB. Keep comfortably under 10MB to avoid RAM spikes on Android
        if (length > 0 && length <= 10 * 1024 * 1024) {
          return compressedVideo;
        }
      }
    } catch (_) {
      // Fallback to audio extraction if compression encounters any issue
    }
    return extractAudioForAnalysis(videoPath);
  }

  /// Compresses video to 480p ultrafast H.264 (~1.0-2.5MB for 1-2 minute video)
  Future<String> compressVideoForAnalysis(String videoPath) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outVideoPath = '${tempDir.path}/gemini_visual_$timestamp.mp4';

    // -vf "scale='min(480,iw)':-2" : Scales video proportionally to max 480 width/height
    // -r 12 : 12 fps gives 100% adequate temporal resolution for Gemini vision and cuts payload in half
    // -crf 34 -preset ultrafast -tune fastdecode -threads 0 : Finishes in 1-2 seconds with all CPU cores
    // -c:a aac -b:a 40k -ac 1 : Mono audio for voice clarity
    final cmd =
        '-y -threads 0 -i "$videoPath" -vf "scale=\'min(480,iw)\':-2" -r 12 -c:v libx264 -preset ultrafast -tune fastdecode -crf 34 -c:a aac -b:a 40k -ac 1 "$outVideoPath"';

    final session = await FFmpegKit.execute(cmd);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      return outVideoPath;
    } else {
      final logs = await session.getAllLogsAsString();
      throw Exception('FFmpeg video compression failed: $logs');
    }
  }

  /// Extracts audio track from the original video as MP3 for lightweight Gemini ingestion
  Future<String> extractAudioForAnalysis(String videoPath) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outAudioPath = '${tempDir.path}/extracted_audio_$timestamp.mp3';

    // -vn: no video, -ac 1: mono for smaller payload, -ar 16000: 16kHz speech recognition optimal, -b:a 64k
    final cmd =
        '-y -threads 0 -i "$videoPath" -vn -ac 1 -ar 16000 -b:a 64k "$outAudioPath"';

    final session = await FFmpegKit.execute(cmd);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      return outAudioPath;
    } else {
      final logs = await session.getAllLogsAsString();
      throw Exception('FFmpeg បរាជ័យក្នុងការទាញយកសំឡេងពីវីដេអូ: $logs');
    }
  }

  /// Resolves the color for watermark text with configurable opacity
  static Color resolveWatermarkColor(String colorName, {double opacity = 0.40}) {
    final double op = opacity.clamp(0.1, 1.0);
    switch (colorName.toLowerCase()) {
      case 'gold':
        return const Color(0xFFFFD700).withValues(alpha: op); // Radiant Gold
      case 'yellow':
        return const Color(0xFFFFEE58).withValues(alpha: op); // Bright Lemon
      case 'white':
        return const Color(0xFFFFFFFF).withValues(alpha: op);
      case 'cyan':
        return const Color(0xFF00E5FF).withValues(alpha: op);
      case 'green':
      case 'emerald':
        return const Color(0xFF00E676).withValues(alpha: op);
      case 'pink':
        return const Color(0xFFFF4081).withValues(alpha: op);
      case 'orange':
        return const Color(0xFFFF9100).withValues(alpha: op);
      case 'red':
        return const Color(0xFFFF1744).withValues(alpha: op);
      case 'purple':
        return const Color(0xFFD500F9).withValues(alpha: op);
      default:
        return const Color(0xFFFFD700).withValues(alpha: op);
    }
  }

  /// Resolves the designated Khmer font family dynamically
  static TextStyle getKhmerWatermarkTextStyle({
    required String fontName,
    Color? color,
    Paint? foreground,
    required double fontSize,
    FontWeight fontWeight = FontWeight.w700,
    List<Shadow>? shadows,
  }) {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return TextStyle(
        fontFamily: fontName,
        fontFamilyFallback: const ['Noto Sans Khmer', 'sans-serif'],
        color: foreground == null ? color : null,
        foreground: foreground,
        fontSize: fontSize,
        fontWeight: fontWeight,
        shadows: shadows,
      );
    }

    try {
      switch (fontName) {
        case 'Moul':
          return GoogleFonts.moul(
            color: foreground == null ? color : null,
            foreground: foreground,
            fontSize: fontSize,
            fontWeight: fontWeight,
            shadows: shadows,
          );
        case 'Moulpali':
          return GoogleFonts.moulpali(
            color: foreground == null ? color : null,
            foreground: foreground,
            fontSize: fontSize,
            fontWeight: fontWeight,
            shadows: shadows,
          );
        case 'Preahvihear':
          return GoogleFonts.preahvihear(
            color: foreground == null ? color : null,
            foreground: foreground,
            fontSize: fontSize,
            fontWeight: fontWeight,
            shadows: shadows,
          );
        case 'Koulen':
          return GoogleFonts.koulen(
            color: foreground == null ? color : null,
            foreground: foreground,
            fontSize: fontSize,
            fontWeight: fontWeight,
            shadows: shadows,
          );
        case 'Bayon':
          return GoogleFonts.bayon(
            color: foreground == null ? color : null,
            foreground: foreground,
            fontSize: fontSize,
            fontWeight: fontWeight,
            shadows: shadows,
          );
        case 'Dangrek':
          return GoogleFonts.dangrek(
            color: foreground == null ? color : null,
            foreground: foreground,
            fontSize: fontSize,
            fontWeight: fontWeight,
            shadows: shadows,
          );
        case 'Bokor':
          return GoogleFonts.bokor(
            color: foreground == null ? color : null,
            foreground: foreground,
            fontSize: fontSize,
            fontWeight: fontWeight,
            shadows: shadows,
          );
        case 'Kdam Thmor Pro':
          return GoogleFonts.kdamThmorPro(
            color: foreground == null ? color : null,
            foreground: foreground,
            fontSize: fontSize,
            fontWeight: fontWeight,
            shadows: shadows,
          );
        case 'Kantumruy Pro':
          return GoogleFonts.kantumruyPro(
            color: foreground == null ? color : null,
            foreground: foreground,
            fontSize: fontSize,
            fontWeight: fontWeight,
            shadows: shadows,
          );
        case 'Battambang':
          return GoogleFonts.battambang(
            color: foreground == null ? color : null,
            foreground: foreground,
            fontSize: fontSize,
            fontWeight: fontWeight,
            shadows: shadows,
          );
        case 'Siemreap':
          return GoogleFonts.siemreap(
            color: foreground == null ? color : null,
            foreground: foreground,
            fontSize: fontSize,
            fontWeight: fontWeight,
            shadows: shadows,
          );
        case 'Noto Sans Khmer':
        default:
          return GoogleFonts.notoSansKhmer(
            color: foreground == null ? color : null,
            foreground: foreground,
            fontSize: fontSize,
            fontWeight: fontWeight,
            shadows: shadows,
          );
      }
    } catch (_) {
      return TextStyle(
        fontFamily: 'Noto Sans Khmer',
        color: foreground == null ? color : null,
        foreground: foreground,
        fontSize: fontSize,
        fontWeight: fontWeight,
        shadows: shadows,
      );
    }
  }

  /// Generates a transparent PNG image of the watermark text with artistic Khmer ornamental fonts,
  /// custom color, and 40% translucent fill + dark shadow so video content shines through cleanly.
  Future<String> createWatermarkImage({
    required String text,
    String? outputPath,
    String fontName = 'Moul',
    String colorName = 'gold',
    double opacity = 0.40,
  }) async {
    final String path;
    if (outputPath != null && outputPath.isNotEmpty) {
      path = outputPath;
    } else {
      final tempDir = await getTemporaryDirectory();
      path =
          '${tempDir.path}/watermark_${DateTime.now().millisecondsSinceEpoch}.png';
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 1. Subtle, semi-transparent dark outline stroke (40% opacity)
    final outlineSpan = TextSpan(
      text: text,
      style: getKhmerWatermarkTextStyle(
        fontName: fontName,
        fontSize: 25,
        fontWeight: FontWeight.w700,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..color = const Color(0x66000000), // ~40% translucent dark outline
      ),
    );
    final outlinePainter = TextPainter(
      text: outlineSpan,
      textDirection: TextDirection.ltr,
    );
    outlinePainter.layout();

    // 2. Soft, 35% translucent drop shadow
    final shadowSpan = TextSpan(
      text: text,
      style: getKhmerWatermarkTextStyle(
        fontName: fontName,
        fontSize: 25,
        fontWeight: FontWeight.w700,
        color: const Color(0x55000000),
      ),
    );
    final shadowPainter = TextPainter(
      text: shadowSpan,
      textDirection: TextDirection.ltr,
    );
    shadowPainter.layout();

    // 3. Elegant translucent colored fill (40% opacity as requested)
    final fillColor = resolveWatermarkColor(colorName, opacity: opacity);
    final fillSpan = TextSpan(
      text: text,
      style: getKhmerWatermarkTextStyle(
        fontName: fontName,
        fontSize: 25,
        fontWeight: FontWeight.w700,
        color: fillColor,
      ),
    );
    final fillPainter = TextPainter(
      text: fillSpan,
      textDirection: TextDirection.ltr,
    );
    fillPainter.layout();

    final width = (outlinePainter.width + 36).ceil();
    final height = (outlinePainter.height + 26).ceil();

    const baseOffset = Offset(18, 13);
    const shadowOffset = Offset(19.5, 14.5);

    shadowPainter.paint(canvas, shadowOffset);
    outlinePainter.paint(canvas, baseOffset);
    fillPainter.paint(canvas, baseOffset);

    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    final file = File(path);
    await file.writeAsBytes(pngBytes, flush: true);
    return file.path;
  }

  /// Parses timestamps like "00:00:02,800", "01:28", "88.5" into total seconds
  static double? _parseTimeToSeconds(String? timeStr) {
    if (timeStr == null) return null;
    var s = timeStr
        .trim()
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll('(', '')
        .replaceAll(')', '');
    if (s.isEmpty) return null;
    s = s.replaceAll(',', '.');

    final parts = s.split(':');
    if (parts.length == 3) {
      final h = double.tryParse(parts[0]) ?? 0;
      final m = double.tryParse(parts[1]) ?? 0;
      final sec = double.tryParse(parts[2]) ?? 0;
      return h * 3600 + m * 60 + sec;
    } else if (parts.length == 2) {
      final m = double.tryParse(parts[0]) ?? 0;
      final sec = double.tryParse(parts[1]) ?? 0;
      return m * 60 + sec;
    } else if (parts.length == 1) {
      return double.tryParse(parts[0]);
    }
    return null;
  }

  static String _formatAssTime(double totalSec) {
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;
    final sInt = s.toInt();
    final cs = ((s - sInt) * 100).toInt();
    return '$h:${m.toString().padLeft(2, '0')}:${sInt.toString().padLeft(2, '0')}.${cs.toString().padLeft(2, '0')}';
  }

  static bool _fontRegistered = false;

  /// Ensures bundled Noto Sans Khmer font is extracted to app documents
  /// and registered with FFmpegKit so libass always renders Khmer subtitles perfectly.
  Future<String?> ensureKhmerFontRegistered() async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final fontsDir = Directory('${appDocDir.path}/fonts');
      if (!await fontsDir.exists()) {
        await fontsDir.create(recursive: true);
      }

      final fontFile = File('${fontsDir.path}/NotoSansKhmer-Bold.ttf');
      if (!await fontFile.exists() || await fontFile.length() == 0) {
        try {
          final data =
              await rootBundle.load('assets/fonts/NotoSansKhmer-Bold.ttf');
          final bytes = data.buffer
              .asUint8List(data.offsetInBytes, data.lengthInBytes);
          await fontFile.writeAsBytes(bytes, flush: true);
        } catch (e) {
          debugPrint('Warning: Could not load bundled font asset: $e');
        }
      }

      if (!_fontRegistered) {
        try {
          final fontDirs = [fontsDir.path];
          if (Platform.isAndroid && await Directory('/system/fonts').exists()) {
            fontDirs.add('/system/fonts');
          }
          await FFmpegKitConfig.setFontDirectoryList(
            fontDirs,
            {
              'Noto Sans Khmer': fontFile.path,
              'Noto Sans Khmer UI': fontFile.path,
              'NotoSansKhmer': fontFile.path,
              'sans-serif': fontFile.path,
              'Default': fontFile.path,
            },
          );
          _fontRegistered = true;
        } catch (e) {
          debugPrint('Warning: FFmpegKitConfig.setFontDirectoryList failed: $e');
        }
      }

      return fontsDir.path;
    } catch (e) {
      debugPrint('ensureKhmerFontRegistered error: $e');
      return null;
    }
  }

  static String _wrapKhmerTextForSubtitles(String text,
      {int maxLineChars = 24}) {
    if (text.length <= maxLineChars || text.contains(r'\N')) return text;

    final spaceIdx = text.indexOf(' ', (maxLineChars * 0.6).toInt());
    if (spaceIdx != -1 && spaceIdx <= maxLineChars + 6) {
      return '${text.substring(0, spaceIdx).trim()}\\N${text.substring(spaceIdx).trim()}';
    }

    int splitIdx = text.length ~/ 2;
    while (splitIdx > 0 && splitIdx < text.length) {
      final code = text.codeUnitAt(splitIdx);
      final prevCode = text.codeUnitAt(splitIdx - 1);
      final isCombining = (code >= 0x17B6 && code <= 0x17D3) || code == 0x17DD;
      final isAfterCoeng = prevCode == 0x17D2;

      if (!isCombining && !isAfterCoeng) {
        break;
      }
      splitIdx++;
    }

    if (splitIdx > 0 && splitIdx < text.length) {
      return '${text.substring(0, splitIdx).trim()}\\N${text.substring(splitIdx).trim()}';
    }
    return text;
  }

  /// Generates a styled ASS subtitle file tuned specifically for 9:16 mobile videos (compact & elegant)
  Future<String> createSubtitlesAssFile({
    required String scriptText,
    int videoWidth = 720,
    int videoHeight = 1280,
    String colorTheme = 'yellow',
    String? outputPath,
  }) async {
    final String assPath;
    if (outputPath != null && outputPath.isNotEmpty) {
      assPath = outputPath;
    } else {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      assPath = '${tempDir.path}/subtitles_$timestamp.ass';
    }

    final isPortrait = videoHeight >= videoWidth;
    final playResX = isPortrait ? 720 : 1280;
    final playResY = isPortrait ? 1280 : 720;
    // Compact font size: 21 for 9:16 portrait so it never looks bulky or blocks the video
    final fontSize = isPortrait ? 21 : 25;
    final marginV = isPortrait ? 75 : 45;
    final marginLR = isPortrait ? 28 : 50;

    // ASS PrimaryColour is in &HAABBGGRR format
    String primaryColor;
    switch (colorTheme.toLowerCase()) {
      case 'white':
        primaryColor = '&H00FFFFFF';
        break;
      case 'cyan':
        primaryColor = '&H00FFFF00'; // Cyan
        break;
      case 'green':
        primaryColor = '&H0033FF33'; // Lime green
        break;
      case 'yellow':
      default:
        primaryColor = '&H0000E5FF'; // Golden Amber / Yellow
        break;
    }

    final buffer = StringBuffer();
    buffer.writeln('[Script Info]');
    buffer.writeln('ScriptType: v4.00+');
    buffer.writeln('PlayResX: $playResX');
    buffer.writeln('PlayResY: $playResY');
    buffer.writeln('ScaledBorderAndShadow: yes');
    buffer.writeln('');
    buffer.writeln('[V4+ Styles]');
    buffer.writeln(
        'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding');
    buffer.writeln(
        'Style: Default,Noto Sans Khmer,$fontSize,$primaryColor,&H00000000,&H00000000,&H90000000,-1,0,0,0,100,100,0,0,1,1.8,0.6,2,$marginLR,$marginLR,$marginV,1');
    buffer.writeln('');
    buffer.writeln('[Events]');
    buffer.writeln(
        'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text');

    final timePattern = RegExp(
        r'\[?\(?(\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d+)?)(?:\s*(?:-->|[-–])\s*(\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d+)?))?\)?\]?');

    final lines = scriptText.split('\n');
    final parsedEvents = <Map<String, dynamic>>[];

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (RegExp(r'^\d+$').hasMatch(line)) continue;
      if (!RegExp(r'[\u1780-\u17FF]').hasMatch(line)) continue;

      final tMatch = timePattern.firstMatch(line);
      if (tMatch == null) continue;

      final startSec = _parseTimeToSeconds(tMatch.group(1));
      final endSec = _parseTimeToSeconds(tMatch.group(2));
      if (startSec == null) continue;

      var cleanText = line
          .replaceAll(timePattern, '')
          .replaceAll('[ប្រុស]:', '')
          .replaceAll('[ស្រី]:', '')
          .replaceAll('[ប្រុស]', '')
          .replaceAll('[ស្រី]', '')
          .replaceAll(RegExp(r'^[:៖\-–\s]+'), '')
          .trim();

      cleanText = cleanText.replaceAll('"', '').trim();
      if (cleanText.isEmpty) continue;

      // Smart line wrapping for 9:16 vertical video without breaking Khmer Unicode glyphs
      cleanText = _wrapKhmerTextForSubtitles(cleanText);

      parsedEvents.add({
        'start': startSec,
        'end': endSec,
        'text': cleanText,
      });
    }

    for (int i = 0; i < parsedEvents.length; i++) {
      final ev = parsedEvents[i];
      final start = ev['start'] as double;
      double end = ev['end'] as double? ??
          (i + 1 < parsedEvents.length
              ? (parsedEvents[i + 1]['start'] as double)
              : start + 3.0);

      if (end <= start) end = start + 2.5;
      if (end - start > 4.5) end = start + 3.8;

      final startStr = _formatAssTime(start);
      final endStr = _formatAssTime(end);
      final text = ev['text'] as String;

      buffer.writeln('Dialogue: 0,$startStr,$endStr,Default,,0,0,0,,$text');
    }

    final assFile = File(assPath);
    await assFile.writeAsString(buffer.toString(), flush: true);
    return assFile.path;
  }

  /// Merges the newly synthesized Khmer voice with original video,
  /// stripping out Chinese spoken dialogue and preserving background music/SFX underneath.
  /// Optionally burns in on-screen Khmer subtitles and moving watermark.
  Future<String> mergeKhmerVoiceWithVideo({
    required String originalVideoPath,
    required String khmerAudioPath,
    required double duckingVolume, // 0.0 to 1.0
    bool removeChineseVocals = true, // Removes spoken Chinese voice, preserving BGM/SFX
    String? watermarkText,
    String? watermarkFont,
    String? watermarkColor,
    double watermarkOpacity = 0.40,
    String? scriptText,
    bool subtitleEnabled = false,
    String subtitleColor = 'yellow',
    Function(int progressPercentage)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputVideoPath = '${tempDir.path}/khmer_recap_output_$timestamp.mp4';

    // Register Android system Khmer fonts with FFmpegKit's fontconfig so subtitles render crisp glyphs
    await ensureKhmerFontRegistered();

    final videoMeta = await probeVideo(originalVideoPath);
    final hasOriginalAudio = videoMeta.hasAudio;

    // Clean audio ducking filter with intelligent Chinese vocal cancellation
    final double vol = duckingVolume.clamp(0.0, 1.0);
    final String bgAudioFilter;
    if (vol <= 0.01) {
      // Ducking is 0%: Mute original audio completely for 100% pure, crystal-clear Khmer voice
      bgAudioFilter = '[1:a]volume=1.25[aout]';
    } else if (removeChineseVocals) {
      final bgVolStr = vol.toStringAsFixed(2);
      if (videoMeta.audioChannels >= 2) {
        // High-precision Mid-Side vocal cancellation with sub-bass preservation:
        // Mid (center channel) speech is suppressed by 36dB while preserving stereo BGM, instruments & sound effects!
        bgAudioFilter =
            '[0:a]aformat=channel_layouts=stereo,asplit=2[bg_low][bg_high];'
            '[bg_low]lowpass=f=200,volume=0.85[bg_bass];'
            '[bg_high]highpass=f=200,stereotools=mlev=0.015625:slev=1.35[bg_sides];'
            '[bg_bass][bg_sides]amix=inputs=2:dropout_transition=0,volume=$bgVolStr[bg];'
            '[1:a]volume=1.25[khmer];'
            '[bg][khmer]amix=inputs=2:duration=first:dropout_transition=0[aout]';
      } else {
        // Mono voice rejection notch filter (reduces human speech frequencies 250Hz - 3500Hz)
        bgAudioFilter =
            '[0:a]equalizer=f=1200:width_type=o:w=2.5:g=-16,equalizer=f=2800:width_type=o:w=1.8:g=-14,volume=$bgVolStr[bg];'
            '[1:a]volume=1.25[khmer];'
            '[bg][khmer]amix=inputs=2:duration=first:dropout_transition=0[aout]';
      }
    } else {
      final bgVolStr = vol.toStringAsFixed(2);
      bgAudioFilter =
          '[0:a]volume=$bgVolStr[bg];[1:a]volume=1.25[khmer];'
          '[bg][khmer]amix=inputs=2:duration=first:dropout_transition=0[aout]';
    }

    String? watermarkImgPath;
    if (watermarkText != null && watermarkText.trim().isNotEmpty) {
      try {
        watermarkImgPath = await createWatermarkImage(
          text: watermarkText.trim(),
          fontName: watermarkFont ?? 'Moul',
          colorName: watermarkColor ?? 'gold',
          opacity: watermarkOpacity,
        );
      } catch (e) {
        debugPrint('Warning: Could not create watermark image: $e');
      }
    }

    String? subtitleAssPath;
    if (subtitleEnabled && scriptText != null && scriptText.trim().isNotEmpty) {
      try {
        subtitleAssPath = await createSubtitlesAssFile(
          scriptText: scriptText,
          videoWidth: videoMeta.width,
          videoHeight: videoMeta.height,
          colorTheme: subtitleColor,
        );
      } catch (e) {
        debugPrint('Warning: Could not create subtitle ASS file: $e');
      }
    }

    String? subFilterParam;
    String? escapedAssPath;
    if (subtitleAssPath != null) {
      escapedAssPath = subtitleAssPath
          .replaceAll(r'\', '/')
          .replaceAll(':', r'\:')
          .replaceAll("'", r"\'");
      subFilterParam = "ass='$escapedAssPath'";
    }

    // Build video filter graph
    String vFilter = '';
    String vMap = '0:v:0';
    String watermarkInput = '';

    if (watermarkImgPath != null && subFilterParam != null) {
      watermarkInput = '-i "$watermarkImgPath"';
      vFilter =
          "[0:v]$subFilterParam[vsub];[vsub][2:v]overlay=x='20+(W-w-40)*(0.5+0.5*sin(t*0.6))':y='25+(H-h-50)*(0.5+0.5*cos(t*0.45))'[vout]";
      vMap = '[vout]';
    } else if (watermarkImgPath != null) {
      watermarkInput = '-i "$watermarkImgPath"';
      vFilter =
          "[0:v][2:v]overlay=x='20+(W-w-40)*(0.5+0.5*sin(t*0.6))':y='25+(H-h-50)*(0.5+0.5*cos(t*0.45))'[vout]";
      vMap = '[vout]';
    } else if (subFilterParam != null) {
      vFilter = "[0:v]$subFilterParam[vout]";
      vMap = '[vout]';
    }

    String cmd;
    if (vFilter.isNotEmpty) {
      final filterGraph =
          hasOriginalAudio ? '$vFilter;$bgAudioFilter' : vFilter;
      final aMap = hasOriginalAudio ? '-map "[aout]"' : '-map 1:a:0';
      cmd = '-y -threads 0 -i "$originalVideoPath" -i "$khmerAudioPath" $watermarkInput '
          '-filter_complex "$filterGraph" '
          '-map "$vMap" $aMap -c:v libx264 -preset ultrafast -tune fastdecode -crf 23 -c:a aac -b:a 192k -shortest "$outputVideoPath"';
    } else {
      if (hasOriginalAudio) {
        cmd = '-y -threads 0 -i "$originalVideoPath" -i "$khmerAudioPath" '
            '-filter_complex "$bgAudioFilter" '
            '-map 0:v:0 -map "[aout]" -c:v copy -c:a aac -b:a 192k -shortest "$outputVideoPath"';
      } else {
        cmd = '-y -threads 0 -i "$originalVideoPath" -i "$khmerAudioPath" '
            '-map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -shortest "$outputVideoPath"';
      }
    }

    final session = await FFmpegKit.execute(cmd);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      return outputVideoPath;
    }

    final logs = await session.getAllLogsAsString();
    debugPrint('FFmpeg with ass filter failed: $logs');

    // Subtitle retry: if 'ass' filter failed, retry with 'subtitles' filter
    if (subFilterParam != null && escapedAssPath != null) {
      final retrySubParam = "subtitles='$escapedAssPath'";
      final retryVFilter = vFilter.replaceAll(subFilterParam, retrySubParam);
      final retryFilterGraph =
          hasOriginalAudio ? '$retryVFilter;$bgAudioFilter' : retryVFilter;
      final retryAMap = hasOriginalAudio ? '-map "[aout]"' : '-map 1:a:0';
      final retryCmd =
          '-y -threads 0 -i "$originalVideoPath" -i "$khmerAudioPath" $watermarkInput '
          '-filter_complex "$retryFilterGraph" '
          '-map "$vMap" $retryAMap -c:v libx264 -preset ultrafast -tune fastdecode -crf 23 -c:a aac -b:a 192k -shortest "$outputVideoPath"';

      final retrySession = await FFmpegKit.execute(retryCmd);
      if (ReturnCode.isSuccess(await retrySession.getReturnCode())) {
        return outputVideoPath;
      }
      final retryLogs = await retrySession.getAllLogsAsString();
      debugPrint('FFmpeg with subtitles filter fallback failed: $retryLogs');
    }

    // Graceful fallback: If subtitle or filter complex encountered any error on this device,
    // run baseline audio merge without subtitle filter so user always gets their video successfully
    String fallbackCmd;
    if (hasOriginalAudio) {
      fallbackCmd =
          '-y -threads 0 -i "$originalVideoPath" -i "$khmerAudioPath" '
          '-filter_complex "$bgAudioFilter" '
          '-map 0:v:0 -map "[aout]" -c:v libx264 -preset ultrafast -tune fastdecode -crf 23 -c:a aac -b:a 192k -shortest "$outputVideoPath"';
    } else {
      fallbackCmd =
          '-y -threads 0 -i "$originalVideoPath" -i "$khmerAudioPath" '
          '-map 0:v:0 -map 1:a:0 -c:v libx264 -preset ultrafast -tune fastdecode -crf 23 -c:a aac -b:a 192k -shortest "$outputVideoPath"';
    }

    final fallbackSession = await FFmpegKit.execute(fallbackCmd);
    final fallbackReturnCode = await fallbackSession.getReturnCode();

    if (ReturnCode.isSuccess(fallbackReturnCode)) {
      return outputVideoPath;
    }

    final fallbackLogs = await fallbackSession.getAllLogsAsString();
    throw Exception('FFmpeg បរាជ័យក្នុងការច្របាច់បញ្ចូលសំឡេង និងវីដេអូ: $fallbackLogs');
  }

  /// Exports standalone Khmer recap audio to persistent Android storage
  Future<String> exportKhmerAudioFile(
      String srcAudioPath, String customName) async {
    Directory? exportDir;
    if (Platform.isAndroid) {
      exportDir = Directory('/storage/emulated/0/Download');
      if (!await exportDir.exists()) {
        exportDir = await getExternalStorageDirectory();
      }
    } else {
      exportDir = await getApplicationDocumentsDirectory();
    }

    final targetPath = '${exportDir!.path}/${customName}_Khmer_Recap.mp3';
    final srcFile = File(srcAudioPath);
    await srcFile.copy(targetPath);
    return targetPath;
  }

  static const MethodChannel _scannerChannel =
      MethodChannel('com.example.khmer_recap_ai/media_scanner');

  /// Exports dubbed video into Phone Gallery (DCIM/KhmerRecap) exactly ONCE without duplicate copies
  Future<String> autoSaveToGallery(String srcVideoPath,
      {String? customName}) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final title = customName ?? 'KhmerRecap_$timestamp';
    final fileName = '$title.mp4';

    String targetPath = srcVideoPath;

    if (Platform.isAndroid) {
      // 1. Native MediaStore insertion into DCIM/KhmerRecap
      try {
        final dynamic nativeResult =
            await _scannerChannel.invokeMethod('saveVideoToGallery', {
          'srcPath': srcVideoPath,
          'title': title,
        });
        if (nativeResult is String && nativeResult.isNotEmpty) {
          if (!nativeResult.startsWith('content://') && await File(nativeResult).exists()) {
            targetPath = nativeResult;
          } else {
            targetPath = srcVideoPath;
          }
          return targetPath; // Return immediately to guarantee single gallery entry!
        }
      } catch (e) {
        debugPrint('Native saveVideoToGallery note: $e');
      }

      // 2. Fallback only if native MediaStore fails
      try {
        final dcimDir = Directory('/storage/emulated/0/DCIM/KhmerRecap');
        if (!await dcimDir.exists()) {
          await dcimDir.create(recursive: true);
        }
        final dcimFile = File('${dcimDir.path}/$fileName');
        if (!await dcimFile.exists() ||
            (await dcimFile.length()) != (await File(srcVideoPath).length())) {
          await File(srcVideoPath).copy(dcimFile.path);
        }
        targetPath = dcimFile.path;
        await _scannerChannel.invokeMethod('scanFile', {'path': targetPath});
      } catch (_) {}
    } else {
      final docDir = await getApplicationDocumentsDirectory();
      final iosFile = File('${docDir.path}/$fileName');
      await File(srcVideoPath).copy(iosFile.path);
      targetPath = iosFile.path;
    }

    return targetPath;
  }

  /// Saves the dubbed video to the Movies or DCIM directory and scans into Phone Gallery
  Future<String> exportDubbedVideoFile(
      String srcVideoPath, String customName) async {
    return autoSaveToGallery(srcVideoPath, customName: customName);
  }
}
