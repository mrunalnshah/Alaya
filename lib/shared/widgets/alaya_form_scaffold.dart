import 'dart:async';

import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';

/// The body of every editor screen (ARCH_5 §3 archetype B).
///
/// Three things that every form needs and that every form otherwise reimplements slightly
/// differently:
///
/// 1. **A scrolling body.** Law U2 — a screen with a text input has a scroll ancestor, or it
///    overflows the moment a keyboard opens at a raised text scale.
/// 2. **A sticky footer holding the commit.** Law U14 — an app-bar "Save" is a stretch on a 6.7"
///    phone held one-handed, and this app is used one-handed. The footer sits above the keyboard
///    because the enclosing `Scaffold` resizes; the screen must therefore **not** set
///    `resizeToAvoidBottomInset: false`.
/// 3. **An unsaved-changes guard.** Law U10 — dismissing an editor with edits in it prompts, and a
///    rejected save leaves every field populated.
///
/// The screen supplies `Scaffold(appBar: …, body: AlayaFormScaffold(…))` and owns its own state;
/// this widget owns none of it.
class AlayaFormScaffold extends StatelessWidget {
  /// Creates a form body committing through [onPrimary].
  const AlayaFormScaffold({
    required this.child,
    required this.primaryLabel,
    required this.onPrimary,
    required this.discardTitle,
    required this.discardBody,
    required this.discardConfirmLabel,
    required this.discardCancelLabel,
    this.secondaryLabel,
    this.onSecondary,
    this.isDirty = false,
    this.isSubmitting = false,
    this.padding = const EdgeInsets.fromLTRB(
      AlayaSpacing.screenEdge,
      AlayaSpacing.md,
      AlayaSpacing.screenEdge,
      AlayaSpacing.xxl,
    ),
    super.key,
  });

  /// The form's fields and sections.
  final Widget child;

  /// The commit button's label, already localised. Names the action — "Save expense", not "Save".
  final String primaryLabel;

  /// The commit. Null disables the button, which is how an invalid form reports itself.
  final VoidCallback? onPrimary;

  /// Title of the discard prompt.
  final String discardTitle;

  /// Body of the discard prompt. Says what will be lost.
  final String discardBody;

  /// The discard prompt's confirm label — the destructive one.
  final String discardConfirmLabel;

  /// The discard prompt's cancel label, which returns to the form.
  final String discardCancelLabel;

  /// An optional secondary action's label.
  final String? secondaryLabel;

  /// The secondary action.
  final VoidCallback? onSecondary;

  /// Whether the form holds unsaved edits. Drives the guard.
  final bool isDirty;

  /// Whether a save is in flight. Disables both actions and shows progress on the primary.
  final bool isSubmitting;

  /// Padding around [child], inside the scroll view.
  final EdgeInsetsGeometry padding;

  Future<void> _confirmDiscard(BuildContext context) async {
    final navigator = Navigator.of(context);
    final discard = await ConfirmSheet.show(
      context,
      title: discardTitle,
      body: discardBody,
      confirmLabel: discardConfirmLabel,
      cancelLabel: discardCancelLabel,
      destructive: true,
    );
    if (discard && navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final blocked = isDirty || isSubmitting;
    return PopScope<Object?>(
      canPop: !blocked,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || isSubmitting) return;
        unawaited(_confirmDiscard(context));
      },
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: padding,
              child: child,
            ),
          ),
          _FormFooter(
            primaryLabel: primaryLabel,
            onPrimary: isSubmitting ? null : onPrimary,
            secondaryLabel: secondaryLabel,
            onSecondary: isSubmitting ? null : onSecondary,
            isSubmitting: isSubmitting,
          ),
        ],
      ),
    );
  }
}

class _FormFooter extends StatelessWidget {
  const _FormFooter({
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    required this.isSubmitting,
  });

  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = secondaryLabel;

    final primary = FilledButton(
      onPressed: onPrimary,
      child: isSubmitting
          ? SizedBox(
              width: AlayaSpacing.lg,
              height: AlayaSpacing.lg,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.onPrimary,
              ),
            )
          : Text(primaryLabel),
    );

    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
            child: secondary == null
                ? SizedBox(width: double.infinity, child: primary)
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onSecondary,
                          child: Text(secondary),
                        ),
                      ),
                      const SizedBox(width: AlayaSpacing.sm),
                      Expanded(flex: 2, child: primary),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
