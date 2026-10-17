import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsService settingsService;

  const SettingsScreen({super.key, required this.settingsService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _newKeyInputController;
  late final TextEditingController _ttsEndpointController;
  late final TextEditingController _ttsTokenController;
  late final TextEditingController _prasithVoiceController;
  late final TextEditingController _sreymomVoiceController;
  late final TextEditingController _watermarkTextController;
  late double _syncDelay;
  late bool _watermarkEnabled;
  bool _isTestingKeys = false;
  Map<String, bool?> _keyValidationStatus = {};

  @override
  void initState() {
    super.initState();
    _newKeyInputController = TextEditingController();
    _ttsEndpointController =
        TextEditingController(text: widget.settingsService.ttsEndpoint);
    _ttsTokenController =
        TextEditingController(text: widget.settingsService.ttsApiToken);
    _prasithVoiceController =
        TextEditingController(text: widget.settingsService.voicePrasithId);
    _sreymomVoiceController =
        TextEditingController(text: widget.settingsService.voiceSreymomId);
    _watermarkTextController =
        TextEditingController(text: widget.settingsService.watermarkText);
    _syncDelay = widget.settingsService.audioSyncDelay;
    _watermarkEnabled = widget.settingsService.watermarkEnabled;
  }

  @override
  void dispose() {
    _newKeyInputController.dispose();
    _ttsEndpointController.dispose();
    _ttsTokenController.dispose();
    _prasithVoiceController.dispose();
    _sreymomVoiceController.dispose();
    _watermarkTextController.dispose();
    super.dispose();
  }

  void _addKeysFromInput() {
    final text = _newKeyInputController.text.trim();
    if (text.isEmpty) return;

    widget.settingsService.addGeminiKeys(text);
    _newKeyInputController.clear();
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'បានបន្ថែម API Key ចូលក្នុង Pool រួចរាល់! (សរុប: ${widget.settingsService.geminiApiKeys.length})'),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _removeKey(String key) {
    widget.settingsService.removeGeminiKey(key);
    _keyValidationStatus.remove(key);
    setState(() {});
  }

  Future<void> _testAllKeys() async {
    final keys = widget.settingsService.geminiApiKeys;
    if (keys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('មិនមាន API Key សម្រាប់ពិនិត្យទេ! សូមបញ្ចូល Key ជាមុនសិន។'),
          backgroundColor: Colors.amber,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isTestingKeys = true);

    final results = <String, bool?>{};
    for (final key in keys) {
      try {
        final url = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models?key=$key');
        final resp = await http.get(url).timeout(const Duration(seconds: 6));
        results[key] = resp.statusCode == 200;
      } catch (_) {
        results[key] = false;
      }
    }

    if (mounted) {
      setState(() {
        _keyValidationStatus = results;
        _isTestingKeys = false;
      });

      final validCount = results.values.where((v) => v == true).length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'ការពិនិត្យបានបញ្ចប់: $validCount/${keys.length} Key មានសុពលភាព!'),
          backgroundColor:
              validCount > 0 ? const Color(0xFF10B981) : Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _saveSettings() {
    widget.settingsService.ttsEndpoint = _ttsEndpointController.text.trim();
    widget.settingsService.ttsApiToken = _ttsTokenController.text.trim();
    widget.settingsService.voicePrasithId = _prasithVoiceController.text.trim();
    widget.settingsService.voiceSreymomId = _sreymomVoiceController.text.trim();
    widget.settingsService.audioSyncDelay = _syncDelay;
    widget.settingsService.watermarkEnabled = _watermarkEnabled;
    widget.settingsService.watermarkText = _watermarkTextController.text.trim();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.greenAccent),
            SizedBox(width: 8),
            Text('បានរក្សាទុកការកំណត់ដោយជោគជ័យ! (Settings Saved)'),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _maskKey(String key) {
    if (key.length <= 10) return '••••••••';
    return '${key.substring(0, 7)}...${key.substring(key.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final keys = widget.settingsService.geminiApiKeys;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        title: const Text(
          'ការកំណត់ប្រព័ន្ធ (Settings)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.save_rounded, color: Colors.cyanAccent),
            tooltip: 'រក្សាទុក (Save)',
            onPressed: _saveSettings,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App Branding Header with New 3D Logo
            Center(
              child: Column(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.cyanAccent.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'assets/images/app_logo.png',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: const Color(0xFF1E293B),
                          child: const Icon(Icons.movie_filter_rounded,
                              color: Colors.amberAccent, size: 36),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Khmer Movie Dubbing Studio',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'AI Video Dialogue Translation & Voiceover Engine',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // Gemini Multi-Key Pool Section Card
            _buildSectionCard(
              title: '🔑 Gemini API Key Pool (ដាក់ Key បានច្រើន)',
              subtitle:
                  'ប្រព័ន្ធប្ដូរ Key ស្វ័យប្រវត្តិ (Auto-Failover) កុំឱ្យទាក់ Limit',
              icon: Icons.vpn_key_rounded,
              color: Colors.cyanAccent,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: keys.isNotEmpty
                            ? const Color(0xFF10B981).withValues(alpha: 0.15)
                            : Colors.redAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: keys.isNotEmpty
                              ? const Color(0xFF10B981)
                              : Colors.redAccent,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '🟢 មាន ${keys.length} Key ក្នុង Pool',
                        style: TextStyle(
                          color: keys.isNotEmpty
                              ? const Color(0xFF34D399)
                              : Colors.redAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _isTestingKeys ? null : _testAllKeys,
                      icon: _isTestingKeys
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.cyanAccent))
                          : const Icon(Icons.speed_rounded,
                              size: 16, color: Colors.cyanAccent),
                      label: Text(
                        _isTestingKeys ? 'កំពុងតេស្ត...' : 'តេស្ត Key ទាំងអស់',
                        style: const TextStyle(
                            color: Colors.cyanAccent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Multi-Key Paste / Input Field
                TextField(
                  controller: _newKeyInputController,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText:
                        'បិទភ្ជាប់ Key មួយ ឬច្រើននៅទីនេះ (ចុះបន្ទាត់ ឬសញ្ញាក្បៀស , )...\nAIzaSy...',
                    hintStyle:
                        const TextStyle(color: Colors.white24, fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.cyanAccent)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('➕ បន្ថែម Key ចូលក្នុង Pool (Add Keys)',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _addKeysFromInput,
                  ),
                ),

                if (keys.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 8),
                  const Text('បញ្ជី Key ដែលបានកំណត់ (Configured Keys):',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: keys.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final k = keys[index];
                      final status = _keyValidationStatus[k];
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: status == true
                                ? const Color(0xFF10B981)
                                : status == false
                                    ? Colors.redAccent
                                    : Colors.white10,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    Colors.cyanAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '#${index + 1}',
                                style: const TextStyle(
                                    color: Colors.cyanAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _maskKey(k),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'monospace',
                                    fontSize: 12),
                              ),
                            ),
                            if (status != null)
                              Icon(
                                status
                                    ? Icons.check_circle_rounded
                                    : Icons.cancel_rounded,
                                color: status
                                    ? const Color(0xFF10B981)
                                    : Colors.redAccent,
                                size: 18,
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded,
                                  color: Colors.redAccent, size: 20),
                              tooltip: 'លុប Key',
                              onPressed: () => _removeKey(k),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],

                const SizedBox(height: 8),
                const Text(
                  '💡 បង្កើត Key ដោយឥតគិតថ្លៃនៅ: aistudio.google.com/app/apikey',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Khmer TTS Engine Section
            _buildSectionCard(
              title: '🎙️ Khmer Neural TTS (សំឡេងខ្មែរ)',
              subtitle: 'Microsoft Edge Neural TTS (Piseth & Sreymom)',
              icon: Icons.record_voice_over_rounded,
              color: const Color(0xFFA855F7),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.purpleAccent.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.bolt_rounded,
                          color: Colors.amberAccent, size: 22),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'ប្រព័ន្ធប្រើ Microsoft Edge Neural TTS ផ្ទាល់ (ល្បឿនលឿន និងឥតគិតថ្លៃ មិនបាច់ដាក់ Token)',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('សំឡេង ប្រសិទ្ធ (ប្រុស)',
                              style: TextStyle(
                                  color: Colors.amberAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _prasithVoiceController,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('សំឡេង ស្រីមុំ (ស្រី)',
                              style: TextStyle(
                                  color: Colors.pinkAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _sreymomVoiceController,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Lip-Sync Audio Delay Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: Colors.amberAccent.withValues(alpha: 0.3),
                    width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.sync_rounded,
                                color: Colors.amberAccent, size: 22),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'ពន្យារពេលសំឡេងឱ្យត្រូវមាត់',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amberAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_syncDelay >= 0 ? "+" : ""}${_syncDelay.toStringAsFixed(1)}s (វិនាទី)',
                          style: const TextStyle(
                              color: Colors.amberAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'សារ៉េពន្យារពេល ឬរំកិលសំឡេងឱ្យត្រូវមាត់តួអង្គ (Default: 0.0s ធម្មជាតិ)៖ ប្រសិនបើសំឡេងចេញយឺតជាងមាត់ អាចរំកិលទៅដក (-) ប្រសិនបើសំឡេងចេញលឿនជាងមាត់ អាចរំកិលទៅបូក (+)។',
                    style: TextStyle(
                        color: Colors.white60, fontSize: 11, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.amberAccent,
                      inactiveTrackColor: Colors.white12,
                      thumbColor: Colors.amberAccent,
                      overlayColor: Colors.amberAccent.withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: _syncDelay,
                      min: -1.5,
                      max: 2.0,
                      divisions: 35,
                      onChanged: (val) => setState(() => _syncDelay = val),
                    ),
                  ),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('-1.5s (មុនមាត់)',
                          style:
                              TextStyle(color: Colors.white38, fontSize: 10)),
                      Text('0.0s (ធម្មជាតិ)',
                          style: TextStyle(
                              color: Colors.amberAccent, fontSize: 10)),
                      Text('+2.0s (ពន្យារ)',
                          style:
                              TextStyle(color: Colors.white38, fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // Section 4: Video Watermark Logo Settings
            _buildSectionCard(
              title: 'Watermark Logo លើវីដេអូ (Video Watermark)',
              subtitle: 'អក្សរស្រមោលរត់ចុះឡើងៗលើវីដេអូរហូតទាល់តែចប់',
              icon: Icons.branding_watermark_rounded,
              color: Colors.tealAccent,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('បើកដំណើរការ Watermark Logo',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                          Text('រត់ចុះឡើងៗលើវីដេអូស្វ័យប្រវត្តិ',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 11)),
                        ],
                      ),
                    ),
                    Switch(
                      value: _watermarkEnabled,
                      activeColor: Colors.tealAccent,
                      onChanged: (val) =>
                          setState(() => _watermarkEnabled = val),
                    ),
                  ],
                ),
                if (_watermarkEnabled) ...[
                  const SizedBox(height: 12),
                  const Text('អក្សរ Logo / Watermark Text:',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _watermarkTextController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'ឧ. ដោយ.B.T.movie',
                      hintStyle: const TextStyle(color: Colors.white30),
                      prefixIcon: const Icon(Icons.title_rounded,
                          color: Colors.tealAccent, size: 20),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Colors.tealAccent)),
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 24),

            // Save Action Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_rounded, size: 22),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'រក្សាទុកការកំណត់ទាំងអស់ (Save Settings)',
                    style:
                        TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                ),
                onPressed: _saveSettings,
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF131D31),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(
                      subtitle,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}
