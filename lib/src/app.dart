import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/player/presentation/mini_player.dart';
import 'features/subscription/data/subscription_repository.dart';
import 'routing/app_router.dart';
import 'theme/app_theme.dart';

/// Root widget. Wires the router and themes into a [MaterialApp.router].
class KittyStoryApp extends ConsumerWidget {
  const KittyStoryApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    // Keep RevenueCat's identified user in sync with Firebase auth.
    ref.watch(subscriptionSyncProvider);
    return MaterialApp.router(
      title: 'Kitty Stories',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
      // The now-playing bar lives above the route, so it survives navigation
      // and is reachable from wherever the user wandered off to.
      builder: (context, child) => Column(
        children: [
          Expanded(child: child ?? const SizedBox.shrink()),
          const MiniPlayer(),
        ],
      ),
    );
  }
}
