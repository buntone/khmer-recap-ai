import 'dart:io';
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

  /// Extracts audio track from the original video as MP3 for lightweight Gemini ingestion
  Future<String> extractAudioForAnalysis(String videoPath) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outAudioPath = '${tempDir.path}/extracted_audio_$timestamp.mp3';

    // -vn: no video, -ac 1: mono for smaller payload, -ar 16000: 16kHz speech recognition optimal, -b:a 64k
    final cmd = '-y -i "$videoPath" -vn -ac 1 -ar 16000 -b:a 64k "$outAudioPath"';

    final session = await FFmpegKit.execute(cmd);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      return outAudioPath;
    } else {
      final logs = await session.getAllLogsAsString();
      throw Exception('FFmpeg បរាជ័យក្នុងការទាញយកសំឡេងពីវីដេអូ: $logs');
    }
  }

  /// Merges the newly synthesized Khmer voice with original video,
  /// ducking the original Chinese audio to [duckingVolume] (e.g. 0.15 = 15%).
  /// Utilizes fast stream-copy for video (`-c:v copy`) when possible to prevent re-encoding lag.
  Future<String> mergeKhmerVoiceWithVideo({
    required String originalVideoPath,
    required String khmerAudioPath,
    required double duckingVolume, // 0.0 (mute) to 1.0 (full)
    Function(int progressPercentage)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputVideoPath = '${tempDir.path}/khmer_recap_output_$timestamp.mp4';

    // Complex filter:
    // [0:a] is original video audio (ducked to duckingVolume)
    // [1:a] is new Khmer narration (kept prominent at volume 1.1)
    // amix combines both streams seamlessly
    final bgVolume = duckingVolume.clamp(0.0, 1.0).toStringAsFixed(2);
    
    // Check if original video has audio track first
    final mediaInfo = await FFprobeKit.getMediaInformation(originalVideoPath);
    final hasOriginalAudio = mediaInfo.getMediaInformation()?.getStreams().any((s) => s.getType() == 'audio') ?? false;

    String cmd;
    if (hasOriginalAudio && duckingVolume > 0.01) {
      cmd = '-y -i "$originalVideoPath" -i "$khmerAudioPath" '
          '-filter_complex "[0:a]volume=$bgVolume[bg];[1:a]volume=1.15[khmer];[khmer][bg]amix=inputs=2:duration=first:dropout_transition=3[aout]" '
          '-map 0:v:0 -map "[aout]" -c:v copy -c:a aac -b:a 192k -shortest "$outputVideoPath"';
    } else {
      // If ducking volume is 0 or original has no audio, completely replace with Khmer audio
      cmd = '-y -i "$originalVideoPath" -i "$khmerAudioPath" '
          '-map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -shortest "$outputVideoPath"';
    }

    final session = await FFmpegKit.execute(cmd);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      return outputVideoPath;
    } else {
      // If stream copy failed due to container flags, fallback to re-encoding with H.264
      final fallbackCmd = '-y -i "$originalVideoPath" -i "$khmerAudioPath" '
          '-c:v libx264 -preset ultrafast -crf 23 -c:a aac -b:a 192k -shortest "$outputVideoPath"';
      final fallbackSession = await FFmpegKit.execute(fallbackCmd);
      final fallbackReturnCode = await fallbackSession.getReturnCode();

      if (ReturnCode.isSuccess(fallbackReturnCode)) {
        return outputVideoPath;
      }

      final logs = await session.getAllLogsAsString();
      throw Exception('FFmpeg បរាជ័យក្នុងការច្របាច់បញ្ចូលសំឡេង និងវីដេអូ: $logs');
    }
  }

  /// Exports standalone Khmer recap audio to persistent Android storage
  Future<String> exportKhmerAudioFile(String srcAudioPath, String customName) async {
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

  /// Saves the dubbed video to the Movies or Download directory
  Future<String> exportDubbedVideoFile(String srcVideoPath, String customName) async {
    Directory? exportDir;
    if (Platform.isAndroid) {
      exportDir = Directory('/storage/emulated/0/Movies/KhmerRecap');
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }
    } else {
      exportDir = await getApplicationDocumentsDirectory();
    }

    final targetPath = '${exportDir.path}/${customName}_KhmerDubbed.mp4';
    final srcFile = File(srcVideoPath);
    await srcFile.copy(targetPath);
    return targetPath;
  }
}
