import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Pure Dart implementation of Microsoft Edge Neural TTS with Sec-MS-GEC v2 DRM
/// Enables crystal-clear Khmer Piseth (km-KH-PisethNeural) and Sreymom (km-KH-SreymomNeural)
/// without third-party API keys or external server dependencies.
class EdgeTtsV2 {
  static const int winEpoch = 11644473600;
  static const double sToNs = 1e9;
  static const String trustedClientToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  static const String chromiumFullVersion = '143.0.3650.75';
  static const String chromiumMajorVersion = '143';
  static const String secMsGecVersion = '2-$chromiumFullVersion';
  static const String wssUrl =
      'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1';

  static const int _u32Mask = 0xFFFFFFFF;

  static const List<int> _sha256Initial = [
    0x6A09E667,
    0xBB67AE85,
    0x3C6EF372,
    0xA54FF53A,
    0x510E527F,
    0x9B05688C,
    0x1F83D9AB,
    0x5BE0CD19,
  ];

  static const List<int> _sha256State = [
    0xFD9FBEA2,
    0x91243CE7,
    0xBE499094,
    0xCD2E1E0A,
    0x6C006F49,
    0x04BD35AB,
    0xFEB0A7E4,
    0x03EFFBD2,
  ];

  static const List<int> _sha256Schedule = [
    0xEB24BF9E,
    0x1558691F,
    0xA0C09EE2,
    0x0CFA32BA,
    0xA622EE8C,
    0xD1DD9491,
    0xC0DD25A0,
    0xF9E70AB6,
    0xF0C31573,
    0x7058CE4E,
    0x7188E606,
    0x00E5AB33,
    0xD258B060,
    0x72766564,
  ];

  static const List<int> _sha256RoundConstants = [
    0x428A2F98,
    0x71374491,
    0xB5C0FBCF,
    0xE9B5DBA5,
    0x3956C25B,
    0x59F111F1,
    0x923F82A4,
    0xAB1C5ED5,
    0xD807AA98,
    0x12835B01,
    0x243185BE,
    0x550C7DC3,
    0x72BE5D74,
    0x80DEB1FE,
    0x9BDC06A7,
    0xC19BF174,
    0xE49B69C1,
    0xEFBE4786,
    0x0FC19DC6,
    0x240CA1CC,
    0x2DE92C6F,
    0x4A7484AA,
    0x5CB0A9DC,
    0x76F988DA,
    0x983E5152,
    0xA831C66D,
    0xB00327C8,
    0xBF597FC7,
    0xC6E00BF3,
    0xD5A79147,
    0x06CA6351,
    0x14292967,
    0x27B70A85,
    0x2E1B2138,
    0x4D2C6DFC,
    0x53380D13,
    0x650A7354,
    0x766A0ABB,
    0x81C2C92E,
    0x92722C85,
    0xA2BFE8A1,
    0xA81A664B,
    0xC24B8B70,
    0xC76C51A3,
    0xD192E819,
    0xD6990624,
    0xF40E3585,
    0x106AA070,
    0x19A4C116,
    0x1E376C08,
    0x2748774C,
    0x34B0BCB5,
    0x391C0CB3,
    0x4ED8AA4A,
    0x5B9CCA4F,
    0x682E6FF3,
    0x748F82EE,
    0x78A5636F,
    0x84C87814,
    0x8CC70208,
    0x90BEFFFA,
    0xA4506CEB,
    0xBEF9A3F7,
    0xC67178F2,
  ];

  static const int _sha256Adjustment = 0xC9DC06A7;
  static final List<int> _sha256BlockConstants = [
    ..._sha256RoundConstants.sublist(0, 14),
    _sha256Adjustment,
    ..._sha256RoundConstants.sublist(15),
  ];

  static const int _sha256Sigma0Adjustment = 0x059C0B80;
  static const int _sha256Sigma1Adjustment = 0x000B92C0;

