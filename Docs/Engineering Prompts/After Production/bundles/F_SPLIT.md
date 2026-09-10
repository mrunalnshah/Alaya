# F_SPLIT

Shared expenses, groups, balances, settling up, the shareable summary.

**39 files · 9,240 lines.**  Written 2026-08-27T08:54:37-04:00.

Every file below is complete and current. Paths are destinations.

---

### `lib/features/split/presentation/screens/split_bill_screen.dart`

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/money/money_formatter.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/core/time/date_key_labels.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/split_group.dart';
import 'package:alaya/domain/services/split/split_resolver.dart';
import 'package:alaya/features/split/presentation/sheets/name_picker_sheet.dart';
import 'package:alaya/features/split/presentation/sheets/save_as_group_sheet.dart';
import 'package:alaya/features/split/presentation/widgets/people_counter.dart';
import 'package:alaya/features/split/presentation/widgets/split_method_picker.dart';
import 'package:alaya/features/split/presentation/widgets/split_proportion_bar.dart';
import 'package:alaya/features/split/presentation/widgets/split_tip_row.dart';
import 'package:alaya/features/split/providers/quick_split_handoff.dart';
import 'package:alaya/features/split/providers/split_bill_provider.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/account_picker.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// One participant while the bill is being worked out.
///
/// **A slot, not a person.** Arithmetic does not need to know who anybody is: at a table with the bill
/// in your hand, "four of us, equally, and the sushi was his" is answerable in three taps, and nobody
/// should wait while four contact records get typed. [payeeId] stays null until somebody is named,
/// and **it can stay null all the way through saving** — `SplitBill.save` creates a person for anybody
/// still anonymous, so the debt is real and the name can be fixed afterwards.
class _Slot {
  _Slot();

  /// Who this is, once named.
  String? payeeId;

  /// The weight, basis points or exact amount typed against this slot.
  int? value;

  /// What is charged to this slot alone — their sushi, or their contribution.
  int? extra;
}

/// Working out a bill, on one screen (ARCH_5 §3 archetype B).
///
/// ## Names are never required
///
/// Amount, tip, how many people, how it splits — and none of it needs a contact record, **including
/// the save.** An earlier version refused to save until every slot was named, which meant four contact
/// records demanded at the moment everybody is standing up to leave. Anybody still anonymous becomes a
/// person called "Person 4"; the debt appears in balances immediately and the name is fixed later,
/// because nothing anywhere stores a name — only the id.
///
/// ## Everything the arithmetic can express
///
/// Equally · by shares · by percentage · exact amounts, a tip on the whole bill, and on any row an
/// **extra** charged to that person alone — *"Ravi ordered ₹800 of sushi"* and *"I'll put in ₹2,000"*
/// are the same operation from two directions, which is why there is no separate subsidy mode.
///
/// ## And it makes groups, rather than expecting them
///
/// Once two people are named, the split itself can become a group. Making one used to mean leaving
/// here and re-picking the same four people — so nobody did, so nobody had groups.
class SplitBillScreen extends ConsumerStatefulWidget {
  /// Creates the screen. [expenseId] reopens an existing split for editing.
  const SplitBillScreen({this.expenseId, super.key});

  /// The split being edited, or null for a new one.
  ///
  /// **Passed as GoRouter's `extra` rather than through a second route.** `/split/:id/edit` would be a fifth
  /// route on a module that just went from eight to four, and the bill screen's draft is in-memory anyway —
  /// so a deep link into a half-edited split could not restore what it promised.
  final String? expenseId;

  @override
  ConsumerState<SplitBillScreen> createState() => _SplitBillScreenState();
}

class _SplitBillScreenState extends ConsumerState<SplitBillScreen> {
  final _title = TextEditingController();

  /// The bill as typed, before tip or rounding.
  ///
  /// **Held apart from the figure being split**, so the tip chips stay reversible: adding 10% and then
  /// clearing it must return the original bill, which is impossible once the two have been merged.
  Money? _bill;

  int _tipBasisPoints = 0;
  bool _roundUp = false;

  String? _groupId;
  String? _accountId;

  /// Who fronted the money, or null for the user.
  ///
  /// **Null rather than the user's own id, deliberately.** `split.selfPayeeId` resolves asynchronously, so a
  /// field initialised from it would be null for the first frame and indistinguishable from "not chosen".
  /// Null means *me*, and the save resolves it.
  String? _paidBy;

  /// Whether slot one has been claimed for the user yet.
  bool _claimedSelf = false;
  DateKey? _on;
  DateKey? _settleBy;
  SplitMethod _method = SplitMethod.equal;
  bool _recordExpense = true;
  int _digits = 2;

  /// Whether an existing split has been read into the fields yet.
  bool _loadedExisting = false;

  /// True while that read is in flight, so the screen does not offer to save an empty draft over a real split.
  bool _loadingExisting = false;

  /// **Two by default, because one person is not a split.**
  final List<_Slot> _slots = [_Slot(), _Slot()];

  /// What actually gets divided: the bill, plus tip, rounded if asked.
  Money? get _total => SplitTipRow.totalFor(
    base: _bill,
    basisPoints: _tipBasisPoints,
    roundUp: _roundUp,
    decimalDigits: _digits,
  );

  @override
  void initState() {
    super.initState();
    // **Picked up from the home card, so a bill worked out there is not typed twice.**
    final pending = ref.read(quickSplitHandoffProvider);
    if (pending == null) return;
    _bill = pending.total;
    // The card asks whether the user paid; this screen asks whether to record the expense. Same
    // question, so carrying the answer means the switch is already right.
    _recordExpense = pending.iPaid;
    while (_slots.length < pending.people) {
      _slots.add(_Slot());
    }
    // **Cleared after the frame, not here.** Riverpod refuses a provider mutation during a build, and
    // `initState` runs inside one. Reading now and clearing next frame keeps the values available for
    // the first paint while still making the handoff single-use.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(quickSplitHandoffProvider.notifier).take();
    });
  }

  /// Reads an existing split into the fields, once.
  ///
  /// **Every field comes from the row, including the payer**, so re-saving cannot silently change who
  /// covered the bill. The one thing that does not survive is the tip: the total is stored with the tip
  /// already in it — there is no separate column, deliberately, because a stored tip would be a second
  /// number that could disagree with the total. Reopening therefore shows the tipped figure as the bill,
  /// which is what was actually divided.
  Future<void> _loadExisting(String id) async {
    if (_loadedExisting || _loadingExisting) return;
    _loadingExisting = true;
    final expense = await ref
        .read(splitLedgerRepositoryProvider)
        .expenseById(id);
    if (!mounted) return;
    _loadingExisting = false;
    if (expense == null) {
      // Deleted from under the screen. Left as a blank new split rather than closed, because closing would
      // discard whatever the user had already typed on top of it.
      setState(() => _loadedExisting = true);
      return;
    }
    setState(() {
      _loadedExisting = true;
      _bill = expense.total;
      _method = expense.splitMethod;
      _groupId = expense.groupId;
      _on = expense.dateKey;
      _settleBy = expense.settleByDateKey;
      _title.text = expense.title ?? '';
      _paidBy = expense.paidByPayeeId;
      // Nothing new is written to the ledger on an edit, so the switch is off and stays off.
      _recordExpense = false;
      _slots
        ..clear()
        ..addAll([
          for (final share in expense.shares)
            _Slot()
              ..payeeId = share.payeeId
              // An extra is stored in the same column as a weight or a percentage, distinguished only by
              // `inputKind` — so reading it back into the wrong field would turn "₹800 of sushi" into a
              // weight of 800 and divide the bill eight hundred ways.
              ..value = share.inputKind == ShareInputKind.extra
                  ? null
                  : share.inputValue
              ..extra = share.inputKind == ShareInputKind.extra
                  ? share.inputValue
                  : null,
        ]);
      if (_slots.isEmpty) _slots.add(_Slot());
      // Already named by the row it came from; claiming slot one again would overwrite a real participant.
      _claimedSelf = true;
    });
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  /// Puts the user in the first slot, once their id is known.
  ///
  /// **"Four of us" means four including you**, and until now it did not. The slots were all anonymous and
  /// the payer was forced to be the user, so splitting ₹5,000 four ways produced four placeholders owing
  /// ₹1,250 each — ₹5,000 owed to you, when one of those four *was* you. You were over-owed by your own
  /// share, and nothing contradicted it because the "I owe" arm of the balance view was unreachable.
  ///
  /// Scheduled after the frame rather than assigned in `build`: `splitSelfProvider` is a `FutureProvider`
  /// and Riverpod refuses a mutation during a build. The same reason the quick-split handoff is cleared this
  /// way.
  void _claimFirstSlotForSelf(String self) {
    if (_claimedSelf || _slots.isEmpty) return;
    _claimedSelf = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _slots.first.payeeId != null) return;
      setState(() => _slots.first.payeeId = self);
    });
  }

  /// Applies [change] and rebuilds.
  ///
  /// **No dirty flag.** This screen carried one until it stopped being an `AlayaFormScaffold`; the
  /// discard guard went with the change to a calculator and the field stayed, assigned on every edit
  /// and read by nothing. Most uses here are throwaway arithmetic, and a "discard your changes?" sheet
  /// in front of somebody who just wanted a number is friction charged for nothing.
  void _touch(VoidCallback change) => setState(change);

  void _setCount(int count) => _touch(() {
    // Added and removed from the end, so a name already assigned to Person 1 stays on Person 1.
    while (_slots.length < count) {
      _slots.add(_Slot());
    }
    while (_slots.length > count && _slots.length > 1) {
      _slots.removeLast();
    }
  });

  /// The label for slot [index] — "You", a name once assigned, or a number until then.
  ///
  /// **The user's own slot reads "You", not their name.** Two reasons, and the second is a bug the tests
  /// found: "You owe ₹1,250" is clearer than "Mrunal owes ₹1,250" on your own screen — and looking the id up
  /// in `splitPeopleProvider` returned "Someone" whenever the self payee was not in that list, which is
  /// every widget test and any install where the row was archived.
  String _labelFor(
    int index,
    List<Payee> people,
    AlayaStrings strings, {
    String? self,
  }) {
    final id = _slots[index].payeeId;
    if (id == null) return strings.splitPersonN(index + 1);
    if (self != null && id == self) return strings.splitPaidByYou;
    for (final payee in people) {
      if (payee.id == id) return _disambiguated(payee, people);
    }
    return strings.splitUnknownPerson;
  }

  /// A payee's name, with their phone appended when somebody else shares the name.
  static String _disambiguated(Payee payee, List<Payee> people) {
    final clashes = people.where((p) => p.name == payee.name).length > 1;
    final phone = payee.phone?.trim();
    if (!clashes || phone == null || phone.isEmpty) return payee.name;
    return '${payee.name} · $phone';
  }

  ShareInput _inputFor(int index, String payeeId) {
    final slot = _slots[index];
    // An extra wins over the method, and that is not a conflict: an extra says what somebody owes on
    // top, the method says how the rest divides.
    final extra = slot.extra;
    if (extra != null && extra > 0) return ShareInput.extra(payeeId, extra);
    return switch (_method) {
      SplitMethod.equal => ShareInput.equal(payeeId),
      SplitMethod.shares => ShareInput.shares(payeeId, slot.value ?? 1),
      SplitMethod.percent => ShareInput.percent(payeeId, slot.value ?? 0),
      SplitMethod.exactAmounts => ShareInput.exact(payeeId, slot.value ?? 0),
      // Itemised splits come from a receipt's lines, which this screen does not have. Named so adding
      // an enum member breaks here rather than falling through — Law L13.
      SplitMethod.perLine => ShareInput.equal(payeeId),
    };
  }

  /// Resolves against synthetic ids, so the arithmetic runs before anybody is named.
  ///
  /// **`slot-0`, `slot-1` … rather than payee ids.** `SplitResolver` needs only distinct keys, so the
  /// same resolver that will write the shares runs on a table of strangers — a calculator first and a
  /// ledger second, with no second implementation to keep in step.
  SplitResolution? _resolve() {
    final total = _total;
    if (total == null || total.isZero || _slots.isEmpty) return null;
    try {
      return const SplitResolver().resolve(
        total: total,
        inputs: [
          for (var i = 0; i < _slots.length; i++) _inputFor(i, 'slot-$i'),
        ],
      );
    } on ArgumentError {
      return null;
    }
  }

  ResolvedShare? _shareForSlot(SplitResolution? r, int index) {
    if (r == null) return null;
    for (final share in r.shares) {
      if (share.payeeId == 'slot-$index') return share;
    }
    return null;
  }

  Future<void> _pickName(int index, List<Payee> people) async {
    final chosen = await NamePickerSheet.show(
      context,
      people: people,
      selected: _slots[index].payeeId,
      taken: {
        for (var i = 0; i < _slots.length; i++)
          if (i != index && _slots[i].payeeId != null) _slots[i].payeeId!,
      },
    );
    if (chosen == null || !mounted) return;
    _touch(() => _slots[index].payeeId = chosen);
  }

  /// Applies a group: its members fill the slots, and its weights the values.
  void _applyGroup(SplitGroup? group) => _touch(() {
    _groupId = group?.id;
    if (group == null) return;
    _slots
      ..clear()
      ..addAll([
        for (final member in group.members) _Slot()..payeeId = member.payeeId,
      ]);
    final weights = group.defaultWeightsByPayee;
    if (weights == null) {
      // A partial set prefills nothing: treating an unweighted member as weightless would invent an
      // instruction — "she did not eat" is a real thing to mean.
      _method = SplitMethod.equal;
      return;
    }
    _method = SplitMethod.shares;
    for (final slot in _slots) {
      slot.value = weights[slot.payeeId];
    }
  });

  /// Slot [index]'s weight expressed against the whole, in basis points.
  ///
  /// **Weights are relative — 2:1:1 and 4:2:2 are the same split** — so storing the raw number would
  /// make a group's defaults depend on which of the two somebody typed. Converting against the total
  /// makes both come back as 50/25/25. They need not sum to 10,000: three equal members store 3,333
  /// each, and a group's weights are used as *shares* where only the ratio matters.
  int? _weightAsBasisPoints(int index) {
    var total = 0;
    for (final slot in _slots) {
      total += slot.value ?? 1;
    }
    if (total <= 0) return null;
    return ((_slots[index].value ?? 1) * 10000) ~/ total;
  }

  /// Turns the people currently on the bill into a reusable group.
  ///
  /// **Only offered once at least two slots are named**, because a group of anonymous placeholders is
  /// a group of nobody — members are `payees` rows and a slot without one has nothing to store. That
  /// is the one thing on this screen naming is still required for.
  Future<void> _saveAsGroup(
    List<Payee> people,
    AlayaStrings strings, {
    String? self,
  }) async {
    final candidates = <GroupCandidate>[
      for (var i = 0; i < _slots.length; i++)
        if (_slots[i].payeeId case final id?)
          (
            payeeId: id,
            name: _labelFor(i, people, strings, self: self),
            weightBasisPoints: _method == SplitMethod.shares
                ? _weightAsBasisPoints(i)
                : null,
          ),
    ];
    if (candidates.length < 2) return;

    final saved = await SaveAsGroupSheet.show(context, candidates: candidates);
    if (saved == null || !mounted) return;

    final groups =
        ref.read(splitAllGroupsProvider).valueOrNull ?? const <SplitGroup>[];
    for (final group in groups) {
      if (group.name == saved) {
        _touch(() => _groupId = group.id);
        break;
      }
    }
    if (mounted) showResultSnack(context, message: strings.splitGroupSaved);
  }

  /// The result as plain text, for the group chat.
  String _resultText(
    SplitResolution resolution,
    List<Payee> people,
    AlayaStrings strings, {
    String? self,
  }) {
    const formatter = MoneyFormatter();
    String money(Money m) =>
        formatter.format(m, decimalDigits: _digits, symbol: m.currencyCode);

    final buffer = StringBuffer();
    final what = _title.text.trim();
    buffer.writeln(what.isEmpty ? strings.splitBillAction : what);

    final bill = _bill;
    final tipped = bill != null && resolution.total.minor != bill.minor;
    buffer.writeln(
      tipped
          // Bill and adjustment stated separately, because "we paid 5,240" and "the bill was 4,763"
          // are both things somebody at the table will want to check.
          ? '${money(bill)} + ${money(Money(resolution.total.minor - bill.minor, bill.currencyCode))}'
                ' = ${money(resolution.total)}'
          : money(resolution.total),
    );
    buffer.writeln();

    for (var i = 0; i < _slots.length; i++) {
      final share = _shareForSlot(resolution, i);
      if (share == null) continue;
      final label = _labelFor(i, people, strings, self: self);
      final extra = share.extra;
      buffer.writeln(
        extra == null
            ? '$label: ${money(share.amount)}'
            : '$label: ${money(share.amount)}  '
                  '(${money(share.fromRemainder ?? extra)} + ${money(extra)})',
      );
    }
    if (!resolution.isExact) {
      buffer
        ..writeln()
        ..writeln(
          '${resolution.isOverAllocated ? strings.splitOverAllocated : strings.splitUnallocated}'
          ' ${money(resolution.unallocated.abs())}',
        );
    }
    return buffer.toString().trimRight();
  }

  /// What the ledger row and the split will say about this evening.
  ///
  /// **Because a transaction reading "₹5,000" with no payee and no note is unidentifiable a month later.** A
  /// split expense sets no `payeeId` — there is no single counterparty to name — so the note is the only thing
  /// carrying meaning into the ledger, and it used to be the title alone, which is often empty.
  ///
  /// **Only participants with a real name are listed, and the rest are counted.** The screen labels an unnamed
  /// slot "Person 2", but `SplitBill.save` numbers new placeholders past everything that already exists — so
  /// the slot shown as "Person 2" may be stored as "Person 7", and a note naming the first would point at
  /// nobody. Counting them avoids the mismatch and reads better than a list of placeholders either way.
  ///
  /// **You are never in the list.** "Split 4 ways with you and Ravi" is a sentence about somebody else; the
  /// count already includes you.
  ///
  /// Four complete sentences rather than fragments joined by a separator: a translator needs the whole
  /// sentence to order it, and a raw `' · '` is the string literal Law U5 forbids.
  String _noteFor(List<Payee> people, AlayaStrings strings, String? self) {
    final named = <String>[
      for (var i = 0; i < _slots.length; i++)
        if (_slots[i].payeeId case final id?)
          if (id != self) _labelFor(i, people, strings, self: self),
    ];
    final title = _title.text.trim();
    // A comma-space join is punctuation rather than copy — the same call `_plain` makes about a decimal point.
    // The *sentences* around it are in the ARB, which is where Law U5 draws the line.
    final names = named.join(', ');

    if (title.isEmpty) {
      return named.isEmpty
          ? strings.splitNoteWays(_slots.length)
          : strings.splitNoteWaysWith(_slots.length, names);
    }
    return named.isEmpty
        ? strings.splitNoteTitled(title, _slots.length)
        : strings.splitNoteTitledWith(title, _slots.length, names);
  }

  Future<void> _save() async {
    final strings = AlayaStrings.of(context);
    final total = _total;
    if (total == null) return;
    final people = ref.read(splitPeopleProvider).valueOrNull ?? const <Payee>[];
    final self = ref.read(splitSelfProvider).valueOrNull;

    final ok = await ref
        .read(splitBillProvider.notifier)
        .save(
          total: total,
          // **Slots, not resolved inputs.** The provider names anybody anonymous first and then builds
          // the inputs against the ids it got back — so the screen hands over what the user chose and
          // never has to invent a payee itself.
          participants: [
            for (final slot in _slots)
              (payeeId: slot.payeeId, value: slot.value, extra: slot.extra),
          ],
          method: _method,
          recordExpense: _recordExpense,
          expenseId: widget.expenseId,
          paidByPayeeId: _paidBy,
          note: _noteFor(people, strings, self),
          accountId: _accountId,
          groupId: _groupId,
          title: _title.text.trim().isEmpty ? null : _title.text.trim(),
          on: _on,
          settleBy: _settleBy,
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
    showResultSnack(context, message: strings.splitBillSaved);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    _digits = ref.watch(splitDecimalDigitsProvider).valueOrNull ?? 2;
    final people =
        ref.watch(splitPeopleProvider).valueOrNull ?? const <Payee>[];
    final groups =
        ref.watch(splitAllGroupsProvider).valueOrNull ?? const <SplitGroup>[];
    final accounts =
        ref.watch(splitAccountsProvider).valueOrNull ?? const <Account>[];
    final self = ref.watch(splitSelfProvider).valueOrNull;
    final submitting = ref.watch(splitBillProvider).isLoading;

    final editing = widget.expenseId;
    if (editing != null) {
      unawaited(_loadExisting(editing));
    } else if (self != null) {
      _claimFirstSlotForSelf(self);
    }
    final resolution = _resolve();
    final named = _slots.where((s) => s.payeeId != null).length;
    final unnamed = _slots.length - named;
    // **Naming is no longer a condition of saving.** The only two are an amount to divide and knowing
    // which person is the user — the first because there is nothing to save without it, the second
    // because a balance has no direction without it.
    final canSave = resolution != null && self != null && !submitting;

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(
          widget.expenseId == null
              ? strings.splitBillAction
              : strings.splitEditTitle,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AlayaSpacing.screenEdge,
          AlayaSpacing.md,
          AlayaSpacing.screenEdge,
          AlayaSpacing.xxxl * 3,
        ),
        children: [
          // ── 1. how much ─────────────────────────────────────────────────────────────────
          AmountField(
            currencyCode: 'INR',
            decimalDigits: _digits,
            label: strings.splitBillAmount,
            // **No `autofocus`.** A keyboard on arrival covers the tip chips, the people counter and the
            // method picker — everything somebody needs to *see* before deciding what to type. The rule
            // this follows: focus a field on open only when the surface has nothing to read or choose, and
            // was opened by a tap that named that field. A bill editor is the opposite of both.
            // **The handoff was arriving and rendering blank.** `initState` set `_bill` from the quick
            // card, so the arithmetic was right and the field showed nothing — "the amount I wrote before
            // is not written though it takes it into consideration". `AmountField` has taken an
            // `initialValue` all along; this screen never passed one.
            //
            // Safe on every rebuild: the field builds its controller once from this value, so passing
            // `_bill` cannot fight a keystroke.
            initialValue: _bill,
            onChanged: (value) => _touch(() => _bill = value),
          ),

          // ── 2. the tip, because a restaurant bill is not the number on the slip ─────────
          const SizedBox(height: AlayaSpacing.sm),
          SplitTipRow(
            base: _bill,
            basisPoints: _tipBasisPoints,
            roundUp: _roundUp,
            decimalDigits: _digits,
            onTip: (bp) => _touch(() => _tipBasisPoints = bp),
            onRoundUp: (value) => _touch(() => _roundUp = value),
          ),

          // ── 3. how many ─────────────────────────────────────────────────────────────────
          const SizedBox(height: AlayaSpacing.md),
          // **Typable as well as tappable (#7).** Two to four is a tap each way; two to fourteen is
          // twelve taps, which is where a stepper stops being a convenience. The same control the home
          // card uses, so the two screens answer "how many of us" identically.
          _PeopleRow(count: _slots.length, onChanged: _setCount),

          // ── 4. how it splits ────────────────────────────────────────────────────────────
          const SizedBox(height: AlayaSpacing.lg),
          // **Four segments at 320dp is eighty pixels each, and a `SegmentedButton` cannot wrap** — its
          // children take an equal slice of whatever width exists and clip. "By percentage" at a doubled
          // text scale had nowhere to go. Chips reflow onto a second line, and a caption now explains the
          // selected method, which the four labels were never able to carry.
          SplitMethodPicker(
            method: _method,
            onChanged: (method) => _touch(() => _method = method),
          ),

          const SizedBox(height: AlayaSpacing.md),
          for (var i = 0; i < _slots.length; i++)
            _SlotRow(
              label: _labelFor(i, people, strings, self: self),
              named: _slots[i].payeeId != null,
              method: _method,
              currencyCode: _total?.currencyCode ?? 'INR',
              decimalDigits: _digits,
              value: _slots[i].value,
              extra: _slots[i].extra,
              resolved: _shareForSlot(resolution, i),
              onName: () => _pickName(i, people),
              onValue: (v) => _touch(() => _slots[i].value = v),
              onExtra: (v) => _touch(() => _slots[i].extra = v),
            ),

          if (resolution != null && !resolution.isExact) ...[
            const SizedBox(height: AlayaSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusChip(
                // Never auto-balanced. Forcing the shares to equal the total would charge somebody for
                // a discrepancy nobody told them about (anomaly A11's rule, one table over).
                label: resolution.isOverAllocated
                    ? strings.splitOverAllocated
                    : strings.splitUnallocated,
                tone: StatusTone.warning,
                trailing: AmountText(
                  resolution.unallocated.abs(),
                  size: AmountSize.small,
                  showSign: false,
                  decimalDigits: _digits,
                ),
              ),
            ),
          ],

          // ── the answer, drawn and shareable, with nobody named ──────────────────────────
          if (resolution != null) ...[
            SectionHeader(
              label: strings.splitBillTheSplit,
              padding: const EdgeInsets.only(
                top: AlayaSpacing.xl,
                bottom: AlayaSpacing.sm,
              ),
            ),
            SplitProportionBar(
              slices: [
                for (var i = 0; i < _slots.length; i++)
                  if (_shareForSlot(resolution, i) case final share?)
                    ProportionSlice(
                      label: _labelFor(i, people, strings, self: self),
                      amount: share.amount,
                      extra: share.extra,
                    ),
              ],
              total: resolution.total,
              decimalDigits: _digits,
            ),

            const SizedBox(height: AlayaSpacing.md),
            AlayaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    strings.splitBillResultHint,
                    style: AlayaTypography.caption.copyWith(
                      color: semantic.muted,
                    ),
                  ),
                  const SizedBox(height: AlayaSpacing.sm),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(
                          text: _resultText(
                            resolution,
                            people,
                            strings,
                            self: self,
                          ),
                        ),
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
                    label: Text(strings.splitCopyResult),
                  ),
                ],
              ),
            ),
          ],

          // ── keeping it: everything below is optional ────────────────────────────────────
          SectionHeader(
            label: strings.splitBillKeepIt,
            padding: const EdgeInsets.only(
              top: AlayaSpacing.xl,
              bottom: AlayaSpacing.xxs,
            ),
          ),
          Text(
            strings.splitBillKeepItHelp,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),

          const SizedBox(height: AlayaSpacing.md),
          TextFormField(
            controller: _title,
            decoration: InputDecoration(
              labelText: strings.splitBillWhatFor,
              hintText: strings.splitBillWhatForHint,
            ),
            onChanged: (_) => _touch(() {}),
          ),

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

          // **Making a group out of the split you already have.** The one thing here that still needs
          // names, because a group's members are `payees` rows and a placeholder is not somebody you
          // meant to keep.
          if (_groupId == null && named >= 2) ...[
            const SizedBox(height: AlayaSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _saveAsGroup(people, strings, self: self),
                icon: const Icon(
                  Icons.group_add_outlined,
                  size: AlayaIconSize.md,
                ),
                label: Text(strings.splitSaveAsGroupAction(named)),
              ),
            ),
          ],

          const SizedBox(height: AlayaSpacing.md),
          // **Who paid, and this control is why "You owe" can be anything other than zero.**
          // `v_split_balances` reports a debt of yours only when the payer is somebody else; the column and
          // the view have always supported it and no screen ever offered it, so one whole direction of the
          // module was dead.
          _PaidByPicker(
            options: [
              for (var i = 0; i < _slots.length; i++)
                (
                  payeeId: _slots[i].payeeId,
                  label: _labelFor(i, people, strings, self: self),
                  isSelf:
                      _slots[i].payeeId != null && _slots[i].payeeId == self,
                ),
            ],
            paidBy: _paidBy,
            onChanged: (payeeId) => _touch(() {
              _paidBy = payeeId;
              // Somebody else's money did not leave your account, so there is nothing to record in your
              // ledger until you settle. Forced here as well as in the provider, so the switch below cannot
              // sit on while being ignored.
              if (payeeId != null && payeeId != self) _recordExpense = false;
            }),
          ),

          const SizedBox(height: AlayaSpacing.md),
          SwitchListTile(
            value: _recordExpense,
            contentPadding: EdgeInsets.zero,
            title: Text(strings.splitBillRecordExpense),
            subtitle: Text(
              strings.splitBillRecordExpenseHelp,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
            onChanged: _paidBy != null && _paidBy != self
                ? null
                : (value) => _touch(() => _recordExpense = value),
          ),
          if (_recordExpense) ...[
            const SizedBox(height: AlayaSpacing.sm),
            AccountPicker(
              accounts: accounts,
              selected: _accountFor(accounts, _accountId),
              label: strings.labelAccount,
              hint: strings.hintSelectAccount,
              onChanged: (account) => _touch(() => _accountId = account.id),
            ),
          ],

          const SizedBox(height: AlayaSpacing.md),
          DatePickerField(
            value: _on ?? ref.read(splitTodayProvider),
            label: strings.labelDate,
            formatted: (date) => date.fullLabel,
            onChanged: (date) => _touch(() => _on = date),
          ),
          const SizedBox(height: AlayaSpacing.md),
          DatePickerField(
            value: _settleBy,
            label: strings.splitSettleByLabel,
            hint: strings.splitSettleByHint,
            firstDate: ref.read(splitTodayProvider),
            formatted: (date) => date.fullLabel,
            onChanged: (date) => _touch(() => _settleBy = date),
          ),

          if (unnamed > 0) ...[
            const SizedBox(height: AlayaSpacing.md),
            Text(
              // **Tells you what will happen instead of stopping you.** This used to read "Name 2 more
              // people to save this" and disable the button — four contact records demanded at the
              // moment everybody is standing up to leave. Now it says where they will land and that
              // the name is fixable, which is information rather than a wall.
              strings.splitUnnamedWillBeSaved(unnamed),
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
          ],
          if (self == null) ...[
            const SizedBox(height: AlayaSpacing.xs),
            Text(
              strings.splitSelfPayeeUnset,
              style: AlayaTypography.caption.copyWith(color: semantic.warning),
            ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: canSave ? _save : null,
        backgroundColor: canSave ? null : Theme.of(context).disabledColor,
        icon: const Icon(Icons.check, size: AlayaIconSize.md),
        label: Text(strings.splitSaveToBalances),
      ),
    );
  }

  static Account? _accountFor(List<Account> accounts, String? id) {
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }
}

