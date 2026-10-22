import 'package:flutter/material.dart';
import '../models/subtitle_entry.dart';
import '../theme/studio_theme.dart';
import 'subtitle_edit_dialog.dart';

class SubtitleTableWidget extends StatelessWidget {
  final List<SubtitleEntry> subtitles;
  final int activeSubtitleIndex;
  final Function(SubtitleEntry entry) onSeekToSubtitle;
  final Function(SubtitleEntry updated) onUpdateSubtitle;
  final Function(int index) onDeleteSubtitle;
  final VoidCallback onImportSrt;
  final VoidCallback onAddSubtitle;

  const SubtitleTableWidget({
    super.key,
    required this.subtitles,
    this.activeSubtitleIndex = -1,
    required this.onSeekToSubtitle,
    required this.onUpdateSubtitle,
    required this.onDeleteSubtitle,
    required this.onImportSrt,
    required this.onAddSubtitle,
  });

  void _openEditDialog(BuildContext context, SubtitleEntry entry) {
    showDialog(
      context: context,
      builder: (context) => SubtitleEditDialog(
        entry: entry,
        onSave: onUpdateSubtitle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: StudioTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StudioTheme.borderCard, width: 1.2),
      ),
      child: Column(
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // SRT Subtitle badge
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: StudioTheme.cyanAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.subtitles_rounded,
                    color: StudioTheme.cyanAccent,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SRT Subtitle',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
                      Text(
                        'កែអក្សរ / បកប្រែ / វាយតម្លៃ',
                        style: TextStyle(
                          color: StudioTheme.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                // Import SRT button
                InkWell(
                  onTap: onImportSrt,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1B4B),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: StudioTheme.purpleAccent.withValues(alpha: 0.8),
                        width: 1,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.file_upload_outlined,
                            color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'នាំចូល SRT',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Add / Edit button
                InkWell(
                  onTap: onAddSubtitle,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: StudioTheme.borderCard,
                        width: 1,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_note_rounded,
                            color: StudioTheme.cyanAccent, size: 15),
                        SizedBox(width: 4),
                        Text(
                          'កែសម្រួល',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: StudioTheme.borderCard),

          // Subtitle Entries List
          if (subtitles.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 36),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Icon(Icons.closed_caption_off_rounded,
                      color: Colors.white.withValues(alpha: 0.3), size: 40),
                  const SizedBox(height: 8),
                  const Text(
                    'មិនទាន់មានអក្សររត់ SRT នៅឡើយទេ',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'ចុច «នាំចូល SRT» ឬ «បង្កើតសំឡេងខ្មែរ» ដើម្បីឱ្យ AI បកប្រែដោយស្វ័យប្រវត្តិ',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: subtitles.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Color(0xFF131D3F)),
              itemBuilder: (context, index) {
                final entry = subtitles[index];
                final isActive = activeSubtitleIndex == entry.index;

                return InkWell(
                  onTap: () => onSeekToSubtitle(entry),
                  child: Container(
                    color: isActive
                        ? StudioTheme.cyanAccent.withValues(alpha: 0.12)
                        : Colors.transparent,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Row Index
                        SizedBox(
                          width: 20,
                          child: Text(
                            '${entry.index}',
                            style: TextStyle(
                              color: isActive
                                  ? StudioTheme.cyanAccent
                                  : Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Timing & Khmer Text
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    entry.formattedStartTime,
                                    style: const TextStyle(
                                      color: StudioTheme.cyanAccent,
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const Text(
                                    ' ➔ ',
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 9,
                                    ),
                                  ),
                                  Text(
                                    entry.formattedEndTime,
                                    style: const TextStyle(
                                      color: StudioTheme.cyanAccent,
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: entry.isFemale
                                          ? StudioTheme.cyanAccent
                                              .withValues(alpha: 0.15)
                                          : StudioTheme.purpleAccent
                                              .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      entry.isFemale ? 'ស្រី' : 'ប្រុស',
                                      style: TextStyle(
                                        color: entry.isFemale
                                            ? StudioTheme.cyanAccent
                                            : Colors.purpleAccent,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                entry.khmerText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // Actions (Edit, Delete, Seek)
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              color: Colors.white60, size: 16),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(6),
                          onPressed: () => _openEditDialog(context, entry),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.white38, size: 16),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(6),
                          onPressed: () => onDeleteSubtitle(entry.index),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: StudioTheme.cyanAccent,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