  static const List<List<int>> _cs64Coefficients = [
    [0xE82E91B1, 0xB32700D0],
    [0x44DE24C6, 0x88DFF51D],
    [0x3BEB65BC, 0x29514038],
    [0xC89C5933, 0xB328CBDF],
    [0x8D1EC211, 0xD405B4D5],
    [0x314EF5D5, 0x26E55F3C],
    [0xE92491B1, 0x607801C6],
    [0xF0A5B9D5, 0x82B2C1FB],
    [0x06064CF3, 0xFA51A3DA],
    [0xDA79FA60, 0x207CC464],
    [0xBED20560, 0x3C3C74F3],
    [0x89F9C9F8, 0xD2D14B61],
    [0x35FA38C6, 0xBB04A2C1],
    [0xCB49E3C6, 0xC5626167],
  ];

  static const int _cs64Factor = 0x82893933;
  static const int _cs64Adjustment0 = 0xF2F90B1A;
  static const int _cs64Adjustment1 = 0x0B1A0000;

  static double _clockSkewSeconds = 0.0;
  static bool _clockCalibrated = false;

  static int _rol16(int value) {
    value &= _u32Mask;
    return (((value << 16) | (value >>> 16)) & _u32Mask);
  }

  static List<int> _wordsLe4Even(Uint8List data) {
    final rem = (-data.length) % 4;
    final padCount = (rem + 4) % 4;
    final padded = Uint8List(data.length + padCount);
    padded.setRange(0, data.length, data);
    if (padded.isEmpty) return [];
    final byteData = ByteData.sublistView(padded);
    final List<int> words = [];
    for (int i = 0; i < padded.length; i += 4) {
      words.add(byteData.getUint32(i, Endian.little));
    }
    if (words.length % 2 != 0) {
      words.add(0);
    }
    return words;
  }

  static int _sigma0(int value) {
    value &= _u32Mask;
    return ((value >>> 7) ^
            (value << 25) ^
            (value >>> 18) ^
            (value << 14) ^
            (value >>> 3)) &
        _u32Mask;
  }

  static int _sigma1(int value) {
    value &= _u32Mask;
    return ((value >>> 17) ^
            (value << 15) ^
            (value >>> 19) ^
            (value << 13) ^
            (value >>> 10)) &
        _u32Mask;
  }