/// How many people are sharing.
///
/// **A thin wrapper over [PeopleCounter], not a second stepper.** This screen had its own — a minus, a
/// `Text`, a plus — while the home card had a typable one, so the same question behaved differently
/// depending on which screen you asked it from. The label and its help line stay here because they are
/// this screen's copy; the control comes from one place.
class _PeopleRow extends StatelessWidget {
  const _PeopleRow({required this.count, required this.onChanged});

  final int count;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AlayaSpacing.sm,
      runSpacing: AlayaSpacing.xs,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(strings.splitHowManyPeople, style: AlayaTypography.body),
            Text(
              strings.splitHowManyPeopleHelp,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
          ],
        ),
        // `minimum: 1`, not 2. One participant is a degenerate split the resolver accepts — "I paid, she
        // owes me all of it" — and the home card's 2 is right there because a *calculator* dividing by one
        // is not a calculation.
        PeopleCounter(count: count, minimum: 1, onChanged: onChanged),
      ],
    );
  }
}

/// One option on the payer picker.
typedef PayerOption = ({String? payeeId, String label, bool isSelf});

/// Who fronted the money.
///
/// **The control that makes "You owe" reachable.** `v_split_balances` has two arms — others owe you when you
/// paid, you owe when somebody else did — and the second was dead because the bill screen forced the payer
/// to be the user. The column, the service and the view had all supported it since the schema was written.
///
/// **Chips rather than a dropdown**, for the same reason the method picker uses them: at 320dp with the
/// scaler doubled a row of names has to reflow, and "who paid" is a question with two or three plausible
/// answers rather than a long list.
///
/// Unnamed participants are offered. *"Person 3 paid"* is honest — you know somebody covered it and you have
/// not put a name to them yet, and refusing would make the whole feature wait on typing contacts, which is
/// what this screen exists not to do.
class _PaidByPicker extends StatelessWidget {
  const _PaidByPicker({
    required this.options,
    required this.paidBy,
    required this.onChanged,
  });

  final List<PayerOption> options;

  /// The chosen payer, or null for the user.
  final String? paidBy;

  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.splitWhoPaid,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            ChoiceChip(
              label: Text(strings.splitPaidByYou),
              // Null and the user's own id both mean "me". The screen holds null so the first frame is not
              // waiting on an async read, and treating them as one here keeps the chip selected either way.
              selected:
                  paidBy == null ||
                  options.any((o) => o.isSelf && o.payeeId == paidBy),
              onSelected: (_) => onChanged(null),
            ),
            for (final option in options)
              if (!option.isSelf && option.payeeId != null)
                ChoiceChip(
                  label: Text(option.label),
                  selected: paidBy == option.payeeId,
                  onSelected: (_) => onChanged(option.payeeId),
                ),
          ],
        ),
        if (paidBy != null) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Text(
            // Says what changes, because it is not obvious: no money left your account, so nothing appears
            // in your ledger until the debt is settled. That is the whole point of the case.
            strings.splitPaidBySomebodyElseHelp,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
        ],
      ],
    );
  }
}

/// One participant: their label, whatever the method asks for, their extra, and what it comes to.
class _SlotRow extends StatefulWidget {
  const _SlotRow({
    required this.label,
    required this.named,
    required this.method,
    required this.currencyCode,
    required this.decimalDigits,
    required this.value,
    required this.extra,
    required this.resolved,
    required this.onName,
    required this.onValue,
    required this.onExtra,
  });

  final String label;
  final bool named;
  final SplitMethod method;
  final String currencyCode;
  final int decimalDigits;
  final int? value;
  final int? extra;
  final ResolvedShare? resolved;
  final VoidCallback onName;
  final ValueChanged<int?> onValue;
  final ValueChanged<int?> onExtra;

  @override
  State<_SlotRow> createState() => _SlotRowState();
}

class _SlotRowState extends State<_SlotRow> {
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
          // A `Wrap`, not a `Row`: a label, a field and an amount side by side overflow at 320dp with
          // the text scaler doubled, which is the gate every screen has to pass (Law U15).
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AlayaSpacing.sm,
            runSpacing: AlayaSpacing.xs,
            children: [
              // The label is the naming affordance. Unnamed it is muted and italic, so a row of
              // "Person 1 · Person 2" reads as placeholders rather than as people called that.
              SizedBox(
                width: 132,
                child: InkWell(
                  onTap: widget.onName,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AlayaSpacing.xxs,
                    ),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AlayaSpacing.xxs,
                      children: [
                        Text(
                          widget.label,
                          overflow: TextOverflow.ellipsis,
                          style: widget.named
                              ? AlayaTypography.body
                              : AlayaTypography.body.copyWith(
                                  color: semantic.muted,
                                  fontStyle: FontStyle.italic,
                                ),
                        ),
                        Icon(
                          widget.named
                              ? Icons.edit_outlined
                              : Icons.person_outline,
                          size: AlayaIconSize.sm,
                          color: semantic.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (widget.method == SplitMethod.exactAmounts)
                SizedBox(
                  width: 128,
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
                  width: 92,
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
                    width: 170,
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

          // **The arithmetic, spelled out.** "₹1,050 share + ₹800 just for them" rather than a bare
          // ₹1,850 — a total somebody cannot decompose is one they argue with.
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

  /// A bare figure for the breakdown sentence, which the ARB owns as prose.
  String _plain(Money money) {
    final divisor = widget.decimalDigits == 0 ? 1 : 100;
    final whole = money.minor ~/ divisor;
    final frac = money.minor % divisor;
    return widget.decimalDigits == 0
        ? '$whole'
        : '$whole.${frac.toString().padLeft(widget.decimalDigits, '0')}';
  }
}
```

### `lib/features/split/presentation/screens/split_group_editor_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/split_group.dart';
import 'package:alaya/features/split/providers/split_group_editor_provider.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Creating or editing one split group (ARCH_5 §3 archetype B).
///
/// **This is where default weights are set, and it is what makes "flatmates, 40/30/30" a single tap
/// later.** Without it every shared rent is four numbers retyped monthly, which is the friction that
/// makes people stop using a split app after the third week.
///
/// **Weights are optional and all-or-nothing.** A group where three members carry a weight and one
/// does not cannot prefill anything: treating the fourth as weightless would invent an instruction —
/// *"she did not eat"* is a real thing to mean and must never be inferred from a blank field. That is
/// `SplitGroup.defaultWeightsByPayee` returning null rather than a partial map, and this screen says
/// so rather than letting a half-filled set look finished.
class SplitGroupEditorScreen extends ConsumerStatefulWidget {
  /// Creates the editor. [groupId] null means a new group.
  const SplitGroupEditorScreen({this.groupId, super.key});

  /// The group being edited, or null for a new one.
  final String? groupId;

  @override
  ConsumerState<SplitGroupEditorScreen> createState() =>
      _SplitGroupEditorScreenState();
}

class _SplitGroupEditorScreenState
    extends ConsumerState<SplitGroupEditorScreen> {
  final _name = TextEditingController();
  final _members = <String>[];
  final _weights = <String, int>{};
  final _memberIds = <String, String>{};
  SplitMethod _method = SplitMethod.equal;
  bool _isArchived = false;
  int _sortOrder = 0;
  bool _dirty = false;
  bool _loaded = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Copies the saved group into local state, exactly once.
  ///
  /// The `_loaded` guard is the same one `TagEditorScreen` uses: the provider re-emits on every write
  /// to the table, and without it a stream tick mid-edit would overwrite what the user is typing.
  void _adopt(SplitGroup? group) {
    if (_loaded) return;
    _loaded = true;
    if (group == null) return;
    _name.text = group.name;
    _method = group.defaultSplitMethod;
    _isArchived = group.isArchived;
    _sortOrder = group.sortOrder;
    for (final member in group.members) {
      _members.add(member.payeeId);
      _memberIds[member.payeeId] = member.id;
      final weight = member.defaultWeightBasisPoints;
      if (weight != null) _weights[member.payeeId] = weight;
    }
  }

  void _toggle(String payeeId) => setState(() {
    _dirty = true;
    if (_members.remove(payeeId)) {
      // The weight goes with the member. Leaving it behind would silently reapply an old share if the
      // same person were added back later, which is the kind of value that reappears with no
      // explanation on screen.
      _weights.remove(payeeId);
      return;
    }
    _members.add(payeeId);
  });

  Future<void> _save(SplitGroup? existing) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref
        .read(splitGroupEditorProvider.notifier)
        .save(
          id: existing?.id,
          name: _name.text,
          defaultSplitMethod: _method,
          isArchived: _isArchived,
          sortOrder: _sortOrder,
          members: [
            for (final payeeId in _members)
              (
                payeeId: payeeId,
                weightBasisPoints: _weights[payeeId],
                memberId: _memberIds[payeeId],
              ),
          ],
        );
    if (!mounted) return;
    if (!saved) {
      // The repository's own sentence — a duplicate name and a member listed twice are different
      // problems, and "something went wrong" is what made a form unfixable (Law U9).
      final why = ref.read(splitGroupEditorProvider.notifier).lastError;
      showFailureSnack(context, message: why ?? strings.errorBodyGeneric);
      return;
    }
    showResultSnack(context, message: strings.actionSaved);
    context.pop();
  }

  Future<void> _delete(SplitGroup group) async {
    final strings = AlayaStrings.of(context);
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.splitDeleteGroupTitle,
      body: strings.splitDeleteGroupBody,
      confirmLabel: strings.actionDelete,
      cancelLabel: strings.actionCancel,
    );
    if (!confirmed || !mounted) return;
    final done = await ref
        .read(splitGroupEditorProvider.notifier)
        .delete(group.id);
    if (!mounted) return;
    if (!done) {
      // **The refusal that matters.** A group with expenses cannot be deleted, and the repository's
      // message names the alternative: *"Archive it instead — its history stays and it leaves the
      // pickers."* Showing a generic failure here would leave the user with no way forward.
      final why = ref.read(splitGroupEditorProvider.notifier).lastError;
      showFailureSnack(context, message: why ?? strings.errorBodyGeneric);
      return;
    }
    showResultSnack(context, message: strings.actionDeleted);
    context.pop();
  }

  Widget _shell(AlayaStrings strings, Widget body) => Scaffold(
    appBar: AppBar(
      leading: const CloseButton(),
      title: Text(
        widget.groupId == null
            ? strings.splitGroupNew
            : strings.splitGroupEditTitle,
      ),
    ),
    body: body,
  );

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final people =
        ref.watch(splitPeopleProvider).valueOrNull ?? const <Payee>[];
    final submitting = ref.watch(splitGroupEditorProvider).isLoading;

    final id = widget.groupId;
    if (id == null) {
      _adopt(null);
      return _shell(
        strings,
        _form(strings, people, existing: null, submitting: submitting),
      );
    }

    final group = ref.watch(splitGroupProvider(id));
    return group.when(
      loading: () => _shell(strings, const SizedBox.shrink()),
      error: (error, stack) => _shell(
        strings,
        ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(splitGroupProvider(id)),
        ),
      ),
      data: (found) {
        if (found == null) {
          return _shell(
            strings,
            ErrorState(
              title: strings.errorTitleNotFound,
              body: strings.errorBodyNotFound,
            ),
          );
        }
        _adopt(found);
        return _shell(
          strings,
          _form(strings, people, existing: found, submitting: submitting),
        );
      },
    );
  }

  Widget _form(
    AlayaStrings strings,
    List<Payee> people, {
    required SplitGroup? existing,
    required bool submitting,
  }) {
    final semantic = context.semantic;
    final weighted = _members.where(_weights.containsKey).length;
    // All-or-nothing, and said out loud. A partially weighted group prefills nothing, so a user who
    // filled three of four boxes needs to know the fourth is not optional rather than discovering it
    // when the split comes out equal.
    final partial = weighted > 0 && weighted != _members.length;

    return AlayaFormScaffold(
      primaryLabel: strings.actionSave,
      onPrimary: submitting || _name.text.trim().isEmpty
          ? null
          : () => _save(existing),
      secondaryLabel: existing == null ? null : strings.actionDelete,
      onSecondary: existing == null ? null : () => _delete(existing),
      isDirty: _dirty,
      isSubmitting: submitting,
      discardTitle: strings.confirmDiscardTitle,
      discardBody: strings.confirmDiscardBody,
      discardConfirmLabel: strings.actionDiscard,
      discardCancelLabel: strings.actionKeepEditing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _name,
            decoration: InputDecoration(labelText: strings.splitGroupNameLabel),
            onChanged: (_) => setState(() => _dirty = true),
          ),

          SectionHeader(
            label: strings.splitPickPeople,
            padding: const EdgeInsets.only(
              top: AlayaSpacing.xl,
              bottom: AlayaSpacing.xs,
            ),
          ),
          if (people.isEmpty)
            Text(
              strings.splitPickPeopleEmpty,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            )
          else
            Wrap(
              spacing: AlayaSpacing.xs,
              runSpacing: AlayaSpacing.xs,
              children: [
                for (final payee in people)
                  FilterChip(
                    label: Text(payee.name),
                    selected: _members.contains(payee.id),
                    onSelected: (_) => _toggle(payee.id),
                  ),
              ],
            ),

          if (_members.isNotEmpty) ...[
            SectionHeader(
              label: strings.splitDefaultShares,
              padding: const EdgeInsets.only(
                top: AlayaSpacing.xl,
                bottom: AlayaSpacing.xxs,
              ),
            ),
            Text(
              strings.splitDefaultSharesHelp,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
            const SizedBox(height: AlayaSpacing.sm),
            for (final payeeId in _members)
              _WeightRow(
                name: _nameOf(people, payeeId, strings),
                basisPoints: _weights[payeeId],
                onChanged: (value) => setState(() {
                  _dirty = true;
                  value == null
                      ? _weights.remove(payeeId)
                      : _weights[payeeId] = value;
                }),
              ),
            if (partial) ...[
              const SizedBox(height: AlayaSpacing.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: StatusChip(
                  label: strings.splitWeightsPartial,
                  tone: StatusTone.warning,
                ),
              ),
            ],
          ],

          if (existing != null) ...[
            SectionHeader(
              label: strings.splitArchived,
              padding: const EdgeInsets.only(
                top: AlayaSpacing.xl,
                bottom: AlayaSpacing.xxs,
              ),
            ),
            SwitchListTile(
              value: _isArchived,
              // Archiving is not deleting, and the subtitle is where that distinction becomes usable
              // rather than a rule in a document.
              title: Text(strings.splitArchiveLabel),
              subtitle: Text(
                strings.splitArchiveHelp,
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
              contentPadding: EdgeInsets.zero,
              onChanged: (value) => setState(() {
                _dirty = true;
                _isArchived = value;
              }),
            ),
          ],
        ],
      ),
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
}

/// One member's default share, entered as whole percent.
///
/// **Basis points are stored; percent is typed.** An integer keeps Law L1 intact — 33.33% has no
/// place in a `double` anywhere near money — and the conversion lives at this one boundary rather
/// than in every caller.
class _WeightRow extends StatelessWidget {
  const _WeightRow({
    required this.name,
    required this.basisPoints,
    required this.onChanged,
  });

  final String name;
  final int? basisPoints;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AlayaSpacing.sm),
      // A `Wrap`, not a `Row`: a name beside a fixed-width field overflows at 320dp with the text
      // scaler at 2.0, which is the gate every screen has to pass (Law U15).
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AlayaSpacing.sm,
        runSpacing: AlayaSpacing.xs,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              name,
              style: AlayaTypography.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 110,
            child: TextFormField(
              initialValue: basisPoints == null
                  ? ''
                  : (basisPoints! ~/ 100).toString(),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: strings.splitSharePercent,
                suffixText: '%',
              ),
              onChanged: (text) {
                final parsed = int.tryParse(text.trim());
                onChanged(parsed == null ? null : parsed * 100);
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

### `lib/features/split/presentation/screens/split_home_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/text/split_placeholder_names.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/features/split/presentation/sheets/name_placeholder_sheet.dart';
import 'package:alaya/features/split/presentation/sheets/settle_up_sheet.dart';
import 'package:alaya/features/split/presentation/sheets/split_share_sheet.dart';
import 'package:alaya/features/split/presentation/widgets/quick_split_card.dart';
import 'package:alaya/features/split/presentation/widgets/split_groups_list.dart';
import 'package:alaya/features/split/presentation/widgets/split_history_list.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// The whole split module, on one destination (ARCH_5 §3 archetype C).
///
/// ## Three tabs instead of seven routes
///
/// `/split/groups`, `/split/groups/:groupId` and `/split/groups/:groupId/settle` are gone. The groups
/// list is a tab; a group's balances and its settle-up plan are bottom sheets. **None of the three was an
/// editor** — each read something and offered actions — so each route bought a back arrow, an app bar
/// competing for a 320dp title, and somewhere for a user to end up without knowing how.
///
/// What remains a route is what genuinely earns one: the bill editor, and the group editor. Both are
/// forms with a discard guard, which is what `AlayaFormScaffold` and archetype B exist for.
///
/// ## Balances, History, Groups — in that order
///
/// **Balances first because it answers the question people open the app with**, and the quick splitter
/// sits at the top of it so dividing a bill is still zero taps from arriving. **History second** because
/// it is the only surface that remembers a split settled the same evening — a balance list is not a
/// record of what happened. **Groups last** because a group is a convenience for the other two, not a
/// thing anybody comes here to look at.
///
/// ## No `Scaffold`, no app bar, no FAB
///
/// `Routes.split` sits inside the drawer shell, which owns all three — and the first version of this
/// screen wrapped itself in a second `Scaffold`, stacking a bar with a back arrow under the real one on a
/// destination nobody navigates *into*. That is also why "Create a split" is a button in content: a FAB
/// belongs to the shell, and one hovering over the Groups tab would be the wrong action in the wrong
/// place.
///
/// **Every row that pairs text with an amount is a `Wrap`, not a `Row`.** An `AmountText` cannot shrink
/// below its own text, so `Row(Expanded(name), amount)` overflows the moment the figure is long and the
/// scaler is doubled — ₹1,23,456.78 at 2.0 overran 320dp by 215 pixels.
class SplitHomeScreen extends ConsumerWidget {
  /// Creates the screen.
  const SplitHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          // **A `TabBar` in the body rather than in an app bar**, because the app bar belongs to
          // `_ShellScaffold` and putting tabs there would show them on all eleven destinations.
          TabBar(
            tabs: [
              Tab(text: strings.splitTabBalances),
              Tab(text: strings.splitTabHistory),
              Tab(text: strings.splitTabGroups),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                const _BalancesTab(),
                // Every group and none — a split filed under no group is most of them, since the bill
                // screen makes a group optional.
                const SplitHistoryList(),
                const SplitGroupsList(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BalancesTab extends ConsumerWidget {
  const _BalancesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final balances = ref.watch(splitBalancesProvider);
    final self = ref.watch(splitSelfProvider).valueOrNull;

    return balances.when(
      // **The splitter still shows while balances load**, because it needs none of them. Hiding a
      // working calculator behind somebody else's query is the kind of coupling a skeleton makes easy and
      // nobody notices.
      loading: () => ListView(
        padding: const EdgeInsets.fromLTRB(
          AlayaSpacing.screenEdge,
          AlayaSpacing.md,
          AlayaSpacing.screenEdge,
          AlayaSpacing.xxxl,
        ),
        children: [
          const QuickSplitCard(),
          const SizedBox(height: AlayaSpacing.lg),
          AlayaListSkeleton(label: strings.loadingLabel),
        ],
      ),
      error: (error, stack) => ErrorState(
        title: strings.errorTitleGeneric,
        body: error.toString(),
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(splitBalancesProvider),
      ),
      data: (rows) => _BalancesBody(rows: rows, hasSelf: self != null),
    );
  }
}

class _BalancesBody extends ConsumerWidget {
  const _BalancesBody({required this.rows, required this.hasSelf});

  final List<SplitBalance> rows;

  /// Whether the app knows which payee the user is.
  final bool hasSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final totals = ref.watch(splitTotalsProvider).valueOrNull ?? const {};
    final ageing = ref.watch(splitAgeingProvider).valueOrNull ?? const [];
    final aged = {for (final debt in ageing) debt.balance.payeeId: debt};

    final owed = [
      for (final row in rows)
        if (row.theyOweMe) row,
    ];
    final owing = [
      for (final row in rows)
        if (row.iOweThem) row,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AlayaSpacing.screenEdge,
        AlayaSpacing.md,
        AlayaSpacing.screenEdge,
        AlayaSpacing.xxxl,
      ),
      children: [
        // **The question moved to onboarding.** `SplitSetupCard` used to sit here asking who the user is,
        // because nothing in this module works until `split.selfPayeeId` is set and the screens that
        // noticed pointed at a settings branch with an empty list of candidates. Step one of the first-run
        // flow asks it now, before Split is ever opened — so the common path never reaches the empty state
        // below, and this screen went back to being about balances.
        const QuickSplitCard(),

        const SizedBox(height: AlayaSpacing.sm),
        // Two buttons, not three: Groups is a tab now. A `Wrap` rather than `Expanded`s because at a
        // doubled text scale each label needs more than half the width, and a button's own row cannot
        // shrink its label.
        Wrap(
          spacing: AlayaSpacing.sm,
          runSpacing: AlayaSpacing.xs,
          children: [
            OutlinedButton.icon(
              onPressed: () => context.push(Routes.splitNew),
              icon: const Icon(
                Icons.call_split_outlined,
                size: AlayaIconSize.md,
              ),
              label: Text(strings.splitCreateSplit),
            ),
            OutlinedButton.icon(
              onPressed: rows.isEmpty
                  ? null
                  : () => SplitShareSheet.show(context),
              icon: const Icon(Icons.ios_share, size: AlayaIconSize.md),
              label: Text(strings.actionShare),
            ),
          ],
        ),

        if (rows.isEmpty) ...[
          const SizedBox(height: AlayaSpacing.xl),
          // **Two empty states, because they mean opposite things.** "Nothing outstanding" is success;
          // "the app does not know who you are" is a setup step that silently makes every balance
          // unanswerable — and the setup card above is already asking, so this one only reassures.
          if (hasSelf)
            EmptyState(
              title: strings.splitAllSettledTitle,
              body: strings.splitAllSettledBody,
              icon: Icons.check_circle_outline,
            )
          else
            EmptyState(
              title: strings.splitNoSelfTitle,
              body: strings.splitSelfPayeeUnset,
              icon: Icons.person_outline,
              // **Reachable again, and only for the person who skipped.** Onboarding's name step is
              // optional — archetype B makes the whole flow skippable — so somebody who declined needs
              // somewhere to answer later. That is what a settings branch is for, and it is one tap rather
              // than the four-screen chain this used to be.
              actionLabel: strings.settingsSplit,
              onAction: () => context.push(Routes.settingsSplit),
            ),
        ] else ...[
          for (final entry in totals.entries)
            Padding(
              padding: const EdgeInsets.only(top: AlayaSpacing.md),
              child: AlayaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TotalRow(
                      label: strings.splitOwedToYou,
                      amount: entry.value.owedToMe,
                    ),
                    const SizedBox(height: AlayaSpacing.xs),
                    _TotalRow(
                      label: strings.splitYouOwe,
                      amount: entry.value.iOwe,
                    ),
                  ],
                ),
              ),
            ),

          if (owed.isNotEmpty) ...[
            SectionHeader(
              label: strings.splitOwedToYou,
              padding: const EdgeInsets.only(
                top: AlayaSpacing.xl,
                bottom: AlayaSpacing.xs,
              ),
            ),
            for (final row in owed)
              _BalanceRow(balance: row, aged: aged[row.payeeId]),
          ],

          if (owing.isNotEmpty) ...[
            SectionHeader(
              label: strings.splitYouOwe,
              padding: const EdgeInsets.only(
                top: AlayaSpacing.xl,
                bottom: AlayaSpacing.xs,
              ),
            ),
            for (final row in owing)
              _BalanceRow(balance: row, aged: aged[row.payeeId]),
          ],

          // **The "tap a balance to settle up" hint is gone.** It was instructions for an affordance that
          // should not have needed any, and it sat where nobody scrolled to. Each row now carries its own
          // button, which is the thing the sentence was compensating for.
        ],
      ],
    );
  }
}

/// One side of the totals card: a label and a figure.
///
/// **Stacked rather than side by side.** Two totals in a `Row` of `Expanded`s each get half of 320dp, and
/// half of 320 does not hold "Owed to you" beside ₹1,23,456.78 at a doubled scale.
class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.amount});

  final String label;
  final Money amount;

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
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        // Through `AmountText`, and without a colour of its own: that widget has no `tone` parameter and
        // colours from `kind` deliberately. The label beside it already says which figure this is.
        AmountText(amount, showSign: false),
      ],
    );
  }
}

class _BalanceRow extends ConsumerWidget {
  const _BalanceRow({required this.balance, this.aged});

  final SplitBalance balance;

  /// Set when this debt is old enough to mention.
  final AgeingDebt? aged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final payee = ref.watch(splitPayeeProvider(balance.payeeId));
    final name = payee?.name ?? strings.splitUnknownPerson;
    final days = aged?.ageInDays;

    // **A row this app created, not somebody the user chose.** Saving a split writes a
    // `PayeeKind.splitPlaceholder` for anybody anonymous so the debt can exist at all; this is where
    // that gets fixed, because "Person 4 owes you ₹1,250" is a question asked at exactly the moment the
    // answer is known.
    //
    // Read from `kind` rather than by matching the name — a real contact called "Person 5" is not a
    // placeholder, and a placeholder renamed to "Ravi" stops being one because the *kind* changed.
    final provisional =
        payee != null && SplitPlaceholderNames.isPlaceholder(payee);

    void settle() => SettleUpSheet.show(
      context,
      payeeId: balance.payeeId,
      payeeName: name,
      outstanding: balance.outstanding,
      theyOweMe: balance.theyOweMe,
    );

    return AlayaCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.sm,
        vertical: AlayaSpacing.xs,
      ),
      // The whole card stays tappable — for anybody who has learnt it, it is the larger target. But it is
      // no longer the *only* way in: see the button below.
      onTap: settle,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AlayaSpacing.sm,
        runSpacing: AlayaSpacing.xs,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: provisional
                    // Muted and italic, exactly as the bill screen renders an unnamed slot, so the two
                    // places a placeholder appears look like the same thing.
                    ? AlayaTypography.body.copyWith(
                        color: semantic.muted,
                        fontStyle: FontStyle.italic,
                      )
                    : AlayaTypography.body,
              ),
              // **The action, spelled out, because "the row is tappable" was the only affordance and
              // nobody found it.** A card with no button, no icon and no chevron reads as a list item, and
              // the one sentence that said otherwise sat centred and muted *below* every row — off screen
              // the moment somebody had four balances. Recording a repayment is the reason this module
              // exists after the arithmetic, and it was the least visible thing on the screen.
              //
              // Its own button rather than a trailing chevron: a chevron says "there is more to read",
              // and this is a write.
              TextButton.icon(
                onPressed: settle,
                icon: const Icon(
                  Icons.handshake_outlined,
                  size: AlayaIconSize.sm,
                ),
                label: Text(
                  // Says which direction the money goes, because "Settle up" does not. Somebody looking at
                  // "You owe Ravi ₹1,250" wants to record that they *paid* him.
                  balance.theyOweMe
                      ? strings.splitRecordTheyPaid
                      : strings.splitRecordYouPaid,
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              if (provisional)
                // Its own button, so it does not fight the card's tap. Settling with somebody and naming
                // them are different intents, and a long-press would hide one of them.
                //
                // **`NamePlaceholderSheet`, not `PayeeSheet`.** A name field can only say "call this row
                // Ravi", and if Ravi already exists that leaves two of him — two balances, and settling
                // one leaves the other outstanding with nothing on screen to explain it. The sheet offers
                // the people you already have first, and a name field second.
                TextButton.icon(
                  onPressed: () =>
                      NamePlaceholderSheet.show(context, placeholder: payee),
                  icon: const Icon(
                    Icons.drive_file_rename_outline,
                    size: AlayaIconSize.sm,
                  ),
                  label: Text(strings.splitNameThisPerson),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              if (days != null) ...[
                const SizedBox(height: AlayaSpacing.xxs),
                // The sentence no competitor writes, and it costs nothing: the balance view already
                // carries the oldest contributing expense.
                StatusChip(
                  label: strings.splitOutstandingDays(days),
                  tone: StatusTone.warning,
                ),
              ],
            ],
          ),
          // Direction is carried by which section the row sits under — "Owed to you" or "You owe" —
          // rather than by a colour `AmountText` has no parameter for.
          AmountText(balance.outstanding, showSign: false),
        ],
      ),
    );
  }
}
```

### `lib/features/split/presentation/sheets/add_person_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';

/// Adds somebody you split bills with, and hands their id straight back.
///
/// ## Why the split module has its own instead of reusing `PayeeSheet`
///
/// **`PayeeSheet` defaults to `PayeeKind.merchant`**, which is right for the expense editor — most
/// payees are shops — and wrong here in a way that was invisible and total. Every person added from a
/// split screen was filed as a merchant, `splitPeopleProvider` filters to `person`, so they never
/// appeared. That emptied the name picker, emptied the "which person is you" list in Settings, left
/// `split.selfPayeeId` unsettable, and therefore made **saving a split impossible** — one wrong default
/// four steps upstream of the symptom.
///
/// **It also returns the payee it created.** `PayeeSheet.show` returns `Future<void>`, so the caller
/// had to find the new person by re-reading `splitPeopleProvider` after the sheet closed and diffing
/// against what was there before. That read happens before drift's stream has ticked, so the diff was
/// usually empty and the new person was silently not selected — the "it creates but does not change
/// Person 1" symptom. Returning the id removes the race rather than timing around it.
class AddPersonSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const AddPersonSheet({super.key});

  /// Opens the sheet, resolving to the new payee's id or null when dismissed.
  static Future<String?> show(BuildContext context) =>
      AlayaBottomSheet.show<String>(
        context: context,
        builder: (context) => const AddPersonSheet(),
      );

  @override
  ConsumerState<AddPersonSheet> createState() => _AddPersonSheetState();
}

