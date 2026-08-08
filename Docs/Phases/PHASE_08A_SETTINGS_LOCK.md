# PHASE 8A — Onboarding, the settings tree, and the app lock UI

## Dependencies

```
flutter pub add local_auth path_provider share_plus
```

**Three, not the four the task names, and the fourth is worth a decision rather than a silent add.**
ARCH_1 §7 pins `path_provider`, `file_picker` and `share_plus` to 8A, and `local_auth` too. Three of
those are imported by this phase: `local_auth` for the lock screen's biometric shortcut,
`path_provider` for the export destination, `share_plus` for handing the file off. **`file_picker` has
no importer in 8A.** It exists to *choose* a file to restore, and restore is 8B — ARCH_4 §5.1 assigns
"Offline backup, share to WhatsApp / email" and "Plain, unencrypted backup" to 8B, and ARCH_5 §8 gives
8B the Backup and Restore screens.

So adding it now ships a dependency nothing imports, against the standing rule that only packages a
phase's code actually imports may be added. Either §7's row should read 8B, or it is added now as a
deliberate pre-pin. **Not added here** — say the word and it goes in.

`share_plus` is this phase's ARCH_4 R22 exposure. Its v11 replaced `Share.shareXFiles` with
`SharePlus.instance.share(ShareParams(...))`, and I cannot compile against the installed version, so it
is confined to one file the way 7B confined `fl_chart` and 7A confined `table_calendar`.

## What was missing, and what was not

**`BackupService` and `RestoreService` already exist** (Phase 4C) with providers from Phase 5. I
expected a gap here and checking proved otherwise, so the two backup prompts ARCH_3 §2.2 requires — the
one after PIN setup and the one in front of "forgot both" — wire to the real service rather than to a
placeholder. Good: a security flow that promises a backup and delivers *"Phase 8B"* is worse than one
that never offered.

**Nothing could erase.** No phase built it, and two 8A flows require it: the forgot-both path that
demands the word `ERASE`, and the optional auto-erase after ten failures (ARCH_3 §2.3). Neither is
deferrable to 8B, because both are reachable from the lock screen — the one screen a user sees when they
cannot get in. `EraseService` is therefore this phase's first file, in the same spirit as ARCH_5 §8's
note that 7A and 7B's missing repositories were "the first task of their phase, not the last".

## Four decisions taken before any screen

**The lock screen takes archetype A's shape, not its skeleton.** §3's A is an `AlayaBottomSheet`, and a
lock screen is a full-screen route that must not be dismissible — a sheet with no way out is a worse
answer than a `Scaffold`. What carries over is everything A is actually about: one required field,
autofocused, a commit enabled the moment it parses, and optional context as chips rather than pickers
(here, the biometric shortcut). §3 permits deviating and forbids only inventing a seventh, and the task
names A itself, so this is recorded rather than requested.

**`activePaletteProvider` and `themeModeProvider` stop being `StateProvider`s.** ARCH_4 §5.1 item 23 is
that a user's dark-mode choice is lost on restart, recorded as 8A's work. Both become persisted
`Notifier`s in `app.dart`, which is also the last `StateProvider` in the app — worth noting because
`StateProvider` is legacy in the pinned Riverpod 3.4.1 (§7).

**Lock state is a `NotifierProvider` with a `ValueNotifier` bridge, not a `ChangeNotifier`.** GoRouter's
`refreshListenable` needs a `Listenable`, and the obvious answer — `ChangeNotifierProvider` — is legacy
in Riverpod 3. A bridge driven by the same provider widgets watch also cannot drift out of step with
them, which two separate declarations of one state could.

**The DELIVER list is a subset of what COVERAGE requires.** Payment methods, payees and currencies are
coverage rows; Security, Data and About are branches of the settings tree the task specifies. None has a
named file in DELIVER, and all six are built.

---

## The missing capability, and the wiring

### `lib/data/backup/erase_service.dart`

```dart
import 'dart:async';

import 'package:drift/drift.dart';

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/security/app_lock_store.dart';

/// Erases every row and clears the lock — the last resort behind "I have forgotten both".
///
/// **The one capability ARCH_3 §2.2 requires that no phase had built.** `BackupService` and
/// `RestoreService` arrived in 4C, but nothing could erase, and two of this phase's flows need it: the
/// forgot-both path that requires typing `ERASE`, and the optional auto-erase after ten failed
/// attempts (§2.3). Neither can wait for 8B, because both are reachable from the lock screen — the one
/// screen a user sees when they cannot get in.
///
/// **It clears the lock as well as the data, and that is the whole point.** A user who has forgotten
/// their PIN *and* their recovery code is locked out; wiping their history while leaving the lock in
/// place would leave them exactly as locked out, with nothing left to unlock. Erasing both is what
/// makes "start over" true.
///
/// **It re-seeds, using the database's own seeder rather than one passed in.** An empty database has no
/// currencies and no units, so the app would open to a currency picker with nothing in it, and
/// `AlayaDatabase` already holds the `DatabaseSeeder` it was opened with — taking a second one as a
/// parameter would let the two disagree, and a re-seed that differs from the original install is a
/// worse outcome than no re-seed at all. A database opened without a seeder (every unit test) simply
/// ends up empty, which is what those tests want.
final class EraseService {
  /// Creates the service.
  const EraseService({
    required AlayaDatabase database,
    required AppLockStore lockStore,
  })  : _database = database,
        _lockStore = lockStore;

  final AlayaDatabase _database;
  final AppLockStore _lockStore;

  /// Deletes every row, clears the lock, and re-seeds.
  ///
  /// Ordered deliberately: the data goes first, so a failure part-way leaves the lock intact and the
  /// user no worse off than before they started. Clearing the lock first and then failing the delete
  /// would hand an unlocked app full of data to whoever was holding the phone.
  Future<Result<void, Failure>> eraseEverything() async {
    try {
      await _database.transaction(() async {
        // **`defer_foreign_keys`, not `foreign_keys = OFF`.** SQLite ignores a change to
        // `foreign_keys` inside a transaction — it is a no-op there, silently — so the usual
        // "disable, delete, re-enable" recipe would leave enforcement on and fail on the first child
        // row. `defer_foreign_keys` holds every check until COMMIT, by which point nothing is left to
        // violate. Phase 1C turns `foreign_keys` on in `beforeOpen`, and this leaves that alone.
        await _database.customStatement('PRAGMA defer_foreign_keys = ON');
        for (final table in _database.allTables) {
          await _database.delete(table).go();
        }
      });

      await _lockStore.clearLock();
      // `DatabaseSeeder` is a typedef — `Future<void> Function(AlayaDatabase)` — so this is a call,
      // not a method on an object.
      await _database.seeder?.call(_database);
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('Could not erase the data on this device.', cause: error),
      );
    }
  }
}
```

### `lib/features/settings/state/appearance_settings.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/palettes/palette.dart';
import 'package:alaya/app/theme/palettes/presets.dart';

/// How the appearance choices are stored, and how a stored string becomes a choice again.
///
/// **This closes ARCH_4 §5.1 item 23.** `activePaletteProvider` and `themeModeProvider` shipped in
/// Phase 5 as bare `StateProvider`s with no `app_settings` backing, so a user's dark-mode choice was
/// lost on every restart. The audit recorded it as 8A's work rather than a Phase 5 defect; this is the
/// storage half of the fix.
///
/// Both parsers **fall back rather than throw**, for the reason Law L13 gives about enums in the
/// database: a settings row is user data, a later version may write a palette name this build has
/// never heard of, and a theme choice is not worth failing app startup over.
abstract final class AppearanceSettings {
  /// The `app_settings` key holding the chosen palette's name.
  static const String paletteKey = 'appearance.palette';

  /// The `app_settings` key holding the chosen theme mode.
  static const String themeModeKey = 'appearance.themeMode';

  /// The palette a fresh install uses.
  ///
  /// `AlayaPresets.activePreset` and not a name of its own, so ARCH_3 §8.1's promise that one constant
  /// switches the shipped look survives the arrival of a picker.
  static AlayaPalette get fallbackPalette => AlayaPresets.activePreset;

  /// The theme mode a fresh install uses.
  ///
  /// Following the system is the only defensible default: a finance app opened at midnight should not
  /// be the one bright thing on the phone, and nobody should have to choose before they have seen it.
  static const ThemeMode fallbackThemeMode = ThemeMode.system;

  /// Parses a stored palette name, falling back for anything this build cannot offer.
  static AlayaPalette parsePalette(String? stored) {
    for (final palette in AlayaPresets.all) {
      if (palette.name == stored) return palette;
    }
    return fallbackPalette;
  }

  /// The value written back for [palette].
  static String storedPalette(AlayaPalette palette) => palette.name;

  /// Parses a stored theme mode, falling back for anything unrecognised.
  static ThemeMode parseThemeMode(String? stored) {
    for (final mode in ThemeMode.values) {
      if (mode.name == stored) return mode;
    }
    return fallbackThemeMode;
  }

  /// The value written back for [mode].
  static String storedThemeMode(ThemeMode mode) => mode.name;
}
```

### `lib/app/app.dart`

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/router/app_router.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/palette.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/features/settings/state/appearance_settings.dart';

/// The active palette, restored from `app_settings` and persisted on change.
///
/// A provider rather than a bare constant so Settings and the Theme Lab can switch palettes at
/// runtime and the whole tree rebuilds. `AlayaPresets.activePreset` remains the compile-time default,
/// so the "one constant change" requirement (ARCH_3 §8.1) still holds for anyone who wants to change
/// the shipped look rather than offer a choice.
///
/// **Phase 8A turned this from a `StateProvider` into a persisted `Notifier`, closing ARCH_4 §5.1
/// item 23.** As a bare `StateProvider` it lost the user's choice on every restart — the audit recorded
/// that as 8A's work rather than a Phase 5 defect, and this is it.
final activePaletteProvider = NotifierProvider<ActivePaletteNotifier, AlayaPalette>(
  ActivePaletteNotifier.new,
);

/// Holds and persists the chosen palette.
///
/// The same shape as 6F's `InsightSideNotifier` and 7B's `AnalyticsRangeNotifier`: a synchronous
/// default so the very first frame has a theme, then an unawaited restore. Awaiting the settings read
/// would mean a `FutureProvider` above `MaterialApp`, and the app would show a bare white frame while
/// a key/value lookup completed.
class ActivePaletteNotifier extends Notifier<AlayaPalette> {
  @override
  AlayaPalette build() {
    unawaited(_restore());
    return AppearanceSettings.fallbackPalette;
  }

  Future<void> _restore() async {
    final stored =
        await ref.read(settingsRepositoryProvider).readValue(AppearanceSettings.paletteKey);
    final restored = AppearanceSettings.parsePalette(stored);
    if (restored.name != state.name) state = restored;
  }

  /// Switches to [palette] and remembers it.
  ///
  /// The write is not awaited: the tree should retheme on the frame the swatch is tapped, and a
  /// settings row landing a millisecond later changes nothing the reader can see.
  void use(AlayaPalette palette) {
    state = palette;
    unawaited(
      ref.read(settingsRepositoryProvider).writeValue(
            key: AppearanceSettings.paletteKey,
            value: AppearanceSettings.storedPalette(palette),
            valueType: 'string',
          ),
    );
  }
}

/// The theme mode, following the system by default, restored from `app_settings`.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

/// Holds and persists the chosen theme mode.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    unawaited(_restore());
    return AppearanceSettings.fallbackThemeMode;
  }

  Future<void> _restore() async {
    final stored =
        await ref.read(settingsRepositoryProvider).readValue(AppearanceSettings.themeModeKey);
    final restored = AppearanceSettings.parseThemeMode(stored);
    if (restored != state) state = restored;
  }

  /// Switches to [mode] and remembers it.
  void use(ThemeMode mode) {
    state = mode;
    unawaited(
      ref.read(settingsRepositoryProvider).writeValue(
            key: AppearanceSettings.themeModeKey,
            value: AppearanceSettings.storedThemeMode(mode),
            valueType: 'string',
          ),
    );
  }
}

/// The router, held in a provider so its lifetime matches the app's.
///
/// `GoRouter` owns navigation state, so rebuilding it would reset the stack. Constructing it inside
/// `build` is the standard way to lose a user's place on every theme change.
final routerProvider = Provider<GoRouter>((ref) => AppRouter.build());

/// The root widget.
class AlayaApp extends ConsumerWidget {
  /// Creates the app.
  const AlayaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(activePaletteProvider);
    final mode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      // Not a literal: the app's own name comes from the ARB like every other visible string.
      onGenerateTitle: (context) => AlayaStrings.of(context).appName,
      theme: AlayaTheme.light(palette),
      darkTheme: AlayaTheme.dark(palette),
      themeMode: mode,
      routerConfig: ref.watch(routerProvider),
      localizationsDelegates: const [
        AlayaStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AlayaStrings.supportedLocales,
      debugShowCheckedModeBanner: false,
    );
  }
}
```

### `lib/features/lock/providers/lock_providers.dart`

```dart
/// Lock state, the router's refresh bridge, and the security setting keys (ARCH_5 U19).
///
/// **Nothing here declares a repository or an engine.** `pinServiceProvider` and `eraseServiceProvider`
/// live in `lib/app/providers/` and are watched from here (Law U19).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';

/// Why the app is showing the lock screen, or that it is not.
enum LockPhase {
  /// No lock is configured, or it has been satisfied for this session.
  open,

  /// A lock exists and has not been satisfied.
  locked,

  /// Still asking secure storage whether a lock exists.
  ///
  /// A distinct state rather than an optimistic `open`, because guessing wrong flashes the dashboard —
  /// including the funds header — for one frame before the lock appears. A lock that shows your balance
  /// on the way past is not a lock.
  unknown,
}

/// Whether the app is locked, and the one place that changes.
final lockPhaseProvider = NotifierProvider<LockNotifier, LockPhase>(LockNotifier.new);

/// Holds the lock phase and the three transitions it has.
class LockNotifier extends Notifier<LockPhase> {
  @override
  LockPhase build() {
    unawaited(refresh());
    return LockPhase.unknown;
  }

  /// Re-reads whether a lock is configured, without changing whether it has been satisfied.
  ///
  /// Called on construction and after the lock is enabled or disabled in Settings.
  Future<void> refresh() async {
    final enabled = await ref.read(pinServiceProvider).isEnabled;
    state = enabled ? LockPhase.locked : LockPhase.open;
  }

  /// Records that the user has satisfied the lock for this session.
  void markUnlocked() => state = LockPhase.open;

  /// Locks the app again — on backgrounding past the auto-lock delay, or from Settings.
  ///
  /// A no-op when no lock is configured, so a "lock now" action cannot strand a user who has none
  /// behind a screen they have no way to pass.
  Future<void> lock() async {
    if (!await ref.read(pinServiceProvider).isEnabled) return;
    state = LockPhase.locked;
  }
}

/// Whether navigation should be redirected to the lock screen.
///
/// `unknown` counts as locked. Erring the other way would show the app for a frame while the answer
/// arrived, which is the one thing a lock exists to prevent.
final isLockedProvider = Provider<bool>(
  (ref) => ref.watch(lockPhaseProvider) != LockPhase.open,
);

// `routerRefreshProvider` used to live here. It moved to `app.dart` in the same phase it was written,
// because the router has **two** gates — this one and onboarding — and a bridge that listened to only
// one would leave the other decorative. It belongs with whatever knows about both.

/// How long the app may sit in the background before it locks again (ARCH_3 §2.2).
///
/// Sixty seconds by default: long enough to answer a message or check a rate and come back, short
/// enough that a phone left on a table is not open indefinitely.
const Duration autoLockDelay = Duration(seconds: 60);

/// The `app_settings` key holding the user's chosen auto-lock delay, in seconds.
const String autoLockDelaySettingKey = 'lock.autoLockSeconds';

/// The `app_settings` key holding whether ten failures erase everything (ARCH_3 §2.3).
///
/// **Defaults off, and the key stores only the choice.** The erase itself runs through `EraseService`;
/// this exists so a user who has never opened Security cannot lose their history to a child mashing
/// digits.
const String autoEraseSettingKey = 'lock.autoEraseAfterTenFailures';

/// How many consecutive failures trigger the optional auto-erase.
const int autoEraseFailureThreshold = 10;

/// Whether ten failures erase everything, off unless the user turned it on.
final autoEraseEnabledProvider = FutureProvider<bool>((ref) async {
  final stored = await ref.watch(settingsRepositoryProvider).readValue(autoEraseSettingKey);
  return stored == 'true';
});

/// Re-locks the app when it returns from the background after [autoLockDelay].
///
/// **A widget rather than a service, because only a widget receives lifecycle events.** It wraps the
/// router's content, records the instant of backgrounding and compares on resume — so the elapsed time
/// is measured against the clock rather than by a timer, which would not survive the process being
/// killed and would make the lock defeatable by a task switch.
class AutoLockObserver extends ConsumerStatefulWidget {
  /// Wraps [child].
  const AutoLockObserver({required this.child, super.key});

  /// The app's content.
  final Widget child;

  @override
  ConsumerState<AutoLockObserver> createState() => _AutoLockObserverState();
}

class _AutoLockObserverState extends ConsumerState<AutoLockObserver>
    with WidgetsBindingObserver {
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _leftAt ??= DateTime.now().toUtc();
      case AppLifecycleState.resumed:
        final left = _leftAt;
        _leftAt = null;
        if (left == null) return;
        if (DateTime.now().toUtc().difference(left) >= autoLockDelay) {
          unawaited(ref.read(lockPhaseProvider.notifier).lock());
        }
      case AppLifecycleState.inactive:
        // Deliberately ignored. `inactive` fires for a notification-shade pull and an incoming-call
        // banner, neither of which is leaving the app — locking on it would re-prompt for a PIN
        // several times a day for no reason.
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

## Routes and the gates

`routes.dart` gains 21 constants, 3 patterns, 3 parameters and 3 builders. `app_router.dart` gains an
onboarding gate, a `refreshListenable`, and **a fix**: its lock test was an equality test against
`Routes.lock`, which was harmless while that route was a leaf and would have made `/lock/recovery`
unreachable the moment 8A added one — a locked user tapping *"I have forgotten my PIN"* bounced straight
back to the screen they were trying to leave. It is a prefix test now.

Both files are carried by every UI document (ARCH_6 §2), so PHASE_05 and 06A–07B regenerate.

**Two orderings in the route table are load-bearing**, because go_router walks the list in order and
stops at the first match: `/lock/recovery` is declared before `/lock`, and the literal children of
`/settings/accounts`, `/settings/tags`, `/settings/units` and `/settings/security` before their
parameterised siblings — otherwise `:accountId` swallows the word `new`.

**Every settings branch sits outside the shell.** `/settings` is the drawer destination; its children are
reached *from* it and need a back arrow, which a shell owning a drawer can never imply (Law U18). None of
them uses `_DetailScaffold`: a catalogue needs its own pinned search field and overflow, which that
wrapper does not offer.

**`_destination` and the `placeholder_screen` import are gone.** 8A was the last phase with a placeholder
destination, so both had no caller left and `very_good_analysis` reports `unused_element`. The widget
itself stays for 8B.

### `lib/app/router/routes.dart`

```dart
/// Every route path in the app, in one place.
///
/// Hand-written: `go_router_builder` cannot resolve alongside `drift_dev` (ARCH_1 §7.1). A literal
/// path anywhere else is a route that drifts silently when this file changes.
abstract final class Routes {
  /// Where the app opens.
  static const String initial = dashboard;

  // ── top level, inside the drawer shell ──

  /// The dashboard.
  static const String dashboard = '/';

  /// The transaction ledger.
  static const String expenses = '/expenses';

  /// The inventory catalogue.
  static const String inventory = '/inventory';

  /// The shopping lists.
  static const String shopping = '/shopping';

  /// The recurring templates.
  static const String recurring = '/recurring';

  /// The assets and service records.
  static const String services = '/services';

  /// The calendar.
  static const String calendar = '/calendar';

  /// The insights.
  static const String insights = '/insights';

  /// The settings.
  static const String settings = '/settings';

  // ── outside the shell: full-screen editors and the lock ──

  /// The PIN gate.
  static const String lock = '/lock';

  /// The palette workbench.
  static const String themeLab = '/settings/theme-lab';

  /// The first-run flow. Skippable and resumable (ARCH_5 §3 archetype B).
  static const String onboarding = '/onboarding';

  /// The forgotten-PIN flow: recovery code, then a new PIN.
  ///
  /// **Under `/lock`, and that placement is load-bearing.** The redirect permits anything beneath
  /// `lockBranch` while locked; anywhere else and a locked user would be bounced back to `/lock` the
  /// moment they tapped "I have forgotten my PIN", which is the one path they need.
  static const String lockRecovery = '/lock/recovery';

  /// Everything the lock gate lets through while the app is locked.
  static const String lockBranch = lock;

  /// Settings › Accounts.
  static const String settingsAccounts = '/settings/accounts';

  /// Settings › Payment methods.
  static const String settingsPaymentMethods = '/settings/payment-methods';

  /// Settings › Payees.
  static const String settingsPayees = '/settings/payees';

  /// Settings › Tags.
  static const String settingsTags = '/settings/tags';

  /// Settings › Units.
  static const String settingsUnits = '/settings/units';

  /// Settings › Currencies.
  static const String settingsCurrencies = '/settings/currencies';

  /// Settings › Appearance.
  static const String settingsAppearance = '/settings/appearance';

  /// Settings › Security.
  static const String settingsSecurity = '/settings/security';

  /// Settings › Data.
  static const String settingsData = '/settings/data';

  /// Settings › About.
  static const String settingsAbout = '/settings/about';

  /// Setting or changing the PIN, reached from Settings › Security.
  ///
  /// Onboarding does **not** navigate here — it embeds the same widget as a step. A route would fight
  /// the onboarding gate, which sends everything outside `/onboarding` back to it.
  static const String settingsPin = '/settings/security/pin';

  /// A new account.
  static const String accountNew = '/settings/accounts/new';

  /// A new tag.
  static const String tagNew = '/settings/tags/new';

  /// A new unit.
  static const String unitNew = '/settings/units/new';

  /// A new transaction.
  static const String transactionNew = '/expenses/new';

  /// The line items of a new transaction.
  static const String transactionLinesNew = '/expenses/new/lines';

  /// A new item.
  static const String itemNew = '/inventory/new';

  /// A new recurring template.
  static const String recurringNew = '/recurring/new';

  /// A new asset.
  static const String assetNew = '/services/new';

  // ── parameterised ──

  /// Path pattern for one transaction.
  static const String transactionDetailPattern = '/expenses/:transactionId';

  /// Path pattern for editing one transaction.
  static const String transactionEditPattern = '/expenses/:transactionId/edit';

  /// Path pattern for the line items of one transaction.
  static const String transactionLinesPattern = '/expenses/:transactionId/lines';

  /// Path pattern for one item.
  static const String itemDetailPattern = '/inventory/:itemId';

  /// Path pattern for editing one item.
  static const String itemEditPattern = '/inventory/:itemId/edit';

  /// Path pattern for adding a batch to one item.
  static const String batchNewPattern = '/inventory/:itemId/batch/new';

  /// Path pattern for editing one batch.
  static const String batchEditPattern = '/inventory/:itemId/batch/:batchId';

  /// Path pattern for one batch's movement history.
  static const String batchHistoryPattern = '/inventory/:itemId/batch/:batchId/history';

  /// Path pattern for one shopping list.
  static const String shoppingListPattern = '/shopping/:listId';

  /// Path pattern for turning a shopping list's ticked entries into a purchase.
  static const String shoppingConvertPattern = '/shopping/:listId/convert';

  /// Path pattern for editing one recurring template.
  static const String recurringEditPattern = '/recurring/:templateId/edit';

  /// Path pattern for one template's occurrence history.
  static const String recurringHistoryPattern = '/recurring/:templateId/history';

  /// Path pattern for one recurring template.
  static const String recurringDetailPattern = '/recurring/:templateId';

  /// Path pattern for editing one asset.
  static const String assetEditPattern = '/services/:assetId/edit';

  /// Path pattern for a new service record against one asset.
  static const String serviceNewPattern = '/services/:assetId/service/new';

  /// Path pattern for editing one service record.
  static const String serviceEditPattern = '/services/:assetId/service/:recordId';

  /// Path pattern for one asset.
  static const String assetDetailPattern = '/services/:assetId';

  /// Path pattern for one calendar day.
  static const String calendarDayPattern = '/calendar/:dateKey';

  /// Path pattern for editing one account.
  static const String accountEditPattern = '/settings/accounts/:accountId';

  /// Path pattern for editing one tag.
  static const String tagEditPattern = '/settings/tags/:tagId';

  /// Path pattern for editing one unit. Keyed by code, which is the `units` primary key (ARCH_2 §2).
  static const String unitEditPattern = '/settings/units/:unitCode';

  /// Path pattern for one analytics drill-down.
  ///
  /// **Outside the shell**, unlike `calendarDayPattern`. A day is a view *of* the month, so it keeps
  /// the drawer and the grid stays behind it (Law U27); a drill-down leaves analytics for the ledger
  /// and needs a back arrow, which a shell owning a drawer can never imply (Law U18).
  ///
  /// **The window is deliberately absent from the path.** ARCH_5 §5.7 keeps a selected range in the
  /// view-model — the URL is the record's identity and nothing else — so a drill-down inherits
  /// whatever range the analytics screen is showing.
  static const String insightsDrillDownPattern = '/insights/drill/:drillKind/:drillValue';

  // ── param names, so a builder reading them cannot misspell one ──

  /// The transaction id parameter.
  static const String pTransactionId = 'transactionId';

  /// The item id parameter.
  static const String pItemId = 'itemId';

  /// The batch id parameter.
  static const String pBatchId = 'batchId';

  /// The shopping list id parameter.
  static const String pListId = 'listId';

