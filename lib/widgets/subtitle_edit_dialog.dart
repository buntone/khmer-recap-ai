import 'package:flutter/material.dart';
import '../models/subtitle_entry.dart';
import '../theme/studio_theme.dart';

class SubtitleEditDialog extends StatefulWidget {
  final SubtitleEntry entry;
  final Function(SubtitleEntry updated) onSave;

  const SubtitleEditDialog({
    super.key,
    required this.entry,
    required this.onSave,
  });

  @override
  State<SubtitleEditDialog> createState() => _SubtitleEditDialogState();
}

class _SubtitleEditDialogState extends State<SubtitleEditDialog> {
  late TextEditingController _khmerController;
  late TextEditingController _chineseController;
  late TextEditingController _startController;
  late TextEditingController _endController;
  late bool _isFemale;

  @override
  void initState() {
    super.initState();
    _khmerController = TextEditingController(text: widget.entry.khmerText);
    _chineseController = TextEditingController(text: widget.entry.chineseText);
    _startController = TextEditingController(text: widget.entry.formattedStartTime);
    _endController = TextEditingController(text: widget.entry.formattedEndTime);
    _isFemale = widget.entry.isFemale;
  }

  @override
  void dispose() {
    _khmerController.dispose();
    _chineseController.dispose();
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  void _handleSave() {
    final startMs = SubtitleEntry.parseSrtTimestamp(_startController.text);
    final endMs = SubtitleEntry.parseSrtTimestamp(_endController.text);

    final updated = widget.entry.copyWith(
      startTimeMs: startMs > 0 ? startMs : widget.entry.startTimeMs,
      endTimeMs: endMs > 0 ? endMs : widget.entry.endTimeMs,
      khmerText: _khmerController.text.trim(),
      chineseText: _chineseController.text.trim(),
      isFemale: _isFemale,
    );

    widget.onSave(updated);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: StudioTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: StudioTheme.borderCyan, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: StudioTheme.cyanAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: StudioTheme.cyanAccent, width: 1),
                        ),
                        child: Text(
                          'ឃ្លាទី ${widget.entry.index}',
                          style: const TextStyle(
                            color: StudioTheme.cyanAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'កែសម្រួលអក្សររត់ SRT',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Speaker toggle
              Row(
                children: [
                  const Text('សំឡេងអ្នកនិយាយ:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    label: const Text('👩 ស្រី'),
                    selected: _isFemale,
                    onSelected: (val) => setState(() => _isFemale = true),
                    selectedColor: StudioTheme.cyanAccent.withValues(alpha: 0.25),
                    labelStyle: TextStyle(
                      color: _isFemale ? StudioTheme.cyanAccent : Colors.white60,
                      fontWeight: _isFemale ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('👨 ប្រុស'),
                    selected: !_isFemale,
                    onSelected: (val) => setState(() => _isFemale = false),
                    selectedColor: StudioTheme.purpleAccent.withValues(alpha: 0.25),
                    labelStyle: TextStyle(
                      color: !_isFemale ? Colors.purpleAccent : Colors.white60,
                      fontWeight: !_isFemale ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Timing inputs
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ម៉ោងចាប់ផ្តើម:', style: TextStyle(color: Colors.white60, fontSize: 11)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _startController,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            fillColor: const Color(0xFF070E24),
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: StudioTheme.borderCard),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ម៉ោងបញ្ចប់:', style: TextStyle(color: Colors.white60, fontSize: 11)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _endController,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            fillColor: const Color(0xFF070E24),
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: StudioTheme.borderCard),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Khmer Text
              const Text('អត្ថបទបកប្រែជាភាសាខ្មែរ:', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: _khmerController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.4),
                decoration: InputDecoration(
                  hintText: 'បញ្ចូលអត្ថបទសម្រាយ ឬសន្ទនាខ្មែរ...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  fillColor: const Color(0xFF070E24),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: StudioTheme.borderCard),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: StudioTheme.cyanAccent),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('បោះបង់', style: TextStyle(color: Colors.white60)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: StudioTheme.cyanAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    child: const Text('រក្សាទុក', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
