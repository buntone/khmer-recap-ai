import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'edge_tts_v2.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

enum KhmerVoice {
  autoDialogue, // Auto switch male/female dialogue
  prasith, // Male Voice
  sreymom, // Female Voice
}

extension KhmerVoiceExtension on KhmerVoice {
  String get displayName {
    switch (this) {
      case KhmerVoice.autoDialogue:
        return '🎭 ឆ្លាស់សំឡេងស្វ័យប្រវត្តិ (ប្រុស & ស្រី)';
      case KhmerVoice.prasith:
        return '🎙️ សំឡេងប្រសិទ្ធ (ប្រុស)';
      case KhmerVoice.sreymom:
        return '🎙️ សំឡេងស្រីមុំ (ស្រី)';
    }
  }

  String get shortName {
    switch (this) {
      case KhmerVoice.autoDialogue:
        return 'Auto (Male & Female)';
      case KhmerVoice.prasith:
        return 'Prasith (Male)';
      case KhmerVoice.sreymom:
        return 'Sreymom (Female)';
    }
  }
}

class DialogueSegmentItem {
  final double startSeconds;
  final double? endSeconds;
  final String voiceId;
  final String text;

  DialogueSegmentItem({
    required this.startSeconds,
    this.endSeconds,
    required this.voiceId,
    required this.text,
  });
}

typedef _DialogueSegment = DialogueSegmentItem;

class KhmerTtsService {
  final String endpoint;
  final String apiToken;
  final String prasithVoiceId;
  final String sreymomVoiceId;

  KhmerTtsService({
    required this.endpoint,
    required this.apiToken,
    required this.prasithVoiceId,
    required this.sreymomVoiceId,
  });

  @visibleForTesting
  List<DialogueSegmentItem> parseDialogueSegmentsForTesting(
          String text, KhmerVoice voice) =>
      _parseDialogueSegments(text, voice);

