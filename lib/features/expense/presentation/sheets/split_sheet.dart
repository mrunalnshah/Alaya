import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/core/time/date_key_labels.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/split_group.dart';
import 'package:alaya/domain/services/split/split_resolver.dart';
import 'package:alaya/features/expense/state/split_draft.dart';
import 'package:alaya/features/settings/presentation/sheets/payee_sheet.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';
import 'package:alaya/features/split/presentation/sheets/add_person_sheet.dart';

/// Splitting the expense the editor is already recording (ARCH_5 §3 archetype A).
///
/// **The second way in, not the only one.** `SplitBillScreen` is for "I want to split something";
/// this is for "I am recording an expense that happens to be shared", which is a different intent
/// arriving from a different place. Both produce the same rows.
///
/// **Both paths offer the same arithmetic, and for one release they did not.** This sheet could not
/// express an extra — "Ravi's drinks were ₹400" — while the split screen could, so the same bill
/// split differently depending on which door you came through. Two capabilities behind one model is
/// how a feature becomes folklore about which screen to use.
///
/// **Reads the split module's providers, not the expense editor's.** `transaction_editor_providers`
/// grew its own `splitPayeesProvider`, `splitGroupsProvider` and `splitSelfPayeeProvider` in session
/// 5, and session 6 added `splitPeopleProvider`, `splitAllGroupsProvider` and `splitSelfProvider`
/// without noticing — six providers answering three questions, which is the duplication ARCH_M §6
/// exists to forbid. The three in the expense feature have no callers now and should be deleted.
///
/// Returns content only — no `SafeArea`, no `viewInsets` padding, no scroll view. `AlayaBottomSheet`
/// owns all three, and its doc records that a sheet adding its own reintroduces an overflow that
/// appears the instant a keyboard opens.
class SplitSheet extends ConsumerStatefulWidget {
  /// Edits [draft], or starts a new split of [total].
  const SplitSheet({
    required this.total,
    required this.decimalDigits,
    this.draft,
    super.key,
  });

  /// What is being split. Null disables the sheet entirely — see [show].
  final Money? total;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  /// The split being edited, or null for a new one.
  final SplitDraft? draft;

  /// Opens the sheet, resolving to the edited draft or null when dismissed.
  static Future<SplitDraft?> show(
    BuildContext context, {
    required Money? total,
    required int decimalDigits,
    SplitDraft? draft,
  }) => AlayaBottomSheet.show<SplitDraft>(
    context: context,
    builder: (context) => SplitSheet(
      total: total,
      decimalDigits: decimalDigits,
      draft: draft,
    ),
  );

