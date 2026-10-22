import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';

import '../models/subtitle_entry.dart';
import '../services/ffmpeg_service.dart';
import '../services/gemini_recap_service.dart';
import '../services/khmer_tts_service.dart';
import '../services/project_manager_service.dart';
import '../services/settings_service.dart';
import '../theme/studio_theme.dart';
import '../widgets/subtitle_table_widget.dart';
import '../widgets/waveform_visualizer.dart';
import 'settings_screen.dart';

enum StudioProcessingStage {
  idle,
  analyzingVideo,
  writingScript,
  generatingVoice,
  mergingAudioVideo,
}

class StudioMainScreen extends StatefulWidget {
  final SettingsService settingsService;
  final ProjectManagerService projectManagerService;

  const StudioMainScreen({
    super.key,
    required this.settingsService,
    required this.projectManagerService,
  });

  @override
  State<StudioMainScreen> createState() => _StudioMainScreenState();
}

class _StudioMainScreenState extends State<StudioMainScreen> {
  int _currentTabIndex = 0;

  // Active Video State
  String? _selectedVideoPath;
  String? _dubbedVideoPath;
  VideoPlayerController? _videoPlayerController;
  VideoMetadata? _videoMetadata;
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  // Dubbing & Voice Settings
  List<SubtitleEntry> _subtitles = [];
  int _activeSubtitleIndex = -1;
  KhmerVoice _selectedVoice = KhmerVoice.autoDialogue; // Auto Sreymom & Prasith
  double _speechSpeed = 1.0;
  bool _isAudioPlaying = false;
  String? _generatedKhmerAudioPath;

  // Pipeline Status & Running Indicator
  bool _isProcessing = false;
  StudioProcessingStage _currentStage = StudioProcessingStage.idle;
  String _statusMessage = '';