class _AddPersonSheetState extends ConsumerState<AddPersonSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final strings = AlayaStrings.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = strings.splitAddPersonNameRequired);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final phone = _phone.text.trim();
    final saved = await ref
        .read(payeeRepositoryProvider)
        .save(
          Payee(
            id: ref.read(uidGeneratorProvider).generate(),
            name: name,
            normalizedName: ref.read(normalizerProvider).normalize(name),
            // **`person`, and that is the entire point of this sheet.** A merchant here is invisible to
            // every split screen, which is what made the module unusable.
            kind: PayeeKind.person,
            phone: phone.isEmpty ? null : phone,
          ),
        );
    if (!mounted) return;

    final payee = saved.valueOrNull;
    if (payee == null) {
      setState(() {
        _saving = false;
        // The repository's own sentence — a duplicate name says so, which "something went wrong" does
        // not (Law U9).
        _error = saved.failureOrNull?.message ?? strings.errorBodyGeneric;
      });
      return;
    }
    Navigator.of(context).pop(payee.id);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(strings.splitAddPersonTitle, style: AlayaTypography.sectionHeader),

        const SizedBox(height: AlayaSpacing.md),
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: strings.payeeNameLabel,
            errorText: _error,
          ),
          onSubmitted: (_) => _save(),
        ),

        const SizedBox(height: AlayaSpacing.md),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          // `payeePhoneOptionalLabel`, the key `PayeeSheet` already uses — it reads "Phone (optional)",
          // which `PayeeSheet`'s own comment records as the fix for a two-field sheet feeling like a
          // form. Inventing a second key for the same field would give the same control two names.
          decoration: InputDecoration(
            labelText: strings.payeePhoneOptionalLabel,
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: AlayaSpacing.xxs),
        Text(
          // Says what the field buys, which the label's "(optional)" does not. Two people really are
          // called the same thing, and the phone is the only field that tells them apart in a picker.
          strings.splitAddPersonPhoneHelp,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),

        const SizedBox(height: AlayaSpacing.lg),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(strings.actionSave),
        ),
      ],
    );
  }
}
```

### `lib/features/split/presentation/sheets/name_picker_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/split/presentation/sheets/add_person_sheet.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';

/// Puts a name to one participant.
///
/// **Two people really are called the same thing**, and a list showing "Priya" twice is a coin toss.
/// `payees.phone` is the only field that reliably tells them apart, so it is shown **exactly where a
/// name repeats and nowhere else** — a phone beside every row is noise on the ninety-nine that are
/// unambiguous, and noise is what stops people reading a list at all.
///
/// **Names already used on this split are shown and disabled rather than hidden.** Somebody looking
/// for Ravi and not finding him would add a second Ravi; seeing him greyed with "already on this
/// split" answers the question instead of raising a new one.
///
/// **Adding somebody goes through [AddPersonSheet], not `PayeeSheet`.** The shared sheet defaults to
/// `PayeeKind.merchant` and returns `Future<void>`, which produced two failures at once: the new
/// person was filed as a shop and so never appeared in this list, and the caller had to find them by
/// re-reading a stream that had not ticked yet. `AddPersonSheet` creates a `person` and hands the id
/// straight back, so both the kind and the race are gone rather than worked around.
class NamePickerSheet extends ConsumerWidget {
  /// Creates the sheet.
  const NamePickerSheet({
    required this.people,
    required this.selected,
    required this.taken,
    super.key,
  });

  /// Everybody who could be named.
  final List<Payee> people;

  /// Who this slot currently holds, if anybody.
  final String? selected;

  /// Payee ids already used by the other slots.
  final Set<String> taken;

  /// Opens the sheet, resolving to the chosen payee id or null when dismissed.
  static Future<String?> show(
    BuildContext context, {
    required List<Payee> people,
    required String? selected,
    required Set<String> taken,
  }) => AlayaBottomSheet.show<String>(
    context: context,
    builder: (context) =>
        NamePickerSheet(people: people, selected: selected, taken: taken),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    // Counted once rather than per row: a name clashes when more than one payee carries it, and asking
    // that question inside the loop would be quadratic on a list somebody might have hundreds of.
    final byName = <String, int>{};
    for (final payee in people) {
      byName[payee.name] = (byName[payee.name] ?? 0) + 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(strings.splitPickName, style: AlayaTypography.sectionHeader),
        const SizedBox(height: AlayaSpacing.sm),

        if (people.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.md),
            child: Text(
              strings.splitPickPeopleEmpty,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
          )
        else
          ConstrainedBox(
            // Bounded, because a sheet that grows with the payee list eventually covers the screen and
            // loses its own confirm affordance.
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: people.length,
              itemBuilder: (context, index) {
                final payee = people[index];
                final used = taken.contains(payee.id);
                final phone = payee.phone?.trim();
                final ambiguous = (byName[payee.name] ?? 0) > 1;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: !used,
                  selected: payee.id == selected,
                  leading: Icon(
                    payee.id == selected
                        ? Icons.check_circle
                        : Icons.person_outline,
                    size: AlayaIconSize.md,
                    color: used ? semantic.muted : null,
                  ),
                  title: Text(payee.name),
                  subtitle: used
                      ? Text(strings.splitAlreadyOnSplit)
                      : (ambiguous && phone != null && phone.isNotEmpty
                            ? Text(phone)
                            : null),
                  onTap: used
                      ? null
                      : () => Navigator.of(context).pop(payee.id),
                );
              },
            ),
          ),

        const SizedBox(height: AlayaSpacing.sm),
        OutlinedButton.icon(
          onPressed: () => _create(context),
          icon: const Icon(Icons.person_add_outlined, size: AlayaIconSize.md),
          label: Text(strings.splitNewPerson),
        ),
      ],
    );
  }

  /// Adds somebody and chooses them in one gesture.
  ///
  /// The id comes back from the sheet, so there is nothing to look up and nothing to wait for. The
  /// previous version diffed `splitPeopleProvider` before and after, which read the stream before it
  /// had emitted and so usually found nobody new.
  Future<void> _create(BuildContext context) async {
    final created = await AddPersonSheet.show(context);
    if (!context.mounted) return;
    Navigator.of(context).pop(created);
  }
}
```

### `lib/features/split/presentation/sheets/name_placeholder_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/split/providers/split_merge_provider.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';

/// Who an unnamed split participant turned out to be.
///
/// ## Two answers, and only one of them is a rename
///
/// **"Somebody you know" and "somebody new" are different operations**, which is the bug this sheet fixes.
/// The old affordance opened `PayeeSheet` — a name field — so the only thing you could say was *"call this
/// row Ravi"*. If Ravi already existed you now had two Ravis: two balances, and settling one left the other
/// outstanding with nothing on screen to explain it.
///
/// Picking an existing person **merges**: every share, settlement, membership and paid-by reference moves to
/// them and the placeholder is retired, in one transaction. Typing a name **renames and promotes** —
/// `kind: person`, which is what takes the row out of the placeholder set and into every list a contact
/// belongs in.
///
/// ## The list comes first
///
/// A name field first would invite typing "Ravi" while Ravi is three rows below, which is exactly the
/// duplicate this exists to prevent. The people you already have are the likelier answer at a table you
/// split a bill at, so they are what you see without scrolling.
class NamePlaceholderSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const NamePlaceholderSheet({required this.placeholder, super.key});

  /// The row this app created because nobody had been named.
  final Payee placeholder;

  /// Opens the sheet, resolving true when the placeholder was resolved.
  static Future<bool> show(
    BuildContext context, {
    required Payee placeholder,
  }) async =>
      await AlayaBottomSheet.show<bool>(
        context: context,
        builder: (context) => NamePlaceholderSheet(placeholder: placeholder),
      ) ??
      false;

  @override
  ConsumerState<NamePlaceholderSheet> createState() =>
      _NamePlaceholderSheetState();
}

class _NamePlaceholderSheetState extends ConsumerState<NamePlaceholderSheet> {
  final _name = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _merge(Payee into) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final notifier = ref.read(splitNamePlaceholderProvider.notifier);
    final ok = await notifier.mergeInto(
      placeholderPayeeId: widget.placeholder.id,
      payeeId: into.id,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        // The repository's own sentence — "that person has been deleted, restore them first" is actionable
        // where "something went wrong" is not (Law U9).
        _error =
            notifier.lastError ?? AlayaStrings.of(context).errorBodyGeneric;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  Future<void> _rename() async {
    final strings = AlayaStrings.of(context);
    if (_name.text.trim().isEmpty) {
      setState(() => _error = strings.splitNameRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final notifier = ref.read(splitNamePlaceholderProvider.notifier);
    final ok = await notifier.rename(
      placeholder: widget.placeholder,
      name: _name.text,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = notifier.lastError ?? strings.errorBodyGeneric;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    // `splitPeopleProvider`, so no other placeholder is offered. Merging one placeholder into another would
    // resolve nothing and retire a row somebody still owes money to.
    final people =
        ref.watch(splitPeopleProvider).valueOrNull ?? const <Payee>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(strings.splitNameThisPerson, style: AlayaTypography.sectionHeader),
        const SizedBox(height: AlayaSpacing.xxs),
        Text(
          strings.splitNamePlaceholderBody(widget.placeholder.name),
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),

        if (people.isNotEmpty) ...[
          const SizedBox(height: AlayaSpacing.lg),
          Text(
            strings.splitNameSomebodyKnown,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
          const SizedBox(height: AlayaSpacing.xs),
          ConstrainedBox(
            // Bounded, because a sheet that grows with the payee list eventually covers the name field
            // below it — and that field is the other half of the question.
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: people.length,
              itemBuilder: (context, index) {
                final payee = people[index];
                final phone = payee.phone?.trim();
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: !_busy,
                  leading: Icon(
                    Icons.person_outline,
                    size: AlayaIconSize.md,
                    color: semantic.muted,
                  ),
                  title: Text(payee.name),
                  subtitle: phone == null || phone.isEmpty ? null : Text(phone),
                  onTap: _busy ? null : () => _merge(payee),
                );
              },
            ),
          ),
          const SizedBox(height: AlayaSpacing.md),
          Row(
            children: [
              Expanded(child: Divider(color: semantic.muted)),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AlayaSpacing.sm,
                ),
                child: Text(
                  strings.splitNameOr,
                  style: AlayaTypography.caption.copyWith(
                    color: semantic.muted,
                  ),
                ),
              ),
              Expanded(child: Divider(color: semantic.muted)),
            ],
          ),
        ],

        const SizedBox(height: AlayaSpacing.md),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: strings.splitNameSomebodyNew,
            errorText: _error,
          ),
          onSubmitted: (_) => _rename(),
        ),
        const SizedBox(height: AlayaSpacing.md),
        FilledButton(
          onPressed: _busy ? null : _rename,
          child: Text(strings.actionSave),
        ),
      ],
    );
  }
}
```

### `lib/features/split/presentation/sheets/save_as_group_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/features/split/providers/split_group_editor_provider.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';

/// One participant, as the bill screen knows them at the moment the group is made.
typedef GroupCandidate = ({
  String payeeId,
  String name,
  int? weightBasisPoints,
});

/// Turns the people on the bill in front of you into a reusable group.
///
/// **The answer to "it is very hard to create groups".** Before this, making one meant leaving the
/// split, finding the groups screen, tapping new, naming it, and picking the same four people you had
/// just finished picking. Nobody does that twice, so nobody has groups, so every future dinner starts
/// from an empty screen — and the feature that was supposed to save time never gets used.
///
/// Here the group is made *from* the split that already exists. The people are chosen, the weights are
/// chosen, the only thing missing is a name.
///
/// **Weights come along when the split was weighted.** A 40/30/30 rent split saved as "Flatmates"
/// prefills 40/30/30 next month, which is the entire point of a group carrying defaults — and it is
/// the one thing that would be tedious to reconstruct by hand.
class SaveAsGroupSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const SaveAsGroupSheet({required this.candidates, super.key});

  /// Who will be in the group, in the order they appear on the bill.
  final List<GroupCandidate> candidates;

  /// Opens the sheet, resolving to the new group's id, or null when dismissed.
  static Future<String?> show(
    BuildContext context, {
    required List<GroupCandidate> candidates,
  }) => AlayaBottomSheet.show<String>(
    context: context,
    builder: (context) => SaveAsGroupSheet(candidates: candidates),
  );

  @override
  ConsumerState<SaveAsGroupSheet> createState() => _SaveAsGroupSheetState();
}

class _SaveAsGroupSheetState extends ConsumerState<SaveAsGroupSheet> {
  final _name = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Whether any candidate carries a weight.
  ///
  /// All or none, matching what `SplitGroup.defaultWeightsByPayee` will accept: a partial set prefills
  /// nothing, because treating an unweighted member as weightless would invent an instruction nobody
  /// gave.
  bool get _weighted =>
      widget.candidates.every((c) => c.weightBasisPoints != null);

  Future<void> _save() async {
    final strings = AlayaStrings.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = strings.splitGroupNameRequired);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final notifier = ref.read(splitGroupEditorProvider.notifier);
    final ok = await notifier.save(
      name: name,
      defaultSplitMethod: _weighted ? SplitMethod.shares : SplitMethod.equal,
      members: [
        for (final c in widget.candidates)
          (
            payeeId: c.payeeId,
            weightBasisPoints: _weighted ? c.weightBasisPoints : null,
            memberId: null,
          ),
      ],
    );
    if (!mounted) return;

    if (!ok) {
      setState(() {
        _saving = false;
        // The repository's own sentence — "A group named "Flatmates" already exists" is actionable
        // where "something went wrong" is not (Law U9).
        _error = notifier.lastError ?? strings.errorBodyGeneric;
      });
      return;
    }

    // The id is not returned by the notifier, so the caller re-reads the group list and selects the
    // one that appeared. Popping `true` would make the caller guess; popping the name lets it match.
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(strings.splitSaveAsGroup, style: AlayaTypography.sectionHeader),
        const SizedBox(height: AlayaSpacing.xxs),
        Text(
          strings.splitSaveAsGroupHelp,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),

        const SizedBox(height: AlayaSpacing.md),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: strings.splitGroupNameLabel,
            hintText: strings.splitSaveAsGroupHint,
            errorText: _error,
          ),
          onSubmitted: (_) => _save(),
        ),

        const SizedBox(height: AlayaSpacing.md),
        // Who is going in, shown rather than counted. "4 people" is a number to trust; four names are
        // a thing to check, and this is the last moment before the group exists.
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final candidate in widget.candidates)
              Chip(
                label: Text(
                  _weighted && candidate.weightBasisPoints != null
                      ? strings.splitMemberWithWeight(
                          candidate.name,
                          candidate.weightBasisPoints! ~/ 100,
                        )
                      : candidate.name,
                ),
              ),
          ],
        ),

        if (_weighted) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Text(
            // Says what the group will do next time, which is the reason to make one.
            strings.splitSaveAsGroupWeights,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
        ],

        const SizedBox(height: AlayaSpacing.lg),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(strings.actionSave),
        ),
      ],
    );
  }
}
```

### `lib/features/split/presentation/sheets/settle_up_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/core/time/date_key_labels.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/features/split/providers/settle_up_provider.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/widgets/account_picker.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Records money changing hands to settle a debt (ARCH_5 §3 archetype A).
///
/// **The account is required, and that is the module's central claim made concrete.** A settlement you
/// are part of moved your money, so it writes a real `transactions` row in the same database
/// transaction as the settlement itself — the deposit lands in an account you choose and is spendable
/// from that instant, with no separate split wallet to reconcile. Splitwise's "settle up" is a
/// bookkeeping marker it cannot back with anything; this one has to name where the money went.
///
/// **The amount defaults to the whole balance and stays editable**, which is what makes partial
/// settlement work: "keep adding as they keep paying" needs no special mode, only more rows, because
/// what remains outstanding is derived rather than decremented (Law L3).
///
/// **The ledger row now says what it was for.** A settlement writes an ordinary deposit or withdrawal, and it
/// used to carry whatever note the user typed — which was nothing, because this sheet has no note field. So a
/// month later the ledger held an unexplained ₹1,850 arriving in a bank account, and the only way to find out
/// what it was involved opening the split module and matching amounts by eye. See [_noteFor].
class SettleUpSheet extends ConsumerStatefulWidget {
  /// Settles with [payeeId] for [outstanding].
  const SettleUpSheet({
    required this.payeeId,
    required this.payeeName,
    required this.outstanding,
    required this.theyOweMe,
    this.groupId,
    super.key,
  });

  /// The counterparty.
  final String payeeId;

  /// Their display name, resolved by the caller.
  final String payeeName;

  /// What is outstanding, without its direction.
  final Money outstanding;

  /// Whether they owe the user, rather than the other way round.
  final bool theyOweMe;

  /// The group this settles within, or null for a one-off debt.
  final String? groupId;

  /// Opens the sheet, resolving to true when a settlement was recorded.
  static Future<bool?> show(
    BuildContext context, {
    required String payeeId,
    required String payeeName,
    required Money outstanding,
    required bool theyOweMe,
    String? groupId,
  }) => AlayaBottomSheet.show<bool>(
    context: context,
    builder: (context) => SettleUpSheet(
      payeeId: payeeId,
      payeeName: payeeName,
      outstanding: outstanding,
      theyOweMe: theyOweMe,
      groupId: groupId,
    ),
  );

  @override
  ConsumerState<SettleUpSheet> createState() => _SettleUpSheetState();
}

class _SettleUpSheetState extends ConsumerState<SettleUpSheet> {
  late Money? _amount = widget.outstanding;
  String? _error;
  String? _accountId;
  String? _paymentMethodId;
  DateKey? _on;
  bool _submitting = false;

  /// What the ledger row will say.
  ///
  /// **Composed here because this is the only layer that has both halves.** The words need the ARB, which needs
  /// a `BuildContext`; the counterparty's name is already on this widget. `SettleUp` has neither, and
  /// `SettlementService` has payee *ids* and a group repository rather than names — so anything either of them
  /// produced would be an id or a placeholder.
  ///
  /// **The direction is stated in words, not implied by a sign.** A ledger shows a deposit and a withdrawal
  /// differently already, but "Ravi paid you back" and "You paid Ravi back" are the sentences somebody scanning
  /// a month of transactions actually reads, and they answer the question the amount cannot.
  ///
  /// **The group is named when there is one**, because *"Ravi paid you back — Flatmates"* separates the rent
  /// from the dinner without opening anything. It is read from the group already loaded for this module rather
  /// than fetched: `splitAllGroupsProvider` is watched by every split screen, so this costs no query.
  ///
  /// A stored sentence freezes in the language it was written in — switch to Hindi next year and old notes stay
  /// English. Accepted deliberately: the alternative is a note with no words, and an unreadable ledger row is
  /// the thing this exists to fix.
  String _noteFor(AlayaStrings strings) {
    final group = widget.groupId == null
        ? null
        : ref.read(splitGroupProvider(widget.groupId!)).valueOrNull?.name;

    if (group == null || group.trim().isEmpty) {
      return widget.theyOweMe
          ? strings.splitSettleNoteFrom(widget.payeeName)
          : strings.splitSettleNoteTo(widget.payeeName);
    }
    return widget.theyOweMe
        ? strings.splitSettleNoteFromIn(widget.payeeName, group)
        : strings.splitSettleNoteToIn(widget.payeeName, group);
  }

  Future<void> _settle() async {
    final strings = AlayaStrings.of(context);
    final amount = _amount;
    final accountId = _accountId;
    if (amount == null || accountId == null) return;

    setState(() => _submitting = true);
    final result = await ref
        .read(settleUpProvider.notifier)
        .settle(
          payeeId: widget.payeeId,
          theyOweMe: widget.theyOweMe,
          amount: amount,
          accountId: accountId,
          groupId: widget.groupId,
          paymentMethodId: _paymentMethodId,
          note: _noteFor(strings),
          on: _on,
        );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (!result) {
      // The service's own sentence. "Choose which person is you" and "that account is in USD, not INR"
      // are different problems with different remedies, and collapsing them into one message is what
      // makes a sheet impossible to get past (Law U9).
      final why = ref.read(settleUpProvider.notifier).lastError;
      setState(() => _error = why ?? strings.errorBodyGeneric);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final digits = ref.watch(splitDecimalDigitsProvider).valueOrNull ?? 2;
    final accounts =
        ref.watch(splitAccountsProvider).valueOrNull ?? const <Account>[];
    final methods =
        ref.watch(splitPaymentMethodsProvider).valueOrNull ??
        const <PaymentMethod>[];

    Account? accountFor(String? id) {
      for (final account in accounts) {
        if (account.id == id) return account;
      }
      return null;
    }

    final over = _amount != null && _amount! > widget.outstanding;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.theyOweMe
              ? strings.splitSettleFrom(widget.payeeName)
              : strings.splitSettleTo(widget.payeeName),
          style: AlayaTypography.sectionHeader,
        ),
        const SizedBox(height: AlayaSpacing.xxs),
        // A `Wrap`, not a `Row`: a label beside an amount is the shape that overflows at 320dp with the text
        // scaler doubled, and an `AmountText` cannot shrink below its own text (Law U15).
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AlayaSpacing.xs,
          children: [
            Text(
              strings.splitOutstandingLabel,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
            AmountText(
              widget.outstanding,
              size: AmountSize.small,
              showSign: false,
              decimalDigits: digits,
            ),
          ],
        ),

        const SizedBox(height: AlayaSpacing.lg),
        AmountField(
          currencyCode: widget.outstanding.currencyCode,
          decimalDigits: digits,
          label: strings.splitSettleAmount,
          initialValue: _amount,
          onChanged: (value) => setState(() => _amount = value),
        ),
        if (over) ...[
          const SizedBox(height: AlayaSpacing.xxs),
          Text(
            // **Warned, not blocked.** Paying more than the balance is a real thing to do — rounding up,
            // or covering something not yet entered — and the extra simply flips the balance the other
            // way, which the ledger represents perfectly well. Refusing it would be inventing a rule
            // the data does not have.
            strings.splitSettleOverpay,
            style: AlayaTypography.caption.copyWith(color: semantic.warning),
          ),
        ],

        SectionHeader(
          label: widget.theyOweMe
              ? strings.splitSettleIntoAccount
              : strings.splitSettleFromAccount,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.lg,
            bottom: AlayaSpacing.xs,
          ),
        ),
        AccountPicker(
          accounts: accounts,
          selected: accountFor(_accountId),
          label: strings.labelAccount,
          hint: strings.hintSelectAccount,
          onChanged: (account) => setState(() => _accountId = account.id),
        ),

        const SizedBox(height: AlayaSpacing.md),
        DropdownButtonFormField<String>(
          key: ValueKey(_paymentMethodId),
          initialValue: _paymentMethodId,
          isExpanded: true,
          decoration: InputDecoration(labelText: strings.labelPaymentMethod),
          items: [
            for (final method in methods)
              DropdownMenuItem(value: method.id, child: Text(method.name)),
          ],
          onChanged: (id) => setState(() => _paymentMethodId = id),
        ),

        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: _on ?? ref.read(splitTodayProvider),
          label: strings.labelDate,
          formatted: (date) => date.fullLabel,
          onChanged: (date) => setState(() => _on = date),
        ),

        if (_error != null) ...[
          const SizedBox(height: AlayaSpacing.md),
          Text(
            _error!,
            style: AlayaTypography.caption.copyWith(color: semantic.danger),
          ),
        ],

        const SizedBox(height: AlayaSpacing.lg),
        FilledButton(
          onPressed: _submitting || _amount == null || _accountId == null
              ? null
              : _settle,
          child: Text(strings.splitSettleAction),
        ),
      ],
    );
  }
}
```

### `lib/features/split/presentation/sheets/split_expense_detail_sheet.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/time/date_key_labels.dart';
import 'package:alaya/domain/entities/split_expense.dart';
import 'package:alaya/features/split/providers/split_expense_actions.dart';
import 'package:alaya/features/split/providers/split_history_provider.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// What a split actually was: who paid, who owed what, and how it was decided.
///
/// **History was a list of amounts you could not open.** It said a bill happened and what it came to, and
/// nothing about who covered it, how it divided, or what anybody's share was — so the one screen that
/// remembers a split settled the same evening could not answer the question somebody opens it with.
///
/// **Both the resolved amount and the input that produced it are shown**, because the schema stores both
/// for exactly this. A 40/30/30 split reopens as 40/30/30 rather than as three amounts the reader has to
/// reverse-engineer — and where a share carries an extra, the sentence separates it: *"₹1,050 share + ₹800
/// just for them"*, because a total nobody can decompose is one they argue with.
class SplitExpenseDetailSheet extends ConsumerWidget {
  /// Creates the sheet.
  const SplitExpenseDetailSheet({required this.expenseId, super.key});

  /// The split being shown.
  final String expenseId;

  /// Opens the sheet for [expenseId].
  static Future<void> show(BuildContext context, {required String expenseId}) =>
      AlayaBottomSheet.show<void>(
        context: context,
        builder: (context) => SplitExpenseDetailSheet(expenseId: expenseId),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final expense = ref.watch(splitExpenseProvider(expenseId));

    return expense.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AlayaSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => ErrorState(
        title: strings.errorTitleGeneric,
        body: error.toString(),
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(splitExpenseProvider(expenseId)),
      ),
      data: (found) => found == null
          ? ErrorState(
              title: strings.errorTitleNotFound,
              body: strings.errorBodyNotFound,
            )
          : _Body(expense: found),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.expense});

  final SplitExpense expense;

  static String _methodLabel(AlayaStrings strings, SplitMethod method) =>
      switch (method) {
        SplitMethod.equal => strings.splitMethodEqual,
        SplitMethod.shares => strings.splitMethodShares,
        SplitMethod.percent => strings.splitMethodPercent,
        SplitMethod.exactAmounts => strings.splitMethodExact,
        SplitMethod.perLine => strings.splitMethodPerLine,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final digits = ref.watch(splitDecimalDigitsProvider).valueOrNull ?? 2;
    final self = ref.watch(splitSelfProvider).valueOrNull;
    final payer =
        ref.watch(splitPayeeNameProvider(expense.paidByPayeeId)) ??
        strings.splitUnknownPerson;

    final title = expense.title?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title == null || title.isEmpty ? strings.splitBillAction : title,
          style: AlayaTypography.sectionHeader,
        ),
        const SizedBox(height: AlayaSpacing.xxs),
        Text(
          expense.dateKey.fullLabel,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),

        const SizedBox(height: AlayaSpacing.md),
        _Line(
          label: strings.splitDetailTotal,
          trailing: AmountText(
            expense.total,
            showSign: false,
            decimalDigits: digits,
          ),
        ),
        _Line(
          label: strings.splitDetailPaidBy,
          // **The fact the history list could not show.** Whether you fronted the money or somebody else
          // did decides which direction every share below points, and it is the first thing anybody
          // reopening a split wants to check.
          value: expense.paidByPayeeId == self ? strings.splitPaidByYou : payer,
        ),
        _Line(
          label: strings.splitDetailMethod,
          value: _methodLabel(strings, expense.splitMethod),
        ),
        if (expense.place case final place? when place.trim().isNotEmpty)
          _Line(label: strings.splitDetailPlace, value: place),
        if (expense.occasion case final occasion?
            when occasion.trim().isNotEmpty)
          _Line(label: strings.splitDetailOccasion, value: occasion),

        SectionHeader(
          label: strings.splitBillTheSplit,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.lg,
            bottom: AlayaSpacing.xs,
          ),
        ),
        for (final share in expense.shares)
          _ShareRow(share: share, total: expense.total, digits: digits),

        if (!expense.isFullyAllocated) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            // Reported, never absorbed — the same rule the editor follows. Rounding a shortfall onto
            // somebody charges them for a discrepancy nobody told them about.
            child: StatusChip(
              label: expense.unallocated.isNegative
                  ? strings.splitOverAllocated
                  : strings.splitUnallocated,
              tone: StatusTone.warning,
              trailing: AmountText(
                expense.unallocated.abs(),
                size: AmountSize.small,
                showSign: false,
                decimalDigits: digits,
              ),
            ),
          ),
        ],

        const SizedBox(height: AlayaSpacing.lg),
        Wrap(
          spacing: AlayaSpacing.sm,
          runSpacing: AlayaSpacing.xs,
          children: [
            FilledButton.tonalIcon(
              // **Editing reopens the bill screen with this split loaded**, and saving replaces rather than
              // duplicates: `SplitExpenseService.record` has taken an `id` since it was written, and no
              // screen ever passed one. Nothing new was needed underneath.
              onPressed: () {
                Navigator.of(context).pop();
                context.push(Routes.splitNew, extra: expense.id);
              },
              icon: const Icon(Icons.edit_outlined, size: AlayaIconSize.md),
              label: Text(strings.actionEdit),
            ),
            OutlinedButton.icon(
              onPressed: () => _delete(context, ref, strings),
              icon: const Icon(Icons.delete_outline, size: AlayaIconSize.md),
              label: Text(strings.actionDelete),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.splitDeleteConfirmTitle,
      // **Says what survives.** Deleting a split is a statement about who owed what, not about whether the
      // payment happened — any linked transaction stays in the ledger, because the money did move.
      body: strings.splitDeleteConfirmBody,
      confirmLabel: strings.actionDelete,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final ok = await ref
        .read(splitExpenseActionsProvider.notifier)
        .remove(expense.id);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    if (!context.mounted) return;
    ok
        ? showResultSnack(context, message: strings.splitDeleted)
        : showFailureSnack(context, message: strings.errorBodyGeneric);
  }
}

/// One label-and-value line.
class _Line extends StatelessWidget {
  const _Line({required this.label, this.value, this.trailing});

  final String label;
  final String? value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Padding(
      padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
      // A `Wrap`, not a `Row`: a label beside a long value or an amount is the shape that overflows at
      // 320dp with the scaler doubled (Law U15).
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AlayaSpacing.sm,
        runSpacing: AlayaSpacing.xxs,
        children: [
          Text(
            label,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
          trailing ?? Text(value ?? '', style: AlayaTypography.body),
        ],
      ),
    );
  }
}

/// One participant's share, with the input that produced it.
class _ShareRow extends ConsumerWidget {
  const _ShareRow({
    required this.share,
    required this.total,
    required this.digits,
  });

  final SplitShare share;
  final Money total;
  final int digits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final self = ref.watch(splitSelfProvider).valueOrNull;
    final name = share.payeeId == self
        ? strings.splitPaidByYou
        : ref.watch(splitPayeeNameProvider(share.payeeId)) ??
              strings.splitUnknownPerson;