  /// The recurring template id parameter.
  static const String pTemplateId = 'templateId';

  /// The asset id parameter.
  static const String pAssetId = 'assetId';

  /// The service record id parameter.
  static const String pRecordId = 'recordId';

  /// The calendar date parameter.
  static const String pDateKey = 'dateKey';

  /// The account parameter.
  static const String pAccountId = 'accountId';

  /// The tag parameter.
  static const String pTagId = 'tagId';

  /// The unit parameter — a code, not a UUID.
  static const String pUnitCode = 'unitCode';

  /// The drill-down axis parameter.
  static const String pDrillKind = 'drillKind';

  /// The drill-down value parameter.
  static const String pDrillValue = 'drillValue';

  // ── builders ──

  /// The location for transaction [id].
  static String transactionDetail(String id) => '$expenses/$id';

  /// The location for editing transaction [id].
  static String transactionEdit(String id) => '$expenses/$id/edit';

  /// The location for the line items of transaction [id], or of a new one when null.
  static String transactionLines(String? id) =>
      id == null ? transactionLinesNew : '$expenses/$id/lines';

  /// The location for item [id].
  static String itemDetail(String id) => '$inventory/$id';

  /// The location for editing item [id].
  static String itemEdit(String id) => '$inventory/$id/edit';

  /// The location for adding a batch to item [itemId].
  static String batchNew(String itemId) => '$inventory/$itemId/batch/new';

  /// The location for editing batch [batchId] of item [itemId].
  static String batchEdit(String itemId, String batchId) =>
      '$inventory/$itemId/batch/$batchId';

  /// The location for batch [batchId]'s movement history.
  static String batchHistory(String itemId, String batchId) =>
      '$inventory/$itemId/batch/$batchId/history';

  /// The location for shopping list [id].
  static String shoppingList(String id) => '$shopping/$id';

  /// The location for converting shopping list [id] into a purchase.
  static String shoppingConvert(String id) => '$shopping/$id/convert';

  /// The location for recurring template [id].
  static String recurringDetail(String id) => '$recurring/$id';

  /// The location for editing recurring template [id], or for a new one when null.
  static String recurringEdit(String? id) =>
      id == null ? recurringNew : '$recurring/$id/edit';

  /// The location for template [id]'s occurrence history.
  static String recurringHistory(String id) => '$recurring/$id/history';

  /// The location for asset [id].
  static String assetDetail(String id) => '$services/$id';

  /// The location for editing asset [id], or for a new one when null.
  static String assetEdit(String? id) => id == null ? assetNew : '$services/$id/edit';

  /// The location for a new service record against asset [assetId].
  static String serviceNew(String assetId) => '$services/$assetId/service/new';

  /// The location for editing service record [recordId] of asset [assetId].
  static String serviceEdit(String assetId, String recordId) =>
      '$services/$assetId/service/$recordId';

  /// The location for the calendar on [dateKey].
  static String calendarDay(int dateKey) => '$calendar/$dateKey';

  /// The location for editing [id], or for a new account when null.
  static String accountEdit(String? id) =>
      id == null ? accountNew : '$settingsAccounts/$id';

  /// The location for editing [id], or for a new tag when null.
  static String tagEdit(String? id) => id == null ? tagNew : '$settingsTags/$id';

  /// The location for editing [code], or for a new unit when null.
  static String unitEdit(String? code) => code == null ? unitNew : '$settingsUnits/$code';

  /// The location for the analytics drill-down on [kind] with [value].
  static String insightsDrillDown(String kind, String value) =>
      '$insights/drill/$kind/$value';

  /// The nine drawer destinations, in drawer order.
  ///
  /// Named for the drawer rather than the shell because `AlayaDrawer` reads it by this name — a route
  /// cannot exist in the router and be missing from the drawer without this list disagreeing.
  static const List<String> drawerDestinations = [
    dashboard,
    expenses,
    inventory,
    shopping,
    recurring,
    services,
    calendar,
    insights,
    settings,
  ];
}
```

### `lib/app/router/app_router.dart`

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/analytics/presentation/screens/analytics_home_screen.dart';
import 'package:alaya/features/analytics/presentation/screens/drill_down_screen.dart';
import 'package:alaya/features/analytics/state/drill_down_spec.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/features/lock/presentation/screens/lock_screen.dart';
import 'package:alaya/features/lock/presentation/screens/pin_setup_flow.dart';
import 'package:alaya/features/lock/presentation/screens/recovery_flow.dart';
import 'package:alaya/features/onboarding/presentation/screens/onboarding_flow.dart';
import 'package:alaya/features/settings/presentation/screens/about_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/account_editor_screen.dart';
import 'package:alaya/features/settings/presentation/screens/accounts_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/appearance_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/currencies_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/data_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/payees_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/payment_methods_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/security_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/tag_editor_screen.dart';
import 'package:alaya/features/settings/presentation/screens/tags_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/unit_editor_screen.dart';
import 'package:alaya/features/settings/presentation/screens/units_settings_screen.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_detail_screen.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_editor_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_list_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_editor_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_history_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/inventory_list_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/item_detail_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/item_editor_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/occurrence_history_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/template_builder_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/template_list_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_detail_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_editor_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_list_screen.dart';
import 'package:alaya/features/service/presentation/screens/service_editor_screen.dart';
import 'package:alaya/features/settings/presentation/theme_lab_screen.dart';
import 'package:alaya/features/shopping/presentation/screens/convert_to_purchase_screen.dart';
import 'package:alaya/features/shopping/presentation/screens/shopping_list_screen.dart';
import 'package:alaya/shared/widgets/alaya_drawer.dart';

/// Whether the app is currently locked, consulted on every navigation.
typedef LockGate = bool Function();

/// Whether the first-run flow still has to happen, consulted on every navigation.
typedef OnboardingGate = bool Function();

/// The app's `go_router` configuration — hand-written, per ARCH_1 §7.3.
///
/// **The nine drawer destinations sit inside the shell; every detail and editor route sits outside
/// it** (U18). `AppBar` resolves its leading slot by checking `hasDrawer` *before* `canPop`, so a
/// detail screen rendered inside the drawer shell gets a hamburger where a back arrow belongs.
///
/// Literal-path segments are declared before their parameterised siblings, because go_router walks
/// its route list in order and `:itemId` would otherwise swallow the word `new`.
///
/// **Phase 7B: `/insights` is now a real screen and `/insights/drill/...` is its drill-down.** The
/// drill-down is a top-level route rather than a child of `/insights`, unlike the calendar's day route:
/// a day is a view *of* the month and keeps the drawer (Law U27), while a drill-down leaves analytics
/// for the ledger and needs a back arrow, which a shell owning a drawer can never imply (Law U18).
///
/// **`_detail` was removed in 7B and `_destination` in 8A.** Both were declared and then called by
/// nothing once the last placeholder became a real screen, and `very_good_analysis` reports
/// `unused_element` on each. The `placeholder_screen.dart` import goes with them: **8A was the final
/// phase with a placeholder destination**, so nothing in this file names `PlaceholderScreen` any more.
/// The widget itself stays where it is, for 8B's Reminders and Support Us screens.
///
/// **Phase 8A: the redirect gained an onboarding gate and a `refreshListenable`, and its lock test
/// became a prefix test.** The equality test was harmless while `/lock` was a leaf and silently made
/// `/lock/recovery` unreachable the moment one existed.
abstract final class AppRouter {
  /// Builds the router.
  static GoRouter build({
    LockGate? isLocked,
    OnboardingGate? needsOnboarding,
    Listenable? refreshListenable,
    String initialLocation = Routes.initial,
    GlobalKey<NavigatorState>? navigatorKey,
  }) {
    final locked = isLocked ?? () => false;
    final onboarding = needsOnboarding ?? () => false;
    return GoRouter(
      initialLocation: initialLocation,
      navigatorKey: navigatorKey,
      debugLogDiagnostics: false,
      // **Phase 8A: without this the gates are decorative.** A `redirect` runs on navigation and
      // whenever `refreshListenable` fires, and nothing else — so unlocking updated the state and left
      // the user on the lock screen looking at a correct boolean. `routerRefreshProvider` supplies it.
      refreshListenable: refreshListenable,
      redirect: (context, state) {
        final location = state.matchedLocation;

        // **A prefix test, not an equality test, and that is a fix rather than a refinement.** The
        // gate previously compared against `Routes.lock` exactly, which was harmless while `/lock` was
        // a leaf — and silently unreachable the moment 8A added `/lock/recovery` beneath it. A locked
        // user tapping "I have forgotten my PIN" would have been bounced straight back to the screen
        // they were trying to leave.
        final inLockBranch = location == Routes.lockBranch ||
            location.startsWith('${Routes.lockBranch}/');
        if (locked()) return inLockBranch ? null : Routes.lock;
        if (inLockBranch) return Routes.dashboard;

        // **Checked after the lock, not before.** A lock protects data that onboarding is about to add
        // to; asking someone to finish setting up an app they cannot yet open would be the wrong order.
        if (onboarding()) {
          return location == Routes.onboarding ? null : Routes.onboarding;
        }
        if (location == Routes.onboarding) return Routes.dashboard;
        return null;
      },
      routes: [
        // Literal before parameterised, and **`/lock/recovery` before `/lock`**: go_router walks this
        // list in order, and a `/lock` declared first would match the prefix and swallow its own child.
        GoRoute(
          path: Routes.lockRecovery,
          builder: (context, state) => const RecoveryFlow(),
        ),
        GoRoute(
          path: Routes.lock,
          builder: (context, state) => const LockScreen(),
        ),
        // No `_DetailScaffold`: onboarding brings its own chrome, and a back arrow into a shell the
        // user has not reached yet would be a way out of a flow with nothing behind it.
        GoRoute(
          path: Routes.onboarding,
          builder: (context, state) => const OnboardingFlow(),
        ),
        ShellRoute(
          // No `location` passed: `_ShellScaffold` reads it from the router, because the state handed to a
          // pathless `ShellRoute`'s builder reports `/` for every screen inside it.
          builder: (context, state, child) => _ShellScaffold(child: child),
          routes: [
            GoRoute(
              path: Routes.dashboard,
              builder: (context, state) => const DashboardScreen(),
            ),
            GoRoute(
              path: Routes.expenses,
              builder: (context, state) => const TransactionListScreen(),
            ),
            GoRoute(
              path: Routes.inventory,
              builder: (context, state) => const InventoryListScreen(),
            ),
            GoRoute(
              path: Routes.shopping,
              builder: (context, state) => const ShoppingListScreen(),
            ),
            GoRoute(
              path: Routes.recurring,
              builder: (context, state) => const TemplateListScreen(),
            ),
            GoRoute(
              path: Routes.services,
              builder: (context, state) => const AssetListScreen(),
            ),
            GoRoute(
              path: Routes.calendar,
              builder: (context, state) => const CalendarScreen(),
              routes: [
                // A sub-route rather than a sibling detail route: a day is a view of the month, so it
                // keeps the drawer shell and the month stays behind it (Law U27).
                GoRoute(
                  path: ':${Routes.pDateKey}',
                  builder: (context, state) => CalendarScreen(
                    initialDay: _dateKeyParam(
                      state.pathParameters[Routes.pDateKey],
                    ),
                  ),
                ),
              ],
            ),
            GoRoute(
              path: Routes.insights,
              builder: (context, state) => const AnalyticsHomeScreen(),
            ),
            GoRoute(
              path: Routes.settings,
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
        GoRoute(
          path: Routes.transactionNew,
          builder: (context, state) => const TransactionEditorScreen(),
        ),
        GoRoute(
          path: Routes.transactionLinesNew,
          builder: (context, state) => const LineItemsScreen(),
        ),
        GoRoute(
          path: Routes.transactionLinesPattern,
          builder: (context, state) => LineItemsScreen(
            transactionId: state.pathParameters[Routes.pTransactionId],
          ),
        ),
        GoRoute(
          path: Routes.transactionEditPattern,
          builder: (context, state) => TransactionEditorScreen(
            transactionId: state.pathParameters[Routes.pTransactionId],
          ),
        ),
        GoRoute(
          path: Routes.transactionDetailPattern,
          builder: (context, state) => TransactionDetailScreen(
            transactionId: state.pathParameters[Routes.pTransactionId]!,
          ),
        ),
        GoRoute(
          path: Routes.itemNew,
          builder: (context, state) => const ItemEditorScreen(),
        ),
        GoRoute(
          path: Routes.batchNewPattern,
          builder: (context, state) => BatchEditorScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
          ),
        ),
        GoRoute(
          path: Routes.batchHistoryPattern,
          builder: (context, state) => BatchHistoryScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
            batchId: state.pathParameters[Routes.pBatchId]!,
          ),
        ),
        GoRoute(
          path: Routes.batchEditPattern,
          builder: (context, state) => BatchEditorScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
            batchId: state.pathParameters[Routes.pBatchId],
          ),
        ),
        GoRoute(
          path: Routes.itemEditPattern,
          builder: (context, state) => ItemEditorScreen(
            itemId: state.pathParameters[Routes.pItemId],
          ),
        ),
        GoRoute(
          path: Routes.itemDetailPattern,
          builder: (context, state) => ItemDetailScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
          ),
        ),
        GoRoute(
          path: Routes.shoppingConvertPattern,
          builder: (context, state) => ConvertToPurchaseScreen(
            listId: state.pathParameters[Routes.pListId]!,
          ),
        ),
        GoRoute(
          path: Routes.shoppingListPattern,
          builder: (context, state) => ShoppingListScreen(
            listId: state.pathParameters[Routes.pListId],
          ),
        ),
        GoRoute(
          path: Routes.recurringNew,
          builder: (context, state) => const TemplateBuilderScreen(),
        ),
        GoRoute(
          path: Routes.recurringHistoryPattern,
          builder: (context, state) => OccurrenceHistoryScreen(
            templateId: state.pathParameters[Routes.pTemplateId]!,
          ),
        ),
        GoRoute(
          path: Routes.recurringEditPattern,
          builder: (context, state) => TemplateBuilderScreen(
            templateId: state.pathParameters[Routes.pTemplateId],
          ),
        ),
        GoRoute(
          path: Routes.recurringDetailPattern,
          builder: (context, state) => OccurrenceHistoryScreen(
            templateId: state.pathParameters[Routes.pTemplateId]!,
          ),
        ),
        GoRoute(
          path: Routes.assetNew,
          builder: (context, state) => const AssetEditorScreen(),
        ),
        GoRoute(
          path: Routes.serviceNewPattern,
          builder: (context, state) => ServiceEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
          ),
        ),
        GoRoute(
          path: Routes.serviceEditPattern,
          builder: (context, state) => ServiceEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
            recordId: state.pathParameters[Routes.pRecordId],
          ),
        ),
        GoRoute(
          path: Routes.assetEditPattern,
          builder: (context, state) => AssetEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId],
          ),
        ),
        GoRoute(
          path: Routes.assetDetailPattern,
          builder: (context, state) => AssetDetailScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
          ),
        ),
        GoRoute(
          path: Routes.insightsDrillDownPattern,
          builder: (context, state) => DrillDownScreen(
            // Parsed rather than trusted: this route is deep-linkable, so an unknown axis has to reach
            // the screen as null and be explained there rather than throwing in a builder.
            spec: DrillDownSpec.parse(
              kind: state.pathParameters[Routes.pDrillKind],
              value: state.pathParameters[Routes.pDrillValue],
            ),
          ),
        ),
        GoRoute(
          path: Routes.themeLab,
          builder: (context, state) => _DetailScaffold(
            title: AlayaStrings.of(context).navThemeLab,
            child: const ThemeLabScreen(),
          ),
        ),
        // **Every settings branch sits outside the shell.** `/settings` is the drawer destination; its
        // children are reached *from* it and need a back arrow, which a shell owning a drawer can never
        // imply (Law U18). Each one brings its own `Scaffold` and app bar, so none uses
        // `_DetailScaffold` — a catalogue needs a pinned search field and an overflow of its own, which
        // that wrapper does not offer (ARCH_5 §3 archetype D).
        //
        // The literal children of `/settings/accounts`, `/settings/tags` and `/settings/units` are
        // declared before their parameterised siblings, or `:accountId` swallows the word `new`.
        GoRoute(
          path: Routes.accountNew,
          builder: (context, state) => const AccountEditorScreen(),
        ),
        GoRoute(
          path: Routes.accountEditPattern,
          builder: (context, state) => AccountEditorScreen(
            accountId: state.pathParameters[Routes.pAccountId],
          ),
        ),
        GoRoute(
          path: Routes.settingsAccounts,
          builder: (context, state) => const AccountsSettingsScreen(),
        ),
        GoRoute(
          path: Routes.tagNew,
          builder: (context, state) => const TagEditorScreen(),
        ),
        GoRoute(
          path: Routes.tagEditPattern,
          builder: (context, state) => TagEditorScreen(
            tagId: state.pathParameters[Routes.pTagId],
          ),
        ),
        GoRoute(
          path: Routes.settingsTags,
          builder: (context, state) => const TagsSettingsScreen(),
        ),
        GoRoute(
          path: Routes.unitNew,
          builder: (context, state) => const UnitEditorScreen(),
        ),
        GoRoute(
          path: Routes.unitEditPattern,
          builder: (context, state) => UnitEditorScreen(
            unitCode: state.pathParameters[Routes.pUnitCode],
          ),
        ),
        GoRoute(
          path: Routes.settingsUnits,
          builder: (context, state) => const UnitsSettingsScreen(),
        ),
        GoRoute(
          path: Routes.settingsPaymentMethods,
          builder: (context, state) => const PaymentMethodsSettingsScreen(),
        ),
        GoRoute(
          path: Routes.settingsPayees,
          builder: (context, state) => const PayeesSettingsScreen(),
        ),
        GoRoute(
          path: Routes.settingsCurrencies,
          builder: (context, state) => const CurrenciesSettingsScreen(),
        ),
        GoRoute(
          path: Routes.settingsAppearance,
          builder: (context, state) => const AppearanceSettingsScreen(),
        ),
        // `/settings/security/pin` before `/settings/security`, for the same ordering reason.
        GoRoute(
          path: Routes.settingsPin,
          builder: (context, state) => const PinSetupFlow(),
        ),
        GoRoute(
          path: Routes.settingsSecurity,
          builder: (context, state) => const SecuritySettingsScreen(),
        ),
        GoRoute(
          path: Routes.settingsData,
          builder: (context, state) => const DataSettingsScreen(),
        ),
        GoRoute(
          path: Routes.settingsAbout,
          builder: (context, state) => const AboutSettingsScreen(),
        ),
      ],
    );
  }
}

class _ShellScaffold extends StatelessWidget {
  const _ShellScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // `AppBar` resolves its implied leading by checking `hasDrawer` **before** `canPop`, so a shell that
    // owns a drawer can never show a back arrow no matter how it was reached. That is fine for a drawer
    // destination switched into as a peer, and wrong for one pushed as a drill-down — and both happen
    // here: the drawer `go`es, the dashboard's module grid `push`es.
    //
    // So the slot is stated rather than implied. Pushed: a back arrow that pops the shell's own navigator
    // (`context.pop`, not `Navigator.maybePop`, which from above the shell navigator would target the root
    // one and do nothing). Switched into: null, which lets the hamburger be implied as before.
    //
    // The drawer stays attached either way, so the edge swipe still opens it on a pushed screen.
    final strings = AlayaStrings.of(context);

    // **Read from the router, not from the builder's `state`.** `ShellRoute` declares no `path`, so the
    // `GoRouterState` handed to its builder describes the *shell's* match rather than the leaf's — and a
    // pathless route's `matchedLocation` is its parent's, which here is `/`. Every screen inside the shell
    // therefore looked like the dashboard: `atDashboard` was permanently true so the home action never
    // rendered, `AlayaDrawer` highlighted Dashboard wherever you were, and `titleFor` named it too.
    //
    // `currentConfiguration` is the delegate's live `RouteMatchList`, so its `uri` is the leaf location no
    // matter which builder asks.
    final here = GoRouter.of(context).routerDelegate.currentConfiguration.uri.path;

    // **`context.canPop()` cannot answer this question from here.** This widget is the `ShellRoute`
    // builder, so its context sits *above* the shell's own `Navigator`; `canPop` resolves against the
    // root navigator, which only ever holds the shell itself. It therefore returns false however the
    // screen was reached, `leading` was always null, and the back arrow this once tried to show could
    // never appear. The drawer's hamburger was the only leading widget users ever saw, and from a module
    // the sole way home was the system back gesture.
    //
    // So the way home is stated outright instead of inferred from a stack this context cannot see: every
    // shell screen except the dashboard carries a home action. It pops when there is something to pop and
    // navigates otherwise, so arriving by the module grid's `push` and by the drawer's `go` both end up
    // in the same place — and the hamburger keeps its slot, because the drawer is still how you move
    // between peers (Law U27).
    return Scaffold(
      drawer: AlayaDrawer(currentLocation: here),
      appBar: AppBar(
        title: Text(AlayaDrawer.titleFor(context, here)),
        // **Unconditional, deliberately.** This was `if (!atDashboard)` and never appeared, and rather
        // than reason about why a condition is false I would rather the button exist and be seen. It
        // shows on the dashboard too, where it is merely redundant — a redundant button is a far smaller
        // fault than a missing one, and its presence there is also the proof that this file is live.
        //
        // Once it is confirmed visible, `if (!atDashboard)` can come back.
        actions: [
          IconButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go(Routes.dashboard),
            tooltip: strings.navBackToDashboard,
            icon: const Icon(Icons.home_outlined, size: AlayaIconSize.md),
          ),
        ],
      ),
      body: child,
    );
  }
}

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: child,
  );
}

/// Parses a `:dateKey` path parameter, or null when it is absent or not a date key.
///
/// A malformed deep link opens the calendar on today rather than throwing — the route is reachable
/// from outside the app.
DateKey? _dateKeyParam(String? raw) {
  final value = int.tryParse(raw ?? '');
  if (value == null) return null;

  final year = value ~/ 10000;
  final month = (value ~/ 100) % 100;
  final day = value % 100;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;

  // Round-trip through `fromYmd`, which normalises overflow through `DateTime.utc`: 20260230 comes
  // back as 20260302 and fails this check, where a digit-range test alone would accept it.
  final probe = DateKey.fromYmd(year, month, day);
  return probe.value == value ? probe : null;
}
```

---

## The layering decision, taken

**Not one of the seven delivered UI phases imports `data/` from a feature** — I checked all of them — and
ARCH_1 §6 draws `features → domain → core` and `data → domain → core` as two separate chains. But every
service 8A's screens must drive is a concrete class in `data/`: `PinService` and its `UnlockOutcome`,
`BackupService`, `EraseService`, and `local_auth` itself. A lock screen that branches on `UnlockRefusal`
and reads `retryAfter` for its countdown would have been the first feature to cross that line.

So the services get domain contracts, exactly as `AnalyticsPort` has one. **The deciding argument turned
out not to be architectural purity.** `flutter_secure_storage` and `local_auth` both need a platform
channel, so a widget test of the lock screen's four states cannot run against `PinService` or
`LocalAuthentication` at all — and §9.1 requires four tests per screen. Behind a port they run against a
fake, which is the same reason `Clock` and `SecureKeyValueStore` were made interfaces in the first place.
Without this the phase's own gate is unreachable.

Three ports in `domain/`, three implementations in `data/`, and one fact that made it cheap:
**`BackupArtefact` is a record typedef**, so the `domain/` and `data/` names refer to the same structural
type and no adapter or cast is needed anywhere.

**A correction to what I said last time.** I described `file_picker` as being for restore. ARCH_3 §3.3 is
clearer than that: it is the Storage Access Framework intent for *both* save and open. It still stays out
of 8A, but for a better reason — this phase only ever **shares** (one tap to WhatsApp or Drive, which is
what both its prompts want), and "Save to…" arrives with 8B's Backup screen. So `path_provider` and
`share_plus` are imported here and `file_picker` is 8B's.

Also from §3.4, and binding on the screens that follow: the not-encrypted warning appears on the export
confirmation **every time** — not in settings, not a tooltip.

### `lib/domain/services/lock/app_lock.dart`

```dart
/// The app lock's contract, and the vocabulary an unlock attempt answers in.
///
/// **Why this exists in `domain/` when `PinService` already exists in `data/`.** `PinService` reaches
/// `flutter_secure_storage` through `AppLockStore`, and Law L12 bars a plugin dependency from `domain/`
/// — which is why it was written in `data/` in the first place. But ARCH_1 §6 draws `features → domain →
/// core` and `data → domain → core` as two separate chains, and not one of the seven delivered UI phases
/// imports `data/` from a feature. A lock screen that must branch on [UnlockRefusal] and read
/// [UnlockOutcome.retryAfter] for its countdown would have been the first.
///
/// **The deciding argument is not purity, and it is stronger than a layering diagram.** `PinService` is
/// declared `final class`, which in Dart 3 means it can be neither extended nor implemented outside its
/// own library — so a test fake of it is not awkward, it is **impossible**. `flutter_secure_storage` needs
/// a platform channel, so the real one cannot run in a widget test either. Between the two, the lock
/// screen's four required states (§9.1) had no way to be tested at all. Behind this interface they test
/// against a fake, which is the same reason `Clock` and `SecureKeyValueStore` are interfaces rather than
/// direct plugin calls. `BackupService` is `final` too, and `DataTransferPort` exists for the same reason.
///
/// This is the `AnalyticsPort` pattern: the contract in `domain/`, the plugin-bound implementation in
/// `data/`, the provider typed as the contract so no feature can reach past it.
library;

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';

/// Why an unlock attempt was refused.
enum UnlockRefusal {
  /// The PIN was wrong.
  wrongPin,

  /// Too many wrong attempts; a delay is in force.
  throttled,

  /// No lock is configured, so there is nothing to unlock.
  notEnabled,
}

