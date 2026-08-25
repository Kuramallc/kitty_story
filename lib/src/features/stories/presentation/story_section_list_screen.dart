import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/widgets/async_value_widget.dart';

/// Full list for one Stories-home section ("Created by me", "Community",
/// "Sample"), reached via that section's "View all" button.
///
/// Every section is already backed by a realtime Firestore `snapshots()`
/// stream of the *whole* (user-scoped or curated) collection — there's no
/// server-side cursor to page through. So "infinite scroll" here means
/// revealing the already-synced list in batches as the user nears the
/// bottom, instead of building every card up front.
class SectionListScreen<T> extends ConsumerStatefulWidget {
  const SectionListScreen({
    super.key,
    required this.title,
    required this.watch,
    required this.cardBuilder,
    required this.emptyMessage,
  });

  final String title;

  /// Watches the section's underlying stream provider. Passed as a callback
  /// (rather than the provider itself) so callers don't need to name
  /// riverpod's internal `ProviderListenable` type.
  final AsyncValue<List<T>> Function(WidgetRef ref) watch;
  final Widget Function(T item) cardBuilder;
  final String emptyMessage;

  @override
  ConsumerState<SectionListScreen<T>> createState() =>
      _SectionListScreenState<T>();
}

class _SectionListScreenState<T> extends ConsumerState<SectionListScreen<T>> {
  static const _pageSize = 20;
  int _visibleCount = _pageSize;
  // Updated as a side effect of build() so the scroll listener (which can't
  // itself call ref.watch/read outside the build phase) knows how much more
  // there is to reveal.
  int _totalCount = 0;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels < _scroll.position.maxScrollExtent - 320) return;
    if (_visibleCount < _totalCount) {
      setState(() => _visibleCount += _pageSize);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: AsyncValueWidget<List<T>>(
          value: widget.watch(ref),
          data: (list) {
            _totalCount = list.length;
            if (list.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    widget.emptyMessage,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              );
            }
            final visible = list.take(_visibleCount).toList();
            final hasMore = visible.length < list.length;
            return ListView.separated(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: visible.length + (hasMore ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == visible.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return widget.cardBuilder(visible[index]);
              },
            );
          },
        ),
      ),
    );
  }
}