  @override
  ConsumerState<SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends ConsumerState<SplitSheet> {
  late SplitMethod _method = widget.draft?.method ?? SplitMethod.equal;
  late String? _groupId = widget.draft?.groupId;
  late DateKey? _settleBy = widget.draft?.settleByDateKey;

  /// Who is on the split, in the order they were added.
  late final List<String> _payeeIds = [...?widget.draft?.payeeIds];

  /// The typed value per person — a weight, basis points, or minor units, by method.
  ///
  /// **Kept across a method change rather than cleared.** Switching from shares to percent and back
  /// must not lose the weights somebody just entered; the values are only *interpreted* differently.
  late final Map<String, int> _values = {
    for (final input in widget.draft?.inputs ?? const <ShareInput>[])
      if (input.value != null && input.kind != ShareInputKind.extra)
        input.payeeId: input.value!,
  };

  /// What each person is charged on top of their share.
  late final Map<String, int> _extras = {
    for (final input in widget.draft?.inputs ?? const <ShareInput>[])
      if (input.kind == ShareInputKind.extra && input.value != null)
        input.payeeId: input.value!,
  };

  SplitDraft _draft(String selfPayeeId) => SplitDraft(
    paidByPayeeId: selfPayeeId,
    method: _method,
    groupId: _groupId,
    settleByDateKey: _settleBy,
    inputs: [for (final id in _payeeIds) _inputFor(id)],
  );

  ShareInput _inputFor(String payeeId) {
    // An extra wins over the method, and that is not a conflict: an extra says what somebody owes on
    // top, the method says how the rest divides, and `ShareInputKind.extra` means exactly "this plus
    // an ordinary share of the remainder".
    final extra = _extras[payeeId];
    if (extra != null && extra > 0) return ShareInput.extra(payeeId, extra);
    return switch (_method) {
      SplitMethod.equal => ShareInput.equal(payeeId),
      SplitMethod.shares => ShareInput.shares(payeeId, _values[payeeId] ?? 1),
      SplitMethod.percent => ShareInput.percent(payeeId, _values[payeeId] ?? 0),
      SplitMethod.exactAmounts => ShareInput.exact(
        payeeId,
        _values[payeeId] ?? 0,
      ),
      // Itemised splits are built from the transaction's own lines, not from this sheet. Named so
      // adding an enum member breaks here rather than falling through — Law L13.
      SplitMethod.perLine => ShareInput.equal(payeeId),
    };
  }

  /// Applies a group: its members become the participants, and its weights the values.
  void _applyGroup(SplitGroup? group) {
    setState(() {
      _groupId = group?.id;
      if (group == null) return;
      _payeeIds
        ..clear()
        ..addAll([for (final member in group.members) member.payeeId]);
      _extras.clear();
      final weights = group.defaultWeightsByPayee;
      if (weights == null) {
        // A partial set of weights prefills nothing: treating an unweighted member as weightless would
        // invent an instruction — "she did not eat" is a real thing to mean and must never be inferred
        // from a blank field.
        _method = SplitMethod.equal;
        _values.clear();
        return;
      }
      _method = SplitMethod.shares;
      _values
        ..clear()
        ..addAll(weights);
    });
  }

  void _toggle(String payeeId) => setState(() {
    if (_payeeIds.remove(payeeId)) {
      _values.remove(payeeId);
      _extras.remove(payeeId);
      return;
    }
    _payeeIds.add(payeeId);
  });

  /// Adds somebody and puts them on the split.
  ///
  /// `AddPersonSheet` rather than `PayeeSheet`: the shared sheet defaults to `PayeeKind.merchant`, so
  /// anybody added here was filed as a shop and never appeared in `splitPeopleProvider`. It also
  /// returns the id, which removes the diff-the-stream-afterwards race the old version had.
  Future<void> _addPerson() async {
    final created = await AddPersonSheet.show(context);
    if (created == null || !mounted) return;
    setState(() => _payeeIds.add(created));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final total = widget.total;

    // The amount is what there is to divide, so without one there is nothing to do here. Said rather
    // than shown as a disabled form, because a screen full of inert controls explains nothing.
    if (total == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.xl),
        child: Text(
          strings.splitNeedsAmount,
          style: AlayaTypography.body.copyWith(color: semantic.muted),
        ),
      );
    }

    final people =
        ref.watch(splitPeopleProvider).valueOrNull ?? const <Payee>[];
    final groups =
        ref.watch(splitAllGroupsProvider).valueOrNull ?? const <SplitGroup>[];
    final self = ref.watch(splitSelfProvider).valueOrNull;

