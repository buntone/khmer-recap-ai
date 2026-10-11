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
    Key? key,
    required this.dubbedVideoPath,
    required this.originalVideoPath,
    required this.khmerAudioPath,
    required this.generatedScript,
    required this.selectedVoice,
    required this.duckingVolume,
    required this.settingsService,
  }) : super(key: key);

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  VideoPlayerController? _videoPlayerController;
  late TextEditingController _scriptController;
  late String _currentDubbedVideoPath;
  late String _currentKhmerAudioPath;

  bool _isScriptExpanded = false;
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
      final savedPath = await _ffmpegService.exportDubbedVideoFile(
        _currentDubbedVideoPath,
        'Recap_${DateTime.now().millisecondsSinceEpoch}',
      );
      _showSnackbar('បានរក្សាទុកវីដេអូទៅកាន់ Movies/KhmerRecap ដោយជោគជ័យ!\n($savedPath)', isSuccess: true);
    } catch (e) {
      _showSnackbar('បរាជ័យក្នុងការរក្សាទុកវីដេអូ: $e', isSuccess: false);
    }
  }

  Future<void> _shareVideo() async {
    try {
      final file = XFile(_currentDubbedVideoPath);
      await Share.shareXFiles([file], text: 'វីដេអូសម្រាយរឿងកុនផលិតដោយ Khmer Recap AI Studio');
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
      await Share.shareXFiles([XFile(scriptFile.path)], text: 'អត្ថបទសម្រាយរឿងខ្មែរ');
      _showSnackbar('បាននាំចេញអត្ថបទសម្រាយរឿងជាឯកសារ .txt រួចរាល់!', isSuccess: true);
    } catch (e) {
      _showSnackbar('បរាជ័យក្នុងការនាំចេញអត្ថបទ: $e', isSuccess: false);
    }
  }

  Future<void> _reGenerateVoiceAndRemux() async {
    final newScript = _scriptController.text.trim();
    if (newScript.isEmpty) {
      _showSnackbar('សូមបញ្ចូលអត្ថបទសម្រាយរឿងជាមុនសិន!', isSuccess: false);
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

      final newAudioPath = await ttsService.synthesizeKhmerSpeech(
        text: newScript,
        voice: widget.selectedVoice,
      );

      final newVideoPath = await _ffmpegService.mergeKhmerVoiceWithVideo(
        originalVideoPath: widget.originalVideoPath,
        khmerAudioPath: newAudioPath,
        duckingVolume: widget.duckingVolume,
      );

      _currentKhmerAudioPath = newAudioPath;
      _currentDubbedVideoPath = newVideoPath;

      await _initVideoPlayer(_currentDubbedVideoPath);

      _showSnackbar('បានកែប្រែ និងបញ្ចូលសំឡេងថ្មីដោយជោគជ័យ!', isSuccess: true);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('លទ្ធផលសម្រាយរឿង (Recap Studio Result)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
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
                            color: Colors.white.withOpacity(0.85),
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
                  // Action buttons grid
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.download_rounded, color: Colors.white),
                          label: const Text('រក្សាទុកក្នុង Gallery', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _saveToGallery,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.audiotrack_rounded, color: Colors.white),
                          label: const Text('Export Audio (.mp3)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8B5CF6),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _exportAudio,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.description_outlined, color: Colors.amberAccent),
                      label: const Text('Export Script (.txt / .srt)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _exportScript,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Collapsible & Editable Script Section
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: const Icon(Icons.article_rounded, color: Colors.amberAccent),
                          title: const Text(
                            'អត្ថបទសម្រាយរឿងខ្មែរ (Khmer Recap Script)',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          subtitle: Text(
                            _isScriptExpanded ? 'ចុចដើម្បីបង្រួញ ឬកែសម្រួល' : 'ចុចដើម្បីពិនិត្យ និងកែសម្រួលអត្ថបទ',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                          trailing: Icon(
                            _isScriptExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                            color: Colors.white70,
                          ),
                          onTap: () => setState(() => _isScriptExpanded = !_isScriptExpanded),
                        ),
                        if (_isScriptExpanded) ...[
                          const Divider(color: Colors.white10, height: 1),
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  controller: _scriptController,
                                  maxLines: 10,
                                  style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.6),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: const Color(0xFF0F172A),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                    hintText: 'សរសេរ ឬកែសម្រួលអត្ថបទនៅទីនេះ...',
                                    hintStyle: const TextStyle(color: Colors.white24),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  icon: _isReGenerating
                                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Icon(Icons.refresh_rounded),
                                  label: Text(
                                    _isReGenerating ? 'កំពុងបង្កើតសំឡេងឡើងវិញ...' : '🔄 បង្កើតសំឡេងឡើងវិញ (Re-generate Voice & Mux)',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF6366F1),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onPressed: _isReGenerating ? null : _reGenerateVoiceAndRemux,
                                ),
                              ],
                            ),
                          ),
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
