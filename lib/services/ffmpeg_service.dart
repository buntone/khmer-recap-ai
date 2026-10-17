import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

class VideoMetadata {
  final double durationSeconds;
  final int width;
  final int height;
  final String format;

  VideoMetadata({
    required this.durationSeconds,
    required this.width,
    required this.height,
    required this.format,
  });

  String get resolutionFormatted => '${width}x$height';
  String get durationFormatted {
    final minutes = (durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (durationSeconds.toInt() % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class FFmpegService {
  /// Extracts metadata (duration, width, height) from the input video file
  Future<VideoMetadata> probeVideo(String videoPath) async {
    final mediaInfo = await FFprobeKit.getMediaInformation(videoPath);
    final info = mediaInfo.getMediaInformation();

    if (info == null) {
      return VideoMetadata(
        durationSeconds: 60.0,
        width: 1280,
        height: 720,
        format: 'mp4',
      );
    }

    final durationStr = info.getDuration() ?? '60';
    final duration = double.tryParse(durationStr) ?? 60.0;

    int width = 1280;
    int height = 720;
    final streams = info.getStreams();
    for (final s in streams) {
      if (s.getType() == 'video') {
        width = s.getWidth() ?? 1280;
        height = s.getHeight() ?? 720;
        break;
      }
    }

    return VideoMetadata(
      durationSeconds: duration,
      width: width,
      height: height,
      format: info.getFormat() ?? 'mp4',
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
        // Gemini API inline data limit is 20MB. Keep comfortably under 18MB.
        if (length > 0 && length <= 18 * 1024 * 1024) {
          return compressedVideo;
        }
      }
    } catch (_) {
      // Fallback to audio extraction if compression encounters any issue
    }
    return extractAudioForAnalysis(videoPath);
  }

  /// Compresses video to 480p ultrafast H.264 (~1.5-3.5MB for 1-2 minute video)
  Future<String> compressVideoForAnalysis(String videoPath) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outVideoPath = '${tempDir.path}/gemini_visual_$timestamp.mp4';

    // -vf "scale='min(480,iw)':-2" : Scales video proportionally to max 480 width/height
    // -r 15 : 15 fps gives 100% adequate temporal resolution for Gemini vision and cuts payload in half
    // -crf 32 -preset ultrafast -tune fastdecode -threads 0 : Finishes in 1-2 seconds with all CPU cores
    // -c:a aac -b:a 48k -ac 1 : Mono audio for voice clarity
    final cmd =
        '-y -threads 0 -i "$videoPath" -vf "scale=\'min(480,iw)\':-2" -r 15 -c:v libx264 -preset ultrafast -tune fastdecode -crf 32 -c:a aac -b:a 48k -ac 1 "$outVideoPath"';

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

  /// Generates a transparent PNG image of the watermark text with sharp, crisp edges and black outline (zero blur)
  Future<String> createWatermarkImage({
    required String text,
    String? outputPath,
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

    // 1. Subtle, semi-transparent dark outline stroke (25% opacity)
    final outlineSpan = TextSpan(
      text: text,
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color = const Color(0x40000000), // ~25% translucent dark outline
      ),
    );
    final outlinePainter = TextPainter(
      text: outlineSpan,
      textDirection: TextDirection.ltr,
    );
    outlinePainter.layout();

    // 2. Soft, translucent white fill (40% opacity) so video content shines through cleanly
    final fillSpan = TextSpan(
      text: text,
      style: const TextStyle(
        color: Color(0x66FFFFFF), // ~40% opacity soft translucent white
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ),
    );
    final fillPainter = TextPainter(
      text: fillSpan,
      textDirection: TextDirection.ltr,
    );
    fillPainter.layout();

    final width = (outlinePainter.width + 30).ceil();
    final height = (outlinePainter.height + 20).ceil();

    const offset = Offset(15, 10);
    outlinePainter.paint(canvas, offset);
    fillPainter.paint(canvas, offset);

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
    // Compact font size: 23 for 9:16 portrait so it never looks bulky or blocks the video
    final fontSize = isPortrait ? 23 : 28;
    final marginV = isPortrait ? 85 : 45;
    final marginLR = isPortrait ? 24 : 50;

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
        'Style: Default,sans-serif,$fontSize,$primaryColor,&H00000000,&H00000000,&H90000000,-1,0,0,0,100,100,0,0,1,2.0,0.8,2,$marginLR,$marginLR,$marginV,1');
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

      // Smart line wrapping for 9:16 vertical video
      if (cleanText.length > 22 && !cleanText.contains(r'\N')) {
        int splitIdx = cleanText.indexOf(' ', 16);
        if (splitIdx == -1 || splitIdx > 26) {
          splitIdx = cleanText.length ~/ 2;
        }
        cleanText =
            '${cleanText.substring(0, splitIdx).trim()}\\N${cleanText.substring(splitIdx).trim()}';
      }

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
    String? watermarkText,
    String? scriptText,
    bool subtitleEnabled = true,
    String subtitleColor = 'yellow',
    Function(int progressPercentage)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputVideoPath = '${tempDir.path}/khmer_recap_output_$timestamp.mp4';

    // Vocal cancellation filter: cancels center Chinese speech while keeping stereo background sound
    final bgVolume = (duckingVolume > 0.0 ? duckingVolume : 0.22)
        .clamp(0.05, 0.40)
        .toStringAsFixed(2);
    final bgAudioFilter =
        '[0:a]aformat=channel_layouts=stereo,pan=stereo|c0=0.5*c0-0.5*c1|c1=0.5*c1-0.5*c0,volume=$bgVolume[bg];[1:a]volume=1.35[khmer];[khmer][bg]amix=inputs=2:duration=first:dropout_transition=2[aout]';

    final videoMeta = await probeVideo(originalVideoPath);

    // Check if original video has audio track first
    final mediaInfo = await FFprobeKit.getMediaInformation(originalVideoPath);
    final hasOriginalAudio = mediaInfo
            .getMediaInformation()
            ?.getStreams()
            .any((s) => s.getType() == 'audio') ??
        false;

    String? watermarkImgPath;
    if (watermarkText != null && watermarkText.trim().isNotEmpty) {
      try {
        watermarkImgPath =
            await createWatermarkImage(text: watermarkText.trim());
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

    String? escapedAssPath;
    if (subtitleAssPath != null) {
      escapedAssPath =
          subtitleAssPath.replaceAll(r'\', '/').replaceAll(':', r'\:');
    }

    // Build video filter graph
    String vFilter = '';
    String vMap = '0:v:0';
    String watermarkInput = '';

    if (watermarkImgPath != null && escapedAssPath != null) {
      watermarkInput = '-i "$watermarkImgPath"';
      vFilter =
          "[0:v]subtitles='$escapedAssPath'[vsub];[vsub][2:v]overlay=x='20+(W-w-40)*(0.5+0.5*sin(t*0.6))':y='25+(H-h-50)*(0.5+0.5*cos(t*0.45))'[vout]";
      vMap = '[vout]';
    } else if (watermarkImgPath != null) {
      watermarkInput = '-i "$watermarkImgPath"';
      vFilter =
          "[0:v][2:v]overlay=x='20+(W-w-40)*(0.5+0.5*sin(t*0.6))':y='25+(H-h-50)*(0.5+0.5*cos(t*0.45))'[vout]";
      vMap = '[vout]';
    } else if (escapedAssPath != null) {
      vFilter = "[0:v]subtitles='$escapedAssPath'[vout]";
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

    final logs = await session.getAllLogsAsString();
    throw Exception('FFmpeg បរាជ័យក្នុងការច្របាច់បញ្ចូលសំឡេង និងវីដេអូ: $logs');
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
          targetPath = nativeResult;
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
