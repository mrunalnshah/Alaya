import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_durations.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// One labelled door to the rest of a form (ARCH_5 §2.9, Law U16).
///
/// A form with eleven controls is not hard to use because any one of them is hard — it is hard because
/// all eleven arrive at once and the reader has to decide which matter. This shows the few that usually
/// do, and puts the rest behind one row they can open.
///
/// **Three rules make the pattern safe rather than merely tidier:**
///
/// 1. **[summary] says what is inside.** A collapsed section that gives no account of itself is a place
///    values go to hide: somebody sets a tag, saves, reopens, and the tag is behind a chevron with
///    nothing to suggest it exists. The summary is not decoration — it is what makes collapsing
///    honest.
/// 2. **[startExpanded] opens it when anything inside is non-default.** Reopening a record must show
///    what that record actually holds. A caller passes `true` when it has values worth seeing, and the
///    section stays open from then on.
/// 3. **It never hides a required field.** Only one field in any capture path is required (Law U11), and
///    it belongs above this row. A validation error the user cannot see is worse than a long form.
///
/// The expansion animates at [AlayaDurations.base] — the fifth animation ARCH_5 §2.6 permits, and the
/// only one that exists to *explain*: a section appearing instantly reads as a layout glitch, and the
/// user cannot tell whether they opened something or the screen jumped. It skips entirely under
/// `MediaQuery.disableAnimationsOf`, like every other motion in the app.
class AlayaDisclosure extends StatefulWidget {
  /// Creates a disclosure.
  const AlayaDisclosure({
    required this.label,
    required this.child,
    this.summary,
    this.startExpanded = false,
    super.key,
  });

  /// What is behind the door, e.g. "More details".
  final String label;

  /// What is currently set inside, shown only while collapsed.
  ///
  /// Keep it to the values a user would look for — "Cash · Groceries · 2 tags", not a field list. Null
  /// when nothing inside has been set, which is the common case on a new record.
  final String? summary;

  /// Whether to open on first build.
  ///
  /// Pass `true` when anything inside holds a non-default value. Editing an existing record almost
  /// always means `true`; a blank one almost always means `false`.
  final bool startExpanded;

  /// The fields.
  final Widget child;

  @override
  State<AlayaDisclosure> createState() => _AlayaDisclosureState();
}

class _AlayaDisclosureState extends State<AlayaDisclosure> {
  late bool _open = widget.startExpanded;

  @override
  void didUpdateWidget(AlayaDisclosure oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Opens when the caller newly reports content, and never closes on its own. A section that shut
    // itself while the user was reading it would be the worst version of this widget.
    if (widget.startExpanded && !oldWidget.startExpanded) _open = true;
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final summary = widget.summary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A whole-width row, not an icon button. The affordance is the row: a chevron alone is a
        // 24dp target on a 320dp screen and reads as decoration.
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AlayaSpacing.minTapTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(widget.label, style: AlayaTypography.bodyEmphasis),
                        if (!_open &&
                            summary != null &&
                            summary.isNotEmpty) ...[
                          const SizedBox(height: AlayaSpacing.xxs),
                          Text(
                            summary,
                            style: AlayaTypography.caption.copyWith(
                              color: semantic.muted,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AlayaSpacing.xs),
                  // Rotates rather than swapping glyphs, so the chevron is one object that moved and
                  // not two icons that flickered.
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: reduceMotion
                        ? Duration.zero
                        : AlayaDurations.base,
                    child: Icon(
                      Icons.expand_more,
                      size: AlayaIconSize.md,
                      color: semantic.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // `AnimatedSize` over the real child rather than a cross-fade: the fields must be in the tree
        // whether or not they are visible, so a validation error inside a closed section still counts
        // and `initialValue` on a text field is not re-seeded every time the section opens.
        AnimatedSize(
          duration: reduceMotion ? Duration.zero : AlayaDurations.base,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(bottom: AlayaSpacing.sm),
                  child: widget.child,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
