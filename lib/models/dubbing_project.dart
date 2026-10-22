import 'subtitle_entry.dart';

class DubbingProject {
  final String id;
  String title;
  String videoPath;
  double durationSeconds;
  String? thumbnailPath;
  List<SubtitleEntry> subtitles;
  String selectedVoice; // 'female' or 'male'
  double speechRate; // 0.8x to 1.5x
  DateTime updatedAt;

  DubbingProject({
    required this.id,
    required this.title,
    required this.videoPath,
    this.durationSeconds = 0.0,
    this.thumbnailPath,
    required this.subtitles,
    this.selectedVoice = 'female',
    this.speechRate = 1.0,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'videoPath': videoPath,
        'durationSeconds': durationSeconds,
        'thumbnailPath': thumbnailPath,
        'subtitles': subtitles.map((s) => s.toJson()).toList(),
        'selectedVoice': selectedVoice,
        'speechRate': speechRate,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory DubbingProject.fromJson(Map<String, dynamic> json) => DubbingProject(
        id: json['id'] ?? '',
        title: json['title'] ?? 'Untitled Project',
        videoPath: json['videoPath'] ?? '',
        durationSeconds: (json['durationSeconds'] ?? 0.0).toDouble(),
        thumbnailPath: json['thumbnailPath'],
        subtitles: (json['subtitles'] as List<dynamic>? ?? [])
            .map((e) => SubtitleEntry.fromJson(e))
            .toList(),
        selectedVoice: json['selectedVoice'] ?? 'female',
        speechRate: (json['speechRate'] ?? 1.0).toDouble(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'])
            : DateTime.now(),
      );
}
