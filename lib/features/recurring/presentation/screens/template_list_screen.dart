import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/features/recurring/presentation/sheets/pay_sheet.dart';
import 'package:alaya/features/recurring/presentation/widgets/template_row.dart';
import 'package:alaya/features/recurring/providers/template_builder_providers.dart';
import 'package:alaya/features/recurring/providers/template_list_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Everything that repeats (ARCH_5 §3 archetype D).
///
/// **Nothing on this screen pays anything by itself.** Mounting it materialises occurrences up to
/// today so the list can show what is due; every one of them is created `due`, and money appears only
/// when the user taps Record (anomaly A14).
class TemplateListScreen extends ConsumerWidget {
  /// Creates the screen.
  const TemplateListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final groups = ref.watch(templateGroupsProvider);
    final overdue = ref.watch(overdueCountProvider);

    return Scaffold(
      body: groups.when(
        loading: () => AlayaListSkeleton(label: strings.loadingRecurring),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () {
            ref.invalidate(materialiseProvider);
            ref.invalidate(templatesProvider);
          },
        ),
        data: (sections) => sections.isEmpty
            ? EmptyState(
                title: strings.emptyTitleNoTemplates,
                body: strings.emptyBodyNoTemplates,
                icon: Icons.event_repeat_outlined,
                actionLabel: strings.addTemplate,
                onAction: () => context.push(Routes.recurringNew),
              )
            : Column(
                children: [
                  if (overdue > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AlayaSpacing.screenEdge,
                        AlayaSpacing.sm,
                        AlayaSpacing.screenEdge,
                        0,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: StatusChip(
                          label: strings.recurringOverdue,
                          tone: StatusTone.danger,
                          trailing: Text(
                            '$overdue',
                            style: AlayaTypography.overline.copyWith(
                              color: context.semantic.onStatus,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(child: _Sections(sections: sections)),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.recurringNew),
        tooltip: strings.addTemplate,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _Sections extends ConsumerWidget {
  const _Sections({required this.sections});

  final List<TemplateGroup> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final today = ref.watch(clockProvider).today();
    final digits = ref.watch(builderDecimalDigitsProvider).valueOrNull ?? 2;
    final actions = ref.read(templateActionsProvider);

    Future<void> guard(Future<String?> Function() run) async {
      final error = await run();
      if (!context.mounted || error == null) return;
      showFailureSnack(context, message: error);
    }

    return CustomScrollView(
      slivers: [
        for (final section in sections)
          SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AlayaSpacing.screenEdge,
                    AlayaSpacing.md,
                    AlayaSpacing.screenEdge,
                    AlayaSpacing.xs,
                  ),
                  child: Text(
                    section.direction == RecurringDirection.inflow
                        ? strings.recurringInflow
                        : strings.recurringOutflow,
                    style: AlayaTypography.sectionHeader.copyWith(
                      color: semantic.muted,
                    ),
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: section.rows.length,
                itemBuilder: (context, index) {
                  final row = section.rows[index];
                  final next = row.next;
                  return TemplateRowTile(
                    template: row.template,
                    next: next,
                    today: today,
                    decimalDigits: digits,
                    onTap: () =>
                        context.push(Routes.recurringHistory(row.template.id)),
                    onPay: next == null || row.template.isPaused
                        ? null
                        : () => PaySheet.show(
                            context,
                            occurrenceId: next.id,
                            template: row.template,
                          ),
                    onTogglePause: () => guard(
                      () => actions.setPaused(
                        id: row.template.id,
                        isPaused: !row.template.isPaused,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        const SliverToBoxAdapter(child: SizedBox(height: AlayaSpacing.xxxl)),
      ],
    );
  }
}
