import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'edge_tts_v2.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

enum KhmerVoice {
  autoDialogue, // Auto switch male/female dialogue
  prasith,      // Male Voice
  sreymom,      // Female Voice
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

class _DialogueSegment {
  final double startSeconds;
  final double? endSeconds;
  final String voiceId;
  final String text;

  _DialogueSegment({
    required this.startSeconds,
    this.endSeconds,
    required this.voiceId,
    required this.text,
  });
}

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
    final List<File> chunkFiles = [];
    final List<double> chunkDurations = [];

    // Synthesize each dialogue segment and normalize to standard 24kHz WAV
    for (int i = 0; i < totalSegments; i++) {
      final seg = segments[i];
      onProgress?.call(i / totalSegments, i + 1, totalSegments);

      final chunkBytes = await _callTtsEndpoint(
        text: seg.text,
        voiceId: seg.voiceId,
        speed: speed,
        pitch: pitch,
      );

      final rawChunk = File('${tempDir.path}/raw_${timestamp}_$i.mp3');
      await rawChunk.writeAsBytes(chunkBytes, flush: true);

      // Convert chunk to standard PCM WAV (24000Hz mono) to ensure flawless timing and sample compatibility
      final normFile = File('${tempDir.path}/norm_${timestamp}_$i.wav');
      final normCmd = '-y -i "${rawChunk.path.replaceAll(r'\', '/')}" -ar 24000 -ac 1 "${normFile.path.replaceAll(r'\', '/')}"';
      final normSession = await FFmpegKit.execute(normCmd);
      await normSession.getReturnCode();

      final actualFile = (await normFile.exists() && (await normFile.length()) > 100) ? normFile : rawChunk;

      // Probe audio duration of synthesized chunk
      double dur = 1.5;
      try {
        final mediaInfo = await FFprobeKit.getMediaInformation(actualFile.path);
        final durStr = mediaInfo.getMediaInformation()?.getDuration();
        if (durStr != null) {
          dur = double.tryParse(durStr) ?? (seg.text.length * 0.08);
        }
      } catch (_) {
        dur = seg.text.length * 0.08;
      }

      // Dynamic Speech Rate Adaptation:
      // Calculate available window before the next character's dialogue or the end of the video
      final currentStart = (seg.startSeconds + syncDelaySeconds).clamp(0.0, totalDurationSeconds);
      final nextStart = (i + 1 < totalSegments)
          ? (segments[i + 1].startSeconds + syncDelaySeconds).clamp(0.0, totalDurationSeconds)
          : totalDurationSeconds;

      double availableWindow = nextStart - currentStart;
      if (seg.endSeconds != null) {
        final explicitSceneDur = ((seg.endSeconds! + syncDelaySeconds).clamp(0.0, totalDurationSeconds) - currentStart);
        if (explicitSceneDur > 0.6 && explicitSceneDur < availableWindow) {
          availableWindow = explicitSceneDur;
        }
      }

      File finalChunkFile = actualFile;
      double finalDur = dur;

      // Dynamic Speech Rate Adaptation:
      // If synthesized speech exceeds the available window, accelerate speech rate proportionally with FFmpeg atempo.
      // This completely eliminates truncating/chopping words ("លែងដាច់ពាក្យ ក្រវាត់ពាក្យ") while keeping lip-sync!
      if (availableWindow > 0.4 && dur > (availableWindow - 0.10)) {
        final targetDuration = (availableWindow - 0.15).clamp(0.4, availableWindow);
        double speedRatio = dur / targetDuration;
        
        // Dynamically accelerate long sentences up to 1.95x so all words fit without getting truncated!
        speedRatio = speedRatio.clamp(1.05, 1.95);

        String tempoFilter;
        if (speedRatio <= 2.0) {
          tempoFilter = 'atempo=${speedRatio.toStringAsFixed(2)}';
        } else {
          tempoFilter = 'atempo=1.5,atempo=${(speedRatio / 1.5).toStringAsFixed(2)}';
        }

        final tempoFile = File('${tempDir.path}/tempo_${timestamp}_$i.wav');
        final tempoCmd = '-y -i "${actualFile.path.replaceAll(r'\', '/')}" -filter:a "$tempoFilter" -ar 24000 -ac 1 "${tempoFile.path.replaceAll(r'\', '/')}"';
        final tempoSession = await FFmpegKit.execute(tempoCmd);
        if (ReturnCode.isSuccess(await tempoSession.getReturnCode()) && await tempoFile.exists()) {
          finalChunkFile = tempoFile;
          try {
            final tInfo = await FFprobeKit.getMediaInformation(tempoFile.path);
            final tDurStr = tInfo.getMediaInformation()?.getDuration();
            if (tDurStr != null) {
              finalDur = double.tryParse(tDurStr) ?? (dur / speedRatio);
            } else {
              finalDur = dur / speedRatio;
            }
          } catch (_) {
            finalDur = dur / speedRatio;
          }
        }
      }

      chunkFiles.add(finalChunkFile);
      chunkDurations.add(finalDur);

      onProgress?.call((i + 1) / totalSegments, i + 1, totalSegments);
    }

