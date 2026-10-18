import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../models/watermark_style.dart';
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
  bool _isSavedToGallery = true;
  final FFmpegService _ffmpegService = FFmpegService();
  late KhmerVoice _currentVoice;

  @override
  void initState() {
    super.initState();
    _currentVoice = widget.selectedVoice;
    _currentDubbedVideoPath = widget.dubbedVideoPath;
    _currentKhmerAudioPath = widget.khmerAudioPath;
    _scriptController = TextEditingController(text: widget.generatedScript);
    _initVideoPlayer(_currentDubbedVideoPath);
  }

  void _toggleSpeakerForLine(int lineIndex, bool currentlyFemale) {
    final rawLines = _scriptController.text.split('\n');
    final validLinesIndices = <int>[];
    for (int i = 0; i < rawLines.length; i++) {
      if (rawLines[i].trim().isNotEmpty) {
        validLinesIndices.add(i);
      }
    }
    if (lineIndex < validLinesIndices.length) {
      final actualIndex = validLinesIndices[lineIndex];
      final line = rawLines[actualIndex];

      final timePattern = RegExp(
          r'(\[\d{1,2}:\d{2}(?::\d{2})?(?:\s*(?:-->|[-–])\s*\d{1,2}:\d{2}(?::\d{2})?)?\])');
      final timeMatch = timePattern.firstMatch(line);
      final timeStr = timeMatch?.group(1);

      var textAfter = line.replaceAll(timePattern, '').trim();
      textAfter = textAfter
          .replaceFirst(
              RegExp(
                  r'^\s*[\*_]*[\[\(【（<][^\]\)】）>]+[\]\)】）>][\*_]*\s*[:៖\-–\s]*'),
              '')
          .replaceFirst(RegExp(r'^\s*([^\s:៖\-–]{1,12})\s*[:៖\-–\s]+'), '')
          .replaceAll(RegExp(r'^[:៖\-–\s]+'), '')
          .trim();

      final newTag = currentlyFemale ? '[ប្រុស]:' : '[ស្រី]:';
      final updatedLine = timeStr != null
          ? '$timeStr $newTag $textAfter'
          : '$newTag $textAfter';

      rawLines[actualIndex] = updatedLine;
      setState(() {
        _scriptController.text = rawLines.join('\n');
      });
      _showSnackbar(
          'បានប្ដូរឃ្លាទី ${lineIndex + 1} ទៅជា ${currentlyFemale ? "👨 ប្រុស" : "👩 ស្រី"} រួចរាល់!',
          isSuccess: true);
    }
  }

  void _convertAllLinesTo(bool makeFemale) {
    final rawLines = _scriptController.text.split('\n');
    final updatedLines = <String>[];
    final timePattern = RegExp(
        r'(\[\d{1,2}:\d{2}(?::\d{2})?(?:\s*(?:-->|[-–])\s*\d{1,2}:\d{2}(?::\d{2})?)?\])');

    for (var line in rawLines) {
      if (line.trim().isEmpty) {
        updatedLines.add(line);
        continue;
      }
      final timeMatch = timePattern.firstMatch(line);
      final timeStr = timeMatch?.group(1);

      var textAfter = line.replaceAll(timePattern, '').trim();
      textAfter = textAfter
          .replaceFirst(
              RegExp(
                  r'^\s*[\*_]*[\[\(【（<][^\]\)】）>]+[\]\)】）>][\*_]*\s*[:៖\-–\s]*'),
              '')
          .replaceFirst(RegExp(r'^\s*([^\s:៖\-–]{1,12})\s*[:៖\-–\s]+'), '')
          .replaceAll(RegExp(r'^[:៖\-–\s]+'), '')
          .trim();

      final newTag = makeFemale ? '[ស្រី]:' : '[ប្រុស]:';
      final updatedLine = timeStr != null
          ? '$timeStr $newTag $textAfter'
          : '$newTag $textAfter';
      updatedLines.add(updatedLine);
    }

    setState(() {
      _scriptController.text = updatedLines.join('\n');
      if (makeFemale) {
        _currentVoice = KhmerVoice.sreymom;
      } else {
        _currentVoice = KhmerVoice.prasith;
      }
    });
    _showSnackbar(
        'បានប្ដូរគ្រប់ឃ្លាទាំងអស់ទៅជា ${makeFemale ? "👩 ស្រីសុទ្ធ" : "👨 ប្រុសសុទ្ធ"} រួចរាល់!',
        isSuccess: true);
  }

  void _autoDetectAllGenders() {
    final rawLines = _scriptController.text.split('\n');
    final updatedLines = <String>[];
    final timePattern = RegExp(
        r'(\[\d{1,2}:\d{2}(?::\d{2})?(?:\s*(?:-->|[-–])\s*\d{1,2}:\d{2}(?::\d{2})?)?\])');

    final femaleKeywords = RegExp(
        r'(?:ម៉ាក់|ម៉ែ|ម្ដាយ|ម្តាយ|អូន|កូនស្រី|ប្អូនស្រី|បងស្រី|យាយ|មីង|ប្រពន្ធ|ភរិយា|កញ្ញា|អ្នកនាង|ស្រី|នារី|បងសម្លាញ់|លោកប្ដី|ប្ដីខ្ញុំ|បងកុំ|បងឯង)');

    int countFemale = 0;
    int countMale = 0;

    for (var line in rawLines) {
      if (line.trim().isEmpty) {
        updatedLines.add(line);
        continue;
      }
      final timeMatch = timePattern.firstMatch(line);
      final timeStr = timeMatch?.group(1);

      var textAfter = line.replaceAll(timePattern, '').trim();
      textAfter = textAfter
          .replaceFirst(
              RegExp(
                  r'^\s*[\*_]*[\[\(【（<][^\]\)】）>]+[\]\)】）>][\*_]*\s*[:៖\-–\s]*'),
              '')
          .replaceFirst(RegExp(r'^\s*([^\s:៖\-–]{1,12})\s*[:៖\-–\s]+'), '')
          .replaceAll(RegExp(r'^[:៖\-–\s]+'), '')
          .trim();

      final bool isFemale = femaleKeywords.hasMatch(line);
      if (isFemale) {
        countFemale++;
      } else {
        countMale++;
      }
      final tag = isFemale ? '[ស្រី]:' : '[ប្រុស]:';
      final updatedLine =
          timeStr != null ? '$timeStr $tag $textAfter' : '$tag $textAfter';
      updatedLines.add(updatedLine);
    }

    setState(() {
      _scriptController.text = updatedLines.join('\n');
    });
    _showSnackbar(
        'បានវិភាគបែងចែកដោយស្វ័យប្រវត្តិ៖ 👩 ស្រី $countFemale ឃ្លា និង 👨 ប្រុស $countMale ឃ្លា!',
        isSuccess: true);
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
    if (_isSavedToGallery) {
      _showSnackbar(
          'វីដេអូនេះបានរក្សាទុកក្នុង Gallery (DCIM/KhmerRecap) រួចរាល់ហើយ!\n($_currentDubbedVideoPath)',
          isSuccess: true);
      return;
    }
    try {
      final savedPath = await _ffmpegService.autoSaveToGallery(
        _currentDubbedVideoPath,
        customName: 'Recap_${DateTime.now().millisecondsSinceEpoch}',
      );
      setState(() {
        _isSavedToGallery = true;
      });
      _showSnackbar(
          'បានរក្សាទុកវីដេអូទៅក្នុង Gallery ទូរស័ព្ទ (DCIM/KhmerRecap) រួចរាល់!\n($savedPath)',
          isSuccess: true);
    } catch (e) {
      _showSnackbar('បរាជ័យក្នុងការរក្សាទុកវីដេអូ: $e', isSuccess: false);
    }
  }

  Future<void> _shareVideo() async {
    try {
      final file = XFile(_currentDubbedVideoPath);
      await Share.shareXFiles([file],
          text:
              'វីដេអូបកប្រែ និងបញ្ចូលសំឡេងភាពយន្តផលិតដោយ Khmer Recap AI Studio');
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
      _showSnackbar(
          'បានទាញយកសំឡេងខ្មែរ (.mp3) ទៅកាន់ Download Folder:\n$savedPath',
          isSuccess: true);
    } catch (e) {
      _showSnackbar('បរាជ័យក្នុងការរក្សាទុកសំឡេង: $e', isSuccess: false);
    }
  }

  Future<void> _exportScript() async {
    try {
      final tempDir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final scriptFile = File(
          '${tempDir.path}/Khmer_Recap_Script_${DateTime.now().millisecondsSinceEpoch}.txt');
      await scriptFile.writeAsString(_scriptController.text.trim());
      await Share.shareXFiles([XFile(scriptFile.path)],
          text: 'អត្ថបទបកប្រែសន្ទនាខ្មែរ');
      _showSnackbar('បាននាំចេញអត្ថបទបកប្រែសន្ទនាជាឯកសារ .txt រួចរាល់!',
          isSuccess: true);
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

      final videoMeta =
          await _ffmpegService.probeVideo(widget.originalVideoPath);
      final newAudioPath = await ttsService.synthesizeKhmerSpeech(
        text: newScript,
        voice: _currentVoice,
        totalDurationSeconds: videoMeta.durationSeconds,
        syncDelaySeconds: widget.settingsService.audioSyncDelay,
      );

      final newVideoPath = await _ffmpegService.mergeKhmerVoiceWithVideo(
        originalVideoPath: widget.originalVideoPath,
        khmerAudioPath: newAudioPath,
        duckingVolume: widget.duckingVolume,
        watermarkText: widget.settingsService.watermarkEnabled
            ? widget.settingsService.watermarkText
            : null,
        watermarkFont: widget.settingsService.watermarkFont,
        watermarkColor: widget.settingsService.watermarkColor,
        watermarkOpacity: widget.settingsService.watermarkOpacity,
        scriptText: newScript,
        subtitleEnabled: widget.settingsService.subtitleEnabled,
        subtitleColor: widget.settingsService.subtitleColor,
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
      _isSavedToGallery = true;

      await _initVideoPlayer(_currentDubbedVideoPath);

      _showSnackbar('បានបង្កើតសំឡេងថ្មី និងរក្សាទុកក្នុង Gallery រួចរាល់!',
          isSuccess: true);
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
            Icon(isSuccess ? Icons.check_circle : Icons.error,
                color: isSuccess ? Colors.greenAccent : Colors.redAccent),
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

  void _showWatermarkStyleBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final currentFont = widget.settingsService.watermarkFont;
            final currentColor = widget.settingsService.watermarkColor;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'រចនា Watermark Logo (Font & Color)',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white60, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Mini preview
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Center(
                      child: Text(
                        widget.settingsService.watermarkText,
                        style: FFmpegService.getKhmerWatermarkTextStyle(
                          fontName: currentFont,
                          fontSize: 22,
                          color: FFmpegService.resolveWatermarkColor(
                              currentColor,
                              opacity: 0.40),
                          shadows: const [
                            Shadow(
                              color: Color(0x66000000),
                              offset: Offset(1.5, 1.5),
                              blurRadius: 2.0,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  const Text(
                    'ពុម្ពអក្សរខ្មែរ (Khmer Fonts):',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  SizedBox(
                    height: 90,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: WatermarkStylePresets.fonts.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, idx) {
                        final fontOpt = WatermarkStylePresets.fonts[idx];
                        final isSel = currentFont == fontOpt.key;
                        return InkWell(
                          onTap: () {
                            widget.settingsService.watermarkFont = fontOpt.key;
                            setModalState(() {});
                            setState(() {});
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 120,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? Colors.tealAccent.withValues(alpha: 0.18)
                                  : const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSel
                                    ? Colors.tealAccent
                                    : Colors.white12,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                Text(
                                  fontOpt.category,
                                  style: TextStyle(
                                      color: isSel
                                          ? Colors.tealAccent
                                          : Colors.white38,
                                      fontSize: 9),
                                ),
                                Text(
                                  fontOpt.nameKh,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color:
                                        isSel ? Colors.white : Colors.white70,
                                    fontSize: 11,
                                    fontWeight: isSel
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 14),

                  const Text(
                    'ពណ៌ Logo (Color):',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: WatermarkStylePresets.colors.map((c) {
                      final isSel = currentColor.toLowerCase() ==
                          c.key.toLowerCase();
                      return InkWell(
                        onTap: () {
                          widget.settingsService.watermarkColor = c.key;
                          setModalState(() {});
                          setState(() {});
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isSel
                                ? c.color.withValues(alpha: 0.25)
                                : const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSel ? c.color : Colors.white12,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: c.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                c.nameKh,
                                style: TextStyle(
                                  color: isSel ? Colors.white : Colors.white70,
                                  fontSize: 10.5,
                                  fontWeight: isSel
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          },
        );
      },
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
          child: Text('មិនមានអត្ថបទសន្ទនាទេ',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Voice Selection Mode Chips
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.tune_rounded, color: Colors.amberAccent, size: 16),
                  SizedBox(width: 6),
                  Text('ទម្រង់សំឡេងបញ្ចូល (Voice Mode):',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(
                          () => _currentVoice = KhmerVoice.autoDialogue),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(
                          color: _currentVoice == KhmerVoice.autoDialogue
                              ? Colors.purpleAccent.withValues(alpha: 0.3)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _currentVoice == KhmerVoice.autoDialogue
                                  ? Colors.purpleAccent
                                  : Colors.white24),
                        ),
                        child: const Text('🎭 ឆ្លាស់ប្រុស/ស្រី',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: InkWell(
                      onTap: () =>
                          setState(() => _currentVoice = KhmerVoice.sreymom),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(
                          color: _currentVoice == KhmerVoice.sreymom
                              ? Colors.pinkAccent.withValues(alpha: 0.3)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _currentVoice == KhmerVoice.sreymom
                                  ? Colors.pinkAccent
                                  : Colors.white24),
                        ),
                        child: const Text('👩 ស្រីសុទ្ធ',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.pinkAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: InkWell(
                      onTap: () =>
                          setState(() => _currentVoice = KhmerVoice.prasith),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(
                          color: _currentVoice == KhmerVoice.prasith
                              ? Colors.blueAccent.withValues(alpha: 0.3)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _currentVoice == KhmerVoice.prasith
                                  ? Colors.blueAccent
                                  : Colors.white24),
                        ),
                        child: const Text('👨 ប្រុសសុទ្ធ',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.lightBlueAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _convertAllLinesTo(true),
                      icon: const Icon(Icons.female_rounded,
                          color: Colors.pinkAccent, size: 14),
                      label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('ប្ដូរទាំងអស់ជាស្រី',
                              style: TextStyle(
                                  fontSize: 10.5, color: Colors.pinkAccent))),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: Colors.pinkAccent, width: 0.8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 0),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _convertAllLinesTo(false),
                      icon: const Icon(Icons.male_rounded,
                          color: Colors.lightBlueAccent, size: 14),
                      label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('ប្ដូរទាំងអស់ជាប្រុស',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.lightBlueAccent))),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: Colors.blueAccent, width: 0.8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 0),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _autoDetectAllGenders,
                      icon: const Icon(Icons.auto_awesome_rounded,
                          color: Colors.amberAccent, size: 14),
                      label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('វិភាគស្វ័យប្រវត្តិ',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.amberAccent))),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: Colors.amberAccent, width: 0.8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 0),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '💡 ចុចលើស្លាក [👩 ស្រី] ឬ [👨 ប្រុស] លើឃ្លានីមួយៗខាងក្រោម ដើម្បីប្ដូរសំឡេងឆ្លាស់គ្នា',
                style: TextStyle(color: Colors.white38, fontSize: 10.5),
              ),
            ],
          ),
        ),

        // Watermark Logo Styling Bar
        if (widget.settingsService.watermarkEnabled) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: _showWatermarkStyleBottomSheet,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: Colors.tealAccent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.branding_watermark_rounded,
                      size: 16, color: Colors.tealAccent),
                  const SizedBox(width: 8),
                  const Text('Logo:',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${widget.settingsService.watermarkText} • ${widget.settingsService.watermarkFont}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FFmpegService.getKhmerWatermarkTextStyle(
                        fontName: widget.settingsService.watermarkFont,
                        fontSize: 12,
                        color: FFmpegService.resolveWatermarkColor(
                            widget.settingsService.watermarkColor,
                            opacity: 1.0),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.tealAccent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('ប្ដូរ Font/ពណ៌ 🎨',
                        style: TextStyle(
                            color: Colors.tealAccent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 12),

        // Dialogue list
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: validLines.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final line = validLines[index].trim();
            final timePattern = RegExp(
                r'\[?\(?(\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d+)?(?:\s*(?:-->|[-–])\s*\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d+)?)?)\)?\]?');
            final timeMatch = timePattern.firstMatch(line);
            final timeStr = timeMatch?.group(1);

            final femaleKeywords = RegExp(
                r'(?:ស្រី|តួស្រី|នារី|ស្ត្រី|ម្ដាយ|ម្តាយ|ម៉ាក់|ម៉ែ|យាយ|មីង|ប្រពន្ធ|ភរិយា|កូនស្រី|ប្អូនស្រី|កញ្ញា|អ្នកនាង|អូន|female|woman|girl|\bF\b|女)',
                caseSensitive: false);
            final maleKeywords = RegExp(
                r'(?:ប្រុស|តួប្រុស|បុរស|ឪពុក|ពុក|ប៉ា|តា|ពូ|ប្ដី|ស្វាមី|កូនប្រុស|ប្អូនប្រុស|អ្នករៀបរាប់|អ្នកសម្រាយ|male|man|boy|narrator|\bM\b|男)',
                caseSensitive: false);

            final bracketMatch = RegExp(
                    r'^\s*[\*_]*[\[\(【（<][^\]\)】）>]+[\]\)】）>][\*_]*\s*[:៖\-–\s]*')
                .firstMatch(line.replaceAll(timePattern, '').trim());
            bool isFemale = false;
            if (bracketMatch != null) {
              isFemale = femaleKeywords.hasMatch(bracketMatch.group(0)!);
            } else {
              isFemale = (femaleKeywords.hasMatch(line) &&
                      !maleKeywords.hasMatch(line)) ||
                  RegExp(r'(?:ម៉ាក់|ម៉ែ|ម្ដាយ|ម្តាយ|អូន|កូនស្រី|ប្អូនស្រី|បងសម្លាញ់|លោកប្ដី|ប្ដីខ្ញុំ|បងកុំ)')
                      .hasMatch(line);
            }

            var textOnly = line
                .replaceAll(timePattern, '')
                .replaceFirst(
                    RegExp(
                        r'^\s*[\*_]*[\[\(【（<][^\]\)】）>]+[\]\)】）>][\*_]*\s*[:៖\-–\s]*'),
                    '')
                .replaceFirst(
                    RegExp(r'^\s*([^\s:៖\-–]{1,12})\s*[:៖\-–\s]+'), '')
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
                      : Colors.blueAccent.withValues(alpha: 0.35),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.cyanAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '⏱ $timeStr',
                            style: const TextStyle(
                                color: Colors.cyanAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      InkWell(
                        onTap: () => _toggleSpeakerForLine(index, isFemale),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isFemale
                                ? Colors.pinkAccent.withValues(alpha: 0.22)
                                : Colors.blueAccent.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isFemale
                                  ? Colors.pinkAccent
                                  : Colors.lightBlueAccent,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isFemale ? '👩 ស្រី' : '👨 ប្រុស',
                                style: TextStyle(
                                  color: isFemale
                                      ? Colors.pinkAccent
                                      : Colors.lightBlueAccent,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.swap_horiz_rounded,
                                size: 13,
                                color: isFemale
                                    ? Colors.pinkAccent
                                    : Colors.lightBlueAccent,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '#${index + 1}',
                        style: const TextStyle(
                            color: Colors.white24,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    textOnly.isEmpty ? line : textOnly,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
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
          child: Text('លទ្ធផលបកប្រែ និងបញ្ចូលសំឡេង',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
              child: _videoPlayerController != null &&
                      _videoPlayerController!.value.isInitialized
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio:
                              _videoPlayerController!.value.aspectRatio,
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
                  : const Center(
                      child: CircularProgressIndicator(color: Colors.amber)),
            ),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Auto-Saved to Gallery Notice Banner
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF064E3B).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color:
                              const Color(0xFF10B981).withValues(alpha: 0.6)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            color: Color(0xFF34D399), size: 20),
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
                            icon: const Icon(Icons.download_rounded,
                                color: Colors.white, size: 18),
                            label: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('រក្សាទុក Gallery',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold)),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
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
                            icon: const Icon(Icons.audiotrack_rounded,
                                color: Colors.white, size: 18),
                            label: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('ទាញយក MP3',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold)),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8B5CF6),
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
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
                      icon: const Icon(Icons.description_outlined,
                          color: Colors.amberAccent, size: 18),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('ទាញយកអត្ថបទបកប្រែ (.txt / .srt)',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5)),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
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
                            const Icon(Icons.article_rounded,
                                color: Colors.amberAccent, size: 20),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'អត្ថបទបកប្រែសន្ទនាខ្មែរ',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => setState(
                                  () => _isEditingScript = !_isEditingScript),
                              icon: Icon(
                                  _isEditingScript
                                      ? Icons.visibility_rounded
                                      : Icons.edit_note_rounded,
                                  size: 16,
                                  color: Colors.cyanAccent),
                              label: Text(
                                _isEditingScript ? 'មើលក្រឡោន' : 'កែសម្រួល',
                                style: const TextStyle(
                                    color: Colors.cyanAccent,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                backgroundColor:
                                    Colors.cyanAccent.withValues(alpha: 0.1),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
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
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13, height: 1.5),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none),
                              hintText: 'សរសេរ ឬកែសម្រួលអត្ថបទនៅទីនេះ...',
                              hintStyle: const TextStyle(
                                  color: Colors.white24, fontSize: 12),
                            ),
                          ),
                        ] else ...[
                          _buildDialogueLinesPreview(),
                        ],
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            icon: _isReGenerating
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.refresh_rounded, size: 20),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _isReGenerating
                                    ? 'កំពុងបង្កើតសំឡេងឡើងវិញ...'
                                    : '🔄 បង្កើតសំឡេងឡើងវិញ (Re-generate)',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _isReGenerating
                                ? null
                                : _reGenerateVoiceAndRemux,
                          ),
                        ),
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