  static List<int> _sha256Rounds(List<int> state, List<int> words,
      [int firstRound = 0]) {
    int a = state[0], b = state[1], c = state[2], d = state[3];
    int e = state[4], f = state[5], g = state[6], h = state[7];
    const mask = _u32Mask;
    final constants =
        (firstRound == 14) ? _sha256BlockConstants : _sha256RoundConstants;

    final aligned = ((firstRound + 7) ~/ 8) * 8;
    final limit = aligned < 64 ? aligned : 64;

    for (int index = firstRound; index < limit; index++) {
      final rotE = (e & mask) * 0x100000001;
      final rotA = (a & mask) * 0x100000001;
      final t1 = (h +
              ((rotE >>> 6) ^ (rotE >>> 11) ^ (rotE >>> 25)) +
              (g ^ (e & (f ^ g))) +
              constants[index] +
              words[index]) &
          mask;
      final t2 = (((rotA >>> 2) ^ (rotA >>> 13) ^ (rotA >>> 22)) +
              ((a & b) | (c & (a | b)))) &
          mask;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & mask;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & mask;
    }

    for (int index = limit; index < 64; index += 8) {
      var rotE = (e & mask) * 0x100000001;
      var rotA = (a & mask) * 0x100000001;
      var t1 = (h +
              ((rotE >>> 6) ^ (rotE >>> 11) ^ (rotE >>> 25)) +
              (g ^ (e & (f ^ g))) +
              constants[index] +
              words[index]) &
          mask;
      d = (d + t1) & mask;
      h = (t1 +
              ((rotA >>> 2) ^ (rotA >>> 13) ^ (rotA >>> 22)) +
              ((a & b) | (c & (a | b)))) &
          mask;

      rotE = (d & mask) * 0x100000001;
      rotA = (h & mask) * 0x100000001;
      t1 = (g +
              ((rotE >>> 6) ^ (rotE >>> 11) ^ (rotE >>> 25)) +
              (f ^ (d & (e ^ f))) +
              constants[index + 1] +
              words[index + 1]) &
          mask;
      c = (c + t1) & mask;
      g = (t1 +
              ((rotA >>> 2) ^ (rotA >>> 13) ^ (rotA >>> 22)) +
              ((h & a) | (b & (h | a)))) &
          mask;

      rotE = (c & mask) * 0x100000001;
      rotA = (g & mask) * 0x100000001;
      t1 = (f +
              ((rotE >>> 6) ^ (rotE >>> 11) ^ (rotE >>> 25)) +
              (e ^ (c & (d ^ e))) +
              constants[index + 2] +
              words[index + 2]) &
          mask;
      b = (b + t1) & mask;
      f = (t1 +
              ((rotA >>> 2) ^ (rotA >>> 13) ^ (rotA >>> 22)) +
              ((g & h) | (a & (g | h)))) &
          mask;

      rotE = (b & mask) * 0x100000001;
      rotA = (f & mask) * 0x100000001;
      t1 = (e +
              ((rotE >>> 6) ^ (rotE >>> 11) ^ (rotE >>> 25)) +
              (d ^ (b & (c ^ d))) +
              constants[index + 3] +
              words[index + 3]) &
          mask;
      a = (a + t1) & mask;
      e = (t1 +
              ((rotA >>> 2) ^ (rotA >>> 13) ^ (rotA >>> 22)) +
              ((f & g) | (h & (f | g)))) &
          mask;

      rotE = (a & mask) * 0x100000001;
      rotA = (e & mask) * 0x100000001;
      t1 = (d +
              ((rotE >>> 6) ^ (rotE >>> 11) ^ (rotE >>> 25)) +
              (c ^ (a & (b ^ c))) +
              constants[index + 4] +
              words[index + 4]) &
          mask;
      h = (h + t1) & mask;
      d = (t1 +
              ((rotA >>> 2) ^ (rotA >>> 13) ^ (rotA >>> 22)) +
              ((e & f) | (g & (e | f)))) &
          mask;

      rotE = (h & mask) * 0x100000001;
      rotA = (d & mask) * 0x100000001;
      t1 = (c +
              ((rotE >>> 6) ^ (rotE >>> 11) ^ (rotE >>> 25)) +
              (b ^ (h & (a ^ b))) +
              constants[index + 5] +
              words[index + 5]) &
          mask;
      g = (g + t1) & mask;
      c = (t1 +
              ((rotA >>> 2) ^ (rotA >>> 13) ^ (rotA >>> 22)) +
              ((d & e) | (f & (d | e)))) &
          mask;

      rotE = (g & mask) * 0x100000001;
      rotA = (c & mask) * 0x100000001;
      t1 = (b +
              ((rotE >>> 6) ^ (rotE >>> 11) ^ (rotE >>> 25)) +
              (a ^ (g & (h ^ a))) +
              constants[index + 6] +
              words[index + 6]) &
          mask;
      f = (f + t1) & mask;
      b = (t1 +
              ((rotA >>> 2) ^ (rotA >>> 13) ^ (rotA >>> 22)) +
              ((c & d) | (e & (c | d)))) &
          mask;

      rotE = (f & mask) * 0x100000001;
      rotA = (b & mask) * 0x100000001;
      t1 = (a +
              ((rotE >>> 6) ^ (rotE >>> 11) ^ (rotE >>> 25)) +
              (h ^ (f & (g ^ h))) +
              constants[index + 7] +
              words[index + 7]) &
          mask;
      e = (e + t1) & mask;
      a = (t1 +
              ((rotA >>> 2) ^ (rotA >>> 13) ^ (rotA >>> 22)) +
              ((b & c) | (d & (b | c)))) &
          mask;
    }

    return [a, b, c, d, e, f, g, h];
  }

