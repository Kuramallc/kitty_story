import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/verify_email_sheet.dart';
import '../data/story_repository.dart';
import '../../../common/widgets/paced_progress.dart';
import '../../../common/widgets/page_width.dart';
import '../../../common/errors.dart';

const _ageRanges = ['2-3 years', '4-5 years', '6-8 years'];

/// Shown one after another while the story is being written. Pacing copy, not
/// backend stages — generation is a single request with nothing to report
/// mid-flight — so these describe the shape of a story rather than claiming
/// anything about what the server is doing at that instant.
const _writingMessages = [
  'Thinking of a beginning…',
  'Choosing who the story is about…',
  'Finding a gentle middle…',
  'Winding things down for bedtime…',
  'Reading it back one more time…',
];

/// Form that collects a few prompts and asks the backend to generate a
/// kid-safe story, then opens it in the detail screen.
class GenerateStoryScreen extends ConsumerStatefulWidget {
  const GenerateStoryScreen({super.key});

  @override
  ConsumerState<GenerateStoryScreen> createState() =>
      _GenerateStoryScreenState();
}

class _GenerateStoryScreenState extends ConsumerState<GenerateStoryScreen> {
  final _childName = TextEditingController();
  final _theme = TextEditingController();
  final _characters = TextEditingController();
  String _ageRange = _ageRanges[1];
  bool _loading = false;
  bool _arrived = false;

  @override
  void dispose() {
    _childName.dispose();
    _theme.dispose();
    _characters.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _arrived = false;
    });
    try {
      final story = await ref
          .read(storyRepositoryProvider)
          .generateStory(
            childName: _childName.text.trim(),
            theme: _theme.text.trim(),
            characters: _characters.text.trim(),
            ageRange: _ageRange,
          );
      if (!mounted) return;
      // Let the bar visibly finish before the screen changes. Without this the
      // story replaces a half-full bar, which reads as the wait being cut off
      // rather than completed.
      setState(() => _arrived = true);
      await Future<void>.delayed(const Duration(milliseconds: 280));
      if (mounted) context.pushReplacement('/stories/detail', extra: story);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _arrived = false;
      });
      if (await showVerifyEmailIfNeeded(context, error)) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create the story: ${friendlyError(error)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Create a story')),
      body: SafeArea(
        child: PageWidth(
          maxWidth: kFormWidth,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Tell us a little, and we\'ll write a gentle, original bedtime '
                'story. Everything is kept calm and age-appropriate.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _childName,
                enabled: !_loading,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Child\'s name (optional)',
                  hintText: 'e.g. Maya',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _theme,
                enabled: !_loading,
                decoration: const InputDecoration(
                  labelText: 'Theme or setting',
                  hintText: 'e.g. a cozy forest, the moon, a sleepy train',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _characters,
                enabled: !_loading,
                decoration: const InputDecoration(
                  labelText: 'Characters (optional)',
                  hintText: 'e.g. a little fox and a wise owl',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _ageRange,
                decoration: const InputDecoration(
                  labelText: 'Age',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final a in _ageRanges)
                    DropdownMenuItem(value: a, child: Text(a)),
                ],
                onChanged: _loading
                    ? null
                    : (v) => setState(() => _ageRange = v ?? _ageRange),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loading ? null : _generate,
                icon: const Icon(Icons.auto_awesome),
                label: Text(_loading ? 'Writing your story…' : 'Create story'),
              ),
              if (_loading) ...[
                const SizedBox(height: 24),
                PacedProgress(done: _arrived, messages: _writingMessages),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
