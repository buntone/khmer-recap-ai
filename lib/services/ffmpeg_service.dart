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

  /// Generates a transparent PNG image of the watermark text with rich shadow for video overlay
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

    final textSpan = TextSpan(
      text: text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 26,
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(
            color: Color(0xDD000000), // Solid dark drop shadow
            offset: Offset(2.5, 2.5),
            blurRadius: 4.0,
          ),
          Shadow(
            color: Color(0x99000000),
            offset: Offset(-1.0, -1.0),
            blurRadius: 2.0,
          ),
        ],
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final width = (textPainter.width + 30).ceil();
    final height = (textPainter.height + 20).ceil();

    textPainter.paint(canvas, const Offset(15, 10));

    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    final file = File(path);
    await file.writeAsBytes(pngBytes, flush: true);
    return file.path;
  }

  /// Merges the newly synthesized Khmer voice with original video,
  /// ducking the original Chinese audio to [duckingVolume] (e.g. 0.15 = 15%).
  /// Applies moving / bouncing watermark logo across the video continuously if [watermarkText] is provided.
  Future<String> mergeKhmerVoiceWithVideo({
    required String originalVideoPath,
    required String khmerAudioPath,
    required double duckingVolume, // 0.0 (mute) to 1.0 (full)
    String? watermarkText,
    Function(int progressPercentage)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputVideoPath = '${tempDir.path}/khmer_recap_output_$timestamp.mp4';

    final bgVolume = duckingVolume.clamp(0.0, 1.0).toStringAsFixed(2);

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

    String cmd;
    if (watermarkImgPath != null) {
      // Overlay moving/bouncing watermark continuously across the video with shadow text
      // x oscillates smoothly between 20 and W-w-20
      // y oscillates smoothly between 25 and H-h-25
      const overlayMotion =
          "[0:v][2:v]overlay=x='20+(W-w-40)*(0.5+0.5*sin(t*0.6))':y='25+(H-h-50)*(0.5+0.5*cos(t*0.45))'[vout]";

      if (hasOriginalAudio && duckingVolume >= 0.02) {
        cmd =
            '-y -threads 0 -i "$originalVideoPath" -i "$khmerAudioPath" -i "$watermarkImgPath" '
            '-filter_complex "$overlayMotion;[0:a]volume=$bgVolume[bg];[1:a]volume=1.35[khmer];[khmer][bg]amix=inputs=2:duration=first:dropout_transition=2[aout]" '
            '-map "[vout]" -map "[aout]" -c:v libx264 -preset ultrafast -tune fastdecode -crf 23 -c:a aac -b:a 192k -shortest "$outputVideoPath"';
      } else {
        cmd =
            '-y -threads 0 -i "$originalVideoPath" -i "$khmerAudioPath" -i "$watermarkImgPath" '
            '-filter_complex "$overlayMotion" '
            '-map "[vout]" -map 1:a:0 -c:v libx264 -preset ultrafast -tune fastdecode -crf 23 -c:a aac -b:a 192k -shortest "$outputVideoPath"';
      }
    } else {
      if (hasOriginalAudio && duckingVolume >= 0.02) {
        cmd = '-y -threads 0 -i "$originalVideoPath" -i "$khmerAudioPath" '
            '-filter_complex "[0:a]volume=$bgVolume[bg];[1:a]volume=1.35[khmer];[khmer][bg]amix=inputs=2:duration=first:dropout_transition=2[aout]" '
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
    } else {
      // If stream copy failed due to container flags, fallback to re-encoding with H.264
      String fallbackCmd;
      if (hasOriginalAudio && duckingVolume >= 0.02) {
        fallbackCmd =
            '-y -threads 0 -i "$originalVideoPath" -i "$khmerAudioPath" '
            '-filter_complex "[0:a]volume=$bgVolume[bg];[1:a]volume=1.35[khmer];[khmer][bg]amix=inputs=2:duration=first:dropout_transition=2[aout]" '
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
      throw Exception(
          'FFmpeg បរាជ័យក្នុងការច្របាច់បញ្ចូលសំឡេង និងវីដេអូ: $logs');
    }
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