  /// Converts Khmer recap script to timeline-synchronized narration audio matching exact video seconds
  Future<String> synthesizeKhmerSpeech({
    required String text,
    required KhmerVoice voice,
    double speed = 1.05,
    double pitch = 1.0,
    double totalDurationSeconds = 60.0,
    double syncDelaySeconds = 0.0,
    Function(double progress, int current, int total)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // Parse text into timestamped dialogue segments
    final segments = _parseDialogueSegments(text, voice);
    if (segments.isEmpty) {
      throw Exception('មិនមានអត្ថបទសម្រាប់អានសំឡេងឡើយ។');
    }

    final totalSegments = segments.length;
    final List<List<int>?> rawBytesList = List.filled(totalSegments, null);
    int completedTts = 0;

    // 1. Parallel TTS Synthesis with concurrency pool of 4
    Future<void> synthesizeWorker(List<int> indices) async {
      for (final idx in indices) {
        final seg = segments[idx];
        try {
          final bytes = await _callTtsEndpoint(
            text: seg.text,
            voiceId: seg.voiceId,
            speed: speed,
            pitch: pitch,
          );
          rawBytesList[idx] = bytes;
        } catch (e) {
          debugPrint('TTS segment $idx failed: $e');
        }
        completedTts++;
        onProgress?.call(
          (completedTts / totalSegments) * 0.7,
          completedTts,
          totalSegments,
        );
      }
    }

    const concurrency = 4;
    final workerBuckets = List.generate(concurrency, (_) => <int>[]);
    for (int i = 0; i < totalSegments; i++) {
      workerBuckets[i % concurrency].add(i);
    }
    await Future.wait(
      workerBuckets
          .where((bucket) => bucket.isNotEmpty)
          .map((bucket) => synthesizeWorker(bucket)),
    );

    final List<File> chunkFiles = [];
    final List<double> chunkDurations = [];

    // 2. Normalize chunks and calculate accurate durations
    for (int i = 0; i < totalSegments; i++) {
      final seg = segments[i];
      final chunkBytes = rawBytesList[i] ?? [];
      if (chunkBytes.isEmpty) continue;

      final rawChunk = File('${tempDir.path}/raw_${timestamp}_$i.mp3');
      await rawChunk.writeAsBytes(chunkBytes, flush: true);

      // Convert chunk to standard PCM WAV (24000Hz mono) with multi-threading
      final normFile = File('${tempDir.path}/norm_${timestamp}_$i.wav');
      final normCmd =
          '-y -threads 0 -i "${rawChunk.path.replaceAll(r'\', '/')}" -ar 24000 -ac 1 "${normFile.path.replaceAll(r'\', '/')}"';
      final normSession = await FFmpegKit.execute(normCmd);
      await normSession.getReturnCode();

      final actualFile =
          (await normFile.exists() && (await normFile.length()) > 100)
              ? normFile
              : rawChunk;

      // Fast duration check (instant calculation for WAV, probe fallback only if needed)
      double dur = 1.5;
      if (actualFile == normFile) {
        dur = _getWavDuration(await normFile.length());
      } else {
        try {
          final mediaInfo =
              await FFprobeKit.getMediaInformation(actualFile.path);
          final durStr = mediaInfo.getMediaInformation()?.getDuration();
          if (durStr != null) {
            dur = double.tryParse(durStr) ?? (seg.text.length * 0.08);
          }
        } catch (_) {
          dur = seg.text.length * 0.08;
        }
      }

      // Dynamic Speech Rate Adaptation & Strict Anti-Overlap:
      final currentStart = (seg.startSeconds + syncDelaySeconds)
          .clamp(0.0, totalDurationSeconds);
      final nextStart = (i + 1 < totalSegments)
          ? (segments[i + 1].startSeconds + syncDelaySeconds)
              .clamp(0.0, totalDurationSeconds)
          : totalDurationSeconds;

      double availableWindow = nextStart - currentStart;
      if (seg.endSeconds != null) {
        final explicitSceneDur = ((seg.endSeconds! + syncDelaySeconds)
                .clamp(0.0, totalDurationSeconds) -
            currentStart);
        if (explicitSceneDur > 0.6 && explicitSceneDur < availableWindow) {
          availableWindow = explicitSceneDur;
        }
      }

      File finalChunkFile = actualFile;
      double finalDur = dur;

      if (availableWindow > 0.3 && dur > (availableWindow - 0.12)) {
        final targetDuration =
            (availableWindow - 0.15).clamp(0.35, availableWindow - 0.05);
        double speedRatio = dur / targetDuration;
        speedRatio = speedRatio.clamp(1.05, 2.2);

        String tempoFilter;
        if (speedRatio <= 2.0) {
          tempoFilter = 'atempo=${speedRatio.toStringAsFixed(2)}';
        } else {
          tempoFilter =
              'atempo=1.5,atempo=${(speedRatio / 1.5).toStringAsFixed(2)}';
        }

        final tempoFile = File('${tempDir.path}/tempo_${timestamp}_$i.wav');
        final tempoCmd =
            '-y -threads 0 -i "${actualFile.path.replaceAll(r'\', '/')}" -filter:a "$tempoFilter" -ar 24000 -ac 1 "${tempoFile.path.replaceAll(r'\', '/')}"';
        final tempoSession = await FFmpegKit.execute(tempoCmd);
        if (ReturnCode.isSuccess(await tempoSession.getReturnCode()) &&
            await tempoFile.exists()) {
          finalChunkFile = tempoFile;
          finalDur = _getWavDuration(await tempoFile.length());
        }
      }

      chunkFiles.add(finalChunkFile);
      chunkDurations.add(finalDur);

      onProgress?.call(
        0.7 + (((i + 1) / totalSegments) * 0.3),
        i + 1,
        totalSegments,
      );
    }

    if (chunkFiles.isEmpty) {
      throw Exception('បរាជ័យក្នុងការបង្កើតសំឡេង (Failed to generate voice clips).');
    }

    // Build timeline playlist by inserting pure Dart silence gaps to ensure perfect lip-sync
    final List<File> timelinePlaylist = [];
    double currentTimelinePos = 0.0;

    for (int i = 0; i < chunkFiles.length; i++) {
      final seg = segments[i];
      final chunkFile = chunkFiles[i];
      final chunkDur = chunkDurations[i];

      final targetStart = (seg.startSeconds + syncDelaySeconds)
          .clamp(0.0, totalDurationSeconds);

      // If targetStart is ahead of current timeline position, insert silence gap instantly
      if (targetStart > currentTimelinePos) {
        final gap = targetStart - currentTimelinePos;
        if (gap >= 0.03) {
          final silFile = File('${tempDir.path}/sil_${timestamp}_$i.wav');
          await _generateSilenceFile(gap, silFile.path);
          if (await silFile.exists()) {
            timelinePlaylist.add(silFile);
          }
        }
        currentTimelinePos = targetStart;
      }

      timelinePlaylist.add(chunkFile);
      currentTimelinePos += chunkDur;
    }

    // Trailing silence to match full video length
    if (totalDurationSeconds > currentTimelinePos) {
      final tailGap = totalDurationSeconds - currentTimelinePos;
      if (tailGap >= 0.05) {
        final tailFile = File('${tempDir.path}/tail_$timestamp.wav');
        await _generateSilenceFile(tailGap, tailFile.path);
        if (await tailFile.exists()) {
          timelinePlaylist.add(tailFile);
        }
      }
    }

    // Fast-concatenate playlist with multi-threaded FFmpeg
    final durLimit = totalDurationSeconds.toStringAsFixed(2);
    final outputFile = File('${tempDir.path}/khmer_voice_$timestamp.mp3');
    final concatListFile = File('${tempDir.path}/concat_list_$timestamp.txt');
    final concatContent = timelinePlaylist
        .map((f) => "file '${f.path.replaceAll(r'\', '/')}'")
        .join('\n');
    await concatListFile.writeAsString(concatContent);

    final concatCmd =
        '-y -threads 0 -f concat -safe 0 -i "${concatListFile.path.replaceAll(r'\', '/')}" -t $durLimit -c:a libmp3lame -b:a 128k -ar 24000 -ac 1 "${outputFile.path.replaceAll(r'\', '/')}"';
    final session = await FFmpegKit.execute(concatCmd);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode) &&
        await outputFile.exists() &&
        (await outputFile.length()) > 500) {
      return outputFile.path;
    }

