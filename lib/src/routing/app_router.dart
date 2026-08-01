import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../common/providers/firebase_providers.dart';
import '../features/account/presentation/account_screen.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/home/home_screen.dart';
import '../features/voices/presentation/voice_consent_screen.dart';
import '../features/voices/presentation/voice_record_screen.dart';
import '../features/voices/presentation/voices_screen.dart';
import '../features/stories/domain/story.dart';
import '../features/stories/presentation/generate_story_screen.dart';
import '../features/stories/presentation/stories_screen.dart';
import '../features/stories/presentation/story_detail_screen.dart';
import '../features/player/presentation/player_screen.dart';
import '../features/community/domain/published_story.dart';
import '../features/community/presentation/community_detail_screen.dart';
import '../features/community/presentation/explore_screen.dart';
import '../features/community/presentation/publish_tags_screen.dart';
import 'go_router_refresh_stream.dart';

/// App router with auth gating. When Firebase isn't configured we skip gating
/// entirely so the app still boots (the home shows a setup notice).
final appRouterProvider = Provider<GoRouter>((ref) {
  final firebaseReady = ref.watch(firebaseReadyProvider);
  final authRepository = firebaseReady ? ref.watch(authRepositoryProvider) : null;

  return GoRouter(
    initialLocation: '/',
    // Only refresh on a real signed-in/out transition — not on hourly token
    // refreshes, which would rebuild the navigator and drop route `extra`.
    refreshListenable: authRepository == null
        ? null
        : GoRouterRefreshStream(
            authRepository.authStateChanges().map((u) => u != null).distinct(),
          ),
    redirect: (context, state) {
      if (authRepository == null) return null; // Firebase not configured.
      final loggedIn = authRepository.currentUser != null;
      final atSignIn = state.matchedLocation == '/sign-in';
      if (!loggedIn) return atSignIn ? null : '/sign-in';
      if (atSignIn) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/sign-in',
        name: 'signIn',
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: '/account',
        name: 'account',
        builder: (context, state) => const AccountScreen(),
      ),
      GoRoute(
        path: '/voices',
        name: 'voices',
        builder: (context, state) => const VoicesScreen(),
      ),
      GoRoute(
        path: '/voices/consent',
        name: 'voiceConsent',
        builder: (context, state) => const VoiceConsentScreen(),
      ),
      GoRoute(
        path: '/voices/record',
        name: 'voiceRecord',
        builder: (context, state) => VoiceRecordScreen(
          voiceName: (state.extra as String?) ?? 'My voice',
        ),
      ),
      GoRoute(
        path: '/stories',
        name: 'stories',
        builder: (context, state) => const StoriesScreen(),
      ),
      GoRoute(
        path: '/stories/generate',
        name: 'storyGenerate',
        builder: (context, state) => const GenerateStoryScreen(),
      ),
      GoRoute(
        path: '/stories/detail',
        name: 'storyDetail',
        builder: (context, state) => StoryDetailScreen(story: state.extra as Story),
      ),
      GoRoute(
        path: '/player',
        name: 'player',
        builder: (context, state) => PlayerScreen(args: state.extra as PlayerArgs),
      ),
      GoRoute(
        path: '/explore',
        name: 'explore',
        builder: (context, state) => const ExploreScreen(),
      ),
      GoRoute(
        path: '/explore/story/:id',
        name: 'communityDetail',
        builder: (context, state) => CommunityDetailScreen(
          storyId: state.pathParameters['id']!,
          initial: state.extra as PublishedStory?,
        ),
      ),
      GoRoute(
        path: '/stories/publish',
        name: 'publishStory',
        builder: (context, state) => PublishTagsScreen(story: state.extra as Story),
      ),
    ],
  );
});