    // **How it was decided, not just what it came to.** The schema stores the input beside the resolved
    // amount for this: a 40% share reopens as 40%, and an extra says it is an extra rather than hiding
    // inside a larger figure.
    final how = switch (share.inputKind) {
      ShareInputKind.equal => null,
      ShareInputKind.percent => strings.splitSharePercentOf(
        (share.inputValue ?? 0) / 100,
      ),
      ShareInputKind.shares => strings.splitShareWeightOf(
        share.inputValue ?? 1,
      ),
      ShareInputKind.exact => null,
      ShareInputKind.extra => strings.splitShareIsExtra,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AlayaSpacing.sm,
        runSpacing: AlayaSpacing.xxs,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: AlayaTypography.body),
              if (how != null)
                Text(
                  how,
                  style: AlayaTypography.caption.copyWith(
                    color: semantic.muted,
                  ),
                ),
            ],
          ),
          AmountText(share.amount, showSign: false, decimalDigits: digits),
        ],
      ),
    );
  }
}
```

### `lib/features/split/presentation/sheets/split_group_detail_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/features/split/presentation/sheets/settle_up_sheet.dart';
import 'package:alaya/features/split/presentation/sheets/split_settle_plan_sheet.dart';
import 'package:alaya/features/split/presentation/sheets/split_share_sheet.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// One group: who owes what within it, and what to do about it.
///
/// **Was `/split/groups/:groupId`, the second level of a stack behind a tab.** Nothing on it is an
/// editor — it reads balances and offers three actions — so a route bought a back arrow, an app bar with
/// three competing targets, and somewhere for a user to end up without knowing how.
///
/// **Balances and actions, not balances and a feed.** The screen this replaces also rendered the group's
/// activity, which the History tab now shows for every group at once. Duplicating it here made the sheet
/// long enough to need scrolling past the actions, which are the reason somebody opened it.
///
/// Group balances carry no ageing, deliberately. Ageing is a property of a debt with a *person*, and a
/// group-scoped day count would report the same debt twice for somebody you owe through two groups.
///
/// **Settling is the emphasised action.** Share and Edit are things you do *to* a group; settling is why
/// you looked.
class SplitGroupDetailSheet extends ConsumerWidget {
  /// Creates the sheet.
  const SplitGroupDetailSheet({required this.groupId, super.key});

  /// The group being shown.
  final String groupId;

  /// Opens the sheet for [groupId].
  static Future<void> show(BuildContext context, {required String groupId}) =>
      AlayaBottomSheet.show<void>(
        context: context,
        builder: (context) => SplitGroupDetailSheet(groupId: groupId),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final group = ref.watch(splitGroupProvider(groupId));
    final balances =
        ref.watch(splitGroupBalancesProvider(groupId)).valueOrNull ??
        const <SplitBalance>[];

    final found = group.valueOrNull;
    if (group.hasError) {
      return ErrorState(
        title: strings.errorTitleGeneric,
        body: group.error.toString(),
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(splitGroupProvider(groupId)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          found?.name ?? strings.splitGroupsTitle,
          style: AlayaTypography.sectionHeader,
        ),
        if (found != null) ...[
          const SizedBox(height: AlayaSpacing.xxs),
          Text(
            strings.splitPerPersonCount(found.members.length),
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
        ],

        const SizedBox(height: AlayaSpacing.md),
        if (balances.isEmpty)
          Text(
            // Settled is a real state and worth saying plainly, rather than showing an empty area that
            // reads as a sheet which failed to load half of itself.
            strings.splitAllSettledTitle,
            style: AlayaTypography.body.copyWith(color: semantic.success),
          )
        else ...[
          SectionHeader(
            label: strings.splitBalancesHeader,
            padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
          ),
          for (final balance in balances)
            _GroupBalanceRow(balance: balance, groupId: groupId),
        ],

        const SizedBox(height: AlayaSpacing.lg),
        FilledButton.icon(
          // **Closed before the plan opens.** Two stacked bottom sheets leave somebody dragging one to
          // reveal another, and a plan is stale the moment a settlement is recorded — so reopening beats
          // holding a snapshot behind the thing that invalidates it.
          onPressed: () {
            Navigator.of(context).pop();
            SplitSettlePlanSheet.show(context, groupId: groupId);
          },
          icon: const Icon(Icons.call_merge_outlined, size: AlayaIconSize.md),
          label: Text(strings.splitSimplifyTitle),
        ),

        const SizedBox(height: AlayaSpacing.xs),
        Wrap(
          spacing: AlayaSpacing.sm,
          runSpacing: AlayaSpacing.xs,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                SplitShareSheet.show(context, groupId: groupId);
              },
              icon: const Icon(Icons.ios_share, size: AlayaIconSize.md),
              label: Text(strings.actionShare),
            ),
            OutlinedButton.icon(
              // The editor keeps its route: it is a form with a delete action and a discard guard, which
              // is what `AlayaFormScaffold` and archetype B exist for. A keyboard inside a bottom sheet
              // over a list of chips is the arrangement that made this module feel like work.
              onPressed: () {
                Navigator.of(context).pop();
                context.push(Routes.splitGroupEditFor(groupId));
              },
              icon: const Icon(Icons.edit_outlined, size: AlayaIconSize.md),
              label: Text(strings.actionEdit),
            ),
          ],
        ),
      ],
    );
  }
}

class _GroupBalanceRow extends ConsumerWidget {
  const _GroupBalanceRow({required this.balance, required this.groupId});

  final SplitBalance balance;
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final name =
        ref.watch(splitPayeeNameProvider(balance.payeeId)) ??
        strings.splitUnknownPerson;

    void settle() {
      Navigator.of(context).pop();
      SettleUpSheet.show(
        context,
        payeeId: balance.payeeId,
        payeeName: name,
        outstanding: balance.outstanding,
        theyOweMe: balance.theyOweMe,
        groupId: groupId,
      );
    }

    return AlayaCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.sm,
        vertical: AlayaSpacing.xs,
      ),
      // Settling one person directly, without going through the plan. Most groups have two people and no
      // simplification to find, and making the common case pass through an optimiser is how a feature
      // built for six people slows down the pair who use it daily.
      //
      // **Tappable and labelled**, the same fix as the balance rows on the split screen: a card with no
      // button reads as a list item, and recording a repayment was the least visible thing in the module.
      onTap: settle,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AlayaSpacing.sm,
        runSpacing: AlayaSpacing.xs,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: AlayaTypography.body),
              const SizedBox(height: AlayaSpacing.xxs),
              // The direction in words, not in colour. `AmountText` has no tone parameter — it colours
              // from `kind`, deliberately, so one movement of money never renders as two different
              // things — and a sentence survives a screenshot and a colour-blind reader.
              Text(
                balance.theyOweMe
                    ? strings.splitOwesYou(name)
                    : strings.splitYouOwePerson(name),
                style: AlayaTypography.caption,
              ),
              TextButton.icon(
                onPressed: settle,
                icon: const Icon(
                  Icons.handshake_outlined,
                  size: AlayaIconSize.sm,
                ),
                label: Text(
                  balance.theyOweMe
                      ? strings.splitRecordTheyPaid
                      : strings.splitRecordYouPaid,
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          AmountText(balance.outstanding, showSign: false),
        ],
      ),
    );
  }
}
```

### `lib/features/split/presentation/sheets/split_settle_plan_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/services/split/debt_simplifier.dart';
import 'package:alaya/domain/services/split/split_balance_service.dart';
import 'package:alaya/features/split/presentation/sheets/settle_up_sheet.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// The shortest way to settle a group up — as a suggestion, never as an edit.
///
/// ## Why this is a preview and not a mode
///
/// Splitwise rewrites the group's debt graph in place when simplification is on. Three things follow,
/// all documented by Splitwise itself: its help centre ends up advising users to look at their total
/// rather than the balances between specific members, because those may have been reshuffled; turning it
/// off does not cleanly reverse, so payments already made may no longer line up; and its forum has
/// carried the same complaint for over a decade — *"why do I owe ₹100 to someone who never lent me
/// money?"*
///
/// The most-requested fix, acknowledged by their staff in 2014 and never shipped, was a way to *see* the
/// simplified view without committing to it. That is this sheet.
///
/// **Nothing here writes.** The true pairwise debts stay exactly as recorded; a transfer is acted on by
/// opening the ordinary settle-up sheet, which records the ordinary settlement any manual payment would.
/// There is no simplified state to get stuck in and no toggle to lock.
///
/// **One payment at a time, deliberately.** An "accept all" button would have to write N settlements, and
/// N repository calls cannot be atomic — session 4 established that, and claiming otherwise is the
/// mistake this module already made once.
///
/// ## Why a sheet rather than the screen it was
///
/// It was `/split/groups/:groupId/settle` — the third level of a stack, reached from a group reached from
/// a tab. Nothing on it is an editor: it reads a plan and hands each line to another sheet. A route buys
/// a back arrow and a place to get lost, and this content needs neither.
class SplitSettlePlanSheet extends ConsumerWidget {
  /// Creates the sheet.
  const SplitSettlePlanSheet({required this.groupId, super.key});

  /// The group being settled.
  final String groupId;

  /// Opens the sheet for [groupId].
  static Future<void> show(BuildContext context, {required String groupId}) =>
      AlayaBottomSheet.show<void>(
        context: context,
        builder: (context) => SplitSettlePlanSheet(groupId: groupId),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final plans = ref.watch(splitSettlePlansProvider(groupId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(strings.splitSimplifyTitle, style: AlayaTypography.sectionHeader),
        const SizedBox(height: AlayaSpacing.sm),

        plans.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AlayaSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stack) => ErrorState(
            title: strings.errorTitleGeneric,
            body: error.toString(),
            retryLabel: strings.actionRetry,
            onRetry: () => ref.invalidate(splitSettlePlansProvider(groupId)),
          ),
          data: (rows) => rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AlayaSpacing.lg,
                  ),
                  child: Text(
                    strings.splitAllSettledBody,
                    style: AlayaTypography.body.copyWith(
                      color: semantic.muted,
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entry in rows)
                      _CurrencySection(groupId: groupId, entry: entry),
                  ],
                ),
        ),
      ],
    );
  }
}

class _CurrencySection extends ConsumerWidget {
  const _CurrencySection({required this.groupId, required this.entry});

  final String groupId;
  final CurrencyPlan entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final plan = entry.plan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          // **One section per currency, never merged.** Netting INR against USD without a rate produces
          // a figure nobody can reproduce, and the simplifier refuses a mixed list outright — which is
          // the correct refusal and the reason the grouping is visible here rather than hidden in a
          // total.
          label: entry.currencyCode,
          padding: const EdgeInsets.only(bottom: AlayaSpacing.xxs),
        ),

        Text(
          plan.isImprovement
              ? strings.splitSimplifySaves(
                  plan.originalDebtCount,
                  plan.transfers.length,
                )
              : strings.splitSimplifyNoBetter,
          style: AlayaTypography.body.copyWith(
            color: plan.isImprovement ? semantic.success : semantic.muted,
          ),
        ),

        if (!plan.wasPartitionedExactly) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            // **Says "a way", not "the fewest".** The exact partition runs up to sixteen people; beyond
            // that the greedy fallback still settles everybody but cannot prove it is minimal, and a
            // screen claiming otherwise would assert something the code deliberately does not know.
            child: StatusChip(
              label: strings.splitSimplifyApproximate,
              tone: StatusTone.info,
            ),
          ),
        ],

        const SizedBox(height: AlayaSpacing.sm),
        for (final transfer in plan.transfers)
          _TransferCard(groupId: groupId, transfer: transfer),
      ],
    );
  }
}

class _TransferCard extends ConsumerWidget {
  const _TransferCard({required this.groupId, required this.transfer});

  final String groupId;
  final SuggestedTransfer transfer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final self = ref.watch(splitSelfProvider).valueOrNull;

    String nameOf(String payeeId) =>
        ref.watch(splitPayeeNameProvider(payeeId)) ??
        strings.splitUnknownPerson;

    final youPay = transfer.fromPayeeId == self;
    final youArePaid = transfer.toPayeeId == self;
    final counterparty = youPay ? transfer.toPayeeId : transfer.fromPayeeId;
    final yours = youPay || youArePaid;

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.sm),
      // A transfer between two other people is a suggestion the user can pass on, not something they can
      // record — no money of theirs moves, so there is no account to put it through.
      //
      // **The plan sheet closes before the settle sheet opens.** Two stacked bottom sheets leave a user
      // dragging one to reveal another, and the plan is stale the moment a settlement is recorded anyway
      // — reopening it is both cheaper and more correct than keeping a snapshot behind the thing that
      // invalidates it.
      onTap: !yours
          ? null
          : () {
              Navigator.of(context).pop();
              SettleUpSheet.show(
                context,
                payeeId: counterparty,
                payeeName: nameOf(counterparty),
                outstanding: transfer.amount,
                theyOweMe: youArePaid,
                groupId: groupId,
              );
            },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A `Wrap`, not a `Row`: "Ravi pays Priya" beside an amount is the shape that overflows at
          // 320dp with the text scaler doubled (Law U15).
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AlayaSpacing.sm,
            runSpacing: AlayaSpacing.xxs,
            children: [
              SizedBox(
                width: 170,
                child: Text(
                  strings.splitTransferLine(
                    nameOf(transfer.fromPayeeId),
                    nameOf(transfer.toPayeeId),
                  ),
                  style: AlayaTypography.bodyEmphasis,
                ),
              ),
              AmountText(transfer.amount, showSign: false),
            ],
          ),

          // **The sentence Splitwise leaves its users to work out.** A simplified transfer arrives with
          // no provenance there, which is why the same question keeps being asked on their forum. Every
          // transfer here can account for itself.
          if (!transfer.isDirect) ...[
            const SizedBox(height: AlayaSpacing.xs),
            for (final cleared in transfer.clears)
              Padding(
                padding: const EdgeInsets.only(bottom: AlayaSpacing.xxs),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AlayaSpacing.xxs,
                  children: [
                    Icon(
                      Icons.subdirectory_arrow_right,
                      size: AlayaIconSize.sm,
                      color: semantic.muted,
                    ),
                    SizedBox(
                      width: 150,
                      child: Text(
                        strings.splitClearsDebt(nameOf(cleared.edge.toPayeeId)),
                        style: AlayaTypography.caption.copyWith(
                          color: semantic.muted,
                        ),
                      ),
                    ),
                    AmountText(
                      cleared.amount,
                      size: AmountSize.small,
                      showSign: false,
                      muted: true,
                    ),
                  ],
                ),
              ),
          ],

          if (!yours) ...[
            const SizedBox(height: AlayaSpacing.xxs),
            Text(
              // Says why the row does not respond, rather than leaving a dead card. A transfer between
              // two other people is real advice and not something the user can act on here.
              strings.splitTransferNotYours,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
          ],
        ],
      ),
    );
  }
}
```

### `lib/features/split/presentation/sheets/split_share_sheet.dart`

```dart
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
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/money/money_formatter.dart';
import 'package:alaya/domain/services/split/split_summary_builder.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/features/split/providers/split_summary_provider.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';

/// Shows the shareable summary, and hands it to the system share sheet.
///
/// **This is what stands in for sync.** Nobody else has the app — a recorded decision, not a gap — so
/// the way somebody sees the same numbers is that the user sends them. Every review of every
/// competitor names the opposite arrangement as the friction that kills adoption: splitting a bill
/// with six people needs six installs, and two of them never happen.
///
/// **The summary is composed here, not in a provider.** `SplitSummaryBuilder` needs four sentences
/// from the ARB and `AlayaStrings` needs a `BuildContext`, which no provider has.
///
/// **The text is shown before it is sent.** A share sheet that fires straight into WhatsApp gives no
/// chance to notice a wrong name or a stale amount, and this message names what people owe each other
/// — the most consequential thing this app will ever put in somebody else's hands.
class SplitShareSheet extends ConsumerWidget {
  /// Creates the sheet.
  const SplitShareSheet({this.groupId, super.key});

  /// Restrict to one group, or null for everything outstanding.
  final String? groupId;

  /// Opens the sheet.
  static Future<void> show(BuildContext context, {String? groupId}) =>
      AlayaBottomSheet.show<void>(
        context: context,
        builder: (context) => SplitShareSheet(groupId: groupId),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    final balances = ref
        .watch(splitSummaryBalancesProvider(groupId))
        .valueOrNull;
    final digits = ref.watch(splitDecimalDigitsProvider).valueOrNull;

    if (balances == null || digits == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AlayaSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    const formatter = MoneyFormatter();
    final handle = ref.watch(splitPaymentHandleProvider).valueOrNull;
    final summary = const SplitSummaryBuilder().build(
      balances: balances,
      nameOf: (id) =>
          ref.read(splitPayeeNameProvider(id)) ?? strings.splitUnknownPerson,
      // `symbol` takes the currency code, matching what the transaction list already passes. There is
      // no symbol lookup in this app, and inventing one here would be a second answer to a question
      // every other screen has settled.
      formatAmount: (Money amount) => formatter.format(
        amount,
        decimalDigits: digits,
        symbol: amount.currencyCode,
      ),
      labels: SummaryLabels(
        heading: strings.splitShareHeading,
        owesYou: strings.splitShareOwesYou,
        youOwe: strings.splitShareYouOwe,
        payMeAt: strings.splitSharePayMeAt,
      ),
      paymentHandle: handle,
    );

    if (summary.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.xl),
        child: Text(
          strings.splitAllSettledBody,
          style: AlayaTypography.body.copyWith(color: semantic.muted),
        ),
      );
    }

    final owedAnything = summary.lines.any((line) => line.theyOweMe);
    final hasHandle = handle != null && handle.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(strings.splitShareTitle, style: AlayaTypography.sectionHeader),
        const SizedBox(height: AlayaSpacing.md),

        Container(
          padding: const EdgeInsets.all(AlayaSpacing.sm),
          decoration: BoxDecoration(
            color: semantic.muted.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AlayaSpacing.xs),
          ),
          child: SelectableText(
            summary.text,
            style: AlayaTypography.caption,
          ),
        ),

        // Offered only when somebody actually owes the user — suggesting they add payment details on a
        // summary of their own debts would be advice about the wrong direction. Named as an
        // opportunity rather than an error: the summary is perfectly useful without one.
        if (!hasHandle && owedAnything) ...[
          const SizedBox(height: AlayaSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.splitShareAddHandle,
                  style: AlayaTypography.caption.copyWith(
                    color: semantic.muted,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.push(Routes.settingsSplit),
                child: Text(strings.actionAdd),
              ),
            ],
          ),
        ],

        const SizedBox(height: AlayaSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: summary.text));
                  if (!context.mounted) return;
                  showResultSnack(context, message: strings.splitShareCopied);
                },
                icon: const Icon(Icons.copy_outlined, size: AlayaIconSize.md),
                label: Text(strings.actionCopy),
              ),
            ),
            const SizedBox(width: AlayaSpacing.sm),
            Expanded(
              child: FilledButton.icon(
                onPressed: () =>
                    ref.read(splitShareProvider).shareText(summary.text),
                icon: const Icon(Icons.ios_share, size: AlayaIconSize.md),
                label: Text(strings.actionShare),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
```

### `lib/features/split/presentation/widgets/people_counter.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// How many people are sharing: two taps, or type it.
///
/// **Both, because the two cases are genuinely different.** Going from two to four is a tap each way
/// and a keyboard would be slower; going from two to *fourteen* is twelve taps, which is where a
/// stepper stops being a convenience and becomes a chore. The number between the buttons is therefore
/// a field, not a label.
///
/// **The field reads the count and never fights it.** Its controller is only rewritten when the value
/// arriving from outside differs from what is displayed — otherwise every keystroke would rebuild the
/// parent, push the same text back in, and reset the cursor to the start. That is the same trap the
/// `_loaded` guard solves in `TagEditorScreen`, in its live-editing form rather than its adoption one.
///
/// **Empty is allowed while typing and never committed.** Somebody clearing the field to type "12"
/// passes through "" — treating that as zero would collapse the split, and rejecting it would make the
/// field impossible to clear. It simply reports nothing until a valid number exists.
class PeopleCounter extends StatefulWidget {
  /// Creates the counter.
  const PeopleCounter({
    required this.count,
    required this.onChanged,
    this.minimum = 1,
    super.key,
  });

  /// How many people there are now.
  final int count;

  /// Called with a valid new count.
  final ValueChanged<int> onChanged;

  /// The fewest allowed — one on the full editor, two on the quick card.
  final int minimum;

  /// The most this will accept.
  ///
  /// Not a product rule so much as a guard against a typo: somebody who means 12 and types 120 would
  /// otherwise get a hundred and twenty rows and a frozen screen.
  static const int maximum = 99;

  @override
  State<PeopleCounter> createState() => _PeopleCounterState();
}

class _PeopleCounterState extends State<PeopleCounter> {
  late final TextEditingController _field = TextEditingController(
    text: '${widget.count}',
  );

  @override
  void didUpdateWidget(PeopleCounter old) {
    super.didUpdateWidget(old);
    // Only when it actually differs — see the class doc. A blanket assignment here is what turns a
    // typable field into one that clears itself on the second digit.
    if (_field.text != '${widget.count}') {
      _field.text = '${widget.count}';
    }
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _step(int by) {
    final next = (widget.count + by).clamp(
      widget.minimum,
      PeopleCounter.maximum,
    );
    if (next != widget.count) widget.onChanged(next);
  }

  void _typed(String text) {
    final parsed = int.tryParse(text.trim());
    // Nothing yet, or nonsense: leave the count where it is and let them keep typing.
    if (parsed == null) return;
    final next = parsed.clamp(widget.minimum, PeopleCounter.maximum);
    if (next != widget.count) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton.filledTonal(
          // Disabled at the floor rather than clamping silently: a button that looks live and does
          // nothing is worse than one that plainly cannot be pressed.
          onPressed: widget.count > widget.minimum ? () => _step(-1) : null,
          icon: const Icon(Icons.remove, size: AlayaIconSize.md),
        ),
        SizedBox(
          width: 56,
          child: TextField(
            controller: _field,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            // Digits only, so the parse above is about range rather than shape and the keyboard cannot
            // introduce a minus sign or a decimal point that would need rejecting after the fact.
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            style: AlayaTypography.sectionHeader,
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                vertical: AlayaSpacing.xs,
              ),
            ),
            onChanged: _typed,
            // Leaving the field empty puts the real count back, so it never looks blank once the
            // keyboard closes.
            onTapOutside: (_) {
              if (int.tryParse(_field.text) == null) {
                _field.text = '${widget.count}';
              }
              FocusScope.of(context).unfocus();
            },
          ),
        ),
        IconButton.filledTonal(
          onPressed: widget.count < PeopleCounter.maximum
              ? () => _step(1)
              : null,
          icon: const Icon(Icons.add, size: AlayaIconSize.md),
        ),
      ],
    );
  }
}
```

### `lib/features/split/presentation/widgets/quick_split_card.dart`

```dart
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
```

### `lib/features/split/presentation/widgets/split_groups_list.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/split_group.dart';
import 'package:alaya/features/split/presentation/sheets/split_group_detail_sheet.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// The groups a split can be filed under — a tab, not a screen.
///
/// **Was `/split/groups`.** A list reached from a tab, containing rows that opened another screen: three
/// levels for content that fits in one. It is a tab now, and a row opens a sheet.
///
/// **Archived groups are shown, greyed, not hidden.** Archiving keeps a group's history and its balances
/// and only removes it from the pickers — the distinction ARCH_3 §4 draws against deleting. Hiding them
/// here would make "where did my flatmates group go" unanswerable from the one place that exists to
/// answer it.
///
/// **Most groups are made on the bill screen rather than here.** Once two people on a split are named,
/// *"Save these 2 as a group"* turns the split you already have into a reusable one — which is what fixed
/// "it is very hard to create groups". This list is where they are reviewed, renamed and archived; the
/// button stays because a group made in advance is still a legitimate thing to want.
class SplitGroupsList extends ConsumerWidget {
  /// Creates the list.
  const SplitGroupsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final groups = ref.watch(splitAllGroupsProvider);

    return groups.when(
      loading: () => AlayaListSkeleton(label: strings.loadingLabel),
      error: (error, stack) => ErrorState(
        title: strings.errorTitleGeneric,
        body: error.toString(),
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(splitAllGroupsProvider),
      ),
      data: (rows) => ListView(
        padding: const EdgeInsets.fromLTRB(
          AlayaSpacing.screenEdge,
          AlayaSpacing.md,
          AlayaSpacing.screenEdge,
          AlayaSpacing.xxxl,
        ),
        children: [
          // **Offered above the list rather than as a floating button.** The tab shares its screen with
          // two others and a FAB belongs to the screen, not to one tab — a create-group button hovering
          // over the balances tab would be the wrong action in the wrong place.
          OutlinedButton.icon(
            onPressed: () => context.push(Routes.splitGroupNew),
            icon: const Icon(Icons.group_add_outlined, size: AlayaIconSize.md),
            label: Text(strings.splitGroupNew),
          ),
          const SizedBox(height: AlayaSpacing.md),

          if (rows.isEmpty)
            EmptyState(
              title: strings.splitNoGroupsTitle,
              body: strings.splitNoGroupsBody,
              icon: Icons.groups_outlined,
            )
          else
            for (final group in rows) _GroupRow(group: group),
        ],
      ),
    );
  }
}

class _GroupRow extends ConsumerWidget {
  const _GroupRow({required this.group});

  final SplitGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return AlayaCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.sm,
        vertical: AlayaSpacing.xs,
      ),
      onTap: () => SplitGroupDetailSheet.show(context, groupId: group.id),
      // **A `Wrap`, not a `Row`, and this was a live bug.** A name beside up to two `StatusChip`s is three
      // fixed-width children that cannot shrink — the same shape that overran the split home screen by
      // 215 pixels at a doubled text scale, and worse here because an archived group with custom shares
      // carries both chips at once.
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AlayaSpacing.sm,
        runSpacing: AlayaSpacing.xs,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                group.name,
                style: AlayaTypography.body.copyWith(
                  color: group.isArchived ? semantic.muted : null,
                ),
              ),
              const SizedBox(height: AlayaSpacing.xxs),
              Text(
                strings.splitPerPersonCount(group.members.length),
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
            ],
          ),
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xxs,
            children: [
              // Says what the group will do before it is used. A group carrying 40/30/30 behaves
              // differently from one that splits equally, and that is worth knowing from the list rather
              // than after opening the editor.
              if (group.hasDefaultWeights)
                StatusChip(
                  label: strings.splitHasWeights,
                  tone: StatusTone.info,
                ),
              if (group.isArchived)
                StatusChip(
                  label: strings.splitArchived,
                  tone: StatusTone.neutral,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
```

### `lib/features/split/presentation/widgets/split_history_list.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/core/time/date_key_labels.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/features/split/presentation/sheets/split_expense_detail_sheet.dart';
import 'package:alaya/features/split/providers/split_history_provider.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Every split and every settlement, newest first.
///
/// ## Why the module needed this
///
/// **A balance list is not a record of what happened.** Balances say who currently owes what, so a split
/// settled the same evening leaves nothing behind — and until now that meant no evidence it ever
/// happened. Somebody who divided a restaurant bill, was paid back in cash, and looked for it a week
/// later found an empty screen and had to trust their memory over the app.
///
/// It is also where a split with unnamed participants belongs. Those have real balances while money is
/// outstanding, but the *decision* — four ways, ₹800 of it somebody's sushi — is a fact about an evening
/// rather than about a debt, and this is the only surface that keeps it.
///
/// **It cost one provider.** `watchActivity` already took a nullable `groupId` and nothing ever passed
/// null, so the capability existed and had no caller. `v_split_activity` interleaves both tables as a
/// `UNION ALL` rather than an events table, because two subsystems writing into a shared feed is a
/// synchronisation-bug factory and a view has no synchronisation code to get wrong (anomaly A37).
class SplitHistoryList extends ConsumerWidget {
  /// Creates the list.
  ///
  /// [groupId] narrows it to one group; null shows everything, including splits filed under no group at
  /// all — which is most of them, since the bill screen makes a group optional.
  const SplitHistoryList({this.groupId, super.key});

  /// The group to restrict to, or null for everything.
  final String? groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final scope = groupId;
    final entries = scope == null
        ? ref.watch(splitHistoryProvider)
        : ref.watch(splitGroupHistoryProvider(scope));

    return entries.when(
      loading: () => AlayaListSkeleton(label: strings.loadingLabel),
      error: (error, stack) => ErrorState(
        title: strings.errorTitleGeneric,
        body: error.toString(),
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(
          scope == null
              ? splitHistoryProvider
              : splitGroupHistoryProvider(scope),
        ),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return EmptyState(
            // Names what would fill it rather than reporting a count of nothing. An empty history is the
            // normal state of a new install, not a problem to solve.
            title: strings.splitHistoryEmptyTitle,
            body: strings.splitHistoryEmptyBody,
            icon: Icons.history_outlined,
          );
        }

        final days = _groupByDay(rows);
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
          itemCount: days.length,
          itemBuilder: (context, index) {
            final day = days[index];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  label: day.date.fullLabel,
                  padding: EdgeInsets.only(
                    top: index == 0 ? AlayaSpacing.sm : AlayaSpacing.lg,
                    bottom: AlayaSpacing.xs,
                    left: AlayaSpacing.screenEdge,
                    right: AlayaSpacing.screenEdge,
                  ),
                ),
                for (final entry in day.entries) _HistoryRow(entry: entry),
              ],
            );
          },
        );
      },
    );
  }

  /// Groups [rows] into days, newest day first.
  ///
  /// The feed already arrives newest-first, so the days come out ordered by insertion and the entries
  /// within each keep the view's own ordering — no second sort, and therefore no chance of a second sort
  /// disagreeing with the first.
  static List<_Day> _groupByDay(List<SplitActivityEntry> rows) {
    final byDate = <int, List<SplitActivityEntry>>{};
    final order = <int>[];
    for (final row in rows) {
      final key = row.dateKey.value;
      if (!byDate.containsKey(key)) {
        byDate[key] = [];
        order.add(key);
      }
      byDate[key]!.add(row);
    }
    return [
      for (final key in order) _Day(date: DateKey(key), entries: byDate[key]!),
    ];
  }
}

class _Day {
  const _Day({required this.date, required this.entries});

  final DateKey date;
  final List<SplitActivityEntry> entries;
}

