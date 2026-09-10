import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/services/support/support_port.dart';
import 'package:alaya/features/support/providers/support_providers.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Support Us (ARCH_5 §3 archetype F, outside the shell).
///
/// **The SDKs start in `initState` and nowhere else in the app.** That is the requirement, and it is enforced by
/// `AdsAndBilling` being the only file that imports either SDK — a `grep` for `google_mobile_ads` returning one
/// path is the check. An install where nobody opens this screen never initialises the SDK, never fetches a
/// consent form, and never collects an advertising identifier.
///
/// **Archetype F with one deviation: no `displayAmount`.** F wants one headline number per overview, and this
/// screen has none to give — the honest headline is a sentence, because the app is free and nothing here unlocks
/// anything. A fabricated "₹0 raised" would be worse than no number.
///
/// **Nothing on this screen changes what the app can do.** There are no paid features, so a tip is a tip rather
/// than a paywall wearing a friendly label, and the copy says so.
class SupportScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const SupportScreen({super.key});

  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  @override
  void initState() {
    super.initState();
    // The one call site. A post-frame callback because `start()` mutates a provider, which Riverpod asserts on
    // during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(supportProvider.notifier).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(supportProvider);
    final semantic = context.semantic;

    return Scaffold(
      appBar: AppBar(title: Text(strings.supportTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
        children: [
          Text(strings.supportIntro, style: AlayaTypography.body),
          const SizedBox(height: AlayaSpacing.xs),
          Text(
            strings.supportNoPaidFeatures,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
          if (state.thanksShown) ...[
            const SizedBox(height: AlayaSpacing.lg),
            AlayaCard(
              padding: const EdgeInsets.all(AlayaSpacing.lg),
              child: Row(
                children: [
                  Icon(
                    Icons.favorite_outline,
                    size: AlayaIconSize.lg,
                    color: semantic.success,
                  ),
                  const SizedBox(width: AlayaSpacing.sm),
                  Expanded(
                    child: Text(
                      strings.supportThanks,
                      style: AlayaTypography.bodyEmphasis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AlayaSpacing.lg),
          SectionHeader(label: strings.supportWatchHeader),
          const SizedBox(height: AlayaSpacing.xs),
          Text(strings.supportWatchBody, style: AlayaTypography.body),
          if (state.consent == AdConsent.unavailable) ...[
            const SizedBox(height: AlayaSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AlayaSpacing.md),
              decoration: BoxDecoration(
                color: semantic.muted.withValues(alpha: 0.12),
                borderRadius: AlayaRadii.borderMd,
              ),
              // Says what happened rather than showing a button that cannot work: without consent settled, no ad
              // is requested at all (ARCH_1 §7's "resolver + UMP consent").
              child: Text(
                strings.supportConsentUnavailable,
                style: AlayaTypography.body,
              ),
            ),
          ],
          const SizedBox(height: AlayaSpacing.md),
          FilledButton.icon(
            onPressed: state.adLoaded && !state.isWorking
                ? () => ref.read(supportProvider.notifier).watchAd()
                : null,
            icon: const Icon(Icons.play_circle_outline, size: AlayaIconSize.md),
            label: Text(
              // Three honest labels rather than one that lies while loading: an enabled "Watch" over an advert
              // that has not arrived is the dead control §10 objects to.
              state.isWorking
                  ? strings.supportLoading
                  : state.adLoaded
                  ? strings.supportWatchAction
                  : strings.supportNoAd,
              style: AlayaTypography.button,
            ),
          ),
          const SizedBox(height: AlayaSpacing.xl),
          SectionHeader(label: strings.supportTipHeader),
          const SizedBox(height: AlayaSpacing.xs),
          Text(strings.supportTipBody, style: AlayaTypography.body),
          const SizedBox(height: AlayaSpacing.md),
          if (state.products.isEmpty)
            Text(
              strings.supportTipUnavailable,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            )
          else
            for (final product in state.products)
              Padding(
                padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
                child: OutlinedButton(
                  onPressed: state.isWorking
                      ? null
                      : () =>
                            ref.read(supportProvider.notifier).tip(product.id),
                  // **The store's own price string**, never reformatted: Play returns it localised for the
                  // user's account, which need not match this app's home currency. This is the one place money
                  // is displayed without `AmountText`, and reformatting it would make it wrong.
                  child: Text(
                    strings.supportTipAction(product.price),
                    style: AlayaTypography.button,
                  ),
                ),
              ),
          if (state.failureMessage != null) ...[
            const SizedBox(height: AlayaSpacing.md),
            Text(
              state.failureMessage!,
              style: AlayaTypography.body.copyWith(color: semantic.danger),
            ),
          ],
        ],
      ),
    );
  }
}