  // Services
  final FFmpegService _ffmpegService = FFmpegService();
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadSampleProject();
  }

  void _loadSampleProject() {
    // Initial sample subtitles matching reference UI until user generates real ones
    _subtitles = [
      SubtitleEntry(
        index: 1,
        startTimeMs: 1200,
        endTimeMs: 4500,
        chineseText: '我不想让你离开',
        khmerText: 'ខ្ញុំមិនចង់ឱ្យអ្នកចាកចេញទេ',
        isFemale: true,
      ),
      SubtitleEntry(
        index: 2,
        startTimeMs: 4800,
        endTimeMs: 8200,
        chineseText: '你想去哪里？是真的吗？',
        khmerText: 'តើអ្នកចង់ទៅណាម្ដេចមែនទេ?',
        isFemale: false,
      ),
      SubtitleEntry(
        index: 3,
        startTimeMs: 8500,
        endTimeMs: 12300,
        chineseText: '等一下！我们在这里！',
        khmerText: 'ឈប់សិន! យើងនៅទីនេះ!',
        isFemale: false,
      ),
    ];
  }

  @override
  void dispose() {
    _videoPlayerController?.removeListener(_onVideoPlayerTick);
    _videoPlayerController?.dispose();
    super.dispose();
  }

  void _onVideoPlayerTick() {
    if (!mounted || _videoPlayerController == null) return;
    final pos = _videoPlayerController!.value.position;
    final isPl = _videoPlayerController!.value.isPlaying;

    int activeIdx = -1;
    final curMs = pos.inMilliseconds;
    for (final sub in _subtitles) {
      if (curMs >= sub.startTimeMs && curMs <= sub.endTimeMs) {
        activeIdx = sub.index;
        break;
      }
    }

    setState(() {
      _currentPosition = pos;
      _isPlaying = isPl;
      _activeSubtitleIndex = activeIdx;
    });
  }

  Future<void> _pickVideoFile() async {
    if (Platform.isAndroid) {
      await [Permission.videos, Permission.storage].request();
    }
    final XFile? file =
        await _imagePicker.pickVideo(source: ImageSource.gallery);
    if (file != null) {
      await _loadVideo(file.path);
    }
  }

  Future<void> _loadVideo(String path) async {
    _videoPlayerController?.removeListener(_onVideoPlayerTick);
    await _videoPlayerController?.dispose();

    final controller = VideoPlayerController.file(File(path));
    await controller.initialize();
    controller.addListener(_onVideoPlayerTick);

    final meta = await _ffmpegService.probeVideo(path);

    setState(() {
      _selectedVideoPath = path;
      _videoPlayerController = controller;
      _videoMetadata = meta;
      _totalDuration = controller.value.duration;
      _dubbedVideoPath = null;
    });

    await controller.play();
  }

  void _togglePlayPause() {
    if (_videoPlayerController == null) return;
    if (_videoPlayerController!.value.isPlaying) {
      _videoPlayerController!.pause();
    } else {
      _videoPlayerController!.play();
    }
  }

  void _seekToSubtitle(SubtitleEntry entry) {
    if (_videoPlayerController == null) return;
    _videoPlayerController!.seekTo(Duration(milliseconds: entry.startTimeMs));
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _currentSubtitleText {
    if (_activeSubtitleIndex <= 0) return '';
    final match = _subtitles.firstWhere(
      (s) => s.index == _activeSubtitleIndex,
      orElse: () => SubtitleEntry(
          index: 0, startTimeMs: 0, endTimeMs: 0, khmerText: ''),
    );
    return match.khmerText;
  }

  // ================= REAL 4-STAGE RECAP PIPELINE =================
  Future<void> _startAutomatedRecapPipeline() async {
    if (_selectedVideoPath == null) {
      _showSnackbar('សូមជ្រើសរើសវីដេអូជាមុនសិន!', isError: true);
      await _pickVideoFile();
      if (_selectedVideoPath == null) return;
    }

    final hasApiKey = widget.settingsService.geminiApiKey.trim().isNotEmpty;
    if (!hasApiKey) {
      _showSnackbar(
          'សូមកំណត់ Gemini API Key នៅក្នុង Settings ជាមុនសិន!',
          isError: true);
      _openSettings();
      return;
    }

    // Pause player during heavy processing
    try {
      await _videoPlayerController?.pause();
    } catch (_) {}

    setState(() {
      _isProcessing = true;
      _currentStage = StudioProcessingStage.analyzingVideo;
      _statusMessage =
          'កំពុងវិភាគវីដេអូ និងបង្រួមទិន្នន័យសម្រាប់ Gemini AI...';
    });

    try {
      // Stage 1: Prepare lightweight media for Gemini Multimodal Analysis
      final mediaPath =
          await _ffmpegService.prepareMediaForGemini(_selectedVideoPath!);
      final mimeType = mediaPath.endsWith('.mp4') ? 'video/mp4' : 'audio/mp3';

      // Stage 2: Send to Gemini for Chinese Dialogue Translation & Role assignment (ស្រី/ប្រុស)
      setState(() {
        _currentStage = StudioProcessingStage.writingScript;
        _statusMessage =
            'Gemini AI កំពុងមើលវីដេអូ អានអក្សររត់ និងបកប្រែសន្ទនា (ស្រី & ប្រុស)...';
      });

      final geminiService =
          GeminiRecapService(apiKeys: widget.settingsService.geminiApiKeys);
      final duration = _videoMetadata?.durationSeconds ?? 60.0;

      final khmerScript = await geminiService.generateKhmerRecapScript(
        mediaPath: mediaPath,
        videoDurationSeconds: duration,
        mimeType: mimeType,
      );

      // Parse generated script lines into interactive SubtitleEntry items
      _parseGeneratedScriptToSubtitles(khmerScript, duration);

      // Stage 3: Khmer TTS Multi-Speaker Voiceover Generation
      setState(() {
        _currentStage = StudioProcessingStage.generatingVoice;
        _statusMessage =
            'កំពុងបំប្លែងអត្ថបទទៅជាសំឡេង (${_selectedVoice.displayName})...';
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

      _generatedKhmerAudioPath = khmerAudioPath;

      // Stage 4: Merge final audio with video (CapCut sidechain auto-ducking to suppress Chinese dialogue)
      setState(() {
        _currentStage = StudioProcessingStage.mergingAudioVideo;
        _statusMessage =
            'កំពុងសង្កត់សំឡេងចិនដើម និងបញ្ចូលសំឡេងខ្មែរជាមួយភ្លេង background...';
      });

      final dubbedVideoPath = await _ffmpegService.mergeKhmerVoiceWithVideo(
        originalVideoPath: _selectedVideoPath!,
        khmerAudioPath: khmerAudioPath,
        duckingVolume: widget.settingsService.defaultDuckingVolume,
        removeChineseVocals: widget.settingsService.removeChineseVocals,
        bgmTrackId: widget.settingsService.selectedBgmTrack,
        bgmVolume: widget.settingsService.bgmVolume,
        watermarkText: widget.settingsService.watermarkEnabled
            ? widget.settingsService.watermarkText
            : null,
        watermarkFont: widget.settingsService.watermarkFont,
        watermarkColor: widget.settingsService.watermarkColor,
        watermarkOpacity: widget.settingsService.watermarkOpacity,
        scriptText: khmerScript,
        subtitleEnabled: true,
      );

      _dubbedVideoPath = dubbedVideoPath;

      // Auto-save dubbed video directly to phone Gallery (DCIM/KhmerRecap)
      setState(() {
        _statusMessage =
            'កំពុងរក្សាទុកវីដេអូស្វ័យប្រវត្តិចូល Gallery ទូរស័ព្ទ...';
      });

      try {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final baseName = p.basenameWithoutExtension(_selectedVideoPath!);
        await _ffmpegService.autoSaveToGallery(
          dubbedVideoPath,
          customName: '${baseName}_Recap_$timestamp',
        );
      } catch (e) {
        debugPrint('Auto-save warning: $e');
      }

      // Re-load dubbed video in preview player
      await _loadVideo(dubbedVideoPath);

      setState(() {
        _isProcessing = false;
        _currentStage = StudioProcessingStage.idle;
        _isAudioPlaying = true;
      });

      _showSnackbar('🎉 បង្កើតវីដេអូសម្រាយរឿងជោគជ័យ និងបានរក្សាទុកក្នុង Gallery!',
          isError: false);
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _currentStage = StudioProcessingStage.idle;
      });
      _showSnackbar('បរាជ័យក្នុងការដំណើរការ: $e', isError: true);
    }
  }

  void _parseGeneratedScriptToSubtitles(String script, double totalDuration) {
    final rawLines = script.split('\n');
    final List<SubtitleEntry> parsed = [];

    final timeRegex = RegExp(r'\[(\d{1,2}):(\d{2})(?:\s*[-–➔>]+\s*(\d{1,2}):(\d{2}))?\]');
    int entryIndex = 1;
    double currentSeconds = 1.0;

    for (final line in rawLines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final timeMatch = timeRegex.firstMatch(trimmed);
      int startMs;
      int endMs;

      if (timeMatch != null) {
        final startM = int.parse(timeMatch.group(1)!);
        final startS = int.parse(timeMatch.group(2)!);
        startMs = (startM * 60 + startS) * 1000;

        if (timeMatch.group(3) != null && timeMatch.group(4) != null) {
          final endM = int.parse(timeMatch.group(3)!);
          final endS = int.parse(timeMatch.group(4)!);
          endMs = (endM * 60 + endS) * 1000;
        } else {
          endMs = startMs + 3500;
        }
      } else {
        startMs = (currentSeconds * 1000).toInt();
        endMs = startMs + 3500;
        currentSeconds += 4.0;
      }

      final femaleKeywords = RegExp(
          r'(?:ស្រី|នារី|ស្ត្រី|ម្ដាយ|ម្តាយ|ម៉ាក់|ម៉ែ|យាយ|មីង|ប្រពន្ធ|ភរិយា|កូនស្រី|female|woman|\bF\b|女)',
          caseSensitive: false);
      final isFemale = femaleKeywords.hasMatch(trimmed);

      var cleanText = trimmed
          .replaceAll(timeRegex, '')
          .replaceAll(
              RegExp(
                  r'\[?\b\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d+)?(?:\s*(?:-->|[-–])\s*\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d+)?)?\]?'),
              '')
          .replaceAll(
              RegExp(
                  r'^\s*[\*_]*[\[\(【（<]?(?:(?:តួ)?(?:ប្រុស|ស្រី|បុរស|នារី|ស្ត្រី)|អ្នករៀបរាប់|male|female|man|woman|boy|girl|narrator|\b[MF]\b)[\]\)】）>]*[\*_]*\s*[:៖\-–\s]*',
                  caseSensitive: false),
              '')
          .replaceAll(
              RegExp(
                  r'[\*_]*[\[\(【（<]\s*(?:ក្នុងចិត្ត|គិតក្នុងចិត្ត|内心|心想|独白)\s*[\]\)】）>][\*_]*'),
              '')
          .replaceAll(RegExp(r'["{}\[\]【】]'), '')
          .replaceAll(RegExp(r'^[:៖\-–\s]+'), '')
          .trim();

      if (cleanText.isNotEmpty &&
          RegExp(r'[\u1780-\u17B3]').hasMatch(cleanText)) {
        parsed.add(SubtitleEntry(
          index: entryIndex++,
          startTimeMs: startMs,
          endTimeMs: endMs,
          khmerText: cleanText,
          isFemale: isFemale,
        ));
      }
    }

    if (parsed.isNotEmpty) {
      setState(() => _subtitles = parsed);
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(settingsService: widget.settingsService),
      ),
    );
  }

  void _showSnackbar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : StudioTheme.cyanAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StudioTheme.background,
      body: SafeArea(
        child: Stack(
          children: [
            IndexedStack(
              index: _currentTabIndex,
              children: [
                _buildHomeDashboardTab(),
                _buildSubtitlesTab(),
                _buildVoiceAiTab(),
                _buildProjectsTab(),
              ],
            ),
            if (_isProcessing) _buildAnimatedPipelineTrackerOverlay(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  // ================= TAB 0: HOME DASHBOARD =================
  Widget _buildHomeDashboardTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          _buildImportGrid(),
          const SizedBox(height: 12),
          _buildVideoPlayerCard(),
          const SizedBox(height: 12),
          _buildLanguageTranslationBar(),
          const SizedBox(height: 12),
          _buildAiKhmerVoiceCard(),
          const SizedBox(height: 12),
          SubtitleTableWidget(
            subtitles: _subtitles,
            activeSubtitleIndex: _activeSubtitleIndex,
            onSeekToSubtitle: _seekToSubtitle,
            onUpdateSubtitle: (updated) {
              final idx = _subtitles.indexWhere((s) => s.index == updated.index);
              if (idx >= 0) setState(() => _subtitles[idx] = updated);
            },
            onDeleteSubtitle: (index) {
              setState(() => _subtitles.removeWhere((s) => s.index == index));
            },
            onImportSrt: () {
              _showSnackbar('បានផ្ទុកអក្សររត់ SRT ចូលរួចរាល់!');
            },
            onAddSubtitle: () {
              final nextIndex = _subtitles.length + 1;
              final lastEnd = _subtitles.isNotEmpty
                  ? _subtitles.last.endTimeMs + 300
                  : 1000;
              setState(() {
                _subtitles.add(SubtitleEntry(
                  index: nextIndex,
                  startTimeMs: lastEnd,
                  endTimeMs: lastEnd + 3000,
                  khmerText: 'ឃ្លាថ្មីដែលត្រូវបកប្រែ...',
                  isFemale: _selectedVoice == KhmerVoice.sreymom,
                ));
              });
            },
          ),
          const SizedBox(height: 14),
          _buildStickyActionButtons(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // 1. Header with Golden Reel Crown Logo & Settings
  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD166), Color(0xFFB8860B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: StudioTheme.goldAccent.withValues(alpha: 0.35),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(Icons.movie_creation_rounded,
                    color: Colors.black, size: 24),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => StudioTheme.goldGradient
                      .createShader(Offset.zero & bounds.size),
                  child: const Text(
                    'Khmer Dubbing Studio',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(height: 1),
                const Text(
                  'AI Chinese to Khmer Voiceover',
                  style: TextStyle(
                    color: StudioTheme.cyanAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: StudioTheme.surfaceVariant,
              border: Border.all(
                  color: StudioTheme.cyanAccent.withValues(alpha: 0.4)),
            ),
            child: const Icon(Icons.settings_rounded,
                color: StudioTheme.cyanAccent, size: 20),
          ),
          onPressed: _openSettings,
        ),
      ],
    );
  }

  // 2. Import Video Card + Active Video Thumbnail
  Widget _buildImportGrid() {
    final fileName = _selectedVideoPath != null
        ? p.basename(_selectedVideoPath!)
        : 'drama_chinese_001.mp4';
    final durStr = _formatDuration(_totalDuration);

    return Row(
      children: [
        // Left: Import Video Button
        Expanded(
          child: InkWell(
            onTap: _pickVideoFile,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 104,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: StudioTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: StudioTheme.borderCyan.withValues(alpha: 0.7),
                  width: 1.2,
                ),
                boxShadow: StudioTheme.cyanGlowShadow(blur: 8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: StudioTheme.buttonCyanPurple,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.cloud_upload_rounded,
                            color: Colors.white, size: 18),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded,
                          color: StudioTheme.cyanAccent, size: 13),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'ជ្រើសរើសវីដេអូ',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Import Video',
                        style: TextStyle(
                            color: StudioTheme.cyanAccent, fontSize: 11),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'គាំទ្រ MP4, MOV, AVI, MKV (9:16)',
                        style: TextStyle(
                            color: StudioTheme.textMuted, fontSize: 8.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Right: Active Video Preview Card
        Expanded(
          child: Container(
            height: 104,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: StudioTheme.borderCard, width: 1.2),
              gradient: StudioTheme.cardGradient,
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    color: const Color(0xFF1E293B),
                    child: Center(
                      child: Icon(Icons.movie_filter_rounded,
                          color: Colors.white.withValues(alpha: 0.25), size: 36),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.85)
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: StudioTheme.cyanAccent, width: 0.8),
                    ),
                    child: const Text(
                      '9:16',
                      style: TextStyle(
                        color: StudioTheme.cyanAccent,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  right: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.access_time_rounded,
                              color: StudioTheme.cyanAccent, size: 10),
                          const SizedBox(width: 3),
                          Text(
                            durStr,
                            style: const TextStyle(
                              color: StudioTheme.cyanAccent,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 3. Video Player with On-Screen Subtitle Overlay & Controls
  Widget _buildVideoPlayerCard() {
    final curStr = _formatDuration(_currentPosition);
    final totStr = _formatDuration(_totalDuration);

    return Container(
      decoration: BoxDecoration(
        color: StudioTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: StudioTheme.borderCyan.withValues(alpha: 0.85),
          width: 1.4,
        ),
        boxShadow: StudioTheme.cyanGlowShadow(blur: 10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_videoPlayerController != null &&
                    _videoPlayerController!.value.isInitialized)
                  VideoPlayer(_videoPlayerController!)
                else
                  Container(
                    color: const Color(0xFF070E24),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.video_library_rounded,
                              color: StudioTheme.cyanAccent.withValues(alpha: 0.5),
                              size: 44),
                          const SizedBox(height: 8),
                          const Text(
                            'ជ្រើសរើសវីដេអូដើម្បីចាក់មើល',
                            style: TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),

                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Text(
                      'HD',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                Positioned(
                  top: 10,
                  right: 10,
                  child: InkWell(
                    onTap: () {},
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.fullscreen_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ),

                // In-video Subtitle Overlay
                if (_currentSubtitleText.isNotEmpty)
                  Positioned(
                    bottom: 12,
                    left: 16,
                    right: 16,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          _currentSubtitleText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFFFEB3B), // Yellow subtitle
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: 4),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Timeline Seek Slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: StudioTheme.cyanAccent,
              inactiveTrackColor: Colors.white12,
              thumbColor: StudioTheme.cyanAccent,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayColor: StudioTheme.cyanAccent.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: _currentPosition.inMilliseconds
                  .toDouble()
                  .clamp(0.0, _totalDuration.inMilliseconds.toDouble() > 0
                      ? _totalDuration.inMilliseconds.toDouble()
                      : 1.0),
              min: 0.0,
              max: _totalDuration.inMilliseconds.toDouble() > 0
                  ? _totalDuration.inMilliseconds.toDouble()
                  : 1.0,
              onChanged: (val) {
                _videoPlayerController?.seekTo(Duration(milliseconds: val.toInt()));
              },
            ),
          ),

          // Player Bottom Controls Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(
              children: [
                InkWell(
                  onTap: _togglePlayPause,
                  child: Icon(
                    _isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$curStr / $totStr',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                const Icon(Icons.volume_up_rounded,
                    color: Colors.white70, size: 18),
                const SizedBox(width: 12),
                const Icon(Icons.aspect_ratio_rounded,
                    color: Colors.white70, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 4. Language Translation Selector Bar (Chinese ➔ Khmer)
  Widget _buildLanguageTranslationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: StudioTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StudioTheme.borderCard, width: 1.2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFDE2910),
                ),
                child: const Center(
                  child: Text('🇨🇳', style: TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '中文',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Chinese',
                    style: TextStyle(
                        color: StudioTheme.textSecondary, fontSize: 10.5),
                  ),
                ],
              ),
            ],
          ),
          const Icon(Icons.arrow_forward_rounded,
              color: StudioTheme.cyanAccent, size: 20),
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF032EA6),
                ),
                child: const Center(
                  child: Text('🇰🇭', style: TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ខ្មែរ',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Khmer',
                    style: TextStyle(
                        color: StudioTheme.textSecondary, fontSize: 10.5),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white38, size: 18),
            ],
          ),
        ],
      ),
    );
  }

  // 5. AI Khmer Voice Selection & Dynamic Audio Waveform
  Widget _buildAiKhmerVoiceCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: StudioTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: StudioTheme.purpleAccent.withValues(alpha: 0.7),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      gradient: StudioTheme.buttonCyanPurple,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.mic_rounded,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 8),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Khmer Voice',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'សំឡេងបកប្រែដោយ AI (ស្រី & ប្រុស អូតូ)',
                        style: TextStyle(
                            color: StudioTheme.textSecondary, fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
              InkWell(
                onTap: () => setState(() => _currentTabIndex = 2),
                child: Row(
                  children: const [
                    Icon(Icons.graphic_eq_rounded,
                        color: StudioTheme.cyanAccent, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'ការកំណត់សំឡេង',
                      style: TextStyle(
                          color: StudioTheme.cyanAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: StudioTheme.cyanAccent, size: 14),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 3 Voice Selector Chips: [Auto Dialogue], [Female Sreymom], [Male Prasith]
          Row(
            children: [
              // Auto Dialogue (ស្រី & ប្រុស)
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _selectedVoice = KhmerVoice.autoDialogue),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _selectedVoice == KhmerVoice.autoDialogue
                          ? StudioTheme.cyanAccent.withValues(alpha: 0.20)
                          : const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedVoice == KhmerVoice.autoDialogue
                            ? StudioTheme.cyanAccent
                            : Colors.white12,
                        width: _selectedVoice == KhmerVoice.autoDialogue ? 1.6 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: StudioTheme.cyanAccent.withValues(alpha: 0.25),
                          child: const Icon(Icons.auto_awesome_rounded,
                              color: StudioTheme.cyanAccent, size: 16),
                        ),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'អូតូ\nស្រី+ប្រុស',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Female Sreymom
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _selectedVoice = KhmerVoice.sreymom),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _selectedVoice == KhmerVoice.sreymom
                          ? Colors.pinkAccent.withValues(alpha: 0.20)
                          : const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedVoice == KhmerVoice.sreymom
                            ? Colors.pinkAccent
                            : Colors.white12,
                        width: _selectedVoice == KhmerVoice.sreymom ? 1.6 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.pinkAccent.withValues(alpha: 0.25),
                          child: const Icon(Icons.face_3_rounded,
                              color: Colors.pinkAccent, size: 16),
                        ),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'ស្រី\nSreymom',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Male Prasith
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _selectedVoice = KhmerVoice.prasith),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _selectedVoice == KhmerVoice.prasith
                          ? StudioTheme.purpleAccent.withValues(alpha: 0.20)
                          : const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedVoice == KhmerVoice.prasith
                            ? StudioTheme.purpleAccent
                            : Colors.white12,
                        width: _selectedVoice == KhmerVoice.prasith ? 1.6 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.blueAccent.withValues(alpha: 0.25),
                          child: const Icon(Icons.face_rounded,
                              color: Colors.lightBlueAccent, size: 16),
                        ),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'ប្រុស\nPrasith',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Speed Slider
          Row(
            children: [
              const Text('ល្បឿនសំឡេង',
                  style: TextStyle(color: Colors.white70, fontSize: 11.5)),
              const Spacer(),
              Text(
                '${_speechSpeed.toStringAsFixed(1)}x',
                style: const TextStyle(
                  color: StudioTheme.cyanAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: StudioTheme.cyanAccent,
              inactiveTrackColor: Colors.white12,
              thumbColor: StudioTheme.cyanAccent,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            ),
            child: Slider(
              value: _speechSpeed,
              min: 0.8,
              max: 1.5,
              divisions: 7,
              onChanged: (val) => setState(() => _speechSpeed = val),
            ),
          ),
          const SizedBox(height: 6),

          // Audio Waveform Bar
          WaveformVisualizerWidget(
            isPlaying: _isAudioPlaying,
            onTogglePlay: () {
              if (_generatedKhmerAudioPath == null && _subtitles.isNotEmpty) {
                _startAutomatedRecapPipeline();
              } else {
                setState(() => _isAudioPlaying = !_isAudioPlaying);
              }
            },
          ),
        ],
      ),
    );
  }

  // 6. Action Bar: Auto Dubbing & MP4 Export
  Widget _buildStickyActionButtons() {
    return Row(
      children: [
        // Primary Cyan/Purple Button: បង្កើតសម្រាយរឿងអូតូ (Auto Dub & Translate)
        Expanded(
          flex: 6,
          child: InkWell(
            onTap: _isProcessing ? null : _startAutomatedRecapPipeline,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                gradient: StudioTheme.buttonCyanPurple,
                borderRadius: BorderRadius.circular(14),
                boxShadow: StudioTheme.cyanGlowShadow(blur: 10),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'បង្កើតសម្រាយរឿងអូតូ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Secondary Gold/Dark Button: នាំចេញ MP4
        Expanded(
          flex: 4,
          child: InkWell(
            onTap: _isProcessing ? null : _exportDubbedMp4,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1B2E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: StudioTheme.goldAccent.withValues(alpha: 0.8),
                  width: 1.2,
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.video_call_rounded,
                      color: StudioTheme.goldAccent, size: 20),
                  SizedBox(width: 6),
                  Text(
                    'នាំចេញ MP4',
                    style: TextStyle(
                      color: StudioTheme.goldLight,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _exportDubbedMp4() async {
    if (_dubbedVideoPath != null && await File(_dubbedVideoPath!).exists()) {
      await Share.shareXFiles([XFile(_dubbedVideoPath!)],
          text: 'វីដេអូសម្រាយរឿង AI Khmer Dubbing Studio');
      _showSnackbar('បានចែករំលែកវីដេអូរួចរាល់!');
    } else {
      await _startAutomatedRecapPipeline();
    }
  }

  // ================= TAB 1: SUBTITLES EDITOR =================
  Widget _buildSubtitlesTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'អក្សររត់ SRT & បកប្រែ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  final srtContent =
                      ProjectManagerService.generateSrtContent(_subtitles);
                  Share.share(srtContent, subject: 'Khmer_Subtitles.srt');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: StudioTheme.cyanAccent,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Export .SRT',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: _subtitles.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final entry = _subtitles[index];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: StudioTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: StudioTheme.borderCard),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '#${entry.index}  •  ${entry.formattedTimeRange}',
                            style: const TextStyle(
                                color: StudioTheme.cyanAccent,
                                fontSize: 11,
                                fontFamily: 'monospace'),
                          ),
                          Text(
                            entry.isFemale ? '👩 ស្រី' : '👨 ប្រុស',
                            style: TextStyle(
                              color: entry.isFemale
                                  ? StudioTheme.cyanAccent
                                  : Colors.purpleAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        entry.khmerText,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ================= TAB 2: VOICE AI SETTINGS =================
  Widget _buildVoiceAiTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'កំណត់សំឡេង AI (Voice & Audio Ducking)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: StudioTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: StudioTheme.borderCard),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.volume_down_rounded,
                        color: StudioTheme.cyanAccent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'ប្រព័ន្ធសង្កត់សំឡេងចិន (Sidechain Ducking)',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  '• ភ្លេងដើម និង Sound Effect (SFX) នៅបន្លឺឮធម្មតា\n• ពេលសំឡេងខ្មែរនិយាយ សំឡេងចិននឹងត្រូវសង្កត់បាត់ភ្លាមៗ (-24dB)\n• កាត់ប្រេកង់សំឡេងនិយាយចិនស្វ័យប្រវត្តិតាមស្ទីល CapCut',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 11.5, height: 1.5),
                ),
                const Divider(height: 24, color: StudioTheme.borderCard),
                const Text('ម៉ាស៊ីនបំប្លែងសំឡេង (TTS Engine):',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 6),
                Text(
                  widget.settingsService.ttsEndpoint,
                  style: const TextStyle(
                      color: StudioTheme.cyanAccent,
                      fontSize: 12,
                      fontFamily: 'monospace'),
                ),
                const Divider(height: 24, color: StudioTheme.borderCard),
                const Text('សំឡេង Prasith (ប្រុស):',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text(widget.settingsService.voicePrasithId,
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
                const SizedBox(height: 12),
                const Text('សំឡេង Sreymom (ស្រី):',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text(widget.settingsService.voiceSreymomId,
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================= TAB 3: PROJECTS =================
  Widget _buildProjectsTab() {
    final projects = widget.projectManagerService.getProjects();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'គម្រោងទាំងអស់ (Projects)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded,
                    color: StudioTheme.cyanAccent),
                onPressed: _pickVideoFile,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (projects.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_open_rounded,
                        color: Colors.white.withValues(alpha: 0.3), size: 48),
                    const SizedBox(height: 8),
                    const Text('មិនទាន់មានគម្រោងដែលបានរក្សាទុកទេ',
                        style: TextStyle(color: Colors.white60, fontSize: 13)),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: projects.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final p = projects[index];
                  return ListTile(
                    tileColor: StudioTheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: StudioTheme.borderCard),
                    ),
                    leading: const Icon(Icons.movie_rounded,
                        color: StudioTheme.cyanAccent),
                    title: Text(p.title,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text('${p.subtitles.length} ឃ្លាអក្សររត់',
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 11)),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: Colors.white38),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // ================= BOTTOM NAVIGATION BAR =================
  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF070E24),
        border: const Border(
          top: BorderSide(color: Color(0xFF131D3F), width: 1.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 10,
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _currentTabIndex,
        onTap: (index) => setState(() => _currentTabIndex = index),
        backgroundColor: Colors.transparent,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: StudioTheme.cyanAccent,
        unselectedItemColor: StudioTheme.textMuted,
        selectedFontSize: 11,
        unselectedFontSize: 10.5,
        elevation: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'ទំព័រដើម\nHome',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.subtitles_rounded),
            label: 'អក្សរសម្រួល\nSubtitles',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.mic_rounded),
            label: 'សំឡេង AI\nVoice AI',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.folder_rounded),
            label: 'គម្រោង\nProjects',
          ),
        ],
      ),
    );
  }

  // Animated Pipeline Progress Tracker Modal (Stage Stepper)
  Widget _buildAnimatedPipelineTrackerOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: StudioTheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: StudioTheme.borderCyan, width: 1.6),
            boxShadow: StudioTheme.cyanGlowShadow(blur: 20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.8,
                      valueColor:
                          AlwaysStoppedAnimation(StudioTheme.cyanAccent),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'ដំណើរការបកប្រែ & បញ្ចូលសំឡេង AI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                _statusMessage,
                style: const TextStyle(
                  color: StudioTheme.cyanAccent,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              _buildStageStepperRow(
                step: 1,
                label: 'កំពុងវិភាគវីដេអូ & ដកស្រង់រូបភាព',
                stage: StudioProcessingStage.analyzingVideo,
              ),
              const SizedBox(height: 10),
              _buildStageStepperRow(
                step: 2,
                label: 'Gemini AI កំពុងបកប្រែសន្ទនា (ស្រី & ប្រុស)',
                stage: StudioProcessingStage.writingScript,
              ),
              const SizedBox(height: 10),
              _buildStageStepperRow(
                step: 3,
                label: 'កំពុងបង្កើតសំឡេងខ្មែរ (ស្រី & ប្រុស) តាមឃ្លា',
                stage: StudioProcessingStage.generatingVoice,
              ),
              const SizedBox(height: 10),
              _buildStageStepperRow(
                step: 4,
                label: 'សង្កត់សំឡេងចិន & បញ្ចូលសំឡេងជាមួយភ្លេងដើម',
                stage: StudioProcessingStage.mergingAudioVideo,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStageStepperRow({
    required int step,
    required String label,
    required StudioProcessingStage stage,
  }) {
    final isDone = _currentStage.index > stage.index;
    final isCurrent = _currentStage == stage;

    Color color = Colors.white24;
    IconData icon = Icons.radio_button_unchecked;

    if (isDone) {
      color = Colors.greenAccent;
      icon = Icons.check_circle_rounded;
    } else if (isCurrent) {
      color = StudioTheme.cyanAccent;
      icon = Icons.timelapse_rounded;
    }

    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$step. $label',
            style: TextStyle(
              color: isCurrent
                  ? Colors.white
                  : (isDone ? Colors.white70 : Colors.white38),
              fontSize: 11.5,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}
