import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/features/recurring/presentation/sheets/pay_sheet.dart';
import 'package:alaya/features/recurring/providers/occurrence_history_providers.dart';
import 'package:alaya/features/recurring/providers/pay_providers.dart';
import 'package:alaya/features/recurring/providers/template_builder_providers.dart';
import 'package:alaya/features/recurring/providers/template_list_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_timeline.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

/// One template's occurrences (ARCH_5 §3 archetype C), outside the drawer shell (U18).
///
/// **Shows the actual against the usual, but only where they differ.** `paidAmount` is what really
/// left the account and `defaultAmount` is what the template expects; a bill that came in high is the
/// §7.2 row this screen closes, and repeating the default under every unchanged row would bury it.
class OccurrenceHistoryScreen extends ConsumerWidget {
  /// Shows the occurrences of [templateId].
  const OccurrenceHistoryScreen({required this.templateId, super.key});

  /// Which template's history to show.
  final String templateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final template = ref.watch(historyTemplateProvider(templateId));

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.historyRecurringTitle),
        actions: [
          IconButton(
            onPressed: () => context.push(Routes.recurringEdit(templateId)),
            tooltip: strings.actionEdit,
            icon: const Icon(Icons.edit_outlined, size: AlayaIconSize.lg),
          ),
        ],
      ),
      body: template.when(
        loading: () => AlayaListSkeleton(
          label: strings.loadingRecurring,
          hasLeading: false,
        ),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(historyTemplateProvider(templateId)),
        ),
        data: (value) => value == null
            ? EmptyState(
                title: strings.errorTitleNotFound,
                body: strings.errorBodyNotFound,
                icon: Icons.search_off_outlined,
              )
            : _Body(template: value),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.template});

  final RecurringTemplate template;

  Future<void> _undo(
    BuildContext context,
    WidgetRef ref,
    RecurringOccurrence occurrence,
  ) async {
    final strings = AlayaStrings.of(context);
    final transactionId = occurrence.paidTransactionId;
    if (transactionId == null) return;
    // Consequential, and the body names both halves and their order (ARCH_5 §5.4): the obligation
    // returns to due, then the transaction it created is deleted along with anything that transaction
    // produced.
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.payUndoTitle,
      body: strings.payUndoBody,
      confirmLabel: strings.actionUndo,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final error = await ref
        .read(occurrenceActionsProvider)
        .undoPayment(
          occurrenceId: occurrence.id,
          transactionId: transactionId,
        );
    if (!context.mounted) return;
    error == null
        ? showResultSnack(context, message: strings.payUndone)
        : showFailureSnack(context, message: error);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final async = ref.watch(occurrencesProvider(template.id));
    final today = ref.watch(clockProvider).today();
    final digits = ref.watch(builderDecimalDigitsProvider).valueOrNull ?? 2;

    return async.when(
      loading: () => AlayaListSkeleton(label: strings.loadingRecurring),
      error: (error, stack) => ErrorState(
        title: strings.errorTitleGeneric,
        body: error.toString(),
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(occurrencesProvider(template.id)),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return EmptyState(
            title: strings.emptyTitleNoOccurrences,
            body: strings.emptyBodyNoOccurrences,
            icon: Icons.event_repeat_outlined,
          );
        }
        final ordered = [...rows]
          ..sort((a, b) => b.dueDateKey.compareTo(a.dueDateKey));
        return CustomScrollView(
          slivers: [
            AlayaTimeline(
              itemCount: ordered.length,
              itemBuilder: (context, index) {
                final occurrence = ordered[index];
                final paid = occurrence.paidAmount;
                final overdue = occurrence.isOverdue(today);
                final differs = paid != null && paid != template.defaultAmount;

                return AlayaTimelineEntry(
                  title: switch (occurrence.status) {
                    RecurringOccurrenceStatus.paid => strings.statusPaid,
                    RecurringOccurrenceStatus.skipped =>
                      strings.occurrenceSkipped,
                    RecurringOccurrenceStatus.dismissed =>
                      strings.statusDismissed,
                    RecurringOccurrenceStatus.due =>
                      overdue ? strings.recurringOverdue : strings.statusDue,
                  },
                  trailing: AmountText(
                    paid ?? template.defaultAmount,
                    size: AmountSize.small,
                    showSign: false,
                    decimalDigits: digits,
                    muted: !occurrence.isPaid,
                  ),
                  subtitle: DateText(
                    occurrence.dueDateKey,
                    style: DateTextStyle.medium,
                    muted: true,
                  ),
                  meta: differs
                      ? strings.historyDefaultVsActual
                      : occurrence.note,
                  icon: switch (occurrence.status) {
                    RecurringOccurrenceStatus.paid =>
                      Icons.check_circle_outline,
                    RecurringOccurrenceStatus.skipped => Icons.redo,
                    RecurringOccurrenceStatus.dismissed => Icons.block,
                    RecurringOccurrenceStatus.due => Icons.schedule,
                  },
                  tone: switch (occurrence.status) {
                    RecurringOccurrenceStatus.paid =>
                      template.direction == RecurringDirection.inflow
                          ? TimelineTone.incoming
                          : TimelineTone.outgoing,
                    RecurringOccurrenceStatus.skipped ||
                    RecurringOccurrenceStatus.dismissed =>
                      TimelineTone.superseded,
                    RecurringOccurrenceStatus.due =>
                      overdue ? TimelineTone.outgoing : TimelineTone.neutral,
                  },
                  badge: differs ? strings.historyDefaultVsActual : null,
                  onTap: occurrence.isPaid
                      ? () => _undo(context, ref, occurrence)
                      : occurrence.isOutstanding
                      ? () => PaySheet.show(
                          context,
                          occurrenceId: occurrence.id,
                          template: template,
                        )
                      : null,
                );
              },
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
                child: Text(
                  strings.emptyBodyNoOccurrences,
                  style: AlayaTypography.caption.copyWith(
                    color: semantic.muted,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