/// The outcome of an unlock attempt.
class UnlockOutcome {
  /// Creates an outcome.
  const UnlockOutcome({
    required this.unlocked,
    this.refusal,
    this.failedCount = 0,
    this.retryAfter,
  });

  /// A successful unlock.
  const UnlockOutcome.success()
      : unlocked = true,
        refusal = null,
        failedCount = 0,
        retryAfter = null;

  /// Whether the app should open.
  final bool unlocked;

  /// Why not, when [unlocked] is false.
  final UnlockRefusal? refusal;

  /// How many consecutive wrong attempts have now been recorded.
  final int failedCount;

  /// How long the user must wait before the next attempt is even checked.
  final Duration? retryAfter;

  /// True when a delay is currently in force.
  bool get isThrottled => refusal == UnlockRefusal.throttled;
}

/// Verifies, changes, enables and disables the app lock.
///
/// **No encryption, and the contract says so where an implementer will read it.** The lock is a UI gate
/// over a plaintext database (ARCH_1 §2.1): nothing here derives a database key, and nothing here can
/// lock a user out of their own data. That is what makes the "forgot both" path able to export a readable
/// backup before erasing, which is the improvement dropping encryption bought (ARCH_3 §2.2).
abstract interface class AppLock {
  /// How many characters a recovery code has (ARCH_3 §2.1).
  ///
  /// **On the contract because the field that accepts one needs it**, and `RecoveryCode.length` lives in
  /// `data/` where a feature may not reach. A counter that disagreed with the validator would tell the
  /// user their correct code was the wrong length.
  static const int recoveryCodeLength = 10;

  /// Whether a lock is configured.
  Future<bool> get isEnabled;

  /// How many digits the configured PIN has.
  Future<int> readPinLength();

  /// How long until the next attempt will be checked, or null when none is owed.
  Future<Duration?> remainingLockout();

  /// How many consecutive wrong attempts have been recorded.
  ///
  /// Read by the optional auto-erase, which fires at ARCH_3 §2.3's tenth failure — the count has to be
  /// legible to the caller for that, not only to the throttle.
  Future<int> readFailedCount();

  /// Attempts to unlock with [pin].
  Future<UnlockOutcome> verifyPin(String pin);

  /// Enables the lock with [pin], returning the recovery code to show **once**.
  Future<Result<String, Failure>> enable({required String pin});

  /// Changes the PIN, verifying [currentPin] first. The recovery code is unchanged.
  Future<Result<void, Failure>> changePin({
    required String currentPin,
    required String newPin,
  });

  /// Disables the lock, verifying [pin] first.
  Future<Result<void, Failure>> disable({required String pin});

  /// Resets the PIN using [code], for the forgotten-PIN path.
  Future<Result<void, Failure>> resetWithRecoveryCode({
    required String code,
    required String newPin,
  });
}
```

### `lib/domain/services/lock/biometric_gate.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';

/// Why a biometric prompt did not unlock.
enum BiometricRefusal {
  /// The device has no enrolled biometric, or none the app may use.
  unavailable,

  /// The user dismissed the prompt or failed the check.
  rejected,

  /// The platform refused — too many attempts, or a hardware lockout of its own.
  lockedOut,
}

/// The biometric shortcut on the lock screen (ARCH_3 §2.2).
///
/// **A shortcut and nothing more, which is why the contract is this small.** No key material is involved
/// — the database is plaintext and the PIN is a UI gate — so a successful biometric check is exactly as
/// authoritative as a correct PIN and no more. Anything richer here would imply otherwise.
///
/// A port because `local_auth` needs a platform channel: without one, a widget test of the lock screen
/// could not run, and §9.1 requires four of them per screen.
abstract interface class BiometricGate {
  /// Whether this device can offer the shortcut at all.
  ///
  /// Checked before the button is shown rather than after it is pressed. Offering a shortcut that then
  /// says "not available" is the control ARCH_5 §10 objects to — one that looks live and is not.
  Future<bool> get isAvailable;

  /// Prompts, returning the refusal rather than throwing when it does not succeed.
  ///
  /// [reason] is the already-localised sentence the platform shows, so no string literal reaches the
  /// plugin (Law U5).
  Future<Result<void, Failure>> authenticate({required String reason});
}
```

### `lib/domain/services/backup/data_transfer_port.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';

/// What an export produced.
///
/// Moved here from `data/` in 8A so a feature can name it. A record of four plain values with no drift
/// or Flutter dependency, so `domain/` is a legal home for it on Law L12's own terms.
typedef BackupArtefact = ({String path, int sizeBytes, bool isZipped, String fileName});

/// Exporting the database, and erasing it.
///
/// **One port for both, because they are the two halves of the same conversation.** ARCH_3 §2.2's
/// forgot-both path offers an export *and then* erases, and a user who is about to lose everything
/// should not have that offer come from a different subsystem than the erase does.
///
/// **Why a port at all.** The export needs a destination path (`path_provider`) and a way to hand the
/// file off (`share_plus`), and both are plugins — so a feature orchestrating them directly would be
/// untestable, and Law L12 keeps plugin dependencies out of `domain/`. The screens see this; `data/`
/// owns the platform.
abstract interface class DataTransferPort {
  /// The word the user must type before an erase runs (ARCH_3 §2.2).
  ///
  /// **On the contract, because the screen that compares against it may not import `data/`** — and
  /// because a second copy in the UI would be a second thing to change. Not localised, and the only
  /// user-facing string in this project exempt from Law U5: a translated confirmation word would mean a
  /// support article could not tell anyone what to type, and the point of the gate is that it cannot be
  /// satisfied by tapping.
  static const String eraseConfirmationWord = 'ERASE';

  /// Writes a backup somewhere the user can reach and offers to share it.
  ///
  /// Returns the artefact so a screen can state the file name and size — a backup the user cannot
  /// identify later is one they will not trust when they need it (ARCH_3 §3.4).
  Future<Result<BackupArtefact, Failure>> exportAndShare();

  /// Deletes every row, clears the lock, and re-seeds.
  ///
  /// **Clears the lock too, and that is the point.** A user who has forgotten their PIN *and* their
  /// recovery code is locked out; wiping their history while leaving the lock in place would leave them
  /// exactly as locked out, with nothing left to unlock.
  Future<Result<void, Failure>> eraseEverything();
}
```

### `lib/data/security/local_auth_biometric_gate.dart`

```dart
import 'package:local_auth/local_auth.dart';

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/services/lock/biometric_gate.dart';

/// The production [BiometricGate], over `local_auth`.
///
/// **The only file in this phase that imports `local_auth`.** Confining it is the same containment 7A
/// applied to `table_calendar` and 7B to `fl_chart` — the plugin's surface could not be compiled against
/// in the session that wrote this (ARCH_4 R22), so if it differs, one file changes rather than the lock
/// screen.
///
/// **Every failure is a `Result`, never an exception.** `local_auth` throws a `PlatformException` for a
/// missing enrolment, a hardware lockout and a user cancellation alike, and a lock screen that crashes
/// because somebody tapped the wrong thing is worse than one with no shortcut at all.
final class LocalAuthBiometricGate implements BiometricGate {
  /// Creates the gate over [auth].
  const LocalAuthBiometricGate(this._auth);

  final LocalAuthentication _auth;

  /// Whether the shortcut is offered at all.
  ///
  /// **False, and that is a security decision rather than a stub.** Two attempts at the installed
  /// `local_auth`'s signature were rejected by the analyzer — first `options: AuthenticationOptions(...)`,
  /// then `stickyAuth:`/`biometricOnly:` as direct parameters — so `authenticate` here accepts
  /// `localizedReason` and nothing this file can identify.
  ///
  /// Without `biometricOnly`, the platform prompt may offer **device-credential fallback**: the phone's own
  /// PIN or pattern would satisfy Alaya's lock. That is precisely the threat ARCH_3 §2.5 says this lock
  /// exists for — someone holding an already-unlocked phone — so shipping the shortcut unconstrained would
  /// quietly undo the guarantee the lock screen makes in writing.
  ///
  /// A convenience is the right thing to lose to uncertainty. The shortcut is optional in ARCH_3 §2.2,
  /// `LockScreen` already omits the key entirely when this is false (asserted in `lock_screen_test.dart`),
  /// and re-enabling it is this one constant plus the options `authenticate` turns out to accept.
  static const bool shortcutEnabled = false;

  @override
  Future<bool> get isAvailable async {
    if (!shortcutEnabled) return false;
    try {
      // Both checks, because they answer different questions: the device may have the hardware while
      // the user has enrolled nothing, and offering a shortcut that cannot work is the dead control
      // ARCH_5 §10 objects to.
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      return _auth.canCheckBiometrics;
    } on Object {
      return false;
    }
  }

  @override
  Future<Result<void, Failure>> authenticate({required String reason}) async {
    try {
      // `localizedReason` only: it is the one parameter every published `local_auth` signature has agreed
      // on. **Unreachable while [shortcutEnabled] is false**, and the options that constrain the prompt to
      // biometrics must be restored here before that flag is flipped back.
      final ok = await _auth.authenticate(localizedReason: reason);
      return ok
          ? const Result.ok(null)
          : const Result.failure(
              BusinessRuleFailure('Not recognised.', rule: 'biometricRejected'),
            );
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The fingerprint check could not run.', cause: error),
      );
    }
  }
}
```

### `lib/data/backup/share_backup_transfer.dart`

```dart
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/data/backup/backup_service.dart';
import 'package:alaya/data/backup/erase_service.dart';
import 'package:alaya/domain/services/backup/data_transfer_port.dart' as port;

/// The production [port.DataTransferPort]: `VACUUM INTO` into the cache, then the system share sheet.
///
/// **The only file in this phase that imports `path_provider` or `share_plus`,** for the same
/// containment reason as the biometric gate. `share_plus` is the sharper edge of the two: its v11
/// replaced `Share.shareXFiles` with `SharePlus.instance.share(ShareParams(...))`, and that call could
/// not be compiled against here (ARCH_4 R22). If it has moved again, this file is the only casualty.
///
/// **Share, not save-to.** ARCH_3 §3.3 gives export two shapes: a Storage Access Framework
/// *create-document* intent where the user picks a location, and a `share_plus` hand-off. This phase
/// needs only the second — its two prompts are "make a backup now?" after setting a PIN and "export
/// first" before erasing, and both want one tap to WhatsApp or Drive rather than a file browser. The SAF
/// path arrives with 8B's Backup screen, which is why `file_picker` is 8B's dependency and not this
/// phase's.
///
/// The file lands in the **cache** directory rather than documents, because it is a hand-off rather than
/// a stored artefact: the OS may reclaim it once shared, which is the correct lifetime for a copy of
/// every balance the user owns.
final class ShareBackupTransfer implements port.DataTransferPort {
  /// Creates the transfer over [backup] and [erase].
  const ShareBackupTransfer({
    required BackupService backup,
    required EraseService erase,
  })  : _backup = backup,
        _erase = erase;

  final BackupService _backup;
  final EraseService _erase;

  @override
  Future<Result<port.BackupArtefact, Failure>> exportAndShare() async {
    try {
      final directory = await getApplicationCacheDirectory();
      final name = _backup.suggestedFileName(zipped: false);
      final destination = '${directory.path}${Platform.pathSeparator}$name';

      final exported = await _backup.export(destinationPath: destination);
      final artefact = exported.valueOrNull;
      if (artefact == null) {
        return Result.failure(
          exported.failureOrNull ??
              const UnexpectedFailure('The backup could not be written.'),
        );
      }

      await SharePlus.instance.share(
        ShareParams(files: [XFile(artefact.path)]),
      );
      return Result.ok(artefact);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The backup could not be shared.', cause: error),
      );
    }
  }

  @override
  Future<Result<void, Failure>> eraseEverything() => _erase.eraseEverything();
}
```

### `lib/features/onboarding/state/onboarding_state.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';

/// Which step of the first-run flow the user is on.
///
/// Stored by name, so resuming survives a restart and a reorder of this enum does not silently move
/// somebody to a different step (Law L13's reasoning, applied to a settings row rather than a column).
enum OnboardingStep {
  /// Which currency totals are shown in.
  currency,

  /// The accounts, and what was in them when the user started.
  accounts,

  /// The optional lock.
  security,

  /// Finished or skipped.
  done,
}

/// How the first-run flow is stored.
abstract final class OnboardingKeys {
  /// The `app_settings` key holding whether onboarding is finished or was skipped.
  static const String done = 'onboarding.done';

  /// The `app_settings` key holding the furthest step reached.
  ///
  /// **Written on every step change, which is what "resumable" costs.** A flow that only records
  /// completion would restart from the beginning after a phone call at step two, and re-asking someone
  /// for their opening balances is the fastest way to have them skip the flow entirely.
  static const String step = 'onboarding.step';

  /// Parses a stored step name, falling back to the first step.
  static OnboardingStep parseStep(String? stored) {
    for (final step in OnboardingStep.values) {
      if (step.name == stored) return step;
    }
    return OnboardingStep.currency;
  }
}

/// One account being set up, before it is saved.
///
/// A draft rather than an `Account`, because an `Account` requires a `normalizedName` and a `sortOrder`
/// that the user never sees and should not have to think about, and because half of these rows already
/// exist in the database — Phase 1C's seeder creates two — so the flow is editing as much as creating.
class DraftAccount {
  /// Creates a draft.
  const DraftAccount({
    required this.name,
    required this.kind,
    required this.currencyCode,
    required this.openingMinor,
    required this.openingDate,
    this.id,
    this.includeInNetWorth = true,
    this.currencyTouched = false,
  });

  /// A draft of an account that already exists, keeping every value it has.
  factory DraftAccount.from(Account account) => DraftAccount(
        id: account.id,
        name: account.name,
        kind: account.kind,
        currencyCode: account.currencyCode,
        openingMinor: account.openingBalance.minor,
        openingDate: account.openingBalanceDateKey,
        includeInNetWorth: account.includeInNetWorth,
      );

  /// The existing account's id, or null for one being added.
  final String? id;

  /// What the user calls it.
  final String name;

  /// Cash, bank, wallet, card or other.
  final AccountKind kind;

  /// The currency the balance is held in.
  ///
  /// Its own field and not derived from the home currency, because Law L9 makes the home currency a
  /// display choice: an account in yen stays in yen however the user chooses to see totals.
  final String currencyCode;

  /// What was in it on [openingDate], in minor units.
  final int openingMinor;

  /// The date the balance was true on.
  ///
  /// **This is the half of the pair that gets forgotten** (anomaly A03). A balance without a date
  /// cannot be placed in a ledger, so every transaction before it would be silently unaccounted for.
  final DateKey openingDate;

  /// Whether it counts toward net worth.
  final bool includeInNetWorth;

  /// Whether the user has chosen this account's currency themselves.
  ///
  /// **Why a flag and not a comparison.** Changing the home currency on step one should carry the
  /// seeded accounts with it — nobody choosing yen wants two rupee accounts they did not ask for — but
  /// it must not overwrite a currency the user set deliberately. Comparing against the old home
  /// currency cannot tell those apart when they happen to match.
  final bool currencyTouched;

  /// The balance as a `Money`.
  Money get openingBalance => Money(openingMinor, currencyCode);

  /// Whether this draft is complete enough to save.
  bool get isValid => name.trim().isNotEmpty && currencyCode.isNotEmpty;

  /// A copy with the given fields replaced.
  DraftAccount copyWith({
    String? name,
    AccountKind? kind,
    String? currencyCode,
    int? openingMinor,
    DateKey? openingDate,
    bool? includeInNetWorth,
    bool? currencyTouched,
  }) =>
      DraftAccount(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        currencyCode: currencyCode ?? this.currencyCode,
        openingMinor: openingMinor ?? this.openingMinor,
        openingDate: openingDate ?? this.openingDate,
        includeInNetWorth: includeInNetWorth ?? this.includeInNetWorth,
        currencyTouched: currencyTouched ?? this.currencyTouched,
      );
}

/// Everything the first-run flow is holding.
class OnboardingDraft {
  /// Creates a draft.
  const OnboardingDraft({
    required this.step,
    required this.homeCurrencyCode,
    required this.accounts,
    this.isLoaded = false,
    this.isSaving = false,
    this.lockEnabled = false,
    this.failureMessage,
  });

  /// The step being shown.
  final OnboardingStep step;

  /// The currency totals are aggregated into (Law L9).
  final String homeCurrencyCode;

  /// The accounts being set up, seeded ones included.
  final List<DraftAccount> accounts;

  /// Whether the existing accounts and settings have been read yet.
  final bool isLoaded;

  /// Whether a save is in flight.
  final bool isSaving;

  /// Whether a lock was set during this flow.
  final bool lockEnabled;

  /// The repository's own message from the last failed write (Law U9).
  final String? failureMessage;

  /// Whether every account is complete enough to save.
  bool get accountsAreValid =>
      accounts.isNotEmpty && accounts.every((account) => account.isValid);

  /// A copy with the given fields replaced.
  ///
  /// [failureMessage] is cleared by passing [clearFailure], because `null` cannot distinguish "leave it"
  /// from "clear it" in a `copyWith` — and a stale error under a field the user has since fixed is worse
  /// than no error at all.
  OnboardingDraft copyWith({
    OnboardingStep? step,
    String? homeCurrencyCode,
    List<DraftAccount>? accounts,
    bool? isLoaded,
    bool? isSaving,
    bool? lockEnabled,
    String? failureMessage,
    bool clearFailure = false,
  }) =>
      OnboardingDraft(
        step: step ?? this.step,
        homeCurrencyCode: homeCurrencyCode ?? this.homeCurrencyCode,
        accounts: accounts ?? this.accounts,
        isLoaded: isLoaded ?? this.isLoaded,
        isSaving: isSaving ?? this.isSaving,
        lockEnabled: lockEnabled ?? this.lockEnabled,
        failureMessage: clearFailure ? null : (failureMessage ?? this.failureMessage),
      );
}
```

## Putting the services behind the contracts

`PinService` keeps every line of its throttle and its constant-time compare; what changes is that
`UnlockOutcome` and `UnlockRefusal` now come from `domain/` instead of being declared here, and it says
`implements AppLock`. It also gains two delegating reads — `readPinLength` and `readFailedCount` — because
the UI needs both (a 4- or 6-box keypad, and ARCH_3 §2.3's tenth failure) and reaching around this class
to `AppLockStore` would put a second consumer on fields only this class should interpret.

`SettingsRepository` gains `writeHomeCurrencyCode`, the counterpart of the `readHomeCurrencyCode` that has
existed since 3A. Onboarding has to write that key, the key lives in `data/repositories/settings_keys.dart`,
and a feature may not import `data/` — so the alternative was a duplicated literal in the onboarding
feature that would write to a dead key the moment `data/` renamed it. It routes through `writeValue`, so
there is still one write path (Law U22).

`pinServiceProvider` is retyped `Provider<AppLock>`. Three providers join it, and **all three are typed as
the contract** so no feature can reach a plugin.

Carried, so their documents regenerate: PHASE_04C, PHASE_03A, PHASE_03B, PHASE_05.

### `lib/data/security/pin_service.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/security/app_lock_store.dart';
import 'package:alaya/data/security/recovery_code.dart';
import 'package:alaya/domain/services/lock/app_lock.dart';

/// Verifies, changes, enables and disables the app lock, and enforces ARCH_3 §2.3's throttle.
///
/// **No encryption.** The lock is a UI gate over a plaintext database (ARCH_1 §2.1), so nothing here
/// derives a database key and nothing here can lock a user out of their own data — the "forgot both"
/// path can still export a readable backup, which is the improvement dropping encryption bought.
final class PinService implements AppLock {
  /// Creates the service.
  PinService({
    required AppLockStore store,
    required Clock clock,
    RecoveryCode? recoveryCode,
  })  : _store = store,
        _clock = clock,
        _recoveryCode = recoveryCode ?? RecoveryCode();

  final AppLockStore _store;
  final Clock _clock;
  final RecoveryCode _recoveryCode;

  /// The delay owed after [failures] consecutive wrong attempts (ARCH_3 §2.3).
  ///
  /// The first four are free, because a mistyped digit on a phone keyboard is ordinary and punishing
  /// it would make the lock hostile to its owner rather than to an attacker. From the fifth the delay
  /// grows: 30 s, 1 min, 5 min, then 15 min doubling to a one-hour ceiling.
  ///
  /// The ceiling exists on purpose. Unbounded doubling would eventually lock the legitimate owner out
  /// for days over a forgotten PIN — and against an attacker, one hour per attempt already reduces
  /// the 10,000-value four-digit space to years. Past that point more delay costs the owner
  /// everything and the attacker nothing.
  static Duration delayAfterFailures(int failures) {
    if (failures <= 4) return Duration.zero;
    if (failures == 5) return const Duration(seconds: 30);
    if (failures == 6) return const Duration(minutes: 1);
    if (failures == 7) return const Duration(minutes: 5);
    final doublings = failures - 8;
    final minutes = 15 * (1 << doublings);
    return Duration(minutes: minutes > 60 ? 60 : minutes);
  }

  @override
  Future<bool> get isEnabled => _store.isEnabled;

  /// How many digits the configured PIN has.
  ///
  /// Delegated rather than reimplemented: the store owns the value because it is written alongside the
  /// hash, and a second source of truth for "is this a 4- or 6-box keypad" would eventually disagree
  /// with the PIN it is asking for.
  @override
  Future<int> readPinLength() => _store.readPinLength();

  /// How many consecutive wrong attempts have been recorded.
  ///
  /// Exposed for the optional auto-erase, which fires at ARCH_3 §2.3's tenth failure. The throttle
  /// already reads this internally; the caller needs it too, and reaching around this class to the store
  /// would put a second consumer on a field only this class is supposed to interpret.
  @override
  Future<int> readFailedCount() => _store.readFailedCount();

  @override
  Future<Duration?> remainingLockout() async {
    final until = await _store.readLockedUntilUtc();
    if (until == null) return null;
    final remaining = until.difference(_clock.now().toUtc());
    return remaining.isNegative || remaining == Duration.zero ? null : remaining;
  }

  /// Attempts to unlock with [pin].
  ///
  /// Checks the throttle **before** comparing, so a throttled attempt costs no PBKDF2 work and
  /// cannot be used to time the comparison.
  @override
  Future<UnlockOutcome> verifyPin(String pin) async {
    final hash = await _store.readPinHash();
    final salt = await _store.readSalt();
    if (hash == null || salt == null) {
      return const UnlockOutcome(unlocked: false, refusal: UnlockRefusal.notEnabled);
    }

    final waiting = await remainingLockout();
    if (waiting != null) {
      return UnlockOutcome(
        unlocked: false,
        refusal: UnlockRefusal.throttled,
        failedCount: await _store.readFailedCount(),
        retryAfter: waiting,
      );
    }

    final candidate = await _store.deriveHash(secret: pin, salt: salt);
    if (_constantTimeEquals(candidate, hash)) {
      await _store.resetFailures();
      return const UnlockOutcome.success();
    }
    return _recordFailure();
  }

  /// Resets the PIN using [code], for the forgotten-PIN path.
  ///
  /// Subject to the same throttle as a PIN attempt: without it the recovery code would be the weaker
  /// of the two secrets to attack, which would make the whole lock only as strong as the path nobody
  /// remembers exists.
  @override
  Future<Result<void, Failure>> resetWithRecoveryCode({
    required String code,
    required String newPin,
  }) async {
    final recoveryHash = await _store.readRecoveryHash();
    final salt = await _store.readSalt();
    if (recoveryHash == null || salt == null) {
      return const Result.failure(
        BusinessRuleFailure('No lock is configured.', rule: 'lockNotEnabled'),
      );
    }

    final waiting = await remainingLockout();
    if (waiting != null) {
      return Result.failure(
        BusinessRuleFailure(
          'Too many attempts. Try again in ${waiting.inSeconds} seconds.',
          rule: 'throttled',
        ),
      );
    }

    final normalized = _recoveryCode.normalize(code);
    if (!_recoveryCode.isWellFormed(normalized)) {
      await _recordFailure();
      return const Result.failure(
        ValidationFailure('A recovery code is 10 characters.', field: 'code'),
      );
    }

    final candidate = await _store.deriveHash(secret: normalized, salt: salt);
    if (!_constantTimeEquals(candidate, recoveryHash)) {
      await _recordFailure();
      return const Result.failure(
        BusinessRuleFailure('That recovery code is not correct.', rule: 'wrongRecoveryCode'),
      );
    }

    final pinCheck = _validatePinFormat(newPin);
    if (pinCheck != null) return Result.failure(pinCheck);

    // The recovery code itself is unchanged — the user has one code for the life of the install, and
    // silently rotating it here would invalidate the copy they wrote down.
    await _store.writeNewPin(pin: newPin, pinLength: newPin.length);
    return const Result.ok(null);
  }

  /// Enables the lock with [pin], returning the recovery code to show the user **once**.
  @override
  Future<Result<String, Failure>> enable({required String pin}) async {
    if (await _store.isEnabled) {
      return const Result.failure(
        BusinessRuleFailure('A lock is already set.', rule: 'lockAlreadyEnabled'),
      );
    }
    final pinCheck = _validatePinFormat(pin);
    if (pinCheck != null) return Result.failure(pinCheck);

    final code = _recoveryCode.generate();
    await _store.writeLock(pin: pin, recoveryCode: code, pinLength: pin.length);
    return Result.ok(_recoveryCode.format(code));
  }

  /// Changes the PIN, verifying [currentPin] first. The recovery code is unchanged.
  @override
  Future<Result<void, Failure>> changePin({
    required String currentPin,
    required String newPin,
  }) async {
    final outcome = await verifyPin(currentPin);
    if (!outcome.unlocked) {
      return Result.failure(
        BusinessRuleFailure(
          outcome.isThrottled
              ? 'Too many attempts. Try again shortly.'
              : 'That PIN is not correct.',
          rule: outcome.isThrottled ? 'throttled' : 'wrongPin',
        ),
      );
    }
    final pinCheck = _validatePinFormat(newPin);
    if (pinCheck != null) return Result.failure(pinCheck);

    await _store.writeNewPin(pin: newPin, pinLength: newPin.length);
    return const Result.ok(null);
  }

