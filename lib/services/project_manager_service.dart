import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/dubbing_project.dart';
import '../models/subtitle_entry.dart';

class ProjectManagerService {
  static const String _keyProjects = 'studio_saved_projects_v2';
  final SharedPreferences _prefs;

  ProjectManagerService(this._prefs);

  static Future<ProjectManagerService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return ProjectManagerService(prefs);
  }

  List<DubbingProject> getProjects() {
    try {
      final rawList = _prefs.getStringList(_keyProjects) ?? [];
      return rawList.map((str) => DubbingProject.fromJson(jsonDecode(str))).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      debugPrint('Error reading projects: $e');
      return [];
    }
  }

  Future<void> saveProject(DubbingProject project) async {
    final list = getProjects();
    final index = list.indexWhere((p) => p.id == project.id);
    project.updatedAt = DateTime.now();

    if (index >= 0) {
      list[index] = project;
    } else {
      list.insert(0, project);
    }

    final rawList = list.map((p) => jsonEncode(p.toJson())).toList();
    await _prefs.setStringList(_keyProjects, rawList);
  }

  Future<void> deleteProject(String id) async {
    final list = getProjects()..removeWhere((p) => p.id == id);
    final rawList = list.map((p) => jsonEncode(p.toJson())).toList();
    await _prefs.setStringList(_keyProjects, rawList);
  }

  /// Parses an SRT file into a list of SubtitleEntry items
  static List<SubtitleEntry> parseSrtFile(String content) {
    final List<SubtitleEntry> entries = [];
    final blocks = content.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'));

    int fallbackIndex = 1;
    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length >= 2) {
        int index = fallbackIndex;
        int timeLineIdx = 0;

        if (int.tryParse(lines[0].trim()) != null) {
          index = int.parse(lines[0].trim());
          timeLineIdx = 1;
        }

        if (lines.length > timeLineIdx && lines[timeLineIdx].contains('-->')) {
          final timeParts = lines[timeLineIdx].split('-->');
          final startMs = SubtitleEntry.parseSrtTimestamp(timeParts[0]);
          final endMs = SubtitleEntry.parseSrtTimestamp(timeParts[1]);

          final textLines = lines.sublist(timeLineIdx + 1).join('\n').trim();
          final isFemale = textLines.contains('[ស្រី]') ||
              textLines.toLowerCase().contains('female');

          // Clean tags if present
          final cleanText = textLines
              .replaceAll(RegExp(r'\[(ស្រី|ប្រុស|female|male)\][:\s]*', caseSensitive: false), '')
              .trim();

          entries.add(SubtitleEntry(
            index: index,
            startTimeMs: startMs,
            endTimeMs: endMs,
            khmerText: cleanText,
            isFemale: isFemale,
          ));
          fallbackIndex++;
        }
      }
    }
    return entries;
  }

  /// Generates a standard UTF-8 SRT string from SubtitleEntry list
  static String generateSrtContent(List<SubtitleEntry> entries) {
    final buffer = StringBuffer();
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      buffer.writeln('${i + 1}');
      buffer.writeln('${e.formattedStartTime} --> ${e.formattedEndTime}');
      final speakerTag = e.isFemale ? '[ស្រី]: ' : '[ប្រុស]: ';
      buffer.writeln('$speakerTag${e.khmerText}');
      buffer.writeln();
    }
    return buffer.toString();
  }
}
