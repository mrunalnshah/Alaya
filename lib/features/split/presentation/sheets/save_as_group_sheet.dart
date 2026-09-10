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