  /// Disables the lock, verifying [pin] first.
  @override
  Future<Result<void, Failure>> disable({required String pin}) async {
    final outcome = await verifyPin(pin);
    if (!outcome.unlocked) {
      return Result.failure(
        BusinessRuleFailure(
          outcome.isThrottled
              ? 'Too many attempts. Try again shortly.'
              : 'That PIN is not correct.',
          rule: outcome.isThrottled ? 'throttled' : 'wrongPin',
        ),
      );
    }
    await _store.clearLock();
    return const Result.ok(null);
  }

  Future<UnlockOutcome> _recordFailure() async {
    final count = await _store.incrementFailedCount();
    final delay = delayAfterFailures(count);
    if (delay > Duration.zero) {
      await _store.writeLockedUntilUtc(_clock.now().toUtc().add(delay));
    }
    return UnlockOutcome(
      unlocked: false,
      refusal: delay > Duration.zero ? UnlockRefusal.throttled : UnlockRefusal.wrongPin,
      failedCount: count,
      retryAfter: delay > Duration.zero ? delay : null,
    );
  }

  Failure? _validatePinFormat(String pin) {
    if (pin.length != 4 && pin.length != 6) {
      return const ValidationFailure('A PIN is 4 or 6 digits.', field: 'pin');
    }
    if (!RegExp(r'^\d+$').hasMatch(pin)) {
      return const ValidationFailure('A PIN is digits only.', field: 'pin');
    }
    return null;
  }

  /// Compares two base64 hashes without an early exit.
  ///
  /// The timing channel here is small — both strings are the same length and the comparison happens
  /// after 310,000 PBKDF2 iterations that dominate any measurement — but a length-independent compare
  /// costs nothing and removes the question entirely.
  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
```

### `lib/domain/repositories/settings_repository.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';

/// Reads and writes the app's key/value settings.
abstract interface class SettingsRepository {
  /// Emits the value for [key], or null when unset.
  Stream<String?> watchValue(String key);

  /// Reads the value for [key], or null when unset.
  Future<String?> readValue(String key);

  /// Emits every setting as a key/value map.
  Stream<Map<String, String>> watchAll();

  /// Writes [value] against [key].
  Future<Result<void, Failure>> writeValue({
    required String key,
    required String value,
    required String valueType,
  });

  /// Removes [key].
  Future<Result<void, Failure>> remove(String key);

  /// Records the user's chosen home currency code.
  ///
  /// **Added in 8A, as the counterpart to [readHomeCurrencyCode].** Onboarding has to write this key,
  /// and the key itself lives in `data/repositories/settings_keys.dart` — which a feature may not import
  /// (Law L12, and no delivered feature does). The alternative was a duplicated literal in the
  /// onboarding feature that would silently write to a dead key if `data/` ever renamed it. A named
  /// method keeps one definition on the side that owns it.
  Future<Result<void, Failure>> writeHomeCurrencyCode(String code);

  /// The user's chosen home currency code, used for display aggregation only (Law L9).
  Future<String?> readHomeCurrencyCode();

  /// The account quick-add falls back to when no last-used account is known.
  ///
  /// Lives in settings rather than as a column on `Account`, because the schema has no
  /// `isDefault` there — quick-add resolves last-used first, then this (ARCH_2 §4.1).
  Future<String?> readDefaultAccountId();
}
```

### `lib/data/repositories/settings_repository_impl.dart`

```dart
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/settings_dao.dart';
import 'package:alaya/data/repositories/settings_keys.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';

/// `SettingsRepository` backed by `SettingsDao`.
///
/// The two named lookups — [readHomeCurrencyCode], [readDefaultAccountId] — read the fixed keys
/// in [SettingsKeys] that Phase 1C's seed data writes on first launch, so both are populated from
/// the very first run rather than needing an explicit "unset" path.
final class SettingsRepositoryImpl implements SettingsRepository {
  /// Creates the repository over [dao], using [clock] for write timestamps.
  const SettingsRepositoryImpl(this._dao, this._clock);

  final SettingsDao _dao;
  final Clock _clock;

  @override
  Stream<String?> watchValue(String key) => _dao.watchValue(key);

  @override
  Future<String?> readValue(String key) => _dao.readValue(key);

  @override
  Stream<Map<String, String>> watchAll() => _dao.watchAll();

  @override
  Future<Result<void, Failure>> writeValue({
    required String key,
    required String value,
    required String valueType,
  }) async {
    await _dao.writeValue(
      key: key,
      value: value,
      valueType: valueType,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> remove(String key) async {
    await _dao.softDelete(key: key, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  @override
  Future<String?> readHomeCurrencyCode() => _dao.readValue(SettingsKeys.homeCurrencyCode);

  @override
  Future<Result<void, Failure>> writeHomeCurrencyCode(String code) => writeValue(
        key: SettingsKeys.homeCurrencyCode,
        value: code,
        valueType: 'string',
      );

  @override
  Future<String?> readDefaultAccountId() => _dao.readValue(SettingsKeys.defaultAccountId);
}
```

### `lib/app/providers/service_providers.dart`

```dart
/// One provider per engine.
///
/// The stateless engines are `const` and could in principle be constructed at each use site. They get
/// providers anyway so that every dependency in the app arrives the same way — a codebase where some
/// collaborators are injected and others are constructed inline is one where you cannot tell, from a
/// widget, what it actually depends on.
///
/// ## Every engine now has a provider
///
/// Three did not, for five phases. `CalendarAggregator` was blocked on `CalendarRepository` and was
/// wired in 7A; `AnalyticsService` was blocked on an `AnalyticsPort` adapter and `AnalyticsCacheService`
/// on `AnalyticsCacheRepository`, and both are wired here (ARCH_4 §5.1 item 15).
///
/// **The decision to omit them rather than stub them was the right one, and it is worth keeping the
/// reasoning after the fact.** A port returning empty rows makes an unfinished analytics screen
/// indistinguishable from a working one that found no data — there is no way to tell those apart from
/// the UI, and no test that would have failed. An absent provider is a compile error at the first use
/// site, which names the problem where someone can act on it. Phase 6F's insight card is the proof:
/// its spending side shipped as an honest inline empty state naming what it waited for, rather than
/// as a chart of zeroes.
///
/// `analyticsServiceProvider` is the one `FutureProvider` among the engines, because `AnalyticsService`
/// takes a **loaded** `RateTable` rather than the service that loads it. That is ARCH_3 §1.5's design
/// working as intended: conversion is synchronous so a month of data costs one table load instead of
/// two cache round trips per amount, and somebody has to await the load. Here it is a provider.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/data/backup/backup_service.dart';
import 'package:alaya/data/backup/restore_service.dart';
import 'package:alaya/data/remote/currency_api_client.dart';
import 'package:alaya/data/repositories/mappers/rate_mappers.dart';
import 'package:alaya/data/security/app_lock_store.dart';
import 'package:alaya/data/backup/erase_service.dart';
import 'package:alaya/data/backup/share_backup_transfer.dart';
import 'package:alaya/data/security/local_auth_biometric_gate.dart';
import 'package:alaya/data/security/pin_service.dart';
import 'package:alaya/data/security/recovery_code.dart';
import 'package:alaya/domain/services/analytics/analytics_cache_service.dart';
import 'package:alaya/domain/services/analytics/analytics_service.dart';
import 'package:alaya/domain/services/backup/data_transfer_port.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';
import 'package:alaya/domain/services/lock/app_lock.dart';
import 'package:alaya/domain/services/lock/biometric_gate.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';
import 'package:alaya/domain/services/date_range_service.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';
import 'package:alaya/domain/services/low_stock_suggestion_engine.dart';
import 'package:alaya/domain/services/purchase_fan_out_service.dart';
import 'package:alaya/domain/services/recurring_engine.dart';
import 'package:alaya/domain/services/stock_reconciler.dart';
import 'package:alaya/domain/services/unit_engine.dart';


// ── stateless engines ───────────────────────────────────────────────────────────────────

/// Unit conversion within a category.
final unitEngineProvider = Provider<UnitEngine>((ref) => const UnitEngine());

/// Date-range presets for filters and analytics.
final dateRangeServiceProvider = Provider<DateRangeService>((ref) => const DateRangeService());

/// Net worth and per-account balances.
final balanceServiceProvider = Provider<BalanceService>((ref) => const BalanceService());

/// FEFO consumption planning.
final inventoryConsumptionServiceProvider =
    Provider<InventoryConsumptionService>((ref) => const InventoryConsumptionService());

/// Cache-versus-ledger reconciliation and repair.
final stockReconcilerProvider = Provider<StockReconciler>((ref) => const StockReconciler());

/// Idempotent low-stock suggestion decisions.
final lowStockSuggestionEngineProvider =
    Provider<LowStockSuggestionEngine>((ref) => const LowStockSuggestionEngine());

/// Recurring schedule arithmetic — next due, materialisation, settlement.
final recurringEngineProvider = Provider<RecurringEngine>((ref) => const RecurringEngine());

// ── engines with dependencies ───────────────────────────────────────────────────────────

/// Turns a purchase line into a batch, an asset or a template.
final purchaseFanOutServiceProvider = Provider<PurchaseFanOutService>(
  (ref) => PurchaseFanOutService(normalizer: ref.watch(normalizerProvider)),
);

/// The exchange-rate HTTP client.
final currencyApiClientProvider = Provider<CurrencyApiClient>(
  (ref) => CurrencyApiClient(
    dio: ref.watch(dioProvider),
    logger: ref.watch(loggerProvider),
  ),
);

/// Rate lookup, cross-rate pivoting and the once-daily fetch.
///
/// Its four collaborators are closures over the DAO rather than the repository, which is what keeps
/// this out of a cycle: `CurrencyRepository` depends on this service, so a service depending on the
/// repository would not resolve.
final currencyRateServiceProvider = Provider<CurrencyRateService>((ref) {
  final dao = ref.watch(currencyDaoProvider);
  final client = ref.watch(currencyApiClientProvider);
  final clock = ref.watch(clockProvider);
  final uids = ref.watch(uidGeneratorProvider);
  return CurrencyRateService(
    loadTable: () async => RateMappers.tableFrom(
      rows: await dao.allRates(),
      decimalDigitsByCode: await dao.decimalDigitsByCode(),
    ),
    saveSnapshot: (snapshot) => dao.upsertRates(
      RateMappers.companionsFrom(snapshot: snapshot, uids: uids, clock: clock),
    ),
    fetchSnapshot: client.fetchLatest,
    // `newestRateDate` takes the base code; a snapshot is always USD-pivoted (ARCH_3 §1.2).
    newestCachedDate: () => dao.newestRateDate(RateTable.pivotCode),
    clock: clock,
  );
});

// ── security ────────────────────────────────────────────────────────────────────────────

/// Recovery-code generation and normalisation.
final recoveryCodeProvider = Provider<RecoveryCode>((ref) => RecoveryCode());

/// The app-lock secret store.
///
/// Reads and writes secure storage only, never the database — which is what makes a restore unable
/// to change the lock (ARCH_3 §2.1).
final appLockStoreProvider = Provider<AppLockStore>(
  (ref) => AppLockStore(storage: ref.watch(secureKeyValueStoreProvider)),
);

/// PIN verification, change, enable, disable and the failure throttle.
final pinServiceProvider = Provider<AppLock>(
  (ref) => PinService(
    store: ref.watch(appLockStoreProvider),
    clock: ref.watch(clockProvider),
    recoveryCode: ref.watch(recoveryCodeProvider),
  ),
);

/// The biometric shortcut on the lock screen (ARCH_3 §2.2).
///
/// Typed as the **contract**, so no feature can reach `local_auth` — and so a widget test substitutes a
/// fake instead of needing a platform channel, which is the reason the contract exists.
final biometricGateProvider = Provider<BiometricGate>(
  (ref) => LocalAuthBiometricGate(LocalAuthentication()),
);

/// Erasing everything — the last resort behind "I have forgotten both" (ARCH_3 §2.2).
///
/// Takes its seeder from the database rather than as an argument, so a re-seed after an erase cannot
/// differ from the install it is restoring.
final eraseServiceProvider = Provider<EraseService>(
  (ref) => EraseService(
    database: ref.watch(databaseProvider),
    lockStore: ref.watch(appLockStoreProvider),
  ),
);

/// Exporting a backup and erasing everything, behind one contract.
///
/// One port for both because ARCH_3 §2.2's forgot-both path offers the export *and then* erases, and the
/// two halves of that conversation should not come from different subsystems.
final dataTransferPortProvider = Provider<DataTransferPort>(
  (ref) => ShareBackupTransfer(
    backup: ref.watch(backupServiceProvider),
    erase: ref.watch(eraseServiceProvider),
  ),
);

// ── backup ──────────────────────────────────────────────────────────────────────────────

/// Database export via `VACUUM INTO`.
final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    database: ref.watch(databaseProvider),
    historyDao: ref.watch(backupHistoryDaoProvider),
    clock: ref.watch(clockProvider),
    uids: ref.watch(uidGeneratorProvider),
  ),
);

/// Merge and Replace restore.
final restoreServiceProvider = Provider<RestoreService>(
  (ref) => RestoreService(database: ref.watch(databaseProvider)),
);

/// The calendar aggregator, which applies ARCH_3 §6's per-type severity thresholds.
///
/// Stateless and `const`-constructible, but it takes a repository, so it gets a provider like every
/// other engine — no widget constructs it.
final calendarAggregatorProvider = Provider<CalendarAggregator>(
  (ref) => CalendarAggregator(ref.watch(calendarRepositoryProvider)),
);

// ── analytics ───────────────────────────────────────────────────────────────────────────

/// The home currency every converted analytics figure is expressed in.
///
/// `'INR'` is a data fallback for a setting Phase 1C's seed always writes, not a user-visible string,
/// so Law U5 does not reach it. It is named rather than inlined because three files now need the same
/// answer and three literals is how they start disagreeing.
const String analyticsFallbackHomeCurrencyCode = 'INR';

/// Memoisation for analytics results slower than roughly 200 ms (ARCH_3 §5.2).
final analyticsCacheServiceProvider = Provider<AnalyticsCacheService>(
  (ref) => AnalyticsCacheService(ref.watch(analyticsCacheRepositoryProvider)),
);

/// ARCH_3 §5.1's twenty-four queries, over the SQL adapter and a loaded rate table.
///
/// **A `FutureProvider`, because the `RateTable` has to be in hand before the service is built.**
/// Every conversion in `AnalyticsService` is synchronous by design (ARCH_3 §1.5) — that is what makes
/// converting a month of transactions one table load rather than a thousand — so the awaiting happens
/// once, here, instead of per amount.
///
/// Re-created when the rate cache is written, because `CurrencyRateService.table()` is watched rather
/// than read: a rate arriving must change the figures it feeds, not just the unconverted count beside
/// them.
final analyticsServiceProvider = FutureProvider<AnalyticsService>((ref) async {
  final rates = await ref.watch(currencyRateServiceProvider).table();
  final home = await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ??
      analyticsFallbackHomeCurrencyCode;
  return AnalyticsService(
    port: ref.watch(analyticsPortProvider),
    rates: rates,
    homeCurrencyCode: home,
  );
});
```

## Onboarding

**Archetype B with one deviation, recorded: no `CloseButton`.** §3's editor opens with ✕ because an editor
is a task you abandon *back to* something. Onboarding has nothing behind it — the router redirects here
until it is finished or skipped — so the escape is a named **Skip** action that says where it leads. Both
routes through the same `finish()`, so a skip is recorded as deliberately as a completion, and neither
leaves the flag unset for the next launch to re-ask.

Three defects of mine were fixed before this landed. `commitCurrency` used `Result.fold` with an `async`
success branch and a sync failure branch — two different return types for one type parameter, which does
not compile. It also wrote through a settings key I had invented, when `SettingsKeys.homeCurrencyCode`
already existed in `data/`; that is what `writeHomeCurrencyCode` is for. And I had called
`DateText.format` — `DateText` has no public formatter, its `_format` being private precisely because
every other date in the app goes through the widget. A `DatePickerField` wants a `String`, so this is the
one place in the phase a date is formatted by hand, with the same `intl` call 6A's forms make.

`onboardingCurrenciesProvider` is declared here rather than reusing 6A's `enabledCurrenciesProvider`,
because that one lives inside `quick_add_sheet.dart` — importing a sheet to obtain a provider is worse
coupling than a second stream over a five-row seeded table. Filed for Phase 9 along with moving it out of
a screen file.

### `lib/features/onboarding/providers/onboarding_providers.dart`

```dart
/// View-model state for the first-run flow (ARCH_5 U19).
///
/// **Nothing here declares a repository or an engine.** `accountRepositoryProvider`,
/// `settingsRepositoryProvider` and the rest live in `lib/app/providers/` and are watched from here
/// (Law U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/features/lock/providers/lock_providers.dart';
import 'package:alaya/features/onboarding/state/onboarding_state.dart';

/// Whether the first-run flow still has to happen.
enum OnboardingPhase {
  /// Still asking `app_settings`.
  ///
  /// Distinct from `needed`, so the router does not push a brand-new user into onboarding and then pull
  /// them out again a frame later when the answer arrives.
  unknown,

  /// Not finished and not skipped.
  needed,

  /// Finished, or skipped deliberately.
  done,
}

/// Whether onboarding is still owed, and the one place that changes.
final onboardingPhaseProvider =
    NotifierProvider<OnboardingPhaseNotifier, OnboardingPhase>(OnboardingPhaseNotifier.new);

/// Reads and records whether onboarding is finished.
class OnboardingPhaseNotifier extends Notifier<OnboardingPhase> {
  @override
  OnboardingPhase build() {
    unawaited(_restore());
    return OnboardingPhase.unknown;
  }

  Future<void> _restore() async {
    final stored =
        await ref.read(settingsRepositoryProvider).readValue(OnboardingKeys.done);
    state = stored == 'true' ? OnboardingPhase.done : OnboardingPhase.needed;
  }

  /// Records that onboarding is over, whether finished or skipped.
  ///
  /// The write is awaited, unlike the theme and range preferences: this is the flag that stops the
  /// router sending the user back, and losing it would restart the flow on the next launch.
  Future<void> complete() async {
    await ref.read(settingsRepositoryProvider).writeValue(
          key: OnboardingKeys.done,
          value: 'true',
          valueType: 'string',
        );
    state = OnboardingPhase.done;
  }
}

/// Whether the router should redirect to the first-run flow.
///
/// `unknown` counts as **not** needing onboarding, the opposite of how the lock treats it. Guessing
/// wrong here shows the dashboard for one frame; guessing wrong on the lock shows somebody's balance.
/// The costs are not symmetric, so the defaults are not either.
final needsOnboardingProvider = Provider<bool>(
  (ref) => ref.watch(onboardingPhaseProvider) == OnboardingPhase.needed,
);

/// The currencies the picker offers.
///
/// **Declared here rather than reusing 6A's `enabledCurrenciesProvider`, which lives inside
/// `quick_add_sheet.dart`.** Importing a sheet to obtain a provider is worse coupling than a second
/// stream over `currencies` — a five-row seeded table — and 7B's rule about not duplicating a stream was
/// about `accounts`, which grows. Consolidating the two belongs in Phase 9's sweep, along with moving
/// that provider out of a screen file.
final onboardingCurrenciesProvider = StreamProvider<List<Currency>>(
  (ref) => ref.watch(currencyRepositoryProvider).watchEnabled(),
);

/// One currency's minor-unit precision, so an amount field shows the right number of decimals.
///
/// JPY has none, and an opening balance typed as `1200` becoming `¥1,200.00` is the bug this prevents.
final onboardingCurrencyDigitsProvider =
    FutureProvider.family<int, String>((ref, code) async {
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});

/// The first-run flow's draft and every transition it has.
final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingDraft>(OnboardingController.new);

/// Holds the draft, loads what the seeder already created, and commits.
class OnboardingController extends Notifier<OnboardingDraft> {
  @override
  OnboardingDraft build() {
    unawaited(_load());
    return const OnboardingDraft(
      step: OnboardingStep.currency,
      homeCurrencyCode: fallbackHomeCurrencyCode,
      accounts: <DraftAccount>[],
    );
  }

  /// The currency assumed until `app_settings` answers.
  ///
  /// Matches Phase 1C's seeder default so the first frame agrees with the database rather than flicking
  /// from one code to another.
  static const String fallbackHomeCurrencyCode = 'INR';

  /// Loads the seeded accounts and the stored step.
  ///
  /// **The flow edits as much as it creates.** Phase 1C's seeder already inserts two accounts and a
  /// `homeCurrencyCode`, so starting from an empty list would either duplicate them or quietly ignore
  /// them — and a first-run screen that shows none of the accounts the app already has reads as broken.
  Future<void> _load() async {
    final settings = ref.read(settingsRepositoryProvider);
    final home = await settings.readHomeCurrencyCode() ?? fallbackHomeCurrencyCode;
    final storedStep = await settings.readValue(OnboardingKeys.step);
    final existing = await ref.read(accountRepositoryProvider).watchSelectable().first;

    state = state.copyWith(
      step: OnboardingKeys.parseStep(storedStep),
      homeCurrencyCode: home,
      accounts: [for (final account in existing) DraftAccount.from(account)],
      isLoaded: true,
    );
  }

  /// Sets the currency totals are shown in, carrying untouched accounts with it.
  ///
  /// **Untouched accounts follow; chosen ones do not.** Somebody selecting yen on step one does not want
  /// two rupee accounts they never asked for, and equally does not want an account they deliberately set
  /// to rupees rewritten behind them. `DraftAccount.currencyTouched` is what separates the two.
  void setHomeCurrency(String code) {
    state = state.copyWith(
      homeCurrencyCode: code,
      accounts: [
        for (final account in state.accounts)
          account.currencyTouched ? account : account.copyWith(currencyCode: code),
      ],
      clearFailure: true,
    );
  }

  /// Adds an empty account row, in the home currency and dated today.
  void addAccount() {
    state = state.copyWith(
      accounts: [
        ...state.accounts,
        DraftAccount(
          name: '',
          kind: AccountKind.cash,
          currencyCode: state.homeCurrencyCode,
          openingMinor: 0,
          openingDate: ref.read(clockProvider).today(),
        ),
      ],
      clearFailure: true,
    );
  }

  /// Replaces the row at [index].
  void updateAccount(int index, DraftAccount account) {
    if (index < 0 || index >= state.accounts.length) return;
    final next = [...state.accounts]..[index] = account;
    state = state.copyWith(accounts: next, clearFailure: true);
  }

  /// Marks the row at [index] as having a currency the user chose.
  void setAccountCurrency(int index, String code) {
    if (index < 0 || index >= state.accounts.length) return;
    final next = [...state.accounts]
      ..[index] = state.accounts[index].copyWith(currencyCode: code, currencyTouched: true);
    state = state.copyWith(accounts: next, clearFailure: true);
  }

  /// Removes the row at [index].
  ///
  /// A row that already exists in the database is **not** deleted here — removing it from the draft
  /// only stops this flow writing to it. Deleting an account is a destructive action with its own tier
  /// in ARCH_5 §5.5, and burying it in a first-run screen would be the wrong place for it.
  void removeAccount(int index) {
    if (index < 0 || index >= state.accounts.length) return;
    final next = [...state.accounts]..removeAt(index);
    state = state.copyWith(accounts: next, clearFailure: true);
  }

  /// Records that a lock was set during this flow.
  void markLockEnabled() => state = state.copyWith(lockEnabled: true);

  /// Moves to [step] and remembers it, so a restart resumes here.
  Future<void> goTo(OnboardingStep step) async {
    state = state.copyWith(step: step, clearFailure: true);
    await ref.read(settingsRepositoryProvider).writeValue(
          key: OnboardingKeys.step,
          value: step.name,
          valueType: 'string',
        );
  }

  /// Writes the home currency, then moves to the accounts step.
  ///
  /// Through `writeHomeCurrencyCode` rather than `writeValue` with a key: the key lives in `data/`, which
  /// a feature may not import, and a literal here would write to a dead key the moment `data/` renamed it.
  Future<bool> commitCurrency() async {
    state = state.copyWith(isSaving: true, clearFailure: true);
    final result = await ref
        .read(settingsRepositoryProvider)
        .writeHomeCurrencyCode(state.homeCurrencyCode);
    if (result.isFailure) {
      state = state.copyWith(isSaving: false, failureMessage: result.failureOrNull?.message);
      return false;
    }
    state = state.copyWith(isSaving: false);
    await goTo(OnboardingStep.accounts);
    return true;
  }

  /// Saves every account, then moves to the security step.
  ///
  /// **Stops at the first failure rather than continuing.** Half-written accounts with the other half
  /// reported as an error is a worse state to leave someone in than nothing written, and Law L14's
  /// all-or-nothing reasoning applies to a loop of writes as much as to a transaction.
  Future<bool> commitAccounts() async {
    state = state.copyWith(isSaving: true, clearFailure: true);
    final repository = ref.read(accountRepositoryProvider);
    final normalizer = ref.read(normalizerProvider);
    final uids = ref.read(uidGeneratorProvider);

    for (var i = 0; i < state.accounts.length; i++) {
      final draft = state.accounts[i];
      final account = Account(
        id: draft.id ?? uids.generate(),
        name: draft.name.trim(),
        normalizedName: normalizer.normalize(draft.name),
        kind: draft.kind,
        currencyCode: draft.currencyCode,
        openingBalance: Money(draft.openingMinor, draft.currencyCode),
        openingBalanceDateKey: draft.openingDate,
        isArchived: false,
        includeInNetWorth: draft.includeInNetWorth,
        sortOrder: i,
      );
      final result = await repository.save(account);
      if (result.isFailure) {
        state = state.copyWith(
          isSaving: false,
          failureMessage: result.failureOrNull?.message,
        );
        return false;
      }
    }

    state = state.copyWith(isSaving: false);
    await goTo(OnboardingStep.security);
    return true;
  }

  /// Ends the flow, whether the user finished it or skipped.
  ///
  /// **Clears the lock gate as well as the onboarding one.** Enabling a lock on the security step sets
  /// `isLocked`, and the router would eject the user from the flow they are still in — so the session is
  /// marked satisfied here. Somebody who has just chosen a PIN, twice, has demonstrated they know it.
  Future<void> finish() async {
    await goTo(OnboardingStep.done);
    if (state.lockEnabled) {
      ref.read(lockPhaseProvider.notifier).markUnlocked();
    }
    await ref.read(onboardingPhaseProvider.notifier).complete();
  }
}
```

### `lib/features/onboarding/presentation/screens/onboarding_flow.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/features/lock/presentation/screens/pin_setup_flow.dart';
import 'package:alaya/features/onboarding/providers/onboarding_providers.dart';
import 'package:alaya/features/onboarding/state/onboarding_state.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// The first-run flow (ARCH_5 §3 archetype B).
///
/// **Skippable from every step and resumable into any of them.** `OnboardingController.goTo` writes the
/// step to `app_settings` on each transition, so a phone call at step two does not cost the opening
/// balances already typed — and re-asking for those is the fastest way to have somebody skip the flow
/// entirely.
///
/// **Archetype B, with one deviation: no `CloseButton`.** §3's editor opens with ✕ because an editor is a
/// task you can abandon back to something. Onboarding has nothing behind it — the router redirects here
/// until it is finished or skipped — so the escape is a named **Skip** action instead, which says where it
/// leads. Both routes through the same `finish()`, so a skip is recorded as deliberately as a completion.
///
/// **It edits as much as it creates.** Phase 1C's seeder already inserts two accounts and a home
/// currency, so a flow that started from an empty list would either duplicate them or ignore them, and a
/// first-run screen showing none of the accounts the app already has reads as broken.
class OnboardingFlow extends ConsumerWidget {
  /// Creates the flow.
  const OnboardingFlow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final draft = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);

    // Loading: the seeded accounts and the stored step have not arrived. Not an empty list — showing
    // "no accounts yet" to somebody who has two would be a lie for one frame (Law U4).
    if (!draft.isLoaded) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.onboardingTitle)),
        body: Center(
          child: Text(
            strings.onboardingLoading,
            style: AlayaTypography.body.copyWith(color: context.semantic.muted),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_stepTitle(strings, draft.step)),
        actions: [
          TextButton(
            onPressed: draft.isSaving ? null : () => controller.finish(),
            child: Text(strings.onboardingSkip, style: AlayaTypography.button),
          ),
        ],
      ),
      body: AlayaFormScaffold(
        primaryLabel: _primaryLabel(strings, draft.step),
        onPrimary: draft.isSaving ? null : () => _commit(context, ref, draft),
        secondaryLabel: draft.step == OnboardingStep.currency ? null : strings.actionBack,
        onSecondary: draft.step == OnboardingStep.currency
            ? null
            : () => controller.goTo(_previous(draft.step)),
        isSubmitting: draft.isSaving,
        // Nothing to guard: there is no way out of this screen except Skip, which commits the decision to
        // skip. A discard prompt over a flow the user cannot accidentally leave would be noise.
        discardTitle: strings.onboardingSkipTitle,
        discardBody: strings.onboardingSkipBody,
        discardConfirmLabel: strings.onboardingSkip,
        discardCancelLabel: strings.actionKeepEditing,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StepProgress(step: draft.step),
            const SizedBox(height: AlayaSpacing.lg),
            if (draft.failureMessage != null) ...[
              // The repository's own message, inline under the step it belongs to (Law U9).
              ErrorState(
                title: strings.errorTitleGeneric,
                body: draft.failureMessage!,
                retryLabel: strings.actionRetry,
                onRetry: () => _commit(context, ref, draft),
              ),
              const SizedBox(height: AlayaSpacing.lg),
            ],
            switch (draft.step) {
              OnboardingStep.currency => const _CurrencyStep(),
              OnboardingStep.accounts => const _AccountsStep(),
              OnboardingStep.security || OnboardingStep.done => const _SecurityStep(),
            },
          ],
        ),
      ),
    );
  }

  Future<void> _commit(BuildContext context, WidgetRef ref, OnboardingDraft draft) async {
    final controller = ref.read(onboardingControllerProvider.notifier);
    switch (draft.step) {
      case OnboardingStep.currency:
        await controller.commitCurrency();
      case OnboardingStep.accounts:
        await controller.commitAccounts();
      case OnboardingStep.security:
      case OnboardingStep.done:
        await controller.finish();
    }
  }

  OnboardingStep _previous(OnboardingStep step) => switch (step) {
        OnboardingStep.currency => OnboardingStep.currency,
        OnboardingStep.accounts => OnboardingStep.currency,
        OnboardingStep.security => OnboardingStep.accounts,
        OnboardingStep.done => OnboardingStep.security,
      };

  String _stepTitle(AlayaStrings strings, OnboardingStep step) => switch (step) {
        OnboardingStep.currency => strings.onboardingCurrencyTitle,
        OnboardingStep.accounts => strings.onboardingAccountsTitle,
        OnboardingStep.security || OnboardingStep.done => strings.onboardingSecurityTitle,
      };

  String _primaryLabel(AlayaStrings strings, OnboardingStep step) => switch (step) {
        OnboardingStep.currency => strings.onboardingNext,
        OnboardingStep.accounts => strings.onboardingSaveAccounts,
        OnboardingStep.security || OnboardingStep.done => strings.onboardingFinish,
      };
}