    final draft = self == null ? null : _draft(self);
    final resolution = draft?.resolve(total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(strings.splitSheetTitle, style: AlayaTypography.sectionHeader),

        if (groups.isNotEmpty) ...[
          const SizedBox(height: AlayaSpacing.md),
          DropdownButtonFormField<String?>(
            key: ValueKey(_groupId),
            initialValue: _groupId,
            isExpanded: true,
            decoration: InputDecoration(labelText: strings.splitGroupLabel),
            items: [
              DropdownMenuItem(
                value: null,
                child: Text(strings.splitGroupNone),
              ),
              for (final group in groups)
                DropdownMenuItem(value: group.id, child: Text(group.name)),
            ],
            onChanged: (id) => _applyGroup(
              id == null ? null : groups.firstWhere((g) => g.id == id),
            ),
          ),
        ],

        SectionHeader(
          label: strings.splitPickPeople,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.lg,
            bottom: AlayaSpacing.xs,
          ),
        ),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final payee in people)
              FilterChip(
                label: Text(payee.name),
                selected: _payeeIds.contains(payee.id),
                onSelected: (_) => _toggle(payee.id),
              ),
            ActionChip(
              avatar: const Icon(
                Icons.person_add_outlined,
                size: AlayaIconSize.sm,
              ),
              label: Text(strings.splitAddPerson),
              onPressed: _addPerson,
            ),
          ],
        ),

        if (_payeeIds.isNotEmpty) ...[
          const SizedBox(height: AlayaSpacing.md),
          DatePickerField(
            value: _settleBy,
            label: strings.splitSettleByLabel,
            hint: strings.splitSettleByHint,
            // A deadline in the past emits a calendar event that is overdue the moment it is created,
            // which `CalendarAggregator` renders as a warning on a split nobody has had a chance to
            // settle.
            firstDate: ref.read(splitTodayProvider),
            formatted: (date) => date.fullLabel,
            onChanged: (date) => setState(() => _settleBy = date),
          ),

          const SizedBox(height: AlayaSpacing.lg),
          SegmentedButton<SplitMethod>(
            segments: [
              ButtonSegment(
                value: SplitMethod.equal,
                label: Text(strings.splitMethodEqual),
              ),
              ButtonSegment(
                value: SplitMethod.shares,
                label: Text(strings.splitMethodShares),
              ),
              ButtonSegment(
                value: SplitMethod.percent,
                label: Text(strings.splitMethodPercent),
              ),
              ButtonSegment(
                value: SplitMethod.exactAmounts,
                label: Text(strings.splitMethodExact),
              ),
            ],
            selected: {_method},
            showSelectedIcon: false,
            onSelectionChanged: (choice) =>
                setState(() => _method = choice.first),
          ),

          const SizedBox(height: AlayaSpacing.md),
          for (final payeeId in _payeeIds)
            _ShareRow(
              name: _nameOf(people, payeeId, strings),
              method: _method,
              currencyCode: total.currencyCode,
              decimalDigits: widget.decimalDigits,
              value: _values[payeeId],
              extra: _extras[payeeId],
              resolved: _shareOf(resolution, payeeId),
              onValue: (value) => setState(() {
                value == null
                    ? _values.remove(payeeId)
                    : _values[payeeId] = value;
              }),
              onExtra: (value) => setState(() {
                value == null || value == 0
                    ? _extras.remove(payeeId)
                    : _extras[payeeId] = value;
              }),
            ),

          if (resolution != null && !resolution.isExact) ...[
            const SizedBox(height: AlayaSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusChip(
                // Never auto-balanced, exactly as `LineItemsSection` refuses to: forcing the shares to
                // equal the total would charge somebody for a discrepancy nobody told them about.
                label: resolution.isOverAllocated
                    ? strings.splitOverAllocated
                    : strings.splitUnallocated,
                tone: StatusTone.warning,
                trailing: AmountText(
                  resolution.unallocated.abs(),
                  size: AmountSize.small,
                  showSign: false,
                  decimalDigits: widget.decimalDigits,
                ),
              ),
            ),
          ],
        ],

        const SizedBox(height: AlayaSpacing.lg),
        FilledButton(
          // Disabled until the module knows who the user is. Without `split.selfPayeeId` nothing can
          // say which side of the debt they are on, so every balance would be a guess.
          onPressed: draft == null
              ? null
              : () => Navigator.of(context).pop(draft),
          child: Text(strings.splitApply),
        ),
        if (self == null) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Text(
            strings.splitSelfPayeeUnset,
            style: AlayaTypography.caption.copyWith(color: semantic.warning),
          ),
        ],
      ],
    );
  }

  static String _nameOf(
    List<Payee> people,
    String payeeId,
    AlayaStrings strings,
  ) {
    for (final payee in people) {
      if (payee.id == payeeId) return payee.name;
    }
    return strings.splitUnknownPerson;
  }

  static ResolvedShare? _shareOf(SplitResolution? r, String payeeId) {
    if (r == null) return null;
    for (final share in r.shares) {
      if (share.payeeId == payeeId) return share;
    }
    return null;
  }
}

/// One participant: their name, whatever the method asks for, their extra, and what it comes to.
class _ShareRow extends StatefulWidget {
  const _ShareRow({
    required this.name,
    required this.method,
    required this.currencyCode,
    required this.decimalDigits,
    required this.value,
    required this.extra,
    required this.resolved,
    required this.onValue,
    required this.onExtra,
  });

  final String name;
  final SplitMethod method;
  final String currencyCode;
  final int decimalDigits;
  final int? value;
  final int? extra;
  final ResolvedShare? resolved;
  final ValueChanged<int?> onValue;
  final ValueChanged<int?> onExtra;

  @override
  State<_ShareRow> createState() => _ShareRowState();
}

class _ShareRowState extends State<_ShareRow> {
  late bool _showExtra = (widget.extra ?? 0) > 0;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final resolved = widget.resolved;

