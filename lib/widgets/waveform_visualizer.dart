import 'package:flutter/material.dart';
import '../theme/studio_theme.dart';

class WaveformVisualizerWidget extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onTogglePlay;

  const WaveformVisualizerWidget({
    super.key,
    required this.isPlaying,
    required this.onTogglePlay,
  });

  @override
  State<WaveformVisualizerWidget> createState() =>
      _WaveformVisualizerWidgetState();
}

class _WaveformVisualizerWidgetState extends State<WaveformVisualizerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  // Preset bar heights to create a realistic audio waveform shape
  static const List<double> _barHeights = [
    0.25, 0.4, 0.7, 0.5, 0.85, 0.3, 0.65, 0.9, 0.45, 0.35,
    0.6, 0.8, 0.95, 0.5, 0.75, 0.4, 0.85, 0.65, 0.3, 0.5,
    0.7, 0.9, 0.4, 0.6, 0.8, 0.35, 0.75, 0.55, 0.9, 0.3,
    0.6, 0.75, 0.4, 0.85, 0.5, 0.65, 0.4, 0.75, 0.3, 0.2
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.isPlaying) {
      _animController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant WaveformVisualizerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _animController.repeat(reverse: true);
      } else {
        _animController.stop();
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF070E24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StudioTheme.borderCard, width: 1.0),
      ),
      child: Row(
        children: [
          // Play / Pause Circle
          InkWell(
            onTap: widget.onTogglePlay,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: StudioTheme.buttonCyanPurple,
              ),
              child: Icon(
                widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Dynamic Waveform bars
          Expanded(
            child: AnimatedBuilder(
              animation: _animController,
              builder: (context, child) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(_barHeights.length, (index) {
                    final base = _barHeights[index];
                    final animFactor = widget.isPlaying
                        ? (0.7 +
                            0.3 *
                                (0.5 +
                                    0.5 *
                                        ((index % 2 == 0 ? 1 : -1) *
                                            _animController.value)))
                        : 1.0;
                    final h = (base * 26 * animFactor).clamp(4.0, 30.0);

                    // Gradient coloring across the waveform (Cyan -> Purple)
                    final t = index / _barHeights.length;
                    final barColor = Color.lerp(
                      StudioTheme.cyanAccent,
                      const Color(0xFFB5179E),
                      t,
                    )!;

                    return Container(
                      width: 2.4,
                      height: h,
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(1.5),
                        boxShadow: [
                          BoxShadow(
                            color: barColor.withValues(alpha: 0.35),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