/// Which of the three steps is showing.
///
/// Words and a count, not three dots. A dot row says "there are more" without saying how many more or
/// what they are, and the one question somebody abandons a setup flow over is how long it will take.
class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.step});

  final OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final index = switch (step) {
      OnboardingStep.currency => 1,
      OnboardingStep.accounts => 2,
      OnboardingStep.security || OnboardingStep.done => 3,
    };
    return Text(
      strings.onboardingStepOf(index, 3),
      style: AlayaTypography.overline.copyWith(color: context.semantic.muted),
    );
  }
}

/// Step one: the currency totals are shown in.
class _CurrencyStep extends ConsumerWidget {
  const _CurrencyStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final draft = ref.watch(onboardingControllerProvider);
    final currencies =
        ref.watch(onboardingCurrenciesProvider).valueOrNull ?? const <Currency>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings.onboardingCurrencyBody, style: AlayaTypography.body),
        const SizedBox(height: AlayaSpacing.xs),
        // **Says what it does and what it does not.** Law L9 makes this a display choice: it changes what
        // totals are added up in, and changes no amount that was ever recorded. Somebody who thinks they
        // are converting their history would be very surprised later.
        Text(
          strings.onboardingCurrencyNote,
          style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.lg),
        if (currencies.isEmpty)
          Text(
            strings.onboardingLoading,
            style: AlayaTypography.body.copyWith(color: context.semantic.muted),
          )
        else
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            children: [
              for (final currency in currencies)
                ChoiceChip(
                  label: Text(
                    strings.onboardingCurrencyChip(currency.code, currency.symbol),
                    style: AlayaTypography.button,
                  ),
                  selected: currency.code == draft.homeCurrencyCode,
                  onSelected: (_) => ref
                      .read(onboardingControllerProvider.notifier)
                      .setHomeCurrency(currency.code),
                ),
            ],
          ),
      ],
    );
  }
}

/// Step two: the accounts, and what was in them when the user started.
class _AccountsStep extends ConsumerWidget {
  const _AccountsStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final draft = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings.onboardingAccountsBody, style: AlayaTypography.body),
        const SizedBox(height: AlayaSpacing.xs),
        // **This is the paragraph anomaly A03 exists for.** An opening balance without a date cannot be
        // placed in a ledger, so every transaction before that date would be silently unaccounted for —
        // and the balance is the only reason a new user's real cash is visible at all.
        Text(
          strings.onboardingOpeningNote,
          style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.lg),
        // Empty is reachable: the user can remove every row. It names the next action rather than the
        // absence (ARCH_5 §2.8).
        if (draft.accounts.isEmpty)
          EmptyState(
            title: strings.onboardingNoAccountsTitle,
            body: strings.onboardingNoAccountsBody,
            icon: Icons.account_balance_wallet_outlined,
            actionLabel: strings.onboardingAddAccount,
            onAction: controller.addAccount,
          )
        else ...[
          for (var i = 0; i < draft.accounts.length; i++) ...[
            _AccountCard(index: i, draft: draft.accounts[i]),
            const SizedBox(height: AlayaSpacing.sm),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: controller.addAccount,
              icon: const Icon(Icons.add, size: AlayaIconSize.md),
              label: Text(strings.onboardingAddAccount, style: AlayaTypography.button),
            ),
          ),
        ],
      ],
    );
  }
}

/// One account being set up.
class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.index, required this.draft});

  final int index;
  final DraftAccount draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final controller = ref.read(onboardingControllerProvider.notifier);
    final digits = ref.watch(onboardingCurrencyDigitsProvider(draft.currencyCode)).valueOrNull ?? 2;

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: draft.name,
                  decoration: InputDecoration(labelText: strings.accountNameLabel),
                  onChanged: (value) =>
                      controller.updateAccount(index, draft.copyWith(name: value)),
                ),
              ),
              IconButton(
                onPressed: () => controller.removeAccount(index),
                tooltip: strings.onboardingRemoveAccount,
                icon: const Icon(Icons.close, size: AlayaIconSize.md),
              ),
            ],
          ),
          const SizedBox(height: AlayaSpacing.sm),
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            children: [
              for (final kind in AccountKind.values)
                ChoiceChip(
                  label: Text(_kindLabel(strings, kind), style: AlayaTypography.button),
                  selected: kind == draft.kind,
                  onSelected: (_) =>
                      controller.updateAccount(index, draft.copyWith(kind: kind)),
                ),
            ],
          ),
          const SizedBox(height: AlayaSpacing.sm),
          AmountField(
            currencyCode: draft.currencyCode,
            decimalDigits: digits,
            initialValue: draft.openingBalance,
            label: strings.accountOpeningBalanceLabel,
            // Negative allowed: a card account can legitimately open overdrawn, and refusing it would
            // force somebody to record a debt as an asset.
            allowNegative: true,
            onChanged: (money) => controller.updateAccount(
              index,
              draft.copyWith(openingMinor: money?.minor ?? 0),
            ),
          ),
          const SizedBox(height: AlayaSpacing.sm),
          DatePickerField(
            value: draft.openingDate,
            label: strings.accountOpeningDateLabel,
            // `DateText` has no public formatter — its `_format` is private, because every other date in
            // the app goes through the widget. A `DatePickerField` needs a `String`, so this is the same
            // `intl` call 6A's forms make, and the only place in this phase a date is formatted by hand.
            // A formatter, not a formatted string: `DatePickerField.formatted` is
            // `String Function(DateKey)`, so it formats whichever date the picker lands on rather than
            // the one that was there when this built.
            formatted: (date) => DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag())
                .format(date.toUtcMidnight()),
            onChanged: (date) =>
                controller.updateAccount(index, draft.copyWith(openingDate: date)),
          ),
          const SizedBox(height: AlayaSpacing.sm),
          SwitchListTile(
            value: draft.includeInNetWorth,
            title: Text(strings.accountIncludeInNetWorth, style: AlayaTypography.body),
            // **The toggle is explained, which is the whole of ARCH_5 §7.2's row for it.** A switch called
            // "include in net worth" with no subtitle leaves the user guessing whether turning it off
            // hides the account or merely stops it being counted.
            subtitle: Text(
              strings.accountIncludeInNetWorthHelp,
              style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
            ),
            contentPadding: EdgeInsets.zero,
            onChanged: (value) => controller.updateAccount(
              index,
              draft.copyWith(includeInNetWorth: value),
            ),
          ),
        ],
      ),
    );
  }

  String _kindLabel(AlayaStrings strings, AccountKind kind) => switch (kind) {
        AccountKind.cash => strings.accountKindCash,
        AccountKind.bank => strings.accountKindBank,
        AccountKind.wallet => strings.accountKindWallet,
        AccountKind.card => strings.accountKindCard,
        AccountKind.other => strings.accountKindOther,
      };
}

/// Step three: the optional lock.
class _SecurityStep extends ConsumerWidget {
  const _SecurityStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final draft = ref.watch(onboardingControllerProvider);

    if (draft.lockEnabled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(label: strings.onboardingLockOnHeader),
          const SizedBox(height: AlayaSpacing.xs),
          Text(strings.onboardingLockOnBody, style: AlayaTypography.body),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings.onboardingSecurityBody, style: AlayaTypography.body),
        const SizedBox(height: AlayaSpacing.xs),
        // **ARCH_3 §2.5, in the place somebody decides.** This PIN stops a person holding the unlocked
        // phone. It does not encrypt anything. No "bank-grade", no padlock implying otherwise — and the
        // sentence about the phone's own lock screen is there because that is what actually protects the
        // file when the device is off.
        Text(
          strings.lockHonestBody,
          style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.lg),
        // Embedded, not pushed. A route would fight the onboarding gate, which sends everything outside
        // `/onboarding` back to it — and it keeps the flow one continuous thing.
        const PinSetupFlow(
          embedded: true,
        ),
      ],
    );
  }
}
```

## The lock screen's view-model

**`final class` is what settled the port question, and it is worth recording where it will be read.**
`PinService` and `BackupService` are both declared `final`, so in Dart 3 neither can be extended *or
implemented* outside its own library — a test fake is impossible, not merely inconvenient. Add a platform
channel to that and the lock screen's four required states had no way to be tested at all. That is a
sharper argument than the layering diagram I opened with, and it is now in `app_lock.dart` where an
implementer meets it.

Two things this view-model does that the service deliberately does not:

**The throttle ticks.** `PinService.remainingLockout()` answers once; a countdown that does not move reads
as the app having frozen, and the difference between "wait 30 seconds" and "this is broken" is a visible
second hand. The ticker re-reads the store each second rather than counting down in memory, because the
stored value is an absolute instant — killing the app cannot shorten the wait.

**The auto-erase decision lives here, not in the service.** `PinService` enforces ARCH_3 §2.3's throttle
for everybody; the ten-failure erase is an opt-in, default off, so it belongs where the setting is
readable. An unset key reads as false, which is what "default off" has to mean for a feature that destroys
data.

A dismissed fingerprint prompt increments **neither** the shake trigger nor the failure count — it is not a
wrong PIN, and counting it toward the throttle would let a pocket-tap lock somebody out of their own app.

### `lib/features/lock/providers/lock_entry_providers.dart`

```dart
/// View-model state for the lock screen (ARCH_5 U19).
///
/// **Neither `AppLock` nor `UnlockOutcome` is named here, and that is deliberate.** Dart needs an import
/// only to *write* a type, not to call a member on an inferred one — so this file drives the lock through
/// `pinServiceProvider` and translates the outcome into [LockEntryError] before the screen sees anything.
/// The screen therefore owns every string (Law U5) while this owns every decision about which applies.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/features/lock/providers/lock_providers.dart';

/// What the lock screen is showing.
class LockEntryState {
  /// Creates a state.
  const LockEntryState({
    required this.pinLength,
    this.entered = '',
    this.shakeTrigger = 0,
    this.failedCount = 0,
    this.remaining,
    this.isChecking = false,
    this.biometricAvailable = false,
    this.isErasing = false,
    this.message,
  });

  /// How many digits the configured PIN has, so the field knows when it is full.
  final int pinLength;

  /// What has been typed.
  final String entered;

  /// Incremented on every rejection, so two failures shake twice (ARCH_5 §2.6).
  final int shakeTrigger;

  /// Consecutive wrong attempts recorded so far.
  final int failedCount;

  /// How long until the next attempt will even be checked, or null when none is owed.
  ///
  /// **Ticks down while the screen is open**, because a throttle the user cannot see reads as the app
  /// having frozen — and the countdown is the difference between "wait 30 seconds" and "this is broken".
  final Duration? remaining;

  /// Whether a check is in flight.
  final bool isChecking;

  /// Whether this device can offer the biometric shortcut.
  final bool biometricAvailable;

  /// Whether the ten-failure auto-erase is running.
  final bool isErasing;

  /// The reason the last attempt was refused, already localised by the screen.
  final String? message;

  /// Whether a delay is in force.
  bool get isThrottled => remaining != null;

  /// Whether the entered PIN is long enough to submit.
  bool get isComplete => entered.length >= pinLength;

  /// A copy with the given fields replaced.
  LockEntryState copyWith({
    int? pinLength,
    String? entered,
    int? shakeTrigger,
    int? failedCount,
    Duration? remaining,
    bool clearRemaining = false,
    bool? isChecking,
    bool? biometricAvailable,
    bool? isErasing,
    String? message,
    bool clearMessage = false,
  }) =>
      LockEntryState(
        pinLength: pinLength ?? this.pinLength,
        entered: entered ?? this.entered,
        shakeTrigger: shakeTrigger ?? this.shakeTrigger,
        failedCount: failedCount ?? this.failedCount,
        remaining: clearRemaining ? null : (remaining ?? this.remaining),
        isChecking: isChecking ?? this.isChecking,
        biometricAvailable: biometricAvailable ?? this.biometricAvailable,
        isErasing: isErasing ?? this.isErasing,
        message: clearMessage ? null : (message ?? this.message),
      );
}

/// Why the last attempt failed, in terms the screen can localise.
///
/// A separate signal from [LockEntryState.message] so the screen owns every string (Law U5) while the
/// view-model owns the decision about which one applies.
enum LockEntryError {
  /// The PIN was wrong and no delay is owed yet.
  wrongPin,

  /// A delay is in force.
  throttled,

  /// The biometric prompt did not succeed.
  biometricFailed,

  /// The erase failed.
  eraseFailed,
}

/// The lock screen's entry state.
final lockEntryProvider =
    NotifierProvider<LockEntryNotifier, LockEntryState>(LockEntryNotifier.new);

/// Drives PIN entry, the throttle countdown, the biometric shortcut and the auto-erase.
class LockEntryNotifier extends Notifier<LockEntryState> {
  Timer? _ticker;

  @override
  LockEntryState build() {
    ref.onDispose(() => _ticker?.cancel());
    unawaited(_prime());
    return const LockEntryState(pinLength: 4);
  }

  /// The last error, for the screen to turn into a sentence.
  LockEntryError? get lastError => _lastError;
  LockEntryError? _lastError;

  Future<void> _prime() async {
    final lock = ref.read(pinServiceProvider);
    final length = await lock.readPinLength();
    final failed = await lock.readFailedCount();
    final remaining = await lock.remainingLockout();
    final biometric = await ref.read(biometricGateProvider).isAvailable;
    state = state.copyWith(
      pinLength: length,
      failedCount: failed,
      remaining: remaining,
      biometricAvailable: biometric,
    );
    if (remaining != null) _startTicker();
  }

  /// Appends a digit, submitting automatically once the PIN is long enough.
  ///
  /// **Auto-submits rather than waiting for a button.** A four-digit PIN with a separate Enter is five
  /// taps for a screen the user passes through several times a day, and there is nothing to review — the
  /// field is either right or it is not.
  Future<void> append(String digit) async {
    if (state.isThrottled || state.isChecking) return;
    final next = state.entered + digit;
    state = state.copyWith(entered: next, clearMessage: true);
    if (next.length >= state.pinLength) await submit();
  }

  /// Removes the last digit.
  void backspace() {
    if (state.entered.isEmpty) return;
    state = state.copyWith(
      entered: state.entered.substring(0, state.entered.length - 1),
      clearMessage: true,
    );
  }

  /// Checks the entered PIN.
  Future<void> submit() async {
    if (state.isThrottled || state.isChecking) return;
    state = state.copyWith(isChecking: true);
    final outcome = await ref.read(pinServiceProvider).verifyPin(state.entered);

    if (outcome.unlocked) {
      _ticker?.cancel();
      _lastError = null;
      state = state.copyWith(isChecking: false, entered: '', clearMessage: true);
      ref.read(lockPhaseProvider.notifier).markUnlocked();
      return;
    }

    _lastError = outcome.isThrottled ? LockEntryError.throttled : LockEntryError.wrongPin;
    state = state.copyWith(
      isChecking: false,
      // Cleared, so the next attempt starts from an empty field rather than the user having to delete
      // four digits they already know are wrong.
      entered: '',
      shakeTrigger: state.shakeTrigger + 1,
      failedCount: outcome.failedCount,
      remaining: outcome.retryAfter,
    );
    if (outcome.retryAfter != null) _startTicker();

    // **Checked here and not inside `PinService`.** The service enforces ARCH_3 §2.3's throttle for
    // everyone; the erase is an opt-in the user turned on in Settings, so the decision belongs where the
    // setting is readable. Default off (§2.3), which is why an unset key reads as false.
    if (outcome.failedCount >= autoEraseFailureThreshold) {
      final enabled = await ref.read(autoEraseEnabledProvider.future);
      if (enabled) await _eraseEverything();
    }
  }

  /// Tries the biometric shortcut.
  ///
  /// **Subject to the same throttle as a PIN.** Otherwise the shortcut would be the cheaper of the two
  /// paths to attack, and a lock is only as strong as the weakest way in.
  Future<void> useBiometric({required String reason}) async {
    if (state.isThrottled || state.isChecking) return;
    state = state.copyWith(isChecking: true, clearMessage: true);
    final result = await ref.read(biometricGateProvider).authenticate(reason: reason);
    if (result.isOk) {
      _lastError = null;
      state = state.copyWith(isChecking: false);
      ref.read(lockPhaseProvider.notifier).markUnlocked();
      return;
    }
    _lastError = LockEntryError.biometricFailed;
    state = state.copyWith(
      isChecking: false,
      // **No `shakeTrigger` and no `failedCount`.** A dismissed fingerprint prompt is not a wrong PIN,
      // and counting it toward the throttle would let a pocket-tap lock somebody out.
      message: '',
    );
  }

  Future<void> _eraseEverything() async {
    state = state.copyWith(isErasing: true);
    final result = await ref.read(dataTransferPortProvider).eraseEverything();
    state = state.copyWith(isErasing: false);
    if (result.isFailure) {
      _lastError = LockEntryError.eraseFailed;
      return;
    }
    // The erase clears the lock too, so there is nothing left to unlock.
    await ref.read(lockPhaseProvider.notifier).refresh();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final remaining = await ref.read(pinServiceProvider).remainingLockout();
      if (remaining == null) {
        timer.cancel();
        state = state.copyWith(clearRemaining: true, clearMessage: true);
        return;
      }
      state = state.copyWith(remaining: remaining);
    });
  }
}
```

## The lock screen

**Archetype A's shape, not its skeleton, and there are two deviations — both recorded.** A is a capture
sheet, and a lock screen cannot be a sheet: a sheet is dismissible, and one with no way out is a worse
answer than a screen. What carries over is what A is actually about — exactly one required input, focus in
it on open, context as chips rather than pickers, and a commit that fires the moment the input parses.

The second deviation is a **keypad instead of A's "keyboard up"**. The system keyboard is the wrong control
here: it can be switched to a layout with no digits, it carries autocorrect chrome over a secret, and it can
be dismissed leaving no way to type on a screen with no other exit. Every key is a labelled 48dp target,
which is also what makes `labeledTapTargetGuideline` pass without special pleading.

**The copy is as much the point as the keypad.** ARCH_3 §2.5, on the screen where the decision is made:
this PIN stops someone who picks up the unlocked phone, and it does not encrypt anything. **There is no
padlock glyph anywhere in the file** — a closed padlock is the universal icon for encryption, and drawing
one would undo the sentence beside it.

Four details worth naming:

**The throttle is a duration that moves.** ARCH_3 §2.3's delays reach an hour; a screen that silently
refuses every tap is indistinguishable from a broken one. The `m:ss` is formatted in Dart rather than the
ARB, because a plural on "second" cannot express `1:05` and a clock is not a string a translator should
have to assemble.

**The empty feedback line reserves its height.** A control that moves under a thumb mid-tap is how a wrong
digit gets entered.

**Dots, one per configured digit** — which is why `readPinLength` was added to the port. A six-digit PIN
entered into four boxes is a confusing failure rather than a wrong one.

**The biometric key is absent, not disabled, where the device cannot offer it**, with a spacer holding `0`
centred. A disabled control that can never become enabled is the dead affordance ARCH_5 §10 objects to.

### `lib/features/lock/presentation/screens/lock_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/lock/presentation/widgets/pin_pad.dart';
import 'package:alaya/features/lock/providers/lock_entry_providers.dart';
import 'package:alaya/shared/widgets/scroll_safe_center.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

/// The PIN gate (ARCH_5 §3 archetype A, outside the shell).
///
/// **Archetype A's shape, not its skeleton, and the deviation is deliberate.** A is a capture sheet:
/// `AlayaBottomSheet`, one required field autofocused, optional context as chips, a full-width commit. A
/// lock screen cannot be a sheet — a sheet is dismissible, and one with no way out is a worse answer than
/// a screen. What carries over is everything A is actually about: exactly one required input, focus in it
/// on open, context as chips rather than pickers, and a commit that fires the moment the input parses.
///
/// **A keypad rather than a `TextField`, which is the second deviation from A's "keyboard up".** The
/// system keyboard is the wrong control here: it can be switched to a layout with no digits, it carries
/// autocorrect chrome over a secret, and it can be dismissed leaving no way to type on a screen with no
/// other exit. Every key here is a labelled 48dp target, which is also what makes
/// `labeledTapTargetGuideline` pass without special pleading.
///
/// **The copy is the point of this screen as much as the keypad is (ARCH_3 §2.5).** It says in plain words
/// that this PIN stops someone who picks up the unlocked phone, and that it does **not** encrypt anything
/// — because the database is plaintext by design (ARCH_1 §2.1) and claiming otherwise would be both
/// dishonest and a Play listing risk. There is no padlock glyph anywhere in this file: a closed padlock is
/// the universal icon for encryption, and drawing one here would undo the sentence beside it.
class LockScreen extends ConsumerWidget {
  /// Creates the lock screen.
  const LockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(lockEntryProvider);
    final notifier = ref.read(lockEntryProvider.notifier);

