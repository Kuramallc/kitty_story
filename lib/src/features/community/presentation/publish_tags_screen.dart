import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/verify_email_sheet.dart';
import '../../stories/domain/story.dart';
import '../data/community_repository.dart';
import '../domain/published_story.dart';
import '../../../common/errors.dart';
import '../../../common/widgets/paced_progress.dart';

/// Moderates a generated story, shows Claude's proposed tags for editing, and
/// publishes it to the community pool.
class PublishTagsScreen extends ConsumerStatefulWidget {
  const PublishTagsScreen({super.key, required this.story});

  final Story story; // a generated story owned by the user

  @override
  ConsumerState<PublishTagsScreen> createState() => _PublishTagsScreenState();
}

/// What the moderation pass actually does, in the order it does it. Unlike the
/// story-writing copy these are not decorative: prepareStoryForPublish really
/// is one model call that judges safety and proposes tags, so saying so is
/// accurate. It is still a single request, so the bar is paced, not measured.
const _checkingMessages = [
  'Reading your story…',
  'Checking it is gentle enough for young listeners…',
  'Picking tags so other families can find it…',
];

/// Both calls are fast once the function is warm and slow on a cold start:
/// prepareStoryForPublish measured 1.9s and 2.3s warm against 24.5s cold.
///
/// Paced for the warm case. At ~2s the bar reads as real progress and
/// completes; on a cold start it reaches the ceiling early and waits there
/// with the messages still rotating, which is the designed degradation. There
/// is no single pace that covers a twelve-fold spread, and getting the common
/// path right matters more than the first call after an idle period.
const _checkingPace = Duration(seconds: 6);
const _publishingPace = Duration(seconds: 6);

class _PublishTagsScreenState extends ConsumerState<PublishTagsScreen> {
  bool _loading = true;
  bool _checked = false;
  bool _published = false;
  bool _safe = false;
  String _reason = '';
  bool _publishing = false;
  final List<String> _content = [];
  final List<String> _style = [];
  final List<String> _wisdom = [];

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final result =
          await ref.read(communityRepositoryProvider).prepareToPublish(widget.story.id);
      if (!mounted) return;
      // Let the bar reach 100% before the editor replaces it, so the check
      // reads as finished rather than interrupted.
      setState(() => _checked = true);
      await Future<void>.delayed(const Duration(milliseconds: 280));
      if (!mounted) return;
      setState(() {
        _safe = result.safe;
        _reason = result.reason;
        _content..clear()..addAll(result.tags.content);
        _style..clear()..addAll(result.tags.style);
        _wisdom..clear()..addAll(result.tags.wisdom);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      // Keep the spinner up while the verify sheet is open: dropping _loading
      // first would flash the "isn't suitable for young children" screen behind
      // it, which is the wrong reason entirely.
      if (await showVerifyEmailIfNeeded(context, error)) {
        if (mounted) context.pop(); // back to the story, ready to retry
        return;
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _safe = false;
        _reason = 'We couldn\'t check this story. Please try again.';
      });
    }
  }

  Future<void> _publish() async {
    // Capture the (root) messenger before any await so we can show the success
    // message after popping back to the story page.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _publishing = true);
    try {
      await ref.read(communityRepositoryProvider).publish(
            generatedStoryId: widget.story.id,
            tags: StoryTags(content: _content, style: _style, wisdom: _wisdom),
          );
      if (!mounted) return;
      setState(() => _published = true);
      await Future<void>.delayed(const Duration(milliseconds: 280));
      if (!mounted) return;
      context.pop(); // back to the story page
      messenger.showSnackBar(
        const SnackBar(content: Text('Published to the community 🎉')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _publishing = false);
      if (await showVerifyEmailIfNeeded(context, error)) return;
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(_friendly(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Publish story')),
      body: SafeArea(
        child: _loading
            ? _checking(theme)
            : !_safe
                ? _blocked(theme)
                : _editor(theme),
      ),
    );
  }

  /// The moderation wait. States plainly that a model is reading the story —
  /// a parent is handing something their child will hear to other families'
  /// children, and is owed a clear account of what is being done to it.
  Widget _checking(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 40, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Checking your story', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'AI reads it to make sure it stays gentle and age-appropriate, '
              'and suggests tags so other families can find it. You can edit '
              'the tags before publishing.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            PacedProgress(
              done: _checked,
              duration: _checkingPace,
              messages: _checkingMessages,
            ),
          ],
        ),
      ),
    );
  }

  Widget _blocked(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('This story can\'t be published',
                style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              _reason.isEmpty ? 'It isn\'t suitable for young children.' : _reason,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: () => context.pop(), child: const Text('Go back')),
          ],
        ),
      ),
    );
  }

  Widget _editor(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(widget.story.title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Review the tags families will use to find your story. Remove any, or add your own.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        _CategoryEditor(label: 'Content', hint: 'animals, ocean', tags: _content, onChanged: () => setState(() {})),
        _CategoryEditor(label: 'Style', hint: 'soothing, rhyming', tags: _style, onChanged: () => setState(() {})),
        _CategoryEditor(label: 'Wisdom', hint: 'kindness, courage', tags: _wisdom, onChanged: () => setState(() {})),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _publishing ? null : _publish,
          icon: const Icon(Icons.public),
          label: Text(_publishing ? 'Publishing…' : 'Publish to community'),
        ),
        if (_publishing) ...[
          const SizedBox(height: 16),
          PacedProgress(
            done: _published,
            duration: _publishingPace,
            messages: const [
              'Sharing it with the community…',
              'Adding your tags…',
            ],
          ),
        ],
      ],
    );
  }
}

String _friendly(Object error) =>
    friendlyError(error, fallback: 'Could not publish. Please try again.');


class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({
    required this.label,
    required this.hint,
    required this.tags,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final List<String> tags;
  final VoidCallback onChanged;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final t = raw.trim().toLowerCase();
    _ctrl.clear();
    if (t.isEmpty || widget.tags.contains(t) || widget.tags.length >= 8) return;
    widget.tags.add(t);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (widget.tags.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: -4,
              children: [
                for (final t in widget.tags)
                  InputChip(
                    label: Text(t),
                    onDeleted: () {
                      widget.tags.remove(t);
                      widget.onChanged();
                    },
                  ),
              ],
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            textInputAction: TextInputAction.done,
            onSubmitted: _add,
            decoration: InputDecoration(
              hintText: 'Add a tag (${widget.hint})',
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: () => _add(_ctrl.text)),
            ),
          ),
        ],
      ),
    );
  }
}
