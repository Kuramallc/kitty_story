import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Explains voice cloning in plain language and captures explicit consent
/// before any recording happens. The acceptance (with version + timestamp)
/// is stored on the voice doc at creation time.
class VoiceConsentScreen extends StatefulWidget {
  const VoiceConsentScreen({super.key});

  @override
  State<VoiceConsentScreen> createState() => _VoiceConsentScreenState();
}

class _VoiceConsentScreenState extends State<VoiceConsentScreen> {
  final _name = TextEditingController();
  bool _accepted = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Add a voice')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Before we record', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            const _InfoTile(
              icon: Icons.record_voice_over_outlined,
              text: 'You will read a short script for about 1–2 minutes. '
                  'We use that recording to create an AI copy of the voice '
                  'that can read bedtime stories aloud.',
            ),
            const _InfoTile(
              icon: Icons.cloud_upload_outlined,
              text: 'The recording is sent securely to ElevenLabs, our voice '
                  'technology partner, to create the voice.',
            ),
            const _InfoTile(
              icon: Icons.verified_user_outlined,
              text: 'Only record your own voice, or someone who has given you '
                  'their explicit permission. The script includes a spoken '
                  'permission statement.',
            ),
            const _InfoTile(
              icon: Icons.delete_outline,
              text: 'You can delete a voice at any time. That removes the '
                  'recording, the AI voice, and any audio made with it.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Whose voice is this?',
                hintText: 'e.g. Mom, Dad, Grandma',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _accepted,
              onChanged: (v) => setState(() => _accepted = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'I am the speaker, or I have the speaker\'s explicit '
                'permission, and I consent to creating an AI copy of this '
                'voice for use in this app.',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _accepted && _name.text.trim().isNotEmpty
                  ? () => context.push('/voices/record', extra: _name.text.trim())
                  : null,
              child: const Text('Continue to recording'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
