import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/settings/providers/settings_providers.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/widgets/alaya_search_field.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// One row of the settings tree.
class _Entry {
  const _Entry({
    required this.title,
    required this.icon,
    required this.route,
    required this.keywords,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final String route;

  /// Extra words this row should match on.
  ///
  /// **Because the title is not what people search for.** Somebody looking for dark mode types "dark", not
  /// "Appearance"; somebody looking to change their PIN types "PIN", not "Security". A tree whose search
  /// only matched headings would be worse than no search at all, because it would answer "no results" to a
  /// setting that is right there.
  final List<String> keywords;
}

/// The settings tree (ARCH_5 §3 archetype D).
///
/// **Archetype D with two deviations.** There is no FAB, because nothing is added at the tree level — every
/// branch owns its own add action. And the grouping is by subject rather than by a user-chosen axis, because
/// a settings tree has no axis the user controls; the three groups are what the app is made of, in the order
/// somebody looks for them.
///
/// **The search field is pinned and real**, per D — catalogues are searched constantly, and a ten-branch
/// tree with sub-settings is exactly the case where scanning fails. It matches keywords as well as titles,
/// so "dark" finds Appearance and "PIN" finds Security.
///
/// Each row carries a live count, which is D's "the one number that matters": a branch that says *18 tags*
/// tells the user whether it is worth opening before they open it.
class SettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final query = ref.watch(settingsQueryProvider).trim().toLowerCase();
    final groups = _groups(context, ref, strings);

    final filtered = query.isEmpty
        ? groups
        : [
            for (final group in groups)
              (
                label: group.label,
                entries: [
                  for (final entry in group.entries)
                    if (entry.title.toLowerCase().contains(query) ||
                        entry.keywords.any((word) => word.contains(query)))
                      entry,
                ],
              ),
          ].where((group) => group.entries.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AlayaSpacing.screenEdge,
            AlayaSpacing.sm,
            AlayaSpacing.screenEdge,
            AlayaSpacing.xs,
          ),
          child: AlayaSearchField(
            hintText: strings.settingsSearchHint,
            clearLabel: strings.actionClear,
            onChanged: ref.read(settingsQueryProvider.notifier).set,
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              // Empty is reachable only through search, so it names the search rather than the tree — "no
              // settings" would be false, and the user can see it is.
              ? EmptyState(
                  title: strings.settingsNoMatchTitle,
                  body: strings.settingsNoMatchBody,
                  icon: Icons.search_off_outlined,
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final group = filtered[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            top: AlayaSpacing.lg,
                            bottom: AlayaSpacing.xs,
                          ),
                          child: SectionHeader(label: group.label),
                        ),
                        for (final entry in group.entries)
                          _EntryTile(entry: entry),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  List<({String label, List<_Entry> entries})> _groups(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) {
    final accounts = ref.watch(settingsAccountCountProvider).valueOrNull;
    final methods = ref.watch(settingsPaymentMethodCountProvider).valueOrNull;
    final payees = ref.watch(settingsPayeeCountProvider).valueOrNull;
    final tags = ref.watch(settingsTagCountProvider).valueOrNull;
    final units = ref.watch(settingsUnitCountProvider).valueOrNull;
    final currencies = ref.watch(settingsCurrencyCountProvider).valueOrNull;
    final self = ref.watch(splitSelfProvider).valueOrNull;

    return [
      (
        label: strings.settingsGroupMoney,
        entries: [
          _Entry(
            title: strings.settingsAccounts,
            // Null while the count is loading, so the row shows its title alone rather than "0 accounts"
            // — a zero that is really "not yet known" is the kind of figure Law U4 exists to prevent.
            subtitle: accounts == null
                ? null
                : strings.settingsAccountCount(accounts),
            icon: Icons.account_balance_wallet_outlined,
            route: Routes.settingsAccounts,
            keywords: const [
              'account',
              'balance',
              'bank',
              'cash',
              'wallet',
              'net worth',
            ],
          ),
          _Entry(
            title: strings.settingsPaymentMethods,
            subtitle: methods == null
                ? null
                : strings.settingsPaymentMethodCount(methods),
            icon: Icons.credit_card_outlined,
            route: Routes.settingsPaymentMethods,
            keywords: const ['payment', 'card', 'upi', 'method'],
          ),
          _Entry(
            title: strings.settingsPayees,
            subtitle: payees == null
                ? null
                : strings.settingsPayeeCount(payees),
            icon: Icons.storefront_outlined,
            route: Routes.settingsPayees,
            keywords: const ['payee', 'shop', 'merchant', 'who'],
          ),
          _Entry(
            title: strings.settingsSplit,
            // **Not a count, and the only row here that is not.** Every other subtitle says how much is
            // in a branch; this one says whether the module works at all. Until `split.selfPayeeId` is
            // set, nothing can tell which side of a debt the user is on — so three screens send people
            // here, and "Not set up yet" is how they recognise the row when they arrive.
            subtitle: self == null
                ? strings.settingsSplitUnset
                : strings.settingsSplitSet,
            icon: Icons.call_split_outlined,
            // The keywords matter more than usual: somebody sent here by a message about splitting a
            // bill will type "split" or "who am i", neither of which appears in the title.
            keywords: const ['split', 'share', 'owe', 'upi', 'me', 'who am i'],
            route: Routes.settingsSplit,
          ),
        ],
      ),
      (
        label: strings.settingsGroupThings,
        entries: [
          _Entry(
            title: strings.settingsTags,
            subtitle: tags == null ? null : strings.settingsTagCount(tags),
            icon: Icons.sell_outlined,
            route: Routes.settingsTags,
            keywords: const ['tag', 'label', 'category', 'kitchen'],
          ),
          _Entry(
            title: strings.settingsUnits,
            subtitle: units == null ? null : strings.settingsUnitCount(units),
            icon: Icons.straighten_outlined,
            route: Routes.settingsUnits,
            keywords: const ['unit', 'kg', 'litre', 'measure', 'weight'],
          ),
          _Entry(
            title: strings.settingsCurrencies,
            subtitle: currencies == null
                ? null
                : strings.settingsCurrencyCount(
                    currencies.enabled,
                    currencies.total,
                  ),
            icon: Icons.currency_exchange_outlined,
            route: Routes.settingsCurrencies,
            keywords: const ['currency', 'rate', 'exchange', 'home currency'],
          ),
        ],
      ),
      (
        label: strings.settingsGroupApp,
        entries: [
          _Entry(
            title: strings.settingsAppearance,
            icon: Icons.palette_outlined,
            route: Routes.settingsAppearance,
            keywords: const [
              'appearance',
              'theme',
              'dark',
              'light',
              'palette',
              'colour',
              'color',
            ],
          ),
          _Entry(
            title: strings.settingsSecurity,
            icon: Icons.shield_outlined,
            route: Routes.settingsSecurity,
            keywords: const [
              'security',
              'pin',
              'lock',
              'fingerprint',
              'biometric',
              'erase',
            ],
          ),
          // Phase 8B. Reminders sits beside Security because both are about what the app does when it is not
          // open, and somebody looking for one often means the other.
          _Entry(
            title: strings.remindersTitle,
            subtitle: strings.settingsRemindersHelp,
            icon: Icons.notifications_none_outlined,
            route: Routes.settingsReminders,
            keywords: const [
              'reminder',
              'notification',
              'notify',
              'alert',
              'digest',
              'expiry',
              'due',
              'daily',
            ],
          ),
          _Entry(
            title: strings.settingsData,
            icon: Icons.folder_outlined,
            route: Routes.settingsData,
            keywords: const ['data', 'backup', 'export', 'restore', 'trash'],
          ),
          // **Reachable from Settings and nowhere else.** Ads load when that screen opens, so a shell
          // destination or a dashboard tile would start an SDK for people who never asked (ARCH_4 §5.1).
          _Entry(
            title: strings.supportTitle,
            subtitle: strings.settingsSupportHelp,
            icon: Icons.favorite_outline,
            route: Routes.support,
            keywords: const [
              'support',
              'tip',
              'donate',
              'advert',
              'ad',
              'help',
              'contribute',
            ],
          ),
          _Entry(
            title: strings.settingsAbout,
            icon: Icons.info_outlined,
            route: Routes.settingsAbout,
            keywords: const [
              'about',
              'version',
              'licence',
              'license',
              'open source',
            ],
          ),
        ],
      ),
    ];
  }
}

/// One tappable branch.
class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return ListTile(
      leading: Icon(entry.icon, size: AlayaIconSize.lg, color: semantic.muted),
      title: Text(entry.title, style: AlayaTypography.cardTitle),
      subtitle: entry.subtitle == null
          ? null
          : Text(
              entry.subtitle!,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
      trailing: Icon(
        Icons.chevron_right,
        size: AlayaIconSize.md,
        color: semantic.muted,
      ),
      onTap: () => context.push(entry.route),
    );
  }
}
