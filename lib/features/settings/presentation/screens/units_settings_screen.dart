import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/settings/presentation/widgets/unit_labels.dart';
import 'package:alaya/features/settings/providers/unit_settings_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Settings › Units (ARCH_5 §3 archetype D, outside the shell).
///
/// **Grouped by category, because the categories are the one thing here that can never change.** ARCH_1 §5.3
/// fixes them at three and Law L8 makes cross-category conversion inexpressible, so weight, volume and count
/// are not a filter the user chose — they are the shape of the data, and grouping says so without a sentence.
///
/// Each row states what one of the unit **is**, in its category's base unit: *1 kg = 1,000 g*. A factor shown
/// as `1000000` would be technically the stored value and useless to read.
class UnitsSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const UnitsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final units = ref.watch(unitsSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsUnits)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.unitNew),
        tooltip: strings.unitsAdd,
        child: const Icon(Icons.add, size: AlayaIconSize.lg),
      ),
      body: units.when(
        loading: () => AlayaListSkeleton(label: strings.unitsLoading),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(unitsSettingsProvider),
        ),
        data: (rows) {
          // Reachable only after somebody deletes every user unit *and* the seed's, which the seeder makes
          // unlikely — but a list screen with no empty state is a list screen that renders a blank rectangle.
          if (rows.isEmpty) {
            return EmptyState(
              title: strings.unitsEmptyTitle,
              body: strings.unitsEmptyBody,
              icon: Icons.straighten_outlined,
              actionLabel: strings.unitsAdd,
              onAction: () => context.push(Routes.unitNew),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
            children: [
              for (final category in UnitCategory.values) ...[
                Padding(
                  padding: const EdgeInsets.only(
                    top: AlayaSpacing.lg,
                    bottom: AlayaSpacing.xs,
                  ),
                  child: SectionHeader(
                    label: unitCategoryLabel(strings, category),
                  ),
                ),
                for (final unit in rows.where(
                  (row) => row.category == category,
                ))
                  _UnitRow(unit: unit),
              ],
              const SizedBox(height: AlayaSpacing.lg),
              // The rule from ARCH_1 §5.3, stated where somebody about to add a unit will read it — not only
              // as a refusal after they have tried.
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AlayaSpacing.screenEdge,
                ),
                child: Text(
                  strings.unitsCategoriesFixedNote,
                  style: AlayaTypography.caption.copyWith(
                    color: context.semantic.muted,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One unit, stated as what it equals.
class _UnitRow extends StatelessWidget {
  const _UnitRow({required this.unit});

  final Unit unit;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return ListTile(
      title: Row(
        children: [
          Expanded(
            child: Text(
              strings.unitsRowTitle(unit.displayName, unit.code),
              style: AlayaTypography.cardTitle,
            ),
          ),
          if (unit.isSystem) ...[
            const SizedBox(width: AlayaSpacing.xs),
            StatusChip(
              label: strings.unitsSystemChip,
              tone: StatusTone.neutral,
            ),
          ],
        ],
      ),
      subtitle: Text(
        // `1 kg = 1,000 g`, assembled from the stored thousandths so the reader never meets them.
        strings.unitsEquals(
          unit.code,
          unitBaseAmountLabel(unit),
          unit.category.baseUnitCode,
        ),
        style: AlayaTypography.caption.copyWith(color: semantic.muted),
      ),
      onTap: () => context.push(Routes.unitEdit(unit.code)),
    );
  }
}