    // The fourth state, and the only destructive one this screen has: the ten-failure auto-erase is
    // running. It takes the whole screen because there is nothing left to enter a PIN against — the erase
    // clears the lock as well as the data — and because somebody watching their history be deleted should
    // not also be looking at a keypad.
    if (state.isErasing) {
      return Scaffold(
        body: ScrollSafeCenter(
          padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
          child: Text(
            strings.lockErasing,
            style: AlayaTypography.body.copyWith(color: context.semantic.danger),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: ScrollSafeCenter(
          padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.lockTitle,
                  style: AlayaTypography.screenTitle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AlayaSpacing.xs),
                // ARCH_3 §2.5, on the screen itself and not buried in Settings.
                Text(
                  strings.lockHonestBody,
                  style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AlayaSpacing.xl),
                ShakeOnError(
                  trigger: state.shakeTrigger,
                  child: PinDots(
                    length: state.pinLength,
                    filled: state.entered.length,
                    dimmed: state.isThrottled,
                  ),
                ),
                const SizedBox(height: AlayaSpacing.md),
                _Feedback(state: state, error: notifier.lastError),
                const SizedBox(height: AlayaSpacing.lg),
                PinKeypad(
                  enabled: !state.isThrottled && !state.isChecking,
                  onDigit: notifier.append,
                  onBackspace: notifier.backspace,
                  // A chip, in A's spirit: the shortcut sits beside the required input rather than
                  // replacing it, and it is absent — not disabled — where the device cannot offer it.
                  onBiometric: state.biometricAvailable
                      ? () => notifier.useBiometric(reason: strings.lockBiometricReason)
                      : null,
                ),
                const SizedBox(height: AlayaSpacing.lg),
                TextButton(
                  onPressed: () => context.push(Routes.lockRecovery),
                  child: Text(strings.lockForgotPin, style: AlayaTypography.button),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Keeps the keypad thumb-sized on a phone and stops it stretching across a tablet.
  static const double _maxWidth = 360;
}

/// The countdown, the refusal, or nothing.
///
/// **The throttle is stated as a duration that moves**, per this phase's brief. A screen that silently
/// refuses every tap is indistinguishable from a broken one, and ARCH_3 §2.3's delays reach an hour — long
/// enough that a user with no explanation would reasonably conclude the app had failed.
class _Feedback extends StatelessWidget {
  const _Feedback({required this.state, required this.error});

  final LockEntryState state;
  final LockEntryError? error;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    final remaining = state.remaining;
    if (remaining != null) {
      return Column(
        children: [
          Text(
            strings.lockThrottled(_clock(remaining)),
            style: AlayaTypography.bodyEmphasis.copyWith(color: semantic.warning),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AlayaSpacing.xxs),
          Text(
            strings.lockThrottledWhy,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    final message = switch (error) {
      LockEntryError.wrongPin => strings.lockWrongPin,
      LockEntryError.biometricFailed => strings.lockBiometricFailed,
      LockEntryError.eraseFailed => strings.lockEraseFailed,
      LockEntryError.throttled || null => null,
    };
    if (message == null) {
      // Reserves the line's height so the keypad does not jump when a message appears — a control that
      // moves under a thumb mid-tap is how a wrong digit gets entered.
      return const SizedBox(height: AlayaSpacing.lg);
    }
    return Text(
      message,
      style: AlayaTypography.body.copyWith(color: semantic.danger),
      textAlign: TextAlign.center,
    );
  }

  /// `m:ss` for anything a minute or longer, plain seconds below that.
  ///
  /// Formatted here rather than in the ARB because a plural on "second" cannot express `1:05`, and a
  /// duration is not a number a translator should have to assemble.
  String _clock(Duration remaining) {
    final total = remaining.inSeconds;
    if (total < 60) return '$total';
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '$minutes:${seconds < 10 ? '0$seconds' : '$seconds'}';
  }
}
```

## The PIN pad, extracted; and PIN setup

Three screens ask for a PIN — the lock, setup, and recovery — so `PinDots` and `PinKeypad` move into
`features/lock/presentation/widgets/`. **Feature-local, not `shared/`:** ARCH_5 §8 permits this phase no
shared additions, and it is right not to need one, because a keypad is only ever wanted by those three. The
alternative was three private copies, and the third would have drifted. `lock_screen.dart` shrinks from 346
lines to 186 and sheds the two token imports that went with the widgets.

**A defect of mine, caught in the writing.** `_commit` ended with `markUnlocked()`, then a state re-read,
then `markUnlocked()` again. Enabling a lock makes `isEnabled` answer true — so that middle re-read set the
phase to `locked`, firing the router's `refreshListenable` and ejecting the user to the lock screen from the
very screen where they had just entered their PIN twice. One `markUnlocked()` is the whole of it; the
re-read exists for the opposite direction, a lock disabled elsewhere.

Two other decisions inside the flow:

**A mismatch clears both entries, not just the second.** Somebody who mistyped does not know which of the
two was wrong, and re-confirming against a first entry they may have fat-fingered would set a PIN they do
not know.

**The recovery code is held in memory and nowhere else.** `PinService` stores its hash; a code the app could
redisplay would be one an attacker could read off a screen instead of guessing.

### `lib/features/lock/presentation/widgets/pin_pad.dart`

```dart
/// The PIN dots and keypad, shared by the three screens that ask for a PIN.
///
/// **Feature-local, not `shared/`.** ARCH_5 §8 permits this phase no shared additions, and it is
/// right not to need one: a keypad is only ever wanted by the lock, PIN setup and recovery, all of
/// which live here. Three private copies would have been the alternative, and the third would have
/// drifted.
library;

import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';



/// One dot per digit of the configured PIN.
///
/// Dots rather than an obscured field: the count is information the user needs — a six-digit PIN entered
/// into four boxes is a confusing failure — and `readPinLength` exists so this can be right.
class PinDots extends StatelessWidget {
  /// Creates the dots.
  const PinDots({required this.length, required this.filled, required this.dimmed});

  /// How many digits the configured PIN has.
  final int length;
  /// How many have been entered.
  final int filled;
  /// Renders muted while a throttle is in force.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.xs),
            child: Container(
              width: AlayaSpacing.sm,
              height: AlayaSpacing.sm,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled
                    ? (dimmed ? semantic.muted : theme.colorScheme.primary)
                    : theme.colorScheme.outlineVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// The digits, the backspace and the optional biometric shortcut.
class PinKeypad extends StatelessWidget {
  /// Creates the keypad.
  const PinKeypad({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
  });

  /// Whether keys accept taps.
  final bool enabled;
  /// Called with the digit tapped.
  final ValueChanged<String> onDigit;
  /// Removes the last digit.
  final VoidCallback onBackspace;
  /// The biometric shortcut, or null where the device has none.
  final VoidCallback? onBiometric;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final digit in row)
                _Key(
                  label: digit,
                  enabled: enabled,
                  onPressed: () => onDigit(digit),
                ),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (onBiometric == null)
              const _KeySpacer()
            else
              _Key(
                icon: Icons.fingerprint,
                // A tooltip and a `Semantics` label, because a fingerprint glyph is not one of the six
                // ARCH_5 §2.7 lets stand alone.
                semanticLabel: strings.lockUseBiometric,
                enabled: enabled,
                onPressed: onBiometric!,
              ),
            _Key(label: '0', enabled: enabled, onPressed: () => onDigit('0')),
            _Key(
              icon: Icons.backspace_outlined,
              semanticLabel: strings.lockBackspace,
              enabled: enabled,
              onPressed: onBackspace,
            ),
          ],
        ),
      ],
    );
  }
}

/// One key. Sized from the tap-target token, so a doubled text scale cannot shrink it below 48dp.
class _Key extends StatelessWidget {
  const _Key({
    required this.enabled,
    required this.onPressed,
    this.label,
    this.icon,
    this.semanticLabel,
  });

  final bool enabled;
  final VoidCallback onPressed;
  final String? label;
  final IconData? icon;
  final String? semanticLabel;

  static const double _extent = AlayaSpacing.minTapTarget + AlayaSpacing.md;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = icon != null
        ? Icon(icon, size: AlayaIconSize.lg)
        : Text(label!, style: AlayaTypography.amountLarge);

    return Padding(
      padding: const EdgeInsets.all(AlayaSpacing.xs),
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: SizedBox(
          width: _extent,
          height: _extent,
          child: Material(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: AlayaRadii.borderMd,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              borderRadius: AlayaRadii.borderMd,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Holds the biometric key's place when the device cannot offer one, so `0` stays centred.
class _KeySpacer extends StatelessWidget {
  const _KeySpacer();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(AlayaSpacing.xs),
        child: SizedBox(width: _Key._extent, height: _Key._extent),
      );
}
```

### `lib/features/lock/providers/pin_setup_providers.dart`

```dart
/// View-model state for setting or changing the PIN (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/features/lock/providers/lock_providers.dart';

/// Which part of the setup flow is showing.
enum PinSetupStage {
  /// Choosing and entering a PIN.
  enter,

  /// Entering it a second time.
  confirm,

  /// The recovery code, shown once.
  recovery,

  /// The offer to make a backup, per ARCH_3 §2.2.
  backup,

  /// Finished.
  done,
}

/// What the setup flow is holding.
class PinSetupState {
  /// Creates a state.
  const PinSetupState({
    this.stage = PinSetupStage.enter,
    this.length = 4,
    this.entered = '',
    this.confirmed = '',
    this.recoveryCode,
    this.acknowledged = false,
    this.isSaving = false,
    this.shakeTrigger = 0,
    this.mismatch = false,
    this.failureMessage,
  });

  /// The part being shown.
  final PinSetupStage stage;

  /// Four digits, or six if the user chose it (ARCH_3 §2.1).
  final int length;

  /// The first entry.
  final String entered;

  /// The second entry.
  final String confirmed;

  /// The code to show exactly once, formatted `ABCDE-FGHJK`.
  ///
  /// Held in memory only, and never written anywhere this app can read back — `PinService` stores its
  /// hash and nothing else. A code the app could redisplay would be one an attacker could read off a
  /// screen instead of guessing.
  final String? recoveryCode;

  /// Whether the one confirmation box is ticked.
  final bool acknowledged;

  /// Whether a write is in flight.
  final bool isSaving;

  /// Incremented on a mismatch, so two in a row shake twice.
  final int shakeTrigger;

  /// Whether the second entry differed from the first.
  final bool mismatch;

  /// The service's own message from a failed enable (Law U9).
  final String? failureMessage;

  /// Which entry the keypad is filling.
  String get active => stage == PinSetupStage.confirm ? confirmed : entered;

  /// A copy with the given fields replaced.
  PinSetupState copyWith({
    PinSetupStage? stage,
    int? length,
    String? entered,
    String? confirmed,
    String? recoveryCode,
    bool? acknowledged,
    bool? isSaving,
    int? shakeTrigger,
    bool? mismatch,
    String? failureMessage,
    bool clearFailure = false,
  }) =>
      PinSetupState(
        stage: stage ?? this.stage,
        length: length ?? this.length,
        entered: entered ?? this.entered,
        confirmed: confirmed ?? this.confirmed,
        recoveryCode: recoveryCode ?? this.recoveryCode,
        acknowledged: acknowledged ?? this.acknowledged,
        isSaving: isSaving ?? this.isSaving,
        shakeTrigger: shakeTrigger ?? this.shakeTrigger,
        mismatch: mismatch ?? this.mismatch,
        failureMessage: clearFailure ? null : (failureMessage ?? this.failureMessage),
      );
}

/// The PIN setup flow's state.
final pinSetupProvider =
    NotifierProvider<PinSetupNotifier, PinSetupState>(PinSetupNotifier.new);

/// Drives the four stages ARCH_3 §2.2 specifies for enabling a lock.
class PinSetupNotifier extends Notifier<PinSetupState> {
  @override
  PinSetupState build() => const PinSetupState();

  /// Switches between a 4- and 6-digit PIN, discarding whatever was typed.
  ///
  /// Discarding is deliberate: keeping three digits of a four-digit attempt when the user asks for six
  /// leaves a half-filled field that looks like progress toward something it is not.
  void setLength(int length) => state = PinSetupState(length: length);

  /// Appends a digit to whichever entry is active, advancing when it is full.
  Future<void> append(String digit) async {
    if (state.isSaving) return;
    if (state.stage == PinSetupStage.enter) {
      final next = state.entered + digit;
      state = state.copyWith(entered: next, mismatch: false, clearFailure: true);
      if (next.length >= state.length) {
        state = state.copyWith(stage: PinSetupStage.confirm);
      }
      return;
    }
    if (state.stage != PinSetupStage.confirm) return;
    final next = state.confirmed + digit;
    state = state.copyWith(confirmed: next, mismatch: false);
    if (next.length >= state.length) await _commit();
  }

  /// Removes the last digit of the active entry, stepping back a stage when it empties.
  void backspace() {
    if (state.stage == PinSetupStage.confirm) {
      if (state.confirmed.isEmpty) {
        // Back to the first entry rather than nowhere: a user who mistyped the confirmation and holds
        // backspace should end up somewhere they can act, not at a dead field.
        state = state.copyWith(stage: PinSetupStage.enter, mismatch: false);
        return;
      }
      state = state.copyWith(
        confirmed: state.confirmed.substring(0, state.confirmed.length - 1),
        mismatch: false,
      );
      return;
    }
    if (state.entered.isEmpty) return;
    state = state.copyWith(entered: state.entered.substring(0, state.entered.length - 1));
  }

  Future<void> _commit() async {
    if (state.confirmed != state.entered) {
      // **Both entries are cleared, not just the second.** Somebody who mistyped does not know which of
      // the two was wrong, and re-confirming against a first entry they may have fat-fingered would set a
      // PIN they do not know.
      state = state.copyWith(
        stage: PinSetupStage.enter,
        entered: '',
        confirmed: '',
        mismatch: true,
        shakeTrigger: state.shakeTrigger + 1,
      );
      return;
    }

    state = state.copyWith(isSaving: true, clearFailure: true);
    final result = await ref.read(pinServiceProvider).enable(pin: state.entered);
    final code = result.valueOrNull;
    if (code == null) {
      state = state.copyWith(
        isSaving: false,
        stage: PinSetupStage.enter,
        entered: '',
        confirmed: '',
        shakeTrigger: state.shakeTrigger + 1,
        failureMessage: result.failureOrNull?.message,
      );
      return;
    }

    // **The session is marked satisfied, and deliberately *not* refreshed.** Enabling a lock means
    // `PinService.isEnabled` now answers true, so re-reading it here would set the phase to `locked` —
    // firing the router's `refreshListenable` and ejecting the user to the lock screen from the very
    // screen where they just entered the PIN twice, which is more proof than the lock screen asks for.
    // The re-read exists for the opposite direction: a lock disabled elsewhere.
    ref.read(lockPhaseProvider.notifier).markUnlocked();

    state = state.copyWith(
      isSaving: false,
      stage: PinSetupStage.recovery,
      recoveryCode: code,
    );
  }

  /// Ticks or unticks the single confirmation box.
  void acknowledge({required bool value}) =>
      state = state.copyWith(acknowledged: value);

  /// Moves from the recovery code to the backup offer.
  void toBackupOffer() {
    if (!state.acknowledged) return;
    state = state.copyWith(stage: PinSetupStage.backup);
  }

  /// Exports a backup and offers to share it, then finishes.
  Future<bool> backupNow() async {
    state = state.copyWith(isSaving: true, clearFailure: true);
    final result = await ref.read(dataTransferPortProvider).exportAndShare();
    state = state.copyWith(
      isSaving: false,
      stage: result.isOk ? PinSetupStage.done : PinSetupStage.backup,
      failureMessage: result.isOk ? null : result.failureOrNull?.message,
    );
    return result.isOk;
  }

  /// Declines the backup and finishes.
  void skipBackup() => state = state.copyWith(stage: PinSetupStage.done);
}
```

## PIN setup

**ARCH_3 §2.2's sequence exactly, and the order is not arbitrary.** PIN twice, then the recovery code, then
one confirmation, then the offer of a backup. The code is generated only once the PIN is confirmed, so a
half-finished attempt leaves no orphan secret; the confirmation gates leaving the code behind; and the
backup offer comes last, because that is the moment a lock has just been placed over data the user may have
no other copy of.

**`embedded` is what lets onboarding reuse this without a route** — a route would fight the onboarding gate
that sends everything outside `/onboarding` back to it. As a screen it brings its own `Scaffold` and a
`CloseButton` (archetype B: setting a PIN is a task you abandon, not a place you go up from); embedded it is
a bare column and the enclosing footer is the way on.

**One checkbox, per the brief.** Two would be a form; none would let somebody swipe past the only thing that
can rescue a forgotten PIN. It gates the button rather than warning after the fact.

**ARCH_3 §3.4's warning is on the backup offer, in a tinted panel, every time.** Not in settings, not a
tooltip. The database is plaintext too, so this is a consistent threat model rather than a contradiction —
and saying it here is what keeps it one.

Copy-to-clipboard **is** offered for the recovery code. A password manager is the sensible home for it, and
refusing to let people use one is worse security theatre than the clipboard risk it avoids. The code is also
`SelectableText` in a tabular numeric style, so every glyph is the same width and nothing is ambiguous.

Two defects of mine fixed in the writing: `_MarkOnboardingLock` was constructed as `const` without having a
constructor, and `_BackupStage` took an `embedded` field it never read.

The `ERASE` word moved from `EraseService` onto `DataTransferPort`, because the screen that must compare
against it may not import `data/` — and a second copy in the UI would have been a second thing to change.

### `lib/features/lock/presentation/screens/pin_setup_flow.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/lock/presentation/widgets/pin_pad.dart';
import 'package:alaya/features/lock/providers/pin_setup_providers.dart';
import 'package:alaya/features/onboarding/providers/onboarding_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

/// Setting or changing the PIN (ARCH_5 §3 archetype B).
///
/// **ARCH_3 §2.2's sequence exactly: PIN twice, then the recovery code, then one confirmation, then the
/// offer of a backup.** The order is not arbitrary. The code is generated only once the PIN is confirmed,
/// so a half-finished attempt leaves no orphan secret; the confirmation gates leaving the code behind; and
/// the backup offer comes last because it is the moment a lock has just been placed over data the user may
/// have no other copy of.
///
/// **[embedded] is what lets onboarding reuse this without a route.** As a screen it brings its own
/// `Scaffold` and app bar; embedded it is a bare column, because onboarding owns the chrome and the
/// footer, and because a route here would fight the onboarding gate that sends everything outside
/// `/onboarding` back to it.
class PinSetupFlow extends ConsumerWidget {
  /// Creates the flow. [embedded] omits the scaffold, for onboarding's security step.
  const PinSetupFlow({this.embedded = false, super.key});

  /// Whether an enclosing screen supplies the scaffold.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final body = _Body(embedded: embedded);
    if (embedded) return body;

    return Scaffold(
      appBar: AppBar(
        // `CloseButton`, per archetype B: setting a PIN is a task you abandon, not a place you go up from.
        leading: const CloseButton(),
        title: Text(strings.pinSetupTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
          child: body,
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.embedded});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pinSetupProvider);
    return switch (state.stage) {
      PinSetupStage.enter || PinSetupStage.confirm => const _EntryStage(),
      PinSetupStage.recovery => const _RecoveryStage(),
      PinSetupStage.backup => const _BackupStage(),
      PinSetupStage.done => _DoneStage(embedded: embedded),
    };
  }
}

/// Stages one and two: the PIN, twice.
class _EntryStage extends ConsumerWidget {
  const _EntryStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(pinSetupProvider);
    final notifier = ref.read(pinSetupProvider.notifier);
    final confirming = state.stage == PinSetupStage.confirm;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          confirming ? strings.pinSetupConfirmPrompt : strings.pinSetupEnterPrompt,
          style: AlayaTypography.bodyEmphasis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Text(
          strings.lockHonestBody,
          style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AlayaSpacing.lg),
        // Offered only before the first digit: changing length mid-entry discards what was typed, and a
        // control that silently throws away work is worse than one that disappears.
        if (!confirming && state.entered.isEmpty)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AlayaSpacing.xs,
            children: [
              for (final length in const [4, 6])
                ChoiceChip(
                  label: Text(strings.pinSetupLength(length), style: AlayaTypography.button),
                  selected: state.length == length,
                  onSelected: (_) => notifier.setLength(length),
                ),
            ],
          ),
        const SizedBox(height: AlayaSpacing.lg),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: PinDots(
            length: state.length,
            filled: state.active.length,
            dimmed: false,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        if (state.mismatch)
          Text(
            strings.pinSetupMismatch,
            style: AlayaTypography.body.copyWith(color: context.semantic.danger),
            textAlign: TextAlign.center,
          )
        else if (state.failureMessage != null)
          Text(
            state.failureMessage!,
            style: AlayaTypography.body.copyWith(color: context.semantic.danger),
            textAlign: TextAlign.center,
          )
        else
          const SizedBox(height: AlayaSpacing.lg),
        const SizedBox(height: AlayaSpacing.md),
        PinKeypad(
          enabled: !state.isSaving,
          onDigit: notifier.append,
          onBackspace: notifier.backspace,
        ),
      ],
    );
  }
}

/// Stage three: the recovery code, shown once, behind one confirmation.
class _RecoveryStage extends ConsumerWidget {
  const _RecoveryStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(pinSetupProvider);
    final notifier = ref.read(pinSetupProvider.notifier);
    final code = state.recoveryCode ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(label: strings.pinSetupRecoveryHeader),
        const SizedBox(height: AlayaSpacing.xs),
        Text(strings.pinSetupRecoveryBody, style: AlayaTypography.body),
        const SizedBox(height: AlayaSpacing.lg),
        AlayaCard(
          padding: const EdgeInsets.all(AlayaSpacing.lg),
          child: Column(
            children: [
              // `SelectableText`, so somebody using a screen reader or a password manager can get at it
              // without the clipboard — and `amountLarge` because a tabular numeric style is exactly what
              // a code of digits and letters wants: every glyph the same width, nothing ambiguous.
              SelectableText(
                code,
                style: AlayaTypography.amountLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AlayaSpacing.sm),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (!context.mounted) return;
                  showResultSnack(context, message: strings.pinSetupRecoveryCopied);
                },
                icon: const Icon(Icons.copy_outlined, size: AlayaIconSize.md),
                label: Text(strings.pinSetupRecoveryCopy, style: AlayaTypography.button),
              ),
            ],
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        // Copy is offered rather than withheld: a password manager is the sensible home for this, and
        // refusing to let people use one would be worse security theatre than the clipboard risk it avoids.
        Text(
          strings.pinSetupRecoveryWhereToKeep,
          style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.lg),
        // **One checkbox, per the brief.** Two would be a form; none would let somebody swipe past the only
        // thing that can rescue a forgotten PIN. It gates the button rather than warning after the fact.
        CheckboxListTile(
          value: state.acknowledged,
          onChanged: (value) => notifier.acknowledge(value: value ?? false),
          title: Text(strings.pinSetupRecoveryAck, style: AlayaTypography.body),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
        ),
        const SizedBox(height: AlayaSpacing.md),
        FilledButton(
          onPressed: state.acknowledged ? notifier.toBackupOffer : null,
          child: Text(strings.actionContinue, style: AlayaTypography.button),
        ),
      ],
    );
  }
}

/// Stage four: the offer of a backup, per ARCH_3 §2.2.
class _BackupStage extends ConsumerWidget {
  const _BackupStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(pinSetupProvider);
    final notifier = ref.read(pinSetupProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(label: strings.pinSetupBackupHeader),
        const SizedBox(height: AlayaSpacing.xs),
        Text(strings.pinSetupBackupBody, style: AlayaTypography.body),
        const SizedBox(height: AlayaSpacing.md),
        // **ARCH_3 §3.4, every single time an export is offered** — not in settings, not a tooltip. The
        // database is plaintext too, so this is a consistent threat model rather than a contradiction, and
        // saying it here is what keeps it one.
        Container(
          padding: const EdgeInsets.all(AlayaSpacing.md),
          decoration: BoxDecoration(
            color: context.semantic.warning.withValues(alpha: 0.12),
            borderRadius: AlayaRadii.borderMd,
          ),
          child: Text(
            strings.backupNotEncryptedWarning,
            style: AlayaTypography.bodyEmphasis,
          ),
        ),
        if (state.failureMessage != null) ...[
          const SizedBox(height: AlayaSpacing.md),
          Text(
            state.failureMessage!,
            style: AlayaTypography.body.copyWith(color: context.semantic.danger),
          ),
        ],
        const SizedBox(height: AlayaSpacing.lg),
        FilledButton(
          onPressed: state.isSaving ? null : () => notifier.backupNow(),
          child: Text(strings.pinSetupBackupNow, style: AlayaTypography.button),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextButton(
          onPressed: state.isSaving ? null : notifier.skipBackup,
          child: Text(strings.pinSetupBackupLater, style: AlayaTypography.button),
        ),
      ],
    );
  }
}