  static void _expandSha256Schedule(List<int> words, [int firstWord = 16]) {
    const mask = _u32Mask;
    for (int index = firstWord; index < 64; index++) {
      final x = words[index - 2];
      final y = words[index - 15];
      final s1 =
          ((x >>> 17) ^ (x << 15) ^ (x >>> 19) ^ (x << 13) ^ (x >>> 10)) & mask;
      final s0 =
          ((y >>> 7) ^ (y << 25) ^ (y >>> 18) ^ (y << 14) ^ (y >>> 3)) & mask;
      final val = (s1 + words[index - 7] + s0 + words[index - 16]) & mask;
      if (index < words.length) {
        words[index] = val;
      } else {
        words.add(val);
      }
    }
  }

  static List<int> _sha256Init(Uint8List data) {
    const mask = _u32Mask;
    final words = List<int>.filled(14, 0, growable: true);
    words.add(((data[0] << 16) | (data[1] << 8) | data[2]) & mask);
    words.add(
        ((data[3] << 24) | (data[4] << 16) | (data[5] << 8) | data[6]) & mask);

    for (int index = 16; index < 30; index++) {
      int value = _sha256Schedule[index - 16];
      if (index - 2 >= 14) {
        value += (index == 16)
            ? (_sigma1(words[index - 2]) ^ _sha256Sigma1Adjustment)
            : _sigma1(words[index - 2]);
      }
      if (index - 7 >= 14) {
        value += words[index - 7];
      }
      if (index - 15 >= 14) {
        value += (index == 29)
            ? (_sigma0(words[index - 15]) ^ _sha256Sigma0Adjustment)
            : _sigma0(words[index - 15]);
      }
      words.add(value & mask);
    }

    words.add((_sigma1(words[28]) +
            words[23] +
            _sigma0(words[15]) +
            words[14] +
            _sha256Adjustment -
            _sha256RoundConstants[14]) &
        mask);

    _expandSha256Schedule(words, 31);
    final working = _sha256Rounds(_sha256State, words, 14);
    return List.generate(8, (i) => (_sha256Initial[i] + working[i]) & mask);
  }

  static Uint8List _sha256Digest(Uint8List data) {
    if (data.length < 7) {
      throw ArgumentError('Token salt must contain at least 7 bytes');
    }
    const mask = _u32Mask;
    final length = 57 + data.length;
    final padLen = ((55 - length) % 64 + 64) % 64;
    final padded = Uint8List(data.length - 7 + 1 + padLen + 8);
    padded.setRange(0, data.length - 7, data.sublist(7));
    padded[data.length - 7] = 0x80;
    final bd = ByteData.sublistView(padded);
    bd.setUint64(padded.length - 8, length * 8, Endian.big);

    var state = _sha256Init(data.sublist(0, 7));
    for (int offset = 0; offset < padded.length; offset += 64) {
      final words = List<int>.generate(
          16, (i) => bd.getUint32(offset + i * 4, Endian.big),
          growable: true);
      _expandSha256Schedule(words);
      final working = _sha256Rounds(state, words);
      state = List.generate(8, (i) => (state[i] + working[i]) & mask);
    }

    final outBd = ByteData(32);
    for (int i = 0; i < 8; i++) {
      outBd.setUint32(i * 4, state[i], Endian.big);
    }
    return outBd.buffer.asUint8List();
  }