    return Padding(
      padding: const EdgeInsets.only(bottom: AlayaSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A `Wrap`, not a `Row`: a name, a field and an amount side by side overflow at 320dp with
          // the text scaler doubled, which is the gate every screen has to pass (Law U15).
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AlayaSpacing.sm,
            runSpacing: AlayaSpacing.xs,
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  widget.name,
                  style: AlayaTypography.body,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.method == SplitMethod.exactAmounts)
                SizedBox(
                  width: 130,
                  child: AmountField(
                    currencyCode: widget.currencyCode,
                    decimalDigits: widget.decimalDigits,
                    label: strings.splitShareAmount,
                    initialValue: widget.value == null
                        ? null
                        : Money(widget.value!, widget.currencyCode),
                    onChanged: (money) => widget.onValue(money?.minor),
                  ),
                )
              else if (widget.method != SplitMethod.equal)
                SizedBox(
                  width: 96,
                  child: TextFormField(
                    initialValue: _weightText,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: widget.method == SplitMethod.percent
                          ? strings.splitSharePercent
                          : strings.splitShareWeight,
                      suffixText: widget.method == SplitMethod.percent
                          ? '%'
                          : null,
                    ),
                    onChanged: (text) => widget.onValue(_parseWeight(text)),
                  ),
                ),
              if (resolved != null)
                AmountText(
                  resolved.amount,
                  size: AmountSize.small,
                  showSign: false,
                  decimalDigits: widget.decimalDigits,
                ),
              if (!_showExtra)
                TextButton.icon(
                  onPressed: () => setState(() => _showExtra = true),
                  icon: const Icon(Icons.add, size: AlayaIconSize.sm),
                  label: Text(strings.splitAddExtra),
                ),
            ],
          ),

          if (_showExtra)
            Padding(
              padding: const EdgeInsets.only(
                left: AlayaSpacing.md,
                top: AlayaSpacing.xs,
              ),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AlayaSpacing.sm,
                runSpacing: AlayaSpacing.xs,
                children: [
                  SizedBox(
                    width: 150,
                    child: AmountField(
                      currencyCode: widget.currencyCode,
                      decimalDigits: widget.decimalDigits,
                      label: strings.splitExtraLabel,
                      initialValue: widget.extra == null
                          ? null
                          : Money(widget.extra!, widget.currencyCode),
                      onChanged: (money) => widget.onExtra(money?.minor),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() => _showExtra = false);
                      widget.onExtra(null);
                    },
                    tooltip: strings.splitRemoveExtra,
                    icon: Icon(
                      Icons.close,
                      size: AlayaIconSize.md,
                      color: semantic.muted,
                    ),
                  ),
                ],
              ),
            ),

          // **The arithmetic, spelled out.** "₹1,150 + ₹400 just for them" rather than a bare ₹1,550 —
          // a total somebody cannot decompose is one they argue with.
          if (resolved?.extra != null && resolved?.fromRemainder != null)
            Padding(
              padding: const EdgeInsets.only(left: AlayaSpacing.md),
              child: Text(
                strings.splitShareBreakdown(
                  _plain(resolved!.fromRemainder!),
                  _plain(resolved.extra!),
                ),
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
            ),
        ],
      ),
    );
  }

  /// Basis points shown as whole percent — 2500 reads as `25`.
  ///
  /// Basis points are what the schema stores, because an integer keeps Law L1 intact; a percent sign
  /// is what a person types. The conversion lives here, at the one boundary between them.
  String get _weightText {
    final value = widget.value;
    if (value == null) return '';
    return widget.method == SplitMethod.percent
        ? (value ~/ 100).toString()
        : value.toString();
  }

  int? _parseWeight(String text) {
    final parsed = int.tryParse(text.trim());
    if (parsed == null) return null;
    return widget.method == SplitMethod.percent ? parsed * 100 : parsed;
  }

  /// A bare figure for the breakdown sentence.
  ///
  /// The one place this sheet renders money without `AmountText`, because the string is interpolated
  /// into a sentence the ARB owns. Law U7's single path to pixels is for figures a reader compares;
  /// this is prose, and an `AmountText` inside it would fight the caption style around it.
  String _plain(Money money) {
    final divisor = widget.decimalDigits == 0 ? 1 : 100;
    final whole = money.minor ~/ divisor;
    final frac = money.minor % divisor;
    return widget.decimalDigits == 0
        ? '$whole'
        : '$whole.${frac.toString().padLeft(widget.decimalDigits, '0')}';
  }
}
