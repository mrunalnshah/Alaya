import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/settings/providers/split_settings_providers.dart';
import 'package:alaya/features/split/presentation/sheets/add_person_sheet.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/features/split/providers/split_summary_provider.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Who you are, and how people can pay you (ARCH_5 §3 archetype D leaf).
///
/// **This screen is on its way out.** Onboarding will ask for the name once, at which point nothing
/// arrives here for the first time and the branch becomes what it should always have been: somewhere to
/// *change* a decision, not to make one. Until that lands it is still the only place the payment details
/// can be set.
///
/// **The link to Groups is gone.** Groups are a tab on `/split` now, and a settings branch offering a
/// shortcut into a tab of another destination is the kind of cross-link that made this module feel like a
/// maze — seven routes where two would do.
class SplitSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const SplitSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final people = ref.watch(splitPeopleProvider);
    final self = ref.watch(splitSelfProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsSplit)),
      body: people.when(
        loading: () => AlayaListSkeleton(label: strings.loadingLabel),
        error: (error, stack) => EmptyState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          icon: Icons.error_outline,
        ),
        data: (all) => ListView(
          padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlayaSpacing.screenEdge,
              ),
              child: SectionHeader(label: strings.splitSettingsWhoAreYou),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AlayaSpacing.screenEdge,
                0,
                AlayaSpacing.screenEdge,
                AlayaSpacing.sm,
              ),
              child: Text(
                strings.splitSettingsWhoAreYouHelp,
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
            ),

            if (all.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AlayaSpacing.screenEdge,
                ),
                child: Text(
                  strings.splitSettingsNoPeople,
                  style: AlayaTypography.body.copyWith(color: semantic.muted),
                ),
              )
            else
              for (final payee in all)
                RadioListTile<String>(
                  value: payee.id,
                  groupValue: self,
                  title: Text(payee.name),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AlayaSpacing.screenEdge,
                  ),
                  onChanged: (id) => _claim(context, ref, id, payee),
                ),

            // **`AddPersonSheet`, not `PayeeSheet`.** The shared sheet defaults a new payee to
            // `PayeeKind.merchant`, and `splitPeopleProvider` filters to persons — so anybody added from
            // here used to vanish from the very list that sent them to add somebody.
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlayaSpacing.screenEdge,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => AddPersonSheet.show(context),
                  icon: const Icon(
                    Icons.person_add_outlined,
                    size: AlayaIconSize.md,
                  ),
                  label: Text(strings.splitAddPerson),
                ),
              ),
            ),

            SectionHeader(
              label: strings.splitSettingsPayMe,
              padding: const EdgeInsets.fromLTRB(
                AlayaSpacing.screenEdge,
                AlayaSpacing.xl,
                AlayaSpacing.screenEdge,
                AlayaSpacing.xxs,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlayaSpacing.screenEdge,
              ),
              child: Text(
                // What it buys, not what it is. Optional, and the summary works without one.
                strings.splitSettingsPayMeHelp,
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AlayaSpacing.screenEdge,
                AlayaSpacing.sm,
                AlayaSpacing.screenEdge,
                0,
              ),
              child: _PaymentHandleField(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _claim(
    BuildContext context,
    WidgetRef ref,
    String? id,
    Payee payee,
  ) async {
    if (id == null) return;
    final strings = AlayaStrings.of(context);
    final ok = await ref.read(splitSettingsProvider.notifier).setSelf(id);
    if (!context.mounted) return;
    showResultSnack(
      context,
      message: ok
          ? strings.splitSettingsClaimed(payee.name)
          : strings.errorBodyGeneric,
    );
  }
}

/// Where people can send money, in whatever form the user's country uses.
///
/// Its own widget so the controller has somewhere to live and be disposed — a `TextEditingController`
/// created inside a `build` leaks one per rebuild, and a settings screen rebuilds on every provider it
/// watches.
class _PaymentHandleField extends ConsumerStatefulWidget {
  const _PaymentHandleField();

  @override
  ConsumerState<_PaymentHandleField> createState() =>
      _PaymentHandleFieldState();
}

class _PaymentHandleFieldState extends ConsumerState<_PaymentHandleField> {
  final _controller = TextEditingController();
  bool _loaded = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final saved = ref.watch(splitPaymentHandleProvider).valueOrNull;

    // Adopted once. The provider re-emits after every write, and without this guard a save would reset
    // the cursor to the start of the field mid-typing — the same `_loaded` guard `TagEditorScreen` uses
    // and for the same reason.
    if (!_loaded && saved != null) {
      _loaded = true;
      _controller.text = saved;
    }

    return TextField(
      controller: _controller,
      // **No keyboard hint, no autocorrect, no validation.** The field used to be a UPI id with an email
      // keyboard, which quietly assumed India. It now holds a PayPal link, an IBAN, a Venmo handle or a
      // sentence, and any assumption about its shape would be wrong somewhere.
      autocorrect: false,
      maxLines: 2,
      minLines: 1,
      decoration: InputDecoration(
        labelText: strings.splitSettingsPayMeLabel,
        hintText: strings.splitSettingsPayMeHint,
        suffixIcon: IconButton(
          onPressed: () => _save(strings),
          tooltip: strings.actionSave,
          icon: const Icon(Icons.check, size: AlayaIconSize.md),
        ),
      ),
      onSubmitted: (_) => _save(strings),
    );
  }

  Future<void> _save(AlayaStrings strings) async {
    final ok = await ref
        .read(splitSettingsProvider.notifier)
        .setPaymentHandle(_controller.text);
    if (!mounted) return;
    showResultSnack(
      context,
      message: ok ? strings.actionSaved : strings.errorBodyGeneric,
    );
  }
}
