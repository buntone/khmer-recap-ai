import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

enum KhmerVoice {
  prasith, // Male Voice
  sreymom, // Female Voice
}

extension KhmerVoiceExtension on KhmerVoice {
  String get displayName {
    switch (this) {
      case KhmerVoice.prasith:
        return '🎙️ សំឡេងប្រសិទ្ធ (ប្រុស)';
      case KhmerVoice.sreymom:
        return '🎙️ សំឡេងស្រីមុំ (ស្រី)';
    }
  }

  String get shortName {
    switch (this) {
      case KhmerVoice.prasith:
        return 'Prasith (Male)';
      case KhmerVoice.sreymom:
        return 'Sreymom (Female)';
    }
  }
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

  /// Converts Khmer recap script to high-quality .mp3 audio file
  /// Returns the absolute path of the generated audio file
  Future<String> synthesizeKhmerSpeech({
    required String text,
    required KhmerVoice voice,
    double speed = 1.05,
    double pitch = 1.0,
    Function(double progress)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputFile = File('${tempDir.path}/khmer_voice_$timestamp.mp3');

    final voiceId = (voice == KhmerVoice.prasith) ? prasithVoiceId : sreymomVoiceId;

    // Split text into manageable paragraphs/chunks if it's very long
    final chunks = _splitTextIntoChunks(text, 500);
    final List<int> combinedAudioBytes = [];

    for (int i = 0; i < chunks.length; i++) {
      final chunkText = chunks[i].trim();
      if (chunkText.isEmpty) continue;

      final chunkBytes = await _callTtsEndpoint(
        text: chunkText,
        voiceId: voiceId,
        speed: speed,
        pitch: pitch,
      );

      combinedAudioBytes.addAll(chunkBytes);

      if (onProgress != null) {
        onProgress((i + 1) / chunks.length);
      }
    }

    if (combinedAudioBytes.isEmpty) {
      throw Exception('មិនទទួលបានទិន្នន័យសំឡេងពី Khmer TTS Service ឡើយ។');
    }

    await outputFile.writeAsBytes(combinedAudioBytes, flush: true);
    return outputFile.path;
  }

  /// Sends HTTP POST request to the Khmer TTS engine
  Future<List<int>> _callTtsEndpoint({
    required String text,
    required String voiceId,
    required double speed,
    required double pitch,
  }) async {
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
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // If server returns raw mp3 bytes
        if (response.headers['content-type']?.contains('audio') == true ||
            response.headers['content-type']?.contains('octet-stream') == true) {
          return response.bodyBytes;
        }

        // If server returns JSON with base64 audio
        try {
          final jsonData = jsonDecode(utf8.decode(response.bodyBytes));
          if (jsonData is Map && jsonData.containsKey('audio_base64')) {
            return base64Decode(jsonData['audio_base64']);
          } else if (jsonData is Map && jsonData.containsKey('audio_url')) {
            // Download audio from returned URL
            final downloadRes = await http.get(Uri.parse(jsonData['audio_url']));
            return downloadRes.bodyBytes;
          }
        } catch (_) {}

        // Fallback to body bytes
        return response.bodyBytes;
      } else {
        throw Exception(
          'Khmer TTS Request Failed [HTTP ${response.statusCode}]: ${response.body}',
        );
      }
    } catch (e) {
      // If server unreachable or error, handle with informative exception
      throw Exception('បរាជ័យក្នុងការតភ្ជាប់ទៅកាន់ Khmer TTS Engine: $e');
    }
  }

  /// Splits long narration texts by sentences or punctuation
  List<String> _splitTextIntoChunks(String text, int maxChars) {
    if (text.length <= maxChars) {
      return [text];
    }

    final List<String> chunks = [];
    final sentences = text.split(RegExp(r'(?<=[។\n!?])\s*'));
    StringBuffer currentChunk = StringBuffer();

    for (final sentence in sentences) {
      if (currentChunk.length + sentence.length > maxChars && currentChunk.isNotEmpty) {
        chunks.add(currentChunk.toString());
        currentChunk = StringBuffer();
      }
      currentChunk.write('$sentence ');
    }

    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk.toString());
    }

    return chunks;
  }
}
