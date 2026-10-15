import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../services/ffmpeg_service.dart';
import '../services/khmer_tts_service.dart';
import '../services/settings_service.dart';

class ResultScreen extends StatefulWidget {
  final String dubbedVideoPath;
  final String originalVideoPath;
  final String khmerAudioPath;
  final String generatedScript;
  final KhmerVoice selectedVoice;
  final double duckingVolume;
  final SettingsService settingsService;

  const ResultScreen({
    super.key,
    required this.dubbedVideoPath,
    required this.originalVideoPath,
    required this.khmerAudioPath,
    required this.generatedScript,
    required this.selectedVoice,
    required this.duckingVolume,
    required this.settingsService,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  VideoPlayerController? _videoPlayerController;
  late TextEditingController _scriptController;
  late String _currentDubbedVideoPath;
  late String _currentKhmerAudioPath;

  bool _isReGenerating = false;
  final FFmpegService _ffmpegService = FFmpegService();

  @override
  void initState() {
    super.initState();
    _currentDubbedVideoPath = widget.dubbedVideoPath;
    _currentKhmerAudioPath = widget.khmerAudioPath;
    _scriptController = TextEditingController(text: widget.generatedScript);
    _initVideoPlayer(_currentDubbedVideoPath);
  }

  Future<void> _initVideoPlayer(String path) async {
    await _videoPlayerController?.dispose();
    _videoPlayerController = VideoPlayerController.file(File(path));
    await _videoPlayerController!.initialize();
    await _videoPlayerController!.play();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    _scriptController.dispose();
    super.dispose();
  }

  Future<void> _saveToGallery() async {
    try {
      final savedPath = await _ffmpegService.autoSaveToGallery(
        _currentDubbedVideoPath,
        customName: 'Recap_${DateTime.now().millisecondsSinceEpoch}',
      );
      _showSnackbar('បានរក្សាទុកវីដេអូទៅក្នុង Gallery ទូរស័ព្ទ (DCIM/KhmerRecap) រួចរាល់!\n($savedPath)', isSuccess: true);
    } catch (e) {
      _showSnackbar('បរាជ័យក្នុងការរក្សាទុកវីដេអូ: $e', isSuccess: false);
    }
  }

  Future<void> _shareVideo() async {
    try {
      final file = XFile(_currentDubbedVideoPath);
      await Share.shareXFiles([file], text: 'វីដេអូបកប្រែ និងបញ្ចូលសំឡេងភាពយន្តផលិតដោយ Khmer Recap AI Studio');
    } catch (e) {
      _showSnackbar('បរាជ័យក្នុងការចែករំលែក: $e', isSuccess: false);
    }
  }

  Future<void> _exportAudio() async {
    try {
      final savedPath = await _ffmpegService.exportKhmerAudioFile(
        _currentKhmerAudioPath,
        'Voiceover_${DateTime.now().millisecondsSinceEpoch}',
      );
      _showSnackbar('បានទាញយកសំឡេងខ្មែរ (.mp3) ទៅកាន់ Download Folder:\n$savedPath', isSuccess: true);
    } catch (e) {
      _showSnackbar('បរាជ័យក្នុងការរក្សាទុកសំឡេង: $e', isSuccess: false);
    }
  }

  Future<void> _exportScript() async {
    try {
      final tempDir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      final scriptFile = File('${tempDir.path}/Khmer_Recap_Script_${DateTime.now().millisecondsSinceEpoch}.txt');
      await scriptFile.writeAsString(_scriptController.text.trim());
      await Share.shareXFiles([XFile(scriptFile.path)], text: 'អត្ថបទបកប្រែសន្ទនាខ្មែរ');
      _showSnackbar('បាននាំចេញអត្ថបទបកប្រែសន្ទនាជាឯកសារ .txt រួចរាល់!', isSuccess: true);
    } catch (e) {
      _showSnackbar('បរាជ័យក្នុងការនាំចេញអត្ថបទ: $e', isSuccess: false);
    }
  }

  Future<void> _reGenerateVoiceAndRemux() async {
    final newScript = _scriptController.text.trim();
    if (newScript.isEmpty) {
      _showSnackbar('សូមបញ្ចូលអត្ថបទបកប្រែសន្ទនាជាមុនសិន!', isSuccess: false);
      return;
    }

    setState(() => _isReGenerating = true);

    try {
      final ttsService = KhmerTtsService(
        endpoint: widget.settingsService.ttsEndpoint,
        apiToken: widget.settingsService.ttsApiToken,
        prasithVoiceId: widget.settingsService.voicePrasithId,
        sreymomVoiceId: widget.settingsService.voiceSreymomId,
      );

      final videoMeta = await _ffmpegService.probeVideo(widget.originalVideoPath);
      final newAudioPath = await ttsService.synthesizeKhmerSpeech(
        text: newScript,
        voice: widget.selectedVoice,
        totalDurationSeconds: videoMeta.durationSeconds,
        syncDelaySeconds: widget.settingsService.audioSyncDelay,
      );

      final newVideoPath = await _ffmpegService.mergeKhmerVoiceWithVideo(
        originalVideoPath: widget.originalVideoPath,
        khmerAudioPath: newAudioPath,
        duckingVolume: widget.duckingVolume,
      );

      // Auto-save re-generated video directly to phone Gallery (DCIM/KhmerRecap)
      String finalNewVideoPath = newVideoPath;
      try {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final savedPath = await _ffmpegService.autoSaveToGallery(
          newVideoPath,
          customName: 'KhmerRecap_Regen_$timestamp',
        );
        finalNewVideoPath = savedPath;
      } catch (_) {}

      _currentKhmerAudioPath = newAudioPath;
      _currentDubbedVideoPath = finalNewVideoPath;

      await _initVideoPlayer(_currentDubbedVideoPath);

      _showSnackbar('បានបង្កើតសំឡេងថ្មី និងរក្សាទុកក្នុង Gallery រួចរាល់!', isSuccess: true);
    } catch (e) {
      _showSnackbar('កំហុសអំឡុងពេលបង្កើតសំឡេងឡើងវិញ: $e', isSuccess: false);
    } finally {
      if (mounted) setState(() => _isReGenerating = false);
    }
  }

  void _showSnackbar(String message, {required bool isSuccess}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isSuccess ? Icons.check_circle : Icons.error, color: isSuccess ? Colors.greenAccent : Colors.redAccent),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  bool _isEditingScript = false;

  Widget _buildDialogueLinesPreview() {
    final rawLines = _scriptController.text.split('\n');
    final validLines = rawLines.where((l) => l.trim().isNotEmpty).toList();

    if (validLines.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16.0),
        child: Center(
          child: Text('មិនមានអត្ថបទសន្ទនាទេ', style: TextStyle(color: Colors.white38, fontSize: 12)),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: validLines.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final line = validLines[index].trim();
        final timeMatch = RegExp(r'\[(\d{1,2}:\d{2}(?::\d{2})?)\]').firstMatch(line);
        final timeStr = timeMatch?.group(1);

        final isFemale = line.contains('[ស្រី]') || line.contains('ស្រី:');
        final isMale = line.contains('[ប្រុស]') || line.contains('ប្រុស:');

        var textOnly = line
            .replaceAll(RegExp(r'\[\d{1,2}:\d{2}(?::\d{2})?\]'), '')
            .replaceAll('[ប្រុស]:', '')
            .replaceAll('[ស្រី]:', '')
            .replaceAll('[ប្រុស]', '')
            .replaceAll('[ស្រី]', '')
            .replaceAll(RegExp(r'^[:៖\-–\s]+'), '')
            .trim();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isFemale
                  ? Colors.pinkAccent.withValues(alpha: 0.35)
                  : (isMale ? Colors.blueAccent.withValues(alpha: 0.35) : Colors.white12),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (timeStr != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '⏱ $timeStr',
                        style: const TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (isFemale || isMale)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isFemale
                            ? Colors.pinkAccent.withValues(alpha: 0.15)
                            : Colors.blueAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isFemale ? '👩 ស្រី' : '👨 ប្រុស',
                        style: TextStyle(
                          color: isFemale ? Colors.pinkAccent : Colors.lightBlueAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Text(
                    '#${index + 1}',
                    style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                textOnly,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('លទ្ធផលបកប្រែ និងបញ្ចូលសំឡេង', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Colors.blueAccent),
            tooltip: 'ចែករំលែក (Share)',
            onPressed: _shareVideo,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Video Player Area
            Container(
              color: Colors.black,
              height: 250,
              child: _videoPlayerController != null && _videoPlayerController!.value.isInitialized
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: _videoPlayerController!.value.aspectRatio,
                          child: VideoPlayer(_videoPlayerController!),
                        ),
                        IconButton(
                          iconSize: 52,
                          icon: Icon(
                            _videoPlayerController!.value.isPlaying
                                ? Icons.pause_circle_filled_rounded
                                : Icons.play_circle_fill_rounded,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                          onPressed: () {
                            setState(() {
                              _videoPlayerController!.value.isPlaying
                                  ? _videoPlayerController!.pause()
                                  : _videoPlayerController!.play();
                            });
                          },
                        ),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: VideoProgressIndicator(
                            _videoPlayerController!,
                            allowScrubbing: true,
                            colors: const VideoProgressColors(
                              playedColor: Colors.amber,
                              bufferedColor: Colors.white24,
                              backgroundColor: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    )
                  : const Center(child: CircularProgressIndicator(color: Colors.amber)),
            ),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Auto-Saved to Gallery Notice Banner
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF064E3B).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.6)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: Color(0xFF34D399), size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'បានរក្សាទុកក្នុង Gallery ទូរស័ព្ទស្វ័យប្រវត្តិ (DCIM/KhmerRecap)',
                            style: TextStyle(
                              color: Color(0xFFD1FAE5),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Action buttons row (Equal height 48 & no overflow)
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.download_rounded, color: Colors.white, size: 18),
                            label: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('រក្សាទុក Gallery', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _saveToGallery,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.audiotrack_rounded, color: Colors.white, size: 18),
                            label: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('ទាញយក MP3', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8B5CF6),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _exportAudio,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.description_outlined, color: Colors.amberAccent, size: 18),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('ទាញយកអត្ថបទបកប្រែ (.txt / .srt)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5)),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _exportScript,
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Structured Dialogue Section Container
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    padding: const EdgeInsets.all(14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.article_rounded, color: Colors.amberAccent, size: 20),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'អត្ថបទបកប្រែសន្ទនាខ្មែរ',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => setState(() => _isEditingScript = !_isEditingScript),
                              icon: Icon(_isEditingScript ? Icons.visibility_rounded : Icons.edit_note_rounded, size: 16, color: Colors.cyanAccent),
                              label: Text(
                                _isEditingScript ? 'មើលក្រឡោន' : 'កែសម្រួល',
                                style: const TextStyle(color: Colors.cyanAccent, fontSize: 11.5, fontWeight: FontWeight.bold),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                backgroundColor: Colors.cyanAccent.withValues(alpha: 0.1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Divider(color: Colors.white10, height: 1),
                        const SizedBox(height: 12),

                        if (_isEditingScript) ...[
                          TextField(
                            controller: _scriptController,
                            maxLines: 8,
                            style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              hintText: 'សរសេរ ឬកែសម្រួលអត្ថបទនៅទីនេះ...',
                              hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 48,
                            child: ElevatedButton.icon(
                              icon: _isReGenerating
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.refresh_rounded, size: 20),
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _isReGenerating ? 'កំពុងបង្កើតសំឡេងឡើងវិញ...' : '🔄 បង្កើតសំឡេងឡើងវិញ (Re-generate)',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _isReGenerating ? null : _reGenerateVoiceAndRemux,
                            ),
                          ),
                        ] else ...[
                          _buildDialogueLinesPreview(),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
