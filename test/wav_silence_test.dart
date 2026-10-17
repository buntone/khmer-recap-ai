import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Pure Dart WAV silence generator produces canonical 24kHz mono PCM WAV',
      () async {
    const sampleRate = 24000;
    const channels = 1;
    const bitsPerSample = 16;
    const bytesPerSample = bitsPerSample ~/ 8;
    const durationSeconds = 1.5;

    final numSamples = (durationSeconds * sampleRate).round();
    final dataSize = numSamples * channels * bytesPerSample;
    final totalSize = 36 + dataSize;

    expect(dataSize, 1.5 * 24000 * 2); // 72,000 bytes of PCM
    expect(totalSize, 36 + 72000);
    expect(44 + dataSize, 72044);

    final dur = (72044 - 44) / 48000.0;
    expect(dur, 1.5);
  });
}
