import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/money/money_formatter.dart';
import 'package:alaya/features/split/presentation/widgets/people_counter.dart';
import 'package:alaya/features/split/providers/quick_split_handoff.dart';
import 'package:alaya/features/split/providers/split_bill_provider.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/amount_text.dart';

/// Splitting a bill in three taps, at the top of the split screen.
///
/// **The bill has arrived and everybody is waiting.** That is the moment this module serves, and it used to
/// cost a tap to open a screen before the first digit could be typed. Here the amount field is the first
/// thing under the app bar.
///
/// **And it can now keep the answer without leaving.** Saving used to mean pressing *Add names*, landing on
/// the bill editor, and confirming there — a whole screen crossed to record a split whose every input was
/// already on this card. The debt is written here; the editor is for the cases that need more.
///
/// ## The one question worth asking
///
/// *Did you pay the whole bill, or is everybody paying their own?* It does not change the division —
/// ₹5,000 four ways is ₹1,250 either way — but it changes the number that matters:
///
/// * **You paid.** You are out ₹5,000 and owed ₹3,750. That figure is the answer, and it is a debt worth
///   saving.
/// * **Everybody pays their own.** Nobody owes anybody; ₹1,250 each is the answer, and there is nothing to
///   record — which is why the save button is not offered in that case.
class QuickSplitCard extends ConsumerStatefulWidget {
  /// Creates the card.
  const QuickSplitCard({super.key});

  @override
  ConsumerState<QuickSplitCard> createState() => _QuickSplitCardState();
}

class _QuickSplitCardState extends ConsumerState<QuickSplitCard> {
  /// Owned here rather than left to `AmountField`, so a successful save can clear the field.
  ///
  /// A card that keeps the figures after writing them looks like it did nothing, and the next bill gets
  /// typed on top of the last one.
  final _amountField = TextEditingController();

  Money? _amount;
  int _people = 2;

  /// Whether the user covered the whole bill.
  ///
  /// True by default: somebody opening a split app usually just paid for everybody, and defaulting to the
  /// other case would hide the "owed to you" figure behind a toggle nobody knew to look for.
  bool _iPaid = true;

  @override
  void dispose() {
    _amountField.dispose();
    super.dispose();
  }

  /// What each *other* person pays — the floor of the division.
  ///
  /// **The person who paid absorbs the stray paise.** ₹1,000 three ways is ₹333.33 each with one paisa left
  /// over; giving it to the payer makes "₹333.33 each" true for everybody who owes, which is the sentence
  /// being read out at the table.
  Money? get _each {
    final total = _amount;
    if (total == null || total.isZero || _people < 1) return null;
    return Money(total.minor ~/ _people, total.currencyCode);
  }

  /// What the division cannot place — zero when it comes out even.
  Money? get _remainder {
    final total = _amount;
    if (total == null || total.isZero || _people < 1) return null;
    return Money(total.minor % _people, total.currencyCode);
  }

  /// What everybody else owes the user, when the user paid.
  ///
  /// `each × (people − 1)` — exact by construction, because the payer's own share is whatever is left and
  /// therefore carries the remainder.
  Money? get _owed {
    final each = _each;
    if (each == null || !_iPaid) return null;
    return Money(each.minor * (_people - 1), each.currencyCode);
  }

  /// A bare figure for a caption the ARB owns as prose.
  static String _plain(Money money, int digits) {
    final divisor = digits == 0 ? 1 : 100;
    final whole = money.minor ~/ divisor;
    final frac = money.minor % divisor;
    return digits == 0
        ? '$whole'
        : '$whole.${frac.toString().padLeft(digits, '0')}';
  }

  String _resultText(AlayaStrings strings, int digits) {
    const formatter = MoneyFormatter();
    String money(Money m) =>
        formatter.format(m, decimalDigits: digits, symbol: m.currencyCode);

    final total = _amount!;
    final each = _each!;
    final owed = _owed;
    final buffer = StringBuffer()
      ..writeln('${money(total)} · ${strings.splitPerPersonCount(_people)}')
      ..writeln(strings.splitQuickEachPays(money(each)));
    if (owed != null) buffer.writeln(strings.splitQuickOwedToMe(money(owed)));
    return buffer.toString().trimRight();
  }

