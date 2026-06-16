import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../stories/domain/story.dart';
import '../data/community_repository.dart';
import '../domain/published_story.dart';

/// Moderates a generated story, shows Claude's proposed tags for editing, and
/// publishes it to the community pool.
class PublishTagsScreen extends ConsumerStatefulWidget {
  const PublishTagsScreen({super.key, required this.story});

  final Story story; // a generated story owned by the user

  @override
  ConsumerState<PublishTagsScreen> createState() => _PublishTagsScreenState();
}

class _PublishTagsScreenState extends ConsumerState<PublishTagsScreen> {
  bool _loading = true;
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
      setState(() {
        _safe = result.safe;
        _reason = result.reason;
        _content..clear()..addAll(result.tags.content);
        _style..clear()..addAll(result.tags.style);
        _wisdom..clear()..addAll(result.tags.wisdom);
        _loading = false;
      });
    } catch (_) {
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
      context.pop(); // back to the story page
      messenger.showSnackBar(
        const SnackBar(content: Text('Published to the community 🎉')),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _publishing = false);
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
            ? const _Centered(child: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Checking your story…'),
              ])
            : !_safe
                ? _blocked(theme)
                : _editor(theme),
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
          icon: _publishing
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.public),
          label: Text(_publishing ? 'Publishing…' : 'Publish to community'),
        ),
      ],
    );
  }
}

String _friendly(Object error) {
  final s = error.toString();
  final i = s.indexOf('] ');
  return i >= 0 ? s.substring(i + 2) : 'Could not publish. Please try again.';
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final List<Widget> child;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: child),
      );
}

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
