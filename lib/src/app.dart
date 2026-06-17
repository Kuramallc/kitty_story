import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      title: 'Kitty Story',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