    // Build timeline playlist by inserting silence gaps to ensure perfect lip-sync
    final List<File> timelinePlaylist = [];
    double currentTimelinePos = 0.0;

    for (int i = 0; i < totalSegments; i++) {
      final seg = segments[i];
      final chunkFile = chunkFiles[i];
      final chunkDur = chunkDurations[i];

      final targetStart = (seg.startSeconds + syncDelaySeconds).clamp(0.0, totalDurationSeconds);

      // If targetStart is ahead of current timeline position, insert silence gap
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

    if (timelinePlaylist.isEmpty) {
      return chunkFiles.first.path;
    }

    // Fast-concatenate playlist with FFmpeg with re-encoding to standardized MP3
    // Note: -t $durLimit guarantees the audio strictly never extends past video duration
    final durLimit = totalDurationSeconds.toStringAsFixed(2);
    final outputFile = File('${tempDir.path}/khmer_voice_$timestamp.mp3');
    final concatListFile = File('${tempDir.path}/concat_list_$timestamp.txt');
    final concatContent = timelinePlaylist
        .map((f) => "file '${f.path.replaceAll(r'\', '/')}'")
        .join('\n');
    await concatListFile.writeAsString(concatContent);

    final concatCmd = '-y -f concat -safe 0 -i "${concatListFile.path.replaceAll(r'\', '/')}" -t $durLimit -c:a libmp3lame -b:a 128k -ar 24000 -ac 1 "${outputFile.path.replaceAll(r'\', '/')}"';
    final session = await FFmpegKit.execute(concatCmd);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode) && await outputFile.exists() && (await outputFile.length()) > 500) {
      return outputFile.path;
    }

    // Fallback concat with re-encoding to AAC
    final fallbackOutputFile = File('${tempDir.path}/khmer_voice_$timestamp.aac');
    final fallbackCmd = '-y -f concat -safe 0 -i "${concatListFile.path.replaceAll(r'\', '/')}" -t $durLimit -c:a aac -b:a 192k "${fallbackOutputFile.path.replaceAll(r'\', '/')}"';
    final fallbackSession = await FFmpegKit.execute(fallbackCmd);
    final fallbackReturnCode = await fallbackSession.getReturnCode();

    if (ReturnCode.isSuccess(fallbackReturnCode) && await fallbackOutputFile.exists()) {
      return fallbackOutputFile.path;
    }

    if (await outputFile.exists()) {
      return outputFile.path;
    }

    return chunkFiles.first.path;
  }

  /// Generates a silence WAV file of exact duration using FFmpeg lavfi
  Future<File> _generateSilenceFile(double durationSeconds, String outputPath) async {
    final dur = durationSeconds.toStringAsFixed(3);
    final cmd = '-y -f lavfi -i anullsrc=r=24000:cl=mono -t $dur -ar 24000 -ac 1 "$outputPath"';
    final session = await FFmpegKit.execute(cmd);
    await session.getReturnCode();
    return File(outputPath);
  }

  /// Parses timestamps like "00:00:02,800", "01:28", "88.5" into total seconds
  static double? _parseTimeToSeconds(String? timeStr) {
    if (timeStr == null) return null;
    var s = timeStr.trim().replaceAll('[', '').replaceAll(']', '').replaceAll('(', '').replaceAll(')', '');
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

    final lines = cleanInput.split('\n');
    final List<_DialogueSegment> segments = [];

    final timePattern = RegExp(
      r'\[?\(?(\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d+)?)(?:\s*(?:-->|[-–])\s*(\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d+)?))?\)?\]?'
    );

    final genericTagStartPattern = RegExp(
      r'^\s*[\*_]*\[?(?:(?:តួ)?(?:ប្រុស|ស្រី|បុរស|នារី|ស្ត្រី)|អ្នករៀបរាប់|male|female|man|woman|boy|girl|narrator|\b[MF]\b)\]?[\*_]*\s*[:៖\-–\s]+',
      caseSensitive: false,
    );

    double? pendingStartSeconds;
    double? pendingEndSeconds;
    double currentTimestamp = 0.0;
    bool hasSeenFirstTimestamp = false;

    for (final line in lines) {
      var trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Skip SRT block numbers (e.g. "1", "2")
      if (RegExp(r'^\d+$').hasMatch(trimmed)) continue;

      // Skip lines that are purely JSON syntax or code
      if (trimmed == '{' || trimmed == '}' || trimmed == '[' || trimmed == ']' || trimmed == '},') continue;
      if (RegExp(r'^"(?:time|speaker|gender|segments|dialogue|text)":', caseSensitive: false).hasMatch(trimmed)) {
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
        if (trimmed.contains('ការបកប្រែ') ||
            trimmed.contains('ខាងក្រោមនេះ') ||
            trimmed.contains('សាច់រឿង') ||
            trimmed.contains('បញ្ចូលសំឡេង') ||
            trimmed.contains('Timestamp') ||
            trimmed.endsWith('៖') ||
            trimmed.endsWith(':')) {
          continue;
        }
      }

      if (!hasKhmer) continue;

      final startSeconds = pendingStartSeconds ?? currentTimestamp;
      final endSeconds = pendingEndSeconds;
      pendingStartSeconds = null;
      pendingEndSeconds = null;

      var lineText = trimmed.replaceAll(timePattern, '').trim();

      bool isFemale = false;
      bool hasExplicitSpeaker = false;

      // 1. Match any bracketed tag at the start e.g. [ស្រីចាស់], [ប្រុសចាស់], [ស្រី], [ប្រុស], [F], [M], [យាយ], [ម៉ាក់]
      final bracketMatch = RegExp(r'^\s*\[([^\]]+)\]\s*[:៖\-–\s]*').firstMatch(lineText);
      if (bracketMatch != null) {
        final tagContent = bracketMatch.group(1)!.trim();
        if (RegExp(r'(?:ស្រី|នារី|ស្ត្រី|ម្ដាយ|ម៉ាក់|យាយ|female|woman|girl|\bF\b)', caseSensitive: false).hasMatch(tagContent)) {
          isFemale = true;
          hasExplicitSpeaker = true;
        } else if (RegExp(r'(?:ប្រុស|បុរស|ឪពុក|ប៉ា|តា|អ្នករៀបរាប់|male|man|boy|narrator|\bM\b)', caseSensitive: false).hasMatch(tagContent)) {
          isFemale = false;
          hasExplicitSpeaker = true;
        }
        lineText = lineText.replaceFirst(RegExp(r'^\s*\[([^\]]+)\]\s*[:៖\-–\s]*'), '');
      } else {
        // 2. Match unbracketed tag at start e.g. ស្រីចាស់: or ប្រុស: or F:
        final plainMatch = RegExp(r'^\s*([^\s:៖\-–]{1,12})\s*[:៖\-–\s]+').firstMatch(lineText);
        if (plainMatch != null) {
          final tagContent = plainMatch.group(1)!.trim();
          if (RegExp(r'(?:ស្រី|នារី|ស្ត្រី|ម្ដាយ|ម៉ាក់|យាយ|female|woman|girl|^F$)', caseSensitive: false).hasMatch(tagContent)) {
            isFemale = true;
            hasExplicitSpeaker = true;
            lineText = lineText.replaceFirst(RegExp(r'^\s*([^\s:៖\-–]{1,12})\s*[:៖\-–\s]+'), '');
          } else if (RegExp(r'(?:ប្រុស|បុរស|ឪពុក|ប៉ា|តា|អ្នករៀបរាប់|male|man|boy|narrator|^M$)', caseSensitive: false).hasMatch(tagContent)) {
            isFemale = false;
            hasExplicitSpeaker = true;
            lineText = lineText.replaceFirst(RegExp(r'^\s*([^\s:៖\-–]{1,12})\s*[:៖\-–\s]+'), '');
          }
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
        }
      }

      // Clean text: strip brackets, quotes, leftover colons
      var cleanLine = lineText
          .replaceAll(RegExp(r'["{}\[\]]'), '')
          .replaceAll(RegExp(r'^[:៖\-–\s]+'), '')
          .trim();

      if (cleanLine.isNotEmpty && RegExp(r'[\u1780-\u17FF]').hasMatch(cleanLine)) {
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

    if (segments.isEmpty) {
      final fallbackClean = cleanInput
          .replaceFirst(genericTagStartPattern, '')
          .replaceAll(RegExp(r'["{}\[\]]'), '')
          .trim();
      if (fallbackClean.isNotEmpty && RegExp(r'[\u1780-\u17FF]').hasMatch(fallbackClean)) {
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
        if (apiToken.trim().isNotEmpty) 'Authorization': 'Bearer ${apiToken.trim()}',
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
        final response = await http.post(
          uri,
          headers: headers,
          body: body,
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          if (response.headers['content-type']?.contains('audio') == true ||
              response.headers['content-type']?.contains('octet-stream') == true) {
            return response.bodyBytes;
          }

          try {
            final jsonData = jsonDecode(utf8.decode(response.bodyBytes));
            if (jsonData is Map && jsonData.containsKey('audio_base64')) {
              return base64Decode(jsonData['audio_base64']);
            } else if (jsonData is Map && jsonData.containsKey('audio_url')) {
              final downloadRes = await http.get(Uri.parse(jsonData['audio_url'])).timeout(const Duration(seconds: 10));
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

    throw Exception('មិនអាចទាញយកសំឡេងអានជាភាសាខ្មែរបានឡើយ (Failed to synthesize Khmer speech).');
  }
}
