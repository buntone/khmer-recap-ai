import 'dart:convert';
import 'dart:io';
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

    // 1. Parallel TTS Synthesis with concurrency pool of 3 for blazing-fast generation
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

    const concurrency = 3;
    final workerBuckets = List.generate(concurrency, (_) => <int>[]);
    for (int i = 0; i < totalSegments; i++) {
      workerBuckets[i % concurrency].add(i);
    }
    await Future.wait(
      List.generate(workerBuckets.length, (bIdx) async {
        if (workerBuckets[bIdx].isEmpty) return;
        if (bIdx > 0) await Future.delayed(Duration(milliseconds: 30 * bIdx));
        await synthesizeWorker(workerBuckets[bIdx]);
      }),
    );

    // Map chunk files by their EXACT segment index to prevent ANY index desynchronization!
    final Map<int, File> chunkFilesMap = {};

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

      // Dynamic Speech Rate Adaptation:
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

      if (availableWindow > 0.3 && dur > (availableWindow - 0.12)) {
        final targetDuration =
            (availableWindow - 0.15).clamp(0.35, availableWindow - 0.05);
        double speedRatio = dur / targetDuration;
        speedRatio = speedRatio.clamp(1.05, 2.0);

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
        }
      }

      chunkFilesMap[i] = finalChunkFile;

      onProgress?.call(
        0.7 + (((i + 1) / totalSegments) * 0.3),
        i + 1,
        totalSegments,
      );
    }

    if (chunkFilesMap.isEmpty) {
      throw Exception(
          'បរាជ័យក្នុងការបង្កើតសំឡេង (Failed to generate voice clips).');
    }

    // 3. Build master PCM audio timeline:
    // Placed at exact millisecond sample offsets to ensure 100% frame-perfect lip sync,
    // zero cumulative drift, and zero cutoffs at the end of the video!
    const sampleRate = 24000;
    const channels = 1;
    const bytesPerSample = 2; // 16-bit mono PCM = 2 bytes per sample
    final totalSamples = (totalDurationSeconds * sampleRate).round();
    final totalPcmBytes = totalSamples * channels * bytesPerSample;
    final masterPcm = Uint8List(totalPcmBytes); // Initialized with 0 (clean digital silence)
    final masterBd = ByteData.view(masterPcm.buffer);

    for (int i = 0; i < totalSegments; i++) {
      final seg = segments[i];
      final chunkFile = chunkFilesMap[i];
      if (chunkFile == null || !await chunkFile.exists()) continue;

      final chunkRawBytes = await chunkFile.readAsBytes();
      if (chunkRawBytes.length <= 44) continue;

      // Extract raw 16-bit PCM samples cleanly without WAV headers or metadata chunks
      final chunkPcm = _extractPcmData(chunkRawBytes);
      if (chunkPcm == null || chunkPcm.isEmpty) continue;

      final chunkSampleCount = chunkPcm.length ~/ bytesPerSample;
      if (chunkSampleCount <= 0) continue;

      final targetStart = (seg.startSeconds + syncDelaySeconds)
          .clamp(0.0, totalDurationSeconds);
      final startSample = (targetStart * sampleRate).round();
      if (startSample >= totalSamples) continue;

      // Calculate available samples to the end of the video timeline
      final availableSamplesToEnd = totalSamples - startSample;
      final copySamples = chunkSampleCount <= availableSamplesToEnd
          ? chunkSampleCount
          : availableSamplesToEnd;
      if (copySamples <= 0) continue;

      final bytesToCopy = copySamples * bytesPerSample;

      // Create a mutable copy of the PCM segment to apply smooth anti-click micro-fades
      final pcmSlice = Uint8List.fromList(chunkPcm.sublist(0, bytesToCopy));
      final bdSlice = ByteData.view(pcmSlice.buffer);

      // 1. Smooth 5ms micro-fade IN (120 samples at 24kHz) to prevent initial step pop/click
      final inFade = copySamples < 120 ? copySamples : 120;
      for (int s = 0; s < inFade; s++) {
        final sampleOffset = s * bytesPerSample;
        final val = bdSlice.getInt16(sampleOffset, Endian.little);
        final factor = s / inFade;
        bdSlice.setInt16(sampleOffset, (val * factor).round().clamp(-32768, 32767), Endian.little);
      }

      // 2. Smooth 10ms micro-fade OUT (240 samples at 24kHz) at end of speech segment
      final outFade = copySamples < 240 ? copySamples : 240;
      final outStart = copySamples - outFade;
      for (int s = 0; s < outFade; s++) {
        final sampleOffset = (outStart + s) * bytesPerSample;
        final val = bdSlice.getInt16(sampleOffset, Endian.little);
        final factor = (outFade - s) / outFade;
        bdSlice.setInt16(sampleOffset, (val * factor).round().clamp(-32768, 32767), Endian.little);
      }

      // 3. Additive PCM Mixing with saturation clamping:
      // Guarantees all sentences are fully audible and prevents abrupt truncation or silence dropouts!
      for (int s = 0; s < copySamples; s++) {
        final targetOffset = (startSample + s) * bytesPerSample;
        if (targetOffset + 2 > totalPcmBytes) break;
        final existing = masterBd.getInt16(targetOffset, Endian.little);
        final incoming = bdSlice.getInt16(s * bytesPerSample, Endian.little);
        final mixed = (existing + incoming).clamp(-32768, 32767);
        masterBd.setInt16(targetOffset, mixed, Endian.little);
      }
    }

    // Write master timeline WAV file with standard 44-byte RIFF header
    final masterWavFile = File('${tempDir.path}/master_timeline_$timestamp.wav');
    final totalFileSize = 36 + totalPcmBytes;
    final masterWavBytes = Uint8List(44 + totalPcmBytes);
    final bd = ByteData.view(masterWavBytes.buffer);

    // RIFF chunk descriptor
    masterWavBytes.setRange(0, 4, 'RIFF'.codeUnits);
    bd.setUint32(4, totalFileSize, Endian.little);
    masterWavBytes.setRange(8, 12, 'WAVE'.codeUnits);

    // fmt subchunk
    masterWavBytes.setRange(12, 16, 'fmt '.codeUnits);
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little); // PCM
    bd.setUint16(22, channels, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(
        28, sampleRate * channels * bytesPerSample, Endian.little); // 48000
    bd.setUint16(32, channels * bytesPerSample, Endian.little); // 2
    bd.setUint16(34, 16, Endian.little); // 16 bits

    // data subchunk
    masterWavBytes.setRange(36, 40, 'data'.codeUnits);
    bd.setUint32(40, totalPcmBytes, Endian.little);

    // Copy raw master PCM data
    masterWavBytes.setRange(44, 44 + totalPcmBytes, masterPcm);
    await masterWavFile.writeAsBytes(masterWavBytes, flush: true);

    // Fast-encode master WAV to high-quality MP3 with multi-threaded FFmpeg
    final outputFile = File('${tempDir.path}/khmer_voice_$timestamp.mp3');
    final mp3Cmd =
        '-y -threads 0 -i "${masterWavFile.path.replaceAll(r'\', '/')}" -c:a libmp3lame -b:a 128k -ar 24000 -ac 1 "${outputFile.path.replaceAll(r'\', '/')}"';
    final session = await FFmpegKit.execute(mp3Cmd);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode) &&
        await outputFile.exists() &&
        (await outputFile.length()) > 500) {
      return outputFile.path;
    }

    // Fallback to AAC
    final fallbackOutputFile =
        File('${tempDir.path}/khmer_voice_$timestamp.aac');
    final fallbackCmd =
        '-y -threads 0 -i "${masterWavFile.path.replaceAll(r'\', '/')}" -c:a aac -b:a 192k "${fallbackOutputFile.path.replaceAll(r'\', '/')}"';
    final fallbackSession = await FFmpegKit.execute(fallbackCmd);
    final fallbackReturnCode = await fallbackSession.getReturnCode();

    if (ReturnCode.isSuccess(fallbackReturnCode) &&
        await fallbackOutputFile.exists()) {
      return fallbackOutputFile.path;
    }

    if (await masterWavFile.exists()) {
      return masterWavFile.path;
    }

    if (chunkFilesMap.isNotEmpty) {
      return chunkFilesMap.values.first.path;
    }
    return masterWavFile.path;
  }

  /// Calculates exact duration of 24000Hz 16-bit mono PCM WAV instantly (48,000 bytes/sec)
  static double _getWavDuration(int fileSizeBytes) {
    if (fileSizeBytes <= 44) return 0.0;
    return (fileSizeBytes - 44) / 48000.0;
  }

  /// Extracts the exact raw 16-bit PCM bytes by properly traversing the RIFF WAV chunks
  /// to locate the 'data' subchunk, preventing header/metadata interpretation as audio clicks!
  static Uint8List? _extractPcmData(Uint8List wavBytes) {
    if (wavBytes.length < 12) return null;
    // Check 'RIFF' and 'WAVE'
    if (wavBytes[0] != 0x52 ||
        wavBytes[1] != 0x49 ||
        wavBytes[2] != 0x46 ||
        wavBytes[3] != 0x46 ||
        wavBytes[8] != 0x57 ||
        wavBytes[9] != 0x41 ||
        wavBytes[10] != 0x56 ||
        wavBytes[11] != 0x45) {
      return wavBytes.length > 44 ? wavBytes.sublist(44) : null;
    }

    final bd = ByteData.view(
        wavBytes.buffer, wavBytes.offsetInBytes, wavBytes.lengthInBytes);
    int offset = 12;

    while (offset + 8 <= wavBytes.length) {
      final chunkId =
          String.fromCharCodes(wavBytes.sublist(offset, offset + 4));
      final chunkSize = bd.getUint32(offset + 4, Endian.little);
      final dataStart = offset + 8;

      if (chunkId == 'data') {
        final dataEnd = (dataStart + chunkSize).clamp(0, wavBytes.length);
        if (dataEnd > dataStart) {
          return wavBytes.sublist(dataStart, dataEnd);
        }
      }

      // Next chunk: chunkSize plus 1 padding byte if chunkSize is odd
      offset = dataStart + chunkSize + (chunkSize % 2);
    }

    // Fallback: search for 'data' signature directly in the file
    for (int i = 12; i <= wavBytes.length - 8; i++) {
      if (wavBytes[i] == 0x64 && // 'd'
          wavBytes[i + 1] == 0x61 && // 'a'
          wavBytes[i + 2] == 0x74 && // 't'
          wavBytes[i + 3] == 0x61) {
        // 'a'
        final chunkSize = bd.getUint32(i + 4, Endian.little);
        final dataStart = i + 8;
        final dataEnd = (dataStart + chunkSize).clamp(0, wavBytes.length);
        if (dataEnd > dataStart) {
          return wavBytes.sublist(dataStart, dataEnd);
        }
      }
    }

    return wavBytes.length > 44 ? wavBytes.sublist(44) : null;
  }

  @visibleForTesting
  static Uint8List? extractPcmDataForTesting(Uint8List wavBytes) =>
      _extractPcmData(wavBytes);


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
        if (RegExp(r'^(?:នេះជា|ខាងក្រោមនេះជា)?\s*(?:ការបកប្រែ|តារាងបកប្រែ|បញ្ជីបកប្រែ)\s*[:៖]?$',
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

      final femaleKeywords = RegExp(
          r'(?:ស្រី|តួស្រី|នារី|ស្ត្រី|ម្ដាយ|ម្តាយ|ម៉ាក់|ម៉ែ|យាយ|លោកយាយ|មីង|អ្នកមីង|ប្រពន្ធ|ភរិយា|កូនស្រី|ប្អូនស្រី|បងស្រី|ចៅស្រី|កញ្ញា|អ្នកនាង|ជំទាវ|អូន|female|woman|girl|\bF\b|女|女主)',
          caseSensitive: false);
      final maleKeywords = RegExp(
          r'(?:ប្រុស|តួប្រុស|បុរស|ឪពុក|ពុក|ប៉ា|លោកប៉ា|តា|លោកតា|ពូ|លោកពូ|ប្ដី|ស្វាមី|កូនប្រុស|ប្អូនប្រុស|បងប្រុស|ចៅប្រុស|អ្នកកំលោះ|លោក|អ្នករៀបរាប់|អ្នកសម្រាយ|male|man|boy|narrator|\bM\b|男|男主)',
          caseSensitive: false);

      // 1. Match any bracketed tag at the start e.g. [ស្រី], 【ស្រី】, (ស្រី), **[ស្រី]**, <ស្រី>
      final bracketMatch = RegExp(
              r'^\s*[\*_]*[\[\(【（<]([^\]\)】）>]+)[\]\)】）>][\*_]*\s*[:៖\-–\s]*')
          .firstMatch(lineText);
      if (bracketMatch != null) {
        final tagContent = bracketMatch.group(1)!.trim();
        if (femaleKeywords.hasMatch(tagContent)) {
          isFemale = true;
          hasExplicitSpeaker = true;
        } else if (maleKeywords.hasMatch(tagContent)) {
          isFemale = false;
          hasExplicitSpeaker = true;
        }
        lineText = lineText.replaceFirst(
            RegExp(r'^\s*[\*_]*[\[\(【（<][^\]\)】）>]+[\]\)】）>][\*_]*\s*[:៖\-–\s]*'),
            '');
      } else {
        // 2. Match unbracketed tag at start e.g. ស្រី: or ប្រុស: or នារី៖
        final plainMatch = RegExp(r'^\s*([^\s:៖\-–]{1,12})\s*[:៖\-–\s]+')
            .firstMatch(lineText);
        if (plainMatch != null) {
          final tagContent = plainMatch.group(1)!.trim();
          if (femaleKeywords.hasMatch(tagContent)) {
            isFemale = true;
            hasExplicitSpeaker = true;
            lineText = lineText.replaceFirst(
                RegExp(r'^\s*([^\s:៖\-–]{1,12})\s*[:៖\-–\s]+'), '');
          } else if (maleKeywords.hasMatch(tagContent)) {
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
        if (femaleKeywords.hasMatch(trimmed)) {
          isFemale = true;
          hasExplicitSpeaker = true;
        } else if (maleKeywords.hasMatch(trimmed)) {
          isFemale = false;
          hasExplicitSpeaker = true;
        }
      }

      // 3. Dialogue content heuristics: If no explicit speaker tag was found,
      // intelligently infer speaker gender from spoken words and kinship references!
      if (!hasExplicitSpeaker) {
        final isFemaleDialogue = RegExp(
          r'(?:(?:^|\s)(?:ម៉ាក់|ម៉ែ|ម្ដាយ|ម្តាយ|អូន|កូនស្រី|ប្អូនស្រី|នាងខ្ញុំ|អ្នកនាង|កញ្ញា)(?:[\s!,?៖:]|$)|(?:បងសម្លាញ់|លោកប្ដី|ប្ដីខ្ញុំ|បងកុំ|បងឯង))',
        ).hasMatch(lineText);

        final isMaleDialogue = RegExp(
          r'(?:(?:^|\s)(?:ប៉ា|ពុក|ឪពុក|បង|កូនប្រុស|ប្អូនប្រុស)(?:[\s!,?៖:]|$)|(?:អូនសម្លាញ់|ប្រពន្ធខ្ញុំ|អូនកុំ|អូនឯង))',
        ).hasMatch(lineText);

        if (isFemaleDialogue && !isMaleDialogue) {
          isFemale = true;
          hasExplicitSpeaker = true;
        } else if (isMaleDialogue && !isFemaleDialogue) {
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

      // Eliminate any unwanted "សម្រាយរឿង" / "សម្រាយសាច់រឿង" intro narration prefixes
      cleanLine = cleanLine
          .replaceFirst(
              RegExp(
                  r'^(?:ការសម្រាយរឿង|សម្រាយសាច់រឿង|សម្រាយរឿង|អ្នកសម្រាយរឿង|សម្រាយ)\s*[:៖\-–\s]*',
                  caseSensitive: false),
              '')
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

  /// Sends request to Microsoft Edge Neural TTS or Custom Khmer TTS engine with auto-retry
  /// Sends request to Microsoft Edge Neural TTS or Custom Khmer TTS engine with auto-retry
  Future<List<int>> _callTtsEndpoint({
    required String text,
    required String voiceId,
    required double speed,
    required double pitch,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      return [];
    }

    // 1. Primary: Microsoft Neural Edge-TTS v2 (Piseth & Sreymom) - Fast & ultra natural
    final selectedEdgeVoice = voiceId.toLowerCase().contains('sreymom')
        ? 'km-KH-SreymomNeural'
        : 'km-KH-PisethNeural';

    final ratePercent = ((speed - 1.0) * 100).round();
    final rateStr = ratePercent >= 0 ? '+$ratePercent%' : '$ratePercent%';

    try {
      final audioBytes = await EdgeTtsV2.synthesize(
        text: cleanText,
        voice: selectedEdgeVoice,
        rate: rateStr,
      );

      if (audioBytes.isNotEmpty && audioBytes.length > 200) {
        return audioBytes;
      }
    } catch (e) {
      debugPrint('Edge-TTS note for "$cleanText": $e');
    }

    // 2. Custom User-Configured REST Endpoint (if configured)
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
        'text': cleanText,
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
            .timeout(const Duration(seconds: 4));

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
                  .timeout(const Duration(seconds: 4));
              return downloadRes.bodyBytes;
            }
          } catch (_) {}

          return response.bodyBytes;
        }
      } catch (_) {}
    }

    // 3. Fallback: Ultra-fast Google Khmer TTS (200-300ms)
    try {
      final encodedText = Uri.encodeComponent(cleanText);
      final gTtsUri = Uri.parse(
        'https://translate.googleapis.com/translate_tts?client=gtx&ie=UTF-8&tl=km&q=$encodedText',
      );
      final gResponse = await http.get(
        gTtsUri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ).timeout(const Duration(milliseconds: 2500));

      if (gResponse.statusCode == 200 && gResponse.bodyBytes.length > 80) {
        return gResponse.bodyBytes;
      }
    } catch (_) {}

    // Fallback tw-ob client
    try {
      final encodedText = Uri.encodeComponent(cleanText);
      final fallbackUri = Uri.parse(
        'https://translate.google.com/translate_tts?ie=UTF-8&tl=km&client=tw-ob&q=$encodedText',
      );
      final fallbackRes = await http.get(
        fallbackUri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ).timeout(const Duration(milliseconds: 2500));
      if (fallbackRes.statusCode == 200 && fallbackRes.bodyBytes.length > 80) {
        return fallbackRes.bodyBytes;
      }
    } catch (_) {}

    throw Exception(
        'មិនអាចទាញយកសំឡេងអានជាភាសាខ្មែរបានឡើយ (Failed to synthesize Khmer speech).');
  }
}