  /// Writes the split: you, plus everybody else as an unnamed participant.
  ///
  /// **You are participant one, and leaving you out was a real bug on the other screen.** Four anonymous
  /// slots with you as payer means four strangers each owing a quarter — ₹5,000 owed to you on a ₹5,000
  /// bill, when one of those four *was* you.
  ///
  /// **`recordExpense: false`, deliberately.** Recording the expense needs an account, and an account picker
  /// on a card whose whole point is three taps is the screen this exists to avoid. The debt is written; the
  /// money is not, and the caption under the button says so rather than leaving it to be discovered.
  Future<void> _save(String self) async {
    final strings = AlayaStrings.of(context);
    final total = _amount;
    if (total == null || total.isZero) return;

    final ok = await ref
        .read(splitBillProvider.notifier)
        .save(
          total: total,
          participants: [
            (payeeId: self, value: null, extra: null),
            for (var i = 1; i < _people; i++)
              (payeeId: null, value: null, extra: null),
          ],
          method: SplitMethod.equal,
          recordExpense: false,
        );
    if (!mounted) return;

    if (!ok) {
      showFailureSnack(
        context,
        message:
            ref.read(splitBillProvider.notifier).lastError ??
            strings.errorBodyGeneric,
      );
      return;
    }
    setState(() {
      _amount = null;
      _amountField.clear();
      _people = 2;
    });
    if (!mounted) return;
    showResultSnack(context, message: strings.splitBillSaved);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final digits = ref.watch(splitDecimalDigitsProvider).valueOrNull ?? 2;
    final self = ref.watch(splitSelfProvider).valueOrNull;
    final saving = ref.watch(splitBillProvider).isLoading;
    final each = _each;

    return AlayaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AmountField(
            controller: _amountField,
            currencyCode: 'INR',
            decimalDigits: digits,
            label: strings.splitQuickAmount,
            onChanged: (value) => setState(() => _amount = value),
          ),

          const SizedBox(height: AlayaSpacing.sm),
          // A `Wrap`, not a `Row`: a label beside a counter is the shape that overflows at 320dp with the
          // scaler doubled (Law U15).
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AlayaSpacing.sm,
            runSpacing: AlayaSpacing.xs,
            children: [
              Text(strings.splitQuickPeople, style: AlayaTypography.body),
              // **Typable as well as tappable.** Two to four is a tap each way; two to fourteen is twelve
              // taps, which is where a stepper stops being a convenience.
              PeopleCounter(
                count: _people,
                minimum: 2,
                onChanged: (value) => setState(() => _people = value),
              ),
            ],
          ),

          const SizedBox(height: AlayaSpacing.sm),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text(strings.splitQuickIPaid)),
              ButtonSegment(
                value: false,
                label: Text(strings.splitQuickEachTheirOwn),
              ),
            ],
            selected: {_iPaid},
            showSelectedIcon: false,
            onSelectionChanged: (choice) =>
                setState(() => _iPaid = choice.first),
          ),

          if (each != null) ...[
            const SizedBox(height: AlayaSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AlayaSpacing.md),

            _Figure(
              label: strings.splitQuickEach,
              amount: each,
              emphasised: !_iPaid,
              decimalDigits: digits,
            ),
            if (_owed case final owed?) ...[
              const SizedBox(height: AlayaSpacing.xs),
              _Figure(
                // **The answer when you paid**, emphasised over the per-person figure because it is the
                // reason somebody opened a split app rather than a calculator.
                label: strings.splitQuickOwed,
                amount: owed,
                emphasised: true,
                decimalDigits: digits,
              ),
            ],
            if (_remainder case final left? when !left.isZero) ...[
              const SizedBox(height: AlayaSpacing.xxs),
              Text(
                // Says where the odd paise went rather than leaving the figures not to add up.
                _iPaid
                    ? strings.splitQuickYouAbsorb(_plain(left, digits))
                    : strings.splitQuickLeftOver(_plain(left, digits)),
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
            ],

            const SizedBox(height: AlayaSpacing.md),
            // **Offered only when the user paid.** "Each their own" divides a bill and creates no debt, so
            // there is nothing to record — a button that wrote an empty split would be worse than none.
            //
            // Needs `self` too: a balance has no direction without knowing which person the user is, so
            // every figure saved would be a guess.
            if (_iPaid && self != null) ...[
              FilledButton.icon(
                onPressed: saving ? null : () => _save(self),
                icon: const Icon(Icons.check, size: AlayaIconSize.md),
                label: Text(strings.splitSaveToBalances),
              ),
              const SizedBox(height: AlayaSpacing.xxs),
              Text(
                // Says what it did *and* what it did not. A save that quietly leaves the account balance
                // untouched is the kind of omission somebody discovers a month later while reconciling.
                strings.splitQuickSaveHelp(_people - 1),
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
              const SizedBox(height: AlayaSpacing.sm),
            ],

            Wrap(
              spacing: AlayaSpacing.sm,
              runSpacing: AlayaSpacing.xs,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: _resultText(strings, digits)),
                    );
                    if (!context.mounted) return;
                    showResultSnack(
                      context,
                      message: strings.splitResultCopied,
                    );
                  },
                  icon: const Icon(
                    Icons.copy_outlined,
                    size: AlayaIconSize.md,
                  ),
                  label: Text(strings.actionCopy),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    // Handed over rather than re-typed. Somebody who has just worked out a bill and wants a
                    // tip, a method, an account or real names should not meet an empty amount field.
                    ref.read(quickSplitHandoffProvider.notifier).offer((
                      total: _amount!,
                      people: _people,
                      iPaid: _iPaid,
                    ));
                    context.push(Routes.splitNew);
                  },
                  icon: const Icon(
                    Icons.tune_outlined,
                    size: AlayaIconSize.md,
                  ),
                  label: Text(strings.splitQuickMoreOptions),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: AlayaSpacing.xs),
            Text(
              strings.splitQuickHint,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// One figure with its label, emphasised when it is the answer.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.amount,
    required this.emphasised,
    required this.decimalDigits,
  });

  final String label;
  final Money amount;
  final bool emphasised;
  final int decimalDigits;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AlayaSpacing.sm,
      runSpacing: AlayaSpacing.xxs,
      children: [
        Text(
          label,
          style: emphasised
              ? AlayaTypography.body
              : AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        // Size carries the emphasis rather than colour: `AmountText` has no tone parameter, and a larger
        // figure reads as the answer in any theme and in a screenshot.
        AmountText(
          amount,
          size: emphasised ? AmountSize.large : AmountSize.small,
          showSign: false,
          decimalDigits: decimalDigits,
        ),
      ],
    );
  }
}
