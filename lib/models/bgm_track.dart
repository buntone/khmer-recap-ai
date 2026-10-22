import 'package:flutter/material.dart';

class BgmTrack {
  final String id;
  final String nameKh;
  final String category;
  final String descriptionKh;
  final String? assetPath;
  final IconData icon;
  final Color color;

  const BgmTrack({
    required this.id,
    required this.nameKh,
    required this.category,
    required this.descriptionKh,
    this.assetPath,
    required this.icon,
    this.color = const Color(0xFF6366F1),
  });

  bool get isNone => id == 'none' || assetPath == null || assetPath!.isEmpty;

  static const List<BgmTrack> presets = [
    BgmTrack(
      id: 'original',
      nameKh: 'សំឡេងដើម (Auto-Ducking)',
      category: 'Original Audio',
      descriptionKh: 'រក្សាសំឡេងដើមពីវីដេអូ និងសង្កត់សំឡេងខ្មែរពីលើកុំឱ្យឮសំឡេងចិន',
      assetPath: null,
      icon: Icons.movie_filter_rounded,
      color: Color(0xFF00E676),
    ),
    BgmTrack(
      id: 'action',
      nameKh: 'វាយប្រហារ កក្រើក',
      category: 'Action / Fight',
      descriptionKh: 'ស័ក្តិសមសម្រាប់ឈុតប្រយុទ្ធ ក្បាច់គុន និងវាយតប់ជក់ចិត្ត',
      assetPath: 'assets/audio/recap_action.mp3',
      icon: Icons.flash_on_rounded,
      color: Color(0xFFFF5722),
    ),
    BgmTrack(
      id: 'suspense',
      nameKh: 'រន្ធត់ តានតឹង',
      category: 'Suspense / Thriller',
      descriptionKh: 'ស័ក្តិសមសម្រាប់ឈុតដេញតាម រត់គេចខ្លួន និងរឿងឃាតកម្ម',
      assetPath: 'assets/audio/recap_suspense.mp3',
      icon: Icons.warning_amber_rounded,
      color: Color(0xFFE91E63),
    ),
    BgmTrack(
      id: 'mystery',
      nameKh: 'អាថ៌កំបាំង ស៊ើបអង្កេត',
      category: 'Mystery / Detective',
      descriptionKh: 'ស័ក្តិសមសម្រាប់ឈុតលួចចូល ស៊ើបអង្កេត និងលាតត្រដាងការពិត',
      assetPath: 'assets/audio/recap_mystery.mp3',
      icon: Icons.psychology_rounded,
      color: Color(0xFF9C27B0),
    ),
    BgmTrack(
      id: 'epic',
      nameKh: 'វីរភាព អស្ចារ្យ',
      category: 'Epic / Adventure',
      descriptionKh: 'ស័ក្តិសមសម្រាប់រឿងផ្សងព្រេង វីរបុរស និងឈុតបញ្ចប់ធំៗ',
      assetPath: 'assets/audio/recap_epic.mp3',
      icon: Icons.auto_awesome_rounded,
      color: Color(0xFFFFB300),
    ),
    BgmTrack(
      id: 'drama',
      nameKh: 'មនោសញ្ចេតនា កម្សត់',
      category: 'Drama / Emotional',
      descriptionKh: 'ស័ក្តិសមសម្រាប់ឈុតសោកសៅ បែកបាក់ និងការចងចាំ',
      assetPath: 'assets/audio/recap_drama.mp3',
      icon: Icons.favorite_rounded,
      color: Color(0xFF00BCD4),
    ),
    BgmTrack(
      id: 'dark',
      nameKh: 'ខ្មៅងងឹត ព្រឺព្រួច',
      category: 'Dark / Horror',
      descriptionKh: 'ស័ក្តិសមសម្រាប់ឈុតខ្មោច គ្រោះថ្នាក់ និងភាពភ័យខ្លាច',
      assetPath: 'assets/audio/recap_dark.mp3',
      icon: Icons.nightlight_round,
      color: Color(0xFF673AB7),
    ),
    BgmTrack(
      id: 'emotional',
      nameKh: 'ស្រទន់ រៀបរាប់',
      category: 'Cinematic Ambient',
      descriptionKh: 'ភ្លេងរៀបរាប់ស្រាលៗ ជួយឱ្យសំឡេងនិយាយកាន់តែច្បាស់ល្អ',
      assetPath: 'assets/audio/recap_emotional.mp3',
      icon: Icons.music_note_rounded,
      color: Color(0xFF4CAF50),
    ),
    BgmTrack(
      id: 'none',
      nameKh: 'គ្មានភ្លេង (សំឡេងនិយាយសុទ្ធ)',
      category: 'Voice Only',
      descriptionKh: 'បិទភ្លេងទាំងអស់ ទុកតែសំឡេងអានសម្រាយរឿងសុទ្ធ ១០០%',
      assetPath: null,
      icon: Icons.volume_off_rounded,
      color: Color(0xFF78909C),
    ),
  ];

  bool get isOriginal => id == 'original';

  static BgmTrack getById(String? id) {
    if (id == null) return presets.first;
    return presets.firstWhere(
      (t) => t.id == id,
      orElse: () => presets.first,
    );
  }
}
