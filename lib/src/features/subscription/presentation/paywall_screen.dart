import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../common/legal_urls.dart';
import '../data/subscription_repository.dart';

/// Shows the upgrade paywall as a bottom sheet. [reason] is an optional line
/// explaining why it appeared (e.g. the limit the user just hit).
Future<void> showPaywall(BuildContext context, {String? reason}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _PaywallSheet(reason: reason),
  );
}

/// If [error] is a free-tier limit error from a Cloud Function, show the paywall
/// and return true (handled). Otherwise return false so the caller can fall back
/// to its own error handling.
Future<bool> showPaywallIfQuota(BuildContext context, Object error) async {
  if (error is FirebaseFunctionsException && error.code == 'resource-exhausted') {
    await showPaywall(context, reason: error.message);
    return true;
  }
  return false;
}

class _PaywallSheet extends ConsumerStatefulWidget {
  const _PaywallSheet({this.reason});

  final String? reason;

  @override
  ConsumerState<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends ConsumerState<_PaywallSheet> {
  late final Future<Offering?> _offering =
      ref.read(subscriptionRepositoryProvider).currentOffering();
  bool _busy = false;

  Future<void> _buy(Package package) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final ok = await ref.read(subscriptionRepositoryProvider).purchase(package);
      if (!mounted) return;
      if (ok) {
        navigator.pop();
        messenger.showSnackBar(const SnackBar(
          content: Text("You're all set — enjoy unlimited stories! 🎉"),
        ));
      } else {
        messenger.showSnackBar(const SnackBar(content: Text('Purchase not completed.')));
      }
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code != PurchasesErrorCode.purchaseCancelledError && mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Purchase failed: ${e.message}')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final ok = await ref.read(subscriptionRepositoryProvider).restore();
      if (!mounted) return;
      if (ok) navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(ok ? 'Subscription restored.' : 'No previous subscription found.'),
      ));
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not restore purchases.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.auto_awesome, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('Kitty Story Unlimited',
              style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            widget.reason ?? 'Unlimited voices and bedtime stories for your family.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          for (final benefit in const [
            'Unlimited family voices',
            'Unlimited bedtime stories — no weekly limit',
            'Cancel anytime',
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Icon(Icons.check_circle, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(benefit, style: theme.textTheme.bodyMedium)),
              ]),
            ),
          const SizedBox(height: 20),
          FutureBuilder<Offering?>(
            future: _offering,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final packages = snap.data?.availablePackages ?? const [];
              if (packages.isEmpty) {
                return Column(children: [
                  Text(
                    "The subscription isn't available in your region yet — "
                    'enjoy the free plan!',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Maybe later'),
                  ),
                ]);
              }
              final package = packages.first;
              final price = package.storeProduct.priceString;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: _busy ? null : () => _buy(package),
                    child: _busy
                        ? const SizedBox(
                            height: 20, width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('Subscribe · $price / month'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _restore,
                    child: const Text('Restore purchases'),
                  ),
                  const SizedBox(height: 4),
                  _SubscriptionTerms(price: price),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The disclosures App Store guideline 3.1.2 requires on the paywall itself:
/// length, price per period, auto-renewal, and working Terms + Privacy links.
class _SubscriptionTerms extends StatelessWidget {
  const _SubscriptionTerms({required this.price});

  final String price;

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      children: [
        Text(
          'Kitty Story Unlimited is a $price/month subscription that renews '
          'automatically until cancelled. Cancel any time, at least 24 hours '
          'before the period ends, in your store account settings.',
          textAlign: TextAlign.center,
          style: muted,
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: () => _open(kTermsOfUseUrl),
              child: const Text('Terms of Use'),
            ),
            Text('·', style: muted),
            TextButton(
              onPressed: () => _open(kPrivacyPolicyUrl),
              child: const Text('Privacy Policy'),
            ),
          ],
        ),
      ],
    );
  }
}
