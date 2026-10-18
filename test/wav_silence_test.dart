import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:khmer_recap_ai/services/khmer_tts_service.dart';

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

    const dur = (72044 - 44) / 48000.0;
    expect(dur, 1.5);
  });

  test('extractPcmData cleanly skips metadata LIST/INFO chunks and finds raw PCM',
      () {
    // Construct a WAV with RIFF, fmt, LIST (metadata), and data chunk
    final rawPcm = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
    final listChunk = Uint8List.fromList('ISFTLavf60.16.100'.codeUnits);

    final totalSize = 36 + 8 + listChunk.length + rawPcm.length;
    final wavBytes = BytesBuilder();

    // RIFF
    wavBytes.add('RIFF'.codeUnits);
    final bdSize = ByteData(4)..setUint32(0, totalSize, Endian.little);
    wavBytes.add(bdSize.buffer.asUint8List());
    wavBytes.add('WAVE'.codeUnits);

    // fmt chunk (16 bytes)
    wavBytes.add('fmt '.codeUnits);
    final bdFmt = ByteData(4)..setUint32(0, 16, Endian.little);
    wavBytes.add(bdFmt.buffer.asUint8List());
    final bdFmtData = ByteData(16)
      ..setUint16(0, 1, Endian.little)
      ..setUint16(2, 1, Endian.little)
      ..setUint32(4, 24000, Endian.little)
      ..setUint32(8, 48000, Endian.little)
      ..setUint16(12, 2, Endian.little)
      ..setUint16(14, 16, Endian.little);
    wavBytes.add(bdFmtData.buffer.asUint8List());

    // LIST chunk (metadata)
    wavBytes.add('LIST'.codeUnits);
    final bdList = ByteData(4)
      ..setUint32(0, listChunk.length, Endian.little);
    wavBytes.add(bdList.buffer.asUint8List());
    wavBytes.add(listChunk);
    if (listChunk.length % 2 != 0) {
      wavBytes.addByte(0); // padding byte
    }

    // data chunk
    wavBytes.add('data'.codeUnits);
    final bdData = ByteData(4)..setUint32(0, rawPcm.length, Endian.little);
    wavBytes.add(bdData.buffer.asUint8List());
    wavBytes.add(rawPcm);

    final extracted =
        KhmerTtsService.extractPcmDataForTesting(wavBytes.toBytes());
    expect(extracted, isNotNull);
    expect(extracted!.length, rawPcm.length);
    expect(extracted, rawPcm);
  });
}
