import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The app's one transient message.
///
/// Material's default snack bar is a wide slab with its own type scale and its
/// own four-second dwell, neither of which is this app's. A toast here is the
/// same object every card and sheet is: a `surfaceHighest` fill, a hairline
/// border, `Radii.control`, and body text at the size the rest of the screen reads
/// at. It is also brief: long enough to read six words, not long enough to
/// still be covering the log on return to it. Anything requiring
/// longer than that is not a toast, it is a sheet.
///
/// The queue is cleared on every call. Two of these stacking up means the
/// second is the relevant one and the first obstructs it.
void showToast(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  bool destructive = false,
}) => showToastOn(
  ScaffoldMessenger.of(context),
  message,
  actionLabel: actionLabel,
  onAction: onAction,
  destructive: destructive,
);

/// The same toast, for a caller that grabbed its messenger before an `await`.
///
/// Reaching for `ScaffoldMessenger.of(context)` after one is how a message ends
/// up thrown from a widget that has already left the tree, so every path that
/// awaits anything holds the messenger instead of the context.
void showToastOn(
  ScaffoldMessengerState messenger,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  bool destructive = false,
}) {
  final c = messenger.context.c;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: messenger.context.t.bodyMedium?.copyWith(
            color: destructive ? c.negative : c.textPrimary,
          ),
        ),
        // An action needs time to be aimed at; a statement only needs reading.
        duration: Duration(
          milliseconds: actionLabel == null ? 1800 : 3200,
        ),
        backgroundColor: c.surfaceHighest,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        margin: const EdgeInsets.all(Space.md),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          side: BorderSide(color: c.border),
        ),
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(
                label: actionLabel,
                textColor: c.accent,
                onPressed: onAction,
              ),
      ),
    );
}
