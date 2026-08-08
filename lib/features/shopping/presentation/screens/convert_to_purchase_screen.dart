import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/shopping/providers/convert_providers.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Turns a finished list into a pre-filled withdrawal (ARCH_5 §3 archetype B).
///
/// **It hands off; it does not commit.** The primary action offers a draft to the expense editor and
/// navigates there. The amount, the account and the payee are decisions only that screen collects,
/// and duplicating them here would fork the one place in the app that knows how a withdrawal is
/// shaped (anomaly A25). Nothing is written until the user saves there.
class ConvertToPurchaseScreen extends ConsumerWidget {
  /// Converts the ticked entries of [listId].
  const ConvertToPurchaseScreen({required this.listId, super.key});

  /// Which list to convert.
  final String listId;

  void _handOff(
    BuildContext context,
    WidgetRef ref,
    List<TransactionLine> lines,
  ) {
    final offered = ref
        .read(convertActionsProvider)
        .offerDraft(listId: listId, lines: lines);
    if (!offered) return;
    context.pushReplacement(Routes.transactionNew);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final draft = ref.watch(purchaseDraftProvider(listId));

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(strings.convertTitle),
      ),
      body: draft.when(
        loading: () => AlayaListSkeleton(
          label: strings.loadingShopping,
          hasLeading: false,
        ),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: strings.errorBodyGeneric,
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(purchaseDraftProvider(listId)),
        ),
        data: (lines) => lines.isEmpty
            ? EmptyState(
                title: strings.convertNothingTitle,
                body: strings.convertNothingBody,
                icon: Icons.checklist_outlined,
              )
            : AlayaFormScaffold(
                primaryLabel: strings.convertConfirm,
                onPrimary: () => _handOff(context, ref, lines),
                isDirty: false,
                isSubmitting: false,
                discardTitle: strings.confirmDiscardTitle,
                discardBody: strings.confirmDiscardBody,
                discardConfirmLabel: strings.actionDiscard,
                discardCancelLabel: strings.actionKeepEditing,
                child: _Preview(lines: lines),
              ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.lines});

  final List<TransactionLine> lines;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.convertBody,
          style: AlayaTypography.body.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AlayaSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: StatusChip(
            label: strings.convertLineCount(lines.length),
            tone: StatusTone.info,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  line.destination == TransactionLineDestination.inventory
                      ? Icons.inventory_2_outlined
                      : Icons.receipt_long_outlined,
                  size: AlayaIconSize.md,
                  color: semantic.muted,
                ),
                const SizedBox(width: AlayaSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.description, style: AlayaTypography.body),
                      if (line.quantity != null) ...[
                        const SizedBox(height: AlayaSpacing.xxs),
                        QtyText(line.quantity!, muted: true),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
