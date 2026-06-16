import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/community_repository.dart';
import '../domain/published_story.dart';

class ExploreState {
  const ExploreState({
    this.items = const [],
    this.filterTags = const [],
    this.loading = false,
    this.loadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<PublishedStory> items;
  final List<String> filterTags;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final Object? error;

  ExploreState copyWith({
    List<PublishedStory>? items,
    List<String>? filterTags,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) {
    return ExploreState(
      items: items ?? this.items,
      filterTags: filterTags ?? this.filterTags,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Drives the Explore feed: filter-by-tags + likes-sorted pagination.
class ExploreController extends Notifier<ExploreState> {
  DocumentSnapshot<Map<String, dynamic>>? _cursor;

  @override
  ExploreState build() {
    Future.microtask(refresh);
    return const ExploreState(loading: true);
  }

  CommunityRepository get _repo => ref.read(communityRepositoryProvider);

  Future<void> setFilter(List<String> tags) async {
    state = state.copyWith(filterTags: tags);
    await refresh();
  }

  Future<void> refresh() async {
    _cursor = null;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final page = await _repo.fetchExplore(tags: state.filterTags);
      _cursor = page.lastDoc;
      state = state.copyWith(items: page.items, loading: false, hasMore: page.hasMore);
    } catch (error) {
      state = state.copyWith(loading: false, error: error);
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final page = await _repo.fetchExplore(tags: state.filterTags, startAfter: _cursor);
      _cursor = page.lastDoc;
      state = state.copyWith(
        items: [...state.items, ...page.items],
        loadingMore: false,
        hasMore: page.hasMore,
      );
    } catch (error) {
      state = state.copyWith(loadingMore: false, error: error);
    }
  }
}

final exploreControllerProvider =
    NotifierProvider.autoDispose<ExploreController, ExploreState>(
        ExploreController.new);