class _HistoryRow extends ConsumerWidget {
  const _HistoryRow({required this.entry});

  final SplitActivityEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final digits = ref.watch(splitDecimalDigitsProvider).valueOrNull ?? 2;
    final who =
        ref.watch(splitPayeeNameProvider(entry.payeeId)) ??
        strings.splitUnknownPerson;

    // Exhaustive over the kind, so a third activity kind fails to compile here rather than rendering the
    // wrong sentence (Law L13).
    final what = switch (entry.kind) {
      SplitActivityKind.expense => strings.splitHistoryPaidBy(who),
      SplitActivityKind.settlement => strings.splitHistorySettledBy(who),
    };
    // The label is whichever of title, occasion, place or note the view found — so a row is named by
    // whatever the user actually typed, and falls back to the sentence about the payer rather than to a
    // blank line.
    //
    // **When there is no label the sentence is the title and there is no subtitle**, because the first
    // version used it as both: an unlabelled row rendered "Ravi paid" at 15pt with "Ravi paid" in grey
    // underneath it. Two lines saying one thing reads as a rendering fault, and a caption only earns its
    // place when it adds something the line above does not already say.
    final label = entry.label?.trim();
    final named = label != null && label.isNotEmpty;
    final title = named ? label : what;

    return AlayaCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.sm,
        vertical: AlayaSpacing.xs,
      ),
      // **Only an expense opens.** A settlement is a single fact — this much moved, on this day, between
      // these two — and a sheet repeating the row it was opened from would be a tap that buys nothing. An
      // expense has shares, a payer and a method behind it, none of which fit on a row.
      onTap: entry.kind == SplitActivityKind.expense
          ? () => SplitExpenseDetailSheet.show(context, expenseId: entry.refId)
          : null,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AlayaSpacing.sm,
        runSpacing: AlayaSpacing.xs,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AlayaSpacing.xs,
            children: [
              Icon(
                // A bill and a repayment are opposite events and the glyph says which without a word.
                switch (entry.kind) {
                  SplitActivityKind.expense => Icons.call_split_outlined,
                  SplitActivityKind.settlement => Icons.handshake_outlined,
                },
                size: AlayaIconSize.md,
                color: semantic.muted,
              ),
              SizedBox(
                width: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AlayaTypography.body,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (named)
                      Text(
                        what,
                        style: AlayaTypography.caption.copyWith(
                          color: semantic.muted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          // Unsigned, and deliberately. An expense is not necessarily an outflow from the user's
          // account — somebody else may have paid it — so a minus sign would assert something this row
          // does not know. The icon carries the direction.
          AmountText(entry.amount, showSign: false, decimalDigits: digits),
        ],
      ),
    );
  }
}
```

### `lib/features/split/presentation/widgets/split_method_picker.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/split_enums.dart';

/// How a bill divides: equally, by shares, by percentage, or exact amounts.
///
/// ## Why this is not a `SegmentedButton`
///
/// It was one, with four segments. At the 320dp gate that is **eighty pixels each**, and a segmented
/// button cannot wrap — its children get an equal slice of whatever width there is and clip. "By
/// percentage" at a doubled text scale had nowhere to go, so the control was unreadable exactly for the
/// users Law U15 exists to protect.
///
/// Chips in a `Wrap` reflow to two lines and then three, each staying legible. One tap either way, and the
/// row grows downward instead of squeezing sideways.
///
/// ## And it says what the choice means
///
/// A caption under the chips explains the selected method in a sentence. "By shares" is not
/// self-explanatory — it is the 2:1:1 case, and somebody who has not met it before will otherwise tap all
/// four to find out which one they wanted. The four labels were doing two jobs and only managing one.
class SplitMethodPicker extends StatelessWidget {
  /// Creates the picker.
  const SplitMethodPicker({
    required this.method,
    required this.onChanged,
    super.key,
  });

  /// The method in force.
  final SplitMethod method;

  /// Called with the newly chosen method.
  final ValueChanged<SplitMethod> onChanged;

  /// The methods this control offers.
  ///
  /// **[SplitMethod.perLine] is excluded and that is not an oversight.** An itemised split comes from a
  /// receipt's lines, which this screen does not have — the expense editor does. Offering it here would be
  /// a chip that cannot work, and the resolver would refuse it.
  static const List<SplitMethod> offered = [
    SplitMethod.equal,
    SplitMethod.shares,
    SplitMethod.percent,
    SplitMethod.exactAmounts,
  ];

  static String _label(
    AlayaStrings strings,
    SplitMethod method,
  ) => switch (method) {
    SplitMethod.equal => strings.splitMethodEqual,
    SplitMethod.shares => strings.splitMethodShares,
    SplitMethod.percent => strings.splitMethodPercent,
    SplitMethod.exactAmounts => strings.splitMethodExact,
    // Named rather than defaulted, so adding a method fails to compile here instead of silently
    // borrowing another one's label (Law L13).
    SplitMethod.perLine => strings.splitMethodPerLine,
  };

  static String _explains(AlayaStrings strings, SplitMethod method) =>
      switch (method) {
        SplitMethod.equal => strings.splitMethodEqualHelp,
        SplitMethod.shares => strings.splitMethodSharesHelp,
        SplitMethod.percent => strings.splitMethodPercentHelp,
        SplitMethod.exactAmounts => strings.splitMethodExactHelp,
        SplitMethod.perLine => strings.splitMethodPerLineHelp,
      };

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.splitMethodTitle,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final option in offered)
              ChoiceChip(
                label: Text(_label(strings, option)),
                selected: option == method,
                onSelected: (_) => onChanged(option),
              ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Text(
          // The sentence the four labels could not carry. Shown for the selected one only — four
          // explanations at once is a paragraph nobody reads.
          _explains(strings, method),
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
      ],
    );
  }
}
```

### `lib/features/split/presentation/widgets/split_proportion_bar.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/shared/widgets/amount_text.dart';

/// One person's slice of a bill.
final class ProportionSlice {
  /// Creates a slice.
  const ProportionSlice({
    required this.label,
    required this.amount,
    this.extra,
  });

  /// Who — a name, or "Person 2" before anybody is named.
  final String label;

  /// Their whole share, extra included.
  final Money amount;

  /// The part of [amount] charged to them alone, when they had an extra.
  final Money? extra;
}

/// A bill drawn to scale, so the split can be seen rather than read.
///
/// ## Why a bar and not just the numbers
///
/// Four figures in a column are four things to compare by reading. One bar is a single glance: Ravi's
/// slice is visibly a third of the bill while everybody else has a fifth, and **the reason for it is
/// drawn as a distinct block inside his slice**. The sentence "₹1,050 share + ₹800 just for them" says
/// the same thing and takes a moment longer, which is a moment somebody spends at a table with three
/// people waiting.
///
/// Nothing else in this category shows the shape of a bill. It costs one widget and no schema.
///
/// ## Colour, and its limits
///
/// Hues are derived from the theme's primary by rotating 47° per slice — a prime-ish step that keeps
/// adjacent slices apart without a hardcoded palette that would fight a user's chosen scheme.
///
/// **Colour is never the only carrier.** Every slice is also named and priced in the legend below, and
/// the bar is decorative in the accessibility sense: a reader who cannot distinguish two hues loses
/// nothing, because the same information is in the rows underneath. That is the same rule the balance
/// rows follow by putting direction in a section heading rather than in a tint.
///
/// ## The remainder
///
/// What the slices do not cover is drawn as a hatched gap rather than being absorbed. Percentages
/// reaching 90% leave a visible tenth of the bar empty, which is a better explanation of "unallocated"
/// than a chip — and it is the same refusal to auto-balance that `LineItemsSection` records.
class SplitProportionBar extends StatelessWidget {
  /// Creates the bar.
  const SplitProportionBar({
    required this.slices,
    required this.total,
    required this.decimalDigits,
    super.key,
  });

  /// Each participant's slice, in display order.
  final List<ProportionSlice> slices;

  /// What is being split, which sets the scale.
  final Money total;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  /// How tall the bar is drawn.
  static const double barHeight = 28;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;

    // Against the *total*, not against the sum of the slices. Scaling to the slices would stretch an
    // over-allocated split to a perfect bar and hide the very thing worth seeing.
    final scale = total.minor.abs();
    if (scale == 0 || slices.isEmpty) return const SizedBox.shrink();

    final allocated = slices.fold<int>(0, (sum, s) => sum + s.amount.minor);
    final leftover = scale - allocated;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AlayaSpacing.xs),
          child: SizedBox(
            height: barHeight,
            child: Row(
              children: [
                for (var i = 0; i < slices.length; i++)
                  ..._segmentsFor(slices[i], _hueFor(scheme, i)),
                if (leftover > 0)
                  Expanded(
                    flex: leftover,
                    child: CustomPaint(
                      painter: _HatchPainter(color: semantic.muted),
                    ),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: AlayaSpacing.sm),
        for (var i = 0; i < slices.length; i++)
          _LegendRow(
            slice: slices[i],
            colour: _hueFor(scheme, i),
            percent: scale == 0 ? 0 : slices[i].amount.minor * 100 / scale,
            decimalDigits: decimalDigits,
          ),
      ],
    );
  }

  /// One or two segments for a slice — two when part of it is an extra.
  ///
  /// `Expanded` with an integer flex, so the widths are laid out by the framework in exact proportion
  /// to minor units. Computing pixel widths here would need the bar's measured width and would
  /// re-introduce the rounding that `Money.allocate` exists to avoid.
  List<Widget> _segmentsFor(ProportionSlice slice, Color colour) {
    final extra = slice.extra?.minor ?? 0;
    final share = slice.amount.minor - extra;
    return [
      if (share > 0)
        Expanded(
          flex: share,
          child: ColoredBox(color: colour),
        ),
      if (extra > 0)
        Expanded(
          flex: extra,
          child: ColoredBox(
            // The same hue, darkened — related to the person's share, and visibly not the same thing.
            // A separate hue would read as a fifth participant.
            color: Color.alphaBlend(
              Colors.black.withValues(alpha: 0.32),
              colour,
            ),
          ),
        ),
    ];
  }

  /// A hue for slice [index], rotated from the theme's primary.
  static Color _hueFor(ColorScheme scheme, int index) {
    final base = HSLColor.fromColor(scheme.primary);
    return base
        .withHue((base.hue + index * 47) % 360)
        // Floors kept off the extremes so a pale or near-black primary still yields legible slices.
        .withSaturation(base.saturation.clamp(0.45, 0.85))
        .withLightness(base.lightness.clamp(0.42, 0.62))
        .toColor();
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.slice,
    required this.colour,
    required this.percent,
    required this.decimalDigits,
  });

  final ProportionSlice slice;
  final Color colour;
  final double percent;
  final int decimalDigits;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return Padding(
      padding: const EdgeInsets.only(bottom: AlayaSpacing.xxs),
      // A `Wrap`, not a `Row`: a name beside an amount beside a percentage is three fixed children,
      // which is the shape that overflows at 320dp with the scaler doubled (Law U15).
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AlayaSpacing.xs,
        runSpacing: AlayaSpacing.xxs,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Text(slice.label, style: AlayaTypography.caption),
          Text(
            strings.splitPercentOfBill(percent.round()),
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
          AmountText(
            slice.amount,
            size: AmountSize.small,
            showSign: false,
            decimalDigits: decimalDigits,
          ),
        ],
      ),
    );
  }
}

/// Diagonal stripes for the part of a bill nothing covers.
///
/// Drawn rather than tinted, because a solid grey block reads as another participant. Stripes read as
/// absence, which is what an unallocated remainder is.
class _HatchPainter extends CustomPainter {
  const _HatchPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = color.withValues(alpha: 0.10);
    canvas.drawRect(Offset.zero & size, background);

    final stroke = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..strokeWidth = 1.5;
    // Starting at -height so the first stripes still cross the top-left corner; without the offset the
    // leading edge of a narrow remainder is blank and the hatching looks like a rendering fault.
    for (var x = -size.height; x < size.width; x += 6) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_HatchPainter oldDelegate) => oldDelegate.color != color;
}
```

### `lib/features/split/presentation/widgets/split_tip_row.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/shared/widgets/amount_text.dart';

/// A tip or service charge on top of the bill.
///
/// ## Any percentage, not four of them
///
/// The first version offered 5, 10, 15 and round-up, which covers a lot of restaurants and none of the
/// other reasons somebody adds to a bill. **1% happens** — a card surcharge, a small service charge, a
/// rounding the table agreed to — and a fixed row of chips makes an ordinary number unreachable.
///
/// So the chips stay for the common cases and a **Custom** chip reveals a field. The two are one value,
/// not two that agree by habit: choosing 10% writes 1000 basis points, and the field edits the same
/// number, so a chip and a field cannot disagree.
///
/// **Basis points, not percent, and that is what makes fractions expressible.** 12.5% is 1250 with no
/// rounding anywhere; a percent-typed field would have had to store 12 or 13.
///
/// ## Round-up is not a percentage and does not pretend to be
///
/// It answers *"make it a round number"*, which no percentage expresses — ₹4,730 to ₹4,800 is 1.48%, and
/// nobody thinks in those terms at a counter. It is a separate flag, applied after the tip, so "10% and
/// then make it round" is one state rather than a choice between two.
class SplitTipRow extends StatefulWidget {
  /// Creates the row.
  const SplitTipRow({
    required this.base,
    required this.basisPoints,
    required this.roundUp,
    required this.decimalDigits,
    required this.onTip,
    required this.onRoundUp,
    super.key,
  });

  /// The bill before any tip, or null while nothing has been typed.
  final Money? base;

  /// The tip as a fraction of the bill, in basis points. 1000 is 10%.
  final int basisPoints;

  /// Whether the total is rounded up to a whole major unit afterwards.
  final bool roundUp;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  /// Called with a new tip in basis points.
  final ValueChanged<int> onTip;

  /// Called when the round-up flag changes.
  final ValueChanged<bool> onRoundUp;

  /// The percentages offered as chips.
  ///
  /// A shortcut list rather than a product decision: any number is reachable through **Custom**, and
  /// these three are the ones worth one tap.
  static const List<int> presetPercents = [5, 10, 15];

  /// The largest tip accepted, in basis points.
  ///
  /// A tip larger than the bill is a typo far more often than an intention, and a field that accepts
  /// 1000% turns a slipped keypress into a balance nobody can explain.
  static const int maxBasisPoints = 10000;

  /// The tip [basisPoints] produces on [base].
  ///
  /// **Floor, and that is the honest direction.** A tip is a number somebody says out loud — "ten
  /// percent" — so rounding it up to make the arithmetic prettier charges the table for a decision nobody
  /// made. The stray paise show up in the total, where they are visible.
  ///
  /// Public and static because it is pure arithmetic with no widget in it, which is what lets the visuals
  /// test assert 5%, 10% and 15% without pumping a frame.
  static Money tipOn(Money base, int basisPoints) =>
      Money(base.minor * basisPoints ~/ 10000, base.currencyCode);

  /// The granularity a round-up reaches for, in minor units.
  ///
  /// **Ten major units — ₹10, not ₹1.** Rounding ₹4,730 to ₹4,731 is not a round-up; nobody at a counter
  /// means that. Ten is the step people actually reach for, and it is what makes the chip's promise true.
  ///
  /// **Derived from [decimalDigits] rather than hardcoded**, because JPY has none: a literal 1000 would
  /// make "round up" mean ¥1,000 in Tokyo and ₹10 in Ahmedabad, and only one of those is what the chip
  /// says. Ten of whatever the currency counts in.
  static int stepFor(int decimalDigits) => 10 * _pow10(decimalDigits);

  /// What actually gets divided: [base], plus the tip, rounded up if asked.
  ///
  /// **Static, because the screen owns the number and this widget only edits it.** The bill and the
  /// figure being split are held apart so the chips stay reversible — adding 10% and clearing it must
  /// return the original bill, which is impossible once the two have been merged.
  ///
  /// **Floor on the tip, ceiling on the round-up**, and each is the honest direction for what it means.
  /// A tip is a number somebody says out loud, so rounding it up charges the table for a decision nobody
  /// made; a round-up is a request to reach the next whole unit, so it can only go up.
  static Money? totalFor({
    required Money? base,
    required int basisPoints,
    required bool roundUp,
    required int decimalDigits,
  }) {
    if (base == null) return null;
    // Through `tipOn` and `stepFor` rather than inlining both: two copies of the same arithmetic is how a
    // widget and its test come to disagree about what 12.5% means.
    final tipped = base.minor + tipOn(base, basisPoints).minor;
    if (!roundUp) return Money(tipped, base.currencyCode);
    final unit = stepFor(decimalDigits);
    final remainder = tipped % unit;
    return Money(
      remainder == 0 ? tipped : tipped + (unit - remainder),
      base.currencyCode,
    );
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  @override
  State<SplitTipRow> createState() => _SplitTipRowState();
}

class _SplitTipRowState extends State<SplitTipRow> {
  /// Whether the percent field is showing.
  ///
  /// Starts open when the tip is not one of the presets, so reopening a 12% split shows the number that
  /// produced it rather than a row of chips none of which is selected.
  late bool _custom = widget.basisPoints > 0 && !_isPreset(widget.basisPoints);

  late final TextEditingController _field = TextEditingController(
    text: widget.basisPoints == 0 ? '' : _percentText(widget.basisPoints),
  );

  static bool _isPreset(int basisPoints) =>
      SplitTipRow.presetPercents.any((p) => p * 100 == basisPoints);

  /// Basis points as a percentage string, dropping a trailing `.0`.
  ///
  /// 1250 reads as `12.5`, 1000 as `10` — a field showing `10.0` invites somebody to delete the zero and
  /// then the point, which is two keystrokes of fighting the field.
  static String _percentText(int basisPoints) {
    final whole = basisPoints ~/ 100;
    final frac = basisPoints % 100;
    if (frac == 0) return '$whole';
    return frac % 10 == 0 ? '$whole.${frac ~/ 10}' : '$whole.$frac';
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  /// Selects [basisPoints], or clears the tip when it is already selected.
  ///
  /// **Tapping the chosen chip again clears it**, which a `ChoiceChip` does not do on its own. Choosing 10%
  /// and then deciding against it should not require finding the "None" chip — the thing you just tapped is
  /// where your thumb already is. My rewrite dropped this and a test caught it.
  void _choose(int basisPoints) {
    final next = (!_custom && widget.basisPoints == basisPoints)
        ? 0
        : basisPoints;
    setState(() {
      _custom = false;
      final text = next == 0 ? '' : _percentText(next);
      if (_field.text != text) _field.text = text;
    });
    widget.onTip(next);
  }

  void _typed(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      // Cleared means no tip. Distinct from unparseable, which is left alone so a half-typed "1." does
      // not blank the figure somebody is in the middle of writing.
      widget.onTip(0);
      return;
    }
    final parsed = double.tryParse(trimmed);
    if (parsed == null) return;
    widget.onTip(
      (parsed * 100).round().clamp(0, SplitTipRow.maxBasisPoints),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final base = widget.base;
    final total = SplitTipRow.totalFor(
      base: base,
      basisPoints: widget.basisPoints,
      roundUp: widget.roundUp,
      decimalDigits: widget.decimalDigits,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.splitTipTitle,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.xs),

        // A `Wrap`, so six chips reflow onto a second line at 320dp with the scaler doubled rather than
        // overflowing — the shape that caught the balance rows and the group rows before them (Law U15).
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            ChoiceChip(
              label: Text(strings.splitTipNone),
              selected: widget.basisPoints == 0 && !_custom,
              onSelected: (_) => _choose(0),
            ),
            for (final percent in SplitTipRow.presetPercents)
              ChoiceChip(
                label: Text(strings.splitTipPercentChip(percent)),
                selected: !_custom && widget.basisPoints == percent * 100,
                onSelected: (_) => _choose(percent * 100),
              ),
            ChoiceChip(
              // **The chip that makes 1% reachable.** Selecting it changes no number — it reveals the
              // field, which is where the number comes from.
              label: Text(strings.splitTipCustom),
              selected: _custom,
              onSelected: (_) => setState(() => _custom = true),
            ),
            FilterChip(
              // A `FilterChip`, not a `ChoiceChip`, because it is independent: "10% and make it round" is
              // one state, and a choice chip would have forced a decision between the two.
              label: Text(strings.splitRoundUp),
              selected: widget.roundUp,
              onSelected: widget.onRoundUp,
            ),
          ],
        ),

        if (_custom) ...[
          const SizedBox(height: AlayaSpacing.sm),
          SizedBox(
            width: 108,
            child: TextField(
              controller: _field,
              // **`autofocus` kept here, and it is one of four places in the app that keeps it.** This
              // field does not exist until somebody taps **Custom %** — a tap whose only meaning is "I want
              // to type a number". Without focus that tap costs a second one, to reach a field the first
              // tap conjured.
              autofocus: true,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              // Digits and one point, so `_typed` is about range rather than shape. A tip of 12.5% is a
              // real thing to want and basis points carry it exactly.
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                LengthLimitingTextInputFormatter(5),
              ],
              style: AlayaTypography.sectionHeader,
              decoration: InputDecoration(
                isDense: true,
                suffixText: '%',
                labelText: strings.splitTipCustom,
              ),
              onChanged: _typed,
            ),
          ),
        ],

        if (base != null && total != null && total.minor != base.minor) ...[
          const SizedBox(height: AlayaSpacing.xs),
          // **Labels and figures as separate widgets, not one interpolated sentence.** Every other amount
          // in this app renders through `AmountText`, which knows the currency's symbol, its decimal
          // places and its grouping; a string built here would have reimplemented all three and got JPY
          // wrong. An earlier version of this row did exactly that, with a private `_plain` helper that
          // hardcoded a divisor.
          //
          // A `Wrap`, so the four parts reflow at 320dp with the scaler doubled rather than clipping.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AlayaSpacing.xxs,
            children: [
              Text(
                strings.splitTipAdded,
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
              AmountText(
                Money(total.minor - base.minor, base.currencyCode),
                size: AmountSize.small,
                showSign: false,
                muted: true,
                decimalDigits: widget.decimalDigits,
              ),
              Text(
                strings.splitTipTotalLabel,
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
              AmountText(
                total,
                size: AmountSize.small,
                showSign: false,
                muted: true,
                decimalDigits: widget.decimalDigits,
              ),
            ],
          ),
        ],
      ],
    );
  }
}
```

### `lib/features/split/providers/quick_split_handoff.dart`

```dart
/// Carrying a quick split through to the full screen (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/core/money/money.dart';

/// A split worked out on the home card, on its way to being named and saved.
typedef QuickSplit = ({Money total, int people, bool iPaid});

/// Hands a quick split from the home card to [SplitBillScreen].
///
/// **A provider rather than `GoRouterState.extra`, and the reason is testability.** `extra` is
/// `Object?` — the receiving builder casts and hopes — while this is typed at both ends and can be
/// overridden in a widget test without a router at all.
///
/// **Read once and cleared**, so returning to the bill screen later does not silently repopulate it
/// with a bill from an hour ago. The clear happens in the reader, not the writer, because only the
/// reader knows it has been consumed.
final quickSplitHandoffProvider =
    NotifierProvider<QuickSplitHandoff, QuickSplit?>(QuickSplitHandoff.new);

/// Holds at most one pending quick split.
class QuickSplitHandoff extends Notifier<QuickSplit?> {
  @override
  QuickSplit? build() => null;

  /// Stores [split] for the next screen to pick up.
  void offer(QuickSplit split) => state = split;

  /// Returns the pending split and forgets it.
  QuickSplit? take() {
    final pending = state;
    state = null;
    return pending;
  }
}
```

### `lib/features/split/providers/settle_up_provider.dart`

```dart
/// Recording a settlement (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/split/providers/split_providers.dart';

/// Runs a settle-up and holds why it failed.
///
/// `AsyncValue<void>` rather than a bool, so the reason survives to the sheet. *"Choose which person is
/// you"* and *"that account is in USD, not INR"* are different problems with different remedies, and
/// collapsing them into one message is what makes a sheet impossible to get past (Law U9).
final settleUpProvider = NotifierProvider<SettleUp, AsyncValue<void>>(
  SettleUp.new,
);

/// Settles a debt, in whichever direction it runs.
class SettleUp extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Records that [amount] moved between the user and [payeeId].
  ///
  /// **The direction is derived here rather than asked for.** `SettlementService.settle` takes a
  /// `from` and a `to`, and a sheet that made the caller assemble those would let a screen record a
  /// payment in the wrong direction — which is the one mistake in this module that produces a
  /// plausible-looking wrong balance rather than an error. `theyOweMe` is the only question a user can
  /// answer, and the balance row already knows it.
  ///
  /// [note] is what the ledger row will say, composed by the sheet.
  ///
  /// **Passed through rather than built here, and that is a layering point rather than a convenience.** A note
  /// is a sentence, a sentence needs the ARB, and `AlayaStrings.of(context)` needs a `BuildContext` no notifier
  /// has. `SettlementService` cannot build one either — it holds payee *ids* and a group repository, not names.
  /// So the feature decides the words and the domain records them.
  Future<bool> settle({
    required String payeeId,
    required bool theyOweMe,
    required Money amount,
    required String accountId,
    String? groupId,
    String? paymentMethodId,
    String? note,
    DateKey? on,
  }) async {
    final self = await ref.read(splitSelfProvider.future);
    if (self == null) {
      state = AsyncError<void>(
        const BusinessRuleFailure(
          'Choose which person is you before settling up.',
          rule: 'splitSelfPayeeUnset',
        ),
        StackTrace.current,
      );
      return false;
    }

    state = const AsyncLoading<void>();
    final result = await ref
        .read(settlementServiceProvider)
        .settle(
          fromPayeeId: theyOweMe ? payeeId : self,
          toPayeeId: theyOweMe ? self : payeeId,
          amount: amount,
          accountId: accountId,
          groupId: groupId,
          paymentMethodId: paymentMethodId,
          note: note,
          on: on,
        );

    final failure = result.failureOrNull;
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    state = const AsyncData(null);
    // The balance views recompute from the new rows on their own — nothing here invalidates a
    // provider, because Law L3 means there is no cached total to invalidate. That is the whole point
    // of deriving balances rather than storing them.
    return true;
  }

  /// The message from the last failure, or null.
  ///
  /// Typed, not cast: an `as dynamic` to reach `message` would compile against anything and fail at
  /// runtime the first time a non-`Failure` landed in the error slot.
  String? get lastError {
    final error = state.error;
    return error is Failure ? error.message : null;
  }
}
```

### `lib/features/split/providers/split_bill_provider.dart`

```dart
/// Recording a split from the split module's own screen (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/text/split_placeholder_names.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/services/split/split_resolver.dart';
import 'package:alaya/features/split/providers/split_providers.dart';

/// One participant as the bill screen holds them: a payee, or nobody yet.
typedef BillParticipant = ({String? payeeId, int? value, int? extra});

/// Saves a bill split from the split screen, optionally recording the expense too.
final splitBillProvider = NotifierProvider<SplitBill, AsyncValue<void>>(
  SplitBill.new,
);