    // Fallback concat with AAC
    final fallbackOutputFile =
        File('${tempDir.path}/khmer_voice_$timestamp.aac');
    final fallbackCmd =
        '-y -threads 0 -f concat -safe 0 -i "${concatListFile.path.replaceAll(r'\', '/')}" -t $durLimit -c:a aac -b:a 192k "${fallbackOutputFile.path.replaceAll(r'\', '/')}"';
    final fallbackSession = await FFmpegKit.execute(fallbackCmd);
    final fallbackReturnCode = await fallbackSession.getReturnCode();

    if (ReturnCode.isSuccess(fallbackReturnCode) &&
        await fallbackOutputFile.exists()) {
      return fallbackOutputFile.path;
    }

    if (await outputFile.exists()) {
      return outputFile.path;
    }

    return chunkFiles.first.path;
  }

  /// Calculates exact duration of 24000Hz 16-bit mono PCM WAV instantly (48,000 bytes/sec)
  static double _getWavDuration(int fileSizeBytes) {
    if (fileSizeBytes <= 44) return 0.0;
    return (fileSizeBytes - 44) / 48000.0;
  }

  /// Generates a standard PCM WAV silence file instantly in pure Dart without FFmpeg
  static Future<File> _generateSilenceFile(
      double durationSeconds, String outputPath) async {
    const sampleRate = 24000;
    const channels = 1;
    const bitsPerSample = 16;
    const bytesPerSample = bitsPerSample ~/ 8;
    final numSamples = (durationSeconds * sampleRate).round();
    final dataSize = numSamples * channels * bytesPerSample;
    final totalSize = 36 + dataSize;

    final bytes = Uint8List(44 + dataSize);
    final bd = ByteData.view(bytes.buffer);

    // RIFF chunk descriptor
    bytes.setRange(0, 4, 'RIFF'.codeUnits);
    bd.setUint32(4, totalSize, Endian.little);
    bytes.setRange(8, 12, 'WAVE'.codeUnits);

    // fmt subchunk
    bytes.setRange(12, 16, 'fmt '.codeUnits);
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little); // PCM format
    bd.setUint16(22, channels, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, sampleRate * channels * bytesPerSample, Endian.little); // 48000
    bd.setUint16(32, channels * bytesPerSample, Endian.little); // 2
    bd.setUint16(34, bitsPerSample, Endian.little); // 16

    // data subchunk
    bytes.setRange(36, 40, 'data'.codeUnits);
    bd.setUint32(40, dataSize, Endian.little);

    final file = File(outputPath);
    await file.writeAsBytes(bytes, flush: true);
    return file;
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

  /// Parses raw script into timestamped dialogue segments for male and female voices
  List<_DialogueSegment> _parseDialogueSegments(String text, KhmerVoice mode) {
    final cleanInput = text.trim();
    if (cleanInput.isEmpty) return [];

    // Preprocess text to ensure every speaker tag or timestamp tag begins on a separate line
    // This prevents male and female dialogues from being accidentally merged into a single line
    final preprocessedText = cleanInput
        .replaceAllMapped(
          RegExp(
              r'([^\n])\s*(\[\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d+)?(?:\s*(?:-->|[-–])\s*\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d+)?)?\])'),
          (m) => '${m[1]}\n${m[2]}',
        )
        .replaceAllMapped(
          RegExp(
              r'([^\n])\s*(\[?(?:តួ)?(?:ប្រុស|ស្រី|បុរស|នារី|ស្ត្រី|អ្នករៀបរាប់|male|female|man|woman|boy|girl|\b[MF]\b)\]?[:៖])',
              caseSensitive: false),
          (m) => '${m[1]}\n${m[2]}',
        );

    final lines = preprocessedText.split('\n');
    final List<_DialogueSegment> segments = [];

    final timePattern = RegExp(
        r'\[?\(?(\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d+)?)(?:\s*(?:-->|[-–])\s*(\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d+)?))?\)?\]?');

    final genericTagStartPattern = RegExp(
      r'^\s*[\*_]*\[?(?:(?:តួ)?(?:ប្រុស|ស្រី|បុរស|នារី|ស្ត្រី)|អ្នករៀបរាប់|male|female|man|woman|boy|girl|narrator|\b[MF]\b)\]?[\*_]*\s*[:៖\-–\s]+',
      caseSensitive: false,
    );

    double? pendingStartSeconds;
    double? pendingEndSeconds;
    double currentTimestamp = 0.0;
    bool hasSeenFirstTimestamp = false;
    String activeSpeakerVoiceId = prasithVoiceId;
    bool hasFoundFirstSpeaker = false;

    for (final line in lines) {
      var trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      // Skip SRT block numbers (e.g. "1", "2")
      if (RegExp(r'^\d+$').hasMatch(trimmed)) {
        continue;
      }

      // Skip lines that are purely JSON syntax or code
      if (trimmed == '{' ||
          trimmed == '}' ||
          trimmed == '[' ||
          trimmed == ']' ||
          trimmed == '},') {
        continue;
      }
      if (RegExp(r'^"(?:time|speaker|gender|segments|dialogue|text)":',
              caseSensitive: false)
          .hasMatch(trimmed)) {
        final valMatch = RegExp(r':\s*"(.*)"?,?$').firstMatch(trimmed);
        if (valMatch != null) {
          trimmed = valMatch.group(1) ?? '';
        } else {
          continue;
        }
      }

      // Check if line contains a timestamp (SRT or [MM:SS] or [MM:SS - MM:SS])
      final tMatch = timePattern.firstMatch(trimmed);
      if (tMatch != null) {
        final sVal = _parseTimeToSeconds(tMatch.group(1));
        final eVal = _parseTimeToSeconds(tMatch.group(2));
        if (sVal != null) {
          pendingStartSeconds = sVal;
          pendingEndSeconds = eVal;
          currentTimestamp = sVal;
          hasSeenFirstTimestamp = true;
        }
      }

      final hasKhmer = RegExp(r'[\u1780-\u17FF]').hasMatch(trimmed);

      // Filter conversational AI preambles before first timestamp
      if (!hasSeenFirstTimestamp && hasKhmer && tMatch == null) {
        if (RegExp(
                r'^(?:នេះជា|ខាងក្រោមនេះជា)?\s*(?:ការបកប្រែ|តារាងបកប្រែ|បញ្ជីបកប្រែ)\s*[:៖]?$',
                caseSensitive: false)
            .hasMatch(trimmed) ||
            trimmed.startsWith('```') ||
            trimmed.startsWith('Translation:') ||
            trimmed.startsWith('Here is')) {
          continue;
        }
        // Actual intro narration or thoughts before timestamp -> start at 00:01
        pendingStartSeconds = 1.0;
        currentTimestamp = 1.0;
        hasSeenFirstTimestamp = true;
      }

      if (!hasKhmer) continue;

      final startSeconds = pendingStartSeconds ?? currentTimestamp;
      final endSeconds = pendingEndSeconds;
      pendingStartSeconds = null;
      pendingEndSeconds = null;

      var lineText = trimmed.replaceAll(timePattern, '').trim();

      bool isFemale = false;
      bool hasExplicitSpeaker = false;

      // 1. Match any bracketed tag at the start e.g. [ស្រី], [ប្រុស], [អ្នករៀបរាប់], [សម្រាយ], [អ្នកសម្រាយ], [ក្នុងចិត្ត]
      final bracketMatch =
          RegExp(r'^\s*\[([^\]]+)\]\s*[:៖\-–\s]*').firstMatch(lineText);
      if (bracketMatch != null) {
        final tagContent = bracketMatch.group(1)!.trim();
        if (RegExp(
                r'(?:ស្រី|នារី|ស្ត្រី|ម្ដាយ|ម៉ាក់|យាយ|female|woman|girl|\bF\b)',
                caseSensitive: false)
            .hasMatch(tagContent)) {
          isFemale = true;
          hasExplicitSpeaker = true;
        } else if (RegExp(
                r'(?:ប្រុស|បុរស|ឪពុក|ប៉ា|តា|អ្នករៀបរាប់|អ្នកសម្រាយ|សម្រាយ|male|man|boy|narrator|\bM\b)',
                caseSensitive: false)
            .hasMatch(tagContent)) {
          isFemale = false;
          hasExplicitSpeaker = true;
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
            hasExplicitSpeaker = true;
            lineText = lineText.replaceFirst(
                RegExp(r'^\s*([^\s:៖\-–]{1,12})\s*[:៖\-–\s]+'), '');
          } else if (RegExp(
                  r'(?:ប្រុស|បុរស|ឪពុក|ប៉ា|តា|អ្នករៀបរាប់|អ្នកសម្រាយ|សម្រាយ|male|man|boy|narrator|^M$)',
                  caseSensitive: false)
              .hasMatch(tagContent)) {
            isFemale = false;
            hasExplicitSpeaker = true;
            lineText = lineText.replaceFirst(
                RegExp(r'^\s*([^\s:៖\-–]{1,12})\s*[:៖\-–\s]+'), '');
          }
        }
      }

      // Check for story recap narration without explicit tag
      final bool isRecap = RegExp(
        r'(?:សម្រាយ|អ្នកសម្រាយ|អ្នករៀបរាប់)',
        caseSensitive: false,
      ).hasMatch(trimmed);

      if (isRecap && !hasExplicitSpeaker) {
        isFemale = false;
        hasExplicitSpeaker = true;
      }

      // If untagged inner monologue, check for gender context cues
      if (!hasExplicitSpeaker &&
          RegExp(r'(?:ក្នុងចិត្ត|គិតក្នុងចិត្ត|内心|心想|独白)').hasMatch(trimmed)) {
        if (RegExp(r'(?:នាង|ម៉ាក់|ម៉ែ|កូនស្រី|ប្អូនស្រី|ស្ត្រី|យាយ)').hasMatch(trimmed)) {
          isFemale = true;
          hasExplicitSpeaker = true;
        } else if (RegExp(r'(?:បង|ពុក|ប៉ា|កូនប្រុស|ប្អូនប្រុស|បុរស|តា)').hasMatch(trimmed)) {
          isFemale = false;
          hasExplicitSpeaker = true;
        }
      }

      String lineVoiceId = prasithVoiceId;
      if (mode == KhmerVoice.sreymom) {
        lineVoiceId = sreymomVoiceId;
      } else if (mode == KhmerVoice.prasith) {
        lineVoiceId = prasithVoiceId;
      } else {
        // Auto dialogue mode:
        if (hasExplicitSpeaker) {
          lineVoiceId = isFemale ? sreymomVoiceId : prasithVoiceId;
          activeSpeakerVoiceId = lineVoiceId;
          hasFoundFirstSpeaker = true;
        } else {
          // If no explicit tag, continue with current active speaker or fallback to male
          lineVoiceId =
              hasFoundFirstSpeaker ? activeSpeakerVoiceId : prasithVoiceId;
        }
      }

      // Clean text: strip brackets, quotes, leftover colons
      var cleanLine = lineText
          .replaceAll(RegExp(r'["{}\[\]]'), '')
          .replaceAll(RegExp(r'^[:៖\-–\s]+'), '')
          .trim();

      if (cleanLine.isNotEmpty &&
          RegExp(r'[\u1780-\u17FF]').hasMatch(cleanLine)) {
        segments.add(_DialogueSegment(
          startSeconds: startSeconds,
          endSeconds: endSeconds,
          voiceId: lineVoiceId,
          text: cleanLine,
        ));
      }
    }

    // Sort by timestamp in chronological order
    segments.sort((a, b) => a.startSeconds.compareTo(b.startSeconds));

    // Ensure non-overlapping timestamps (minimum 1.2s spacing between dialogue lines)
    for (int i = 0; i < segments.length - 1; i++) {
      if (segments[i + 1].startSeconds < segments[i].startSeconds + 1.2) {
        segments[i + 1] = _DialogueSegment(
          startSeconds: segments[i].startSeconds + 1.2,
          endSeconds: segments[i + 1].endSeconds,
          voiceId: segments[i + 1].voiceId,
          text: segments[i + 1].text,
        );
      }
    }

    if (segments.isEmpty) {
      final fallbackClean = cleanInput
          .replaceFirst(genericTagStartPattern, '')
          .replaceAll(RegExp(r'["{}\[\]]'), '')
          .trim();
      if (fallbackClean.isNotEmpty &&
          RegExp(r'[\u1780-\u17FF]').hasMatch(fallbackClean)) {
        segments.add(_DialogueSegment(
          startSeconds: 0.0,
          voiceId: prasithVoiceId,
          text: fallbackClean,
        ));
      }
    }

    return segments;
  }

  /// Sends request to Microsoft Edge Neural TTS or Custom Khmer TTS engine
  Future<List<int>> _callTtsEndpoint({
    required String text,
    required String voiceId,
    required double speed,
    required double pitch,
  }) async {
    // 1. Primary High-Quality Natural Voice: Microsoft Neural Edge-TTS v2 (Piseth & Sreymom)
    try {
      final selectedEdgeVoice = voiceId.toLowerCase().contains('sreymom')
          ? 'km-KH-SreymomNeural'
          : 'km-KH-PisethNeural';

      final ratePercent = ((speed - 1.0) * 100).round();
      final rateStr = ratePercent >= 0 ? '+$ratePercent%' : '$ratePercent%';

      final audioBytes = await EdgeTtsV2.synthesize(
        text: text.trim(),
        voice: selectedEdgeVoice,
        rate: rateStr,
      );

      if (audioBytes.isNotEmpty) {
        return audioBytes;
      }
    } catch (_) {
      // Fallback if Edge-TTS has connection issue
    }

    // 2. Custom User-Configured REST Endpoint (e.g., KhmerVoice.ai, CamCyber)
    if (endpoint.isNotEmpty && !endpoint.contains('api.khmervoice.ai')) {
      final uri = Uri.parse(endpoint);
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'audio/mpeg, audio/mp3, application/octet-stream',
        if (apiToken.trim().isNotEmpty)
          'Authorization': 'Bearer ${apiToken.trim()}',
        if (apiToken.trim().isNotEmpty) 'x-api-key': apiToken.trim(),
      };

      final body = jsonEncode({
        'text': text,
        'voice': voiceId,
        'voice_id': voiceId,
        'language': 'km-KH',
        'speed': speed,
        'pitch': pitch,
        'format': 'mp3',
      });

      try {
        final response = await http
            .post(
              uri,
              headers: headers,
              body: body,
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          if (response.headers['content-type']?.contains('audio') == true ||
              response.headers['content-type']?.contains('octet-stream') ==
                  true) {
            return response.bodyBytes;
          }

          try {
            final jsonData = jsonDecode(utf8.decode(response.bodyBytes));
            if (jsonData is Map && jsonData.containsKey('audio_base64')) {
              return base64Decode(jsonData['audio_base64']);
            } else if (jsonData is Map && jsonData.containsKey('audio_url')) {
              final downloadRes = await http
                  .get(Uri.parse(jsonData['audio_url']))
                  .timeout(const Duration(seconds: 10));
              return downloadRes.bodyBytes;
            }
          } catch (_) {}

          return response.bodyBytes;
        }
      } catch (_) {}
    }

    // 3. Fallback: Google Khmer TTS (Fast and reliable backup)
    try {
      final encodedText = Uri.encodeComponent(text.trim());
      final gTtsUri = Uri.parse(
        'https://translate.google.com/translate_tts?ie=UTF-8&tl=km&client=tw-ob&q=$encodedText',
      );
      final gResponse = await http.get(
        gTtsUri,
        headers: {'User-Agent': 'Mozilla/5.0 (Android; Mobile)'},
      ).timeout(const Duration(seconds: 10));

      if (gResponse.statusCode == 200 && gResponse.bodyBytes.isNotEmpty) {
        return gResponse.bodyBytes;
      }
    } catch (_) {}

    throw Exception(
        'មិនអាចទាញយកសំឡេងអានជាភាសាខ្មែរបានឡើយ (Failed to synthesize Khmer speech).');
  }
}
