import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/settings/presentation/widgets/tag_scope_labels.dart';
import 'package:alaya/features/settings/providers/tag_settings_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Settings › Tags (ARCH_5 §3 archetype D, outside the shell).
///
/// **The scoping matrix is the point of this screen, not decoration on it.** `tags.allowedIn*` is what stops
/// "Kitchen" appearing in the deposit editor's tag picker — a tag scoped to inventory only has no business being
/// offered when somebody records their salary. Every row therefore states its scopes as chips, because a scope
/// that is only visible after opening the editor is one nobody will notice is wrong.
///
/// **A tag with no scopes at all is called out**, not silently listed. It cannot appear anywhere in the app, so
/// it is invisible everywhere except this screen — exactly the kind of dead row a user would spend time hunting
/// for in the pickers before thinking to come here.
///
/// **One level of nesting, and a child is grouped under its top-most ancestor.** ARCH_2 sets no depth limit, but
/// a deeper tree cannot be shown in a picker without indenting past the width of a phone. Flattening keeps a
/// grandchild reachable rather than lost.
class TagsSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const TagsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final tags = ref.watch(tagsSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsTags)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.tagNew),
        tooltip: strings.tagsAdd,
        child: const Icon(Icons.add, size: AlayaIconSize.lg),
      ),
      body: tags.when(
        loading: () => AlayaListSkeleton(label: strings.tagsLoading),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(tagsSettingsProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return EmptyState(
              title: strings.tagsEmptyTitle,
              body: strings.tagsEmptyBody,
              icon: Icons.sell_outlined,
              actionLabel: strings.tagsAdd,
              onAction: () => context.push(Routes.tagNew),
            );
          }
          final tree = ref.watch(tagTreeProvider);
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
            itemCount: tree.length,
            itemBuilder: (context, index) {
              final branch = tree[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TagRow(tag: branch.parent),
                  for (final child in branch.children)
                    _TagRow(tag: child, nested: true),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// One tag: its colour, its name, and where it is allowed to appear.
class _TagRow extends StatelessWidget {
  const _TagRow({required this.tag, this.nested = false});

  final Tag tag;
  final bool nested;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final theme = Theme.of(context);
    final scopes = tag.allowedScopes;

    return ListTile(
      contentPadding: EdgeInsets.only(
        // Indented once and no further, which is the visible half of the one-level rule.
        left: AlayaSpacing.screenEdge + (nested ? AlayaSpacing.lg : 0),
        right: AlayaSpacing.screenEdge,
      ),
      leading: Container(
        width: AlayaSpacing.md,
        height: AlayaSpacing.md,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tag.colorArgb == null
              ? theme.colorScheme.outlineVariant
              : Color(tag.colorArgb!),
        ),
      ),
      title: Row(
        children: [
          Expanded(child: Text(tag.name, style: AlayaTypography.cardTitle)),
          if (tag.isSystem) ...[
            const SizedBox(width: AlayaSpacing.xs),
            // A system tag can be re-scoped and recoloured but not deleted, and saying so on the row saves the
            // trip into an editor whose delete button is missing for no stated reason.
            StatusChip(label: strings.tagsSystemChip, tone: StatusTone.neutral),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AlayaSpacing.xxs),
        child: scopes.isEmpty
            ? Text(
                strings.tagsNoScopesWarning,
                style: AlayaTypography.caption.copyWith(
                  color: semantic.warning,
                ),
              )
            : Wrap(
                spacing: AlayaSpacing.xxs,
                runSpacing: AlayaSpacing.xxs,
                children: [
                  for (final scope in TagScope.values)
                    if (scopes.contains(scope))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AlayaSpacing.xs,
                          vertical: AlayaSpacing.xxs / 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: AlayaRadii.borderSm,
                        ),
                        child: Text(
                          tagScopeLabel(strings, scope),
                          style: AlayaTypography.overline.copyWith(
                            color: semantic.muted,
                          ),
                        ),
                      ),
                ],
              ),
      ),
      onTap: () => context.push(Routes.tagEdit(tag.id)),
    );
  }
}