/// Writes the split, the placeholders it needed, and the transaction when the user's money moved.
class SplitBill extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Records a bill, standing in for anybody who is still anonymous.
  ///
  /// **Unnamed participants become placeholder payees, and that is what lets a split save at the table.**
  /// `split_shares.payee_id` is `NOT NULL REFERENCES payees(id)`, so a debt has to be with somebody;
  /// refusing to save until every slot was named meant four contact records demanded at the moment
  /// everybody is standing up to leave. They are written as [PayeeKind.splitPlaceholder], so the row exists
  /// where balances need it and is filtered out of every list a contact belongs in.
  ///
  /// **[paidByPayeeId] defaults to the user and no longer forces them.** It used to be hardcoded to `self`,
  /// which made one arm of `v_split_balances` unreachable — that arm reports "I owe" only when the payer is
  /// somebody else, so "You owe" was structurally zero however many splits were saved. The schema, the
  /// service and the view all supported the other case; the only screen that writes never offered it.
  ///
  /// **The transaction comes first, and a failure between the two leaves the safe half.** An expense saved
  /// without its split is visible in the ledger and can be split again; a split saved against a transaction
  /// that does not exist is a debt for a payment nobody made.
  Future<bool> save({
    required Money total,
    required List<BillParticipant> participants,
    required SplitMethod method,
    required bool recordExpense,

    /// The split being replaced, or null for a new one.
    ///
    /// **`SplitExpenseService.record` has taken an id since it was written** — "supplied when re-saving an
    /// existing split, so an edit replaces rather than duplicates" — and no screen ever passed one. Editing
    /// needed no new domain code at all; it needed a caller.
    String? expenseId,
    String? paidByPayeeId,

    /// What the ledger row will say, composed by the screen.
    ///
    /// **Passed in rather than built here, because a note is a sentence and a sentence needs the ARB** — which
    /// needs a `BuildContext` this notifier does not have. The screen knows the words; this knows the writes.
    ///
    /// It lands on both the transaction and the split expense. A ledger row reading "₹5,000" with no payee and
    /// no note is the one an owner cannot identify a month later, and that row is the reason this exists.
    String? note,
    String? accountId,
    String? groupId,
    String? title,
    String? place,
    String? occasion,
    DateKey? on,
    DateKey? settleBy,
  }) async {
    state = const AsyncLoading<void>();
    final clock = ref.read(clockProvider);
    final date = on ?? clock.today();
    final self = await ref.read(splitSelfProvider.future);

    if (self == null) {
      state = AsyncError<void>(
        const BusinessRuleFailure(
          'Choose which person is you before splitting a bill.',
          rule: 'splitSelfPayeeUnset',
        ),
        StackTrace.current,
      );
      return false;
    }

    final payer = paidByPayeeId ?? self;

    final named = await _standInForEverybody(participants);
    if (named == null) {
      // `_standInForEverybody` has already put the repository's own sentence in `state`.
      return false;
    }

    String? transactionId;
    // **No transaction when somebody else paid, whatever the caller asked for.** No money left the user's
    // account, so a withdrawal would invent an outflow — and `SplitExpense.wasPaidByYou` reads
    // `transactionId != null`, so a stray one would make every screen claim they had paid. The screen
    // disables the switch as well; this is the backstop, because an invented outflow is invisible once
    // written.
    // **No new transaction when re-saving.** An edit that wrote another withdrawal would double the outflow
    // for one dinner, and the original is still in the ledger. Changing the amount of a recorded expense is
    // the expense editor's job; this screen edits the *split*.
    if (recordExpense &&
        accountId != null &&
        payer == self &&
        expenseId == null) {
      final uids = ref.read(uidGeneratorProvider);
      final created = await ref
          .read(transactionRepositoryProvider)
          .create(
            transaction: Transaction(
              id: uids.generate(),
              kind: TransactionKind.withdrawal,
              // **`otherOut`, not a guessed category.** The screen asks for a title, not a subtype, and
              // inventing one would put every shared dinner into whichever bucket seemed likeliest.
              subtype: TransactionSubtype.otherOut,
              occurredAtUtc: clock.now(),
              dateKey: date,
              // **The full bill, not the user's share.** Cash is cash: the whole amount left the account
              // whatever the split says. The share is derivable and the outflow is not, which is the
              // premise of the two analytics lenses.
              originalAmount: total,
              needsReview: false,
              fromAccountId: accountId,
              // The composed sentence when there is one, and the bare title otherwise — so a transaction is
              // never *less* legible than it was before this parameter existed.
              note: note ?? title,
            ),
          );
      if (created.isFailure) {
        state = AsyncError<void>(created.failureOrNull!, StackTrace.current);
        return false;
      }
      transactionId = created.valueOrNull!.id;
    }

    final result = await ref
        .read(splitExpenseServiceProvider)
        .record(
          id: expenseId,
          total: total,
          paidByPayeeId: payer,
          inputs: [
            for (var i = 0; i < named.length; i++)
              _inputFor(named[i], participants[i], method),
          ],
          method: method,
          transactionId: transactionId,
          groupId: groupId,
          title: title,
          place: place,
          occasion: occasion,
          // Carried onto the expense as well as the transaction: reopening a split from history shows the same
          // sentence the ledger row shows, rather than two descriptions of one evening.
          note: note,
          on: date,
          settleBy: settleBy,
        );

    final failure = result.failureOrNull;
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    state = const AsyncData(null);
    return true;
  }

  /// Resolves every participant to a payee id, creating a placeholder for anybody anonymous.
  ///
  /// Returns null when a row could not be created, having already reported why.
  ///
  /// **Numbered against every payee that exists, not against this split.** Two splits a week apart must not
  /// both produce a "Person 1" — two strangers sharing a row is a wrong balance nobody would think to
  /// check. `nextNames` continues past the highest already there, and a placeholder since renamed to "Ravi"
  /// does not free its number, because rows still reference it.
  Future<List<String>?> _standInForEverybody(
    List<BillParticipant> participants,
  ) async {
    final anonymous = <int>[
      for (var i = 0; i < participants.length; i++)
        if (participants[i].payeeId == null) i,
    ];
    if (anonymous.isEmpty) {
      return [for (final p in participants) p.payeeId!];
    }

    // **Every participant, placeholders included.** Numbering against the pickers list would reuse a number
    // already taken by a placeholder, and two shares would point at one row.
    final existing = await ref.read(splitParticipantsProvider.future);
    final names = SplitPlaceholderNames.nextNames(
      count: anonymous.length,
      existing: [for (final payee in existing) payee.name],
    );

    final uids = ref.read(uidGeneratorProvider);
    final normalizer = ref.read(normalizerProvider);
    final repository = ref.read(payeeRepositoryProvider);
    final resolved = [for (final p in participants) p.payeeId];

    for (var i = 0; i < anonymous.length; i++) {
      final saved = await repository.save(
        Payee(
          id: uids.generate(),
          name: names[i],
          normalizedName: normalizer.normalize(names[i]),
          // **`splitPlaceholder`, not `person`.** The row is real enough for a foreign key and invisible to
          // every list of contacts.
          kind: PayeeKind.splitPlaceholder,
        ),
      );
      final payee = saved.valueOrNull;
      if (payee == null) {
        state = AsyncError<void>(
          saved.failureOrNull ??
              const UnexpectedFailure('That person could not be added.'),
          StackTrace.current,
        );
        return null;
      }
      resolved[anonymous[i]] = payee.id;
    }
    return [for (final id in resolved) id!];
  }

  ShareInput _inputFor(
    String payeeId,
    BillParticipant participant,
    SplitMethod method,
  ) {
    // An extra wins over the method, and that is not a conflict: an extra says what somebody owes on top,
    // the method says how the rest divides.
    final extra = participant.extra;
    if (extra != null && extra > 0) return ShareInput.extra(payeeId, extra);
    return switch (method) {
      SplitMethod.equal => ShareInput.equal(payeeId),
      SplitMethod.shares => ShareInput.shares(payeeId, participant.value ?? 1),
      SplitMethod.percent => ShareInput.percent(
        payeeId,
        participant.value ?? 0,
      ),
      SplitMethod.exactAmounts => ShareInput.exact(
        payeeId,
        participant.value ?? 0,
      ),
      // Itemised splits come from a receipt's lines, which this screen does not have. Named so adding an
      // enum member breaks here rather than falling through — Law L13.
      SplitMethod.perLine => ShareInput.equal(payeeId),
    };
  }

  /// The message from the last failure, or null.
  String? get lastError {
    final error = state.error;
    return error is Failure ? error.message : null;
  }
}
```

### `lib/features/split/providers/split_expense_actions.dart`

```dart
/// Acting on a split that already exists (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/features/split/providers/split_history_provider.dart';
import 'package:alaya/features/split/providers/split_providers.dart';

/// Deleting a recorded split.
final splitExpenseActionsProvider =
    NotifierProvider<SplitExpenseActions, AsyncValue<void>>(
      SplitExpenseActions.new,
    );

/// Removes a split, leaving the money alone.
class SplitExpenseActions extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Deletes [id] and its shares.
  ///
  /// **Any linked transaction stays.** The money did move; deleting the split is a statement about who owed
  /// what, not about whether the payment happened. Removing the transaction too would take a real
  /// withdrawal out of the account ledger because a debt was reconsidered.
  Future<bool> remove(String id) async {
    state = const AsyncLoading<void>();
    final result = await ref.read(splitExpenseServiceProvider).remove(id);
    final failure = result.failureOrNull;
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    // Balances derive from the shares that just went; the history feed unions the expenses table. Both are
    // streams over views, and invalidating is what makes the screens behind this sheet agree with it.
    ref
      ..invalidate(splitBalancesProvider)
      ..invalidate(splitHistoryProvider);
    state = const AsyncData(null);
    return true;
  }

  /// The message from the last failure, or null.
  String? get lastError {
    final error = state.error;
    return error is Failure ? error.message : null;
  }
}
```

### `lib/features/split/providers/split_group_editor_provider.dart`

```dart
/// Saving one split group (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/text/normalizer.dart';
import 'package:alaya/domain/entities/split_group.dart';

/// Runs a group save and holds why it failed.
///
/// `AsyncValue<void>` rather than a bool, so the reason survives to the screen. A save refused for a
/// duplicate name and one refused for a member listed twice are different problems, and reporting both
/// as "something went wrong" is what makes a form unfixable (Law U9).
final splitGroupEditorProvider =
    NotifierProvider<SplitGroupEditor, AsyncValue<void>>(
      SplitGroupEditor.new,
    );

/// Validates and saves a group.
class SplitGroupEditor extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Saves the group, returning whether it committed.
  ///
  /// **Member ids are minted here, not in the screen.** A membership row's id has no meaning outside
  /// its row, and generating one per rebuild would make every keystroke look like a different member
  /// list to `saveGroup`'s delete-then-insert. Existing members keep theirs so an edit updates rather
  /// than replaces.
  Future<bool> save({
    String? id,
    required String name,
    required SplitMethod defaultSplitMethod,
    required List<({String payeeId, int? weightBasisPoints, String? memberId})>
    members,
    bool isArchived = false,
    int sortOrder = 0,
    String? note,
  }) async {
    state = const AsyncLoading<void>();
    final uids = ref.read(uidGeneratorProvider);
    final groupId = id ?? uids.generate();

    final result = await ref
        .read(splitGroupRepositoryProvider)
        .save(
          SplitGroup(
            id: groupId,
            name: name.trim(),
            // Built with `Normalizer`, so one implementation decides what "the same name" means
            // everywhere — the same reason every named entity carries a normalized form rather than
            // letting each repository invent one.
            normalizedName: const Normalizer().normalize(name),
            defaultSplitMethod: defaultSplitMethod,
            isArchived: isArchived,
            sortOrder: sortOrder,
            note: note,
            members: [
              for (var i = 0; i < members.length; i++)
                SplitMember(
                  id: members[i].memberId ?? uids.generate(),
                  groupId: groupId,
                  payeeId: members[i].payeeId,
                  defaultWeightBasisPoints: members[i].weightBasisPoints,
                  sortOrder: i,
                ),
            ],
          ),
        );

    final failure = result.failureOrNull;
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    state = const AsyncData(null);
    return true;
  }

  /// Archives or unarchives a group.
  Future<bool> setArchived({
    required String id,
    required bool isArchived,
  }) async {
    final result = await ref
        .read(splitGroupRepositoryProvider)
        .setArchived(id: id, isArchived: isArchived);
    final failure = result.failureOrNull;
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    return true;
  }

  /// Deletes a group, which the repository refuses while expenses reference it.
  Future<bool> delete(String id) async {
    final result = await ref.read(splitGroupRepositoryProvider).delete(id);
    final failure = result.failureOrNull;
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    return true;
  }

  /// The message from the last failure, or null.
  ///
  /// **Typed, not cast.** `Failure.message` is the sentence the repository wrote — *"This group has 3
  /// expense(s). Archive it instead"* names both the problem and the remedy — and an `as dynamic` to
  /// reach it would compile against anything and fail at runtime the first time a non-`Failure` landed
  /// in the error slot.
  String? get lastError {
    final error = state.error;
    return error is Failure ? error.message : null;
  }
}
```

### `lib/features/split/providers/split_history_provider.dart`

```dart
/// Everything that has happened in the split module, newest first (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/split_expense.dart';
import 'package:alaya/domain/entities/split_read_models.dart';

/// How many entries the history tab reads.
///
/// **A page size, not a guess about how much history matters.** `v_split_activity` is a `UNION ALL` over
/// two tables that only grow, with no date bound — the one read in this module that gets slower every
/// month somebody keeps using it. Fifty is roughly a screen and a half of scrolling; the contract makes
/// `limit` required precisely so a screen has to say a number out loud rather than inherit one.
const int splitHistoryPageSize = 50;

/// Expenses and settlements interleaved, across every group and none.
///
/// **`groupId: null` was already supported and nothing used it.** `watchActivity` takes a nullable group
/// and the module only ever passed one, so a split filed under no group — which is most of them, since
/// the bill screen makes a group optional — appeared on no screen at all once it was saved. The feed
/// existed, the view existed, and the only reader narrowed it to a group.
///
/// **This is where an unnamed split lives.** A participant nobody has named has a placeholder payee and
/// therefore a real balance, but a split saved and settled in one sitting leaves no balance behind — and
/// without history there was no evidence it ever happened. A ledger of decisions is not the same thing
/// as a list of who currently owes what, and the module had only the second.
final splitHistoryProvider = StreamProvider<List<SplitActivityEntry>>(
  (ref) => ref
      .watch(splitLedgerRepositoryProvider)
      .watchActivity(limit: splitHistoryPageSize),
);

/// The same feed, restricted to one group.
///
/// Kept separate from [splitHistoryProvider] rather than folded into a family with a nullable argument:
/// `family<..., String?>` would give two provider instances that look interchangeable at the call site,
/// and "the whole feed" and "this group's feed" answer different questions on different screens.
final splitGroupHistoryProvider =
    StreamProvider.family<List<SplitActivityEntry>, String>(
      (ref, groupId) => ref
          .watch(splitLedgerRepositoryProvider)
          .watchActivity(groupId: groupId, limit: splitHistoryPageSize),
    );

/// One split, with its shares, for the detail sheet.
///
/// **A stream, unlike the settle-up plan.** A plan is a snapshot of a question asked once; an expense is a
/// record that can be edited from the sheet that shows it, and a stale total sitting behind an edit the user
/// just made is the kind of thing that makes people re-check the arithmetic by hand.
///
/// `autoDispose`, because one of these exists per expense ever opened. Without it, scrolling a year of
/// history and tapping through it would leave a subscription per row for the life of the app.
final splitExpenseProvider = StreamProvider.autoDispose
    .family<SplitExpense?, String>(
      (ref, id) =>
          ref.watch(splitLedgerRepositoryProvider).watchExpenseById(id),
    );
```

### `lib/features/split/providers/split_merge_provider.dart`

```dart
/// Putting a name to an unnamed split participant (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/split/providers/split_providers.dart';

/// Resolves a placeholder into a real person, either way round.
final splitNamePlaceholderProvider =
    NotifierProvider<SplitNamePlaceholder, AsyncValue<void>>(
      SplitNamePlaceholder.new,
    );

/// The two answers to *"who is this?"*, and they are different operations.
///
/// **"Somebody you know" is a merge; "a new name" is a rename.** Both look like typing a name into a box,
/// and only one of them can be done with an `UPDATE payees SET name`. If Ravi already exists, renaming the
/// placeholder to "Ravi" leaves two Ravis — he ends up with two balances, and settling one leaves the other
/// outstanding with no explanation on screen.
class SplitNamePlaceholder extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Says this placeholder was somebody the app already knows.
  ///
  /// Every share, settlement, membership and paid-by reference moves to [payeeId] and the placeholder is
  /// retired — in one database transaction, because a half-moved identity is two debts where there should
  /// be one.
  Future<bool> mergeInto({
    required String placeholderPayeeId,
    required String payeeId,
  }) async {
    state = const AsyncLoading<void>();
    final result = await ref
        .read(splitLedgerRepositoryProvider)
        .mergePlaceholder(
          placeholderPayeeId: placeholderPayeeId,
          payeeId: payeeId,
        );
    return _settle(result.failureOrNull);
  }

  /// Says this placeholder was somebody new, called [name].
  ///
  /// **Writes `kind: person` as well as the name**, which is what takes the row out of the placeholder set
  /// and into every list a contact belongs in. Renaming alone left it hidden — the user did the right thing
  /// and the app appeared to ignore them.
  Future<bool> rename({
    required Payee placeholder,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;

    state = const AsyncLoading<void>();
    final result = await ref
        .read(payeeRepositoryProvider)
        .save(
          Payee(
            id: placeholder.id,
            name: trimmed,
            normalizedName: ref.read(normalizerProvider).normalize(trimmed),
            kind: PayeeKind.person,
            phone: placeholder.phone,
            note: placeholder.note,
          ),
        );
    return _settle(result.failureOrNull);
  }

  bool _settle(Failure? failure) {
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    // **Balances are invalidated explicitly after a merge.** `watchBalances` is a stream over
    // `v_split_balances`, which drift re-runs when a table it reads is written — and a merge writes through
    // a transaction touching `payees`, which the view *joins* rather than selects from. Relying on the
    // dependency being noticed is the kind of assumption that shows up as a screen that did not change.
    ref.invalidate(splitBalancesProvider);
    state = const AsyncData(null);
    return true;
  }

  /// The message from the last failure, or null.
  String? get lastError {
    final error = state.error;
    return error is Failure ? error.message : null;
  }
}
```

### `lib/features/split/providers/split_providers.dart`

```dart
/// View-model state for the Split module (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/currency_providers.dart'
    show homeDecimalDigitsProvider;
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/split_group.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/domain/services/split/split_balance_service.dart';

/// Every outstanding balance, worst first.
///
/// **Only counterparties with something outstanding**, so an empty list means settled up with
/// everybody rather than "nobody is configured" — which is what lets the home screen tell those two
/// apart instead of showing a success message for a setup step nobody has done.
final splitBalancesProvider = StreamProvider<List<SplitBalance>>(
  (ref) => ref.watch(splitBalanceServiceProvider).watchBalances(),
);

/// What is owed to the user and by the user, per currency.
///
/// Two figures rather than one net total. *"You are owed ₹4,000 and you owe ₹3,900"* is not the same
/// story as *"you are up ₹100"*, and per the module's first decision neither figure is spendable
/// until it arrives.
final splitTotalsProvider = FutureProvider<Map<String, ({Money owedToMe, Money iOwe})>>((
  ref,
) {
  // Rebuilt whenever a balance changes. `totals()` reads the stream once, so without this watch it
  // would hold whatever the figures were when this provider happened to be first read — a stale
  // total on a card is worse than none, because nothing on screen says it is stale.
  ref.watch(splitBalancesProvider);
  return ref.watch(splitBalanceServiceProvider).totals();
});

/// Debts old enough to be worth mentioning, oldest first.
///
/// **The nudge nobody else sends.** A due-date reminder needs a date somebody remembered to set; this
/// needs nothing, because `v_split_balances` already carries the oldest contributing expense. The day
/// count is computed against the injected `Clock` rather than in SQL — ARCH_2 §12.2 forbids a view
/// from consulting the current time, and one that did could not be asserted against a `FixedClock`.
final splitAgeingProvider = FutureProvider<List<AgeingDebt>>((ref) {
  ref.watch(splitBalancesProvider);
  return ref.watch(splitBalanceServiceProvider).ageingDebts();
});

/// Every group, archived ones included, for the groups screen.
final splitAllGroupsProvider = StreamProvider<List<SplitGroup>>(
  (ref) => ref.watch(splitGroupRepositoryProvider).watchAll(),
);

/// One group with its members, for the detail screen and the editor.
final splitGroupProvider = StreamProvider.family<SplitGroup?, String>(
  (ref, id) => ref.watch(splitGroupRepositoryProvider).watchById(id),
);

/// Who owes what within one group.
///
/// **Straight to the repository, not through `SplitBalanceService`.** That service exists for the two
/// things a view cannot do — comparing against the current date, and running the simplifier — and this
/// is neither. A method that only forwards is the indirection ARCH_1 §6 warns makes a call chain
/// unreadable for nothing.
final splitGroupBalancesProvider =
    StreamProvider.family<List<SplitBalance>, String>(
      (ref, groupId) =>
          ref.watch(splitLedgerRepositoryProvider).watchGroupBalances(groupId),
    );

/// What has happened in one group, newest first.
///
/// **`limit` is required by the contract and supplied here.** The feed is a `UNION ALL` over two
/// growing tables with no date bound — the one read in this module that gets slower every month a
/// person keeps using it — so a screen has to name a page size.
final splitGroupActivityProvider =
    StreamProvider.family<List<SplitActivityEntry>, String>(
      (ref, groupId) => ref
          .watch(splitLedgerRepositoryProvider)
          .watchActivity(groupId: groupId, limit: 50),
    );

/// The fewest payments that settle a group, one plan per currency.
///
/// **A `FutureProvider`, not a stream, and that is the honest shape.** A plan is a snapshot of a
/// question asked once — *"what is the shortest way out of this right now"* — and a live-updating plan
/// would rewrite the suggestions under a user's thumb as they act on them. Recording one settlement
/// invalidates it, which is what the screen wants: reopen and the plan reflects what is left.
final splitSettlePlansProvider =
    FutureProvider.family<List<CurrencyPlan>, String>((ref, groupId) {
      ref.watch(splitGroupBalancesProvider(groupId));
      return ref.watch(splitBalanceServiceProvider).settleUpPlans(groupId);
    });

/// Everybody who can be **chosen** for a split.
///
/// **[PayeeKind.person] only, and the exclusion of [PayeeKind.splitPlaceholder] is deliberate.** A
/// placeholder is a row this app created because a split had to name somebody; offering it as a
/// participant on the *next* split would attach two unrelated dinners to the same stranger. It is a
/// record, not a contact.
///
/// Merchants, employers and utilities are excluded for the older reason: `payees` holds shops too, and
/// offering the electricity board as somebody who owes you for dinner is how a picker teaches people
/// to distrust it.
final splitPeopleProvider = StreamProvider<List<Payee>>(
  (ref) => ref
      .watch(payeeRepositoryProvider)
      .watchAll()
      .map(
        (all) => [
          for (final payee in all)
            if (payee.kind == PayeeKind.person) payee,
        ],
      ),
);

/// Everybody who can **appear** on a split — real people and placeholders alike.
///
/// **The opposite filter to [splitPeopleProvider], and getting them the wrong way round is the trap.**
/// A balance row holds a payee id and needs a name for it; if that lookup used the pickers list, every
/// placeholder balance would resolve to null, render as "Someone", and offer no way to fix itself —
/// the exact row the rename affordance exists for.
///
/// Same source, opposite purposes: one answers *"who may I add?"*, this answers *"who is this?"*.
final splitParticipantsProvider = StreamProvider<List<Payee>>(
  (ref) => ref
      .watch(payeeRepositoryProvider)
      .watchAll()
      .map(
        (all) => [
          for (final payee in all)
            if (payee.kind == PayeeKind.person ||
                payee.kind == PayeeKind.splitPlaceholder)
              payee,
        ],
      ),
);

/// The payee the user has claimed as themselves, or null when unset.
///
/// **Null means "not configured", never "nobody".** Without it nothing can say which side of a debt
/// the user is on, so every balance would be a guess.
final splitSelfProvider = FutureProvider<String?>(
  (ref) => ref.watch(splitGroupRepositoryProvider).selfPayeeId(),
);

/// The whole payee behind an id, for a row that needs more than a name.
///
/// Reads [splitParticipantsProvider], so a placeholder resolves — see that provider's note.
final splitPayeeProvider = Provider.family<Payee?, String>((ref, payeeId) {
  final people = ref.watch(splitParticipantsProvider).valueOrNull;
  if (people == null) return null;
  for (final payee in people) {
    if (payee.id == payeeId) return payee;
  }
  return null;
});

/// Resolves a payee id to a display name, for rows that only hold ids.
///
/// Returns null for an unknown id rather than a placeholder string, so each caller decides what to
/// show — a row can fall back to a generic label while a sheet might omit the line entirely.
final splitPayeeNameProvider = Provider.family<String?, String>(
  (ref, payeeId) => ref.watch(splitPayeeProvider(payeeId))?.name,
);

/// The accounts a settlement or an expense can move through.
///
/// `watchSelectable`, not `watchAllIncludingArchived`: an archived account is one the user has
/// retired, and offering it as somewhere money just arrived would put a live balance back into a place
/// they closed.
final splitAccountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchSelectable(),
);

/// How a settlement travelled — UPI, cash, bank transfer.
final splitPaymentMethodsProvider = StreamProvider<List<PaymentMethod>>(
  (ref) => ref.watch(paymentMethodRepositoryProvider).watchAll(),
);

/// The home currency's decimal precision, so no amount hardcodes 2 (ARCH_1 §4.1).
///
/// Re-exported from `app/providers/currency_providers.dart` rather than reimplemented: two providers
/// reading the same setting is the duplication ARCH_M §6 forbids.
final splitDecimalDigitsProvider = homeDecimalDigitsProvider;

/// Today, for a date field's initial value.
///
/// Through `clockProvider` rather than `DateTime.now()`, so a widget test that pins the clock gets a
/// reproducible default.
final splitTodayProvider = Provider<DateKey>(
  (ref) => ref.watch(clockProvider).today(),
);
```

### `lib/features/split/providers/split_summary_provider.dart`

```dart
/// The shareable summary (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/data/ports/split_share_port.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/features/split/providers/split_providers.dart';

/// Where the user's payment details are stored.
///
/// **Renamed from `split.upiId`, and the rename is the feature.** A UPI id is India's rail; the value
/// this key now holds is whatever a user anywhere writes down — a PayPal link, an IBAN, a Venmo
/// handle, "cash is fine". Naming the key after one country's payment system was what made the
/// original field impossible to generalise without a migration.
///
/// No migration accompanies the rename: the old key belonged to an unreleased module and a fallback
/// read for a value that existed for one session is more code than the data is worth.
const String splitPaymentHandleKey = 'split.paymentHandle';

/// The system share sheet.
final splitShareProvider = Provider<SplitSharePort>(
  (ref) => const SystemSplitShare(),
);

/// How people can pay the user, or null when they have not said.
///
/// Free text on purpose. The app makes no claim about how money moves, which is the only way one field
/// works in every country it might be installed in.
final splitPaymentHandleProvider = FutureProvider<String?>(
  (ref) =>
      ref.watch(settingsRepositoryProvider).readValue(splitPaymentHandleKey),
);

/// The balances a summary should cover: one group, or everything outstanding.
///
/// **Balances only — the summary itself is composed in the sheet.** `SplitSummaryBuilder` needs four
/// sentences from the ARB, and `AlayaStrings` needs a `BuildContext` that no provider has. A provider
/// gathers data; a widget adds copy.
final splitSummaryBalancesProvider =
    FutureProvider.family<List<SplitBalance>, String?>((ref, groupId) {
      return groupId == null
          ? ref.watch(splitBalancesProvider.future)
          : ref.watch(splitGroupBalancesProvider(groupId).future);
    });
```

### `test/features/split/add_person_sheet_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/features/split/presentation/sheets/add_person_sheet.dart';

import '../../support/split_harness.dart';

