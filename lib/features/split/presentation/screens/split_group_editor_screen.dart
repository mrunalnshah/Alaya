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