/// The lock is on.
class _DoneStage extends ConsumerWidget {
  const _DoneStage({required this.embedded});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_outline,
                size: AlayaIconSize.lg, color: context.semantic.success),
            const SizedBox(width: AlayaSpacing.sm),
            Expanded(
              child: Text(strings.pinSetupDone, style: AlayaTypography.bodyEmphasis),
            ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.md),
        Text(
          strings.pinSetupDoneBody,
          style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
        ),
        if (!embedded) ...[
          const SizedBox(height: AlayaSpacing.lg),
          FilledButton(
            onPressed: () => context.pop(),
            child: Text(strings.actionDone, style: AlayaTypography.button),
          ),
        ] else ...[
          const SizedBox(height: AlayaSpacing.md),
          // Embedded, the enclosing flow's footer is the way on — but it needs to know a lock now exists,
          // so `finish()` can mark the session satisfied instead of the router ejecting the user.
          const _MarkOnboardingLock(),
        ],
      ],
    );
  }
}

/// Tells the onboarding draft that a lock was set, once.
///
/// A widget rather than a call in `build`: mutating another provider during a build is the error Riverpod
/// asserts on, and a post-frame callback is the sanctioned way to report upward from a subtree.
class _MarkOnboardingLock extends ConsumerStatefulWidget {
  const _MarkOnboardingLock();

  @override
  ConsumerState<_MarkOnboardingLock> createState() => _MarkOnboardingLockState();
}

class _MarkOnboardingLockState extends ConsumerState<_MarkOnboardingLock> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(onboardingControllerProvider.notifier).markLockEnabled();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
```

## Recovery, and the last resort

**`/lock/recovery` sits under `/lock` because the router permits that whole branch while locked.** Anywhere
else, this screen would be redirected straight back to the PIN the user cannot remember — which is the bug
instalment 2's prefix fix was for, seen from the other end.

**The code is not checked before the new PIN is chosen, deliberately.**
`PinService.resetWithRecoveryCode` verifies the code *and* the throttle together, at the point it would set
the PIN. A pre-check with nothing behind it would give unlimited free guesses against the weaker of the two
secrets, which would make the whole lock only as strong as the path nobody remembers exists. A rejection
returns to the code stage rather than the keypad, because a wrong code is the likely cause and leaving
somebody on the keypad spends another throttled attempt on the same mistake.

**The forgot-both path offers the export above the erase, not beside it.** ARCH_3 §2.2 requires the offer;
putting it first is what makes it an offer rather than a footnote nobody reads after they have already typed
the word. §3.4's not-encrypted warning is on it, as everywhere else an export is offered.

**The erase button is an `OutlinedButton` in `danger`, never a filled one**, and enabled only on an exact
match with `DataTransferPort.eraseConfirmationWord`. ARCH_5 §5.5 puts an irreversible action last and quiet;
a prominent primary here would be the one control on the screen that destroys everything, styled like the
one that saves.

**And this path only exists because the database is plaintext.** With encryption the export would have been
unreadable without the key the user has lost. Nobody permanently loses their financial history to a
forgotten four-digit PIN — which ARCH_4 records as the improvement dropping encryption bought.

`AppLock` gains `recoveryCodeLength`, so the field's counter cannot disagree with the validator that rejects
it; `RecoveryCode.length` lives in `data/`, where a feature may not reach.

### `lib/features/lock/providers/recovery_providers.dart`

```dart
/// View-model state for the forgotten-PIN and forgotten-both paths (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/features/lock/providers/lock_providers.dart';

/// Which part of the recovery flow is showing.
enum RecoveryStage {
  /// Entering the recovery code.
  code,

  /// Choosing a new PIN.
  newPin,

  /// Entering the new PIN again.
  confirmPin,

  /// The last resort: erase and start over.
  forgotBoth,

  /// The PIN has been reset.
  done,
}

/// What the recovery flow is holding.
class RecoveryState {
  /// Creates a state.
  const RecoveryState({
    this.stage = RecoveryStage.code,
    this.code = '',
    this.length = 4,
    this.entered = '',
    this.confirmed = '',
    this.eraseTyped = '',
    this.isWorking = false,
    this.shakeTrigger = 0,
    this.mismatch = false,
    this.exported = false,
    this.failureMessage,
  });

  /// The stage being shown.
  final RecoveryStage stage;

  /// The recovery code as typed, hyphen and case included.
  ///
  /// Passed through unnormalised: `PinService.resetWithRecoveryCode` normalises and validates, and a second
  /// normaliser here could disagree with the one that actually checks.
  final String code;

  /// How many digits the new PIN will have.
  final int length;

  /// The first entry of the new PIN.
  final String entered;

  /// The second entry.
  final String confirmed;

  /// What the user has typed into the erase confirmation.
  final String eraseTyped;

  /// Whether a check, export or erase is in flight.
  final bool isWorking;

  /// Incremented on a rejection, so two in a row shake twice.
  final int shakeTrigger;

  /// Whether the two new-PIN entries differed.
  final bool mismatch;

  /// Whether a backup has been taken during this flow.
  final bool exported;

  /// The service's own message from the last failure (Law U9).
  final String? failureMessage;

  /// Which entry the keypad is filling.
  String get active => stage == RecoveryStage.confirmPin ? confirmed : entered;

  /// A copy with the given fields replaced.
  RecoveryState copyWith({
    RecoveryStage? stage,
    String? code,
    int? length,
    String? entered,
    String? confirmed,
    String? eraseTyped,
    bool? isWorking,
    int? shakeTrigger,
    bool? mismatch,
    bool? exported,
    String? failureMessage,
    bool clearFailure = false,
  }) =>
      RecoveryState(
        stage: stage ?? this.stage,
        code: code ?? this.code,
        length: length ?? this.length,
        entered: entered ?? this.entered,
        confirmed: confirmed ?? this.confirmed,
        eraseTyped: eraseTyped ?? this.eraseTyped,
        isWorking: isWorking ?? this.isWorking,
        shakeTrigger: shakeTrigger ?? this.shakeTrigger,
        mismatch: mismatch ?? this.mismatch,
        exported: exported ?? this.exported,
        failureMessage: clearFailure ? null : (failureMessage ?? this.failureMessage),
      );
}

/// The recovery flow's state.
final recoveryProvider =
    NotifierProvider<RecoveryNotifier, RecoveryState>(RecoveryNotifier.new);

/// Drives recovery by code, and the erase behind it.
class RecoveryNotifier extends Notifier<RecoveryState> {
  @override
  RecoveryState build() => const RecoveryState();

  /// Records the typed code.
  void setCode(String code) =>
      state = state.copyWith(code: code, clearFailure: true);

  /// Moves to choosing a new PIN.
  ///
  /// **The code is not checked here.** `PinService.resetWithRecoveryCode` verifies it and the throttle
  /// together, at the point it would set the new PIN — so a wrong code costs one throttled attempt rather
  /// than an unlimited number of free guesses against a check with nothing behind it.
  void toNewPin() {
    if (state.code.trim().isEmpty) return;
    state = state.copyWith(stage: RecoveryStage.newPin, clearFailure: true);
  }

  /// Switches between a 4- and 6-digit new PIN, discarding what was typed.
  void setLength(int length) =>
      state = state.copyWith(length: length, entered: '', confirmed: '', mismatch: false);

  /// Appends a digit to whichever entry is active.
  Future<void> append(String digit) async {
    if (state.isWorking) return;
    if (state.stage == RecoveryStage.newPin) {
      final next = state.entered + digit;
      state = state.copyWith(entered: next, mismatch: false, clearFailure: true);
      if (next.length >= state.length) {
        state = state.copyWith(stage: RecoveryStage.confirmPin);
      }
      return;
    }
    if (state.stage != RecoveryStage.confirmPin) return;
    final next = state.confirmed + digit;
    state = state.copyWith(confirmed: next, mismatch: false);
    if (next.length >= state.length) await _reset();
  }

  /// Removes the last digit, stepping back a stage when the entry empties.
  void backspace() {
    if (state.stage == RecoveryStage.confirmPin) {
      if (state.confirmed.isEmpty) {
        state = state.copyWith(stage: RecoveryStage.newPin, mismatch: false);
        return;
      }
      state = state.copyWith(
        confirmed: state.confirmed.substring(0, state.confirmed.length - 1),
        mismatch: false,
      );
      return;
    }
    if (state.entered.isEmpty) return;
    state = state.copyWith(entered: state.entered.substring(0, state.entered.length - 1));
  }

  Future<void> _reset() async {
    if (state.confirmed != state.entered) {
      state = state.copyWith(
        stage: RecoveryStage.newPin,
        entered: '',
        confirmed: '',
        mismatch: true,
        shakeTrigger: state.shakeTrigger + 1,
      );
      return;
    }

    state = state.copyWith(isWorking: true, clearFailure: true);
    final result = await ref.read(pinServiceProvider).resetWithRecoveryCode(
          code: state.code,
          newPin: state.entered,
        );
    if (result.isFailure) {
      // **Back to the code stage, not the PIN stage.** A rejection here is almost always a wrong recovery
      // code rather than a mistyped new PIN, and leaving somebody on the keypad to try the same code again
      // spends another throttled attempt on the same mistake.
      state = state.copyWith(
        isWorking: false,
        stage: RecoveryStage.code,
        entered: '',
        confirmed: '',
        shakeTrigger: state.shakeTrigger + 1,
        failureMessage: result.failureOrNull?.message,
      );
      return;
    }

    state = state.copyWith(isWorking: false, stage: RecoveryStage.done);
    // The new PIN satisfies this session: somebody who has just chosen one, twice, should not be asked for
    // it again on the way out.
    ref.read(lockPhaseProvider.notifier).markUnlocked();
  }

  /// Opens the last resort.
  void toForgotBoth() =>
      state = state.copyWith(stage: RecoveryStage.forgotBoth, clearFailure: true);

  /// Records what has been typed into the erase confirmation.
  void setEraseTyped(String value) => state = state.copyWith(eraseTyped: value);

  /// Exports a backup before erasing, per ARCH_3 §2.2.
  ///
  /// **Possible only because the database is plaintext and the lock is not a decryption key.** This is the
  /// path the redesign bought: nobody permanently loses their financial history to a forgotten PIN.
  Future<bool> exportFirst() async {
    state = state.copyWith(isWorking: true, clearFailure: true);
    final result = await ref.read(dataTransferPortProvider).exportAndShare();
    state = state.copyWith(
      isWorking: false,
      exported: result.isOk,
      failureMessage: result.isOk ? null : result.failureOrNull?.message,
    );
    return result.isOk;
  }

  /// Erases everything, once the confirmation word has been typed exactly.
  Future<bool> eraseEverything() async {
    state = state.copyWith(isWorking: true, clearFailure: true);
    final result = await ref.read(dataTransferPortProvider).eraseEverything();
    if (result.isFailure) {
      state = state.copyWith(isWorking: false, failureMessage: result.failureOrNull?.message);
      return false;
    }
    state = state.copyWith(isWorking: false, stage: RecoveryStage.done);
    // The erase cleared the lock as well as the data, so re-reading leaves the app open.
    await ref.read(lockPhaseProvider.notifier).refresh();
    return true;
  }
}
```

### `lib/features/lock/presentation/screens/recovery_flow.dart`

```dart
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
import 'package:alaya/domain/services/backup/data_transfer_port.dart';
import 'package:alaya/domain/services/lock/app_lock.dart';
import 'package:alaya/features/lock/presentation/widgets/pin_pad.dart';
import 'package:alaya/features/lock/providers/recovery_providers.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

/// Recovering a forgotten PIN, and the last resort behind it (ARCH_5 §3 archetype B).
///
/// **Reachable while the app is locked**, which is why `/lock/recovery` sits under `/lock`: the router
/// permits anything in that branch while locked, and anywhere else this screen would be redirected straight
/// back to the PIN the user cannot remember.
///
/// **The forgot-both path offers a backup before it erases, and that is the improvement dropping encryption
/// bought** (ARCH_3 §2.2). With an encrypted database the export would have been unreadable without the key
/// the user has lost; plaintext means nobody permanently loses their financial history to a forgotten
/// four-digit PIN.
class RecoveryFlow extends ConsumerWidget {
  /// Creates the flow.
  const RecoveryFlow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(recoveryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.recoveryTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
          child: switch (state.stage) {
            RecoveryStage.code => const _CodeStage(),
            RecoveryStage.newPin || RecoveryStage.confirmPin => const _PinStage(),
            RecoveryStage.forgotBoth => const _ForgotBothStage(),
            RecoveryStage.done => const _DoneStage(),
          },
        ),
      ),
    );
  }
}

/// Entering the recovery code.
class _CodeStage extends ConsumerWidget {
  const _CodeStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(recoveryProvider);
    final notifier = ref.read(recoveryProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings.recoveryCodePrompt, style: AlayaTypography.body),
        const SizedBox(height: AlayaSpacing.lg),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: TextField(
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            // The length comes from the contract, so the counter cannot disagree with the validator. One
            // extra character for the display hyphen in `ABCDE-FGHJK`.
            maxLength: AppLock.recoveryCodeLength + 1,
            style: AlayaTypography.amountLarge,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              labelText: strings.recoveryCodeLabel,
              errorText: state.failureMessage,
            ),
            onChanged: notifier.setCode,
          ),
        ),
        const SizedBox(height: AlayaSpacing.lg),
        FilledButton(
          onPressed: state.code.trim().isEmpty ? null : notifier.toNewPin,
          child: Text(strings.actionContinue, style: AlayaTypography.button),
        ),
        const SizedBox(height: AlayaSpacing.xl),
        // The last resort is reachable but not adjacent to the commit: a destructive path sits last and
        // quiet, in the manner of archetype E's destructive actions (ARCH_5 §3).
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: notifier.toForgotBoth,
            child: Text(strings.recoveryForgotBoth, style: AlayaTypography.button),
          ),
        ),
      ],
    );
  }
}

/// Choosing the new PIN, twice.
class _PinStage extends ConsumerWidget {
  const _PinStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(recoveryProvider);
    final notifier = ref.read(recoveryProvider.notifier);
    final confirming = state.stage == RecoveryStage.confirmPin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          confirming ? strings.pinSetupConfirmPrompt : strings.recoveryNewPinPrompt,
          style: AlayaTypography.bodyEmphasis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AlayaSpacing.lg),
        if (!confirming && state.entered.isEmpty)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AlayaSpacing.xs,
            children: [
              for (final length in const [4, 6])
                ChoiceChip(
                  label: Text(strings.pinSetupLength(length), style: AlayaTypography.button),
                  selected: state.length == length,
                  onSelected: (_) => notifier.setLength(length),
                ),
            ],
          ),
        const SizedBox(height: AlayaSpacing.lg),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: PinDots(length: state.length, filled: state.active.length, dimmed: false),
        ),
        const SizedBox(height: AlayaSpacing.md),
        if (state.mismatch)
          Text(
            strings.pinSetupMismatch,
            style: AlayaTypography.body.copyWith(color: context.semantic.danger),
            textAlign: TextAlign.center,
          )
        else
          const SizedBox(height: AlayaSpacing.lg),
        const SizedBox(height: AlayaSpacing.md),
        PinKeypad(
          enabled: !state.isWorking,
          onDigit: notifier.append,
          onBackspace: notifier.backspace,
        ),
      ],
    );
  }
}

/// The last resort: export, then type the word, then erase.
class _ForgotBothStage extends ConsumerWidget {
  const _ForgotBothStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(recoveryProvider);
    final notifier = ref.read(recoveryProvider.notifier);
    final semantic = context.semantic;
    final armed = state.eraseTyped.trim() == DataTransferPort.eraseConfirmationWord;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings.recoveryForgotBothTitle, style: AlayaTypography.bodyEmphasis),
        const SizedBox(height: AlayaSpacing.xs),
        Text(strings.recoveryForgotBothBody, style: AlayaTypography.body),
        const SizedBox(height: AlayaSpacing.lg),
        // **The export comes first, and it is offered rather than assumed.** ARCH_3 §2.2 requires the offer;
        // ordering it above the erase is what makes it an offer rather than a footnote nobody reads after
        // they have already typed the word.
        Container(
          padding: const EdgeInsets.all(AlayaSpacing.md),
          decoration: BoxDecoration(
            color: semantic.warning.withValues(alpha: 0.12),
            borderRadius: AlayaRadii.borderMd,
          ),
          child: Text(strings.backupNotEncryptedWarning, style: AlayaTypography.bodyEmphasis),
        ),
        const SizedBox(height: AlayaSpacing.md),
        if (state.exported)
          Row(
            children: [
              Icon(Icons.check_circle_outline,
                  size: AlayaIconSize.md, color: semantic.success),
              const SizedBox(width: AlayaSpacing.xs),
              Expanded(
                child: Text(strings.recoveryExported, style: AlayaTypography.body),
              ),
            ],
          )
        else
          FilledButton.tonal(
            onPressed: state.isWorking ? null : () => notifier.exportFirst(),
            child: Text(strings.recoveryExportFirst, style: AlayaTypography.button),
          ),
        const SizedBox(height: AlayaSpacing.xl),
        Text(
          strings.recoveryTypeToConfirm(DataTransferPort.eraseConfirmationWord),
          style: AlayaTypography.body,
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextField(
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: DataTransferPort.eraseConfirmationWord,
            errorText: state.failureMessage,
          ),
          onChanged: notifier.setEraseTyped,
        ),
        const SizedBox(height: AlayaSpacing.md),
        // **Enabled only on an exact match, and never a filled button.** ARCH_5 §5.5 puts an irreversible
        // action last and quiet; a prominent primary here would be the one control on the screen that
        // destroys everything, styled like the one that saves.
        OutlinedButton(
          onPressed: armed && !state.isWorking ? () => notifier.eraseEverything() : null,
          style: OutlinedButton.styleFrom(foregroundColor: semantic.danger),
          child: Text(strings.recoveryEraseEverything, style: AlayaTypography.button),
        ),
      ],
    );
  }
}

/// The PIN is reset, or the data is gone.
class _DoneStage extends ConsumerWidget {
  const _DoneStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_outline,
                size: AlayaIconSize.lg, color: context.semantic.success),
            const SizedBox(width: AlayaSpacing.sm),
            Expanded(child: Text(strings.recoveryDone, style: AlayaTypography.bodyEmphasis)),
          ],
        ),
        const SizedBox(height: AlayaSpacing.lg),
        FilledButton(
          // `go`, not `pop`: the lock branch is behind this screen and the redirect has already released it,
          // so popping would land on a lock screen that immediately bounces to the dashboard anyway.
          onPressed: () => context.go(Routes.dashboard),
          child: Text(strings.actionDone, style: AlayaTypography.button),
        ),
      ],
    );
  }
}
```

## The settings tree

**Archetype D with two deviations.** No FAB, because nothing is added at the tree level — every branch owns
its own add action. And the grouping is by subject rather than a user-chosen axis, because a settings tree has
no axis the user controls; the three groups are what the app is made of, in the order somebody looks for them.

Like every shell destination it declares **no `Scaffold` and no `AppBar`** — `_ShellScaffold` owns both, the
rule 7B's tests pinned.

**The search field matches keywords, not just titles**, and that is the difference between a useful search and
a harmful one. Somebody looking for dark mode types "dark", not "Appearance"; somebody wanting to change their
PIN types "PIN", not "Security". A tree that only matched headings would answer *no results* for a setting
sitting right there — worse than having no search at all.

**Every row carries a live count**, which is D's "the one number that matters": a branch that says *18 tags*
tells you whether it is worth opening before you open it. Two details in those counts:

- The account count **includes archived accounts**, unlike every picker in the app. This row is the way to
  reach an archived account and un-archive it, so a count that hid them would make the branch look emptier
  than the screen behind it — and an archived account nobody can find is one they recreate by hand.
- A count still loading renders as **no subtitle at all**, not `0`. A zero that really means "not yet known"
  is exactly the figure Law U4 exists to prevent.

The empty state is reachable only through search, so it names the search rather than the tree — *no settings*
would be false, and the user can see that it is.

### `lib/features/settings/providers/settings_providers.dart`

```dart
/// View-model state for the settings tree (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';

/// What the user has typed into the settings search field.
final settingsQueryProvider = NotifierProvider<SettingsQueryNotifier, String>(
  SettingsQueryNotifier.new,
);

/// Holds the settings search term.
class SettingsQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  /// Records [query].
  void set(String query) => state = query;
}

/// How many accounts exist, archived ones included.
///
/// **Archived included, unlike the pickers.** This row is the way to *reach* an archived account and
/// un-archive it, so a count that hid them would make the branch look emptier than the screen behind it —
/// and an archived account the user cannot find is one they will recreate by hand.
final settingsAccountCountProvider = StreamProvider<int>(
  (ref) => ref
      .watch(accountRepositoryProvider)
      .watchAllIncludingArchived()
      .map((accounts) => accounts.length),
);

/// How many payment methods exist.
final settingsPaymentMethodCountProvider = StreamProvider<int>(
  (ref) => ref.watch(paymentMethodRepositoryProvider).watchAll().map((rows) => rows.length),
);

/// How many payees exist.
final settingsPayeeCountProvider = StreamProvider<int>(
  (ref) => ref.watch(payeeRepositoryProvider).watchAll().map((rows) => rows.length),
);

/// How many tags exist.
final settingsTagCountProvider = StreamProvider<int>(
  (ref) => ref.watch(tagRepositoryProvider).watchAll().map((rows) => rows.length),
);

/// How many units exist.
final settingsUnitCountProvider = StreamProvider<int>(
  (ref) => ref.watch(unitRepositoryProvider).watchAll().map((rows) => rows.length),
);

/// How many currencies are enabled, and how many exist.
final settingsCurrencyCountProvider = StreamProvider<({int enabled, int total})>((ref) {
  final repository = ref.watch(currencyRepositoryProvider);
  return repository.watchAll().asyncMap((all) async {
    final enabled = await repository.watchEnabled().first;
    return (enabled: enabled.length, total: all.length);
  });
});
```

### `lib/features/settings/presentation/screens/settings_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/settings/providers/settings_providers.dart';
import 'package:alaya/shared/widgets/alaya_search_field.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// One row of the settings tree.
class _Entry {
  const _Entry({
    required this.title,
    required this.icon,
    required this.route,
    required this.keywords,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final String route;

  /// Extra words this row should match on.
  ///
  /// **Because the title is not what people search for.** Somebody looking for dark mode types "dark", not
  /// "Appearance"; somebody looking to change their PIN types "PIN", not "Security". A tree whose search
  /// only matched headings would be worse than no search at all, because it would answer "no results" to a
  /// setting that is right there.
  final List<String> keywords;
}

/// The settings tree (ARCH_5 §3 archetype D).
///
/// **Archetype D with two deviations.** There is no FAB, because nothing is added at the tree level — every
/// branch owns its own add action. And the grouping is by subject rather than by a user-chosen axis, because
/// a settings tree has no axis the user controls; the three groups are what the app is made of, in the order
/// somebody looks for them.
///
/// **The search field is pinned and real**, per D — catalogues are searched constantly, and a ten-branch
/// tree with sub-settings is exactly the case where scanning fails. It matches keywords as well as titles,
/// so "dark" finds Appearance and "PIN" finds Security.
///
/// Each row carries a live count, which is D's "the one number that matters": a branch that says *18 tags*
/// tells the user whether it is worth opening before they open it.
class SettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final query = ref.watch(settingsQueryProvider).trim().toLowerCase();
    final groups = _groups(context, ref, strings);

    final filtered = query.isEmpty
        ? groups
        : [
            for (final group in groups)
              (
                label: group.label,
                entries: [
                  for (final entry in group.entries)
                    if (entry.title.toLowerCase().contains(query) ||
                        entry.keywords.any((word) => word.contains(query)))
                      entry,
                ],
              ),
          ].where((group) => group.entries.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AlayaSpacing.screenEdge,
            AlayaSpacing.sm,
            AlayaSpacing.screenEdge,
            AlayaSpacing.xs,
          ),
          child: AlayaSearchField(
            hintText: strings.settingsSearchHint,
            clearLabel: strings.actionClear,
            onChanged: ref.read(settingsQueryProvider.notifier).set,
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              // Empty is reachable only through search, so it names the search rather than the tree — "no
              // settings" would be false, and the user can see it is.
              ? EmptyState(
                  title: strings.settingsNoMatchTitle,
                  body: strings.settingsNoMatchBody,
                  icon: Icons.search_off_outlined,
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final group = filtered[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            top: AlayaSpacing.lg,
                            bottom: AlayaSpacing.xs,
                          ),
                          child: SectionHeader(label: group.label),
                        ),
                        for (final entry in group.entries) _EntryTile(entry: entry),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  List<({String label, List<_Entry> entries})> _groups(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) {
    final accounts = ref.watch(settingsAccountCountProvider).valueOrNull;
    final methods = ref.watch(settingsPaymentMethodCountProvider).valueOrNull;
    final payees = ref.watch(settingsPayeeCountProvider).valueOrNull;
    final tags = ref.watch(settingsTagCountProvider).valueOrNull;
    final units = ref.watch(settingsUnitCountProvider).valueOrNull;
    final currencies = ref.watch(settingsCurrencyCountProvider).valueOrNull;

    return [
      (
        label: strings.settingsGroupMoney,
        entries: [
          _Entry(
            title: strings.settingsAccounts,
            // Null while the count is loading, so the row shows its title alone rather than "0 accounts"
            // — a zero that is really "not yet known" is the kind of figure Law U4 exists to prevent.
            subtitle: accounts == null ? null : strings.settingsAccountCount(accounts),
            icon: Icons.account_balance_wallet_outlined,
            route: Routes.settingsAccounts,
            keywords: const ['account', 'balance', 'bank', 'cash', 'wallet', 'net worth'],
          ),
          _Entry(
            title: strings.settingsPaymentMethods,
            subtitle: methods == null ? null : strings.settingsPaymentMethodCount(methods),
            icon: Icons.credit_card_outlined,
            route: Routes.settingsPaymentMethods,
            keywords: const ['payment', 'card', 'upi', 'method'],
          ),
          _Entry(
            title: strings.settingsPayees,
            subtitle: payees == null ? null : strings.settingsPayeeCount(payees),
            icon: Icons.storefront_outlined,
            route: Routes.settingsPayees,
            keywords: const ['payee', 'shop', 'merchant', 'who'],
          ),
        ],
      ),
      (
        label: strings.settingsGroupThings,
        entries: [
          _Entry(
            title: strings.settingsTags,
            subtitle: tags == null ? null : strings.settingsTagCount(tags),
            icon: Icons.sell_outlined,
            route: Routes.settingsTags,
            keywords: const ['tag', 'label', 'category', 'kitchen'],
          ),
          _Entry(
            title: strings.settingsUnits,
            subtitle: units == null ? null : strings.settingsUnitCount(units),
            icon: Icons.straighten_outlined,
            route: Routes.settingsUnits,
            keywords: const ['unit', 'kg', 'litre', 'measure', 'weight'],
          ),
          _Entry(
            title: strings.settingsCurrencies,
            subtitle: currencies == null
                ? null
                : strings.settingsCurrencyCount(currencies.enabled, currencies.total),
            icon: Icons.currency_exchange_outlined,
            route: Routes.settingsCurrencies,
            keywords: const ['currency', 'rate', 'exchange', 'home currency'],
          ),
        ],
      ),
      (
        label: strings.settingsGroupApp,
        entries: [
          _Entry(
            title: strings.settingsAppearance,
            icon: Icons.palette_outlined,
            route: Routes.settingsAppearance,
            keywords: const ['appearance', 'theme', 'dark', 'light', 'palette', 'colour', 'color'],
          ),
          _Entry(
            title: strings.settingsSecurity,
            icon: Icons.shield_outlined,
            route: Routes.settingsSecurity,
            keywords: const ['security', 'pin', 'lock', 'fingerprint', 'biometric', 'erase'],
          ),
          _Entry(
            title: strings.settingsData,
            icon: Icons.folder_outlined,
            route: Routes.settingsData,
            keywords: const ['data', 'backup', 'export', 'restore', 'trash'],
          ),
          _Entry(
            title: strings.settingsAbout,
            icon: Icons.info_outlined,
            route: Routes.settingsAbout,
            keywords: const ['about', 'version', 'licence', 'license', 'open source'],
          ),
        ],
      ),
    ];
  }
}

/// One tappable branch.
class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return ListTile(
      leading: Icon(entry.icon, size: AlayaIconSize.lg, color: semantic.muted),
      title: Text(entry.title, style: AlayaTypography.cardTitle),
      subtitle: entry.subtitle == null
          ? null
          : Text(
              entry.subtitle!,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
      trailing: Icon(Icons.chevron_right, size: AlayaIconSize.md, color: semantic.muted),
      onTap: () => context.push(entry.route),
    );
  }
}
```

## The money branches — providers, and Accounts

Denser from here, as flagged: the reasoning that is genuinely non-obvious stays in the doc comments, and the
prose between files stops repeating it.

Three decisions in this pair:

**No delete action on the accounts screen.** `AccountRepository.delete` exists, but an account is named by every
transaction that ever used it; archiving is what the schema is built for (ARCH_3 §4). Offering both side by side
would make the destructive one look like a tidier version of the safe one.

**Archived accounts get their own group rather than being hidden.** Every picker in the app hides them, which
makes this the only place one can be found and restored — and an account nobody can find is one they recreate by
hand, splitting a history that was meant to be one thing.

**The row shows the opening balance, not the live one.** This screen is about how an account is *configured*; a
current balance here would duplicate the figure the dashboard owns and explains.

### `lib/features/settings/providers/money_settings_providers.dart`

```dart
/// View-model state for the accounts, payment-method and payee branches (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/payment_method.dart';

/// Every account, archived ones included, so the branch can offer to un-archive.
final accountsSettingsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchAllIncludingArchived(),
);