/// [AddPersonSheet].
///
/// **This sheet exists because reusing `PayeeSheet` broke the module for a week.** That sheet defaults a
/// new payee to `PayeeKind.merchant` — correct for the expense editor, where a payee usually *is* a shop —
/// and `splitPeopleProvider` filters to persons. So everybody added from a split screen was filed as a
/// shop and never appeared: the picker was empty, Settings had nobody to claim as the user,
/// `split.selfPayeeId` stayed null, and **saving a split was impossible.** One wrong default, four steps
/// upstream of the symptom.
///
/// It also returns the id it created. `PayeeSheet.show` returns `Future<void>`, so the caller had to
/// re-read a stream after the sheet closed and diff it — a read that happens before drift has ticked, so
/// the diff was usually empty and the new person silently not selected.
void main() {
  Widget host() => const Scaffold(body: AddPersonSheet());

  group('the form', () {
    testWidgets('asks for a name and an optional phone', (tester) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('Add someone'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      // The label carries "(optional)" itself — `PayeeSheet`'s own comment records that wording as the fix
      // for a two-field sheet feeling like a form, and reusing the key means one control has one name.
      expect(find.textContaining('optional'), findsWidgets);
    });

    testWidgets('says what the phone buys, which the label does not', (
      tester,
    ) async {
      // Two people really are called the same thing, and the phone is the only field that tells them apart
      // in a picker — where it is shown *only* when a name repeats.
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.textContaining('two people share a name'), findsOneWidget);
    });

    testWidgets('refuses a blank name, and says so in the field', (
      tester,
    ) async {
      // Inline rather than in a snack: the field is the thing that is wrong, and a message floating at the
      // bottom of the screen makes somebody look for what it refers to.
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();

      expect(find.text('They need a name'), findsOneWidget);
    });

    testWidgets('a name of only spaces counts as blank', (tester) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      await tester.enterText(find.byType(TextField).first, '   ');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();

      expect(find.text('They need a name'), findsOneWidget);
    });
  });

  group('the U15 gate', () {
    testWidgets('no overflow at 320dp with the text scaler doubled', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kNarrowPhone,
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
```

### `test/features/split/name_picker_sheet_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/split/presentation/sheets/name_picker_sheet.dart';

import '../../support/split_harness.dart';

/// [NamePickerSheet].
///
/// **The rule under test is that a phone number appears exactly where a name repeats.** Two people
/// really are called the same thing, and a list showing "Priya" twice is a coin toss — but a phone
/// number beside every row is noise on the ninety-nine that are unambiguous, and noise is what stops
/// people reading a list at all. Both halves of that are asserted, because only enforcing the first
/// gives a list nobody reads.
void main() {
  /// The sheet on its own, which is how it renders inside `AlayaBottomSheet`.
  Widget host({
    required List<Payee> people,
    String? selected,
    Set<String> taken = const {},
  }) => Scaffold(
    body: NamePickerSheet(
      people: people,
      selected: selected,
      taken: taken,
    ),
  );

  group('phone numbers, used precisely', () {
    testWidgets('a unique name shows no phone', (tester) async {
      await pumpSplit(
        tester,
        host(
          people: [
            person('p1', 'Ravi', phone: '98765 43210'),
            person('p2', 'Priya', phone: '91234 56789'),
          ],
        ),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('Ravi'), findsOneWidget);
      expect(find.text('98765 43210'), findsNothing);
      expect(find.text('91234 56789'), findsNothing);
    });

    testWidgets('a repeated name shows both phones', (tester) async {
      // The only field that reliably tells them apart, shown at the only moment it is needed.
      await pumpSplit(
        tester,
        host(
          people: [
            person('p1', 'Priya', phone: '91234 56789'),
            person('p2', 'Priya', phone: '99887 76655'),
            person('p3', 'Ravi', phone: '98765 43210'),
          ],
        ),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('Priya'), findsNWidgets(2));
      expect(find.text('91234 56789'), findsOneWidget);
      expect(find.text('99887 76655'), findsOneWidget);
      // Ravi is unique, so his stays hidden even though he has one.
      expect(find.text('98765 43210'), findsNothing);
    });

    testWidgets('a repeated name with no phone degrades quietly', (
      tester,
    ) async {
      // Nothing to disambiguate with is not an error — the rows are simply identical, which is the
      // truth. Inventing a suffix like "(2)" would name somebody something they are not.
      await pumpSplit(
        tester,
        host(people: [person('p1', 'Priya'), person('p2', 'Priya')]),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('Priya'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  });

  group('people already on the split', () {
    testWidgets('are shown and disabled, not hidden', (tester) async {
      // **Hiding them is the tempting mistake.** Somebody looking for Ravi and not finding him adds a
      // second Ravi; seeing him greyed with a reason answers the question instead of raising a new one.
      await pumpSplit(
        tester,
        host(
          people: [person('p1', 'Ravi'), person('p2', 'Priya')],
          taken: const {'p1'},
        ),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('Ravi'), findsOneWidget);
      expect(find.text('Already on this split'), findsOneWidget);

      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Ravi'),
      );
      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);
    });

    testWidgets('somebody free is still tappable', (tester) async {
      await pumpSplit(
        tester,
        host(
          people: [person('p1', 'Ravi'), person('p2', 'Priya')],
          taken: const {'p1'},
        ),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Priya'),
      );
      expect(tile.enabled, isTrue);
      expect(tile.onTap, isNotNull);
    });
  });

  group('the rest of the sheet', () {
    testWidgets('the current holder is marked', (tester) async {
      await pumpSplit(
        tester,
        host(people: [person('p1', 'Ravi')], selected: 'p1'),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('an empty list says where people come from', (tester) async {
      // A blank sheet leaves somebody wondering whether it failed to load.
      await pumpSplit(
        tester,
        host(people: const []),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.byType(ListTile), findsNothing);
      expect(find.textContaining('Add people'), findsOneWidget);
    });

    testWidgets('adding somebody is always offered, even with an empty list', (
      tester,
    ) async {
      // The affordance that stops this being a dead end — the reason the whole picker exists rather
      // than a chip row that only lists what already happens to be there.
      await pumpSplit(
        tester,
        host(people: const []),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('New person'), findsOneWidget);
    });
  });

  group('the U15 gate', () {
    testWidgets('no overflow at 320dp with the text scaler doubled', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        host(
          people: [
            person(
              'p1',
              'Priyadarshini Venkataraman',
              phone: '+91 98765 43210',
            ),
            person(
              'p2',
              'Priyadarshini Venkataraman',
              phone: '+91 99887 76655',
            ),
          ],
          taken: const {'p1'},
        ),
        overrides: splitOverrides(),
        size: kNarrowPhone,
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
```

### `test/features/split/quick_split_card_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/split/presentation/widgets/quick_split_card.dart';
import 'package:alaya/features/split/providers/split_bill_provider.dart';

import '../../support/split_harness.dart';

/// One `save` that reached the provider.
typedef RecordedSave = ({
  Money total,
  List<BillParticipant> participants,
  SplitMethod method,
  bool recordExpense,
});

/// A [SplitBill] that records what it was asked to write and writes nothing.
///
/// **Overriding the notifier rather than the repositories underneath it.** `SplitBill.save` reaches
/// `payeeRepositoryProvider` and `splitExpenseServiceProvider`, neither of which the split harness
/// supplies — so pressing the button in a widget test would throw on a provider that has nothing to do
/// with what is being tested. What matters here is *what the card asks for*, and that is exactly what this
/// captures.
class _RecordingSplitBill extends SplitBill {
  final List<RecordedSave> saves = [];

  @override
  Future<bool> save({
    required Money total,
    required List<BillParticipant> participants,
    required SplitMethod method,
    required bool recordExpense,
    String? expenseId,
    String? paidByPayeeId,
    // Added when the bill screen began composing a ledger note. **A fake overriding a method must track its
    // signature exactly**, and the compiler says so — which is the third time this cycle that widening a
    // contract has broken an implementer, after `FakeSplitLedger` and two construction sites.
    String? note,
    String? accountId,
    String? groupId,
    String? title,
    String? place,
    String? occasion,
    DateKey? on,
    DateKey? settleBy,
  }) async {
    saves.add((
      total: total,
      participants: participants,
      method: method,
      recordExpense: recordExpense,
    ));
    return true;
  }
}

/// [QuickSplitCard].
///
/// **The card exists to answer a bill in three taps**, so the tests are about what appears without anybody
/// being named, about the rounding — which is where a quick calculator quietly lies — and now about saving,
/// which used to mean crossing a whole screen to confirm inputs that were already on this card.
void main() {
  /// The card as the home screen actually mounts it: inside a scrolling list.
  ///
  /// **Not a bare `Scaffold(body: card)`, which is what the first version of this file used.** At a doubled
  /// text scale the card is taller than 640dp, and with nowhere to scroll it overflowed by 191 pixels — a
  /// failure the app cannot produce, because `SplitHomeScreen` puts it in a `ListView`. A host that differs
  /// from production tests a situation nobody can reach and misses the ones they can.
  ///
  /// The vertical dimension is therefore the list's problem and the horizontal one is the card's, which is
  /// what the U15 gate below still checks.
  Widget host() => Scaffold(
    // `ListView` has no const constructor — it does list work at build time — so the `const` moves inward
    // to the children, which do. `Scaffold` being const-constructible is what made the outer one look
    // correct.
    body: ListView(children: const [QuickSplitCard()]),
  );

  Future<void> enterAmount(WidgetTester tester, String rupees) async {
    await tester.enterText(find.byType(TextField).first, rupees);
    await tester.pump();
  }

  Future<void> tapPlus(WidgetTester tester, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.widgetWithIcon(IconButton, Icons.add).first);
      await tester.pump();
    }
  }

  group('before there is an amount', () {
    testWidgets('shows a hint and no figures', (tester) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.textContaining('Type an amount'), findsOneWidget);
      expect(find.text('Each pays'), findsNothing);
      expect(find.text('Owed to you'), findsNothing);
    });
  });

  group('the split', () {
    testWidgets('divides as soon as an amount is typed', (tester) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      await enterAmount(tester, '5000');
      await tapPlus(tester, 2); // two people become four

      expect(find.text('4'), findsOneWidget);
      expect(find.textContaining('1,250'), findsWidgets);
    });

    testWidgets('the stepper never goes below two', (tester) async {
      // One person is not a split, and the card's whole premise is dividing between people.
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      final minus = find.widgetWithIcon(IconButton, Icons.remove).first;
      expect(tester.widget<IconButton>(minus).onPressed, isNull);
      expect(find.text('2'), findsOneWidget);
    });
  });

  group('who paid', () {
    testWidgets('paying it all shows what you are owed', (tester) async {
      // ₹5,000 four ways: everybody else owes ₹1,250, so ₹3,750 comes back.
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      await enterAmount(tester, '5000');
      await tapPlus(tester, 2);

      expect(find.text('Owed to you'), findsOneWidget);
      expect(find.textContaining('3,750'), findsWidgets);
    });

    testWidgets('each their own shows no debt at all', (tester) async {
      // **Showing "owed to you" here would invent a debt.** Nobody owes anybody; the division is the whole
      // answer.
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      await enterAmount(tester, '5000');
      await tester.tap(find.text('Each their own'));
      await tester.pump();

      expect(find.text('Owed to you'), findsNothing);
      expect(find.text('Each pays'), findsOneWidget);
    });

    testWidgets('defaults to having paid, because that is why you are here', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );
      await enterAmount(tester, '5000');

      expect(find.text('Owed to you'), findsOneWidget);
    });
  });

  group('the rounding, which is where a quick calculator lies', () {
    testWidgets('the payer absorbs the odd paise and the card says so', (
      tester,
    ) async {
      // ₹1,000 three ways is ₹333.33 each with one paisa left. Giving it to the payer makes "₹333.33 each"
      // true for everybody who owes — which is the sentence being read out loud.
      //
      // An earlier version showed ₹333.34 as "each pays" while computing what was owed from ₹333.33: two
      // figures describing different splits, differing by the amount nobody would notice.
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      await enterAmount(tester, '1000');
      await tapPlus(tester, 1); // three people

      expect(find.textContaining('333.33'), findsWidgets);
      expect(find.textContaining('666.66'), findsWidgets);
      expect(find.textContaining('You cover the odd'), findsOneWidget);
    });

    testWidgets('an even division says nothing about a remainder', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );
      await enterAmount(tester, '1000');

      expect(find.textContaining('You cover the odd'), findsNothing);
      expect(find.textContaining('left over'), findsNothing);
    });

    testWidgets('with no payer the leftover is named, not hidden', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      await enterAmount(tester, '1000');
      await tapPlus(tester, 1);
      await tester.tap(find.text('Each their own'));
      await tester.pump();

      expect(find.textContaining('left over'), findsOneWidget);
    });
  });

  group('saving, without leaving the screen', () {
    /// The card with a notifier that records instead of writing.
    Future<_RecordingSplitBill> pumpWithRecorder(
      WidgetTester tester, {
      String? self = 'me',
    }) async {
      final recorder = _RecordingSplitBill();
      await pumpSplit(
        tester,
        host(),
        overrides: [
          ...splitOverrides(self: self),
          splitBillProvider.overrideWith(() => recorder),
        ],
        size: kTallViewport,
      );
      return recorder;
    }

    testWidgets('is offered once you have paid a bill', (tester) async {
      // **This is #1b.** Keeping a split used to mean crossing to the bill editor to confirm inputs that
      // were already here.
      final _ = await pumpWithRecorder(tester);
      expect(find.text('Save to balances'), findsNothing);

      await enterAmount(tester, '5000');
      expect(find.text('Save to balances'), findsOneWidget);
    });

    testWidgets('is not offered when everybody pays their own', (
      tester,
    ) async {
      // No debt exists, so there is nothing to record. A button that wrote an empty split would be worse
      // than none.
      await pumpWithRecorder(tester);
      await enterAmount(tester, '5000');
      await tester.tap(find.text('Each their own'));
      await tester.pump();

      expect(find.text('Save to balances'), findsNothing);
    });

    testWidgets('is not offered before the app knows who you are', (
      tester,
    ) async {
      // A balance has no direction without `split.selfPayeeId`: nothing can say whether the others owe you
      // or you owe them, so every figure saved would be a guess.
      await pumpWithRecorder(tester, self: null);
      await enterAmount(tester, '5000');

      expect(find.text('Save to balances'), findsNothing);
    });

    testWidgets('puts you in your own split', (tester) async {
      // **The assertion that guards the over-owing bug.** Four anonymous participants with you as payer
      // means four strangers each owing a quarter — ₹5,000 owed to you on a ₹5,000 bill, when one of those
      // four *was* you. Participant one is the user; the rest are unnamed.
      final recorder = await pumpWithRecorder(tester);
      await enterAmount(tester, '5000');
      await tapPlus(tester, 2); // four people
      await tester.tap(find.text('Save to balances'));
      await tester.pump();

      expect(recorder.saves, hasLength(1));
      final save = recorder.saves.single;
      expect(save.participants, hasLength(4));
      expect(save.participants.first.payeeId, 'me');
      expect(
        save.participants.skip(1).every((p) => p.payeeId == null),
        isTrue,
      );
      expect(save.total.minor, 500000);
      expect(save.method, SplitMethod.equal);
    });

    testWidgets('records the debt and not the money', (tester) async {
      // Recording the expense needs an account, and an account picker on a three-tap card is the screen this
      // exists to avoid. The caption says so rather than leaving it to be found while reconciling.
      final recorder = await pumpWithRecorder(tester);
      await enterAmount(tester, '5000');

      // **Read before the tap, not after.** A successful save clears the card — the test below asserts
      // exactly that — so the whole result block, caption included, is gone by the time the button has been
      // pressed. Checking afterwards was two of my own tests contradicting each other.
      expect(
        find.textContaining("account balance isn't touched"),
        findsOneWidget,
      );

      await tester.tap(find.text('Save to balances'));
      await tester.pump();
      expect(recorder.saves.single.recordExpense, isFalse);
    });

    testWidgets('clears itself afterwards', (tester) async {
      // A card still showing the figures it just wrote looks like it did nothing, and the next bill gets
      // typed on top of the last one.
      await pumpWithRecorder(tester);
      await enterAmount(tester, '5000');
      await tapPlus(tester, 2);
      await tester.tap(find.text('Save to balances'));
      await tester.pump();

      expect(find.textContaining('1,250'), findsNothing);
      expect(find.text('2'), findsOneWidget);
    });
  });

  group('the way on', () {
    testWidgets('copying needs no names', (tester) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(people: []),
        size: kTallViewport,
      );
      await enterAmount(tester, '5000');

      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the fuller editor is offered once there is a result', (
      tester,
    ) async {
      // **Was "Add names", and the rename is not cosmetic.** With saving on the card, this button is the way
      // to a tip, a split method, who paid and an account — somebody wanting to add 10% would never press
      // something labelled "Add names".
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('More options'), findsNothing);
      await enterAmount(tester, '5000');
      expect(find.text('More options'), findsOneWidget);
    });
  });

  group('the U15 gate', () {
    testWidgets('no horizontal overflow at 320dp with the scaler doubled', (
      tester,
    ) async {
      // **Horizontal is the card's responsibility; vertical is the list's.** Every row pairing a label with
      // a figure is a `Wrap`, which is what this holds — a `Row` there is the shape that overran the home
      // screen by 215 pixels on the right.
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(),
        size: kNarrowPhone,
        textScale: 2,
      );

      await enterAmount(tester, '1234567');
      await tapPlus(tester, 5);
      expect(tester.takeException(), isNull);
    });
  });
}
```

### `test/features/split/split_bill_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/features/split/presentation/screens/split_bill_screen.dart';
import 'package:alaya/features/split/presentation/widgets/split_proportion_bar.dart';

import '../../support/split_harness.dart';

