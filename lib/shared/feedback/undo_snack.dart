/// The single implementation of Law U9's success path.
///
/// **Every write reports its outcome.** A save that appears to do nothing is the worst result a form
/// can produce, and the second worst is five features each inventing their own snack bar.
///
/// One at a time: each call hides the current bar before showing its own. A queue would leave the
/// user reading the result of an action they took four taps ago.
library;

import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_durations.dart';

/// Reports a completed write and offers to reverse it.
///
/// Use wherever the data model can undo, which is most places — soft delete exists precisely so this
/// is possible (ARCH_3 §4). ARCH_5 §5.4 fixes what undo means per entity; in particular a stock
/// consume undoes by writing a **reversing movement**, never by deleting the original.
void showUndoSnack(
  BuildContext context, {
  required String message,
  required String undoLabel,
  required VoidCallback onUndo,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: AlayaDurations.snack,
        action: SnackBarAction(label: undoLabel, onPressed: onUndo),
      ),
    );
}

/// Reports a completed write that cannot be undone.
void showResultSnack(
  BuildContext context, {
  required String message,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: AlayaDurations.snack,
        // **An offer, not a redirection.** A completed save must not throw the user into another form:
        // recording the expense was the task, and naming a warranty is a different one. The action puts
        // the next step one tap away without taking the decision for them (Law U9).
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction),
      ),
    );
}

/// Reports a failed write, optionally offering a retry.
///
/// Coloured by the danger tone rather than left to the default surface: a failure that looks
/// identical to a success is a failure the user will not notice.
void showFailureSnack(
  BuildContext context, {
  required String message,
  String? retryLabel,
  VoidCallback? onRetry,
}) {
  final semantic = context.semantic;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: semantic.onStatus)),
        backgroundColor: semantic.danger,
        duration: AlayaDurations.snack,
        action: retryLabel == null || onRetry == null
            ? null
            : SnackBarAction(
                label: retryLabel,
                textColor: semantic.onStatus,
                onPressed: onRetry,
              ),
      ),
    );
}
