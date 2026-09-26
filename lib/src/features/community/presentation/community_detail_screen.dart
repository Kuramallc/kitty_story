import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/verify_email_sheet.dart';
import '../../player/presentation/tell_in_voice.dart';
import '../data/community_repository.dart';
import '../domain/published_story.dart';
import '../../../common/errors.dart';

/// A community story: read it, like it, open a slide-up comment sheet, or hit
/// Play (which saves it to your library and starts telling it in a voice).
///
/// Fetches by [storyId] so it survives navigator rebuilds; [initial] (passed
/// from the Explore card) avoids a round-trip when available.
class CommunityDetailScreen extends ConsumerStatefulWidget {
  const CommunityDetailScreen({super.key, required this.storyId, this.initial});

  final String storyId;
  final PublishedStory? initial;

  @override
  ConsumerState<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends ConsumerState<CommunityDetailScreen> {
  PublishedStory? _story;
  bool _loadFailed = false;
  int _likeCount = 0;
  bool _liking = false;
  bool _busyPlay = false;

  CommunityRepository get _repo => ref.read(communityRepositoryProvider);
  late final Stream<bool> _likedStream = _repo.watchLiked(widget.storyId);
  late final Stream<int> _commentCountStream =
      _repo.watchComments(widget.storyId).map((c) => c.length);
  late final Stream<bool> _savedStream =
      _repo.watchArchivedFlag(widget.storyId);

  @override
  void initState() {
    super.initState();
    _story = widget.initial;
    _likeCount = widget.initial?.likeCount ?? 0;
    if (_story == null) _load();
  }

  Future<void> _load() async {
    try {
      final s = await _repo.fetchPublished(widget.storyId);
      if (!mounted) return;
      // Treat removed / under-review stories as gone (e.g. opened from Saved).
      final available = s != null && s.status == 'published';
      setState(() {
        _story = available ? s : null;
        _likeCount = s?.likeCount ?? 0;
        _loadFailed = !available;
      });
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _toggleLike() async {
    if (_liking) return;
    setState(() => _liking = true);
    try {
      final r = await _repo.toggleLike(widget.storyId);
      if (mounted) setState(() => _likeCount = r.likeCount);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not update like.')));
      }
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  /// Save the story to the user's library, then start telling it in a voice.
  /// Saves the story to the user's library, or removes it if already saved.
  Future<void> _toggleSave(bool saved) async {
    final story = _story;
    if (story == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (saved) {
        await _repo.unarchive(widget.storyId);
        messenger.showSnackBar(
          const SnackBar(content: Text('Removed from your stories.')),
        );
      } else {
        await _repo.archive(story);
        messenger.showSnackBar(
          const SnackBar(content: Text('Saved to your stories.')),
        );
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not update your library: ${friendlyError(error)}')),
      );
    }
  }

  Future<void> _play() async {
    final story = _story;
    if (story == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyPlay = true);
    try {
      await _repo.archive(story);
    } catch (_) {
      // Non-fatal: still try to play.
    }
    messenger.showSnackBar(const SnackBar(content: Text('Saved to your library')));
    if (mounted) {
      await tellStoryInVoice(context, ref, story.toStory(), story.title);
    }
    if (mounted) setState(() => _busyPlay = false);
  }

  void _openComments() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CommentSheet(storyId: widget.storyId),
    );
  }

  Future<void> _report() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Report this story')),
            for (final r in const ['Not appropriate for kids', 'Spam', 'Other'])
              ListTile(title: Text(r), onTap: () => Navigator.pop(context, r)),
          ],
        ),
      ),
    );
    if (reason == null) return;
    final accepted = await _repo.report(widget.storyId, reason);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accepted
              ? 'Thanks — we\'ll take a look.'
              : "Thanks — you've already reported this story."),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = _story;
    if (story == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: _loadFailed
              ? const Text('That story is no longer available.')
              : const CircularProgressIndicator(),
        ),
      );
    }

    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(story.title),
        actions: [
          // Saving is the action people reach for up here; reporting moved
          // down beside the other per-story actions, where its red colour
          // makes it obvious it is not a way to keep the story.
          StreamBuilder<bool>(
            stream: _savedStream,
            builder: (context, snap) {
              final saved = snap.data ?? false;
              return IconButton(
                icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
                tooltip: saved ? 'Remove from my stories' : 'Save to my stories',
                onPressed: () => _toggleSave(saved),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          children: [
            Text(story.title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('Shared by a Kitty Stories family',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (story.tags.all.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: -6,
                children: [
                  for (final t in story.tags.all)
                    Chip(label: Text(t), visualDensity: VisualDensity.compact),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text(story.text, style: theme.textTheme.bodyLarge?.copyWith(height: 1.6)),
          ],
        ),
      ),
      bottomNavigationBar: _ActionBar(
        likeCount: _likeCount,
        liking: _liking,
        busyPlay: _busyPlay,
        likedStream: _likedStream,
        commentCountStream: _commentCountStream,
        onLike: _toggleLike,
        onComment: _openComments,
        onReport: _report,
        onPlay: _play,
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.likeCount,
    required this.liking,
    required this.busyPlay,
    required this.likedStream,
    required this.commentCountStream,
    required this.onLike,
    required this.onComment,
    required this.onReport,
    required this.onPlay,
  });

  final int likeCount;
  final bool liking;
  final bool busyPlay;
  final Stream<bool> likedStream;
  final Stream<int> commentCountStream;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onReport;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
          child: Row(
            children: [
              StreamBuilder<bool>(
                stream: likedStream,
                builder: (context, snap) {
                  final liked = snap.data ?? false;
                  return TextButton.icon(
                    onPressed: liking ? null : onLike,
                    icon: Icon(liked ? Icons.favorite : Icons.favorite_border,
                        color: liked ? theme.colorScheme.primary : null),
                    label: Text('$likeCount'),
                  );
                },
              ),
              StreamBuilder<int>(
                stream: commentCountStream,
                builder: (context, snap) => TextButton.icon(
                  onPressed: onComment,
                  icon: const Icon(Icons.mode_comment_outlined),
                  label: Text('${snap.data ?? 0}'),
                ),
              ),
              // Red, and sitting apart from the counts, so it reads as
              // "report this" rather than another way to keep the story.
              IconButton(
                onPressed: onReport,
                icon: const Icon(Icons.flag_outlined),
                color: theme.colorScheme.error,
                tooltip: 'Report this story',
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: busyPlay ? null : onPlay,
                icon: busyPlay
                    ? const SizedBox(
                        height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: Text(busyPlay ? 'Preparing…' : 'Play'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// TikTok-style slide-up comment sheet: scrollable comments with an input
/// pinned above the keyboard.
class _CommentSheet extends ConsumerStatefulWidget {
  const _CommentSheet({required this.storyId});

  final String storyId;

  @override
  ConsumerState<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends ConsumerState<_CommentSheet> {
  final _ctrl = TextEditingController();
  bool _posting = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _posting) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _posting = true);
    try {
      await ref.read(communityRepositoryProvider).addComment(widget.storyId, text);
      _ctrl.clear();
    } catch (error) {
      if (!mounted) return;
      if (!await showVerifyEmailIfNeeded(context, error)) {
        messenger.showSnackBar(SnackBar(content: Text(_friendlyComment(error))));
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Comments', style: theme.textTheme.titleMedium),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<List<StoryComment>>(
                stream: ref.read(communityRepositoryProvider).watchComments(widget.storyId),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final comments = snap.data!;
                  if (comments.isEmpty) {
                    return Center(
                      child: Text('No comments yet. Be the first!',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    itemCount: comments.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 18)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(comments[i].text, style: theme.textTheme.bodyMedium)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        enabled: !_posting,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _post(),
                        decoration: const InputDecoration(
                          hintText: 'Add a kind comment…',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _posting ? null : _post,
                      icon: _posting
                          ? const SizedBox(
                              height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _friendlyComment(Object error) =>
    friendlyError(error, fallback: 'Could not post that comment.');
