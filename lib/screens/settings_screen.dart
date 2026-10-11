import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsService settingsService;

  const SettingsScreen({Key? key, required this.settingsService}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _geminiApiKeyController;
  late final TextEditingController _ttsEndpointController;
  late final TextEditingController _ttsTokenController;
  late final TextEditingController _prasithVoiceController;
  late final TextEditingController _sreymomVoiceController;
  bool _obscureGeminiKey = true;
  bool _obscureTtsToken = true;

  @override
  void initState() {
    super.initState();
    _geminiApiKeyController = TextEditingController(text: widget.settingsService.geminiApiKey);
    _ttsEndpointController = TextEditingController(text: widget.settingsService.ttsEndpoint);
    _ttsTokenController = TextEditingController(text: widget.settingsService.ttsApiToken);
    _prasithVoiceController = TextEditingController(text: widget.settingsService.voicePrasithId);
    _sreymomVoiceController = TextEditingController(text: widget.settingsService.voiceSreymomId);
  }

  @override
  void dispose() {
    _geminiApiKeyController.dispose();
    _ttsEndpointController.dispose();
    _ttsTokenController.dispose();
    _prasithVoiceController.dispose();
    _sreymomVoiceController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    widget.settingsService.geminiApiKey = _geminiApiKeyController.text.trim();
    widget.settingsService.ttsEndpoint = _ttsEndpointController.text.trim();
    widget.settingsService.ttsApiToken = _ttsTokenController.text.trim();
    widget.settingsService.voicePrasithId = _prasithVoiceController.text.trim();
    widget.settingsService.voiceSreymomId = _sreymomVoiceController.text.trim();

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text(
          'ការកំណត់ប្រព័ន្ធ (Settings)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.save_rounded, color: Colors.amber),
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
            // Gemini Section Card
            _buildSectionCard(
              title: '🤖 Google Gemini AI Configuration',
              subtitle: 'បម្រើការសម្រាប់វិភាគវីដេអូ និងតែងនិពន្ធអត្ថបទសម្រាយរឿងខ្មែរ',
              icon: Icons.psychology_rounded,
              color: Colors.blueAccent,
              children: [
                const Text(
                  'Gemini API Key:',
                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _geminiApiKeyController,
                  obscureText: _obscureGeminiKey,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'AIzaSy...',
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    prefixIcon: const Icon(Icons.key, color: Colors.blueAccent, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureGeminiKey ? Icons.visibility : Icons.visibility_off,
                        color: Colors.white38,
                      ),
                      onPressed: () => setState(() => _obscureGeminiKey = !_obscureGeminiKey),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.blueAccent)),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'ទទួលយក Key ដោយឥតគិតថ្លៃនៅ: aistudio.google.com',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Khmer TTS Section Card
            _buildSectionCard(
              title: '🎙️ Khmer TTS Engine Configuration',
              subtitle: 'ម៉ាស៊ីនបំប្លែងអត្ថបទទៅជាសំឡេងខ្មែរ Prasith & Sreymom',
              icon: Icons.record_voice_over_rounded,
              color: Colors.purpleAccent,
              children: [
                const Text(
                  'TTS REST Endpoint URL:',
                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _ttsEndpointController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'https://api.khmervoice.ai/v1/tts',
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    prefixIcon: const Icon(Icons.link, color: Colors.purpleAccent, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.purpleAccent)),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'API Bearer Token (ប្រសិនបើមាន):',
                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _ttsTokenController,
                  obscureText: _obscureTtsToken,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Bearer Token / API Key',
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    prefixIcon: const Icon(Icons.lock_outline, color: Colors.purpleAccent, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureTtsToken ? Icons.visibility : Icons.visibility_off,
                        color: Colors.white38,
                      ),
                      onPressed: () => setState(() => _obscureTtsToken = !_obscureTtsToken),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.purpleAccent)),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white12),
                const SizedBox(height: 8),
                const Text(
                  'Voice ID Mapping (ការកំណត់អត្តសញ្ញាណសំឡេង):',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('សំឡេង ប្រសិទ្ធ (ប្រុស)', style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _prasithVoiceController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
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
                          const Text('សំឡេង ស្រីមុំ (ស្រី)', style: TextStyle(color: Colors.pinkAccent, fontSize: 12)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _sreymomVoiceController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Save Action Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check, size: 22),
                label: const Text(
                  'រក្សាទុកការកំណត់ទាំងអស់ (Save All Settings)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
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
                  color: color.withOpacity(0.15),
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
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
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