  static List<int> _cs64Digest(Uint8List data, Uint8List digest) {
    const mask = _u32Mask;
    final digestBd = ByteData.sublistView(digest);
    int keyA = digestBd.getUint32(0, Endian.little) | 1;
    int keyB = digestBd.getUint32(4, Endian.little) | 1;

    final factors = [
      (keyA * _cs64Factor) & mask,
      (keyB * _cs64Factor) & mask,
    ];

    final List<int> terms = [];
    final List<int> offsets = [];

    for (int i = 0; i < _cs64Coefficients.length; i++) {
      final coeff = _cs64Coefficients[i][0];
      final off = _cs64Coefficients[i][1];
      terms.add((coeff * factors[i % 2]) & mask);
      offsets.add(off & mask);
    }

    final prefixZeroData = Uint8List(data.length + 1);
    prefixZeroData[0] = 0;
    prefixZeroData.setRange(1, prefixZeroData.length, data);

    final words = _wordsLe4Even(prefixZeroData);
    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      int term = (word * (i % 2 == 0 ? keyA : keyB)) & mask;
      int offset =
          (_rol16(word) * (i % 2 == 0 ? 0xEF0569FB : 0xC31713DB)) & mask;
      if (i == 0) {
        term = (term + _cs64Adjustment0 * factors[0]) & mask;
        offset = (offset + _cs64Adjustment1) & mask;
      }
      terms.add(term);
      offsets.add(offset);
    }

    int swapAcc = 0;
    int swapLast = 0;
    int state = 0;
    int acc = 0;

    for (int i = 0; i < terms.length; i += 2) {
      final x = terms[i];
      final y = terms[i + 1];
      int t = _rol16((offsets[i] + x) & mask);
      int q = (t * 0x76F50F34) & mask;
      swapAcc = (swapAcc + (_rol16(q) * 0xC3EFEA97 + q)) & mask;

      t = _rol16((offsets[i + 1] + y) & mask);
      q = (t * 0x1881CE3C) & mask;
      swapLast = ((_rol16(q) * 0x35BD1EC9 + q)) & mask;
      swapAcc = (swapAcc + swapLast) & mask;

      state = (state * keyA + x) & mask;
      state = (_rol16(state) * 0xCF98B111) & mask;
      state = (_rol16(state) * 0x87085B9F) & mask;
      state = (_rol16(state) * 0x12CEB96D) & mask;
      state = (_rol16(state) * 0x257E1D83) & mask;
      acc += state;

      t = (state * keyB + y) & mask;
      t = (_rol16(t) * 0xA27416F5) & mask;
      t = (_rol16(t) * 0xD38396FF) & mask;
      state = (_rol16((_rol16(t) * 0x7C932B89) & mask) * 0xBFA49F69) & mask;
      acc = (acc + state) & mask;
    }

