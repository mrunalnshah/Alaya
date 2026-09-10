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