/// [SplitBillScreen].
///
/// **The property under test is that arithmetic and saving both work before anybody is named.** An
/// earlier version made you create four payee records before you could divide a restaurant bill, and
/// then refused to save until every slot was named — four contact records demanded at the moment
/// everybody is standing up to leave.
///
/// **A participant's label appears twice once there is a result** — once on their row, once in the
/// proportion bar's legend. So the finders below scope to one or the other rather than counting: a
/// bare `findsNWidgets(2)` would pass if both matches were legend rows and the person's own row had
/// vanished.
void main() {
  Future<void> enterAmount(WidgetTester tester, String rupees) async {
    await tester.enterText(find.byType(TextField).first, rupees);
    await tester.pump();
  }

  Future<void> tapPlus(WidgetTester tester, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.widgetWithIcon(IconButton, Icons.add).first);
      await tester.pump();
    }
  }

  /// The label as it appears on a participant's own row, not in the bar's legend.
  Finder onRow(String label) => find.descendant(
    of: find.byType(ListView),
    matching: find.byWidgetPredicate(
      (w) => w is Text && w.data == label && w.style?.fontStyle != null,
    ),
  );

  /// The label as it appears in the bar's legend.
  Finder inLegend(String label) => find.descendant(
    of: find.byType(SplitProportionBar),
    matching: find.text(label),
  );

  FloatingActionButton saveButton(WidgetTester tester) =>
      tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));

  group('it works with nobody named', () {
    testWidgets('opens with you and one anonymous person', (tester) async {
      // **This asserted two placeholders and the model was wrong.** "Two of us" means you and somebody
      // else, so the first slot is claimed for the user — otherwise splitting ₹5,000 four ways produced
      // four strangers owing ₹1,250 each, ₹5,000 owed to you, when one of those four *was* you. Nothing
      // contradicted it because the "I owe" arm of the balance view was unreachable.
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('You'), findsWidgets);
      expect(find.text('Person 2'), findsOneWidget);
      // No amount yet, so no result and no bar to repeat the labels in.
      expect(find.byType(SplitProportionBar), findsNothing);
    });

    testWidgets('divides a bill with no payees in the database at all', (
      tester,
    ) async {
      // `splitOverrides()` supplies an empty people list, so nothing exists to pick from — and the
      // figures still appear.
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(people: []),
        size: kTallViewport,
      );

      await enterAmount(tester, '1000');
      await tapPlus(tester, 2); // two people become four

      expect(onRow('Person 4'), findsOneWidget);
      expect(inLegend('Person 4'), findsOneWidget);
      expect(find.textContaining('250'), findsWidgets);
      expect(find.text('25%'), findsNWidgets(4));
    });

    testWidgets('the stepper never goes below one person', (tester) async {
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      final minus = find.widgetWithIcon(IconButton, Icons.remove).first;
      await tester.tap(minus);
      await tester.pump();
      // Down to one, and the one left is you — slots are removed from the end, so the first stays.
      expect(find.text('You'), findsWidgets);
      expect(find.text('Person 2'), findsNothing);

      // Disabled at one: zero participants is not a split, and the resolver refuses it — so the
      // control refuses first rather than letting a rebuild throw.
      expect(tester.widget<IconButton>(minus).onPressed, isNull);
    });

    testWidgets('removing a person keeps the earlier slots', (tester) async {
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      await tapPlus(tester, 2);
      expect(find.text('Person 4'), findsOneWidget);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.remove).first);
      await tester.pump();

      // Removed from the end, so a name already assigned to Person 1 stays on Person 1.
      expect(find.text('Person 3'), findsOneWidget);
      expect(find.text('Person 4'), findsNothing);
    });
  });

  group('saving does not need names', () {
    testWidgets('the save button works with everybody anonymous', (
      tester,
    ) async {
      // **This assertion was the exact opposite two commits ago**, and the old one was wrong: it
      // encoded "name four people before you may save" as though it were a rule rather than a
      // limitation of `split_shares.payee_id` being NOT NULL. `SplitBill.save` now creates a person
      // for anybody anonymous, so the constraint is satisfied without the user doing the work.
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(people: []),
        size: kTallViewport,
      );
      await enterAmount(tester, '1000');

      expect(saveButton(tester).onPressed, isNotNull);
    });

    testWidgets('says where the unnamed will land rather than blocking', (
      tester,
    ) async {
      // Information, not a wall. It used to read "Name 2 more people to save this" beside a dead
      // button; it now says what will happen and that the name is fixable.
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );
      await enterAmount(tester, '1000');

      // One, not two: the first slot is you. Matched on the word rather than the count, because the ARB
      // pluralises and a test asserting "1 person is unnamed" would break again the moment the copy
      // changed number.
      expect(find.textContaining('unnamed'), findsOneWidget);
      expect(find.textContaining('rename them any time'), findsOneWidget);
    });

    testWidgets('the notice disappears once everybody is named', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(
          groups: [
            splitGroup('g1', 'Flatmates', members: ['p1', 'p2']),
          ],
          people: [person('p1', 'Ravi'), person('p2', 'Priya')],
        ),
        size: kTallViewport,
      );
      await enterAmount(tester, '1000');
      expect(find.textContaining('unnamed'), findsOneWidget);

      // Applying a group fills every slot with a real person.
      await tester.tap(find.text('No group'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flatmates').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('unnamed'), findsNothing);
    });

    testWidgets('an amount is still required', (tester) async {
      // There is nothing to save without one — the resolver returns null and the bar draws nothing.
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(saveButton(tester).onPressed, isNull);
    });

    testWidgets('knowing which person you are is still required', (
      tester,
    ) async {
      // **The one gate that stays.** Without `split.selfPayeeId` a balance has no direction: nothing
      // can say whether the others owe you or you owe them, so every figure saved would be a guess.
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(self: null),
        size: kTallViewport,
      );
      await enterAmount(tester, '1000');

      expect(saveButton(tester).onPressed, isNull);
      expect(find.textContaining('Choose which person is you'), findsOneWidget);
    });

    testWidgets('copying the result never needs a name either', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(people: []),
        size: kTallViewport,
      );
      await enterAmount(tester, '1000');

      final copy = find.textContaining('Copy the result');
      expect(copy, findsOneWidget);
      await tester.tap(copy);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('the tip', () {
    testWidgets('is added to the bill before it is divided', (tester) async {
      // ₹1,000 plus 10% is ₹1,100, two ways is ₹550 each. Dividing first and adding a tip per person
      // reaches the same total here by luck and a different one the moment the split is unequal.
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      await enterAmount(tester, '1000');
      await tester.tap(find.text('10% tip'));
      await tester.pump();

      expect(find.textContaining('550'), findsWidgets);
      expect(find.text('Adding'), findsOneWidget);
    });

    testWidgets('tapping the chosen tip again clears it', (tester) async {
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      await enterAmount(tester, '1000');
      await tester.tap(find.text('10% tip'));
      await tester.pump();
      expect(find.text('Adding'), findsOneWidget);

      await tester.tap(find.text('10% tip'));
      await tester.pump();
      expect(find.text('Adding'), findsNothing);
      expect(find.textContaining('500'), findsWidgets);
    });

    testWidgets('no tip means no extra line', (tester) async {
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );
      await enterAmount(tester, '1000');

      expect(find.text('Adding'), findsNothing);
    });
  });

  group('the picture', () {
    testWidgets('appears only once there is something to draw', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );
      expect(find.byType(SplitProportionBar), findsNothing);

      await enterAmount(tester, '1000');
      expect(find.byType(SplitProportionBar), findsOneWidget);
    });
  });

  group('the methods', () {
    testWidgets('equal offers no per-person field', (tester) async {
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );
      await enterAmount(tester, '1000');

      // Only the title field is a `TextFormField` while the split is equal — a weight box per person
      // would be three controls asking a question nobody has.
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('shares reveals a weight box per person', (tester) async {
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );
      await enterAmount(tester, '1000');
      await tester.tap(find.text('By shares'));
      await tester.pump();

      // Two participants plus the title field.
      expect(find.byType(TextFormField), findsNWidgets(3));
    });
  });

  group('extras — the restaurant case', () {
    testWidgets('an extra field appears on the row that asks for it', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );
      await enterAmount(tester, '5000');

      expect(find.text('Extra'), findsNWidgets(2));
      await tester.tap(find.text('Extra').first);
      await tester.pump();

      expect(find.text('Just for them'), findsOneWidget);
      // The row that opened one no longer offers to.
      expect(find.text('Extra'), findsOneWidget);
    });
  });

  group('groups', () {
    testWidgets('saving as a group is the one thing that still needs names', (
      tester,
    ) async {
      // A group's members are `payees` rows meant to be reused, and a placeholder is not somebody you
      // meant to keep — so this button waits for two real names even though saving no longer does.
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(people: [person('p1', 'Ravi')]),
        size: kTallViewport,
      );
      await enterAmount(tester, '1000');

      expect(find.textContaining('as a group'), findsNothing);
    });
  });

  group('the U15 gate', () {
    testWidgets('no overflow at 320dp with the text scaler doubled', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        const SplitBillScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Ravi'), person('p2', 'Priyadarshini')],
        ),
        size: kNarrowPhone,
        textScale: 2,
      );
      await enterAmount(tester, '5000');
      await tester.tap(find.text('15% tip'));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
```

### `test/features/split/split_group_detail_sheet_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/features/split/presentation/sheets/split_group_detail_sheet.dart';
import 'package:alaya/features/split/providers/split_providers.dart';

import '../../support/split_harness.dart';

/// [SplitGroupDetailSheet].
///
/// **Was `/split/groups/:groupId`, the second level of a stack behind a tab.** Nothing on it was an
/// editor — it read balances and offered three actions — so the route bought a back arrow, an app bar with
/// three competing targets, and somewhere for a user to end up without knowing how. The screen it replaces
/// had no test either; these are the first assertions this content has ever had.
void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    required List<String> members,
    List<Override> balances = const [],
    Size size = kTallViewport,
    double textScale = 1,
  }) => pumpSplit(
    tester,
    const Scaffold(body: SplitGroupDetailSheet(groupId: 'g1')),
    overrides: [
      ...splitOverrides(
        people: [person('p1', 'Ravi'), person('p2', 'Priya')],
      ),
      splitGroupProvider('g1').overrideWith(
        (ref) => Stream.value(
          splitGroup('g1', 'Flatmates', members: members),
        ),
      ),
      ...balances,
    ],
    size: size,
    textScale: textScale,
  );

  /// Feeds one group's balances.
  ///
  /// **Typed `List<SplitBalance>`, not `List<Object>` with a cast.** The first draft took `Object` and used
  /// `as dynamic` to satisfy the override — which compiles against anything and would have failed at
  /// runtime the moment the provider's element type changed. `as dynamic` to make a call compile means the
  /// call is wrong, and this file is not exempt from that.
  Override groupBalances(List<SplitBalance> rows) =>
      splitGroupBalancesProvider('g1').overrideWith(
        (ref) => Stream.value(rows),
      );

  group('what it shows', () {
    testWidgets('names the group and counts its members', (tester) async {
      await pumpSheet(tester, members: ['p1', 'p2']);

      expect(find.text('Flatmates'), findsOneWidget);
      expect(find.text('2 people'), findsOneWidget);
    });

    testWidgets('settled is said plainly, not left as blank space', (
      tester,
    ) async {
      // An empty area where balances would be reads as a sheet that failed to load half of itself.
      await pumpSheet(tester, members: ['p1', 'p2']);

      expect(find.text('All settled up'), findsOneWidget);
    });

    testWidgets('a balance carries its direction in words', (tester) async {
      // **Not in colour.** `AmountText` has no tone parameter — it colours from `kind`, deliberately, so
      // one movement of money never renders as two different things — and a sentence survives a screenshot
      // and a colour-blind reader.
      await pumpSheet(
        tester,
        members: ['p1', 'p2'],
        balances: [
          groupBalances([owedToMe('p1', 185000)]),
        ],
      );

      expect(find.text('Ravi'), findsOneWidget);
      expect(find.textContaining('owes you'), findsOneWidget);
    });

    testWidgets('shows no activity feed', (tester) async {
      // **The screen this replaces rendered the group's activity too.** The History tab shows every
      // group's at once now, and keeping both made the sheet long enough to scroll past the actions —
      // which are the reason somebody opened it.
      await pumpSheet(
        tester,
        members: ['p1'],
        balances: [
          groupBalances([owedToMe('p1', 185000)]),
        ],
      );

      expect(find.textContaining('Activity'), findsNothing);
    });
  });

  group('the actions', () {
    testWidgets('settling is the emphasised one', (tester) async {
      // Share and Edit are things you do *to* a group; settling is why you looked.
      await pumpSheet(tester, members: ['p1', 'p2']);

      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNWidgets(2));
    });

    testWidgets('offers share and edit without competing for the title', (
      tester,
    ) async {
      await pumpSheet(tester, members: ['p1', 'p2']);

      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('adds no scaffold, app bar or floating button', (tester) async {
      // It is a sheet now. `pumpSheet` supplies the only `Scaffold`; anything more means this content
      // brought its screen chrome with it.
      await pumpSheet(tester, members: ['p1']);

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });

  group('the U15 gate', () {
    testWidgets('no overflow at 320dp with the text scaler doubled', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        members: ['p1', 'p2'],
        balances: [
          groupBalances([owedToMe('p1', 12345678)]),
        ],
        size: kNarrowPhone,
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
```

### `test/features/split/split_group_editor_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/split_group.dart';
import 'package:alaya/features/split/presentation/screens/split_group_editor_screen.dart';
import 'package:alaya/features/split/providers/split_providers.dart';

import '../../support/split_harness.dart';

/// [SplitGroupEditorScreen].
///
/// **The screen where default weights are set**, which is what makes "flatmates, 40/30/30" one tap
/// next month instead of four numbers retyped. Everything below is about the two rules that make that
/// safe: weights are all-or-nothing, and a group with expenses cannot be deleted.
void main() {
  /// Feeds one saved group to the editor.
  ///
  /// `splitGroupProvider` is a family, so the override has to name the same argument the screen will
  /// watch — override the wrong id and the screen sits on a real (unoverridden) provider and hangs in
  /// its loading branch, which looks like a broken test rather than a wrong override.
  List<Override> withGroup(
    SplitGroup group, {
    List<String> people = const [],
  }) => [
    ...splitOverrides(
      people: [for (final id in people) person(id, id.toUpperCase())],
    ),
    splitGroupProvider(group.id).overrideWith((ref) => Stream.value(group)),
  ];

  group('a new group', () {
    testWidgets('opens with a name field and the people to choose from', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        const SplitGroupEditorScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Ravi'), person('p2', 'Priya')],
        ),
        size: kTallViewport,
      );

      expect(find.text('New group'), findsOneWidget);
      expect(find.text('Ravi'), findsOneWidget);
      expect(find.text('Priya'), findsOneWidget);
    });

    testWidgets('cannot be saved without a name', (tester) async {
      // A group is found by its name everywhere else in the module; an unnamed one would be a row
      // nobody could pick from a dropdown.
      await pumpSplit(
        tester,
        const SplitGroupEditorScreen(),
        overrides: splitOverrides(people: [person('p1', 'Ravi')]),
        size: kTallViewport,
      );

      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(save.onPressed, isNull);
    });

    testWidgets('offers no archive switch and no delete', (tester) async {
      // Neither means anything before the group exists. Showing them greyed would be two controls
      // explaining themselves instead of a form.
      await pumpSplit(
        tester,
        const SplitGroupEditorScreen(),
        overrides: splitOverrides(people: [person('p1', 'Ravi')]),
        size: kTallViewport,
      );

      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('names where people come from when there are none', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        const SplitGroupEditorScreen(),
        overrides: splitOverrides(people: []),
        size: kTallViewport,
      );

      expect(find.byType(FilterChip), findsNothing);
      expect(find.textContaining('Add people'), findsOneWidget);
    });
  });

  group('an existing group', () {
    testWidgets('adopts its name and its members', (tester) async {
      await pumpSplit(
        tester,
        const SplitGroupEditorScreen(groupId: 'g1'),
        overrides: withGroup(
          splitGroup('g1', 'Flatmates', members: ['p1', 'p2']),
          people: ['p1', 'p2'],
        ),
        size: kTallViewport,
      );

      expect(find.text('Flatmates'), findsOneWidget);
      final chips = tester.widgetList<FilterChip>(find.byType(FilterChip));
      expect(chips.where((c) => c.selected).length, 2);
    });

    testWidgets('offers archiving, and says it is not deleting', (
      tester,
    ) async {
      // The subtitle is where that distinction becomes usable rather than a rule in a document.
      await pumpSplit(
        tester,
        const SplitGroupEditorScreen(groupId: 'g1'),
        overrides: withGroup(
          splitGroup('g1', 'Flatmates', members: ['p1']),
          people: ['p1'],
        ),
        size: kTallViewport,
      );

      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(find.textContaining('history'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('shows a weight box per member once anybody is on it', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        const SplitGroupEditorScreen(groupId: 'g1'),
        overrides: withGroup(
          splitGroup(
            'g1',
            'Flatmates',
            members: ['p1', 'p2', 'p3'],
            weights: {'p1': 4000, 'p2': 3000, 'p3': 3000},
          ),
          people: ['p1', 'p2', 'p3'],
        ),
        size: kTallViewport,
      );

      // Basis points are stored; whole percent is typed. 4000 reads as 40.
      expect(find.text('40'), findsOneWidget);
      expect(find.text('30'), findsNWidgets(2));
    });
  });

  group('weights are all or nothing', () {
    testWidgets('a partly weighted group says so', (tester) async {
      // **A partial set prefills nothing**, because treating the unweighted member as weightless would
      // invent an instruction — "she did not eat" is a real thing to mean and must never be inferred
      // from a blank field. Somebody who filled three of four boxes needs telling before they save,
      // not when next month's split comes out equal.
      await pumpSplit(
        tester,
        const SplitGroupEditorScreen(groupId: 'g1'),
        overrides: withGroup(
          splitGroup(
            'g1',
            'Flatmates',
            members: ['p1', 'p2', 'p3'],
            weights: {'p1': 5000, 'p2': 5000},
          ),
          people: ['p1', 'p2', 'p3'],
        ),
        size: kTallViewport,
      );

      expect(find.text('Set a share for everybody, or none'), findsOneWidget);
    });

    testWidgets('a fully weighted group does not', (tester) async {
      await pumpSplit(
        tester,
        const SplitGroupEditorScreen(groupId: 'g1'),
        overrides: withGroup(
          splitGroup(
            'g1',
            'Flatmates',
            members: ['p1', 'p2'],
            weights: {'p1': 6000, 'p2': 4000},
          ),
          people: ['p1', 'p2'],
        ),
        size: kTallViewport,
      );

      expect(find.text('Set a share for everybody, or none'), findsNothing);
    });

    testWidgets('a group with no weights at all does not', (tester) async {
      await pumpSplit(
        tester,
        const SplitGroupEditorScreen(groupId: 'g1'),
        overrides: withGroup(
          splitGroup('g1', 'Flatmates', members: ['p1', 'p2']),
          people: ['p1', 'p2'],
        ),
        size: kTallViewport,
      );

      expect(find.text('Set a share for everybody, or none'), findsNothing);
    });
  });

  group('the U15 gate', () {
    testWidgets('no overflow at 320dp with the text scaler doubled', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        const SplitGroupEditorScreen(groupId: 'g1'),
        overrides: [
          ...splitOverrides(
            people: [
              person('p1', 'Priyadarshini Venkataraman'),
              person('p2', 'Ravi'),
            ],
          ),
          splitGroupProvider('g1').overrideWith(
            (ref) => Stream.value(
              splitGroup(
                'g1',
                'Bandra flatmates and the Goa regulars',
                members: ['p1', 'p2'],
                weights: {'p1': 6000, 'p2': 4000},
              ),
            ),
          ),
        ],
        size: kNarrowPhone,
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
```

### `test/features/split/split_groups_list_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/features/split/presentation/widgets/split_groups_list.dart';

import '../../support/split_harness.dart';

/// [SplitGroupsList].
///
/// **Replaces `split_groups_screen_test.dart`.** The screen it tested is gone — the list is a tab on
/// `/split` and a row opens a bottom sheet rather than pushing a route. Every assertion below is one the
/// old file made; only the widget under test and the chrome around it changed.
void main() {
  /// The list as the home screen mounts it: a tab body inside a `Scaffold` the shell owns.
  Widget host() => const Scaffold(body: SplitGroupsList());

  group('the list', () {
    testWidgets('names each group and counts its members', (tester) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(
          groups: [
            splitGroup('g1', 'Flatmates', members: ['p1', 'p2', 'p3']),
            splitGroup('g2', 'Goa trip', members: ['p1', 'p2']),
          ],
        ),
        size: kTallViewport,
      );

      expect(find.text('Flatmates'), findsOneWidget);
      expect(find.text('3 people'), findsOneWidget);
      expect(find.text('2 people'), findsOneWidget);
    });

    testWidgets('says what a group will do before it is used', (tester) async {
      // A group carrying 40/30/30 behaves differently from one that splits equally, and that is worth
      // knowing from the list rather than after opening the editor.
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(
          groups: [
            splitGroup(
              'g1',
              'Flatmates',
              members: ['p1', 'p2'],
              weights: {'p1': 6000, 'p2': 4000},
            ),
            splitGroup('g2', 'Goa trip', members: ['p1', 'p2']),
          ],
        ),
        size: kTallViewport,
      );

      expect(find.text('Custom shares'), findsOneWidget);
    });

    testWidgets('an archived group is shown greyed, not hidden', (
      tester,
    ) async {
      // **Hiding it is the tempting mistake.** Archiving keeps a group's history and its balances and
      // only removes it from the pickers; hiding it here makes "where did my flatmates group go"
      // unanswerable from the one place that exists to answer it.
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(
          groups: [
            splitGroup('g1', 'Old trip', members: ['p1'], archived: true),
          ],
        ),
        size: kTallViewport,
      );

      expect(find.text('Old trip'), findsOneWidget);
      expect(find.text('Archived'), findsOneWidget);
    });
  });

  group('empty', () {
    testWidgets('explains what a group buys rather than saying "none"', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(groups: []),
        size: kTallViewport,
      );

      expect(find.text('No groups yet'), findsOneWidget);
      expect(
        find.textContaining('saves entering the same people'),
        findsOneWidget,
      );
    });

    testWidgets('making one is still offered when the list is empty', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(groups: []),
        size: kTallViewport,
      );

      expect(find.text('New group'), findsOneWidget);
    });
  });

  group('the chrome it no longer owns', () {
    testWidgets('adds no app bar and no floating button', (tester) async {
      // **It was a screen with both.** As a tab it may have neither: the app bar belongs to
      // `_ShellScaffold`, and a FAB placed here would hover over the Balances tab too — the wrong action
      // in the wrong place. "New group" is a button above the list instead.
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(
          groups: [
            splitGroup('g1', 'Flatmates', members: ['p1']),
          ],
        ),
        size: kTallViewport,
      );

      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });

  group('the U15 gate', () {
    testWidgets('a long name with both chips does not overflow', (
      tester,
    ) async {
      // **This is the case that was broken.** The row was a `Row(Expanded, chip, chip)` — three children
      // that cannot shrink — which is the shape that overran the split home screen by 215 pixels. An
      // archived group with custom shares carries both chips at once, so it is the worst one.
      await pumpSplit(
        tester,
        host(),
        overrides: splitOverrides(
          groups: [
            splitGroup(
              'g1',
              'Bandra flatmates and the Goa regulars',
              members: ['p1', 'p2', 'p3', 'p4'],
              weights: {'p1': 4000, 'p2': 2000, 'p3': 2000, 'p4': 2000},
              archived: true,
            ),
          ],
        ),
        size: kNarrowPhone,
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
```

### `test/features/split/split_history_list_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/features/split/presentation/widgets/split_history_list.dart';
import 'package:alaya/features/split/providers/split_history_provider.dart';

import '../../support/split_harness.dart';

/// [SplitHistoryList].
///
/// **A balance list is not a record of what happened**, and until this existed the module had only the
/// first. A split settled the same evening left no balance behind and therefore no evidence at all —
/// somebody who divided a restaurant bill, was paid back in cash, and looked a week later found an empty
/// screen and had to trust their memory over the app.
void main() {
  SplitActivityEntry entry({
    required String id,
    required SplitActivityKind kind,
    required int dateKey,
    required int minor,
    required String payeeId,
    String? label,
    String? groupId,
  }) => SplitActivityEntry(
    refId: id,
    kind: kind,
    dateKey: DateKey(dateKey),
    amount: Money(minor, 'INR'),
    payeeId: payeeId,
    label: label,
    groupId: groupId,
  );

  /// The list plus a feed for it. The harness does not override the history providers, because most split
  /// screens do not read them — a test that needs one says so.
  Future<void> pumpHistory(
    WidgetTester tester,
    List<SplitActivityEntry> feed, {
    String? groupId,
    Size size = kTallViewport,
    double textScale = 1,
  }) => pumpSplit(
    tester,
    Scaffold(body: SplitHistoryList(groupId: groupId)),
    overrides: [
      ...splitOverrides(people: [person('p1', 'Ravi'), person('p2', 'Priya')]),
      splitHistoryProvider.overrideWith((ref) => Stream.value(feed)),
      if (groupId != null)
        splitGroupHistoryProvider(groupId).overrideWith(
          (ref) => Stream.value(feed),
        ),
    ],
    size: size,
    textScale: textScale,
  );

  group('the feed', () {
    testWidgets('shows expenses and settlements together', (tester) async {
      // **A `UNION ALL` over two tables, not an events table.** Two subsystems writing into a shared feed
      // is a synchronisation-bug factory; a view has no synchronisation code to get wrong (anomaly A37).
      await pumpHistory(tester, [
        entry(
          id: 'e1',
          kind: SplitActivityKind.expense,
          dateKey: 20260814,
          minor: 500000,
          payeeId: 'p1',
          label: 'Dinner at Olive',
        ),
        entry(
          id: 's1',
          kind: SplitActivityKind.settlement,
          dateKey: 20260814,
          minor: 125000,
          payeeId: 'p2',
        ),
      ]);

      expect(find.text('Dinner at Olive'), findsOneWidget);
      expect(find.text('Priya settled up'), findsOneWidget);
    });

    testWidgets('names a row by whatever the user actually typed', (
      tester,
    ) async {
      // The view coalesces title, occasion, place and note, so the row is labelled by whichever the user
      // filled in — and falls back to the sentence about the payer rather than to a blank line.
      await pumpHistory(tester, [
        entry(
          id: 'e1',
          kind: SplitActivityKind.expense,
          dateKey: 20260814,
          minor: 500000,
          payeeId: 'p1',
          label: 'Diwali',
        ),
        entry(
          id: 'e2',
          kind: SplitActivityKind.expense,
          dateKey: 20260814,
          minor: 200000,
          payeeId: 'p1',
        ),
      ]);

      expect(find.text('Diwali'), findsOneWidget);
      // Two rows, two occurrences, for different reasons: the labelled one carries "Ravi paid" as its
      // caption under "Diwali", and the unlabelled one carries it as its title with no caption at all.
      expect(find.text('Ravi paid'), findsNWidgets(2));
    });

    testWidgets('a blank label is treated as none, and said once', (
      tester,
    ) async {
      // **This is what caught the duplication.** A row with no usable label used the payer sentence as
      // both its title and its caption, so "Ravi paid" appeared twice — 15pt above 12pt grey. The caption
      // now only renders when it has something different to say.
      await pumpHistory(tester, [
        entry(
          id: 'e1',
          kind: SplitActivityKind.expense,
          dateKey: 20260814,
          minor: 500000,
          payeeId: 'p1',
          label: '   ',
        ),
      ]);

      expect(find.text('Ravi paid'), findsOneWidget);
    });

    testWidgets('groups entries by day, newest day first', (tester) async {
      // The same shape the transaction ledger uses: a flat list of amounts with dates beside them makes
      // "what did we spend on Saturday" a scanning exercise, and a date header turns it into a glance.
      await pumpHistory(tester, [
        entry(
          id: 'e1',
          kind: SplitActivityKind.expense,
          dateKey: 20260814,
          minor: 500000,
          payeeId: 'p1',
          label: 'Today',
        ),
        entry(
          id: 'e2',
          kind: SplitActivityKind.expense,
          dateKey: 20260813,
          minor: 300000,
          payeeId: 'p1',
          label: 'Yesterday',
        ),
        entry(
          id: 'e3',
          kind: SplitActivityKind.expense,
          dateKey: 20260813,
          minor: 100000,
          payeeId: 'p2',
          label: 'Also yesterday',
        ),
      ]);

      // Two dates, three rows — the second date carries two of them. Asserted on the labels rather than on
      // a header widget type, because the grouping is a fact about what a reader sees and not about which
      // widget draws the date.
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Also yesterday'), findsOneWidget);
    });
  });

  group('scope', () {
    testWidgets('null shows everything, including ungrouped splits', (
      tester,
    ) async {
      // **`watchActivity` always took a nullable group and nothing ever passed null**, so a split filed
      // under no group — most of them, since the bill screen makes a group optional — appeared on no
      // screen at all once saved. The capability existed and had no caller.
      await pumpHistory(tester, [
        entry(
          id: 'e1',
          kind: SplitActivityKind.expense,
          dateKey: 20260814,
          minor: 500000,
          payeeId: 'p1',
          label: 'No group at all',
        ),
      ]);

      expect(find.text('No group at all'), findsOneWidget);
    });

    testWidgets('a group id reads the group-scoped provider instead', (
      tester,
    ) async {
      await pumpHistory(
        tester,
        [
          entry(
            id: 'e1',
            kind: SplitActivityKind.expense,
            dateKey: 20260814,
            minor: 500000,
            payeeId: 'p1',
            label: 'Flat rent',
            groupId: 'g1',
          ),
        ],
        groupId: 'g1',
      );

      expect(find.text('Flat rent'), findsOneWidget);
    });
  });

  group('empty', () {
    testWidgets('names what would fill it rather than counting nothing', (
      tester,
    ) async {
      // An empty history is the normal state of a new install, not a problem to solve.
      await pumpHistory(tester, const []);

      expect(find.text('Nothing split yet'), findsOneWidget);
      expect(find.textContaining('newest first'), findsOneWidget);
    });
  });

  group('the U15 gate', () {
    testWidgets('no overflow at 320dp with the text scaler doubled', (
      tester,
    ) async {
      await pumpHistory(
        tester,
        [
          entry(
            id: 'e1',
            kind: SplitActivityKind.expense,
            dateKey: 20260814,
            minor: 12345678,
            payeeId: 'p1',
            label: 'Bandra flatmates and the Goa regulars, September',
          ),
        ],
        size: kNarrowPhone,
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
```

### `test/features/split/split_home_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/split/presentation/screens/split_home_screen.dart';
import 'package:alaya/features/split/presentation/widgets/quick_split_card.dart';
import 'package:alaya/features/split/presentation/widgets/split_groups_list.dart';
import 'package:alaya/features/split/presentation/widgets/split_history_list.dart';

import '../../support/split_harness.dart';

/// [SplitHomeScreen].
///
/// **The first assertion is that there is only one app bar**, because there were two. This screen sits
/// inside the drawer shell, which owns the `Scaffold` and the `AppBar`; the first version wrapped itself
/// in a second `Scaffold` and stacked a bar with a back arrow under the real one, on a destination nobody
/// navigates *into*.
///
/// **The setup-card tests are gone rather than repaired.** `SplitSetupCard` asked who the user is, here,
/// because nothing in the module worked without it. Onboarding's first step asks now — so the assertions
/// below are that the card is *absent* and the escape for somebody who skipped is present, which is the
/// opposite of what they used to say and the correct thing to pin.
///
/// **A section header renders `label.toUpperCase()`**, with the original casing kept only as its
/// `semanticsLabel`. So a header is matched by its upper-case form and a body label by its own.
void main() {
  group('the shell owns the chrome', () {
    testWidgets('the screen adds no app bar of its own', (tester) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(),
      );

      // `pumpInShell` provides exactly one, standing in for `_ShellScaffold`. A second means the screen
      // brought its own back.
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('the screen adds no scaffold and no floating button', (
      tester,
    ) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(),
      );
      expect(find.byType(Scaffold), findsOneWidget);
      // A FAB would belong to the shell, and one placed here would hover over the Groups tab too — the
      // wrong action in the wrong place. "Create a split" is a button in content instead.
      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });

  group('three tabs, one destination', () {
    testWidgets('offers Balances, History and Groups', (tester) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('Balances'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Groups'), findsOneWidget);
    });

    testWidgets('Balances is the tab you land on', (tester) async {
      // It answers the question people open the app with, and the quick splitter sits at the top of it so
      // dividing a bill stays zero taps from arriving.
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.byType(QuickSplitCard), findsOneWidget);
      expect(find.byType(SplitHistoryList), findsNothing);
      expect(find.byType(SplitGroupsList), findsNothing);
    });

    testWidgets('History is a tap away, not a route', (tester) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      expect(find.byType(SplitHistoryList), findsOneWidget);
    });

    testWidgets('Groups is a tab, not the screen it was', (tester) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(
          groups: [
            splitGroup('g1', 'Flatmates', members: ['p1']),
          ],
        ),
        size: kTallViewport,
      );

      await tester.tap(find.text('Groups'));
      await tester.pumpAndSettle();

      expect(find.byType(SplitGroupsList), findsOneWidget);
      expect(find.text('Flatmates'), findsOneWidget);
    });
  });

  group('who the user is, asked elsewhere now', () {
    testWidgets('the screen no longer asks', (tester) async {
      // **`SplitSetupCard` used to be here** and is deleted: onboarding's first step asks the same
      // question before Split is ever opened, so the common path never reaches this state at all.
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(self: null),
        size: kTallViewport,
      );

      expect(find.textContaining('What should we call you'), findsNothing);
    });

    testWidgets('somebody who skipped is given a way out', (tester) async {
      // The name step is optional — archetype B makes the whole flow skippable — so declining has to leave
      // a route to answering later. One tap to a settings branch, rather than the four-screen chain this
      // used to be.
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(self: null),
        size: kTallViewport,
      );

      expect(find.text('Who are you?'), findsOneWidget);
      expect(find.text('Shared expenses'), findsOneWidget);
    });

    testWidgets('the calculator works without knowing who you are', (
      tester,
    ) async {
      // Dividing a bill needs no identity. Hiding it behind setup would be friction charged for nothing.
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(self: null),
        size: kTallViewport,
      );

      expect(find.byType(QuickSplitCard), findsOneWidget);
    });
  });

  group('two empty states, because they mean opposite things', () {
    testWidgets('settled up says so', (tester) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(self: 'me'),
        size: kTallViewport,
      );

      expect(find.text('All settled up'), findsOneWidget);
    });

    testWidgets('an unset self payee is a setup step, not a success', (
      tester,
    ) async {
      // Showing "all settled up" when nothing has been measured would tell somebody they were square with
      // everybody, which is a lie the screen can easily tell and never should.
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(self: null),
        size: kTallViewport,
      );

      expect(find.text('All settled up'), findsNothing);
      expect(find.text('Who are you?'), findsOneWidget);
    });
  });

  group('balances', () {
    testWidgets('each direction gets its own section', (tester) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Ravi'), person('p2', 'Priya')],
          balances: [owedToMe('p1', 185000), iOwe('p2', 40000)],
        ),
        size: kTallViewport,
      );

      expect(find.text('Ravi'), findsOneWidget);
      expect(find.text('Priya'), findsOneWidget);

      // Upper case for the headers, because `SectionHeader` shouts its label; mixed case for the totals
      // card, which is body copy. Direction is carried by *which* section a row sits under, since
      // `AmountText` has no tone parameter and a colour does not survive a screenshot.
      expect(find.text('OWED TO YOU'), findsOneWidget);
      expect(find.text('YOU OWE'), findsOneWidget);
      expect(find.text('Owed to you'), findsOneWidget);
      expect(find.text('You owe'), findsOneWidget);
    });

    testWidgets('a placeholder is offered a name where it is read', (
      tester,
    ) async {
      // **The row somebody will want to fix the moment they see it.** Saving a split writes a
      // `PayeeKind.splitPlaceholder` for anybody anonymous so the debt can exist at all, and this is where
      // that gets corrected — read from `kind`, so a real contact called "Person 5" is never offered a
      // rename it does not need.
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(
          placeholders: [placeholder('p9', 'Person 4')],
          balances: [owedToMe('p9', 125000)],
        ),
        size: kTallViewport,
      );

      expect(find.text('Person 4'), findsOneWidget);
      expect(find.text('Who is this?'), findsOneWidget);
    });

    testWidgets('a real person is not offered one', (tester) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Person 5')],
          balances: [owedToMe('p1', 125000)],
        ),
        size: kTallViewport,
      );

      expect(find.text('Person 5'), findsOneWidget);
      expect(find.text('Who is this?'), findsNothing);
    });

    testWidgets('an old debt says how old', (tester) async {
      // The nudge no competitor sends. It needs no due date — the balance view already carries the oldest
      // contributing expense, and the day count is computed against the injected clock.
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Ravi')],
          balances: [owedToMe('p1', 185000, since: const DateKey(20260714))],
          today: const DateKey(20260814),
        ),
        size: kTallViewport,
      );

      expect(find.text('31 days'), findsOneWidget);
    });

    testWidgets('a recent debt is not nagged about', (tester) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Ravi')],
          balances: [owedToMe('p1', 185000, since: const DateKey(20260812))],
          today: const DateKey(20260814),
        ),
        size: kTallViewport,
      );

      expect(find.textContaining('days'), findsNothing);
    });
  });

  group('the actions', () {
    testWidgets('creating a split is offered on the screen itself', (
      tester,
    ) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('Create a split'), findsOneWidget);
    });

    testWidgets('sharing is disabled when there is nothing to share', (
      tester,
    ) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(balances: []),
        size: kTallViewport,
      );

      final share = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Share'),
      );
      expect(share.onPressed, isNull);
    });

    testWidgets('sharing is offered once somebody owes something', (
      tester,
    ) async {
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Ravi')],
          balances: [owedToMe('p1', 185000)],
        ),
        size: kTallViewport,
      );

      final share = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Share'),
      );
      expect(share.onPressed, isNotNull);
    });
  });

  group('the U15 gate', () {
    testWidgets('no overflow at 320dp with the text scaler doubled', (
      tester,
    ) async {
      // **This one found a real bug.** `Row(Expanded(name), AmountText)` cannot shrink an amount below its
      // own text, so ₹1,23,456.78 at 2.0 overran by 215 pixels. Every row that pairs text with a figure is
      // a `Wrap` now, and this is what holds that.
      await pumpInShell(
        tester,
        const SplitHomeScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Priyadarshini Venkataraman')],
          balances: [
            owedToMe('p1', 12345678, since: const DateKey(20260601)),
          ],
        ),
        size: kNarrowPhone,
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
```

### `test/features/split/split_settings_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/features/settings/presentation/screens/split_settings_screen.dart';

import '../../support/split_harness.dart';

/// [SplitSettingsScreen].
///
/// **This screen changed role rather than shrinking.** It used to be the only place `split.selfPayeeId`
/// could be set, which made it the destination of a redirect chain: three split screens noticed the
/// setting was missing and pointed here, at a list of candidates that was empty because adding somebody
/// from anywhere filed them as a merchant.
///
/// Onboarding asks the name now, first, before Split is ever opened. So this is what a settings branch
/// should be — somewhere to *change* a decision, not to make one — and the assertions below are about
/// that, not about first-run behaviour it no longer owns.
void main() {
  group('choosing who you are', () {
    testWidgets('lists everybody who could be you', (tester) async {
      await pumpSplit(
        tester,
        const SplitSettingsScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Ravi'), person('p2', 'Priya')],
        ),
        size: kTallViewport,
      );

      expect(find.text('Ravi'), findsOneWidget);
      expect(find.text('Priya'), findsOneWidget);
      expect(find.byType(RadioListTile<String>), findsNWidgets(2));
    });

    testWidgets('placeholders are not offered as candidates', (tester) async {
      // **A placeholder is a row this app wrote, not somebody you could be.** `splitPeopleProvider`
      // filters to `PayeeKind.person`, and the harness feeds placeholders only to
      // `splitParticipantsProvider` — the same split the app makes, so the test cannot pass for the wrong
      // reason.
      await pumpSplit(
        tester,
        const SplitSettingsScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Ravi')],
          placeholders: [placeholder('p9', 'Person 4')],
        ),
        size: kTallViewport,
      );

      expect(find.text('Ravi'), findsOneWidget);
      expect(find.text('Person 4'), findsNothing);
      expect(find.byType(RadioListTile<String>), findsOneWidget);
    });

    testWidgets('marks the current choice', (tester) async {
      await pumpSplit(
        tester,
        const SplitSettingsScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Ravi'), person('p2', 'Priya')],
          self: 'p2',
        ),
        size: kTallViewport,
      );

      final tiles = tester
          .widgetList<RadioListTile<String>>(find.byType(RadioListTile<String>))
          .toList();
      // Asserted on the widget's own state rather than on a painted dot, which a theme could change.
      expect(tiles.where((t) => t.value == t.groupValue).length, 1);
      expect(tiles.firstWhere((t) => t.value == 'p2').groupValue, 'p2');
    });

    testWidgets('names the prerequisite when nobody exists yet', (
      tester,
    ) async {
      // Names what to do instead of showing a blank area. A person has to exist as a payee before they
      // can be claimed, and saying so beats an empty list the reader has to interpret.
      await pumpSplit(
        tester,
        const SplitSettingsScreen(),
        overrides: splitOverrides(people: []),
        size: kTallViewport,
      );

      expect(find.byType(RadioListTile<String>), findsNothing);
      expect(find.textContaining('Add people under Payees'), findsOneWidget);
    });

    testWidgets('adding somebody is offered even with an empty list', (
      tester,
    ) async {
      // Through `AddPersonSheet`, not `PayeeSheet`: the shared sheet defaults a new payee to
      // `PayeeKind.merchant`, so anybody added from here used to vanish from the very list that sent them
      // to add somebody.
      await pumpSplit(
        tester,
        const SplitSettingsScreen(),
        overrides: splitOverrides(people: []),
        size: kTallViewport,
      );

      expect(find.text('Add person'), findsOneWidget);
    });
  });

  group('how people can pay you', () {
    testWidgets('is free text with no assumptions about a country', (
      tester,
    ) async {
      // **The field used to be a UPI id with an email keyboard**, which quietly assumed India. It now
      // holds a PayPal link, an IBAN, a Venmo handle or a sentence, so there is nothing to validate and no
      // keyboard hint that would be wrong somewhere.
      await pumpSplit(
        tester,
        const SplitSettingsScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('Payment details'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autocorrect, isFalse);
      // Room for an IBAN, which does not fit on one line at any sensible width.
      expect(field.maxLines, 2);
    });

    testWidgets('says what it buys rather than what it is', (tester) async {
      await pumpSplit(
        tester,
        const SplitSettingsScreen(),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(
        find.textContaining('added to the end of any summary'),
        findsOneWidget,
      );
    });
  });

  group('what it no longer links to', () {
    testWidgets('offers no route to Groups', (tester) async {
      // **This assertion is the inverse of the one it replaces.** Groups are a tab on `/split` now, and a
      // settings branch offering a shortcut into a tab of another destination is the cross-linking that
      // made this module a maze — seven routes where two would do. The screen has no navigation left in
      // it at all, which is why it no longer imports `go_router`.
      await pumpSplit(
        tester,
        const SplitSettingsScreen(),
        overrides: splitOverrides(
          people: [person('p1', 'Ravi')],
          groups: [
            splitGroup('g1', 'Flatmates', members: ['p1']),
          ],
        ),
        size: kTallViewport,
      );

      expect(find.text('Groups'), findsNothing);
      expect(find.text('Flatmates'), findsNothing);
    });
  });

  group('the U15 gate', () {
    testWidgets('no overflow at 320dp with the text scaler doubled', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        const SplitSettingsScreen(),
        overrides: splitOverrides(
          people: [
            person('p1', 'Priyadarshini Venkataraman'),
            person('p2', 'Ravi'),
          ],
          self: 'p1',
        ),
        size: kNarrowPhone,
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
```

### `test/features/split/split_visuals_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/money/money.dart';
import 'package:alaya/features/split/presentation/widgets/split_proportion_bar.dart';
import 'package:alaya/features/split/presentation/widgets/split_tip_row.dart';

import '../../support/split_harness.dart';

/// [SplitProportionBar] and [SplitTipRow].
void main() {
  Money inr(int minor) => Money(minor, 'INR');

  group('the tip arithmetic', () {
    test('is a percentage of the bill, rounded half up', () {
      // ₹4,763 at 10% is ₹476.30 exactly; at 5% it is ₹238.15, which is where a truncating
      // implementation would quietly lose a paisa.
      expect(SplitTipRow.tipOn(inr(476300), 1000), inr(47630));
      expect(SplitTipRow.tipOn(inr(476300), 500), inr(23815));
      expect(SplitTipRow.tipOn(inr(476300), 0), inr(0));
    });

    test('adds to the bill rather than to each share', () {
      // **The only reading that survives "so what did we actually pay".** Dividing first and adding a
      // tip per person happens to agree when the split is equal and disagrees the moment it is not.
      expect(
        SplitTipRow.totalFor(
          base: inr(476300),
          basisPoints: 1000,
          roundUp: false,
          decimalDigits: 2,
        ),
        inr(523930),
      );
    });

    test('rounds up to the next ten, not the next whole unit', () {
      // ₹5,239.30 to ₹5,240 removes the paise and leaves an awkward number. ₹5,240 is the figure
      // somebody says out loud.
      expect(
        SplitTipRow.totalFor(
          base: inr(476300),
          basisPoints: 1000,
          roundUp: true,
          decimalDigits: 2,
        ),
        inr(524000),
      );
    });

    test('rounding a total already on the step leaves it alone', () {
      expect(
        SplitTipRow.totalFor(
          base: inr(500000),
          basisPoints: 0,
          roundUp: true,
          decimalDigits: 2,
        ),
        inr(500000),
      );
    });

    test('the step follows the currency, not the rupee', () {
      // Ten yen, not ten thousand. A zero-decimal currency has no minor units to absorb the difference.
      expect(SplitTipRow.stepFor(2), 1000);
      expect(SplitTipRow.stepFor(0), 10);
    });
  });

  group('the proportion bar', () {
    testWidgets('draws a segment and a legend row per person', (tester) async {
      await pumpSplit(
        tester,
        Scaffold(
          body: SplitProportionBar(
            slices: [
              ProportionSlice(label: 'Person 1', amount: inr(105000)),
              ProportionSlice(
                label: 'Ravi',
                amount: inr(185000),
                extra: inr(80000),
              ),
              ProportionSlice(label: 'Person 3', amount: inr(105000)),
              ProportionSlice(label: 'Person 4', amount: inr(105000)),
            ],
            total: inr(500000),
            decimalDigits: 2,
          ),
        ),
        overrides: splitOverrides(),
        size: kTallViewport,
      );

      expect(find.text('Ravi'), findsOneWidget);
      // 1,850 of 5,000 is 37%; the other three are 21% each.
      expect(find.text('37%'), findsOneWidget);
      expect(find.text('21%'), findsNWidgets(3));
    });

    testWidgets('renders nothing when there is nothing to scale against', (
      tester,
    ) async {
      // A zero total would divide by zero on the way to a flex, so the guard is the widget's own.
      await pumpSplit(
        tester,
        Scaffold(
          body: SplitProportionBar(
            slices: [ProportionSlice(label: 'A', amount: inr(100))],
            total: inr(0),
            decimalDigits: 2,
          ),
        ),
        overrides: splitOverrides(),
      );

      expect(find.text('A'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at 320dp with the text scaler doubled', (
      tester,
    ) async {
      await pumpSplit(
        tester,
        Scaffold(
          body: SplitProportionBar(
            slices: [
              ProportionSlice(
                label: 'Priyadarshini Venkataraman',
                amount: inr(12345678),
                extra: inr(9999),
              ),
              ProportionSlice(label: 'B', amount: inr(1)),
            ],
            total: inr(12355677),
            decimalDigits: 2,
          ),
        ),
        overrides: splitOverrides(),
        size: kNarrowPhone,
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
```