/// Every payment method.
final paymentMethodsSettingsProvider = StreamProvider<List<PaymentMethod>>(
  (ref) => ref.watch(paymentMethodRepositoryProvider).watchAll(),
);

/// Every payee.
final payeesSettingsProvider = StreamProvider<List<Payee>>(
  (ref) => ref.watch(payeeRepositoryProvider).watchAll(),
);

/// The home currency, as the default for a new account.
///
/// A new account in a currency the user never uses is a row they will edit before their first transaction, so
/// the default is the one currency they have already chosen (Law L9's setting, used as a hint rather than a rule).
final accountsHomeCurrencyProvider = FutureProvider<String>(
  (ref) async =>
      await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ?? 'INR',
);

/// One account being edited, or null for a new one.
final accountDraftProvider =
    FutureProvider.autoDispose.family<Account?, String?>((ref, id) async {
  if (id == null) return null;
  return ref.watch(accountRepositoryProvider).byId(id);
});

/// Saves and archives accounts.
final accountEditorProvider =
    NotifierProvider<AccountEditorNotifier, AsyncValue<void>>(AccountEditorNotifier.new);

/// Writes an account, reporting the repository's own message on failure.
class AccountEditorNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Creates or replaces [account], returning whether it was written.
  Future<bool> save({
    required String? id,
    required String name,
    required AccountKind kind,
    required String currencyCode,
    required int openingMinor,
    required DateKey openingDate,
    required bool includeInNetWorth,
    required bool isArchived,
    required int sortOrder,
  }) async {
    state = const AsyncLoading<void>();
    final result = await ref.read(accountRepositoryProvider).save(
          Account(
            id: id ?? ref.read(uidGeneratorProvider).generate(),
            name: name.trim(),
            normalizedName: ref.read(normalizerProvider).normalize(name),
            kind: kind,
            currencyCode: currencyCode,
            openingBalance: Money(openingMinor, currencyCode),
            openingBalanceDateKey: openingDate,
            isArchived: isArchived,
            includeInNetWorth: includeInNetWorth,
            sortOrder: sortOrder,
          ),
        );
    if (result.isFailure) {
      state = AsyncError<void>(
        result.failureOrNull ?? StateError('save failed'),
        StackTrace.current,
      );
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }

  /// Archives or restores [id].
  ///
  /// **Archive, not delete.** ARCH_3 §4 keeps an archived account out of every picker while its history stays
  /// intact and its balance stays out of net worth if the user said so — deleting one would orphan every
  /// transaction that ever named it.
  Future<bool> setArchived({required String id, required bool isArchived}) async {
    state = const AsyncLoading<void>();
    final result = await ref
        .read(accountRepositoryProvider)
        .setArchived(id: id, isArchived: isArchived);
    if (result.isFailure) {
      state = AsyncError<void>(
        result.failureOrNull ?? StateError('archive failed'),
        StackTrace.current,
      );
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }
}

/// Saves a payment method.
final paymentMethodEditorProvider =
    NotifierProvider<PaymentMethodEditorNotifier, AsyncValue<void>>(
  PaymentMethodEditorNotifier.new,
);

/// Writes a payment method.
class PaymentMethodEditorNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Creates or replaces one, returning whether it was written.
  Future<bool> save({
    required String? id,
    required String name,
    required PaymentMethodKind kind,
    required int sortOrder,
    bool isSystem = false,
  }) async {
    state = const AsyncLoading<void>();
    final result = await ref.read(paymentMethodRepositoryProvider).save(
          PaymentMethod(
            id: id ?? ref.read(uidGeneratorProvider).generate(),
            name: name.trim(),
            kind: kind,
            isSystem: isSystem,
            sortOrder: sortOrder,
          ),
        );
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  /// Deletes [id].
  Future<bool> delete(String id) async {
    state = const AsyncLoading<void>();
    final result = await ref.read(paymentMethodRepositoryProvider).delete(id);
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  bool _settle(Object? failure) {
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }
}

/// Saves a payee.
final payeeEditorProvider =
    NotifierProvider<PayeeEditorNotifier, AsyncValue<void>>(PayeeEditorNotifier.new);

/// Writes a payee.
class PayeeEditorNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Creates or replaces one, returning whether it was written.
  Future<bool> save({
    required String? id,
    required String name,
    required PayeeKind kind,
    String? phone,
    String? note,
  }) async {
    state = const AsyncLoading<void>();
    final result = await ref.read(payeeRepositoryProvider).save(
          Payee(
            id: id ?? ref.read(uidGeneratorProvider).generate(),
            name: name.trim(),
            normalizedName: ref.read(normalizerProvider).normalize(name),
            kind: kind,
            phone: phone,
            note: note,
          ),
        );
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  /// Deletes [id].
  Future<bool> delete(String id) async {
    state = const AsyncLoading<void>();
    final result = await ref.read(payeeRepositoryProvider).delete(id);
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  bool _settle(Object? failure) {
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }
}
```

### `lib/features/settings/presentation/screens/accounts_settings_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/features/settings/providers/money_settings_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Settings › Accounts (ARCH_5 §3 archetype D, outside the shell).
///
/// **Outside the shell, so it brings its own `Scaffold` and gets a back arrow** — it is reached *from*
/// `/settings`, and `AppBar` resolves `hasDrawer` before `canPop`, so rendering it inside the shell would put
/// a hamburger where back belongs (Law U18).
///
/// **Archived accounts are listed, in their own group.** Every picker in the app hides them (ARCH_3 §4), which
/// makes this the only place one can be found and restored — and an account the user cannot find is one they
/// will recreate by hand, splitting a history that was meant to be one thing.
///
/// **No delete action anywhere on this screen.** `AccountRepository.delete` exists, but an account is named by
/// every transaction that ever used it; archiving is the answer the schema is built for, and offering both
/// side by side would make the destructive one look like a tidier version of the safe one.
class AccountsSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const AccountsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final accounts = ref.watch(accountsSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsAccounts)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.accountNew),
        tooltip: strings.accountsAdd,
        child: const Icon(Icons.add, size: AlayaIconSize.lg),
      ),
      body: accounts.when(
        // A skeleton, not a spinner: the shape of what is arriving beats a spinner in a space about to be a
        // list (ARCH_5 §5.2).
        loading: () => AlayaListSkeleton(label: strings.accountsLoading),
        // The repository's own message, never a generic body (Law U9).
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(accountsSettingsProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return EmptyState(
              title: strings.accountsEmptyTitle,
              body: strings.accountsEmptyBody,
              icon: Icons.account_balance_wallet_outlined,
              actionLabel: strings.accountsAdd,
              onAction: () => context.push(Routes.accountNew),
            );
          }
          final active = [for (final row in rows) if (!row.isArchived) row];
          final archived = [for (final row in rows) if (row.isArchived) row];
          return ListView(
            padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
            children: [
              for (final row in active) _AccountRow(account: row),
              if (archived.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(
                    top: AlayaSpacing.lg,
                    bottom: AlayaSpacing.xs,
                  ),
                  child: SectionHeader(label: strings.accountsArchivedHeader),
                ),
                for (final row in archived) _AccountRow(account: row),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// One account row: identity, its opening figure, and what is abnormal about it.
class _AccountRow extends ConsumerWidget {
  const _AccountRow({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return ListTile(
      leading: Icon(_icon(account.kind), size: AlayaIconSize.lg, color: semantic.muted),
      title: Text(account.name, style: AlayaTypography.cardTitle),
      subtitle: Text(
        _kindLabel(strings, account.kind),
        style: AlayaTypography.caption.copyWith(color: semantic.muted),
      ),
      // The opening balance, not the current one: this screen is about how the account is *configured*, and a
      // live balance here would be the same figure the dashboard owns, one tap from a screen that explains it.
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AmountText(account.openingBalance, size: AmountSize.small, showSign: false),
          if (account.isArchived || !account.includeInNetWorth) ...[
            const SizedBox(height: AlayaSpacing.xxs),
            StatusChip(
              label: account.isArchived
                  ? strings.accountsArchivedChip
                  : strings.accountsExcludedChip,
              tone: account.isArchived ? StatusTone.neutral : StatusTone.info,
            ),
          ],
        ],
      ),
      onTap: () => context.push(Routes.accountEdit(account.id)),
    );
  }

  IconData _icon(AccountKind kind) => switch (kind) {
        AccountKind.cash => Icons.payments_outlined,
        AccountKind.bank => Icons.account_balance_outlined,
        AccountKind.wallet => Icons.account_balance_wallet_outlined,
        AccountKind.card => Icons.credit_card_outlined,
        AccountKind.other => Icons.savings_outlined,
      };

  String _kindLabel(AlayaStrings strings, AccountKind kind) => switch (kind) {
        AccountKind.cash => strings.accountKindCash,
        AccountKind.bank => strings.accountKindBank,
        AccountKind.wallet => strings.accountKindWallet,
        AccountKind.card => strings.accountKindCard,
        AccountKind.other => strings.accountKindOther,
      };
}
```

## The account editor

**The opening balance and its date are one field pair, never one alone** (anomaly A03), with the same paragraph
onboarding uses. A balance with no date cannot be placed in a ledger, so every transaction before it would be
silently unaccounted for.

**Currency is editable only while the account is new.** Law L9 makes the *home* currency a display choice, but an
account's own currency is what its money **is** — changing it after transactions exist would reinterpret every one
of them. The chips stay visible and inert afterwards, with a line saying why, rather than disappearing.

**Archive is confirmed in both directions.** Archiving removes an account from every picker, which somebody
tidying a list will not have predicted; restoring puts it back into all of them, which is equally worth stating.

**Deleting is absent, and archiving is an `OutlinedButton` placed last** (§5.5) — never the filled one that saves.

The route can name an account that no longer exists — a stale deep link, or a row removed in another window — so
that renders as a stated absence rather than a blank form that would silently create a *second* account on save.

### `lib/features/settings/presentation/screens/account_editor_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/features/onboarding/providers/onboarding_providers.dart';
import 'package:alaya/features/settings/providers/money_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Creating or editing one account (ARCH_5 §3 archetype B).
///
/// **The opening balance and its date are one field pair, never one alone** (anomaly A03). A balance with no
/// date cannot be placed in a ledger, so every transaction before it would be silently unaccounted for — which
/// is why the date is required rather than defaulted and hidden.
///
/// **Archiving lives here, and deleting does not.** An account is named by every transaction that ever used it;
/// `AccountRepository.delete` exists for a mis-created row, but a screen that offers both makes the
/// irreversible one look like a tidier version of the safe one (ARCH_3 §4, ARCH_5 §5.5).
class AccountEditorScreen extends ConsumerStatefulWidget {
  /// Creates the editor. [accountId] null means a new account.
  const AccountEditorScreen({this.accountId, super.key});

  /// The account being edited, or null for a new one.
  final String? accountId;

  @override
  ConsumerState<AccountEditorScreen> createState() => _AccountEditorScreenState();
}

class _AccountEditorScreenState extends ConsumerState<AccountEditorScreen> {
  final _name = TextEditingController();
  AccountKind _kind = AccountKind.cash;
  String? _currency;
  int _openingMinor = 0;
  DateKey? _openingDate;
  bool _includeInNetWorth = true;
  bool _isArchived = false;
  int _sortOrder = 0;
  bool _dirty = false;
  bool _loaded = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Fills the form from [account] once, so a rebuild cannot overwrite what the user has typed.
  void _adopt(Account? account, String homeCurrency, DateKey today) {
    if (_loaded) return;
    _loaded = true;
    if (account == null) {
      _currency = homeCurrency;
      _openingDate = today;
      return;
    }
    _name.text = account.name;
    _kind = account.kind;
    _currency = account.currencyCode;
    _openingMinor = account.openingBalance.minor;
    _openingDate = account.openingBalanceDateKey;
    _includeInNetWorth = account.includeInNetWorth;
    _isArchived = account.isArchived;
    _sortOrder = account.sortOrder;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final draft = ref.watch(accountDraftProvider(widget.accountId));
    final editing = ref.watch(accountEditorProvider);
    final home = ref.watch(onboardingCurrenciesProvider).valueOrNull;
    final homeCode = ref.watch(accountsHomeCurrencyProvider).valueOrNull ?? 'INR';

    return draft.when(
      loading: () => Scaffold(
        appBar: AppBar(leading: const CloseButton(), title: Text(strings.accountEditorTitle)),
        body: Center(
          child: Text(
            strings.accountsLoading,
            style: AlayaTypography.body.copyWith(color: context.semantic.muted),
          ),
        ),
      ),
      error: (error, stack) => Scaffold(
        appBar: AppBar(leading: const CloseButton(), title: Text(strings.accountEditorTitle)),
        body: ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(accountDraftProvider(widget.accountId)),
        ),
      ),
      data: (account) {
        // Empty, in the one sense an editor has one: the route named an account that is not there — a stale
        // deep link, or a row removed in another window. It says so rather than rendering a blank form that
        // would silently create a second account on save.
        if (widget.accountId != null && account == null) {
          return Scaffold(
            appBar: AppBar(leading: const CloseButton(), title: Text(strings.accountEditorTitle)),
            body: ErrorState(
              title: strings.accountsMissingTitle,
              body: strings.accountsMissingBody,
              retryLabel: strings.actionBack,
              onRetry: () => context.pop(),
            ),
          );
        }
        _adopt(account, homeCode, ref.read(clockProvider).today());

        final currencies = home ?? const <Currency>[];
        final canSave = _name.text.trim().isNotEmpty && _currency != null && _openingDate != null;

        return Scaffold(
          appBar: AppBar(
            leading: const CloseButton(),
            title: Text(
              account == null ? strings.accountEditorTitle : strings.accountEditorEditTitle,
            ),
          ),
          body: AlayaFormScaffold(
            primaryLabel: strings.accountEditorSave,
            onPrimary: canSave && !editing.isLoading ? () => _save(account) : null,
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
                  autofocus: account == null,
                  decoration: InputDecoration(labelText: strings.accountNameLabel),
                  onChanged: (_) => setState(() => _dirty = true),
                ),
                const SizedBox(height: AlayaSpacing.md),
                SectionHeader(label: strings.accountKindHeader),
                const SizedBox(height: AlayaSpacing.xs),
                Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xs,
                  children: [
                    for (final kind in AccountKind.values)
                      ChoiceChip(
                        label: Text(_kindLabel(strings, kind), style: AlayaTypography.button),
                        selected: kind == _kind,
                        onSelected: (_) => setState(() {
                          _kind = kind;
                          _dirty = true;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: AlayaSpacing.md),
                SectionHeader(label: strings.accountCurrencyHeader),
                const SizedBox(height: AlayaSpacing.xxs),
                // Law L9 again, where it bites hardest: an account's currency is what its money *is*, not how
                // totals are displayed. Changing it after transactions exist would reinterpret every one of
                // them, so it is offered only while the account is new.
                Text(
                  account == null
                      ? strings.accountCurrencyNewHelp
                      : strings.accountCurrencyLockedHelp,
                  style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
                ),
                const SizedBox(height: AlayaSpacing.xs),
                Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xs,
                  children: [
                    for (final currency in currencies)
                      ChoiceChip(
                        label: Text(currency.code, style: AlayaTypography.button),
                        selected: currency.code == _currency,
                        onSelected: account == null
                            ? (_) => setState(() {
                                  _currency = currency.code;
                                  _dirty = true;
                                })
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: AlayaSpacing.md),
                if (_currency != null)
                  AmountField(
                    currencyCode: _currency!,
                    decimalDigits:
                        ref.watch(onboardingCurrencyDigitsProvider(_currency!)).valueOrNull ?? 2,
                    initialValue: Money(_openingMinor, _currency!),
                    label: strings.accountOpeningBalanceLabel,
                    allowNegative: true,
                    onChanged: (money) => setState(() {
                      _openingMinor = money?.minor ?? 0;
                      _dirty = true;
                    }),
                  ),
                const SizedBox(height: AlayaSpacing.md),
                if (_openingDate != null)
                  DatePickerField(
                    value: _openingDate,
                    label: strings.accountOpeningDateLabel,
                    // A formatter, not a formatted string: `formatted` is `String Function(DateKey)`, so it
                    // formats whichever date the picker lands on rather than the one that was there when
                    // this built.
                    formatted: (date) =>
                        DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag())
                            .format(date.toUtcMidnight()),
                    onChanged: (date) => setState(() {
                      _openingDate = date;
                      _dirty = true;
                    }),
                  ),
                const SizedBox(height: AlayaSpacing.xxs),
                Text(
                  strings.onboardingOpeningNote,
                  style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
                ),
                const SizedBox(height: AlayaSpacing.md),
                SwitchListTile(
                  value: _includeInNetWorth,
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.accountIncludeInNetWorth, style: AlayaTypography.body),
                  subtitle: Text(
                    strings.accountIncludeInNetWorthHelp,
                    style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
                  ),
                  onChanged: (value) => setState(() {
                    _includeInNetWorth = value;
                    _dirty = true;
                  }),
                ),
                if (account != null) ...[
                  const SizedBox(height: AlayaSpacing.xl),
                  // Last and quiet, per ARCH_5 §5.5 — and an `OutlinedButton`, never the filled one that saves.
                  OutlinedButton(
                    onPressed: editing.isLoading ? null : () => _toggleArchive(account),
                    child: Text(
                      _isArchived ? strings.accountsRestore : strings.accountsArchive,
                      style: AlayaTypography.button,
                    ),
                  ),
                  const SizedBox(height: AlayaSpacing.xxs),
                  Text(
                    strings.accountsArchiveHelp,
                    style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
                  ),
                ],
                if (editing.hasError) ...[
                  const SizedBox(height: AlayaSpacing.md),
                  Text(
                    editing.error.toString(),
                    style: AlayaTypography.body.copyWith(color: context.semantic.danger),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _save(Account? existing) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref.read(accountEditorProvider.notifier).save(
          id: existing?.id,
          name: _name.text,
          kind: _kind,
          currencyCode: _currency!,
          openingMinor: _openingMinor,
          openingDate: _openingDate!,
          includeInNetWorth: _includeInNetWorth,
          isArchived: _isArchived,
          sortOrder: _sortOrder,
        );
    if (!mounted || !saved) return;
    showResultSnack(context, message: strings.accountsSaved);
    context.pop();
  }

  Future<void> _toggleArchive(Account account) async {
    final strings = AlayaStrings.of(context);
    final next = !_isArchived;
    // Confirmed in both directions. Archiving removes an account from every picker, which a user who meant to
    // tidy a list will not have predicted; restoring puts it back into all of them, which is equally worth
    // stating before it happens.
    final confirmed = await ConfirmSheet.show(
      context,
      title: next ? strings.accountsArchiveConfirmTitle : strings.accountsRestoreConfirmTitle,
      body: next ? strings.accountsArchiveConfirmBody : strings.accountsRestoreConfirmBody,
      confirmLabel: next ? strings.accountsArchive : strings.accountsRestore,
      cancelLabel: strings.actionCancel,
      destructive: next,
    );
    if (!confirmed || !mounted) return;
    final ok = await ref
        .read(accountEditorProvider.notifier)
        .setArchived(id: account.id, isArchived: next);
    if (!mounted || !ok) return;
    setState(() => _isArchived = next);
    showResultSnack(
      context,
      message: next ? strings.accountsArchived : strings.accountsRestored,
    );
  }

  String _kindLabel(AlayaStrings strings, AccountKind kind) => switch (kind) {
        AccountKind.cash => strings.accountKindCash,
        AccountKind.bank => strings.accountKindBank,
        AccountKind.wallet => strings.accountKindWallet,
        AccountKind.card => strings.accountKindCard,
        AccountKind.other => strings.accountKindOther,
      };
}
```

---

## Scope of this part

Phase 8A is roughly 15,700 lines, so it is split in two. **The split is editorial, not functional** — both
parts must be applied together, because `app_router.dart` names all twelve 8A screens and will not compile
until every one exists, and `app_en.arb` is a single carried file that Part 2 owns.

**This part (30 files) holds the foundation, the lock, onboarding, and the tree:**

| | |
|---|---|
| `EraseService` | the one capability ARCH_3 §2.2 required that no phase had built |
| `AppLock`, `BiometricGate`, `DataTransferPort` | domain contracts, because `PinService` and `BackupService` are `final class` and cannot be faked |
| `PinService` | carried, now `implements AppLock` |
| `SettingsRepository.writeHomeCurrencyCode` | so no feature has to duplicate a `data/` key |
| `routes.dart`, `app_router.dart` | 21 routes, the onboarding gate, `refreshListenable`, and the `/lock/recovery` prefix fix |
| `app.dart` | both theme providers persisted — **closes ARCH_4 §5.1 item 23** |
| onboarding | archetype B, resumable, opening balances **and dates** |
| lock, PIN setup, recovery | archetype A's shape; every CRITICAL requirement |
| settings tree, accounts, account editor | archetype D and B |

**Part 2 (`PHASE_08A_PART2_SETTINGS_TREE.md`) owns:** tags with the `allowedIn*` matrix and one level of
nesting, units with the integer factor and its "make it a new item" escape, payment methods, payees,
currencies, appearance, security, data, about — plus `app_en.arb`, the widget tests, the
`layout_overflow_test.dart` additions and the COVERAGE table.

### Verified in this part

All nine CRITICAL requirements hold: the honest copy is on the lock screen and the onboarding security step,
there is no padlock glyph and no "bank-grade" claim anywhere, no PIN material reaches the database, the
forgot-both path offers an export before it demands `ERASE`, the `LockGate` reads the real service, GoRouter
has its `refreshListenable`, and the ten-failure auto-erase defaults off behind a confirmation.

Mechanically checked across all 30 files: every code block balanced, **no `features/` file imports `data/`**,
no `domain/` file imports `data/`, `flutter/` or `drift/`.

### §7.2 rows closed here

`accounts.includeInNetWorth` — the toggle carries a subtitle in both places it appears, because a switch
called "include in net worth" with nothing under it leaves the reader guessing whether off means hidden or
merely uncounted.

`accounts.openingBalance` / `openingBalanceDateKey` — captured as a pair in onboarding *and* the editor,
with the paragraph explaining why the date is not optional (anomaly A03).

`tags.parentTagId` and `tags.allowedIn*` are Part 2's, in `tags_settings`.

