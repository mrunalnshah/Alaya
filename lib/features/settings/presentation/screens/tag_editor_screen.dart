import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/settings/presentation/widgets/tag_scope_labels.dart';
import 'package:alaya/features/settings/providers/tag_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Creating or editing one tag (ARCH_5 §3 archetype B).
///
/// **This is where `tags.allowedIn*` and `tags.parentTagId` are actually set**, and the two §7.2 rows they
/// represent close here. The matrix is six switches with a line each saying what unticking one would do, because
/// "Withdrawal" on its own tells the reader nothing about *why* a tag would vanish from the screen they use most.
///
/// **A tag scoped nowhere is warned about, not forbidden.** ARCH_2 permits an empty scope set and somebody may
/// well want to park a tag they are not using; inventing a constraint the schema does not have would be worse
/// than saying plainly that the tag will not appear anywhere.
class TagEditorScreen extends ConsumerStatefulWidget {
  /// Creates the editor. [tagId] null means a new tag.
  const TagEditorScreen({this.tagId, super.key});

  /// The tag being edited, or null for a new one.
  final String? tagId;

  @override
  ConsumerState<TagEditorScreen> createState() => _TagEditorScreenState();
}

class _TagEditorScreenState extends ConsumerState<TagEditorScreen> {
  final _name = TextEditingController();
  Set<TagScope> _scopes = {};
  String? _parentId;
  int? _colorArgb;
  int _sortOrder = 0;
  bool _isSystem = false;
  bool _dirty = false;
  bool _loaded = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _adopt(Tag? tag) {
    if (_loaded) return;
    _loaded = true;
    if (tag == null) {
      // A new tag starts scoped to the two money pickers rather than to nothing. Somebody adding a tag almost
      // always means to use it on a transaction, and an empty set would make their first act invisible.
      _scopes = {TagScope.deposit, TagScope.withdrawal};
      return;
    }
    _name.text = tag.name;
    _scopes = {...tag.allowedScopes};
    _parentId = tag.parentTagId;
    _colorArgb = tag.colorArgb;
    _sortOrder = tag.sortOrder;
    _isSystem = tag.isSystem;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final draft = ref.watch(tagDraftProvider(widget.tagId));
    final editing = ref.watch(tagEditorProvider);

    return draft.when(
      loading: () => _shell(strings, const SizedBox.shrink()),
      error: (error, stack) => _shell(
        strings,
        ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(tagDraftProvider(widget.tagId)),
        ),
      ),
      data: (tag) {
        if (widget.tagId != null && tag == null) {
          return _shell(
            strings,
            ErrorState(
              title: strings.tagsMissingTitle,
              body: strings.tagsMissingBody,
              retryLabel: strings.actionBack,
              onRetry: () => context.pop(),
            ),
          );
        }
        _adopt(tag);
        final parents = ref.watch(tagParentChoicesProvider(widget.tagId));
        final theme = Theme.of(context);
        final swatches = <int>[
          theme.colorScheme.primary.toARGB32(),
          theme.colorScheme.secondary.toARGB32(),
          theme.colorScheme.tertiary.toARGB32(),
          theme.colorScheme.primaryContainer.toARGB32(),
          theme.colorScheme.secondaryContainer.toARGB32(),
          theme.colorScheme.tertiaryContainer.toARGB32(),
        ];

        return _shell(
          strings,
          AlayaFormScaffold(
            primaryLabel: strings.tagEditorSave,
            onPrimary: _name.text.trim().isEmpty || editing.isLoading
                ? null
                : () => _save(tag),
            isDirty: _dirty,
            isSubmitting: editing.isLoading,
            discardTitle: strings.confirmDiscardTitle,
            discardBody: strings.confirmDiscardBody,
            discardConfirmLabel: strings.actionDiscard,
            discardCancelLabel: strings.actionKeepEditing,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  autofocus: tag == null,
                  decoration: InputDecoration(labelText: strings.tagNameLabel),
                  onChanged: (_) => setState(() => _dirty = true),
                ),
                const SizedBox(height: AlayaSpacing.lg),
                SectionHeader(label: strings.tagColourHeader),
                const SizedBox(height: AlayaSpacing.xxs),
                // **The swatches come from the live palette; the stored value is a frozen int.** `colorArgb` is
                // a column, so a tag coloured under one preset keeps that colour if the user later switches
                // palettes. Storing a palette *role* would follow the theme, but the schema stores an int and
                // inventing a second encoding in the UI would put two meanings in one column.
                Text(
                  strings.tagColourHelp,
                  style: AlayaTypography.caption.copyWith(
                    color: context.semantic.muted,
                  ),
                ),
                const SizedBox(height: AlayaSpacing.xs),
                Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xs,
                  children: [
                    _Swatch(
                      color: theme.colorScheme.outlineVariant,
                      selected: _colorArgb == null,
                      semanticLabel: strings.tagColourNone,
                      onTap: () => setState(() {
                        _colorArgb = null;
                        _dirty = true;
                      }),
                    ),
                    for (final argb in swatches)
                      _Swatch(
                        color: Color(argb),
                        selected: _colorArgb == argb,
                        semanticLabel: strings.tagColourSwatch,
                        onTap: () => setState(() {
                          _colorArgb = argb;
                          _dirty = true;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: AlayaSpacing.lg),
                SectionHeader(label: strings.tagParentHeader),
                const SizedBox(height: AlayaSpacing.xxs),
                Text(
                  strings.tagParentHelp,
                  style: AlayaTypography.caption.copyWith(
                    color: context.semantic.muted,
                  ),
                ),
                const SizedBox(height: AlayaSpacing.xs),
                Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xs,
                  children: [
                    ChoiceChip(
                      label: Text(
                        strings.tagParentNone,
                        style: AlayaTypography.button,
                      ),
                      selected: _parentId == null,
                      onSelected: (_) => setState(() {
                        _parentId = null;
                        _dirty = true;
                      }),
                    ),
                    // Already filtered to exclude this tag and everything beneath it, so the picker cannot build
                    // a cycle — the constraint lives where the choice is made.
                    for (final parent in parents)
                      ChoiceChip(
                        label: Text(parent.name, style: AlayaTypography.button),
                        selected: parent.id == _parentId,
                        onSelected: (_) => setState(() {
                          _parentId = parent.id;
                          _dirty = true;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: AlayaSpacing.lg),
                SectionHeader(label: strings.tagScopesHeader),
                const SizedBox(height: AlayaSpacing.xxs),
                Text(
                  strings.tagScopesHelp,
                  style: AlayaTypography.caption.copyWith(
                    color: context.semantic.muted,
                  ),
                ),
                if (_scopes.isEmpty) ...[
                  const SizedBox(height: AlayaSpacing.sm),
                  Container(
                    padding: const EdgeInsets.all(AlayaSpacing.md),
                    decoration: BoxDecoration(
                      color: context.semantic.warning.withValues(alpha: 0.12),
                      borderRadius: AlayaRadii.borderMd,
                    ),
                    child: Text(
                      strings.tagsNoScopesWarning,
                      style: AlayaTypography.bodyEmphasis,
                    ),
                  ),
                ],
                const SizedBox(height: AlayaSpacing.xs),
                for (final scope in TagScope.values)
                  SwitchListTile(
                    value: _scopes.contains(scope),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      tagScopeLabel(strings, scope),
                      style: AlayaTypography.body,
                    ),
                    subtitle: Text(
                      tagScopeHelp(strings, scope),
                      style: AlayaTypography.caption.copyWith(
                        color: context.semantic.muted,
                      ),
                    ),
                    onChanged: (on) => setState(() {
                      final next = {..._scopes};
                      if (on) {
                        next.add(scope);
                      } else {
                        next.remove(scope);
                      }
                      _scopes = next;
                      _dirty = true;
                    }),
                  ),
                if (tag != null && !_isSystem) ...[
                  const SizedBox(height: AlayaSpacing.xl),
                  OutlinedButton(
                    onPressed: editing.isLoading ? null : () => _delete(tag),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.semantic.danger,
                    ),
                    child: Text(
                      strings.tagsDelete,
                      style: AlayaTypography.button,
                    ),
                  ),
                  const SizedBox(height: AlayaSpacing.xxs),
                  Text(
                    strings.tagsDeleteHelp,
                    style: AlayaTypography.caption.copyWith(
                      color: context.semantic.muted,
                    ),
                  ),
                ],
                if (editing.hasError) ...[
                  const SizedBox(height: AlayaSpacing.md),
                  Text(
                    editing.error.toString(),
                    style: AlayaTypography.body.copyWith(
                      color: context.semantic.danger,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _shell(AlayaStrings strings, Widget body) => Scaffold(
    appBar: AppBar(
      leading: const CloseButton(),
      title: Text(
        widget.tagId == null
            ? strings.tagEditorTitle
            : strings.tagEditorEditTitle,
      ),
    ),
    body: body,
  );

  Future<void> _save(Tag? existing) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref
        .read(tagEditorProvider.notifier)
        .save(
          id: existing?.id,
          name: _name.text,
          allowedScopes: _scopes,
          sortOrder: _sortOrder,
          parentTagId: _parentId,
          colorArgb: _colorArgb,
          isSystem: _isSystem,
        );
    if (!mounted || !saved) return;
    showResultSnack(context, message: strings.tagsSaved);
    context.pop();
  }

  Future<void> _delete(Tag tag) async {
    final strings = AlayaStrings.of(context);
    // The body says what survives, because a soft delete is not what "delete" usually promises: the transactions
    // that carried this tag keep their history, and only the tag leaves the pickers (ARCH_3 §4).
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.tagsDeleteConfirmTitle,
      body: strings.tagsDeleteConfirmBody,
      confirmLabel: strings.tagsDelete,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final ok = await ref.read(tagEditorProvider.notifier).delete(tag.id);
    if (!mounted || !ok) return;
    showResultSnack(context, message: strings.tagsDeleted);
    context.pop();
  }
}

/// One colour choice.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.semanticLabel,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AlayaSpacing.minTapTarget),
        // A full tap target around a small dot: the swatch reads at 24dp and is touchable at 48 (Law U3).
        child: SizedBox(
          width: AlayaSpacing.minTapTarget,
          height: AlayaSpacing.minTapTarget,
          child: Center(
            child: Container(
              width: AlayaSpacing.xl,
              height: AlayaSpacing.xl,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(color: theme.colorScheme.onSurface, width: 3)
                    : null,
              ),
              child: selected
                  ? Icon(
                      Icons.check,
                      size: AlayaIconSize.sm,
                      color: theme.colorScheme.surface,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
