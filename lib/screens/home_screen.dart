import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;

import '../services/settings_service.dart';
import '../services/gemini_recap_service.dart';
import '../services/khmer_tts_service.dart';
import '../services/ffmpeg_service.dart';
import 'result_screen.dart';
import 'settings_screen.dart';

enum ProcessingStage {
  idle,
  analyzingVideo, // 1. កំពុងវិភាគវីដេអូ (Analyzing Video)
  writingScript, // 2. កំពុងសរសេរអត្ថបទសម្រាយ (Writing Khmer Script)
  generatingVoice, // 3. កំពុងបំប្លែងសំឡេង (Generating Voice)
  mergingAudioVideo // 4. កំពុងបញ្ចូលសំឡេងក្នុងវីដេអូ (Merging Audio & Video)
}

class HomeScreen extends StatefulWidget {
  final SettingsService settingsService;

  const HomeScreen({super.key, required this.settingsService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _selectedVideoPath;
  VideoPlayerController? _previewController;
  VideoMetadata? _videoMetadata;

  KhmerVoice _selectedVoice = KhmerVoice.autoDialogue;
  double _duckingVolume = 0.0; // 0.0 = Mute original Chinese audio completely

  bool _isProcessing = false;
  ProcessingStage _currentStage = ProcessingStage.idle;
  String _statusMessage = '';

  final FFmpegService _ffmpegService = FFmpegService();
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _duckingVolume = widget.settingsService.defaultDuckingVolume;
  }

  @override
  void dispose() {
    _previewController?.dispose();
    super.dispose();
  }

  Future<void> _pickVideoFile() async {
    // Request storage / media permissions
    if (Platform.isAndroid) {
      await [
        Permission.videos,
        Permission.storage,
      ].request();
    }

    final XFile? video =
        await _imagePicker.pickVideo(source: ImageSource.gallery);

    if (video != null && video.path.isNotEmpty) {
      final path = video.path;
      setState(() {
        _selectedVideoPath = path;
      });

      await _setupVideoPreview(path);
    }
  }

  Future<void> _setupVideoPreview(String path) async {
    _previewController?.dispose();
    _previewController = VideoPlayerController.file(File(path));

    await _previewController!.initialize();
    final meta = await _ffmpegService.probeVideo(path);

    if (mounted) {
      setState(() {
        _videoMetadata = meta;
      });
    }
  }

  Future<void> _startRecapPipeline() async {
    if (_selectedVideoPath == null) {
      _showSnackbar('សូមជ្រើសរើសវីដេអូជាមុនសិន!', isError: true);
      return;
    }

    final hasApiKey = widget.settingsService.geminiApiKey.trim().isNotEmpty;
    if (!hasApiKey) {
      _showSnackbar(
          'សូមកំណត់ Gemini API Key នៅក្នុង Settings ជាមុនសិន ដើម្បីឱ្យ AI បកប្រែភាសាចិនក្នុងវីដេអូ!',
          isError: true);
      _openSettings();
      return;
    }

    // Pause preview video player during processing to release ExoPlayer decoder buffers and RAM
    try {
      await _previewController?.pause();
    } catch (_) {}

    setState(() {
      _isProcessing = true;
      _currentStage = ProcessingStage.analyzingVideo;
      _statusMessage =
          'កំពុងរៀបចំ និងបង្រួមវីដេអូសម្រាប់ Gemini AI ពិនិត្យមើលរូបភាព និងអក្សររត់...';
    });

    try {
      // Step 2: Extract visual video / audio for Gemini
      final mediaPath =
          await _ffmpegService.prepareMediaForGemini(_selectedVideoPath!);
      final mimeType = mediaPath.endsWith('.mp4') ? 'video/mp4' : 'audio/mp3';

      // Step 3: Send to Gemini for Chinese Dialogue Translation & Dubbing
      setState(() {
        _currentStage = ProcessingStage.writingScript;
        _statusMessage =
            'Gemini AI កំពុងមើលវីដេអូ អានអក្សររត់ និងបកប្រែសាច់រឿងជាភាសាខ្មែរ...';
      });

      final geminiService =
          GeminiRecapService(apiKeys: widget.settingsService.geminiApiKeys);
      final duration = _videoMetadata?.durationSeconds ?? 60.0;

      final khmerScript = await geminiService.generateKhmerRecapScript(
        mediaPath: mediaPath,
        videoDurationSeconds: duration,
        mimeType: mimeType,
      );

      // Step 4: Khmer TTS Voiceover Generation
      setState(() {
        _currentStage = ProcessingStage.generatingVoice;
        _statusMessage =
            'កំពុងបំប្លែងអត្ថបទទៅជាសំឡេង ${_selectedVoice.displayName}...';
      });

      final ttsService = KhmerTtsService(
        endpoint: widget.settingsService.ttsEndpoint,
        apiToken: widget.settingsService.ttsApiToken,
        prasithVoiceId: widget.settingsService.voicePrasithId,
        sreymomVoiceId: widget.settingsService.voiceSreymomId,
      );

      final khmerAudioPath = await ttsService.synthesizeKhmerSpeech(
        text: khmerScript,
        voice: _selectedVoice,
        totalDurationSeconds: duration,
        syncDelaySeconds: widget.settingsService.audioSyncDelay,
        onProgress: (progress, current, total) {
          if (mounted) {
            setState(() {
              _statusMessage =
                  'កំពុងបង្កើតសំឡេងឃ្លាទី $current/$total (${(progress * 100).toInt()}%)...';
            });
          }
        },
      );

      // Step 5: Merge final audio with video (audio ducking & vocal isolation)
      setState(() {
        _currentStage = ProcessingStage.mergingAudioVideo;
        _statusMessage =
            'កំពុងច្របាច់បញ្ចូលសំឡេងខ្មែរជាមួយវីដេអូ និងកាត់សំឡេងចិនដើម...';
      });

      final dubbedVideoPath = await _ffmpegService.mergeKhmerVoiceWithVideo(
        originalVideoPath: _selectedVideoPath!,
        khmerAudioPath: khmerAudioPath,
        duckingVolume: _duckingVolume,
        watermarkText: widget.settingsService.watermarkEnabled
            ? widget.settingsService.watermarkText
            : null,
        watermarkFont: widget.settingsService.watermarkFont,
        watermarkColor: widget.settingsService.watermarkColor,
        watermarkOpacity: widget.settingsService.watermarkOpacity,
        scriptText: khmerScript,
        subtitleEnabled: widget.settingsService.subtitleEnabled,
        subtitleColor: widget.settingsService.subtitleColor,
      );

      // Auto-save dubbed video directly to phone Gallery (DCIM/KhmerRecap)
      setState(() {
        _statusMessage =
            'កំពុងរក្សាទុកវីដេអូស្វ័យប្រវត្តិចូល Gallery ទូរស័ព្ទ...';
      });

      String finalGalleryVideoPath = dubbedVideoPath;
      try {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final baseName = p.basenameWithoutExtension(_selectedVideoPath!);
        final savedPath = await _ffmpegService.autoSaveToGallery(
          dubbedVideoPath,
          customName: '${baseName}_Recap_$timestamp',
        );
        finalGalleryVideoPath = savedPath;
      } catch (e) {
        debugPrint('Auto-save to gallery warning: $e');
      }

      // Pipeline Complete - Navigate to Result Screen
      setState(() {
        _isProcessing = false;
        _currentStage = ProcessingStage.idle;
      });

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            dubbedVideoPath: finalGalleryVideoPath,
            originalVideoPath: _selectedVideoPath!,
            khmerAudioPath: khmerAudioPath,
            generatedScript: khmerScript,
            selectedVoice: _selectedVoice,
            duckingVolume: _duckingVolume,
            settingsService: widget.settingsService,
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _currentStage = ProcessingStage.idle;
      });
      _showSnackbar('ដំណើរការបរាជ័យ: $e', isError: true);
    }
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(settingsService: widget.settingsService),
      ),
    );
  }

  void _showSnackbar(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? Colors.redAccent.shade700 : const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                boxShadow: [
                  BoxShadow(
                    color: Colors.cyanAccent.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.asset(
                  'assets/images/app_logo.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.movie_filter_rounded,
                      color: Colors.amberAccent,
                      size: 22),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Khmer Dubbing Studio',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'AI Chinese to Khmer Voiceover',
                    style: TextStyle(fontSize: 10, color: Colors.cyanAccent),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded, color: Colors.cyanAccent),
            tooltip: 'ការកំណត់ (Settings)',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Video Picker / Preview Card
            _buildVideoPickerCard(),

            const SizedBox(height: 20),

            // Voice Selector Section
            _buildVoiceSelectorCard(),

            const SizedBox(height: 24),

            // Big Action Button
            _buildActionButton(),

            const SizedBox(height: 20),

            // Real-time Stage Progress Indicator
            if (_isProcessing) _buildPipelineProgressTracker(),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPickerCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          if (_selectedVideoPath == null) ...[
            InkWell(
              onTap: _pickVideoFile,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.video_library_rounded,
                          size: 48, color: Colors.amber),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'ជ្រើសរើសវីដេអូរឿងកុន (Select Video)',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'គាំទ្រឯកសារ .mp4, .mkv, .mov (Chinese recap video)',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            // Video Preview
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18)),
              child: AspectRatio(
                aspectRatio: _previewController?.value.aspectRatio ?? 16 / 9,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_previewController != null &&
                        _previewController!.value.isInitialized)
                      VideoPlayer(_previewController!)
                    else
                      const Center(
                          child:
                              CircularProgressIndicator(color: Colors.amber)),
                    // Play/Pause Overlay Button
                    IconButton(
                      iconSize: 54,
                      icon: Icon(
                        _previewController?.value.isPlaying == true
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                      onPressed: () {
                        setState(() {
                          _previewController!.value.isPlaying
                              ? _previewController!.pause()
                              : _previewController!.play();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14.0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedVideoPath!
                              .split(Platform.pathSeparator)
                              .last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ប្រវែង: ${_videoMetadata?.durationFormatted ?? "--:--"} | កម្រិត: ${_videoMetadata?.resolutionFormatted ?? "--"}',
                          style: const TextStyle(
                              color: Colors.amberAccent, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.change_circle_outlined, size: 18),
                    label: const Text('ប្តូរវីដេអូ'),
                    style:
                        TextButton.styleFrom(foregroundColor: Colors.white70),
                    onPressed: _pickVideoFile,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVoiceSelectorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.record_voice_over_rounded,
                  color: Colors.purpleAccent, size: 20),
              SizedBox(width: 8),
              Text(
                'ជ្រើសរើសសំឡេងអាន',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Featured: Auto Dialogue Switching (Recommended by Default)
          InkWell(
            onTap: () =>
                setState(() => _selectedVoice = KhmerVoice.autoDialogue),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: _selectedVoice == KhmerVoice.autoDialogue
                    ? LinearGradient(
                        colors: [
                          Colors.purpleAccent.withValues(alpha: 0.3),
                          Colors.blueAccent.withValues(alpha: 0.3)
                        ],
                      )
                    : null,
                color: _selectedVoice == KhmerVoice.autoDialogue
                    ? null
                    : const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _selectedVoice == KhmerVoice.autoDialogue
                      ? Colors.purpleAccent
                      : Colors.white12,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purpleAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.auto_awesome,
                        color: Colors.purpleAccent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Flexible(
                              child: Text(
                                '🎭 ឆ្លាស់សំឡេង (ប្រុស & ស្រី)',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'ណែនាំ',
                                style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'សំឡេងស្រីមុំ & ប្រសិទ្ធ ឆ្លាស់គ្នាតាមតួអង្គ និងគិតក្នុងចិត្ត',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _selectedVoice == KhmerVoice.autoDialogue
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: _selectedVoice == KhmerVoice.autoDialogue
                        ? Colors.purpleAccent
                        : Colors.white30,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // Male - Prasith
              Expanded(
                child: InkWell(
                  onTap: () =>
                      setState(() => _selectedVoice = KhmerVoice.prasith),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    decoration: BoxDecoration(
                      color: _selectedVoice == KhmerVoice.prasith
                          ? Colors.blueAccent.withValues(alpha: 0.2)
                          : const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedVoice == KhmerVoice.prasith
                            ? Colors.blueAccent
                            : Colors.white12,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.record_voice_over,
                            color: Colors.blueAccent, size: 22),
                        const SizedBox(height: 6),
                        const Text(
                          'ប្រសិទ្ធ (ប្រុស)',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ទឹកដមរស់រវើក ជក់ចិត្ត',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 10),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Female - Sreymom
              Expanded(
                child: InkWell(
                  onTap: () =>
                      setState(() => _selectedVoice = KhmerVoice.sreymom),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    decoration: BoxDecoration(
                      color: _selectedVoice == KhmerVoice.sreymom
                          ? Colors.pinkAccent.withValues(alpha: 0.2)
                          : const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedVoice == KhmerVoice.sreymom
                            ? Colors.pinkAccent
                            : Colors.white12,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.record_voice_over,
                            color: Colors.pinkAccent, size: 22),
                        const SizedBox(height: 6),
                        const Text(
                          'ស្រីមុំ (ស្រី)',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ពិរោះ រណ្ដំ ស្រទន់',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 10),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF06B6D4)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: _isProcessing ? null : _startRecapPipeline,
        child: _isProcessing
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white)),
                  SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'កំពុងដំណើរការបកប្រែ និងបញ្ចូលសំឡេង...',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('🚀 ', style: TextStyle(fontSize: 18)),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'បង្កើតវីដេអូបកប្រែ និងបញ្ចូលសំឡេង',
                        style: TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPipelineProgressTracker() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.amberAccent)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _statusMessage,
                  style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildStageRow(1, 'កំពុងវិភាគវីដេអូ (Analyzing Video)',
              ProcessingStage.analyzingVideo),
          const SizedBox(height: 10),
          _buildStageRow(2, 'កំពុងបកប្រែការសន្ទនា (Translating Dialogue)',
              ProcessingStage.writingScript),
          const SizedBox(height: 10),
          _buildStageRow(3, 'កំពុងបំប្លែងសំឡេង (Generating Voice)',
              ProcessingStage.generatingVoice),
          const SizedBox(height: 10),
          _buildStageRow(
              4,
              'កំពុងបញ្ចូលសំឡេងក្នុងវីដេអូ (Merging Audio & Video)',
              ProcessingStage.mergingAudioVideo),
        ],
      ),
    );
  }

  Widget _buildStageRow(int step, String label, ProcessingStage stage) {
    final isDone = _currentStage.index > stage.index;
    final isCurrent = _currentStage == stage;

    Color iconColor = Colors.white24;
    IconData iconData = Icons.radio_button_unchecked;

    if (isDone) {
      iconColor = Colors.greenAccent;
      iconData = Icons.check_circle_rounded;
    } else if (isCurrent) {
      iconColor = Colors.amberAccent;
      iconData = Icons.timelapse_rounded;
    }

    return Row(
      children: [
        Icon(iconData, color: iconColor, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$step. $label',
            style: TextStyle(
              color: isCurrent
                  ? Colors.white
                  : (isDone ? Colors.white70 : Colors.white30),
              fontSize: 12,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}
