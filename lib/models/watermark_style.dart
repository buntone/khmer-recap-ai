import 'package:flutter/material.dart';

class WatermarkFontOption {
  final String key;
  final String nameKh;
  final String englishName;
  final String category;

  const WatermarkFontOption({
    required this.key,
    required this.nameKh,
    required this.englishName,
    required this.category,
  });
}

class WatermarkColorOption {
  final String key;
  final String nameKh;
  final Color color;

  const WatermarkColorOption({
    required this.key,
    required this.nameKh,
    required this.color,
  });
}

class WatermarkStylePresets {
  static const List<WatermarkFontOption> fonts = [
    WatermarkFontOption(
      key: 'Moul',
      nameKh: 'អក្សរមូល (ក្បាច់មូឡ)',
      englishName: 'Moul (Classic Recap)',
      category: '👑 ក្បាច់ពេញនិយម',
    ),
    WatermarkFontOption(
      key: 'Moulpali',
      nameKh: 'អក្សរមូលបាលី',
      englishName: 'Moulpali',
      category: '✨ ក្បាច់បាលី',
    ),
    WatermarkFontOption(
      key: 'Preahvihear',
      nameKh: 'អក្សរព្រះវិហារ',
      englishName: 'Preahvihear',
      category: '🏛️ ក្បាច់បុរាណ',
    ),
    WatermarkFontOption(
      key: 'Koulen',
      nameKh: 'អក្សរភ្នំគូលែន',
      englishName: 'Koulen',
      category: '🔥 ក្បាច់ដិតខ្លាំង',
    ),
    WatermarkFontOption(
      key: 'Bayon',
      nameKh: 'អក្សរបាយ័ន',
      englishName: 'Bayon',
      category: '🗿 ក្បាច់ឆ្លាក់ថ្ម',
    ),
    WatermarkFontOption(
      key: 'Dangrek',
      nameKh: 'អក្សរដងរែក',
      englishName: 'Dangrek',
      category: '🎨 ក្បាច់ទាក់ទាញ',
    ),
    WatermarkFontOption(
      key: 'Bokor',
      nameKh: 'អក្សរបូកគោ',
      englishName: 'Bokor',
      category: '🎞️ បែបភាពយន្ត',
    ),
    WatermarkFontOption(
      key: 'Kdam Thmor Pro',
      nameKh: 'អក្សរក្តាមថ្ម',
      englishName: 'Kdam Thmor Pro',
      category: '⚡ បែបទំនើប',
    ),
    WatermarkFontOption(
      key: 'Kantumruy Pro',
      nameKh: 'អក្សរកន្ទុមរុយ',
      englishName: 'Kantumruy Pro',
      category: '💎 ស្អាតប្រណីត',
    ),
    WatermarkFontOption(
      key: 'Battambang',
      nameKh: 'អក្សរបាត់ដំបង',
      englishName: 'Battambang',
      category: '🌿 រលូនទន់ភ្លន់',
    ),
    WatermarkFontOption(
      key: 'Siemreap',
      nameKh: 'អក្សរសៀមរាប',
      englishName: 'Siemreap',
      category: '🌸 ស្រទន់សមរម្យ',
    ),
    WatermarkFontOption(
      key: 'Noto Sans Khmer',
      nameKh: 'ណូតូ សាន',
      englishName: 'Noto Sans Khmer',
      category: '📱 ស្តង់ដារច្បាស់',
    ),
  ];

  static const List<WatermarkColorOption> colors = [
    WatermarkColorOption(
      key: 'gold',
      nameKh: 'មាស (Gold)',
      color: Color(0xFFFFD700),
    ),
    WatermarkColorOption(
      key: 'white',
      nameKh: 'ស (White)',
      color: Color(0xFFFFFFFF),
    ),
    WatermarkColorOption(
      key: 'yellow',
      nameKh: 'លឿងភ្លឺ (Yellow)',
      color: Color(0xFFFFEE58),
    ),
    WatermarkColorOption(
      key: 'cyan',
      nameKh: 'ផ្ទៃមេឃ (Cyan)',
      color: Color(0xFF00E5FF),
    ),
    WatermarkColorOption(
      key: 'green',
      nameKh: 'បៃតងខ្ចី (Green)',
      color: Color(0xFF00E676),
    ),
    WatermarkColorOption(
      key: 'pink',
      nameKh: 'ផ្កាឈូក (Pink)',
      color: Color(0xFFFF4081),
    ),
    WatermarkColorOption(
      key: 'orange',
      nameKh: 'ទឹកក្រូច (Orange)',
      color: Color(0xFFFF9100),
    ),
    WatermarkColorOption(
      key: 'red',
      nameKh: 'ក្រហម (Red)',
      color: Color(0xFFFF1744),
    ),
    WatermarkColorOption(
      key: 'purple',
      nameKh: 'ស្វាយ (Purple)',
      color: Color(0xFFD500F9),
    ),
  ];
}
