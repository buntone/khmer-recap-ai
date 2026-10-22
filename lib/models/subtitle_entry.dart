class SubtitleEntry {
  final int index;
  int startTimeMs;
  int endTimeMs;
  String chineseText;
  String khmerText;
  bool isFemale;

  SubtitleEntry({
    required this.index,
    required this.startTimeMs,
    required this.endTimeMs,
    this.chineseText = '',
    required this.khmerText,
    this.isFemale = true,
  });

  String get formattedStartTime => _formatTime(startTimeMs);
  String get formattedEndTime => _formatTime(endTimeMs);
  String get formattedTimeRange => '$formattedStartTime  ➔  $formattedEndTime';

  static String _formatTime(int ms) {
    final totalSeconds = ms ~/ 1000;
    final milliseconds = ms % 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    final hh = hours.toString().padLeft(2, '0');
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    final mmm = milliseconds.toString().padLeft(3, '0');
    return '$hh:$mm:$ss,$mmm';
  }

  static int parseSrtTimestamp(String timestamp) {
    try {
      final parts = timestamp.trim().replaceAll(',', '.').split(':');
      if (parts.length == 3) {
        final hours = int.parse(parts[0]);
        final minutes = int.parse(parts[1]);
        final secondsParts = parts[2].split('.');
        final seconds = int.parse(secondsParts[0]);
        final ms = secondsParts.length > 1
            ? int.parse(secondsParts[1].padRight(3, '0').substring(0, 3))
            : 0;
        return (hours * 3600 + minutes * 60 + seconds) * 1000 + ms;
      }
    } catch (_) {}
    return 0;
  }

  SubtitleEntry copyWith({
    int? index,
    int? startTimeMs,
    int? endTimeMs,
    String? chineseText,
    String? khmerText,
    bool? isFemale,
  }) {
    return SubtitleEntry(
      index: index ?? this.index,
      startTimeMs: startTimeMs ?? this.startTimeMs,
      endTimeMs: endTimeMs ?? this.endTimeMs,
      chineseText: chineseText ?? this.chineseText,
      khmerText: khmerText ?? this.khmerText,
      isFemale: isFemale ?? this.isFemale,
    );
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'startTimeMs': startTimeMs,
        'endTimeMs': endTimeMs,
        'chineseText': chineseText,
        'khmerText': khmerText,
        'isFemale': isFemale,
      };

  factory SubtitleEntry.fromJson(Map<String, dynamic> json) => SubtitleEntry(
        index: json['index'] ?? 1,
        startTimeMs: json['startTimeMs'] ?? 0,
        endTimeMs: json['endTimeMs'] ?? 0,
        chineseText: json['chineseText'] ?? '',
        khmerText: json['khmerText'] ?? '',
        isFemale: json['isFemale'] ?? true,
      );
}