    return [(swapLast ^ state) & mask, (swapAcc ^ acc) & mask];
  }

  static String _bytesToHexUpper(Uint8List bytes) {
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('')
        .toUpperCase();
  }

  static String generateSecMsGecV2([double? unixTimestamp]) {
    double nowSec = unixTimestamp ??
        ((DateTime.now().toUtc().millisecondsSinceEpoch / 1000.0) +
            _clockSkewSeconds);
    nowSec += winEpoch;
    nowSec -= nowSec % 300;
    nowSec *= sToNs / 100;
    final strToHash = '${nowSec.toStringAsFixed(0)}$trustedClientToken';
    final data = Uint8List.fromList(ascii.encode(strToHash));

    final digest = _sha256Digest(data);
    final cs64Words = _cs64Digest(data, digest);

    final cs64Bd = ByteData(8);
    cs64Bd.setUint32(0, cs64Words[0], Endian.little);
    cs64Bd.setUint32(4, cs64Words[1], Endian.little);

    final cs64Hex = _bytesToHexUpper(cs64Bd.buffer.asUint8List());
    final sha256Hex = _bytesToHexUpper(digest);

    return '$cs64Hex-$sha256Hex';
  }

  static Future<void> calibrateClock({bool force = false}) async {
    if (_clockCalibrated && !force) return;
    try {
      final client = HttpClient()..userAgent = null;
      final req =
          await client.headUrl(Uri.parse('https://speech.platform.bing.com'));
      final resp = await req.close().timeout(const Duration(seconds: 4));
      final serverDateStr = resp.headers.value('date');
      if (serverDateStr != null) {
        final serverTime = HttpDate.parse(serverDateStr);
        final clientTime = DateTime.now().toUtc();
        _clockSkewSeconds = (serverTime.millisecondsSinceEpoch -
                clientTime.millisecondsSinceEpoch) /
            1000.0;
        _clockCalibrated = true;
      }
      await resp.drain();
      client.close();
    } catch (_) {}
  }

  static String generateMuid() {
    final random = Random.secure();
    return List.generate(32, (_) => random.nextInt(16).toRadixString(16))
        .join()
        .toUpperCase();
  }

  static String generateUuidHex() {
    final random = Random.secure();
    return List.generate(32, (_) => random.nextInt(16).toRadixString(16))
        .join();
  }

  static String generateTimestamp() {
    final now = DateTime.now().toUtc();
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final wd = weekdays[now.weekday - 1];
    final mo = months[now.month - 1];
    final d = now.day.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final mi = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return '$wd $mo $d ${now.year} $h:$mi:$s GMT+0000 (Coordinated Universal Time)';
  }

  static String _voiceShortToLong(String shortName) {
    final match =
        RegExp(r'^([a-z]{2,})-([A-Z]{2,})-(.+Neural)$').firstMatch(shortName);
    if (match != null) {
      final locale = '${match.group(1)}-${match.group(2)}';
      final name = match.group(3);
      return 'Microsoft Server Speech Text to Speech Voice ($locale, $name)';
    }
    return shortName;
  }

  static String _xmlEscape(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static List<String> _splitText(String text, [int maxChunkSize = 3500]) {
    text = text.replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]'), ' ');
    if (utf8.encode(text).length <= maxChunkSize) return [text];

    final chunks = <String>[];
    var remaining = text;
    while (remaining.isNotEmpty) {
      if (utf8.encode(remaining).length <= maxChunkSize) {
        chunks.add(remaining);
        break;
      }
      int split = maxChunkSize;
      if (split > remaining.length) split = remaining.length;
      final candidate = remaining.substring(0, split);
      int lastNewline = candidate.lastIndexOf('\n');
      if (lastNewline > 0) {
        split = lastNewline + 1;
      } else {
        int lastSpace = candidate.lastIndexOf(' ');
        if (lastSpace > 0) {
          split = lastSpace + 1;
        }
      }
      chunks.add(remaining.substring(0, split));
      remaining = remaining.substring(split);
    }
    return chunks;
  }

  /// Synthesizes speech to MP3 byte array using Microsoft Edge TTS with v2 DRM authentication
  static Future<Uint8List> synthesize({
    required String text,
    required String voice,
    String rate = '+0%',
    String pitch = '+0Hz',
    String volume = '+0%',
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return Uint8List(0);
    final chunks = _splitText(clean);
    final builder = BytesBuilder(copy: false);

    for (final chunk in chunks) {
      try {
        final bytes = await _synthesizeInternal(
          text: chunk,
          voice: voice,
          rate: rate,
          pitch: pitch,
          volume: volume,
        );
        if (bytes.isNotEmpty) {
          builder.add(bytes);
          continue;
        }
      } catch (_) {}

      // Fast single retry with clock calibration
      try {
        await calibrateClock(force: true);
        final bytes = await _synthesizeInternal(
          text: chunk,
          voice: voice,
          rate: rate,
          pitch: pitch,
          volume: volume,
        );
        if (bytes.isNotEmpty) {
          builder.add(bytes);
        }
      } catch (_) {}
    }
    return builder.toBytes();
  }

  static Future<Uint8List> _synthesizeInternal({
    required String text,
    required String voice,
    required String rate,
    required String pitch,
    required String volume,
  }) async {
    final connectionId = generateUuidHex();
    final requestId = generateUuidHex();
    final gec = generateSecMsGecV2();
    final muid = generateMuid();

    final wsUrlString = '$wssUrl?TrustedClientToken=$trustedClientToken'
        '&ConnectionId=$connectionId'
        '&Sec-MS-GEC=$gec'
        '&Sec-MS-GEC-Version=$secMsGecVersion';

    final httpClient = HttpClient()..userAgent = null;
    final ws = await WebSocket.connect(
      wsUrlString,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/$chromiumMajorVersion.0.0.0 Safari/537.36 '
                'Edg/$chromiumMajorVersion.0.0.0',
        'Accept-Encoding': 'gzip, deflate, br, zstd',
        'Accept-Language': 'en-US,en;q=0.9',
        'Pragma': 'no-cache',
        'Cache-Control': 'no-cache',
        'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
        'Sec-WebSocket-Version': '13',
        'Cookie': 'muid=$muid;',
      },
      compression: CompressionOptions.compressionOff,
      customClient: httpClient,
    ).timeout(const Duration(seconds: 4));

    final timestamp = generateTimestamp();
    final configMsg = 'X-Timestamp:$timestamp\r\n'
        'Content-Type:application/json; charset=utf-8\r\n'
        'Path:speech.config\r\n'
        '\r\n'
        '{"context":{"synthesis":{"audio":{"metadataoptions":'
        '{"sentenceBoundaryEnabled":"false",'
        '"wordBoundaryEnabled":"false"}'
        ',"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}';
    ws.add(configMsg);

    final longVoice = _voiceShortToLong(voice);
    final escaped = _xmlEscape(text);
    // Microsoft Read Aloud protocol requires xml:lang='en-US' at root <speak> tag
    final ssml =
        "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' "
        "xml:lang='en-US'>"
        "<voice name='$longVoice'>"
        "<prosody pitch='$pitch' rate='$rate' volume='$volume'>"
        '$escaped'
        '</prosody></voice></speak>';

    final ssmlMsg = 'X-RequestId:$requestId\r\n'
        'Content-Type:application/ssml+xml\r\n'
        'X-Timestamp:${timestamp}Z\r\n'
        'Path:ssml\r\n'
        '\r\n'
        '$ssml';
    ws.add(ssmlMsg);

    final builder = BytesBuilder(copy: false);
    final completer = Completer<Uint8List>();

    final sub = ws.listen(
      (message) {
        if (message is String) {
          if (message.contains('Path:turn.end')) {
            if (!completer.isCompleted) {
              completer.complete(builder.toBytes());
            }
          }
        } else if (message is List<int>) {
          if (message.length > 2) {
            final headerLength = (message[0] << 8) | message[1];
            if (message.length >= 2 + headerLength) {
              final headerText = ascii.decode(
                  message.sublist(2, 2 + headerLength),
                  allowInvalid: true);
              if (headerText.contains('Content-Type:audio/mpeg')) {
                final audioBytes = message.sublist(2 + headerLength);
                builder.add(audioBytes);
              }
            }
          }
        }
      },
      onError: (err) {
        if (!completer.isCompleted) {
          final partial = builder.toBytes();
          if (partial.length > 100) {
            completer.complete(partial);
          } else {
            completer.completeError(err);
          }
        }
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete(builder.toBytes());
      },
      cancelOnError: true,
    );

    try {
      final result =
          await completer.future.timeout(const Duration(seconds: 5));
      return result;
    } on TimeoutException {
      final partial = builder.toBytes();
      if (partial.length > 100) {
        return partial;
      }
      rethrow;
    } finally {
      await sub.cancel();
      try {
        await ws.close();
      } catch (_) {}
    }
  }
}
