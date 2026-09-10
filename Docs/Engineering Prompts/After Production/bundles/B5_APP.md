# B5_APP

Router, providers, theme, bootstrap. The router imports every screen.

**23 files · 18,303 lines.**  Written 2026-08-27T08:54:37-04:00.

Every file below is complete and current. Paths are destinations.

---

### `lib/app/app.dart`

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
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
import 'package:alaya/features/lock/providers/lock_providers.dart';
import 'package:alaya/features/onboarding/providers/onboarding_providers.dart';
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
final activePaletteProvider =
    NotifierProvider<ActivePaletteNotifier, AlayaPalette>(
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
    final stored = await ref
        .read(settingsRepositoryProvider)
        .readValue(AppearanceSettings.paletteKey);
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
      ref
          .read(settingsRepositoryProvider)
          .writeValue(
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
    final stored = await ref
        .read(settingsRepositoryProvider)
        .readValue(AppearanceSettings.themeModeKey);
    final restored = AppearanceSettings.parseThemeMode(stored);
    if (restored != state) state = restored;
  }

  /// Switches to [mode] and remembers it.
  void use(ThemeMode mode) {
    state = mode;
    unawaited(
      ref
          .read(settingsRepositoryProvider)
          .writeValue(
            key: AppearanceSettings.themeModeKey,
            value: AppearanceSettings.storedThemeMode(mode),
            valueType: 'string',
          ),
    );
  }
}

/// A `Listenable` that fires whenever the lock phase or the onboarding phase changes.
///
/// **Without this, both gates are decorative.** A go_router `redirect` runs on navigation and whenever its
/// `refreshListenable` fires, and nothing else — so unlocking would update the state and leave the user on the
/// lock screen looking at a correct boolean.
///
/// A `ValueNotifier` bridge rather than making either state a `ChangeNotifier`, because
/// `ChangeNotifierProvider` is legacy in the pinned Riverpod 3 (ARCH_1 §7) — and because a bridge driven by the
/// same providers widgets watch cannot drift out of step with them. It lives here rather than in the lock
/// feature because the router has **two** gates and a bridge listening to one would leave the other dead.
final routerRefreshProvider = Provider<Listenable>((ref) {
  final notifier = ValueNotifier<int>(0);
  ref.listen<LockPhase>(
    lockPhaseProvider,
    (previous, next) => notifier.value++,
  );
  ref.listen<OnboardingPhase>(
    onboardingPhaseProvider,
    (previous, next) => notifier.value++,
  );
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// The router, held in a provider so its lifetime matches the app's.
///
/// `GoRouter` owns navigation state, so rebuilding it would reset the stack. Constructing it inside
/// `build` is the standard way to lose a user's place on every theme change.
///
/// **The three arguments are the whole lock and onboarding mechanism.** `AppRouter.build()` defaults `isLocked`
/// to `() => false`, so calling it bare — which this did until the defect was found — leaves a correct
/// `PinService`, a correct `LockScreen` and a correct redirect that is simply never consulted. The symptom is a
/// PIN that Settings reports as set and that the app never asks for.
///
/// `ref.read` for the gates, not `ref.watch`: the redirect calls them on every navigation, so it needs the
/// current value rather than a rebuild of the router. `refreshListenable` is what makes them reactive.
final routerProvider = Provider<GoRouter>(
  (ref) => AppRouter.build(
    isLocked: () => ref.read(isLockedProvider),
    needsOnboarding: () => ref.read(needsOnboardingProvider),
    refreshListenable: ref.watch(routerRefreshProvider),
  ),
);

/// The root widget.
class AlayaApp extends ConsumerWidget {
  /// Creates the app.
  const AlayaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(activePaletteProvider);
    final mode = ref.watch(themeModeProvider);

    // **`AutoLockObserver` wraps the router's output, not the router itself.** Only a widget receives lifecycle
    // events, and without it the app locks on cold start and never again — sixty seconds in the background would
    // pass unnoticed, which is the case ARCH_3 §2.2 is actually about.
    return AutoLockObserver(
      child: MaterialApp.router(
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
      ),
    );
  }
}
```

### `lib/app/bootstrap.dart`

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/app.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/settings_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/connection/open_database.dart';
import 'package:alaya/data/reminders/daily_job.dart';
import 'package:alaya/data/repositories/settings_repository_impl.dart';
import 'package:alaya/data/security/app_lock_store.dart';
import 'package:alaya/data/security/pin_service.dart';
import 'package:alaya/data/security/secure_key_value_store.dart';
import 'package:alaya/features/lock/providers/lock_providers.dart';
import 'package:alaya/features/onboarding/providers/onboarding_providers.dart';
import 'package:alaya/features/onboarding/state/onboarding_state.dart';

/// Opens the database, builds the provider graph and runs the app.
///
/// The database is opened **here and only here**, through `openAlayaDatabase` — the single permitted
/// open path (Law L10). `databaseProvider` throws when un-overridden precisely so that a second open
/// site cannot appear quietly; the symptom of one would be a locked file rather than an error naming
/// the cause.
///
/// The database is plaintext (ARCH_1 §2.1). There is no key to derive, no passphrase to prompt for and
/// no unlock step before the connection opens.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // **ARCH_4 §5.1 item 25.** Everything from here to `runApp` can throw: a corrupt file, a migration that
  // fails, a device out of space, secure storage unavailable after a restore. Before Phase 9 a throw reached
  // nobody — `main` returned the future, so it surfaced in the log and the user saw a blank screen with no way
  // to tell a crash from a slow start.
  //
  // The alternative considered and rejected was a pre-`MaterialApp` failure screen, which item 25 calls out as
  // the worse option: it cannot use the theme, cannot use the ARB, and cannot offer an action.
  try {
    await _start();
  } on Object catch (error, stack) {
    // Deliberately not rethrown. Rethrowing here restores the blank screen this exists to prevent, and the
    // error is already on the console via `debugPrint` for anyone attached.
    debugPrint('Alaya failed to start: $error\n$stack');
    runApp(StartupFailureApp(error: error));
  }
}

/// The real startup path, separated so [bootstrap] can wrap all of it in one guard.
///
/// One `try` around the whole sequence rather than four, because the user-facing answer is the same whichever
/// step failed — the app cannot start — and a per-step message would leak a stack trace into a screen whose
/// entire purpose is to be readable.
Future<void> _start() async {
  final database = openAlayaDatabase();

  // **Phase 8B: the daily job is registered here, once, and nowhere else.**
  //
  // Two obligations depend on it and neither has any other trigger: ARCH_3 §7's daily recompute, so the digest
  // reflects what is actually coming, and §4.2's thirty-day retention, which is a promise the app does not keep
  // unless something enforces it. Both ports exposed the methods from the start; without this call the screens
  // all work and the trash simply never empties.
  //
  // Unawaited deliberately. `Workmanager().initialize` talks to a platform channel, and blocking `runApp` on it
  // would trade a visible first frame for a background schedule nobody is waiting on. `ExistingWorkPolicy.keep`
  // makes repeated registration a no-op, so a cold start that races this loses nothing.
  unawaited(registerDailyJob());

  // **One awaited read, and it removes a whole class of bug.** Whether a lock exists lives in secure storage,
  // which is asynchronous — so a `Notifier` resolving it a frame after the router first runs forces the redirect
  // to guess. Guessing "locked" showed a PIN screen to a fresh install that had none and no way past it; guessing
  // "open" would flash the dashboard, balances included, at somebody who does have one.
  //
  // A few milliseconds here means the router's first decision is already correct.
  // `PinService` requires a `Clock` — it owns ARCH_3 §2.3's throttle, which is arithmetic on stored instants
  // rather than a timer, so it cannot read the wall clock directly. `SystemClock` is what the provider graph
  // supplies too, so this startup instance and the app's agree.
  final lockConfigured = await PinService(
    store: AppLockStore(storage: const FlutterSecureKeyValueStore()),
    clock: const SystemClock(),
  ).isEnabled;

  // The same treatment for onboarding, and after the same bug: an async phase that resolved a frame late could
  // miss its own correction, because `GoRouter` may not have attached its `refreshListenable` yet. The visible
  // symptom was a first-run flow that appeared when the user opened Settings.
  final onboardingDone =
      await SettingsRepositoryImpl(
        SettingsDao(database),
        const SystemClock(),
      ).readValue(OnboardingKeys.done) ==
      'true';

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        lockConfiguredAtStartupProvider.overrideWithValue(lockConfigured),
        onboardingDoneAtStartupProvider.overrideWithValue(onboardingDone),
      ],
      child: const AlayaApp(),
    ),
  );

  // **Re-arm the digest, because a reboot silently disarms it.**
  //
  // `WorkManager` survives a restart; the `AlarmManager` alarm behind `zonedSchedule` does not. So between a
  // reboot and the daily job's next run — up to twenty-four hours, and longer while `requiresBatteryNotLow`
  // holds it back — there is no scheduled notification at all, and nothing in the app says so. The user's
  // report is "it worked, then it stopped", which is indistinguishable from every other cause of silence.
  //
  // Opening the app is the one event that reliably follows a reboot, so it is the one place a cheap re-arm
  // belongs. `rescheduleAll` is idempotent — the digest's Android id is a constant and its schedule row is
  // replaced by `refType` — so doing this on every launch costs one calendar query and can never duplicate.
  //
  // **After `runApp` and unawaited**, for the reason the job registration above is: this reads the calendar a
  // week ahead, and no first frame should wait on a notification nobody is looking at yet.
  //
  // This is a safety net rather than the fix. The correct primary is the plugin's own boot receiver declared in
  // `AndroidManifest.xml`, which re-arms without the app being opened at all — this covers the case where it is
  // absent, and the case where the user reboots and opens the app before Android gets round to the job.
  unawaited(
    buildReminderScheduler(
      database: database,
      clock: const SystemClock(),
      uids: const Uuid7Generator(),
    ).rescheduleAll(),
  );
}

/// What the user sees when the app cannot start at all.
///
/// **A real `MaterialApp`, deliberately.** It has no theme extension, no ARB and no provider scope — those all
/// depend on the startup that just failed — so every string here is a literal and that is the one place in this
/// project where Law U5 does not apply. A localised message would need the delegate that could not be loaded.
///
/// It offers no retry button. The failures that reach here are not transient: a corrupt database, a failed
/// migration, a full disk. A button that re-ran the same open and failed again would suggest the user was doing
/// something wrong. What it offers instead is the one thing that helps — telling them their data is still on the
/// device and that a reinstall will not be needed to recover it, which is true because the file is plaintext and
/// their backups are readable (ARCH_3 §3).
class StartupFailureApp extends StatelessWidget {
  /// Creates the failure screen for [error].
  const StartupFailureApp({required this.error, super.key});

  /// What went wrong. Shown, because a user reporting a fault needs something to quote.
  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Alaya could not start',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your data is still on this device. Nothing has been deleted, and any backup you '
                    'have made can still be opened.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'If this keeps happening, restart the phone. If it still fails, reinstalling will '
                    'clear the app — restore from a backup afterwards.',
                  ),
                  const SizedBox(height: 24),
                  // The raw error, monospaced and selectable, so it can be copied into a bug report. It is the
                  // only actionable thing on the screen for anyone able to act on it.
                  SelectableText(
                    '$error',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Builds a `ProviderScope` over [database] for tests and the Theme Lab.
///
/// Exposed so a widget test can supply `AlayaDatabase(NativeDatabase.memory())` without reaching for
/// `bootstrap`, which would open a real file.
ProviderScope scopeFor({
  required AlayaDatabase database,
  required Widget child,
  List<Override> extraOverrides = const [],
}) => ProviderScope(
  overrides: [databaseProvider.overrideWithValue(database), ...extraOverrides],
  child: child,
);
```

### `lib/app/l10n/generated/app_localizations.dart`

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AlayaStrings
/// returned by `AlayaStrings.of(context)`.
///
/// Applications need to include `AlayaStrings.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AlayaStrings.localizationsDelegates,
///   supportedLocales: AlayaStrings.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AlayaStrings.supportedLocales
/// property.
abstract class AlayaStrings {
  AlayaStrings(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AlayaStrings of(BuildContext context) {
    return Localizations.of<AlayaStrings>(context, AlayaStrings)!;
  }

  static const LocalizationsDelegate<AlayaStrings> delegate =
      _AlayaStringsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// The app's name, shown in the drawer header.
  ///
  /// In en, this message translates to:
  /// **'Alaya'**
  String get appName;

  /// No description provided for @navDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// No description provided for @navExpenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get navExpenses;

  /// No description provided for @navInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get navInventory;

  /// No description provided for @navShopping.
  ///
  /// In en, this message translates to:
  /// **'Shopping'**
  String get navShopping;

  /// No description provided for @navRecurring.
  ///
  /// In en, this message translates to:
  /// **'Recurring'**
  String get navRecurring;

  /// No description provided for @navServices.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get navServices;

  /// No description provided for @navCalendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get navCalendar;

  /// No description provided for @navInsights.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get navInsights;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navThemeLab.
  ///
  /// In en, this message translates to:
  /// **'Theme Lab'**
  String get navThemeLab;

  /// Commits an edit. Active voice, and the same word appears in the resulting confirmation.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get actionSaved;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @actionDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get actionDeleted;

  /// No description provided for @actionUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get actionUndo;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionRetry;

  /// No description provided for @actionAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get actionAdd;

  /// No description provided for @actionEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get actionEdit;

  /// No description provided for @actionDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @actionSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get actionSelect;

  /// No description provided for @actionClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get actionClear;

  /// No description provided for @actionClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get actionClearAll;

  /// No description provided for @actionSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get actionSearch;

  /// No description provided for @actionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get actionConfirm;

  /// No description provided for @actionDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get actionDiscard;

  /// No description provided for @actionKeepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get actionKeepEditing;

  /// Accessibility label for the dismiss affordance on a removable tag chip.
  ///
  /// In en, this message translates to:
  /// **'Remove tag'**
  String get actionRemoveTag;

  /// Accessibility label for the clear button inside AlayaSearchField.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get actionClearSearch;

  /// No description provided for @addExpense.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get addExpense;

  /// No description provided for @addIncome.
  ///
  /// In en, this message translates to:
  /// **'Add income'**
  String get addIncome;

  /// No description provided for @addTransfer.
  ///
  /// In en, this message translates to:
  /// **'Add transfer'**
  String get addTransfer;

  /// No description provided for @addItem.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get addItem;

  /// No description provided for @addToShoppingList.
  ///
  /// In en, this message translates to:
  /// **'Add to shopping list'**
  String get addToShoppingList;

  /// DateText.relative, when the date is the clock's today. Sentence case; it can begin a row.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get dateToday;

  /// No description provided for @dateYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get dateYesterday;

  /// No description provided for @dateTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get dateTomorrow;

  /// No description provided for @emptyTitleNoTransactions.
  ///
  /// In en, this message translates to:
  /// **'No transactions yet'**
  String get emptyTitleNoTransactions;

  /// An empty screen is an invitation to act, so this names the action rather than describing the emptiness.
  ///
  /// In en, this message translates to:
  /// **'Add your first expense and it will appear here.'**
  String get emptyBodyNoTransactions;

  /// No description provided for @emptyTitleNoItems.
  ///
  /// In en, this message translates to:
  /// **'Nothing in your inventory'**
  String get emptyTitleNoItems;

  /// No description provided for @emptyBodyNoItems.
  ///
  /// In en, this message translates to:
  /// **'Add an item to start tracking what you have at home.'**
  String get emptyBodyNoItems;

  /// No description provided for @emptyTitleNoShopping.
  ///
  /// In en, this message translates to:
  /// **'Your list is empty'**
  String get emptyTitleNoShopping;

  /// No description provided for @emptyBodyNoShopping.
  ///
  /// In en, this message translates to:
  /// **'Add something, or let Alaya suggest items you are low on.'**
  String get emptyBodyNoShopping;

  /// No description provided for @emptyTitleNoRecurring.
  ///
  /// In en, this message translates to:
  /// **'No recurring bills'**
  String get emptyTitleNoRecurring;

  /// No description provided for @emptyBodyNoRecurring.
  ///
  /// In en, this message translates to:
  /// **'Set up a bill or subscription and Alaya will remind you when it is due.'**
  String get emptyBodyNoRecurring;

  /// No description provided for @emptyTitleNoResults.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get emptyTitleNoResults;

  /// No description provided for @emptyBodyNoResults.
  ///
  /// In en, this message translates to:
  /// **'Try a shorter search, or check the spelling.'**
  String get emptyBodyNoResults;

  /// No description provided for @loadingLabel.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get loadingLabel;

  /// No description provided for @loadingTransactions.
  ///
  /// In en, this message translates to:
  /// **'Loading transactions'**
  String get loadingTransactions;

  /// Errors do not apologise and are never vague. This pairs with a specific body message.
  ///
  /// In en, this message translates to:
  /// **'That did not work'**
  String get errorTitleGeneric;

  /// No description provided for @errorBodyGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong on our side. Try again.'**
  String get errorBodyGeneric;

  /// No description provided for @errorTitleNotFound.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get errorTitleNotFound;

  /// No description provided for @errorBodyNotFound.
  ///
  /// In en, this message translates to:
  /// **'This item may have been deleted.'**
  String get errorBodyNotFound;

  /// No description provided for @errorBodyNoConnection.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Alaya works offline, but rates will not refresh.'**
  String get errorBodyNoConnection;

  /// No description provided for @errorFieldRequired.
  ///
  /// In en, this message translates to:
  /// **'This is required'**
  String get errorFieldRequired;

  /// No description provided for @errorAmountInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount'**
  String get errorAmountInvalid;

  /// No description provided for @errorAmountZero.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount greater than zero'**
  String get errorAmountZero;

  /// No description provided for @errorAmountInvalidCharacter.
  ///
  /// In en, this message translates to:
  /// **'Digits only'**
  String get errorAmountInvalidCharacter;

  /// No description provided for @errorAmountNegativeNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive amount'**
  String get errorAmountNegativeNotAllowed;

  /// No description provided for @errorAmountTooManyDecimals.
  ///
  /// In en, this message translates to:
  /// **'Too many decimal places'**
  String get errorAmountTooManyDecimals;

  /// No description provided for @errorAmountTooLarge.
  ///
  /// In en, this message translates to:
  /// **'That amount is too large'**
  String get errorAmountTooLarge;

  /// No description provided for @errorQuantityTooLarge.
  ///
  /// In en, this message translates to:
  /// **'That quantity is too large'**
  String get errorQuantityTooLarge;

  /// No description provided for @errorQuantityInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a quantity'**
  String get errorQuantityInvalid;

  /// No description provided for @errorQuantityInvalidCharacter.
  ///
  /// In en, this message translates to:
  /// **'Digits only'**
  String get errorQuantityInvalidCharacter;

  /// No description provided for @errorQuantityNegativeNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive quantity'**
  String get errorQuantityNegativeNotAllowed;

  /// The typed quantity is finer than the chosen unit can express exactly. Shown rather than rounded, because rounding a quantity silently changes what the user recorded.
  ///
  /// In en, this message translates to:
  /// **'Too precise for this unit'**
  String get errorQuantityTooPrecise;

  /// No description provided for @errorDateInvalid.
  ///
  /// In en, this message translates to:
  /// **'Choose a date'**
  String get errorDateInvalid;

  /// No description provided for @confirmDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this?'**
  String get confirmDeleteTitle;

  /// No description provided for @confirmDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'You can undo this for the next few seconds.'**
  String get confirmDeleteBody;

  /// No description provided for @confirmDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard your changes?'**
  String get confirmDiscardTitle;

  /// No description provided for @confirmDiscardBody.
  ///
  /// In en, this message translates to:
  /// **'What you have typed will not be saved.'**
  String get confirmDiscardBody;

  /// No description provided for @labelAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get labelAmount;

  /// No description provided for @labelQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get labelQuantity;

  /// No description provided for @labelUnit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get labelUnit;

  /// No description provided for @labelDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get labelDate;

  /// No description provided for @labelAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get labelAccount;

  /// No description provided for @labelPaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get labelPaymentMethod;

  /// No description provided for @labelPayee.
  ///
  /// In en, this message translates to:
  /// **'Payee'**
  String get labelPayee;

  /// No description provided for @labelCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get labelCategory;

  /// No description provided for @labelTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get labelTags;

  /// No description provided for @labelNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get labelNote;

  /// No description provided for @labelFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get labelFrom;

  /// No description provided for @labelTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get labelTo;

  /// No description provided for @labelItem.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get labelItem;

  /// No description provided for @labelExpiry.
  ///
  /// In en, this message translates to:
  /// **'Expiry'**
  String get labelExpiry;

  /// No description provided for @labelTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get labelTotal;

  /// No description provided for @hintSelectAccount.
  ///
  /// In en, this message translates to:
  /// **'Choose an account'**
  String get hintSelectAccount;

  /// No description provided for @hintSelectUnit.
  ///
  /// In en, this message translates to:
  /// **'Choose a unit'**
  String get hintSelectUnit;

  /// No description provided for @hintSelectTags.
  ///
  /// In en, this message translates to:
  /// **'Choose tags'**
  String get hintSelectTags;

  /// No description provided for @hintSelectDate.
  ///
  /// In en, this message translates to:
  /// **'Choose a date'**
  String get hintSelectDate;

  /// No description provided for @hintSearchItems.
  ///
  /// In en, this message translates to:
  /// **'Search items'**
  String get hintSearchItems;

  /// No description provided for @hintNote.
  ///
  /// In en, this message translates to:
  /// **'Add a note'**
  String get hintNote;

  /// The chip beside a total when some amounts had no exchange rate. Surfaced rather than hidden, because a total missing a row is otherwise indistinguishable from a complete one.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 amount not converted} other{{count} amounts not converted}}'**
  String amountUnconverted(int count);

  /// Shown when a conversion used the nearest earlier rate rather than the exact date's.
  ///
  /// In en, this message translates to:
  /// **'Approximate rate'**
  String get amountApproximate;

  /// Overflow indicator when a row cannot show every tag.
  ///
  /// In en, this message translates to:
  /// **'+{count}'**
  String tagCountMore(int count);

  /// StatusChip on a transaction saved by quick-add. Names what is missing, not that a flag is set.
  ///
  /// In en, this message translates to:
  /// **'Needs details'**
  String get statusNeedsReview;

  /// StatusChip label when a transaction's lines do not sum to its amount. The figure is a separate AmountText (U7); never auto-balanced (anomaly A11).
  ///
  /// In en, this message translates to:
  /// **'Unallocated'**
  String get statusUnallocated;

  /// StatusChip on a batch whose source transaction was deleted. The food did not un-exist.
  ///
  /// In en, this message translates to:
  /// **'Receipt deleted'**
  String get statusDetached;

  /// No description provided for @statusApproximate.
  ///
  /// In en, this message translates to:
  /// **'Approximate'**
  String get statusApproximate;

  /// No description provided for @lowStockLabel.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get lowStockLabel;

  /// No description provided for @expiringSoonLabel.
  ///
  /// In en, this message translates to:
  /// **'Expiring soon'**
  String get expiringSoonLabel;

  /// No description provided for @expiredLabel.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get expiredLabel;

  /// No description provided for @overdueLabel.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get overdueLabel;

  /// No description provided for @dueTodayLabel.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get dueTodayLabel;

  /// No description provided for @paidLabel.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paidLabel;

  /// No description provided for @skippedLabel.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get skippedLabel;

  /// No description provided for @kindDeposit.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get kindDeposit;

  /// No description provided for @kindWithdrawal.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get kindWithdrawal;

  /// No description provided for @kindTransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get kindTransfer;

  /// No description provided for @kindAdjustmentIncrease.
  ///
  /// In en, this message translates to:
  /// **'Stock added'**
  String get kindAdjustmentIncrease;

  /// No description provided for @kindAdjustmentDecrease.
  ///
  /// In en, this message translates to:
  /// **'Stock removed'**
  String get kindAdjustmentDecrease;

  /// No description provided for @subtypeGrocery.
  ///
  /// In en, this message translates to:
  /// **'Groceries'**
  String get subtypeGrocery;

  /// No description provided for @subtypeHousehold.
  ///
  /// In en, this message translates to:
  /// **'Household'**
  String get subtypeHousehold;

  /// No description provided for @subtypeElectronics.
  ///
  /// In en, this message translates to:
  /// **'Electronics'**
  String get subtypeElectronics;

  /// No description provided for @subtypeBill.
  ///
  /// In en, this message translates to:
  /// **'Bill'**
  String get subtypeBill;

  /// No description provided for @subtypeTransferSelf.
  ///
  /// In en, this message translates to:
  /// **'Between my accounts'**
  String get subtypeTransferSelf;

  /// No description provided for @subtypeTransferOut.
  ///
  /// In en, this message translates to:
  /// **'Sent to someone'**
  String get subtypeTransferOut;

  /// No description provided for @subtypeSalaryIn.
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get subtypeSalaryIn;

  /// No description provided for @subtypeOtherIn.
  ///
  /// In en, this message translates to:
  /// **'Other income'**
  String get subtypeOtherIn;

  /// No description provided for @subtypeOtherOut.
  ///
  /// In en, this message translates to:
  /// **'Other expense'**
  String get subtypeOtherOut;

  /// Surfaces transactions.needsReview. Quick-add saves an amount and nothing else by design; without this row that deliberate shortcut becomes silent data rot.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 transaction needs details} other{{count} transactions need details}}'**
  String needsReviewBanner(int count);

  /// No description provided for @needsReviewAction.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get needsReviewAction;

  /// No description provided for @filterTitle.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filterTitle;

  /// No description provided for @filterDateRange.
  ///
  /// In en, this message translates to:
  /// **'Date range'**
  String get filterDateRange;

  /// No description provided for @filterKind.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get filterKind;

  /// No description provided for @filterSubtype.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get filterSubtype;

  /// No description provided for @filterApply.
  ///
  /// In en, this message translates to:
  /// **'Show results'**
  String get filterApply;

  /// No description provided for @filterReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get filterReset;

  /// No description provided for @filterChipAccount.
  ///
  /// In en, this message translates to:
  /// **'Account: {name}'**
  String filterChipAccount(String name);

  /// No description provided for @filterChipPayee.
  ///
  /// In en, this message translates to:
  /// **'Payee: {name}'**
  String filterChipPayee(String name);

  /// No description provided for @filterChipRange.
  ///
  /// In en, this message translates to:
  /// **'{label}'**
  String filterChipRange(String label);

  /// No description provided for @rangeToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get rangeToday;

  /// No description provided for @rangeLast7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get rangeLast7Days;

  /// No description provided for @rangeLast30Days.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get rangeLast30Days;

  /// No description provided for @rangeThisMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get rangeThisMonth;

  /// No description provided for @rangeLastMonth.
  ///
  /// In en, this message translates to:
  /// **'Last month'**
  String get rangeLastMonth;

  /// No description provided for @rangeThisYear.
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get rangeThisYear;

  /// No description provided for @rangeAllTime.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get rangeAllTime;

  /// No description provided for @rangeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get rangeCustom;

  /// No description provided for @searchTransactionsHint.
  ///
  /// In en, this message translates to:
  /// **'Search notes'**
  String get searchTransactionsHint;

  /// No description provided for @transactionDeleted.
  ///
  /// In en, this message translates to:
  /// **'Transaction deleted'**
  String get transactionDeleted;

  /// No description provided for @quickAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick add'**
  String get quickAddTitle;

  /// No description provided for @quickAddMoneyIn.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get quickAddMoneyIn;

  /// No description provided for @quickAddMoneyOut.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get quickAddMoneyOut;

  /// No description provided for @quickAddSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get quickAddSave;

  /// Was "Add details", which implied composing. It saves first, then opens the editor — deliberately, because Alaya is offline-first and U11 says record it now and refine later, so an abandoned edit still leaves the expense captured. The label should say what the button does rather than leave the user to discover it.
  ///
  /// In en, this message translates to:
  /// **'Save and add details'**
  String get actionAddDetails;

  /// No description provided for @editorTitleNew.
  ///
  /// In en, this message translates to:
  /// **'New transaction'**
  String get editorTitleNew;

  /// No description provided for @editorTitleEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit transaction'**
  String get editorTitleEdit;

  /// No description provided for @sectionWhatAndHowMuch.
  ///
  /// In en, this message translates to:
  /// **'What and how much'**
  String get sectionWhatAndHowMuch;

  /// No description provided for @sectionWhereItCameFrom.
  ///
  /// In en, this message translates to:
  /// **'Where it came from'**
  String get sectionWhereItCameFrom;

  /// No description provided for @sectionWhereItWent.
  ///
  /// In en, this message translates to:
  /// **'Where it went'**
  String get sectionWhereItWent;

  /// No description provided for @sectionWhatYouBought.
  ///
  /// In en, this message translates to:
  /// **'What you bought'**
  String get sectionWhatYouBought;

  /// No description provided for @sectionWarranty.
  ///
  /// In en, this message translates to:
  /// **'Warranty'**
  String get sectionWarranty;

  /// No description provided for @sectionSchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get sectionSchedule;

  /// No description provided for @transferOwnAccount.
  ///
  /// In en, this message translates to:
  /// **'To my own account'**
  String get transferOwnAccount;

  /// No description provided for @transferSomeoneElse.
  ///
  /// In en, this message translates to:
  /// **'To someone else'**
  String get transferSomeoneElse;

  /// No description provided for @transferOwnAccountHelp.
  ///
  /// In en, this message translates to:
  /// **'Moves money between your accounts. Your total does not change.'**
  String get transferOwnAccountHelp;

  /// No description provided for @transferSomeoneElseHelp.
  ///
  /// In en, this message translates to:
  /// **'Money leaves your accounts, so it is recorded as an expense.'**
  String get transferSomeoneElseHelp;

  /// No description provided for @alsoAddToInventory.
  ///
  /// In en, this message translates to:
  /// **'Also add to inventory'**
  String get alsoAddToInventory;

  /// No artefact. Recorded as spending and nothing else.
  ///
  /// In en, this message translates to:
  /// **'Just an expense'**
  String get destinationNone;

  /// Creates stock. Names the Inventory module, matching navInventory.
  ///
  /// In en, this message translates to:
  /// **'Save to Inventory'**
  String get destinationInventory;

  /// Creates an asset. Names the Services module, matching navServices.
  ///
  /// In en, this message translates to:
  /// **'Save to Services'**
  String get destinationAsset;

  /// Hands off to the template builder. Matches navRecurring.
  ///
  /// In en, this message translates to:
  /// **'Save to Recurring'**
  String get destinationRecurring;

  /// No description provided for @lineAdd.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get lineAdd;

  /// No description provided for @lineDescription.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get lineDescription;

  /// No description provided for @lineUnitPrice.
  ///
  /// In en, this message translates to:
  /// **'Unit price'**
  String get lineUnitPrice;

  /// No description provided for @lineAmount.
  ///
  /// In en, this message translates to:
  /// **'Line total'**
  String get lineAmount;

  /// Surfaces transaction_lines.created*Id — the artefact this line produced, tappable through to it.
  ///
  /// In en, this message translates to:
  /// **'Created: {name}'**
  String lineCreatedLink(String name);

  /// No description provided for @payeeCreate.
  ///
  /// In en, this message translates to:
  /// **'New payee “{name}”'**
  String payeeCreate(String name);

  /// No description provided for @saveExpense.
  ///
  /// In en, this message translates to:
  /// **'Save expense'**
  String get saveExpense;

  /// No description provided for @saveIncome.
  ///
  /// In en, this message translates to:
  /// **'Save income'**
  String get saveIncome;

  /// No description provided for @saveTransfer.
  ///
  /// In en, this message translates to:
  /// **'Save transfer'**
  String get saveTransfer;

  /// No description provided for @detailSectionLines.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get detailSectionLines;

  /// No description provided for @detailSectionDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get detailSectionDetails;

  /// No description provided for @actionFreezeConversion.
  ///
  /// In en, this message translates to:
  /// **'Show in another currency'**
  String get actionFreezeConversion;

  /// Surfaces transactions.converted*/conversionRateRaw. A separate artefact that is never recomputed (Law L9).
  ///
  /// In en, this message translates to:
  /// **'Frozen on {date} at {rate}'**
  String frozenConversionNote(String date, String rate);

  /// No description provided for @deleteReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Why? (optional)'**
  String get deleteReasonHint;

  /// No description provided for @actionDeleteTransaction.
  ///
  /// In en, this message translates to:
  /// **'Delete transaction'**
  String get actionDeleteTransaction;

  /// No description provided for @labelSubtype.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get labelSubtype;

  /// No description provided for @labelKind.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get labelKind;

  /// No description provided for @themeLabTitle.
  ///
  /// In en, this message translates to:
  /// **'Theme Lab'**
  String get themeLabTitle;

  /// No description provided for @themeLabSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Every token, component and semantic colour, light and dark.'**
  String get themeLabSubtitle;

  /// No description provided for @themeLabSectionSpacing.
  ///
  /// In en, this message translates to:
  /// **'Spacing'**
  String get themeLabSectionSpacing;

  /// No description provided for @themeLabSectionRadii.
  ///
  /// In en, this message translates to:
  /// **'Radii'**
  String get themeLabSectionRadii;

  /// No description provided for @themeLabSectionTypography.
  ///
  /// In en, this message translates to:
  /// **'Typography'**
  String get themeLabSectionTypography;

  /// No description provided for @themeLabSectionElevation.
  ///
  /// In en, this message translates to:
  /// **'Elevation'**
  String get themeLabSectionElevation;

  /// No description provided for @themeLabSectionSemantic.
  ///
  /// In en, this message translates to:
  /// **'Semantic colours'**
  String get themeLabSectionSemantic;

  /// No description provided for @themeLabSectionSurfaces.
  ///
  /// In en, this message translates to:
  /// **'Surface tiers'**
  String get themeLabSectionSurfaces;

  /// No description provided for @themeLabSectionComponents.
  ///
  /// In en, this message translates to:
  /// **'Components'**
  String get themeLabSectionComponents;

  /// No description provided for @themeLabSectionPalettes.
  ///
  /// In en, this message translates to:
  /// **'Palettes'**
  String get themeLabSectionPalettes;

  /// No description provided for @themeLabLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLabLight;

  /// No description provided for @themeLabDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeLabDark;

  /// No description provided for @semanticIncome.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get semanticIncome;

  /// No description provided for @semanticExpense.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get semanticExpense;

  /// No description provided for @semanticTransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get semanticTransfer;

  /// No description provided for @semanticWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get semanticWarning;

  /// No description provided for @semanticDanger.
  ///
  /// In en, this message translates to:
  /// **'Danger'**
  String get semanticDanger;

  /// No description provided for @semanticSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get semanticSuccess;

  /// No description provided for @semanticMuted.
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get semanticMuted;

  /// No description provided for @drawerSectionMoney.
  ///
  /// In en, this message translates to:
  /// **'Money'**
  String get drawerSectionMoney;

  /// No description provided for @drawerSectionHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get drawerSectionHome;

  /// No description provided for @drawerSectionMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get drawerSectionMore;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Favourites'**
  String get inventoryGroupFavourites;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Everything else'**
  String get inventoryGroupUntagged;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get itemKindGeneric;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Food'**
  String get itemKindFood;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Medicine'**
  String get itemKindMedicine;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Beauty'**
  String get itemKindBeauty;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Household'**
  String get itemKindHousehold;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get itemKindOther;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Favourites only'**
  String get filterFavouritesOnly;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Add to favourites'**
  String get actionFavourite;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Remove from favourites'**
  String get actionUnfavourite;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get outOfStockLabel;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 batch} other{{count} batches}}'**
  String itemBatchCount(num count);

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Loading inventory'**
  String get loadingInventory;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Batches'**
  String get detailSectionBatches;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'From a purchase'**
  String get batchOriginPurchase;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Added by hand'**
  String get batchOriginManual;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get batchOriginImported;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'From an adjustment'**
  String get batchOriginAdjustment;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Purchased'**
  String get labelPurchased;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Stored in'**
  String get labelStorageLocation;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Unit cost'**
  String get labelUnitCost;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Bought'**
  String get labelInitial;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Nearest expiry'**
  String get labelNearestExpiry;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Shown in'**
  String get labelDisplayUnit;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get labelItemKind;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Low-stock level'**
  String get labelLowStockThreshold;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Warn before expiry'**
  String get labelExpiryNotifyDays;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Use some'**
  String get actionConsume;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Add a batch'**
  String get actionAddBatch;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Movement history'**
  String get actionViewHistory;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Delete item'**
  String get actionDeleteItem;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Delete this item?'**
  String get confirmDeleteItemTitle;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Its {count, plural, =1{1 batch} other{{count} batches}} go with it. The movement history stays, so what you already used is still recorded.'**
  String confirmDeleteItemBody(num count);

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Item deleted'**
  String get itemDeleted;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =0{Expires today} =1{Expires tomorrow} other{Expires in {days} days}}'**
  String expiresInDays(num days);

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{Expired yesterday} other{Expired {days} days ago}}'**
  String expiredDaysAgo(num days);

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'What it is'**
  String get sectionWhatItIs;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Stock rules'**
  String get sectionStockRules;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get unitCategoryWeight;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get unitCategoryVolume;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get unitCategoryCount;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Measured in {category}'**
  String unitCategoryLocked(Object category);

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'This cannot change. Every batch and movement already recorded is stored in this measure, and there is no conversion between weight, volume and count.'**
  String get unitCategoryLockedHelp;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Days of warning before a batch expires.'**
  String get expiryNotifyDaysHelp;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Favourite'**
  String get labelFavourite;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Save item'**
  String get saveItem;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'How much'**
  String get sectionHowMuch;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Batch details'**
  String get sectionBatchDetails;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Save batch'**
  String get saveBatch;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Batch saved'**
  String get batchSaved;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Freezer, pantry, bathroom shelf…'**
  String get hintStorageLocation;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Use stock'**
  String get consumeTitle;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get consumeKindConsume;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Thrown away'**
  String get consumeKindWaste;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get consumeKindExpired;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Recorded'**
  String get consumeRecorded;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Taking from'**
  String get consumeFromLabel;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Oldest expiry first.'**
  String get consumeFefoNote;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Takes all of 1 batch} other{Spans {count} batches, writing {count} movements}}'**
  String consumeSpansBatches(num count);

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'More than you have on hand'**
  String get consumeOverAvailable;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Movement history'**
  String get historyTitle;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Opening stock'**
  String get movementKindOpeningIn;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Bought'**
  String get movementKindPurchaseIn;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Added by hand'**
  String get movementKindManualIn;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get movementKindConsume;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Thrown away'**
  String get movementKindWaste;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get movementKindExpired;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Adjusted up'**
  String get movementKindAdjustIn;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Adjusted down'**
  String get movementKindAdjustOut;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Reversed'**
  String get movementReversed;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Reverses an earlier movement'**
  String get movementIsReversal;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Reverse'**
  String get actionReverse;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Reverse this movement?'**
  String get confirmReverseTitle;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'An opposite movement is appended. Nothing is erased — both entries stay in the history.'**
  String get confirmReverseBody;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Movement reversed'**
  String get movementReversedSnack;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Nothing recorded yet'**
  String get emptyTitleNoMovements;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Using, wasting or adjusting this batch will show up here.'**
  String get emptyBodyNoMovements;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Add a batch and it will appear here with its expiry.'**
  String get emptyBodyNoBatches;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'How much is left is worked out from the movement history. Use, waste or adjust the batch to change it.'**
  String get batchQuantityLockedHelp;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day} other{{days} days}}'**
  String daysCount(num days);

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Group favourites first'**
  String get groupByFavourites;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Record as used'**
  String get consumeCommitUsed;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Record as thrown away'**
  String get consumeCommitWaste;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Record as expired'**
  String get consumeCommitExpired;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Low · {count}'**
  String lowStockWithCount(Object count);

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Delete batch'**
  String get actionDeleteBatch;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Delete this batch?'**
  String get confirmDeleteBatchTitle;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'The stock it still holds disappears from your on-hand total. What you already used stays in the movement history.'**
  String get confirmDeleteBatchBody;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Batch deleted'**
  String get batchDeleted;

  /// Creates a catalogued item inline while itemising a receipt.
  ///
  /// In en, this message translates to:
  /// **'New item'**
  String get itemCreate;

  /// Shown in the line editor when the item catalogue is empty.
  ///
  /// In en, this message translates to:
  /// **'No items yet — create one so this line becomes stock.'**
  String get itemCreateHint;

  /// Prompt for unitCategory on inline creation; immutable after create (Law L8).
  ///
  /// In en, this message translates to:
  /// **'How is it measured? This cannot change later.'**
  String get itemCreateCategoryPrompt;

  /// Shown when an item with the same normalized name and unit category exists.
  ///
  /// In en, this message translates to:
  /// **'You already have this item, measured the same way. Open the one you have instead of adding a second.'**
  String get itemDuplicateBody;

  /// Shown when the chosen UnitCategory has no rows in units.
  ///
  /// In en, this message translates to:
  /// **'No units are set up for this measure yet. Pick a different measure, or add units in Settings first.'**
  String get itemUnitsMissingBody;

  /// Informational note, never a block: Law L8 makes same-name/different-category distinct items.
  ///
  /// In en, this message translates to:
  /// **'You also have this name under a different measure. That is fine — weight, volume and count never convert into each other.'**
  String get itemSimilarNote;

  /// Opens the existing item a duplicate collides with.
  ///
  /// In en, this message translates to:
  /// **'Open the one I have'**
  String get actionOpenExisting;

  /// Running total of estimated prices on a shopping list.
  ///
  /// In en, this message translates to:
  /// **'Estimated'**
  String get shoppingEstimate;

  /// Opens the list manager from the app bar.
  ///
  /// In en, this message translates to:
  /// **'Switch list'**
  String get shoppingSwitchList;

  /// Progress line above a shopping list.
  ///
  /// In en, this message translates to:
  /// **'{checked} of {total} ticked'**
  String shoppingCheckedCount(Object checked, Object total);

  /// Shopping list empty state.
  ///
  /// In en, this message translates to:
  /// **'Nothing on this list yet'**
  String get emptyTitleNoEntries;

  /// Shopping list empty state body.
  ///
  /// In en, this message translates to:
  /// **'Add what you need, or pull in suggestions from what is running low.'**
  String get emptyBodyNoEntries;

  /// Adds one entry to a shopping list.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addEntry;

  /// Header for entries with no tag.
  ///
  /// In en, this message translates to:
  /// **'Everything else'**
  String get shoppingGroupUntagged;

  /// Clears every tick on a shopping list.
  ///
  /// In en, this message translates to:
  /// **'Untick everything'**
  String get actionUncheckAll;

  /// Entry editor sheet title.
  ///
  /// In en, this message translates to:
  /// **'What do you need?'**
  String get entryEditorTitle;

  /// Free-text label for a shopping entry.
  ///
  /// In en, this message translates to:
  /// **'Name it'**
  String get entryFreeTextLabel;

  /// Hint showing that an entry need not be an inventory item.
  ///
  /// In en, this message translates to:
  /// **'Television, birthday card, light bulbs…'**
  String get entryFreeTextHint;

  /// Optional link from a shopping entry to a catalogued item.
  ///
  /// In en, this message translates to:
  /// **'Link to an item'**
  String get entryLinkItem;

  /// Dropdown option leaving itemId null.
  ///
  /// In en, this message translates to:
  /// **'Not in my inventory'**
  String get entryNoItem;

  /// Optional per-entry price estimate.
  ///
  /// In en, this message translates to:
  /// **'Estimated price'**
  String get labelEstimatedPrice;

  /// Rejection when neither freeText nor itemId is set.
  ///
  /// In en, this message translates to:
  /// **'Give it a name, or link it to an item'**
  String get entryNeedsSomething;

  /// Chip marking an auto-generated low-stock entry.
  ///
  /// In en, this message translates to:
  /// **'Suggested'**
  String get originAutoLowStock;

  /// Chip shown once an auto entry has been edited into a manual one.
  ///
  /// In en, this message translates to:
  /// **'Yours now'**
  String get originPromoted;

  /// Hides an auto suggestion until a later date.
  ///
  /// In en, this message translates to:
  /// **'Snooze a week'**
  String get actionSnooze;

  /// Dismisses an auto suggestion until stock recovers and drops again.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get actionDismiss;

  /// Precedes a DateText on a snoozed entry.
  ///
  /// In en, this message translates to:
  /// **'Snoozed until'**
  String get snoozedUntilLabel;

  /// Low-stock suggestion sheet title.
  ///
  /// In en, this message translates to:
  /// **'Running low'**
  String get generateTitle;

  /// Low-stock suggestion sheet body.
  ///
  /// In en, this message translates to:
  /// **'These are below the level you set. Add the ones you want.'**
  String get generateBody;

  /// Precedes a QtyText giving threshold minus stock on hand.
  ///
  /// In en, this message translates to:
  /// **'Short by'**
  String get generateShortBy;

  /// Re-runs low-stock generation.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get generateRefresh;

  /// Generate sheet empty state.
  ///
  /// In en, this message translates to:
  /// **'Nothing is running low'**
  String get generateEmptyTitle;

  /// Generate sheet empty state body.
  ///
  /// In en, this message translates to:
  /// **'Set a low-stock level on an item and it will show up here when it drops.'**
  String get generateEmptyBody;

  /// Result snack after regeneration.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 suggestion added} other{{count} suggestions added}}'**
  String generateAdded(num count);

  /// Convert-to-purchase screen title.
  ///
  /// In en, this message translates to:
  /// **'Turn into a purchase'**
  String get convertTitle;

  /// Explains the handoff to the expense editor.
  ///
  /// In en, this message translates to:
  /// **'Each ticked entry becomes one line, marked for inventory. You confirm the amount and account next.'**
  String get convertBody;

  /// Primary action; hands off to the 6A editor.
  ///
  /// In en, this message translates to:
  /// **'Open the expense'**
  String get convertConfirm;

  /// Convert screen empty state.
  ///
  /// In en, this message translates to:
  /// **'Nothing is ticked'**
  String get convertNothingTitle;

  /// Convert screen empty state body.
  ///
  /// In en, this message translates to:
  /// **'Tick what you actually bought, then come back.'**
  String get convertNothingBody;

  /// How many lines the draft will carry.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 line} other{{count} lines}}'**
  String convertLineCount(num count);

  /// List manager sheet title.
  ///
  /// In en, this message translates to:
  /// **'Your lists'**
  String get listManagerTitle;

  /// Field label when creating or renaming a list.
  ///
  /// In en, this message translates to:
  /// **'List name'**
  String get listNameLabel;

  /// Creates a shopping list.
  ///
  /// In en, this message translates to:
  /// **'New list'**
  String get listCreate;

  /// Renames a shopping list.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get listRename;

  /// Marks a list as the one that opens by default.
  ///
  /// In en, this message translates to:
  /// **'Make default'**
  String get listSetDefault;

  /// Chip on the default list.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get listDefaultBadge;

  /// Archives a shopping list.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get listArchive;

  /// Un-archives a shopping list.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get listUnarchive;

  /// Chip on an archived list.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get listArchivedBadge;

  /// Section header for archived lists.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get listArchivedSection;

  /// List manager empty state.
  ///
  /// In en, this message translates to:
  /// **'No lists yet'**
  String get emptyTitleNoLists;

  /// List manager empty state body.
  ///
  /// In en, this message translates to:
  /// **'Create one and it becomes your default.'**
  String get emptyBodyNoLists;

  /// Skeleton label for shopping surfaces.
  ///
  /// In en, this message translates to:
  /// **'Loading your list'**
  String get loadingShopping;

  /// Accepts a low-stock suggestion, promoting it to origin=manual so regeneration leaves it alone.
  ///
  /// In en, this message translates to:
  /// **'Add to my list'**
  String get actionAddToList;

  /// Chip on a dismissed suggestion; it stays listed so it can be accepted later.
  ///
  /// In en, this message translates to:
  /// **'Turned down'**
  String get suggestionDismissed;

  /// Title of the dedicated line-items page.
  ///
  /// In en, this message translates to:
  /// **'What you bought'**
  String get lineItemsTitle;

  /// Opens the line-items page from the transaction editor.
  ///
  /// In en, this message translates to:
  /// **'Add or edit items'**
  String get lineItemsManage;

  /// Adds one line from the line-items page.
  ///
  /// In en, this message translates to:
  /// **'Add an item'**
  String get lineItemsAdd;

  /// Commits the line and reopens the editor blank, so a receipt is entered without leaving the sheet.
  ///
  /// In en, this message translates to:
  /// **'Save & add another'**
  String get lineItemsSaveAndAnother;

  /// Running count on the line-items page.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No items yet} =1{1 item} other{{count} items}}'**
  String lineItemsCount(num count);

  /// Line-items page empty state.
  ///
  /// In en, this message translates to:
  /// **'Nothing itemised yet'**
  String get emptyTitleNoLineItems;

  /// Line-items page empty state body.
  ///
  /// In en, this message translates to:
  /// **'Add what was on the receipt. Anything you leave out still counts toward the total.'**
  String get emptyBodyNoLineItems;

  /// Removes one line from a transaction.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get actionRemove;

  /// Snack after removing a line.
  ///
  /// In en, this message translates to:
  /// **'Item removed'**
  String get lineRemoved;

  /// Precedes the summed line total on the line-items page.
  ///
  /// In en, this message translates to:
  /// **'Itemised'**
  String get lineItemsAllocated;

  /// Group header for outflow templates.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get recurringOutflow;

  /// Group header for inflow templates — salary reads as income, not a negative bill.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get recurringInflow;

  /// Precedes a DateText giving the next due date.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get recurringNextDue;

  /// Chip on an occurrence past its due date. Derived from the clock, never stored.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get recurringOverdue;

  /// Chip on a paused template.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get recurringPaused;

  /// Chip when the next occurrence falls today.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get recurringDueToday;

  /// Template list empty state.
  ///
  /// In en, this message translates to:
  /// **'Nothing recurring yet'**
  String get emptyTitleNoTemplates;

  /// Template list empty state body.
  ///
  /// In en, this message translates to:
  /// **'Add a bill, a subscription or a salary and it will appear here when it is next due.'**
  String get emptyBodyNoTemplates;

  /// Adds a recurring template.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addTemplate;

  /// Pauses a template.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get actionPause;

  /// Resumes a paused template.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get actionResume;

  /// Skeleton label for recurring surfaces.
  ///
  /// In en, this message translates to:
  /// **'Loading your schedule'**
  String get loadingRecurring;

  /// First section of the template builder.
  ///
  /// In en, this message translates to:
  /// **'What it is'**
  String get builderSectionWhat;

  /// Frequency section of the template builder.
  ///
  /// In en, this message translates to:
  /// **'How often'**
  String get builderSectionWhen;

  /// Amount and account section of the template builder.
  ///
  /// In en, this message translates to:
  /// **'Defaults'**
  String get builderSectionDefaults;

  /// Template name field.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get labelTemplateName;

  /// Bill, subscription, rent or salary.
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get labelRecurringKind;

  /// Whether money goes out or comes in.
  ///
  /// In en, this message translates to:
  /// **'Direction'**
  String get labelDirection;

  /// RecurringDirection.outflow.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get directionOutflow;

  /// RecurringDirection.inflow.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get directionInflow;

  /// RecurringKind.bill.
  ///
  /// In en, this message translates to:
  /// **'Bill'**
  String get kindBill;

  /// RecurringKind.subscription.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get kindSubscription;

  /// RecurringKind.rent.
  ///
  /// In en, this message translates to:
  /// **'Rent'**
  String get kindRent;

  /// RecurringKind.salary.
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get kindSalary;

  /// Precedes the interval count and unit.
  ///
  /// In en, this message translates to:
  /// **'Every'**
  String get labelEvery;

  /// RecurringIntervalUnit.day.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{day} other{days}}'**
  String unitDay(num count);

  /// RecurringIntervalUnit.week.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{week} other{weeks}}'**
  String unitWeek(num count);

  /// RecurringIntervalUnit.month.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{month} other{months}}'**
  String unitMonth(num count);

  /// RecurringIntervalUnit.year.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{year} other{years}}'**
  String unitYear(num count);

  /// anchorDayOfMonth. Stored once, clamped at render (anomaly A13).
  ///
  /// In en, this message translates to:
  /// **'On day of the month'**
  String get labelAnchorDay;

  /// Explains that the anchor never walks backwards.
  ///
  /// In en, this message translates to:
  /// **'Kept as you set it. Anchored on the 31st, a short month falls on its last day and the next long month returns to the 31st.'**
  String get anchorDayHelp;

  /// startDateKey.
  ///
  /// In en, this message translates to:
  /// **'Starts'**
  String get labelStartDate;

  /// endDateKey, optional.
  ///
  /// In en, this message translates to:
  /// **'Ends'**
  String get labelEndDate;

  /// defaultAmount — a default, not a fixed figure.
  ///
  /// In en, this message translates to:
  /// **'Usual amount'**
  String get labelDefaultAmount;

  /// remindDaysBefore.
  ///
  /// In en, this message translates to:
  /// **'Remind me'**
  String get labelRemindBefore;

  /// Commits the template.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveTemplate;

  /// Header of the frequency preview.
  ///
  /// In en, this message translates to:
  /// **'Next three'**
  String get previewTitle;

  /// Frequency preview with nothing to show.
  ///
  /// In en, this message translates to:
  /// **'Set a start date to see when this lands.'**
  String get previewEmpty;

  /// Marks a previewed date the anchor could not reach.
  ///
  /// In en, this message translates to:
  /// **'Shortened to fit the month'**
  String get previewClamped;

  /// Pay sheet title.
  ///
  /// In en, this message translates to:
  /// **'Record this payment'**
  String get payTitle;

  /// Pay sheet title for an inflow.
  ///
  /// In en, this message translates to:
  /// **'Record this receipt'**
  String get payTitleInflow;

  /// The real figure, which may differ from the default.
  ///
  /// In en, this message translates to:
  /// **'Amount actually paid'**
  String get labelActualAmount;

  /// Inflow wording for the same field.
  ///
  /// In en, this message translates to:
  /// **'Amount actually received'**
  String get labelActualAmountInflow;

  /// Precedes the default amount when the actual differs from it.
  ///
  /// In en, this message translates to:
  /// **'Usually'**
  String get payUsualWas;

  /// paidDateKey.
  ///
  /// In en, this message translates to:
  /// **'Paid on'**
  String get labelPaidOn;

  /// Commits the payment and creates the transaction.
  ///
  /// In en, this message translates to:
  /// **'Record it'**
  String get payCommit;

  /// Result snack after paying.
  ///
  /// In en, this message translates to:
  /// **'Recorded'**
  String get payRecorded;

  /// Rejection when no account is selected.
  ///
  /// In en, this message translates to:
  /// **'Choose which account it came from'**
  String get payNeedsAccount;

  /// Confirmation before undoing.
  ///
  /// In en, this message translates to:
  /// **'Undo this payment?'**
  String get payUndoTitle;

  /// Says exactly what undo reverses, in the order it happens (ARCH_5 §5.4).
  ///
  /// In en, this message translates to:
  /// **'The obligation goes back to due and the transaction it created is deleted. Anything that transaction produced — stock, an asset — goes with it.'**
  String get payUndoBody;

  /// Result snack after undoing.
  ///
  /// In en, this message translates to:
  /// **'Payment undone'**
  String get payUndone;

  /// Marks an occurrence deliberately skipped.
  ///
  /// In en, this message translates to:
  /// **'Skip this one'**
  String get actionSkip;

  /// Chip on a skipped occurrence, and the snack after skipping.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get occurrenceSkipped;

  /// Occurrence history screen title.
  ///
  /// In en, this message translates to:
  /// **'Payment history'**
  String get historyRecurringTitle;

  /// Badge when paidAmount != defaultAmount.
  ///
  /// In en, this message translates to:
  /// **'Differed from the usual amount'**
  String get historyDefaultVsActual;

  /// Occurrence history empty state.
  ///
  /// In en, this message translates to:
  /// **'Nothing due yet'**
  String get emptyTitleNoOccurrences;

  /// Empty state body, stating anomaly A14 plainly.
  ///
  /// In en, this message translates to:
  /// **'Occurrences appear as their due dates arrive. Nothing is ever paid for you.'**
  String get emptyBodyNoOccurrences;

  /// RecurringOccurrenceStatus.due.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get statusDue;

  /// RecurringOccurrenceStatus.paid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get statusPaid;

  /// RecurringOccurrenceStatus.dismissed.
  ///
  /// In en, this message translates to:
  /// **'Dismissed'**
  String get statusDismissed;

  /// RecurringKind.serviceFee — a recurring charge tied to an asset.
  ///
  /// In en, this message translates to:
  /// **'Service fee'**
  String get kindServiceFee;

  /// RecurringKind.other — anything the named kinds do not cover.
  ///
  /// In en, this message translates to:
  /// **'Something else'**
  String get kindOther;

  /// Header above the recurring bills a payment can settle.
  ///
  /// In en, this message translates to:
  /// **'Due now'**
  String get billDueSection;

  /// Opens the template builder from the bill form.
  ///
  /// In en, this message translates to:
  /// **'Set up a recurring bill'**
  String get billSetUpAction;

  /// Shown in the bill form when no occurrence is outstanding.
  ///
  /// In en, this message translates to:
  /// **'Nothing is due right now.'**
  String get billNothingDue;

  /// Snack after a line asked to become recurring.
  ///
  /// In en, this message translates to:
  /// **'Saved. Now set how often it repeats.'**
  String get recurringScheduleNext;

  /// Chip when the next occurrence has not materialised.
  ///
  /// In en, this message translates to:
  /// **'Not due yet'**
  String get recurringNotYetDue;

  /// Precedes the recurring bill this payment will settle.
  ///
  /// In en, this message translates to:
  /// **'Settling'**
  String get billSettlesLabel;

  /// Option that leaves the payment unlinked to any template.
  ///
  /// In en, this message translates to:
  /// **'Not a recurring bill'**
  String get billSettleNone;

  /// Explains that the editor is the single write path for a bill payment.
  ///
  /// In en, this message translates to:
  /// **'Pick one and the amount below becomes what you actually paid. Saving records it once.'**
  String get billSettleHelp;

  /// Helper under the amount when a bill is selected.
  ///
  /// In en, this message translates to:
  /// **'This amount is what gets recorded'**
  String get billAmountBecomesPaid;

  /// Precedes the account resolved automatically for a bill payment.
  ///
  /// In en, this message translates to:
  /// **'Paid from'**
  String get billAccountAuto;

  /// Shown only when no template default, no app default and more than one account exist.
  ///
  /// In en, this message translates to:
  /// **'Which account does this come from? Alaya remembers it on the bill.'**
  String get billAccountAskOnce;

  /// AssetType.appliance group header.
  ///
  /// In en, this message translates to:
  /// **'Appliances'**
  String get assetGroupAppliance;

  /// AssetType.electronics.
  ///
  /// In en, this message translates to:
  /// **'Electronics'**
  String get assetGroupElectronics;

  /// AssetType.vehicle.
  ///
  /// In en, this message translates to:
  /// **'Vehicles'**
  String get assetGroupVehicle;

  /// AssetType.furniture.
  ///
  /// In en, this message translates to:
  /// **'Furniture'**
  String get assetGroupFurniture;

  /// AssetType.property.
  ///
  /// In en, this message translates to:
  /// **'Property'**
  String get assetGroupProperty;

  /// AssetType.serviceProvider — a maid or gardener lives here, not in a second system.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get assetGroupServiceProvider;

  /// AssetType.subscription.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get assetGroupSubscription;

  /// AssetType.other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get assetGroupOther;

  /// Chip when warrantyEndDateKey is still ahead.
  ///
  /// In en, this message translates to:
  /// **'In warranty'**
  String get assetUnderWarranty;

  /// Chip when the warranty ends soon.
  ///
  /// In en, this message translates to:
  /// **'Warranty ending'**
  String get assetWarrantyEnding;

  /// Chip when the warranty has passed.
  ///
  /// In en, this message translates to:
  /// **'Out of warranty'**
  String get assetWarrantyExpired;

  /// Chip when nextServiceDueDateKey has passed.
  ///
  /// In en, this message translates to:
  /// **'Service due'**
  String get assetServiceDue;

  /// Chip when a service is close.
  ///
  /// In en, this message translates to:
  /// **'Service soon'**
  String get assetServiceSoon;

  /// Chip on a disposed asset.
  ///
  /// In en, this message translates to:
  /// **'Disposed'**
  String get assetDisposedChip;

  /// AssetStatus.underRepair.
  ///
  /// In en, this message translates to:
  /// **'Being repaired'**
  String get assetUnderRepair;

  /// Filter that brings disposed assets back into the list.
  ///
  /// In en, this message translates to:
  /// **'Include disposed'**
  String get filterShowDisposed;

  /// Asset list empty state.
  ///
  /// In en, this message translates to:
  /// **'Nothing tracked yet'**
  String get emptyTitleNoAssets;

  /// Asset list empty state body, stating the serviceProvider case plainly.
  ///
  /// In en, this message translates to:
  /// **'Add an appliance, a vehicle, or the person who helps around the house — they all live here.'**
  String get emptyBodyNoAssets;

  /// Adds an asset.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addAsset;

  /// Skeleton label for service surfaces.
  ///
  /// In en, this message translates to:
  /// **'Loading your things'**
  String get loadingAssets;

  /// Identity section on the detail screen.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get assetSectionIdentity;

  /// Warranty section.
  ///
  /// In en, this message translates to:
  /// **'Warranty'**
  String get assetSectionWarranty;

  /// Contact block.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get assetSectionContact;

  /// Service records section.
  ///
  /// In en, this message translates to:
  /// **'Service history'**
  String get assetSectionService;

  /// Service records section for a serviceProvider.
  ///
  /// In en, this message translates to:
  /// **'Salary history'**
  String get assetSectionSalary;

  /// Sum of every service record cost.
  ///
  /// In en, this message translates to:
  /// **'Spent on service so far'**
  String get assetLifetimeCost;

  /// The same figure for a serviceProvider.
  ///
  /// In en, this message translates to:
  /// **'Paid so far'**
  String get assetLifetimeSalary;

  /// assets.brand.
  ///
  /// In en, this message translates to:
  /// **'Brand'**
  String get labelBrand;

  /// assets.modelNo.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get labelModelNo;

  /// assets.serialNo.
  ///
  /// In en, this message translates to:
  /// **'Serial'**
  String get labelSerialNo;

  /// assets.purchasePrice.
  ///
  /// In en, this message translates to:
  /// **'Bought for'**
  String get labelPurchasePrice;

  /// assets.warrantyStartDateKey.
  ///
  /// In en, this message translates to:
  /// **'Warranty from'**
  String get labelWarrantyStart;

  /// assets.warrantyEndDateKey.
  ///
  /// In en, this message translates to:
  /// **'Warranty until'**
  String get labelWarrantyEnd;

  /// assets.warrantyProvider.
  ///
  /// In en, this message translates to:
  /// **'Covered by'**
  String get labelWarrantyProvider;

  /// assets.serviceIntervalDays.
  ///
  /// In en, this message translates to:
  /// **'Service every'**
  String get labelServiceInterval;

  /// assets.nextServiceDueDateKey.
  ///
  /// In en, this message translates to:
  /// **'Next service'**
  String get labelNextService;

  /// assets.primaryContactName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get labelContactName;

  /// assets.primaryContactPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get labelContactPhone;

  /// assets.location.
  ///
  /// In en, this message translates to:
  /// **'Kept in'**
  String get labelLocation;

  /// Dials primaryContactPhone.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get actionCall;

  /// Shown when the tel: intent finds no handler.
  ///
  /// In en, this message translates to:
  /// **'No app on this phone can place that call.'**
  String get callFailed;

  /// Adds a service record.
  ///
  /// In en, this message translates to:
  /// **'Record a service'**
  String get actionAddService;

  /// The same action for a serviceProvider.
  ///
  /// In en, this message translates to:
  /// **'Record a payment'**
  String get actionAddSalary;

  /// Opens the dispose sheet.
  ///
  /// In en, this message translates to:
  /// **'Dispose of it'**
  String get actionDispose;

  /// Reverses a disposal.
  ///
  /// In en, this message translates to:
  /// **'Bring it back'**
  String get actionUndispose;

  /// Chip when linkedRecurringTemplateId is set.
  ///
  /// In en, this message translates to:
  /// **'Paid on a schedule'**
  String get assetLinkedRecurring;

  /// Empty service history.
  ///
  /// In en, this message translates to:
  /// **'Nothing recorded against this yet.'**
  String get emptyBodyNoServices;

  /// assets.name.
  ///
  /// In en, this message translates to:
  /// **'What is it?'**
  String get labelAssetName;

  /// assets.type.
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get labelAssetType;

  /// Explains AssetType.serviceProvider when it is chosen.
  ///
  /// In en, this message translates to:
  /// **'A person you pay regularly belongs here too — their payments become service records.'**
  String get assetTypeHelpPerson;

  /// Commits an asset.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveAsset;

  /// Explains serviceIntervalDays.
  ///
  /// In en, this message translates to:
  /// **'Days between services. The next due date moves on each time you record one.'**
  String get serviceIntervalHelp;

  /// service_records.type.
  ///
  /// In en, this message translates to:
  /// **'What happened'**
  String get labelServiceType;

  /// ServiceRecordType.service.
  ///
  /// In en, this message translates to:
  /// **'Serviced'**
  String get serviceTypeService;

  /// ServiceRecordType.repair.
  ///
  /// In en, this message translates to:
  /// **'Repaired'**
  String get serviceTypeRepair;

  /// ServiceRecordType.maintenance.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get serviceTypeMaintenance;

  /// ServiceRecordType.inspection.
  ///
  /// In en, this message translates to:
  /// **'Inspection'**
  String get serviceTypeInspection;

  /// ServiceRecordType.salaryPaid — the maid case.
  ///
  /// In en, this message translates to:
  /// **'Salary paid'**
  String get serviceTypeSalaryPaid;

  /// ServiceRecordType.other.
  ///
  /// In en, this message translates to:
  /// **'Something else'**
  String get serviceTypeOther;

  /// service_records.providerName.
  ///
  /// In en, this message translates to:
  /// **'Who did it'**
  String get labelProviderName;

  /// service_records.providerPhone.
  ///
  /// In en, this message translates to:
  /// **'Their number'**
  String get labelProviderPhone;

  /// service_records.serviceDateKey.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get labelServiceDate;

  /// service_records.cost.
  ///
  /// In en, this message translates to:
  /// **'Cost'**
  String get labelServiceCost;

  /// service_records.nextDueDateKey.
  ///
  /// In en, this message translates to:
  /// **'Next one due'**
  String get labelNextDue;

  /// The alsoRecordAsExpense toggle.
  ///
  /// In en, this message translates to:
  /// **'Also record it as an expense'**
  String get alsoRecordAsExpense;

  /// Explains what the toggle writes.
  ///
  /// In en, this message translates to:
  /// **'Records an expense for the cost too, so it shows in your ledger.'**
  String get alsoRecordHelp;

  /// Rejection when the toggle is on with no account.
  ///
  /// In en, this message translates to:
  /// **'Choose which account it comes from'**
  String get alsoRecordNeedsAccount;

  /// Rejection when the toggle is on with no cost.
  ///
  /// In en, this message translates to:
  /// **'Add a cost first'**
  String get alsoRecordNeedsCost;

  /// Commits a service record.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveService;

  /// Dispose sheet title.
  ///
  /// In en, this message translates to:
  /// **'What happened to it?'**
  String get disposeTitle;

  /// States anomaly A30 plainly: an asset is never deleted.
  ///
  /// In en, this message translates to:
  /// **'It stays in your records either way — what you spent on it still counts. This just stops it appearing as something you own.'**
  String get disposeBody;

  /// AssetDisposalReason.sold.
  ///
  /// In en, this message translates to:
  /// **'Sold it'**
  String get disposeReasonSold;

  /// AssetDisposalReason.expired.
  ///
  /// In en, this message translates to:
  /// **'Wore out'**
  String get disposeReasonExpired;

  /// AssetDisposalReason.damaged.
  ///
  /// In en, this message translates to:
  /// **'Broke'**
  String get disposeReasonDamaged;

  /// AssetDisposalReason.gifted.
  ///
  /// In en, this message translates to:
  /// **'Gave it away'**
  String get disposeReasonGifted;

  /// AssetDisposalReason.lost.
  ///
  /// In en, this message translates to:
  /// **'Lost it'**
  String get disposeReasonLost;

  /// AssetDisposalReason.replaced.
  ///
  /// In en, this message translates to:
  /// **'Replaced it'**
  String get disposeReasonReplaced;

  /// AssetDisposalReason.other.
  ///
  /// In en, this message translates to:
  /// **'Something else'**
  String get disposeReasonOther;

  /// assets.disposalAmount — what the disposal recovered.
  ///
  /// In en, this message translates to:
  /// **'Got back'**
  String get labelDisposalAmount;

  /// assets.disposedAtDateKey.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get labelDisposalDate;

  /// Commits the disposal.
  ///
  /// In en, this message translates to:
  /// **'Record it'**
  String get disposeCommit;

  /// Snack after disposing.
  ///
  /// In en, this message translates to:
  /// **'Recorded'**
  String get disposeDone;

  /// Snack after un-disposing.
  ///
  /// In en, this message translates to:
  /// **'Back in your list'**
  String get undisposeDone;

  /// Rejection when no reason is chosen.
  ///
  /// In en, this message translates to:
  /// **'Pick what happened'**
  String get disposeNeedsReason;

  /// Search hint on the asset list.
  ///
  /// In en, this message translates to:
  /// **'Search your things and people'**
  String get hintSearchAssets;

  /// Field error when warrantyEndDateKey precedes warrantyStartDateKey.
  ///
  /// In en, this message translates to:
  /// **'The warranty cannot end before it starts'**
  String get errorWarrantyBackwards;

  /// Header above the cost and expense controls on the service editor.
  ///
  /// In en, this message translates to:
  /// **'Money'**
  String get sectionMoney;

  /// Snack after a purchase line created an asset.
  ///
  /// In en, this message translates to:
  /// **'Saved. Now say what it is and how long it is covered.'**
  String get assetCreatedFromPurchase;

  /// Explains destination none.
  ///
  /// In en, this message translates to:
  /// **'Recorded as an expense and nothing else.'**
  String get destinationHelpNone;

  /// Explains destination inventory.
  ///
  /// In en, this message translates to:
  /// **'Groceries, refills, anything measured and consumed. Needs an item and a quantity, and creates stock you can run down.'**
  String get destinationHelpInventory;

  /// Explains destination asset.
  ///
  /// In en, this message translates to:
  /// **'A phone, a fridge, a chair. Creates something you own, with its own warranty and service history.'**
  String get destinationHelpAsset;

  /// Explains destination recurring.
  ///
  /// In en, this message translates to:
  /// **'Sets up a schedule so this comes back every month.'**
  String get destinationHelpRecurring;

  /// Informational note when an asset name repeats. Never a block: five iPhones are five assets.
  ///
  /// In en, this message translates to:
  /// **'You already have one called this. That is fine — this will be a separate one, with its own warranty and service history.'**
  String get assetSameNameNote;

  /// Snack action opening the asset a purchase line created.
  ///
  /// In en, this message translates to:
  /// **'Set the warranty'**
  String get actionSetWarranty;

  /// Optional payment method on the service editor. Travels to the expense, never onto the record.
  ///
  /// In en, this message translates to:
  /// **'How you paid (optional)'**
  String get labelPaymentMethodOptional;

  /// Dashboard screen title.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get dashboardTitle;

  /// Label above the one headline figure on the dashboard.
  ///
  /// In en, this message translates to:
  /// **'Total available funds'**
  String get fundsAvailable;

  /// Chip when BalanceService could not convert some accounts. Excluded from the headline, never summed (anomaly A34).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 balance not converted} other{{count} balances not converted}}'**
  String fundsUnconverted(num count);

  /// Chip when the conversion used the most recent rate on or before today.
  ///
  /// In en, this message translates to:
  /// **'Rate is older than today'**
  String get fundsApproximate;

  /// Explains why the headline may be lower than the sum of every account.
  ///
  /// In en, this message translates to:
  /// **'Balances Alaya has no rate for are left out rather than guessed at.'**
  String get fundsWhyExcluded;

  /// Range label. Always stated, never implied (anomaly A33).
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get rangeLast30;

  /// Deposits over the labelled range.
  ///
  /// In en, this message translates to:
  /// **'In'**
  String get rangeMoneyIn;

  /// Withdrawals over the labelled range.
  ///
  /// In en, this message translates to:
  /// **'Out'**
  String get rangeMoneyOut;

  /// Shown in place of a figure when a range holds no transactions.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet'**
  String get rangeNothingYet;

  /// Chip when transactions in a foreign currency could not be converted into the range total.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 left out} other{{count} left out}}'**
  String rangeExcluded(num count);

  /// The calendar side of the switchable insight card.
  ///
  /// In en, this message translates to:
  /// **'Coming up'**
  String get insightUpcoming;

  /// The analytics side of the switchable insight card.
  ///
  /// In en, this message translates to:
  /// **'Where it went'**
  String get insightSpending;

  /// Semantics label for the insight card switch.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get insightSwitchLabel;

  /// Empty state for the upcoming side.
  ///
  /// In en, this message translates to:
  /// **'Nothing needs attention in the next fortnight.'**
  String get insightNothingUpcoming;

  /// Upcoming row for a recurring occurrence.
  ///
  /// In en, this message translates to:
  /// **'Bill due'**
  String get insightBillDue;

  /// Upcoming row for an asset needing service.
  ///
  /// In en, this message translates to:
  /// **'Service due'**
  String get insightServiceDue;

  /// Upcoming row for an expiring warranty.
  ///
  /// In en, this message translates to:
  /// **'Warranty ending'**
  String get insightWarrantyEnding;

  /// Upcoming row for a batch past or near its expiry.
  ///
  /// In en, this message translates to:
  /// **'Expiring'**
  String get insightBatchExpiring;

  /// Header above the navigation tiles.
  ///
  /// In en, this message translates to:
  /// **'Where to next'**
  String get moduleGridTitle;

  /// Live number on the Expenses tile.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{none this month} =1{1 this month} other{{count} this month}}'**
  String moduleExpenses(num count);

  /// Live number on the Inventory tile.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{nothing tracked} =1{1 running low} other{{count} running low}}'**
  String moduleInventory(num count);

  /// Live number on the Shopping tile.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{list is clear} =1{1 to buy} other{{count} to buy}}'**
  String moduleShopping(num count);

  /// Live number on the Recurring tile.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{all settled} =1{1 due} other{{count} due}}'**
  String moduleRecurring(num count);

  /// Live number on the Services tile.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{nothing needs doing} =1{1 needs attention} other{{count} need attention}}'**
  String moduleServices(num count);

  /// FAB action opening the editor as a deposit.
  ///
  /// In en, this message translates to:
  /// **'Add income'**
  String get fabAddIncome;

  /// FAB action opening the item editor.
  ///
  /// In en, this message translates to:
  /// **'New item'**
  String get fabAddItem;

  /// Skeleton label for the dashboard.
  ///
  /// In en, this message translates to:
  /// **'Adding it up'**
  String get loadingDashboard;

  /// Semantics label for the closed expandable FAB.
  ///
  /// In en, this message translates to:
  /// **'Add something'**
  String get fabOpenLabel;

  /// Semantics label for the open expandable FAB.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get fabCloseLabel;

  /// No description provided for @eventTypeTransaction.
  ///
  /// In en, this message translates to:
  /// **'Transaction'**
  String get eventTypeTransaction;

  /// No description provided for @eventTypeRecurringDue.
  ///
  /// In en, this message translates to:
  /// **'Recurring bill'**
  String get eventTypeRecurringDue;

  /// No description provided for @eventTypeBatchExpiry.
  ///
  /// In en, this message translates to:
  /// **'Expiring'**
  String get eventTypeBatchExpiry;

  /// No description provided for @eventTypeWarrantyEnd.
  ///
  /// In en, this message translates to:
  /// **'Warranty ending'**
  String get eventTypeWarrantyEnd;

  /// No description provided for @eventTypeServiceDue.
  ///
  /// In en, this message translates to:
  /// **'Service due'**
  String get eventTypeServiceDue;

  /// No description provided for @eventTypeShoppingTarget.
  ///
  /// In en, this message translates to:
  /// **'Shopping target'**
  String get eventTypeShoppingTarget;

  /// No description provided for @calendarSeverityWarning.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get calendarSeverityWarning;

  /// No description provided for @calendarSeverityDanger.
  ///
  /// In en, this message translates to:
  /// **'Past its date'**
  String get calendarSeverityDanger;

  /// No description provided for @calendarLoadingDay.
  ///
  /// In en, this message translates to:
  /// **'Loading this day…'**
  String get calendarLoadingDay;

  /// No description provided for @calendarDayErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load this day'**
  String get calendarDayErrorTitle;

  /// No description provided for @calendarDayEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing on this day'**
  String get calendarDayEmptyTitle;

  /// No description provided for @calendarDayEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'No transactions, bills, expiries or services fall here.'**
  String get calendarDayEmptyBody;

  /// No description provided for @calendarRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get calendarRetry;

  /// No description provided for @calendarLoadingMonth.
  ///
  /// In en, this message translates to:
  /// **'Loading this month…'**
  String get calendarLoadingMonth;

  /// No description provided for @calendarErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load the calendar'**
  String get calendarErrorTitle;

  /// No description provided for @calendarPreviousMonth.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get calendarPreviousMonth;

  /// No description provided for @calendarNextMonth.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get calendarNextMonth;

  /// No description provided for @calendarOnDay.
  ///
  /// In en, this message translates to:
  /// **'On this day'**
  String get calendarOnDay;

  /// No description provided for @calendarRangeOn.
  ///
  /// In en, this message translates to:
  /// **'Select a range'**
  String get calendarRangeOn;

  /// No description provided for @calendarRangeOff.
  ///
  /// In en, this message translates to:
  /// **'Stop selecting a range'**
  String get calendarRangeOff;

  /// Prompt after the range start is chosen.
  ///
  /// In en, this message translates to:
  /// **'From {start} — tap another day to finish.'**
  String calendarRangePickEnd(String start);

  /// How many days the chosen range spans.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String calendarInRange(int count);

  /// No description provided for @calendarRangeEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing in these days'**
  String get calendarRangeEmptyTitle;

  /// No description provided for @calendarRangeEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'No transactions, bills, expiries or services fall inside the range.'**
  String get calendarRangeEmptyBody;

  /// No description provided for @calendarBackToToday.
  ///
  /// In en, this message translates to:
  /// **'Back to this month'**
  String get calendarBackToToday;

  /// No description provided for @calendarTotalOut.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get calendarTotalOut;

  /// No description provided for @calendarTotalIn.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get calendarTotalIn;

  /// No description provided for @dashboardOpenCalendar.
  ///
  /// In en, this message translates to:
  /// **'Open calendar'**
  String get dashboardOpenCalendar;

  /// Screen-reader label for the dashboard month card where days are too narrow to tap.
  ///
  /// In en, this message translates to:
  /// **'{month} at a glance. Opens the calendar.'**
  String dashboardCalendarSemantics(String month);

  /// No description provided for @navBackToDashboard.
  ///
  /// In en, this message translates to:
  /// **'Back to dashboard'**
  String get navBackToDashboard;

  /// Shown in a ChartCard while its figure computes. A line rather than a spinner: a card about to hold a chart reads as slow behind one (ARCH_5 §5.2).
  ///
  /// In en, this message translates to:
  /// **'Working it out…'**
  String get chartLoading;

  /// How many of a series' data points converted against a rate from a different day (ARCH_3 §1.3). Says what it means rather than naming the rate quality.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 figure is indicative} other{{count} figures are indicative}}'**
  String chartApproximate(num count);

  /// How many amounts had no usable rate and are excluded from the figure, never counted as zero (anomaly A15).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 amount left out} other{{count} amounts left out}}'**
  String chartUnconverted(num count);

  /// Label above the analytics screen's one displayAmount.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get analyticsTotalSpent;

  /// Semantics label for the range chip row.
  ///
  /// In en, this message translates to:
  /// **'Reporting window'**
  String get analyticsRangeLabel;

  /// Period-over-period comparison, rising. The window compared against is the same length, not a calendar month.
  ///
  /// In en, this message translates to:
  /// **'{percent} more than the window before'**
  String analyticsComparisonUp(Object percent);

  /// Period-over-period comparison, falling.
  ///
  /// In en, this message translates to:
  /// **'{percent} less than the window before'**
  String analyticsComparisonDown(Object percent);

  /// The app-wide unconverted count, distinct from one figure's own exclusions. A transaction outside the window can still be unconvertible.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 amount needs a rate} other{{count} amounts need a rate}}'**
  String analyticsUnconvertedTotal(num count);

  /// Title of the personal-inflation card, queries 12 and 24.
  ///
  /// In en, this message translates to:
  /// **'Your own inflation'**
  String get analyticsInflationTitle;

  /// Explains that the trend is per base unit, so 2 kg and 500 g are comparable.
  ///
  /// In en, this message translates to:
  /// **'What one thing costs you, purchase by purchase'**
  String get analyticsInflationSubtitle;

  /// The personal-inflation sentence, rising. The date is rendered separately through DateText (Law U7).
  ///
  /// In en, this message translates to:
  /// **'{percent} more than the first time in this window'**
  String analyticsInflationUp(Object percent);

  /// The personal-inflation sentence, falling.
  ///
  /// In en, this message translates to:
  /// **'{percent} less than the first time in this window'**
  String analyticsInflationDown(Object percent);

  /// Precedes a DateText giving the earliest purchase in the window.
  ///
  /// In en, this message translates to:
  /// **'First bought'**
  String get analyticsInflationSince;

  /// Empty state: fewer than two priced purchases means there is no trend to draw. Names both ways out.
  ///
  /// In en, this message translates to:
  /// **'Buy something twice and its price trend appears here. Widen the window if you have.'**
  String get analyticsInflationEmpty;

  /// Section header over the spend breakdowns.
  ///
  /// In en, this message translates to:
  /// **'Where it went'**
  String get analyticsSectionSpend;

  /// Section header over the trends.
  ///
  /// In en, this message translates to:
  /// **'Over time'**
  String get analyticsSectionTime;

  /// Section header over payees and items.
  ///
  /// In en, this message translates to:
  /// **'Who and what'**
  String get analyticsSectionWhat;

  /// Section header over stock, waste and expiry.
  ///
  /// In en, this message translates to:
  /// **'Your home'**
  String get analyticsSectionHome;

  /// Section header over recurring commitments and assets.
  ///
  /// In en, this message translates to:
  /// **'Already committed'**
  String get analyticsSectionCommitments;

  /// Query 1. "Kind" rather than "subtype": the schema's word is not the user's.
  ///
  /// In en, this message translates to:
  /// **'By kind'**
  String get analyticsBySubtype;

  /// Query 2.
  ///
  /// In en, this message translates to:
  /// **'By tag'**
  String get analyticsByTag;

  /// The caveat belongs on the card: a reader comparing tag figures against the headline deserves to know why they differ.
  ///
  /// In en, this message translates to:
  /// **'A purchase with two tags counts in both, so these add up to more than the total'**
  String get analyticsByTagNote;

  /// Query 3.
  ///
  /// In en, this message translates to:
  /// **'By payment method'**
  String get analyticsByMethod;

  /// Query 22, with query 8's grocery share beneath it.
  ///
  /// In en, this message translates to:
  /// **'How concentrated'**
  String get analyticsConcentration;

  /// Query 22's headline.
  ///
  /// In en, this message translates to:
  /// **'{percent} of your spending sits in three kinds'**
  String analyticsTopShare(Object percent);

  /// Query 8, stated beneath the concentration figure.
  ///
  /// In en, this message translates to:
  /// **'Groceries are {percent} of it'**
  String analyticsGroceryShare(Object percent);

  /// Marks a parent tag that can be opened. One level only, which is all the schema permits.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 tag inside} other{{count} tags inside}}'**
  String analyticsTagChildren(num count);

  /// The parent tag's own spending, as a sibling of its children rather than folded into them.
  ///
  /// In en, this message translates to:
  /// **'{tag} on its own'**
  String analyticsTagDirect(Object tag);

  /// Tooltip on the in-place drill's back button.
  ///
  /// In en, this message translates to:
  /// **'Back to all tags'**
  String get analyticsTagBack;

  /// Empty state for a spend breakdown.
  ///
  /// In en, this message translates to:
  /// **'Nothing spent in this window'**
  String get analyticsNothingSpent;

  /// Empty state for the tag breakdown: names the action, not the absence.
  ///
  /// In en, this message translates to:
  /// **'Tag a purchase and it will appear here'**
  String get analyticsNoTaggedSpend;

  /// Empty state for the payment-method breakdown.
  ///
  /// In en, this message translates to:
  /// **'Record how you paid and it will appear here'**
  String get analyticsNoMethodSpend;

  /// Query 5.
  ///
  /// In en, this message translates to:
  /// **'In and out'**
  String get analyticsIncomeVsExpense;

  /// Empty state: one month is a pair of figures, not a trend.
  ///
  /// In en, this message translates to:
  /// **'Two months of records and the trend appears here'**
  String get analyticsNeedTwoMonths;

  /// Query 6. Named for what the figure means rather than for the ledger it comes from.
  ///
  /// In en, this message translates to:
  /// **'What you kept'**
  String get analyticsNetFlow;

  /// Explains why a transfer is absent: the ledger nets it to zero across its two legs.
  ///
  /// In en, this message translates to:
  /// **'Moving money between your own accounts does not count'**
  String get analyticsNetFlowNote;

  /// Empty state for net flow.
  ///
  /// In en, this message translates to:
  /// **'Nothing moved in this window'**
  String get analyticsNoFlow;

  /// Query 7.
  ///
  /// In en, this message translates to:
  /// **'Balance over time'**
  String get analyticsBalanceTrend;

  /// Names the account and its currency: this is the one figure on the screen not in the home currency, because converting each point would make the line move when rates moved.
  ///
  /// In en, this message translates to:
  /// **'{account}, in {currency}'**
  String analyticsBalanceIn(Object account, Object currency);

  /// Label on the balance-trend account picker.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get analyticsAccount;

  /// Empty state for the balance trend.
  ///
  /// In en, this message translates to:
  /// **'No movement on this account in this window'**
  String get analyticsNoBalanceMovement;

  /// Query 21.
  ///
  /// In en, this message translates to:
  /// **'When you spend'**
  String get analyticsHeatmap;

  /// Heatmap segment.
  ///
  /// In en, this message translates to:
  /// **'By day of week'**
  String get analyticsByWeekday;

  /// Heatmap segment.
  ///
  /// In en, this message translates to:
  /// **'By date'**
  String get analyticsByDayOfMonth;

  /// Query 4.
  ///
  /// In en, this message translates to:
  /// **'Who you paid most'**
  String get analyticsTopPayees;

  /// Empty state for top payees.
  ///
  /// In en, this message translates to:
  /// **'Name who you paid and they will appear here'**
  String get analyticsNoPayees;

  /// Query 9.
  ///
  /// In en, this message translates to:
  /// **'What cost you most'**
  String get analyticsTopItems;

  /// Empty state for top items by spend.
  ///
  /// In en, this message translates to:
  /// **'Itemise a purchase and it will appear here'**
  String get analyticsNoItemisedSpend;

  /// Query 10.
  ///
  /// In en, this message translates to:
  /// **'What you buy most of'**
  String get analyticsTopByQuantity;

  /// Explains the grouping: Law L8 makes cross-category comparison meaningless.
  ///
  /// In en, this message translates to:
  /// **'Grouped by measure, because weight and count cannot be compared'**
  String get analyticsTopByQuantityNote;

  /// Empty state for top items by quantity.
  ///
  /// In en, this message translates to:
  /// **'Record how much you bought and it will appear here'**
  String get analyticsNoQuantities;

  /// How many times an item was bought in the window.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 purchase} other{{count} purchases}}'**
  String analyticsPurchaseCount(num count);

  /// Query 11.
  ///
  /// In en, this message translates to:
  /// **'The most you have paid'**
  String get analyticsDearest;

  /// Key on the dearest-purchase card.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get analyticsDearestItem;

  /// Key on the dearest-purchase card. The figure is in the currency it was bought in, unconverted.
  ///
  /// In en, this message translates to:
  /// **'Unit price'**
  String get analyticsDearestPrice;

  /// Key on the dearest-purchase card, paired with a DateText.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get analyticsDearestWhen;

  /// Empty state for the dearest purchase.
  ///
  /// In en, this message translates to:
  /// **'Record a unit price and this appears here'**
  String get analyticsNoUnitPrices;

  /// Query 23.
  ///
  /// In en, this message translates to:
  /// **'Your average shop'**
  String get analyticsAverageBasket;

  /// Key on the basket card.
  ///
  /// In en, this message translates to:
  /// **'Average value'**
  String get analyticsBasketValue;

  /// Key on the basket card.
  ///
  /// In en, this message translates to:
  /// **'Average items'**
  String get analyticsBasketLines;

  /// Key on the basket card. Counts the baskets that converted, which is what the average divides by.
  ///
  /// In en, this message translates to:
  /// **'Shops counted'**
  String get analyticsBasketCount;

  /// Empty state for the basket card.
  ///
  /// In en, this message translates to:
  /// **'Record a grocery shop and it will appear here'**
  String get analyticsNoBaskets;

  /// Query 13.
  ///
  /// In en, this message translates to:
  /// **'What is on your shelves'**
  String get analyticsInventoryValue;

  /// Explains why the range chip does not change this figure.
  ///
  /// In en, this message translates to:
  /// **'Right now, whatever window you have chosen'**
  String get analyticsInventoryValueNote;

  /// How many batches had both a cost and a resolvable purchase unit.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 batch valued} other{{count} batches valued}}'**
  String analyticsBatchesValued(num count);

  /// Uncosted stock, reported rather than omitted: a valuation that skipped it would look complete while understating the shelf.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 batch has no cost} other{{count} batches have no cost}}'**
  String analyticsBatchesNoCost(num count);

  /// Empty state for the inventory valuation.
  ///
  /// In en, this message translates to:
  /// **'Record what a batch cost and its value appears here'**
  String get analyticsNoStockValue;

  /// Query 14, one of the app's differentiating insights.
  ///
  /// In en, this message translates to:
  /// **'What you threw away'**
  String get analyticsWaste;

  /// Empty state, and it is good news: worded as a fact rather than as missing data.
  ///
  /// In en, this message translates to:
  /// **'Nothing wasted in this window'**
  String get analyticsNoWaste;

  /// Query 15.
  ///
  /// In en, this message translates to:
  /// **'Expiring within {days} days'**
  String analyticsExpiring(int days);

  /// Empty state for the expiry card.
  ///
  /// In en, this message translates to:
  /// **'Nothing expires soon'**
  String get analyticsNothingExpiring;

  /// How long a batch has. Paired with a tone, because colour is never the only signal (Law U17).
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day left} other{{days} days left}}'**
  String analyticsDaysLeft(num days);

  /// Chip on a batch whose expiry has passed and still holds stock.
  ///
  /// In en, this message translates to:
  /// **'Past its date'**
  String get analyticsExpiredAlready;

  /// Query 16.
  ///
  /// In en, this message translates to:
  /// **'Running low'**
  String get analyticsLowStock;

  /// Explains why this is one figure rather than a trend.
  ///
  /// In en, this message translates to:
  /// **'A count for today, not a history: stock levels are not kept over time'**
  String get analyticsLowStockNote;

  /// Query 16's figure.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item below its threshold} other{{count} items below their threshold}}'**
  String analyticsLowStockCount(num count);

  /// Precedes a DateText on the low-stock count.
  ///
  /// In en, this message translates to:
  /// **'As of'**
  String get analyticsAsOf;

  /// Empty state for the low-stock card.
  ///
  /// In en, this message translates to:
  /// **'Nothing is running low'**
  String get analyticsNothingLow;

  /// Query 17.
  ///
  /// In en, this message translates to:
  /// **'Every month, before anything else'**
  String get analyticsCommitment;

  /// Explains the outflow-only filter: netting salary against rent would report a household as having no fixed costs.
  ///
  /// In en, this message translates to:
  /// **'Bills and subscriptions only. Income is not netted off'**
  String get analyticsCommitmentNote;

  /// How many active templates the monthly figure covers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{from 1 commitment} other{from {count} commitments}}'**
  String analyticsCommitmentCount(num count);

  /// Empty state for the commitment total.
  ///
  /// In en, this message translates to:
  /// **'Add a bill or subscription and it will appear here'**
  String get analyticsNoCommitments;

  /// Query 18.
  ///
  /// In en, this message translates to:
  /// **'Fixed against chosen'**
  String get analyticsRecurringSplit;

  /// Query 18's recurring side. The user's word, not the schema's.
  ///
  /// In en, this message translates to:
  /// **'Fixed'**
  String get analyticsRecurring;

  /// Query 18's discretionary side.
  ///
  /// In en, this message translates to:
  /// **'Chosen'**
  String get analyticsDiscretionary;

  /// Query 18's headline.
  ///
  /// In en, this message translates to:
  /// **'{percent} of your spending was already committed'**
  String analyticsRecurringShare(Object percent);

  /// Query 19. Includes disposed assets, which is the point of a status change rather than a delete.
  ///
  /// In en, this message translates to:
  /// **'What your things cost to keep'**
  String get analyticsServiceCost;

  /// How many service records an asset has in the window.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 visit} other{{count} visits}}'**
  String analyticsServiceCount(num count);

  /// Empty state for the service-cost card.
  ///
  /// In en, this message translates to:
  /// **'Record a service or repair and it will appear here'**
  String get analyticsNoServiceCost;

  /// Query 20.
  ///
  /// In en, this message translates to:
  /// **'Warranties'**
  String get analyticsWarranty;

  /// Chip on an asset still inside its warranty window.
  ///
  /// In en, this message translates to:
  /// **'Covered'**
  String get analyticsCovered;

  /// Chip on an asset whose warranty has run out.
  ///
  /// In en, this message translates to:
  /// **'Cover ended'**
  String get analyticsCoverageEnded;

  /// Empty state for the warranty card.
  ///
  /// In en, this message translates to:
  /// **'Add a warranty date and it will appear here'**
  String get analyticsNoWarranties;

  /// Screen-level empty state. The house section stays visible beneath it, because stock is a "right now" figure.
  ///
  /// In en, this message translates to:
  /// **'Nothing to show for this window'**
  String get analyticsEmptyTitle;

  /// Names both ways out: on a fresh install the second is the answer, on a quiet month the first is.
  ///
  /// In en, this message translates to:
  /// **'Widen the window above, or record something and it will appear here.'**
  String get analyticsEmptyBody;

  /// The clear-cache action, named for what the reader gets rather than for the table it empties.
  ///
  /// In en, this message translates to:
  /// **'Recalculate everything'**
  String get analyticsCacheClear;

  /// The action's in-progress label.
  ///
  /// In en, this message translates to:
  /// **'Recalculating…'**
  String get analyticsCacheClearing;

  /// Explains what the action does. The only place analytics_cache is ever visible (ARCH_5 §7.3).
  ///
  /// In en, this message translates to:
  /// **'Some figures are kept between visits so this screen opens quickly. Clear them if a number looks stale.'**
  String get analyticsCacheExplain;

  /// Precedes a DateText giving when the cache was last cleared.
  ///
  /// In en, this message translates to:
  /// **'Recalculated'**
  String get analyticsCacheCleared;

  /// Success snack. Same word as the button, per ARCH_5 §2.8.
  ///
  /// In en, this message translates to:
  /// **'Figures recalculated'**
  String get analyticsCacheClearedSnack;

  /// Failure snack. Names what failed rather than apologising.
  ///
  /// In en, this message translates to:
  /// **'Could not clear the saved figures'**
  String get analyticsCacheFailed;

  /// Fallback title for the drill-down while its label resolves.
  ///
  /// In en, this message translates to:
  /// **'Behind this figure'**
  String get analyticsDrillTitle;

  /// Precedes the drill-down's per-currency subtotals.
  ///
  /// In en, this message translates to:
  /// **'These come to'**
  String get analyticsDrillTotal;

  /// Semantics label on the drill-down's skeleton.
  ///
  /// In en, this message translates to:
  /// **'Loading these transactions…'**
  String get analyticsDrillLoading;

  /// Drill-down empty state.
  ///
  /// In en, this message translates to:
  /// **'Nothing here in this window'**
  String get analyticsDrillEmptyTitle;

  /// Names the likely cause: the filter is what the reader just chose, the window is what they may have forgotten.
  ///
  /// In en, this message translates to:
  /// **'The window is set on the insights screen. Widen it and these may appear.'**
  String get analyticsDrillEmptyBody;

  /// Shown when the route's parameters name no filter this version knows.
  ///
  /// In en, this message translates to:
  /// **'This link does not point anywhere'**
  String get analyticsDrillUnknownTitle;

  /// Offers the way on rather than throwing: the route is reachable from outside the app.
  ///
  /// In en, this message translates to:
  /// **'Open insights and choose a figure to look behind.'**
  String get analyticsDrillUnknownBody;

  /// The grouped remainder wedge of a donut, past the sixth slice. A ring of twelve slivers is not readable, so the tail becomes one wedge that says what it is.
  ///
  /// In en, this message translates to:
  /// **'Everything else'**
  String get analyticsOtherSlices;

  /// The quiet line under the percentage in the concentration donut's centre, saying what that percentage is of.
  ///
  /// In en, this message translates to:
  /// **'in three kinds'**
  String get analyticsTopThree;

  /// No description provided for @aboutHowItWorksHeader.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get aboutHowItWorksHeader;

  /// No description provided for @aboutLicences.
  ///
  /// In en, this message translates to:
  /// **'Open source licences'**
  String get aboutLicences;

  /// No description provided for @aboutLicencesHelp.
  ///
  /// In en, this message translates to:
  /// **'The libraries Alaya is built on.'**
  String get aboutLicencesHelp;

  /// No description provided for @aboutOfflineBody.
  ///
  /// In en, this message translates to:
  /// **'Everything is stored on this device. Alaya only reaches the internet to fetch exchange rates, once a day.'**
  String get aboutOfflineBody;

  /// The same threat model the lock screen states, in the place somebody comes looking for it. Two locations is not duplication: one is a decision point, the other is where a question gets answered.
  ///
  /// In en, this message translates to:
  /// **'Your data is not encrypted, and no copy of it exists anywhere else unless you make a backup yourself.'**
  String get aboutStorageBody;

  /// No description provided for @aboutTagline.
  ///
  /// In en, this message translates to:
  /// **'A finance and home manager that works entirely on your phone.'**
  String get aboutTagline;

  /// No description provided for @accountCurrencyHeader.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get accountCurrencyHeader;

  /// Law L9 at its sharpest: the home currency is a display choice, but an account’s own currency is what its money is.
  ///
  /// In en, this message translates to:
  /// **'Fixed, because changing it would reinterpret every amount already recorded here.'**
  String get accountCurrencyLockedHelp;

  /// No description provided for @accountCurrencyNewHelp.
  ///
  /// In en, this message translates to:
  /// **'What this account holds. It cannot be changed once you start recording against it.'**
  String get accountCurrencyNewHelp;

  /// No description provided for @accountEditorEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit account'**
  String get accountEditorEditTitle;

  /// Names the thing, per archetype B — never a bare "Save".
  ///
  /// In en, this message translates to:
  /// **'Save account'**
  String get accountEditorSave;

  /// No description provided for @accountEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'New account'**
  String get accountEditorTitle;

  /// No description provided for @accountIncludeInNetWorth.
  ///
  /// In en, this message translates to:
  /// **'Count in net worth'**
  String get accountIncludeInNetWorth;

  /// ARCH_5 §7.2 requires the toggle be explained: without this line the reader cannot tell whether off means hidden or merely uncounted.
  ///
  /// In en, this message translates to:
  /// **'Off means the balance still shows here, but is left out of your total. Useful for an account you hold for someone else.'**
  String get accountIncludeInNetWorthHelp;

  /// No description provided for @accountKindBank.
  ///
  /// In en, this message translates to:
  /// **'Bank'**
  String get accountKindBank;

  /// No description provided for @accountKindCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get accountKindCard;

  /// No description provided for @accountKindCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get accountKindCash;

  /// No description provided for @accountKindHeader.
  ///
  /// In en, this message translates to:
  /// **'What kind?'**
  String get accountKindHeader;

  /// No description provided for @accountKindOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get accountKindOther;

  /// No description provided for @accountKindWallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get accountKindWallet;

  /// No description provided for @accountNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get accountNameLabel;

  /// No description provided for @accountOpeningBalanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Opening balance'**
  String get accountOpeningBalanceLabel;

  /// Not "date": the question is which day the balance was correct, and "date" invites today by default.
  ///
  /// In en, this message translates to:
  /// **'True on'**
  String get accountOpeningDateLabel;

  /// No description provided for @accountsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add an account'**
  String get accountsAdd;

  /// No description provided for @accountsArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive this account'**
  String get accountsArchive;

  /// No description provided for @accountsArchiveConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'It will stop appearing when you record anything. Its history stays, and you can restore it here at any time.'**
  String get accountsArchiveConfirmBody;

  /// No description provided for @accountsArchiveConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Archive this account?'**
  String get accountsArchiveConfirmTitle;

  /// Says what survives, because "archive" does not tell the reader whether their transactions go with it.
  ///
  /// In en, this message translates to:
  /// **'An archived account keeps all its history. It just stops appearing when you record something.'**
  String get accountsArchiveHelp;

  /// No description provided for @accountsArchived.
  ///
  /// In en, this message translates to:
  /// **'Account archived'**
  String get accountsArchived;

  /// No description provided for @accountsArchivedChip.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get accountsArchivedChip;

  /// No description provided for @accountsArchivedHeader.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get accountsArchivedHeader;

  /// No description provided for @accountsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add one so Alaya knows where your money is.'**
  String get accountsEmptyBody;

  /// No description provided for @accountsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No accounts yet'**
  String get accountsEmptyTitle;

  /// No description provided for @accountsExcludedChip.
  ///
  /// In en, this message translates to:
  /// **'Not in net worth'**
  String get accountsExcludedChip;

  /// No description provided for @accountsLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading your accounts…'**
  String get accountsLoading;

  /// A stale deep link, or a row removed in another window. Stated rather than rendering a blank form that would silently create a second account on save.
  ///
  /// In en, this message translates to:
  /// **'It may have been removed. Go back and pick another.'**
  String get accountsMissingBody;

  /// No description provided for @accountsMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'That account is not here'**
  String get accountsMissingTitle;

  /// No description provided for @accountsRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore this account'**
  String get accountsRestore;

  /// Confirmed in both directions: restoring puts an account back into every picker, which is worth stating before it happens.
  ///
  /// In en, this message translates to:
  /// **'It will appear again everywhere you choose an account.'**
  String get accountsRestoreConfirmBody;

  /// No description provided for @accountsRestoreConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore this account?'**
  String get accountsRestoreConfirmTitle;

  /// No description provided for @accountsRestored.
  ///
  /// In en, this message translates to:
  /// **'Account restored'**
  String get accountsRestored;

  /// No description provided for @accountsSaved.
  ///
  /// In en, this message translates to:
  /// **'Account saved'**
  String get accountsSaved;

  /// No description provided for @actionBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get actionBack;

  /// No description provided for @actionContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get actionContinue;

  /// No description provided for @appearanceModeDark.
  ///
  /// In en, this message translates to:
  /// **'Always dark'**
  String get appearanceModeDark;

  /// No description provided for @appearanceModeHeader.
  ///
  /// In en, this message translates to:
  /// **'Light or dark'**
  String get appearanceModeHeader;

  /// No description provided for @appearanceModeLight.
  ///
  /// In en, this message translates to:
  /// **'Always light'**
  String get appearanceModeLight;

  /// No description provided for @appearanceModeSystem.
  ///
  /// In en, this message translates to:
  /// **'Match my phone'**
  String get appearanceModeSystem;

  /// No description provided for @appearanceModeSystemHelp.
  ///
  /// In en, this message translates to:
  /// **'Follows your phone’s light and dark setting.'**
  String get appearanceModeSystemHelp;

  /// No description provided for @appearancePaletteHeader.
  ///
  /// In en, this message translates to:
  /// **'Colours'**
  String get appearancePaletteHeader;

  /// No description provided for @appearanceThemeLabHelp.
  ///
  /// In en, this message translates to:
  /// **'See every colour, spacing and text style the app uses.'**
  String get appearanceThemeLabHelp;

  /// ARCH_3 §3.4 verbatim, on every export confirmation — not in settings, not a tooltip. Corrected in 8B: the 8A wording was a paraphrase that dropped the third sentence.
  ///
  /// In en, this message translates to:
  /// **'This backup is not encrypted. Anyone who opens this file can read every transaction, balance and account name. Only share it somewhere you trust.'**
  String get backupNotEncryptedWarning;

  /// Law L9: disabling it would leave the dashboard with no currency to aggregate into. Disabled rather than hidden, so it reads as an explanation and not a rendering fault.
  ///
  /// In en, this message translates to:
  /// **'Cannot be turned off — your totals are added up in this.'**
  String get currenciesHomeLocked;

  /// No description provided for @currenciesLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading currencies…'**
  String get currenciesLoading;

  /// No description provided for @currenciesToggleFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be changed'**
  String get currenciesToggleFailed;

  /// No description provided for @dataBackupHeader.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get dataBackupHeader;

  /// No description provided for @dataExportBody.
  ///
  /// In en, this message translates to:
  /// **'Sends a copy of your data to WhatsApp, Drive, or anywhere else you choose.'**
  String get dataExportBody;

  /// No description provided for @dataExportConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Share it'**
  String get dataExportConfirmAction;

  /// No description provided for @dataExportConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Share a backup?'**
  String get dataExportConfirmTitle;

  /// No description provided for @dataExportFailed.
  ///
  /// In en, this message translates to:
  /// **'The backup could not be made'**
  String get dataExportFailed;

  /// No description provided for @dataExportTitle.
  ///
  /// In en, this message translates to:
  /// **'Share a backup'**
  String get dataExportTitle;

  /// No description provided for @dataRestoreHeader.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get dataRestoreHeader;

  /// Stated as not-yet-here rather than offered and broken: restore needs the Storage Access Framework picker and a merge strategy, both of which are 8B’s.
  ///
  /// In en, this message translates to:
  /// **'Coming in the next update.'**
  String get dataRestorePending;

  /// No description provided for @dataRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore from a backup'**
  String get dataRestoreTitle;

  /// No description provided for @lockBackspace.
  ///
  /// In en, this message translates to:
  /// **'Delete last digit'**
  String get lockBackspace;

  /// No description provided for @lockBiometricFailed.
  ///
  /// In en, this message translates to:
  /// **'Not recognised. Enter your PIN instead.'**
  String get lockBiometricFailed;

  /// Shown by the system prompt, so it must be localised before it reaches the plugin (Law U5).
  ///
  /// In en, this message translates to:
  /// **'Unlock Alaya'**
  String get lockBiometricReason;

  /// Says what did not change, so a failed erase does not leave the user unsure whether they are locked out of a half-wiped app.
  ///
  /// In en, this message translates to:
  /// **'The data could not be deleted. Your PIN is unchanged.'**
  String get lockEraseFailed;

  /// The ten-failure auto-erase is running. It takes the whole screen, because there is nothing left to enter a PIN against.
  ///
  /// In en, this message translates to:
  /// **'Deleting everything on this device…'**
  String get lockErasing;

  /// No description provided for @lockForgotPin.
  ///
  /// In en, this message translates to:
  /// **'I have forgotten my PIN'**
  String get lockForgotPin;

  /// ARCH_3 §2.5, and the most important string in the app. No "bank-grade", no "military-grade", and no padlock glyph beside it: the database is plaintext by design (ARCH_1 §2.1) and claiming otherwise would be dishonest and a Play listing risk.
  ///
  /// In en, this message translates to:
  /// **'This PIN stops someone who picks up your unlocked phone from opening Alaya. It does not encrypt your data — anyone with access to the phone\'s files can still read them. Your phone\'s own lock screen is what protects the file itself.'**
  String get lockHonestBody;

  /// Says why the delay exists, so a throttle reads as deliberate rather than as the app having frozen.
  ///
  /// In en, this message translates to:
  /// **'The wait gets longer after each wrong attempt.'**
  String get lockThrottledWhy;

  /// No description provided for @lockTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN'**
  String get lockTitle;

  /// The keypad key is an icon, so this is its Semantics label (ARCH_5 §2.7).
  ///
  /// In en, this message translates to:
  /// **'Use fingerprint'**
  String get lockUseBiometric;

  /// No description provided for @lockWrongPin.
  ///
  /// In en, this message translates to:
  /// **'That PIN is not right.'**
  String get lockWrongPin;

  /// No description provided for @onboardingAccountsBody.
  ///
  /// In en, this message translates to:
  /// **'Where do you keep your money? Add the ones you use.'**
  String get onboardingAccountsBody;

  /// No description provided for @onboardingAccountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your accounts'**
  String get onboardingAccountsTitle;

  /// No description provided for @onboardingAddAccount.
  ///
  /// In en, this message translates to:
  /// **'Add an account'**
  String get onboardingAddAccount;

  /// No description provided for @onboardingCurrencyBody.
  ///
  /// In en, this message translates to:
  /// **'Which currency should Alaya add your totals up in?'**
  String get onboardingCurrencyBody;

  /// Law L9 in plain words. Somebody who thinks they are converting their history would be very surprised later.
  ///
  /// In en, this message translates to:
  /// **'This changes how totals are shown. It does not change any amount you have already recorded, and each account keeps its own currency.'**
  String get onboardingCurrencyNote;

  /// No description provided for @onboardingCurrencyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your currency'**
  String get onboardingCurrencyTitle;

  /// No description provided for @onboardingFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get onboardingFinish;

  /// No description provided for @onboardingLoading.
  ///
  /// In en, this message translates to:
  /// **'Getting things ready…'**
  String get onboardingLoading;

  /// No description provided for @onboardingLockOnBody.
  ///
  /// In en, this message translates to:
  /// **'Alaya will ask for your PIN when you open it. You can change or remove it in Settings › Security.'**
  String get onboardingLockOnBody;

  /// No description provided for @onboardingLockOnHeader.
  ///
  /// In en, this message translates to:
  /// **'Lock is on'**
  String get onboardingLockOnHeader;

  /// No description provided for @onboardingNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// No description provided for @onboardingNoAccountsBody.
  ///
  /// In en, this message translates to:
  /// **'Add at least one so Alaya knows where your money is.'**
  String get onboardingNoAccountsBody;

  /// No description provided for @onboardingNoAccountsTitle.
  ///
  /// In en, this message translates to:
  /// **'No accounts yet'**
  String get onboardingNoAccountsTitle;

  /// Anomaly A03. This is the paragraph that stops an opening balance being captured without its date.
  ///
  /// In en, this message translates to:
  /// **'The opening balance is what was there on the date you give. Alaya needs both: a balance with no date cannot be placed in your ledger, and anything you record before that date would not be counted.'**
  String get onboardingOpeningNote;

  /// No description provided for @onboardingRemoveAccount.
  ///
  /// In en, this message translates to:
  /// **'Remove this account'**
  String get onboardingRemoveAccount;

  /// No description provided for @onboardingSaveAccounts.
  ///
  /// In en, this message translates to:
  /// **'Save accounts'**
  String get onboardingSaveAccounts;

  /// No description provided for @onboardingSecurityBody.
  ///
  /// In en, this message translates to:
  /// **'You can put a PIN on Alaya. This is optional and you can add one later.'**
  String get onboardingSecurityBody;

  /// No description provided for @onboardingSecurityTitle.
  ///
  /// In en, this message translates to:
  /// **'Lock the app?'**
  String get onboardingSecurityTitle;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @onboardingSkipBody.
  ///
  /// In en, this message translates to:
  /// **'You can change all of this later in Settings.'**
  String get onboardingSkipBody;

  /// No description provided for @onboardingSkipTitle.
  ///
  /// In en, this message translates to:
  /// **'Skip setting up?'**
  String get onboardingSkipTitle;

  /// No description provided for @onboardingTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Alaya'**
  String get onboardingTitle;

  /// No description provided for @payeeKindEmployer.
  ///
  /// In en, this message translates to:
  /// **'Employer'**
  String get payeeKindEmployer;

  /// No description provided for @payeeKindMerchant.
  ///
  /// In en, this message translates to:
  /// **'Shop'**
  String get payeeKindMerchant;

  /// No description provided for @payeeKindOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get payeeKindOther;

  /// No description provided for @payeeKindPerson.
  ///
  /// In en, this message translates to:
  /// **'Person'**
  String get payeeKindPerson;

  /// No description provided for @payeeKindUtility.
  ///
  /// In en, this message translates to:
  /// **'Utility'**
  String get payeeKindUtility;

  /// No description provided for @payeeNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get payeeNameLabel;

  /// Marked optional, because an unmarked second field reads as required and is the commonest reason a two-field sheet feels like a form.
  ///
  /// In en, this message translates to:
  /// **'Phone (optional)'**
  String get payeePhoneOptionalLabel;

  /// No description provided for @payeesAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a payee'**
  String get payeesAdd;

  /// No description provided for @payeesDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get payeesDelete;

  /// No description provided for @payeesDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Transactions that named them keep their record. They just stop being suggested.'**
  String get payeesDeleteConfirmBody;

  /// No description provided for @payeesDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this payee?'**
  String get payeesDeleteConfirmTitle;

  /// No description provided for @payeesDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be deleted'**
  String get payeesDeleteFailed;

  /// No description provided for @payeesDeleted.
  ///
  /// In en, this message translates to:
  /// **'Payee deleted'**
  String get payeesDeleted;

  /// No description provided for @payeesEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit payee'**
  String get payeesEditTitle;

  /// No description provided for @payeesEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'These build up as you record who you paid.'**
  String get payeesEmptyBody;

  /// No description provided for @payeesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No payees yet'**
  String get payeesEmptyTitle;

  /// No description provided for @payeesLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading payees…'**
  String get payeesLoading;

  /// No description provided for @payeesNoMatchBody.
  ///
  /// In en, this message translates to:
  /// **'Try part of the name.'**
  String get payeesNoMatchBody;

  /// No description provided for @payeesNoMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'No payees match that'**
  String get payeesNoMatchTitle;

  /// No description provided for @payeesSave.
  ///
  /// In en, this message translates to:
  /// **'Save payee'**
  String get payeesSave;

  /// No description provided for @payeesSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be saved'**
  String get payeesSaveFailed;

  /// No description provided for @payeesSaved.
  ///
  /// In en, this message translates to:
  /// **'Payee saved'**
  String get payeesSaved;

  /// No description provided for @payeesSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search payees'**
  String get payeesSearchHint;

  /// No description provided for @paymentKindBankTransfer.
  ///
  /// In en, this message translates to:
  /// **'Bank transfer'**
  String get paymentKindBankTransfer;

  /// No description provided for @paymentKindCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get paymentKindCard;

  /// No description provided for @paymentKindCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get paymentKindCash;

  /// No description provided for @paymentKindCheque.
  ///
  /// In en, this message translates to:
  /// **'Cheque'**
  String get paymentKindCheque;

  /// No description provided for @paymentKindOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get paymentKindOther;

  /// No description provided for @paymentKindUpi.
  ///
  /// In en, this message translates to:
  /// **'UPI'**
  String get paymentKindUpi;

  /// No description provided for @paymentKindWallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get paymentKindWallet;

  /// No description provided for @paymentMethodNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get paymentMethodNameLabel;

  /// No description provided for @paymentMethodsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a payment method'**
  String get paymentMethodsAdd;

  /// No description provided for @paymentMethodsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get paymentMethodsDelete;

  /// No description provided for @paymentMethodsDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Transactions that used it keep their record of having done so. It just stops being offered.'**
  String get paymentMethodsDeleteConfirmBody;

  /// No description provided for @paymentMethodsDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this payment method?'**
  String get paymentMethodsDeleteConfirmTitle;

  /// No description provided for @paymentMethodsDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be deleted'**
  String get paymentMethodsDeleteFailed;

  /// No description provided for @paymentMethodsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Payment method deleted'**
  String get paymentMethodsDeleted;

  /// No description provided for @paymentMethodsEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit payment method'**
  String get paymentMethodsEditTitle;

  /// No description provided for @paymentMethodsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add how you usually pay — cash, UPI, a card.'**
  String get paymentMethodsEmptyBody;

  /// No description provided for @paymentMethodsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No payment methods'**
  String get paymentMethodsEmptyTitle;

  /// No description provided for @paymentMethodsLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading payment methods…'**
  String get paymentMethodsLoading;

  /// No description provided for @paymentMethodsSave.
  ///
  /// In en, this message translates to:
  /// **'Save payment method'**
  String get paymentMethodsSave;

  /// No description provided for @paymentMethodsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be saved'**
  String get paymentMethodsSaveFailed;

  /// No description provided for @paymentMethodsSaved.
  ///
  /// In en, this message translates to:
  /// **'Payment method saved'**
  String get paymentMethodsSaved;

  /// Renameable but not removable, and the chip says so before the user hunts for a delete that is not there.
  ///
  /// In en, this message translates to:
  /// **'Built in'**
  String get paymentMethodsSystemChip;

  /// No description provided for @pinSetupBackupBody.
  ///
  /// In en, this message translates to:
  /// **'You have just put a lock on this app. A backup means a forgotten PIN never costs you your records.'**
  String get pinSetupBackupBody;

  /// No description provided for @pinSetupBackupHeader.
  ///
  /// In en, this message translates to:
  /// **'Make a backup?'**
  String get pinSetupBackupHeader;

  /// No description provided for @pinSetupBackupLater.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get pinSetupBackupLater;

  /// No description provided for @pinSetupBackupNow.
  ///
  /// In en, this message translates to:
  /// **'Back up now'**
  String get pinSetupBackupNow;

  /// No description provided for @pinSetupConfirmPrompt.
  ///
  /// In en, this message translates to:
  /// **'Enter it again'**
  String get pinSetupConfirmPrompt;

  /// No description provided for @pinSetupDone.
  ///
  /// In en, this message translates to:
  /// **'Your PIN is set'**
  String get pinSetupDone;

  /// No description provided for @pinSetupDoneBody.
  ///
  /// In en, this message translates to:
  /// **'Alaya will ask for it when you open the app, and again after a minute in the background.'**
  String get pinSetupDoneBody;

  /// No description provided for @pinSetupEnterPrompt.
  ///
  /// In en, this message translates to:
  /// **'Choose a PIN'**
  String get pinSetupEnterPrompt;

  /// Both entries are cleared, because somebody who mistyped does not know which of the two was wrong.
  ///
  /// In en, this message translates to:
  /// **'Those did not match. Start again.'**
  String get pinSetupMismatch;

  /// The one confirmation, and it gates the button rather than warning after the fact.
  ///
  /// In en, this message translates to:
  /// **'I have saved this code somewhere safe'**
  String get pinSetupRecoveryAck;

  /// True rather than cautious: PinService stores only a hash, so the app genuinely cannot redisplay it.
  ///
  /// In en, this message translates to:
  /// **'This is the only way back in if you forget your PIN. It is shown once and cannot be shown again.'**
  String get pinSetupRecoveryBody;

  /// No description provided for @pinSetupRecoveryCopied.
  ///
  /// In en, this message translates to:
  /// **'Recovery code copied'**
  String get pinSetupRecoveryCopied;

  /// No description provided for @pinSetupRecoveryCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get pinSetupRecoveryCopy;

  /// No description provided for @pinSetupRecoveryHeader.
  ///
  /// In en, this message translates to:
  /// **'Your recovery code'**
  String get pinSetupRecoveryHeader;

  /// No description provided for @pinSetupRecoveryWhereToKeep.
  ///
  /// In en, this message translates to:
  /// **'A password manager is a good place for it. A photo in your gallery is not.'**
  String get pinSetupRecoveryWhereToKeep;

  /// No description provided for @pinSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Set a PIN'**
  String get pinSetupTitle;

  /// No description provided for @recoveryCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Recovery code'**
  String get recoveryCodeLabel;

  /// No description provided for @recoveryCodePrompt.
  ///
  /// In en, this message translates to:
  /// **'Enter the recovery code you saved when you set your PIN.'**
  String get recoveryCodePrompt;

  /// No description provided for @recoveryDone.
  ///
  /// In en, this message translates to:
  /// **'Your PIN has been changed'**
  String get recoveryDone;

  /// No description provided for @recoveryEraseEverything.
  ///
  /// In en, this message translates to:
  /// **'Erase everything'**
  String get recoveryEraseEverything;

  /// No description provided for @recoveryExportFirst.
  ///
  /// In en, this message translates to:
  /// **'Export a copy first'**
  String get recoveryExportFirst;

  /// Asks the user to verify: a backup nobody confirmed is not a backup.
  ///
  /// In en, this message translates to:
  /// **'A copy has been shared. Check it arrived before you erase.'**
  String get recoveryExported;

  /// No description provided for @recoveryForgotBoth.
  ///
  /// In en, this message translates to:
  /// **'I do not have the recovery code either'**
  String get recoveryForgotBoth;

  /// The export is possible only because the database is plaintext — with encryption the copy would be unreadable without the key the user has lost. ARCH_4 records that as the improvement dropping encryption bought.
  ///
  /// In en, this message translates to:
  /// **'Without your PIN or your recovery code there is no way back into this data. You can export a copy first, then erase everything and start again.'**
  String get recoveryForgotBothBody;

  /// No description provided for @recoveryForgotBothTitle.
  ///
  /// In en, this message translates to:
  /// **'Starting over'**
  String get recoveryForgotBothTitle;

  /// No description provided for @recoveryNewPinPrompt.
  ///
  /// In en, this message translates to:
  /// **'Choose a new PIN'**
  String get recoveryNewPinPrompt;

  /// No description provided for @recoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Forgotten PIN'**
  String get recoveryTitle;

  /// No description provided for @securityAutoEraseConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Turn it on'**
  String get securityAutoEraseConfirmAction;

  /// No description provided for @securityAutoEraseConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn on erase after repeated failures?'**
  String get securityAutoEraseConfirmTitle;

  /// No description provided for @securityAutoEraseFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be changed'**
  String get securityAutoEraseFailed;

  /// No description provided for @securityAutoEraseHeader.
  ///
  /// In en, this message translates to:
  /// **'If the PIN is entered wrongly'**
  String get securityAutoEraseHeader;

  /// No description provided for @securityAutoEraseOff.
  ///
  /// In en, this message translates to:
  /// **'Erase after repeated failures is off'**
  String get securityAutoEraseOff;

  /// No description provided for @securityAutoEraseOn.
  ///
  /// In en, this message translates to:
  /// **'Erase after repeated failures is on'**
  String get securityAutoEraseOn;

  /// No description provided for @securityAutoEraseTitle.
  ///
  /// In en, this message translates to:
  /// **'Erase everything after repeated failures'**
  String get securityAutoEraseTitle;

  /// No description provided for @securityAutoLockHeader.
  ///
  /// In en, this message translates to:
  /// **'Auto-lock'**
  String get securityAutoLockHeader;

  /// No description provided for @securityAutoLockTitle.
  ///
  /// In en, this message translates to:
  /// **'Lock when I leave the app'**
  String get securityAutoLockTitle;

  /// No description provided for @securityChangePin.
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get securityChangePin;

  /// Neither branch is guessed: a row saying "no PIN set" for one frame to somebody who has one would be alarming for the wrong reason.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get securityChecking;

  /// No description provided for @securityPinHeader.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get securityPinHeader;

  /// No description provided for @securityRemovePin.
  ///
  /// In en, this message translates to:
  /// **'Remove PIN'**
  String get securityRemovePin;

  /// No description provided for @securityRemovePinConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Anyone who picks up your unlocked phone will be able to open Alaya. You will be asked for your current PIN next.'**
  String get securityRemovePinConfirmBody;

  /// No description provided for @securityRemovePinConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove the PIN?'**
  String get securityRemovePinConfirmTitle;

  /// No description provided for @securityRemovePinHelp.
  ///
  /// In en, this message translates to:
  /// **'You will need your current PIN to do this.'**
  String get securityRemovePinHelp;

  /// No description provided for @securitySetPin.
  ///
  /// In en, this message translates to:
  /// **'Set a PIN'**
  String get securitySetPin;

  /// No description provided for @securitySetPinHelp.
  ///
  /// In en, this message translates to:
  /// **'Alaya will ask for it when you open the app.'**
  String get securitySetPinHelp;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsAccounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get settingsAccounts;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsCurrencies.
  ///
  /// In en, this message translates to:
  /// **'Currencies'**
  String get settingsCurrencies;

  /// No description provided for @settingsData.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get settingsData;

  /// No description provided for @settingsGroupApp.
  ///
  /// In en, this message translates to:
  /// **'The app'**
  String get settingsGroupApp;

  /// No description provided for @settingsGroupMoney.
  ///
  /// In en, this message translates to:
  /// **'Your money'**
  String get settingsGroupMoney;

  /// No description provided for @settingsGroupThings.
  ///
  /// In en, this message translates to:
  /// **'Your things'**
  String get settingsGroupThings;

  /// Names the search rather than the tree: "no settings" in front of a list the user can see is a lie. The examples are the keywords the rows actually match on.
  ///
  /// In en, this message translates to:
  /// **'Try a different word — \"dark\", \"PIN\" and \"backup\" all find something.'**
  String get settingsNoMatchBody;

  /// No description provided for @settingsNoMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches that'**
  String get settingsNoMatchTitle;

  /// No description provided for @settingsPayees.
  ///
  /// In en, this message translates to:
  /// **'Payees'**
  String get settingsPayees;

  /// No description provided for @settingsPaymentMethods.
  ///
  /// In en, this message translates to:
  /// **'Payment methods'**
  String get settingsPaymentMethods;

  /// No description provided for @settingsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search settings'**
  String get settingsSearchHint;

  /// No description provided for @settingsSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSecurity;

  /// No description provided for @settingsTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get settingsTags;

  /// No description provided for @settingsUnits.
  ///
  /// In en, this message translates to:
  /// **'Units'**
  String get settingsUnits;

  /// No description provided for @tagColourHeader.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get tagColourHeader;

  /// Honest about the freeze: colorArgb is a stored int, so a tag coloured under one preset keeps that colour when the palette changes.
  ///
  /// In en, this message translates to:
  /// **'Optional. Kept as chosen, so it stays the same if you change the app’s palette later.'**
  String get tagColourHelp;

  /// No description provided for @tagColourNone.
  ///
  /// In en, this message translates to:
  /// **'No colour'**
  String get tagColourNone;

  /// The swatches are colour-only, so each needs a Semantics label (Law U17).
  ///
  /// In en, this message translates to:
  /// **'Use this colour'**
  String get tagColourSwatch;

  /// No description provided for @tagEditorEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit tag'**
  String get tagEditorEditTitle;

  /// No description provided for @tagEditorSave.
  ///
  /// In en, this message translates to:
  /// **'Save tag'**
  String get tagEditorSave;

  /// No description provided for @tagEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'New tag'**
  String get tagEditorTitle;

  /// No description provided for @tagNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get tagNameLabel;

  /// No description provided for @tagParentHeader.
  ///
  /// In en, this message translates to:
  /// **'Group under'**
  String get tagParentHeader;

  /// No description provided for @tagParentHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional. Grouping keeps long tag lists readable. Only one level deep.'**
  String get tagParentHelp;

  /// No description provided for @tagParentNone.
  ///
  /// In en, this message translates to:
  /// **'No group'**
  String get tagParentNone;

  /// No description provided for @tagScopeDeposit.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get tagScopeDeposit;

  /// No description provided for @tagScopeDepositHelp.
  ///
  /// In en, this message translates to:
  /// **'Offered when you record income.'**
  String get tagScopeDepositHelp;

  /// No description provided for @tagScopeInventory.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get tagScopeInventory;

  /// No description provided for @tagScopeInventoryHelp.
  ///
  /// In en, this message translates to:
  /// **'Offered on things you keep at home.'**
  String get tagScopeInventoryHelp;

  /// No description provided for @tagScopeRecurring.
  ///
  /// In en, this message translates to:
  /// **'Recurring'**
  String get tagScopeRecurring;

  /// No description provided for @tagScopeRecurringHelp.
  ///
  /// In en, this message translates to:
  /// **'Offered on bills and subscriptions.'**
  String get tagScopeRecurringHelp;

  /// No description provided for @tagScopeService.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get tagScopeService;

  /// No description provided for @tagScopeServiceHelp.
  ///
  /// In en, this message translates to:
  /// **'Offered on appliances and their service records.'**
  String get tagScopeServiceHelp;

  /// No description provided for @tagScopeShopping.
  ///
  /// In en, this message translates to:
  /// **'Shopping lists'**
  String get tagScopeShopping;

  /// No description provided for @tagScopeShoppingHelp.
  ///
  /// In en, this message translates to:
  /// **'Used to group a shopping list under headings.'**
  String get tagScopeShoppingHelp;

  /// No description provided for @tagScopeWithdrawal.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get tagScopeWithdrawal;

  /// No description provided for @tagScopeWithdrawalHelp.
  ///
  /// In en, this message translates to:
  /// **'Offered when you record an expense.'**
  String get tagScopeWithdrawalHelp;

  /// No description provided for @tagScopesHeader.
  ///
  /// In en, this message translates to:
  /// **'Where it appears'**
  String get tagScopesHeader;

  /// ARCH_5 §7.2’s allowedIn* row, said in the terms the requirement itself uses.
  ///
  /// In en, this message translates to:
  /// **'A tag is only offered where you turn it on. This is what keeps \"Kitchen\" out of the list when you record your salary.'**
  String get tagScopesHelp;

  /// No description provided for @tagsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a tag'**
  String get tagsAdd;

  /// No description provided for @tagsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete this tag'**
  String get tagsDelete;

  /// Says what survives, because a soft delete is not what "delete" usually promises (ARCH_3 §4).
  ///
  /// In en, this message translates to:
  /// **'Transactions and items already carrying it keep it in their history. It stops appearing when you tag something new.'**
  String get tagsDeleteConfirmBody;

  /// No description provided for @tagsDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this tag?'**
  String get tagsDeleteConfirmTitle;

  /// No description provided for @tagsDeleteHelp.
  ///
  /// In en, this message translates to:
  /// **'Anything already tagged keeps its history. The tag just stops being offered.'**
  String get tagsDeleteHelp;

  /// No description provided for @tagsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Tag deleted'**
  String get tagsDeleted;

  /// No description provided for @tagsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Tags let you group things across accounts — \"Kitchen\", \"Car\", \"Diwali\".'**
  String get tagsEmptyBody;

  /// No description provided for @tagsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No tags yet'**
  String get tagsEmptyTitle;

  /// No description provided for @tagsLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading tags…'**
  String get tagsLoading;

  /// No description provided for @tagsMissingBody.
  ///
  /// In en, this message translates to:
  /// **'It may have been deleted. Go back and pick another.'**
  String get tagsMissingBody;

  /// No description provided for @tagsMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'That tag is not here'**
  String get tagsMissingTitle;

  /// A tag with no scopes cannot appear anywhere in the app, which makes it invisible everywhere except this screen — exactly the dead row somebody would hunt for in the pickers first.
  ///
  /// In en, this message translates to:
  /// **'This tag is not offered anywhere. Turn on at least one place below, or it will never appear.'**
  String get tagsNoScopesWarning;

  /// No description provided for @tagsSaved.
  ///
  /// In en, this message translates to:
  /// **'Tag saved'**
  String get tagsSaved;

  /// No description provided for @tagsSystemChip.
  ///
  /// In en, this message translates to:
  /// **'Built in'**
  String get tagsSystemChip;

  /// No description provided for @unitBaseGrams.
  ///
  /// In en, this message translates to:
  /// **'grams'**
  String get unitBaseGrams;

  /// No description provided for @unitBaseMillilitres.
  ///
  /// In en, this message translates to:
  /// **'millilitres'**
  String get unitBaseMillilitres;

  /// No description provided for @unitBasePieces.
  ///
  /// In en, this message translates to:
  /// **'pieces'**
  String get unitBasePieces;

  /// No description provided for @unitCategoryHeader.
  ///
  /// In en, this message translates to:
  /// **'What does it measure?'**
  String get unitCategoryHeader;

  /// No description provided for @unitCategoryNewHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose carefully: this cannot be changed later.'**
  String get unitCategoryNewHelp;

  /// No description provided for @unitCodeHelp.
  ///
  /// In en, this message translates to:
  /// **'What you will see beside a quantity — kg, ml, pc.'**
  String get unitCodeHelp;

  /// No description provided for @unitCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Short code'**
  String get unitCodeLabel;

  /// No description provided for @unitCodeLockedHelp.
  ///
  /// In en, this message translates to:
  /// **'Fixed once the unit exists, because other records point at it.'**
  String get unitCodeLockedHelp;

  /// No description provided for @unitEditorEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit unit'**
  String get unitEditorEditTitle;

  /// No description provided for @unitEditorSave.
  ///
  /// In en, this message translates to:
  /// **'Save unit'**
  String get unitEditorSave;

  /// No description provided for @unitEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'New unit'**
  String get unitEditorTitle;

  /// No description provided for @unitFactorHeader.
  ///
  /// In en, this message translates to:
  /// **'How big is it?'**
  String get unitFactorHeader;

  /// Guarded rather than trusted: a zero factor would convert every quantity in the unit to nothing and divide the inventory valuation by zero.
  ///
  /// In en, this message translates to:
  /// **'That has to be more than zero.'**
  String get unitFactorMustBePositive;

  /// Stands in for the name while the field is still empty, so the question reads as a sentence either way.
  ///
  /// In en, this message translates to:
  /// **'this unit'**
  String get unitFactorThisUnit;

  /// No description provided for @unitFactorVaries.
  ///
  /// In en, this message translates to:
  /// **'It varies — I cannot give one number'**
  String get unitFactorVaries;

  /// No description provided for @unitNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get unitNameLabel;

  /// A way back, for somebody who realises on reading this that they can state an amount.
  ///
  /// In en, this message translates to:
  /// **'Actually, I can give a number'**
  String get unitVariesBack;

  /// No description provided for @unitVariesCreateItem.
  ///
  /// In en, this message translates to:
  /// **'Create an item instead'**
  String get unitVariesCreateItem;

  /// No description provided for @unitVariesInsteadBody.
  ///
  /// In en, this message translates to:
  /// **'Add \"Biscuit packet\" as its own item, counted in pieces. Then two packets is two of that item, and Alaya can price and track them properly.'**
  String get unitVariesInsteadBody;

  /// No description provided for @unitVariesInsteadTitle.
  ///
  /// In en, this message translates to:
  /// **'Make it an item instead'**
  String get unitVariesInsteadTitle;

  /// No description provided for @unitVariesTitle.
  ///
  /// In en, this message translates to:
  /// **'Then it is not a unit'**
  String get unitVariesTitle;

  /// ARCH_1 §5.3 explained by consequence rather than by quoting the rule. This is what makes the alternative obviously better instead of merely mandated.
  ///
  /// In en, this message translates to:
  /// **'A unit has to be the same amount every time. One packet of biscuits and one packet of rice are different weights, so Alaya could not add two packets together or work out what one cost.'**
  String get unitVariesWhy;

  /// No description provided for @unitsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a unit'**
  String get unitsAdd;

  /// ARCH_1 §5.3 and Law L8, stated where somebody about to add a unit reads it before trying rather than as a refusal afterwards.
  ///
  /// In en, this message translates to:
  /// **'Weight, volume and count are the only three kinds there are. Alaya never converts between them, so a kilo can never become a litre by accident.'**
  String get unitsCategoriesFixedNote;

  /// No description provided for @unitsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete this unit'**
  String get unitsDelete;

  /// The R18 failure from the other direction: a quantity whose unit has gone cannot be converted or valued.
  ///
  /// In en, this message translates to:
  /// **'Anything already bought in this unit keeps its quantity, but that quantity would no longer be readable. Only delete a unit you have not used.'**
  String get unitsDeleteConfirmBody;

  /// No description provided for @unitsDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this unit?'**
  String get unitsDeleteConfirmTitle;

  /// No description provided for @unitsDeleteHelp.
  ///
  /// In en, this message translates to:
  /// **'Only possible while nothing is measured in it.'**
  String get unitsDeleteHelp;

  /// No description provided for @unitsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Unit deleted'**
  String get unitsDeleted;

  /// No description provided for @unitsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Alaya ships with the common ones. Add one if you measure something differently.'**
  String get unitsEmptyBody;

  /// No description provided for @unitsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No units'**
  String get unitsEmptyTitle;

  /// No description provided for @unitsLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading units…'**
  String get unitsLoading;

  /// No description provided for @unitsMissingBody.
  ///
  /// In en, this message translates to:
  /// **'It may have been deleted. Go back and pick another.'**
  String get unitsMissingBody;

  /// No description provided for @unitsMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'That unit is not here'**
  String get unitsMissingTitle;

  /// No description provided for @unitsSaved.
  ///
  /// In en, this message translates to:
  /// **'Unit saved'**
  String get unitsSaved;

  /// No description provided for @unitsSystemChip.
  ///
  /// In en, this message translates to:
  /// **'Built in'**
  String get unitsSystemChip;

  /// The precision matters to the reader: JPY has none, so an amount typed as 1200 is ¥1,200 and not ¥12.00.
  ///
  /// In en, this message translates to:
  /// **'{symbol} · {digits, plural, =0{no decimal places} =1{1 decimal place} other{{digits} decimal places}}'**
  String currenciesRowSubtitle(String symbol, int digits);

  /// A currency row: the code first, because it is what the pickers show.
  ///
  /// In en, this message translates to:
  /// **'{code} · {name}'**
  String currenciesRowTitle(String code, String name);

  /// Names the file, because a backup the user cannot identify later is one they will not trust when they need it (ARCH_3 §3.4).
  ///
  /// In en, this message translates to:
  /// **'Backup saved as {fileName}'**
  String dataExportDone(String fileName);

  /// The countdown ticks. Formatted in Dart as m:ss, because a plural on "second" cannot express 1:05.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again in {time}'**
  String lockThrottled(String time);

  /// No description provided for @onboardingCurrencyChip.
  ///
  /// In en, this message translates to:
  /// **'{code} {symbol}'**
  String onboardingCurrencyChip(String code, String symbol);

  /// Words and a count rather than dots: the one question people abandon a setup flow over is how long it will take.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of {total}'**
  String onboardingStepOf(int step, int total);

  /// No description provided for @pinSetupLength.
  ///
  /// In en, this message translates to:
  /// **'{length} digits'**
  String pinSetupLength(int length);

  /// The word is passed in from DataTransferPort.eraseConfirmationWord and is deliberately not translated, so a support article can tell anyone what to type.
  ///
  /// In en, this message translates to:
  /// **'Type {word} to confirm'**
  String recoveryTypeToConfirm(String word);

  /// No description provided for @securityAutoEraseBody.
  ///
  /// In en, this message translates to:
  /// **'When on, {count} wrong PIN attempts in a row will delete everything on this device.'**
  String securityAutoEraseBody(int count);

  /// The scary confirm names the number. A generic "are you sure?" would not earn consent to a setting that destroys a household’s records.
  ///
  /// In en, this message translates to:
  /// **'After {count} failed attempts, every account, transaction and item on this device is deleted. There is no undo, and no copy unless you have made a backup.'**
  String securityAutoEraseConfirmBody(int count);

  /// Stated rather than configurable in 8A: autoLockDelay is a constant, and a picker writing a setting nothing reads would be a dead control.
  ///
  /// In en, this message translates to:
  /// **'Locks again after {seconds} seconds in the background.'**
  String securityAutoLockBody(int seconds);

  /// Archived accounts included, because this row is the only way to reach one and restore it.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No accounts} =1{1 account} other{{count} accounts}}'**
  String settingsAccountCount(int count);

  /// No description provided for @settingsCurrencyCount.
  ///
  /// In en, this message translates to:
  /// **'{enabled} of {total} enabled'**
  String settingsCurrencyCount(int enabled, int total);

  /// No description provided for @settingsPayeeCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No payees} =1{1 payee} other{{count} payees}}'**
  String settingsPayeeCount(int count);

  /// No description provided for @settingsPaymentMethodCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No payment methods} =1{1 payment method} other{{count} payment methods}}'**
  String settingsPaymentMethodCount(int count);

  /// No description provided for @settingsTagCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No tags} =1{1 tag} other{{count} tags}}'**
  String settingsTagCount(int count);

  /// No description provided for @settingsUnitCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No units} =1{1 unit} other{{count} units}}'**
  String settingsUnitCount(int count);

  /// The condition for being a unit at all. Somebody who reads this and cannot meet it has found the "make it an item" path.
  ///
  /// In en, this message translates to:
  /// **'One of this unit has to be the same number of {base} every time.'**
  String unitFactorHelp(String base);

  /// Asked in base units, never in the stored thousandths — reproducing that arithmetic is what ARCH_4 R18 got wrong three times.
  ///
  /// In en, this message translates to:
  /// **'How many {base} is one {unit}?'**
  String unitFactorQuestion(String base, String unit);

  /// What the unit is, assembled from the stored thousandths so the reader never meets them.
  ///
  /// In en, this message translates to:
  /// **'1 {code} = {amount} {base}'**
  String unitsEquals(String code, String amount, String base);

  /// No description provided for @unitsRowTitle.
  ///
  /// In en, this message translates to:
  /// **'{name} ({code})'**
  String unitsRowTitle(String name, String code);

  /// No description provided for @attachmentsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add an attachment'**
  String get attachmentsAdd;

  /// No description provided for @attachmentsAddFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be attached'**
  String get attachmentsAddFailed;

  /// No description provided for @attachmentsAdded.
  ///
  /// In en, this message translates to:
  /// **'Attached'**
  String get attachmentsAdded;

  /// Not "take a photo": capture needs image_picker, which ARCH_1 §7 does not pin.
  ///
  /// In en, this message translates to:
  /// **'Choose a photo'**
  String get attachmentsChoosePhoto;

  /// No description provided for @attachmentsDelete.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get attachmentsDelete;

  /// No description provided for @attachmentsDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The file is deleted from this phone. Backups you have already made still contain it.'**
  String get attachmentsDeleteConfirmBody;

  /// No description provided for @attachmentsDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove this attachment?'**
  String get attachmentsDeleteConfirmTitle;

  /// No description provided for @attachmentsDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be removed'**
  String get attachmentsDeleteFailed;

  /// No description provided for @attachmentsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Attachment removed'**
  String get attachmentsDeleted;

  /// No description provided for @attachmentsMissing.
  ///
  /// In en, this message translates to:
  /// **'That file is missing from this phone.'**
  String get attachmentsMissing;

  /// No description provided for @attachmentsNone.
  ///
  /// In en, this message translates to:
  /// **'Nothing attached'**
  String get attachmentsNone;

  /// No description provided for @attachmentsOpen.
  ///
  /// In en, this message translates to:
  /// **'Open attachment'**
  String get attachmentsOpen;

  /// No description provided for @attachmentsStoredLocally.
  ///
  /// In en, this message translates to:
  /// **'Kept on this phone only, and included in your backups.'**
  String get attachmentsStoredLocally;

  /// No description provided for @backupConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Make the backup'**
  String get backupConfirmAction;

  /// No description provided for @backupConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Make a backup?'**
  String get backupConfirmTitle;

  /// No description provided for @backupDone.
  ///
  /// In en, this message translates to:
  /// **'Backup saved'**
  String get backupDone;

  /// No description provided for @backupFailed.
  ///
  /// In en, this message translates to:
  /// **'The backup could not be made'**
  String get backupFailed;

  /// No description provided for @backupForget.
  ///
  /// In en, this message translates to:
  /// **'Forget'**
  String get backupForget;

  /// Says what does *not* happen: "remove" over a backup reads as deleting the file.
  ///
  /// In en, this message translates to:
  /// **'This removes it from the list only. The backup file itself stays wherever you put it — Alaya cannot reach into your Drive or your chats.'**
  String get backupForgetConfirmBody;

  /// No description provided for @backupForgetConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Forget this entry?'**
  String get backupForgetConfirmTitle;

  /// No description provided for @backupForgetFailed.
  ///
  /// In en, this message translates to:
  /// **'That entry could not be removed'**
  String get backupForgetFailed;

  /// No description provided for @backupForgotten.
  ///
  /// In en, this message translates to:
  /// **'Entry removed'**
  String get backupForgotten;

  /// Says where, because a backup sitting on the device it protects is not a backup.
  ///
  /// In en, this message translates to:
  /// **'Make one now, and keep it somewhere that is not this phone.'**
  String get backupHistoryEmptyBody;

  /// No description provided for @backupHistoryEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No backups yet'**
  String get backupHistoryEmptyTitle;

  /// No description provided for @backupHistoryHeader.
  ///
  /// In en, this message translates to:
  /// **'Backups you have made'**
  String get backupHistoryHeader;

  /// No description provided for @backupHistoryLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading your backups…'**
  String get backupHistoryLoading;

  /// No description provided for @backupMakeHeader.
  ///
  /// In en, this message translates to:
  /// **'Make a backup'**
  String get backupMakeHeader;

  /// No description provided for @backupRestoreBody.
  ///
  /// In en, this message translates to:
  /// **'Merge a backup into what you have, or replace everything with it.'**
  String get backupRestoreBody;

  /// No description provided for @backupRestoreHeader.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get backupRestoreHeader;

  /// No description provided for @backupRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore from a backup'**
  String get backupRestoreTitle;

  /// No description provided for @backupSaveBody.
  ///
  /// In en, this message translates to:
  /// **'Choose where to put it. Alaya needs no storage permission — you pick the folder.'**
  String get backupSaveBody;

  /// No description provided for @backupSaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Save a copy'**
  String get backupSaveTitle;

  /// No description provided for @backupShareBody.
  ///
  /// In en, this message translates to:
  /// **'Send it to WhatsApp, Drive, or anywhere else.'**
  String get backupShareBody;

  /// No description provided for @backupShareTitle.
  ///
  /// In en, this message translates to:
  /// **'Share a copy'**
  String get backupShareTitle;

  /// No description provided for @backupTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backupTitle;

  /// No description provided for @reminderKindExpiry.
  ///
  /// In en, this message translates to:
  /// **'Things going off'**
  String get reminderKindExpiry;

  /// No description provided for @reminderKindExpiryHelp.
  ///
  /// In en, this message translates to:
  /// **'Food and medicine reaching their use-by date.'**
  String get reminderKindExpiryHelp;

  /// No description provided for @reminderKindLowStock.
  ///
  /// In en, this message translates to:
  /// **'Running low'**
  String get reminderKindLowStock;

  /// The row exists because the enum does; the help says why it is not in the digest.
  ///
  /// In en, this message translates to:
  /// **'Not offered as a reminder: being low on something has no date, so it would arrive every morning until you shopped.'**
  String get reminderKindLowStockHelp;

  /// No description provided for @reminderKindRecurring.
  ///
  /// In en, this message translates to:
  /// **'Bills and subscriptions'**
  String get reminderKindRecurring;

  /// No description provided for @reminderKindRecurringHelp.
  ///
  /// In en, this message translates to:
  /// **'When a recurring payment falls due.'**
  String get reminderKindRecurringHelp;

  /// No description provided for @reminderKindService.
  ///
  /// In en, this message translates to:
  /// **'Appliance servicing'**
  String get reminderKindService;

  /// No description provided for @reminderKindServiceHelp.
  ///
  /// In en, this message translates to:
  /// **'When something is due for its next service.'**
  String get reminderKindServiceHelp;

  /// No description provided for @reminderKindWarranty.
  ///
  /// In en, this message translates to:
  /// **'Warranties ending'**
  String get reminderKindWarranty;

  /// No description provided for @reminderKindWarrantyHelp.
  ///
  /// In en, this message translates to:
  /// **'Before a warranty runs out, while you can still use it.'**
  String get reminderKindWarrantyHelp;

  /// Names the place. "Notifications are blocked" without saying where is a dead end.
  ///
  /// In en, this message translates to:
  /// **'Notifications are turned off for Alaya. Turn them on in your phone’s Settings › Apps › Alaya › Notifications.'**
  String get remindersBlocked;

  /// No description provided for @remindersDenied.
  ///
  /// In en, this message translates to:
  /// **'Alaya needs permission to send notifications.'**
  String get remindersDenied;

  /// ARCH_3 §7’s "fewer, better notifications", stated before the toggles so somebody knows what turning one on means.
  ///
  /// In en, this message translates to:
  /// **'Alaya sends one message a day about what is coming up — not a notification for every item.'**
  String get remindersDigestExplainer;

  /// No description provided for @remindersDigestRow.
  ///
  /// In en, this message translates to:
  /// **'Daily summary'**
  String get remindersDigestRow;

  /// No description provided for @remindersKindsHeader.
  ///
  /// In en, this message translates to:
  /// **'What to remind me about'**
  String get remindersKindsHeader;

  /// No description provided for @remindersLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading your reminders…'**
  String get remindersLoading;

  /// Explains rather than apologises: empty is the normal state with everything off.
  ///
  /// In en, this message translates to:
  /// **'Turn on a reminder above and Alaya will show what it has planned here.'**
  String get remindersNoneScheduledBody;

  /// No description provided for @remindersNoneScheduledTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing scheduled'**
  String get remindersNoneScheduledTitle;

  /// No description provided for @remindersScheduledHeader.
  ///
  /// In en, this message translates to:
  /// **'Currently scheduled'**
  String get remindersScheduledHeader;

  /// No description provided for @remindersTimeHeader.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get remindersTimeHeader;

  /// No description provided for @remindersTimeSaved.
  ///
  /// In en, this message translates to:
  /// **'Reminder time changed'**
  String get remindersTimeSaved;

  /// No description provided for @remindersTimeTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily summary time'**
  String get remindersTimeTitle;

  /// No description provided for @remindersTitle.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get remindersTitle;

  /// No description provided for @remindersToggleFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be changed'**
  String get remindersToggleFailed;

  /// No description provided for @restoreApplyMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge the backup'**
  String get restoreApplyMerge;

  /// No description provided for @restoreApplyReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace everything'**
  String get restoreApplyReplace;

  /// No description provided for @restoreChooseAnother.
  ///
  /// In en, this message translates to:
  /// **'Choose another file'**
  String get restoreChooseAnother;

  /// No description provided for @restoreChooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose a file'**
  String get restoreChooseFile;

  /// No description provided for @restoreChosenHeader.
  ///
  /// In en, this message translates to:
  /// **'Chosen file'**
  String get restoreChosenHeader;

  /// No description provided for @restoreContinueReplace.
  ///
  /// In en, this message translates to:
  /// **'Continue to replace'**
  String get restoreContinueReplace;

  /// No description provided for @restoreDone.
  ///
  /// In en, this message translates to:
  /// **'Restored'**
  String get restoreDone;

  /// ARCH_3 §3.2’s last line, on the one screen where somebody might expect otherwise. Shown at all three stages.
  ///
  /// In en, this message translates to:
  /// **'Your PIN is never restored. It is kept outside the backup, so opening someone else’s backup can never change who can open this app.'**
  String get restoreLockNotRestored;

  /// The default, and the description says why: merge keeps rows the backup does not have.
  ///
  /// In en, this message translates to:
  /// **'Adds what the backup has and updates what is newer. Nothing you have now is lost.'**
  String get restoreMergeBody;

  /// No description provided for @restoreMergeTitle.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get restoreMergeTitle;

  /// No description provided for @restoreModeHeader.
  ///
  /// In en, this message translates to:
  /// **'How should it be applied?'**
  String get restoreModeHeader;

  /// No description provided for @restoreNotADatabase.
  ///
  /// In en, this message translates to:
  /// **'That file is not an Alaya backup.'**
  String get restoreNotADatabase;

  /// No description provided for @restorePickBody.
  ///
  /// In en, this message translates to:
  /// **'Choose a backup file. Alaya will check it before anything changes.'**
  String get restorePickBody;

  /// No description provided for @restoreReplaceBody.
  ///
  /// In en, this message translates to:
  /// **'Throws away what is on this phone and uses the backup instead.'**
  String get restoreReplaceBody;

  /// No description provided for @restoreReplaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace everything'**
  String get restoreReplaceTitle;

  /// No description provided for @restoreReplaceWarning.
  ///
  /// In en, this message translates to:
  /// **'Everything currently on this phone will be thrown away and replaced by the backup. Anything recorded since that backup was made will be gone.'**
  String get restoreReplaceWarning;

  /// No description provided for @restoreRollbackAvailable.
  ///
  /// In en, this message translates to:
  /// **'Restored the wrong file? You can put your previous data back.'**
  String get restoreRollbackAvailable;

  /// Said before the typed confirmation, because somebody who knows there is a way back reads the warning as information rather than a threat.
  ///
  /// In en, this message translates to:
  /// **'Alaya takes a snapshot of your current data first, so you can undo this straight afterwards.'**
  String get restoreRollbackPromise;

  /// No description provided for @restoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restoreTitle;

  /// No description provided for @restoreUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo the replace'**
  String get restoreUndo;

  /// Says what happened rather than showing a button that cannot work: without consent settled, no ad is requested at all.
  ///
  /// In en, this message translates to:
  /// **'Adverts need a choice about personalisation that could not be loaded right now. Nothing has been requested.'**
  String get supportConsentUnavailable;

  /// No description provided for @supportIntro.
  ///
  /// In en, this message translates to:
  /// **'Alaya is free, works offline, and has no accounts to sign up for. If it is useful to you, there are two ways to help.'**
  String get supportIntro;

  /// No description provided for @supportLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get supportLoading;

  /// No description provided for @supportNoAd.
  ///
  /// In en, this message translates to:
  /// **'No advert available right now'**
  String get supportNoAd;

  /// Keeps this a tip rather than a paywall wearing a friendly label, and says so where somebody decides.
  ///
  /// In en, this message translates to:
  /// **'Nothing here unlocks anything. There are no paid features — the whole app is already yours.'**
  String get supportNoPaidFeatures;

  /// No description provided for @supportThanks.
  ///
  /// In en, this message translates to:
  /// **'Thank you. That genuinely helps.'**
  String get supportThanks;

  /// No description provided for @supportTipBody.
  ///
  /// In en, this message translates to:
  /// **'A one-time thank-you through the Play Store. It is not a subscription.'**
  String get supportTipBody;

  /// No description provided for @supportTipHeader.
  ///
  /// In en, this message translates to:
  /// **'Leave a tip'**
  String get supportTipHeader;

  /// No description provided for @supportTipUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Tips are not available on this device right now.'**
  String get supportTipUnavailable;

  /// No description provided for @supportTitle.
  ///
  /// In en, this message translates to:
  /// **'Support Alaya'**
  String get supportTitle;

  /// No description provided for @supportWatchAction.
  ///
  /// In en, this message translates to:
  /// **'Watch an advert'**
  String get supportWatchAction;

  /// True by construction: one file imports the SDK and only this screen starts it.
  ///
  /// In en, this message translates to:
  /// **'One advert, when you choose to. Alaya never shows one anywhere else in the app.'**
  String get supportWatchBody;

  /// No description provided for @supportWatchHeader.
  ///
  /// In en, this message translates to:
  /// **'Watch a short advert'**
  String get supportWatchHeader;

  /// No description provided for @trashDeletedOn.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get trashDeletedOn;

  /// No description provided for @trashEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Things you delete are kept here for 30 days before they go for good.'**
  String get trashEmptyBody;

  /// No description provided for @trashEmptyNow.
  ///
  /// In en, this message translates to:
  /// **'Empty now'**
  String get trashEmptyNow;

  /// The only hard delete a user can reach, so the body says it plainly.
  ///
  /// In en, this message translates to:
  /// **'Everything in the trash is deleted permanently. This is not the trash — there is nowhere left for it to go.'**
  String get trashEmptyNowConfirmBody;

  /// No description provided for @trashEmptyNowConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Empty the trash?'**
  String get trashEmptyNowConfirmTitle;

  /// No description provided for @trashEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'The trash is empty'**
  String get trashEmptyTitle;

  /// Every row says when it goes: a trash that silently empties is one people stop trusting.
  ///
  /// In en, this message translates to:
  /// **'· kept for 30 days'**
  String get trashGoesOn;

  /// No description provided for @trashKindAsset.
  ///
  /// In en, this message translates to:
  /// **'Appliances'**
  String get trashKindAsset;

  /// No description provided for @trashKindItem.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get trashKindItem;

  /// No description provided for @trashKindPayee.
  ///
  /// In en, this message translates to:
  /// **'Payees'**
  String get trashKindPayee;

  /// No description provided for @trashKindRecurring.
  ///
  /// In en, this message translates to:
  /// **'Recurring'**
  String get trashKindRecurring;

  /// No description provided for @trashKindShoppingList.
  ///
  /// In en, this message translates to:
  /// **'Shopping lists'**
  String get trashKindShoppingList;

  /// No description provided for @trashKindTag.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get trashKindTag;

  /// No description provided for @trashKindTransaction.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get trashKindTransaction;

  /// No description provided for @trashLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading the trash…'**
  String get trashLoading;

  /// No description provided for @trashNoMatchBody.
  ///
  /// In en, this message translates to:
  /// **'Remove a filter to see the rest.'**
  String get trashNoMatchBody;

  /// No description provided for @trashNoMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches that filter'**
  String get trashNoMatchTitle;

  /// No description provided for @trashPurgeConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'It will not go back to the trash. There is no undo.'**
  String get trashPurgeConfirmBody;

  /// No description provided for @trashPurgeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this for good?'**
  String get trashPurgeConfirmTitle;

  /// No description provided for @trashPurgeFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be deleted'**
  String get trashPurgeFailed;

  /// No description provided for @trashPurgeOne.
  ///
  /// In en, this message translates to:
  /// **'Delete for good'**
  String get trashPurgeOne;

  /// No description provided for @trashPurgedOne.
  ///
  /// In en, this message translates to:
  /// **'Deleted for good'**
  String get trashPurgedOne;

  /// No description provided for @trashRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get trashRestore;

  /// No description provided for @trashRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be restored'**
  String get trashRestoreFailed;

  /// No description provided for @trashRestored.
  ///
  /// In en, this message translates to:
  /// **'Restored'**
  String get trashRestored;

  /// No description provided for @trashTitle.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get trashTitle;

  /// Names the file, because a backup you cannot identify later is one you will not trust when you need it.
  ///
  /// In en, this message translates to:
  /// **'Backup saved as {fileName}'**
  String backupDoneNamed(String fileName);

  /// The unit changes with the magnitude, so the number is formatted in Dart — a translator cannot choose between KB and MB inside a placeholder.
  ///
  /// In en, this message translates to:
  /// **'· {size}'**
  String backupHistorySize(String size);

  /// No description provided for @remindersTimeBody.
  ///
  /// In en, this message translates to:
  /// **'Sent at {time} each day'**
  String remindersTimeBody(String time);

  /// No description provided for @restoreDoneDetail.
  ///
  /// In en, this message translates to:
  /// **'{tables, plural, =1{1 table restored} other{{tables} tables restored}}'**
  String restoreDoneDetail(int tables);

  /// ARCH_3 §3.2’s gate, stated with both numbers. A refusal without them is one nobody can act on.
  ///
  /// In en, this message translates to:
  /// **'That backup is from a newer version of Alaya (version {backup}) than this app understands (version {app}). Update Alaya and try again.'**
  String restoreNewerSchema(int backup, int app);

  /// The word is not translated, so a support article can tell anyone what to type.
  ///
  /// In en, this message translates to:
  /// **'Type {word} to confirm'**
  String restoreTypeToConfirm(String word);

  /// The store’s own formatted price, never reformatted: Play localises it for the user’s account, which need not match this app’s home currency.
  ///
  /// In en, this message translates to:
  /// **'Leave a tip · {price}'**
  String supportTipAction(String price);

  /// "For good" rather than "deleted", because this is the one hard delete in the app.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nothing to delete} =1{1 item deleted for good} other{{count} items deleted for good}}'**
  String trashPurged(int count);

  /// No description provided for @dataBackupRowBody.
  ///
  /// In en, this message translates to:
  /// **'Save a copy, share it, or restore from one.'**
  String get dataBackupRowBody;

  /// No description provided for @dataTrashRowBody.
  ///
  /// In en, this message translates to:
  /// **'Things you delete are kept here for 30 days.'**
  String get dataTrashRowBody;

  /// No description provided for @settingsRemindersHelp.
  ///
  /// In en, this message translates to:
  /// **'One daily summary of what is coming up.'**
  String get settingsRemindersHelp;

  /// Says on the row itself that this is not a paywall, so the entry cannot read as one.
  ///
  /// In en, this message translates to:
  /// **'Optional, and nothing here unlocks anything.'**
  String get settingsSupportHelp;

  /// No description provided for @settingsTrashCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nothing in the trash} =1{1 item} other{{count} items}}'**
  String settingsTrashCount(int count);

  /// The app bar action. Says what the tap does, because a joined-hands icon alone does not — and no advert is fetched until it is pressed.
  ///
  /// In en, this message translates to:
  /// **'Watch an advert to support Alaya'**
  String get supportWatchTooltip;

  /// A ledger row spoken as one thing (ARCH_5 §6). The comma is the pause a screen reader takes, which is why it is punctuation rather than a word.
  ///
  /// In en, this message translates to:
  /// **'{title}, {amount}'**
  String ledgerRowSemantics(String title, String amount);

  /// The same, with the row’s metadata line — an account, a payment method or a review flag.
  ///
  /// In en, this message translates to:
  /// **'{title}, {amount}, {detail}'**
  String ledgerRowSemanticsDetailed(String title, String amount, String detail);

  /// No description provided for @navRecipes.
  ///
  /// In en, this message translates to:
  /// **'Recipes'**
  String get navRecipes;

  /// The dashboard tile. A zero is worded rather than shown, like every other tile — "0 you can make" is a figure to interpret, "nothing you can make" is an answer.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nothing you can make} =1{1 you can make} other{{count} you can make}}'**
  String moduleRecipes(int count);

  /// No description provided for @recipeSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search recipes'**
  String get recipeSearchHint;

  /// No description provided for @recipeFilterCookable.
  ///
  /// In en, this message translates to:
  /// **'Can cook now'**
  String get recipeFilterCookable;

  /// No description provided for @recipeFilterFavourites.
  ///
  /// In en, this message translates to:
  /// **'Favourites'**
  String get recipeFilterFavourites;

  /// No description provided for @recipeLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading your recipes…'**
  String get recipeLoading;

  /// No description provided for @recipeEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No recipes yet'**
  String get recipeEmptyTitle;

  /// No description provided for @recipeEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add one and Alaya will tell you when you have everything for it.'**
  String get recipeEmptyBody;

  /// No description provided for @recipeNoMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches'**
  String get recipeNoMatchTitle;

  /// No description provided for @recipeNoMatchBody.
  ///
  /// In en, this message translates to:
  /// **'Clear the filters to see every recipe.'**
  String get recipeNoMatchBody;

  /// No description provided for @recipeServes.
  ///
  /// In en, this message translates to:
  /// **'Serves {count}'**
  String recipeServes(int count);

  /// No description provided for @recipeServesAndTime.
  ///
  /// In en, this message translates to:
  /// **'Serves {count} · {minutes} min'**
  String recipeServesAndTime(int count, int minutes);

  /// No description provided for @recipeReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get recipeReady;

  /// No description provided for @recipeShortBy.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 short} other{{count} short}}'**
  String recipeShortBy(int count);

  /// No description provided for @recipeMissingCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 missing} other{{count} missing}}'**
  String recipeMissingCount(int count);

  /// Not "cannot cook". The engine could not judge an ingredient — untracked, or measured in a unit that cannot be compared to what the item is counted in. Saying so is the point of the module.
  ///
  /// In en, this message translates to:
  /// **'Can\'t tell'**
  String get recipeUncheckable;

  /// No description provided for @recipeNoIngredients.
  ///
  /// In en, this message translates to:
  /// **'No ingredients'**
  String get recipeNoIngredients;

  /// No description provided for @recipeDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Recipe'**
  String get recipeDetailTitle;

  /// No description provided for @recipeGoneTitle.
  ///
  /// In en, this message translates to:
  /// **'That recipe is gone'**
  String get recipeGoneTitle;

  /// No description provided for @recipeGoneBody.
  ///
  /// In en, this message translates to:
  /// **'It may have been deleted. Check the trash if you want it back.'**
  String get recipeGoneBody;

  /// No description provided for @recipeServingsLabel.
  ///
  /// In en, this message translates to:
  /// **'Servings'**
  String get recipeServingsLabel;

  /// No description provided for @recipeServingsFewer.
  ///
  /// In en, this message translates to:
  /// **'Fewer servings'**
  String get recipeServingsFewer;

  /// No description provided for @recipeServingsMore.
  ///
  /// In en, this message translates to:
  /// **'More servings'**
  String get recipeServingsMore;

  /// No description provided for @recipeIngredientsHeader.
  ///
  /// In en, this message translates to:
  /// **'Ingredients'**
  String get recipeIngredientsHeader;

  /// No description provided for @recipeMethodHeader.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get recipeMethodHeader;

  /// No description provided for @recipeNotesHeader.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get recipeNotesHeader;

  /// No description provided for @recipeCheckingStock.
  ///
  /// In en, this message translates to:
  /// **'Checking what you have…'**
  String get recipeCheckingStock;

  /// No description provided for @recipeStepMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String recipeStepMinutes(int minutes);

  /// No description provided for @recipeCookAction.
  ///
  /// In en, this message translates to:
  /// **'Cook this'**
  String get recipeCookAction;

  /// No description provided for @recipeCooking.
  ///
  /// In en, this message translates to:
  /// **'Cooking…'**
  String get recipeCooking;

  /// No description provided for @recipeCooked.
  ///
  /// In en, this message translates to:
  /// **'Cooked'**
  String get recipeCooked;

  /// No description provided for @recipeCookedDeducted.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Cooked. Nothing was deducted} =1{Cooked. 1 ingredient deducted} other{Cooked. {count} ingredients deducted}}'**
  String recipeCookedDeducted(int count);

  /// No description provided for @recipeCookFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be cooked'**
  String get recipeCookFailed;

  /// Said before cooking, not after. A user who learns afterwards that two ingredients were skipped has already been given a wrong impression of their stock.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 ingredient will not be deducted — nothing tracks it} other{{count} ingredients will not be deducted — nothing tracks them}}'**
  String recipeCookWillSkip(int count);

  /// No description provided for @recipeShortfall.
  ///
  /// In en, this message translates to:
  /// **'Not enough on hand'**
  String get recipeShortfall;

  /// No description provided for @recipeNoneLeft.
  ///
  /// In en, this message translates to:
  /// **'None left'**
  String get recipeNoneLeft;

  /// No description provided for @recipeUnitMismatch.
  ///
  /// In en, this message translates to:
  /// **'Measured differently from how you track it — can\'t compare'**
  String get recipeUnitMismatch;

  /// No description provided for @recipeNotTracked.
  ///
  /// In en, this message translates to:
  /// **'Not tracked'**
  String get recipeNotTracked;

  /// No description provided for @recipeLinkedIngredient.
  ///
  /// In en, this message translates to:
  /// **'Ingredient'**
  String get recipeLinkedIngredient;

  /// No description provided for @recipeAddAction.
  ///
  /// In en, this message translates to:
  /// **'New recipe'**
  String get recipeAddAction;

  /// No description provided for @recipeNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New recipe'**
  String get recipeNewTitle;

  /// No description provided for @recipeEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit recipe'**
  String get recipeEditTitle;

  /// No description provided for @recipeNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get recipeNameLabel;

  /// No description provided for @recipePrepLabel.
  ///
  /// In en, this message translates to:
  /// **'Prep min'**
  String get recipePrepLabel;

  /// No description provided for @recipeCookLabel.
  ///
  /// In en, this message translates to:
  /// **'Cook min'**
  String get recipeCookLabel;

  /// No description provided for @recipeAddIngredient.
  ///
  /// In en, this message translates to:
  /// **'Add ingredient'**
  String get recipeAddIngredient;

  /// No description provided for @recipeAddStep.
  ///
  /// In en, this message translates to:
  /// **'Add step'**
  String get recipeAddStep;

  /// No description provided for @recipeIngredientLabel.
  ///
  /// In en, this message translates to:
  /// **'Ingredient'**
  String get recipeIngredientLabel;

  /// No description provided for @recipeQuantityLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get recipeQuantityLabel;

  /// No description provided for @recipeOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Optional — will not stop you cooking'**
  String get recipeOptionalLabel;

  /// No description provided for @recipeRemoveIngredient.
  ///
  /// In en, this message translates to:
  /// **'Remove ingredient'**
  String get recipeRemoveIngredient;

  /// No description provided for @recipeRemoveStep.
  ///
  /// In en, this message translates to:
  /// **'Remove step'**
  String get recipeRemoveStep;

  /// No description provided for @recipeStepLabel.
  ///
  /// In en, this message translates to:
  /// **'Step {number}'**
  String recipeStepLabel(int number);

  /// No description provided for @recipeFavouriteToggle.
  ///
  /// In en, this message translates to:
  /// **'Pin this recipe'**
  String get recipeFavouriteToggle;

  /// No description provided for @recipeSaved.
  ///
  /// In en, this message translates to:
  /// **'Recipe saved'**
  String get recipeSaved;

  /// No description provided for @recipeSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'That recipe could not be saved'**
  String get recipeSaveFailed;

  /// Shown under an ingredient with no catalogue link. States the consequence rather than scolding: an unlinked ingredient is fine, it simply cannot be checked against stock or deducted.
  ///
  /// In en, this message translates to:
  /// **'Not linked to inventory — pick from the list to track it'**
  String get recipeNotLinkedHelp;

  /// Placeholder in the ingredient quantity field.
  ///
  /// In en, this message translates to:
  /// **'Leave blank for \"to taste\"'**
  String get recipeQuantityHint;

  /// No description provided for @sectionRecipeMeasures.
  ///
  /// In en, this message translates to:
  /// **'Recipe measures'**
  String get sectionRecipeMeasures;

  /// No description provided for @labelDensity.
  ///
  /// In en, this message translates to:
  /// **'Weight of 1 ml'**
  String get labelDensity;

  /// Three anchors rather than an explanation. A number nobody can estimate is a field nobody fills.
  ///
  /// In en, this message translates to:
  /// **'Lets a recipe measure this in spoons or cups. Water is 1, oil about 0.92, honey about 1.4.'**
  String get densityHelp;

  /// No description provided for @suffixGramsPerMl.
  ///
  /// In en, this message translates to:
  /// **'g'**
  String get suffixGramsPerMl;

  /// No description provided for @labelPieceWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight of 1 piece'**
  String get labelPieceWeight;

  /// No description provided for @pieceWeightHelp.
  ///
  /// In en, this message translates to:
  /// **'Lets a recipe say \"2 of these\" and still know how much to take.'**
  String get pieceWeightHelp;

  /// No description provided for @suffixGrams.
  ///
  /// In en, this message translates to:
  /// **'g'**
  String get suffixGrams;

  /// No description provided for @labelGramsPerTbsp.
  ///
  /// In en, this message translates to:
  /// **'1 tablespoon weighs'**
  String get labelGramsPerTbsp;

  /// Four anchors a cook can recognise, and a sentence saying the one number covers the other measures — so nobody goes looking for a teaspoon field that does not exist.
  ///
  /// In en, this message translates to:
  /// **'Flour about 8 g, sugar 12 g, oil 14 g, honey 21 g. Alaya works out teaspoons and cups from this.'**
  String get gramsPerTbspHelp;

  /// Three examples instead of an instruction. A cook sees at a glance that fractions are accepted, which no wording would convey as quickly.
  ///
  /// In en, this message translates to:
  /// **'2, 1/2, 1 1/2'**
  String get recipeAmountHint;

  /// Shown when a weight-measured item has no tablespoon weight, so volume units are absent from the picker. Names the exact field rather than saying the option is unavailable — the fix is one screen away and the user should know where.
  ///
  /// In en, this message translates to:
  /// **'To measure this in spoons or cups, set \"1 tablespoon weighs\" on the item.'**
  String get recipeSpoonsNeedWeight;

  /// Shown only when the unit is a spoon or a cup. Three examples say "fractions work" faster than any sentence — and the tappable sizes beside it mean most cooks never type at all.
  ///
  /// In en, this message translates to:
  /// **'1/2, 1, 1 1/2'**
  String get recipeAmountHintVessel;

  /// Shown for grams, millilitres, pieces. Nobody writes "half a milligram", and offering fractions there is what made the field confusing.
  ///
  /// In en, this message translates to:
  /// **'200'**
  String get recipeAmountHintPlain;

  /// Said the moment a spoon is chosen for an item that cannot convert it. Names the field, not the limitation: the fix is one screen away and the cook should know where.
  ///
  /// In en, this message translates to:
  /// **'To measure {item} in spoons or cups, set \"1 tablespoon weighs\" on the item.'**
  String recipeNeedsTbspWeight(String item);

  /// No description provided for @recipeNeedsPieceWeight.
  ///
  /// In en, this message translates to:
  /// **'To count {item} by the piece, set \"Weight of 1 piece\" on the item.'**
  String recipeNeedsPieceWeight(String item);

  /// The line restated in the measure the shelf uses: "3 1/2 tablespoon = 51.8 ml", or "= 28 g" once the item declares a tablespoon weight. This is where a cook finds out how big a tablespoon is — for the thing in their hand, not from a table they have to apply themselves.
  ///
  /// In en, this message translates to:
  /// **'{written} = {converted}'**
  String recipeAmountReadout(String written, String converted);

  /// The one door out of a capture form. "More details" rather than "Advanced": nothing behind it is advanced — a tag and a note are ordinary things, just not needed every time. "Advanced" would suggest they are for experts and stop people opening it.
  ///
  /// In en, this message translates to:
  /// **'More details'**
  String get sectionMoreDetails;

  /// Part of the collapsed summary, so a set tag is visible without opening the section.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 tag} other{{count} tags}}'**
  String tagCount(int count);

  /// No description provided for @lineCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String lineCount(int count);

  /// Hint in the quick sheet’s note field. The question the user is actually answering, plus "(optional)" so an empty field never reads as something left undone. No label above it: a label would make it look like a required field in a sheet whose whole promise is one required field.
  ///
  /// In en, this message translates to:
  /// **'What for? (optional)'**
  String get quickAddNoteHint;

  /// Shown when reminders ARE on and the seven-day scan found nothing. The previous copy said "turn on a reminder above", which is what the user had already done — so a working feature read as a broken one.
  ///
  /// In en, this message translates to:
  /// **'Nothing due this week'**
  String get remindersNothingDueTitle;

  /// Confirms the setting is on before explaining the silence. The order matters: somebody who suspects the feature is broken needs the reassurance first.
  ///
  /// In en, this message translates to:
  /// **'Your reminders are on. Alaya looks a week ahead and there is nothing coming up yet — you will get a message the day something does.'**
  String get remindersNothingDueBody;

  /// No description provided for @remindersCheckNow.
  ///
  /// In en, this message translates to:
  /// **'Check now'**
  String get remindersCheckNow;

  /// No description provided for @remindersChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get remindersChecking;

  /// Result of a manual scan. Naming the number is what proves the scan ran.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 thing coming up} other{{count} things coming up}}'**
  String remindersFoundCount(int count);

  /// A result, not a failure — and the sentence that tells somebody their reminders work and their week is simply clear. This is the answer that was impossible to obtain before.
  ///
  /// In en, this message translates to:
  /// **'Nothing coming up in the next week'**
  String get remindersFoundNothing;

  /// Posts one notification immediately. Exists because "it is scheduled for tomorrow morning" and "the delivery path is broken" are indistinguishable by waiting, and this separates them in two seconds.
  ///
  /// In en, this message translates to:
  /// **'Send a test notification'**
  String get remindersSendTest;

  /// Says the app handed it to Android, not that it appeared. If the shade is empty after this, the notification is blocked in system settings rather than broken in the app.
  ///
  /// In en, this message translates to:
  /// **'Sent — check your notifications'**
  String get remindersTestSent;

  /// Undo snack after a swipe. One word, because the row has already gone and the undo button is the point of the message — a sentence explaining what happened would push the action off a 320dp screen.
  ///
  /// In en, this message translates to:
  /// **'Removed'**
  String get shoppingEntryDeleted;

  /// Header of the sheet behind the available-funds figure. The question the user asked by tapping, not a restatement of the label they tapped.
  ///
  /// In en, this message translates to:
  /// **'Where this comes from'**
  String get fundsBreakdownTitle;

  /// No description provided for @fundsNoAccountsTitle.
  ///
  /// In en, this message translates to:
  /// **'No accounts yet'**
  String get fundsNoAccountsTitle;

  /// No description provided for @fundsNoAccountsBody.
  ///
  /// In en, this message translates to:
  /// **'Add an account and its balance will show here.'**
  String get fundsNoAccountsBody;

  /// Shown instead of an amount when no exchange rate is available (anomaly A34). A zero would read as an empty account; this says the balance exists and is excluded.
  ///
  /// In en, this message translates to:
  /// **'Not counted'**
  String get fundsNotCounted;

  /// Explains the greyed rows. Shown only when at least one exists, so it never explains something absent.
  ///
  /// In en, this message translates to:
  /// **'Greyed accounts are excluded from your available funds.'**
  String get fundsExcludedNote;

  /// No description provided for @remindersZone.
  ///
  /// In en, this message translates to:
  /// **'Using your phone’s time zone, {zone}'**
  String remindersZone(String zone);

  /// No description provided for @remindersZoneUnknown.
  ///
  /// In en, this message translates to:
  /// **'Alaya could not work out your phone’s time zone, so the daily summary may arrive at the wrong hour. Check the date and time settings on your phone.'**
  String get remindersZoneUnknown;

  /// No description provided for @remindersOsHolding.
  ///
  /// In en, this message translates to:
  /// **'Your phone has this set and will deliver it.'**
  String get remindersOsHolding;

  /// No description provided for @remindersOsMissing.
  ///
  /// In en, this message translates to:
  /// **'Alaya has scheduled this, but your phone is not holding it. Allow Alaya to start in the background and turn off battery saver for it, then tap Check now.'**
  String get remindersOsMissing;

  /// No description provided for @recipeScaledRounding.
  ///
  /// In en, this message translates to:
  /// **'Amounts are scaled for this serving count. Anything marked ≈ is rounded to the nearest measuring spoon or cup.'**
  String get recipeScaledRounding;

  /// No description provided for @recipeUsesExpired.
  ///
  /// In en, this message translates to:
  /// **'Some of this is past its date'**
  String get recipeUsesExpired;

  /// No description provided for @recipeExpiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Use food that is past its date?'**
  String get recipeExpiredTitle;

  /// No description provided for @recipeExpiredBody.
  ///
  /// In en, this message translates to:
  /// **'{detail}\n\nAlaya will use up the good stock first and only take what it still needs from these. Check them before you cook.'**
  String recipeExpiredBody(String detail);

  /// No description provided for @recipeExpiredLine.
  ///
  /// In en, this message translates to:
  /// **'{name}: {amount} expired {date}'**
  String recipeExpiredLine(String name, String amount, String date);

  /// No description provided for @recipeExpiredMore.
  ///
  /// In en, this message translates to:
  /// **'and {count, plural, =1{1 more ingredient} other{{count} more ingredients}}'**
  String recipeExpiredMore(int count);

  /// No description provided for @recipeExpiredConfirm.
  ///
  /// In en, this message translates to:
  /// **'Cook anyway'**
  String get recipeExpiredConfirm;

  /// No description provided for @recipeCookBlockedExpired.
  ///
  /// In en, this message translates to:
  /// **'Some of what this needs is past its date.'**
  String get recipeCookBlockedExpired;

  /// No description provided for @splitSectionHeader.
  ///
  /// In en, this message translates to:
  /// **'Who owes for this'**
  String get splitSectionHeader;

  /// No description provided for @splitAdd.
  ///
  /// In en, this message translates to:
  /// **'Split with someone'**
  String get splitAdd;

  /// No description provided for @splitEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit split'**
  String get splitEdit;

  /// No description provided for @splitRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove split'**
  String get splitRemove;

  /// No description provided for @splitUnknownPerson.
  ///
  /// In en, this message translates to:
  /// **'Someone'**
  String get splitUnknownPerson;

  /// No description provided for @splitUnallocated.
  ///
  /// In en, this message translates to:
  /// **'Not assigned'**
  String get splitUnallocated;

  /// No description provided for @splitOverAllocated.
  ///
  /// In en, this message translates to:
  /// **'Over by'**
  String get splitOverAllocated;

  /// No description provided for @splitSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Split this expense'**
  String get splitSheetTitle;

  /// No description provided for @splitMethodEqual.
  ///
  /// In en, this message translates to:
  /// **'Equally'**
  String get splitMethodEqual;

  /// No description provided for @splitMethodShares.
  ///
  /// In en, this message translates to:
  /// **'By shares'**
  String get splitMethodShares;

  /// No description provided for @splitMethodPercent.
  ///
  /// In en, this message translates to:
  /// **'By percentage'**
  String get splitMethodPercent;

  /// No description provided for @splitMethodExact.
  ///
  /// In en, this message translates to:
  /// **'Exact amounts'**
  String get splitMethodExact;

  /// No description provided for @splitPickPeople.
  ///
  /// In en, this message translates to:
  /// **'Who is sharing this?'**
  String get splitPickPeople;

  /// No description provided for @splitPickPeopleEmpty.
  ///
  /// In en, this message translates to:
  /// **'Add people in Settings first, then split a bill with them.'**
  String get splitPickPeopleEmpty;

  /// No description provided for @splitGroupLabel.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get splitGroupLabel;

  /// No description provided for @splitGroupNone.
  ///
  /// In en, this message translates to:
  /// **'No group'**
  String get splitGroupNone;

  /// No description provided for @splitPaidByYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get splitPaidByYou;

  /// No description provided for @splitPaidByOther.
  ///
  /// In en, this message translates to:
  /// **'{name} paid'**
  String splitPaidByOther(String name);

  /// No description provided for @splitShareWeight.
  ///
  /// In en, this message translates to:
  /// **'Shares'**
  String get splitShareWeight;

  /// No description provided for @splitSharePercent.
  ///
  /// In en, this message translates to:
  /// **'Percent'**
  String get splitSharePercent;

  /// No description provided for @splitShareAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get splitShareAmount;

  /// No description provided for @splitPerPersonCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 person} other{{count} people}}'**
  String splitPerPersonCount(int count);

  /// No description provided for @splitNeedsAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter the amount first, then choose who is sharing it.'**
  String get splitNeedsAmount;

  /// No description provided for @splitApply.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get splitApply;

  /// No description provided for @splitSelfPayeeUnset.
  ///
  /// In en, this message translates to:
  /// **'Choose which person is you in Settings before splitting a bill.'**
  String get splitSelfPayeeUnset;

  /// No description provided for @navSplit.
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get navSplit;

  /// No description provided for @splitGroupsTitle.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get splitGroupsTitle;

  /// No description provided for @splitOwedToYou.
  ///
  /// In en, this message translates to:
  /// **'Owed to you'**
  String get splitOwedToYou;

  /// No description provided for @splitYouOwe.
  ///
  /// In en, this message translates to:
  /// **'You owe'**
  String get splitYouOwe;

  /// No description provided for @splitAllSettledTitle.
  ///
  /// In en, this message translates to:
  /// **'All settled up'**
  String get splitAllSettledTitle;

  /// No description provided for @splitAllSettledBody.
  ///
  /// In en, this message translates to:
  /// **'Nobody owes anybody anything right now.'**
  String get splitAllSettledBody;

  /// No description provided for @splitNoSelfTitle.
  ///
  /// In en, this message translates to:
  /// **'Who are you?'**
  String get splitNoSelfTitle;

  /// No description provided for @splitOutstandingDays.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day} other{{days} days}}'**
  String splitOutstandingDays(int days);

  /// No description provided for @splitGroupNew.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get splitGroupNew;

  /// No description provided for @splitGroupEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit group'**
  String get splitGroupEditTitle;

  /// No description provided for @splitGroupNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get splitGroupNameLabel;

  /// No description provided for @splitNoGroupsTitle.
  ///
  /// In en, this message translates to:
  /// **'No groups yet'**
  String get splitNoGroupsTitle;

  /// No description provided for @splitNoGroupsBody.
  ///
  /// In en, this message translates to:
  /// **'A group saves entering the same people every time you split a bill with them.'**
  String get splitNoGroupsBody;

  /// No description provided for @splitHasWeights.
  ///
  /// In en, this message translates to:
  /// **'Custom shares'**
  String get splitHasWeights;

  /// No description provided for @splitArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get splitArchived;

  /// No description provided for @splitArchiveLabel.
  ///
  /// In en, this message translates to:
  /// **'Archive this group'**
  String get splitArchiveLabel;

  /// No description provided for @splitArchiveHelp.
  ///
  /// In en, this message translates to:
  /// **'It keeps its history and its balances, and stops appearing when you split a bill.'**
  String get splitArchiveHelp;

  /// No description provided for @splitDefaultShares.
  ///
  /// In en, this message translates to:
  /// **'Default shares'**
  String get splitDefaultShares;

  /// No description provided for @splitDefaultSharesHelp.
  ///
  /// In en, this message translates to:
  /// **'Set a percentage for everybody to prefill a split — like rent at 40/30/30. Leave them all blank to split equally.'**
  String get splitDefaultSharesHelp;

  /// No description provided for @splitWeightsPartial.
  ///
  /// In en, this message translates to:
  /// **'Set a share for everybody, or none'**
  String get splitWeightsPartial;

  /// No description provided for @splitDeleteGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this group?'**
  String get splitDeleteGroupTitle;

  /// No description provided for @splitDeleteGroupBody.
  ///
  /// In en, this message translates to:
  /// **'A group with expenses cannot be deleted — archive it instead and its history stays.'**
  String get splitDeleteGroupBody;

  /// No description provided for @splitBalancesHeader.
  ///
  /// In en, this message translates to:
  /// **'Where you stand'**
  String get splitBalancesHeader;

  /// No description provided for @splitActivityHeader.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get splitActivityHeader;

  /// No description provided for @splitGroupEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get splitGroupEmptyTitle;

  /// No description provided for @splitGroupEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Split a bill with this group and it will show up here.'**
  String get splitGroupEmptyBody;

  /// No description provided for @splitOwesYou.
  ///
  /// In en, this message translates to:
  /// **'{name} owes you'**
  String splitOwesYou(String name);

  /// No description provided for @splitYouOwePerson.
  ///
  /// In en, this message translates to:
  /// **'You owe {name}'**
  String splitYouOwePerson(String name);

  /// No description provided for @splitExpenseBy.
  ///
  /// In en, this message translates to:
  /// **'{name} paid'**
  String splitExpenseBy(String name);

  /// No description provided for @splitSettlementBy.
  ///
  /// In en, this message translates to:
  /// **'{name} settled up'**
  String splitSettlementBy(String name);

  /// No description provided for @splitSettleFrom.
  ///
  /// In en, this message translates to:
  /// **'Settle up with {name}'**
  String splitSettleFrom(String name);

  /// No description provided for @splitSettleTo.
  ///
  /// In en, this message translates to:
  /// **'Pay {name}'**
  String splitSettleTo(String name);

  /// No description provided for @splitOutstandingLabel.
  ///
  /// In en, this message translates to:
  /// **'Outstanding'**
  String get splitOutstandingLabel;

  /// No description provided for @splitSettleAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get splitSettleAmount;

  /// No description provided for @splitSettleOverpay.
  ///
  /// In en, this message translates to:
  /// **'More than the balance — the difference will swing the other way.'**
  String get splitSettleOverpay;

  /// No description provided for @splitSettleIntoAccount.
  ///
  /// In en, this message translates to:
  /// **'Into which account?'**
  String get splitSettleIntoAccount;

  /// No description provided for @splitSettleFromAccount.
  ///
  /// In en, this message translates to:
  /// **'From which account?'**
  String get splitSettleFromAccount;

  /// No description provided for @splitSettleAction.
  ///
  /// In en, this message translates to:
  /// **'Record payment'**
  String get splitSettleAction;

  /// No description provided for @splitSimplifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Settle up'**
  String get splitSimplifyTitle;

  /// No description provided for @splitSimplifySaves.
  ///
  /// In en, this message translates to:
  /// **'{before} payments become {after}'**
  String splitSimplifySaves(int before, int after);

  /// No description provided for @splitSimplifyNoBetter.
  ///
  /// In en, this message translates to:
  /// **'There is no shorter way — these are already the fewest payments.'**
  String get splitSimplifyNoBetter;

  /// No description provided for @splitSimplifyApproximate.
  ///
  /// In en, this message translates to:
  /// **'A short way, not provably the shortest'**
  String get splitSimplifyApproximate;

  /// No description provided for @splitTransferLine.
  ///
  /// In en, this message translates to:
  /// **'{from} pays {to}'**
  String splitTransferLine(String from, String to);

  /// No description provided for @splitClearsDebt.
  ///
  /// In en, this message translates to:
  /// **'clears what is owed to {name}'**
  String splitClearsDebt(String name);

  /// No description provided for @splitShareTitle.
  ///
  /// In en, this message translates to:
  /// **'Send this summary'**
  String get splitShareTitle;

  /// No description provided for @splitShareCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get splitShareCopied;

  /// No description provided for @splitShareAddUpi.
  ///
  /// In en, this message translates to:
  /// **'Add your UPI id in Settings and each line gets a link they can tap to pay you.'**
  String get splitShareAddUpi;

  /// No description provided for @actionCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get actionCopy;

  /// No description provided for @actionShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get actionShare;

  /// No description provided for @splitShareHeading.
  ///
  /// In en, this message translates to:
  /// **'Where we stand'**
  String get splitShareHeading;

  /// No description provided for @splitShareOwesYou.
  ///
  /// In en, this message translates to:
  /// **'Owes you'**
  String get splitShareOwesYou;

  /// No description provided for @splitShareYouOwe.
  ///
  /// In en, this message translates to:
  /// **'You owe'**
  String get splitShareYouOwe;

  /// No description provided for @reminderKindSettlement.
  ///
  /// In en, this message translates to:
  /// **'Debts to settle'**
  String get reminderKindSettlement;

  /// No description provided for @reminderKindSettlementHelp.
  ///
  /// In en, this message translates to:
  /// **'A reminder when a shared bill you agreed to settle by a date is coming up.'**
  String get reminderKindSettlementHelp;

  /// No description provided for @calendarSplitSettleBy.
  ///
  /// In en, this message translates to:
  /// **'Settle by'**
  String get calendarSplitSettleBy;

  /// No description provided for @eventTypeSplitSettleBy.
  ///
  /// In en, this message translates to:
  /// **'Settle up'**
  String get eventTypeSplitSettleBy;

  /// No description provided for @splitSettleByLabel.
  ///
  /// In en, this message translates to:
  /// **'Settle by'**
  String get splitSettleByLabel;

  /// No description provided for @splitSettleByHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional. Setting a date puts this on your calendar and in the daily summary.'**
  String get splitSettleByHelp;

  /// No description provided for @splitSettleByHint.
  ///
  /// In en, this message translates to:
  /// **'No date'**
  String get splitSettleByHint;

  /// No description provided for @moduleSplit.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{all settled} =1{1 person} other{{count} people}}'**
  String moduleSplit(int count);

  /// No description provided for @splitCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Shared expenses'**
  String get splitCardTitle;

  /// No description provided for @splitCardNotSpendable.
  ///
  /// In en, this message translates to:
  /// **'Not part of your available funds until it arrives.'**
  String get splitCardNotSpendable;

  /// No description provided for @splitCardOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest is {days} days'**
  String splitCardOldest(int days);

  /// No description provided for @settingsSplit.
  ///
  /// In en, this message translates to:
  /// **'Shared expenses'**
  String get settingsSplit;

  /// No description provided for @settingsSplitUnset.
  ///
  /// In en, this message translates to:
  /// **'Not set up yet'**
  String get settingsSplitUnset;

  /// No description provided for @settingsSplitSet.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get settingsSplitSet;

  /// No description provided for @splitSettingsWhoAreYou.
  ///
  /// In en, this message translates to:
  /// **'Which person is you?'**
  String get splitSettingsWhoAreYou;

  /// No description provided for @splitSettingsWhoAreYouHelp.
  ///
  /// In en, this message translates to:
  /// **'Every balance is what somebody owes you, or what you owe them. Alaya needs to know which of these people is you.'**
  String get splitSettingsWhoAreYouHelp;

  /// No description provided for @splitSettingsNoPeople.
  ///
  /// In en, this message translates to:
  /// **'Add people under Payees first, then come back and pick yourself.'**
  String get splitSettingsNoPeople;

  /// No description provided for @splitSettingsClaimed.
  ///
  /// In en, this message translates to:
  /// **'You are {name}'**
  String splitSettingsClaimed(String name);

  /// No description provided for @splitSettingsUpi.
  ///
  /// In en, this message translates to:
  /// **'Your UPI id'**
  String get splitSettingsUpi;

  /// No description provided for @splitSettingsUpiLabel.
  ///
  /// In en, this message translates to:
  /// **'UPI id'**
  String get splitSettingsUpiLabel;

  /// No description provided for @splitSettingsUpiHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional. Add it and every summary you share carries a link people can tap to pay you.'**
  String get splitSettingsUpiHelp;

  /// No description provided for @analyticsSectionSplit.
  ///
  /// In en, this message translates to:
  /// **'Shared'**
  String get analyticsSectionSplit;

  /// No description provided for @analyticsSplitLensesTitle.
  ///
  /// In en, this message translates to:
  /// **'What shared bills cost you'**
  String get analyticsSplitLensesTitle;

  /// No description provided for @analyticsSplitLensesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'What left your account, and what you actually used'**
  String get analyticsSplitLensesSubtitle;

  /// No description provided for @analyticsSplitOutflow.
  ///
  /// In en, this message translates to:
  /// **'Left your account'**
  String get analyticsSplitOutflow;

  /// No description provided for @analyticsSplitOutflowHelp.
  ///
  /// In en, this message translates to:
  /// **'Full bills you paid'**
  String get analyticsSplitOutflowHelp;

  /// No description provided for @analyticsSplitMyShare.
  ///
  /// In en, this message translates to:
  /// **'Your share'**
  String get analyticsSplitMyShare;

  /// No description provided for @analyticsSplitMyShareHelp.
  ///
  /// In en, this message translates to:
  /// **'What you actually used'**
  String get analyticsSplitMyShareHelp;

  /// No description provided for @analyticsSplitOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Still out'**
  String get analyticsSplitOutstanding;

  /// No description provided for @analyticsSplitOutstandingHelp.
  ///
  /// In en, this message translates to:
  /// **'Paid out, not yours, not back yet'**
  String get analyticsSplitOutstandingHelp;

  /// No description provided for @analyticsSplitEmpty.
  ///
  /// In en, this message translates to:
  /// **'No shared expenses in this window.'**
  String get analyticsSplitEmpty;

  /// No description provided for @analyticsSplitNoSelf.
  ///
  /// In en, this message translates to:
  /// **'Choose which person is you in Settings to see your share.'**
  String get analyticsSplitNoSelf;

  /// No description provided for @analyticsSplitPartnersTitle.
  ///
  /// In en, this message translates to:
  /// **'Who you split with'**
  String get analyticsSplitPartnersTitle;

  /// No description provided for @analyticsSplitPartnersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'By their share of the bills you paid'**
  String get analyticsSplitPartnersSubtitle;

  /// No description provided for @analyticsSplitPartnerCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 expense} other{{count} expenses}}'**
  String analyticsSplitPartnerCount(int count);

  /// No description provided for @analyticsSplitOccasionTitle.
  ///
  /// In en, this message translates to:
  /// **'By occasion'**
  String get analyticsSplitOccasionTitle;

  /// No description provided for @analyticsSplitOccasionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Diwali, a birthday, a trip'**
  String get analyticsSplitOccasionSubtitle;

  /// No description provided for @analyticsSplitOccasionEmpty.
  ///
  /// In en, this message translates to:
  /// **'Add an occasion when you split a bill and it will appear here.'**
  String get analyticsSplitOccasionEmpty;

  /// No description provided for @analyticsSplitPlaceTitle.
  ///
  /// In en, this message translates to:
  /// **'By place'**
  String get analyticsSplitPlaceTitle;

  /// No description provided for @analyticsSplitPlaceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Where the money went'**
  String get analyticsSplitPlaceSubtitle;

  /// No description provided for @analyticsSplitPlaceEmpty.
  ///
  /// In en, this message translates to:
  /// **'Add a place when you split a bill and it will appear here.'**
  String get analyticsSplitPlaceEmpty;

  /// No description provided for @splitBillAction.
  ///
  /// In en, this message translates to:
  /// **'Split a bill'**
  String get splitBillAction;

  /// No description provided for @splitBillAmount.
  ///
  /// In en, this message translates to:
  /// **'How much was it?'**
  String get splitBillAmount;

  /// No description provided for @splitBillWhatFor.
  ///
  /// In en, this message translates to:
  /// **'What was it for?'**
  String get splitBillWhatFor;

  /// No description provided for @splitBillWhatForHint.
  ///
  /// In en, this message translates to:
  /// **'Dinner at Olive'**
  String get splitBillWhatForHint;

  /// No description provided for @splitBillHow.
  ///
  /// In en, this message translates to:
  /// **'How does it split?'**
  String get splitBillHow;

  /// No description provided for @splitBillYourMoney.
  ///
  /// In en, this message translates to:
  /// **'Your money'**
  String get splitBillYourMoney;

  /// No description provided for @splitBillRecordExpense.
  ///
  /// In en, this message translates to:
  /// **'Record this as an expense'**
  String get splitBillRecordExpense;

  /// No description provided for @splitBillRecordExpenseHelp.
  ///
  /// In en, this message translates to:
  /// **'The full bill left your account, so it belongs in your spending. Turn this off if somebody else paid, or if you have already recorded it.'**
  String get splitBillRecordExpenseHelp;

  /// No description provided for @splitBillSaved.
  ///
  /// In en, this message translates to:
  /// **'Split saved'**
  String get splitBillSaved;

  /// No description provided for @splitAddPerson.
  ///
  /// In en, this message translates to:
  /// **'Add person'**
  String get splitAddPerson;

  /// No description provided for @splitAddExtra.
  ///
  /// In en, this message translates to:
  /// **'Extra'**
  String get splitAddExtra;

  /// No description provided for @splitExtraLabel.
  ///
  /// In en, this message translates to:
  /// **'Just for them'**
  String get splitExtraLabel;

  /// No description provided for @splitRemoveExtra.
  ///
  /// In en, this message translates to:
  /// **'Remove extra'**
  String get splitRemoveExtra;

  /// No description provided for @splitShareBreakdown.
  ///
  /// In en, this message translates to:
  /// **'{share} share + {extra} just for them'**
  String splitShareBreakdown(String share, String extra);

  /// No description provided for @splitTapToSettle.
  ///
  /// In en, this message translates to:
  /// **'Tap anybody to record a payment'**
  String get splitTapToSettle;

  /// No description provided for @splitSettingsPayMe.
  ///
  /// In en, this message translates to:
  /// **'How people can pay you'**
  String get splitSettingsPayMe;

  /// No description provided for @splitSettingsPayMeLabel.
  ///
  /// In en, this message translates to:
  /// **'Payment details'**
  String get splitSettingsPayMeLabel;

  /// No description provided for @splitSettingsPayMeHint.
  ///
  /// In en, this message translates to:
  /// **'UPI id, PayPal link, bank details, or anything else'**
  String get splitSettingsPayMeHint;

  /// No description provided for @splitSettingsPayMeHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional, and free text — whatever works where you are. It is added to the end of any summary you share, so nobody has to ask.'**
  String get splitSettingsPayMeHelp;

  /// No description provided for @splitSharePayMeAt.
  ///
  /// In en, this message translates to:
  /// **'Pay me at:'**
  String get splitSharePayMeAt;

  /// No description provided for @splitShareAddHandle.
  ///
  /// In en, this message translates to:
  /// **'Add your payment details so nobody has to ask.'**
  String get splitShareAddHandle;

  /// No description provided for @splitHowManyPeople.
  ///
  /// In en, this message translates to:
  /// **'How many people?'**
  String get splitHowManyPeople;

  /// No description provided for @splitHowManyPeopleHelp.
  ///
  /// In en, this message translates to:
  /// **'Names are optional — add them later if you want to keep this'**
  String get splitHowManyPeopleHelp;

  /// No description provided for @splitPersonN.
  ///
  /// In en, this message translates to:
  /// **'Person {n}'**
  String splitPersonN(int n);

  /// No description provided for @splitBillResultHint.
  ///
  /// In en, this message translates to:
  /// **'Send this to the table — no names needed.'**
  String get splitBillResultHint;

  /// No description provided for @splitCopyResult.
  ///
  /// In en, this message translates to:
  /// **'Copy the result'**
  String get splitCopyResult;

  /// No description provided for @splitResultCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get splitResultCopied;

  /// No description provided for @splitBillKeepIt.
  ///
  /// In en, this message translates to:
  /// **'Keep it'**
  String get splitBillKeepIt;

  /// No description provided for @splitBillKeepItHelp.
  ///
  /// In en, this message translates to:
  /// **'Everything below is optional. Save it only if you want the debt tracked until it is paid.'**
  String get splitBillKeepItHelp;

  /// No description provided for @splitSaveToBalances.
  ///
  /// In en, this message translates to:
  /// **'Save to balances'**
  String get splitSaveToBalances;

  /// No description provided for @splitNameEveryoneToSave.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Name 1 more person to save this} other{Name {count} more people to save this}}'**
  String splitNameEveryoneToSave(int count);

  /// No description provided for @splitPickName.
  ///
  /// In en, this message translates to:
  /// **'Who is this?'**
  String get splitPickName;

  /// No description provided for @splitNewPerson.
  ///
  /// In en, this message translates to:
  /// **'New person'**
  String get splitNewPerson;

  /// No description provided for @splitAlreadyOnSplit.
  ///
  /// In en, this message translates to:
  /// **'Already on this split'**
  String get splitAlreadyOnSplit;

  /// No description provided for @splitPercentOfBill.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String splitPercentOfBill(int percent);

  /// No description provided for @splitTipPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}% tip'**
  String splitTipPercent(int percent);

  /// No description provided for @splitRoundUp.
  ///
  /// In en, this message translates to:
  /// **'Round up'**
  String get splitRoundUp;

  /// No description provided for @splitTipAdded.
  ///
  /// In en, this message translates to:
  /// **'Adding'**
  String get splitTipAdded;

  /// No description provided for @splitTipTotal.
  ///
  /// In en, this message translates to:
  /// **'Adding {tip} · total {total}'**
  String splitTipTotal(String tip, String total);

  /// No description provided for @splitBillTheSplit.
  ///
  /// In en, this message translates to:
  /// **'The split'**
  String get splitBillTheSplit;

  /// No description provided for @splitSaveAsGroup.
  ///
  /// In en, this message translates to:
  /// **'Save these people as a group'**
  String get splitSaveAsGroup;

  /// No description provided for @splitSaveAsGroupHelp.
  ///
  /// In en, this message translates to:
  /// **'So next time you split with them it is one tap.'**
  String get splitSaveAsGroupHelp;

  /// No description provided for @splitSaveAsGroupHint.
  ///
  /// In en, this message translates to:
  /// **'Flatmates'**
  String get splitSaveAsGroupHint;

  /// No description provided for @splitSaveAsGroupWeights.
  ///
  /// In en, this message translates to:
  /// **'Their shares are saved too, so next time starts the same way.'**
  String get splitSaveAsGroupWeights;

  /// No description provided for @splitSaveAsGroupAction.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Save as a group} other{Save these {count} as a group}}'**
  String splitSaveAsGroupAction(int count);

  /// No description provided for @splitGroupNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Give the group a name'**
  String get splitGroupNameRequired;

  /// No description provided for @splitMemberWithWeight.
  ///
  /// In en, this message translates to:
  /// **'{name} · {percent}%'**
  String splitMemberWithWeight(String name, int percent);

  /// No description provided for @splitGroupSaved.
  ///
  /// In en, this message translates to:
  /// **'Group saved'**
  String get splitGroupSaved;

  /// No description provided for @splitQuickAmount.
  ///
  /// In en, this message translates to:
  /// **'What was the bill?'**
  String get splitQuickAmount;

  /// No description provided for @splitQuickPeople.
  ///
  /// In en, this message translates to:
  /// **'How many of you?'**
  String get splitQuickPeople;

  /// No description provided for @splitQuickIPaid.
  ///
  /// In en, this message translates to:
  /// **'I paid it all'**
  String get splitQuickIPaid;

  /// No description provided for @splitQuickEachTheirOwn.
  ///
  /// In en, this message translates to:
  /// **'Each their own'**
  String get splitQuickEachTheirOwn;

  /// No description provided for @splitQuickEach.
  ///
  /// In en, this message translates to:
  /// **'Each pays'**
  String get splitQuickEach;

  /// No description provided for @splitQuickOwed.
  ///
  /// In en, this message translates to:
  /// **'Owed to you'**
  String get splitQuickOwed;

  /// No description provided for @splitQuickHint.
  ///
  /// In en, this message translates to:
  /// **'Type an amount and it splits as you go. Names are optional.'**
  String get splitQuickHint;

  /// No description provided for @splitQuickAddNames.
  ///
  /// In en, this message translates to:
  /// **'Add names'**
  String get splitQuickAddNames;

  /// No description provided for @splitQuickEachPays.
  ///
  /// In en, this message translates to:
  /// **'Each pays {amount}'**
  String splitQuickEachPays(String amount);

  /// No description provided for @splitQuickOwedToMe.
  ///
  /// In en, this message translates to:
  /// **'Owed to me: {amount}'**
  String splitQuickOwedToMe(String amount);

  /// No description provided for @splitQuickYouAbsorb.
  ///
  /// In en, this message translates to:
  /// **'You cover the odd {amount}.'**
  String splitQuickYouAbsorb(String amount);

  /// No description provided for @splitQuickLeftOver.
  ///
  /// In en, this message translates to:
  /// **'{amount} left over — add names to place it.'**
  String splitQuickLeftOver(String amount);

  /// No description provided for @splitUnnamedWillBeSaved.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 person is unnamed — they will be saved as \"Person N\" and you can rename them any time} other{{count} people are unnamed — they will be saved as \"Person N\" and you can rename them any time}}'**
  String splitUnnamedWillBeSaved(int count);

  /// No description provided for @splitNameThisPerson.
  ///
  /// In en, this message translates to:
  /// **'Who is this?'**
  String get splitNameThisPerson;

  /// No description provided for @splitAddPersonTitle.
  ///
  /// In en, this message translates to:
  /// **'Add someone'**
  String get splitAddPersonTitle;

  /// No description provided for @splitAddPersonNameRequired.
  ///
  /// In en, this message translates to:
  /// **'They need a name'**
  String get splitAddPersonNameRequired;

  /// No description provided for @splitAddPersonPhoneHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional — shown only when two people share a name, so you can tell them apart.'**
  String get splitAddPersonPhoneHelp;

  /// No description provided for @splitSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'First, who are you?'**
  String get splitSetupTitle;

  /// No description provided for @splitSetupBody.
  ///
  /// In en, this message translates to:
  /// **'Alaya needs one name for you, so it can tell who owes whom. You can change it later in Settings.'**
  String get splitSetupBody;

  /// No description provided for @splitSetupNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get splitSetupNameLabel;

  /// No description provided for @splitSetupNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a name to continue'**
  String get splitSetupNameRequired;

  /// No description provided for @splitSetupAction.
  ///
  /// In en, this message translates to:
  /// **'That\'s me'**
  String get splitSetupAction;

  /// No description provided for @splitCreateSplit.
  ///
  /// In en, this message translates to:
  /// **'Create a split'**
  String get splitCreateSplit;

  /// No description provided for @payeeKindSplitPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Unnamed on a split'**
  String get payeeKindSplitPlaceholder;

  /// No description provided for @onboardingNameTitle.
  ///
  /// In en, this message translates to:
  /// **'What should we call you?'**
  String get onboardingNameTitle;

  /// No description provided for @onboardingNameBody.
  ///
  /// In en, this message translates to:
  /// **'Alaya uses this to know which share is yours when you split a bill, and to sign anything you share with friends.'**
  String get onboardingNameBody;

  /// No description provided for @onboardingNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get onboardingNameLabel;

  /// No description provided for @onboardingNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a name, or skip for now'**
  String get onboardingNameRequired;

  /// No description provided for @splitHistoryEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing split yet'**
  String get splitHistoryEmptyTitle;

  /// No description provided for @splitHistoryEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Every bill you divide and every payment you record shows up here, newest first.'**
  String get splitHistoryEmptyBody;

  /// No description provided for @splitHistoryPaidBy.
  ///
  /// In en, this message translates to:
  /// **'{name} paid'**
  String splitHistoryPaidBy(String name);

  /// No description provided for @splitHistorySettledBy.
  ///
  /// In en, this message translates to:
  /// **'{name} settled up'**
  String splitHistorySettledBy(String name);

  /// No description provided for @splitTabBalances.
  ///
  /// In en, this message translates to:
  /// **'Balances'**
  String get splitTabBalances;

  /// No description provided for @splitTabHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get splitTabHistory;

  /// No description provided for @splitTabGroups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get splitTabGroups;

  /// No description provided for @splitTransferNotYours.
  ///
  /// In en, this message translates to:
  /// **'Between two other people — nothing for you to record.'**
  String get splitTransferNotYours;

  /// No description provided for @onboardingNameOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional — leave it blank and continue if you would rather not.'**
  String get onboardingNameOptional;

  /// No description provided for @splitTipTitle.
  ///
  /// In en, this message translates to:
  /// **'Tip or service charge'**
  String get splitTipTitle;

  /// No description provided for @splitTipNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get splitTipNone;

  /// No description provided for @splitTipPercentChip.
  ///
  /// In en, this message translates to:
  /// **'{percent}% tip'**
  String splitTipPercentChip(int percent);

  /// No description provided for @splitTipCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom %'**
  String get splitTipCustom;

  /// No description provided for @splitTipAdds.
  ///
  /// In en, this message translates to:
  /// **'{percent}% of the bill'**
  String splitTipAdds(int percent);

  /// No description provided for @splitMethodTitle.
  ///
  /// In en, this message translates to:
  /// **'How it splits'**
  String get splitMethodTitle;

  /// No description provided for @splitMethodEqualHelp.
  ///
  /// In en, this message translates to:
  /// **'The same amount each. Anything one person owes on top goes in their row.'**
  String get splitMethodEqualHelp;

  /// No description provided for @splitMethodSharesHelp.
  ///
  /// In en, this message translates to:
  /// **'Weights, not amounts — 2:1:1 means one person covers half.'**
  String get splitMethodSharesHelp;

  /// No description provided for @splitMethodPercentHelp.
  ///
  /// In en, this message translates to:
  /// **'A percentage each. They needn\'t add to 100; anything left over is shown.'**
  String get splitMethodPercentHelp;

  /// No description provided for @splitMethodExactHelp.
  ///
  /// In en, this message translates to:
  /// **'Type what each person owes. Any gap against the total is shown, never absorbed.'**
  String get splitMethodExactHelp;

  /// No description provided for @splitMethodPerLineHelp.
  ///
  /// In en, this message translates to:
  /// **'Each item on the receipt divided among whoever ordered it.'**
  String get splitMethodPerLineHelp;

  /// No description provided for @splitMethodPerLine.
  ///
  /// In en, this message translates to:
  /// **'Item by item'**
  String get splitMethodPerLine;

  /// No description provided for @splitTipTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'total'**
  String get splitTipTotalLabel;

  /// No description provided for @splitNamePlaceholderBody.
  ///
  /// In en, this message translates to:
  /// **'{placeholder} is a stand-in Alaya created so the split could be saved. Who was it?'**
  String splitNamePlaceholderBody(String placeholder);

  /// No description provided for @splitNameSomebodyKnown.
  ///
  /// In en, this message translates to:
  /// **'Somebody you already have'**
  String get splitNameSomebodyKnown;

  /// No description provided for @splitNameOr.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get splitNameOr;

  /// No description provided for @splitNameSomebodyNew.
  ///
  /// In en, this message translates to:
  /// **'Somebody new — their name'**
  String get splitNameSomebodyNew;

  /// No description provided for @splitNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a name, or pick somebody above'**
  String get splitNameRequired;

  /// No description provided for @splitWhoPaid.
  ///
  /// In en, this message translates to:
  /// **'Who paid?'**
  String get splitWhoPaid;

  /// No description provided for @splitPaidBySomebodyElseHelp.
  ///
  /// In en, this message translates to:
  /// **'No money left your account, so nothing goes in your ledger until you settle up.'**
  String get splitPaidBySomebodyElseHelp;

  /// No description provided for @splitRecordTheyPaid.
  ///
  /// In en, this message translates to:
  /// **'They paid me back'**
  String get splitRecordTheyPaid;

  /// No description provided for @splitRecordYouPaid.
  ///
  /// In en, this message translates to:
  /// **'I paid them back'**
  String get splitRecordYouPaid;

  /// No description provided for @splitDetailTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get splitDetailTotal;

  /// No description provided for @splitDetailPaidBy.
  ///
  /// In en, this message translates to:
  /// **'Paid by'**
  String get splitDetailPaidBy;

  /// No description provided for @splitDetailMethod.
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get splitDetailMethod;

  /// No description provided for @splitDetailPlace.
  ///
  /// In en, this message translates to:
  /// **'Place'**
  String get splitDetailPlace;

  /// No description provided for @splitDetailOccasion.
  ///
  /// In en, this message translates to:
  /// **'Occasion'**
  String get splitDetailOccasion;

  /// No description provided for @splitSharePercentOf.
  ///
  /// In en, this message translates to:
  /// **'{percent}% of the bill'**
  String splitSharePercentOf(double percent);

  /// No description provided for @splitShareWeightOf.
  ///
  /// In en, this message translates to:
  /// **'{weight} share(s)'**
  String splitShareWeightOf(int weight);

  /// No description provided for @splitShareIsExtra.
  ///
  /// In en, this message translates to:
  /// **'Just for them'**
  String get splitShareIsExtra;

  /// No description provided for @splitDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this split?'**
  String get splitDeleteConfirmTitle;

  /// No description provided for @splitDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The balances it created go with it. Any expense already recorded in your ledger stays — the money did move.'**
  String get splitDeleteConfirmBody;

  /// No description provided for @splitDeleted.
  ///
  /// In en, this message translates to:
  /// **'Split deleted'**
  String get splitDeleted;

  /// No description provided for @splitEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit split'**
  String get splitEditTitle;

  /// No description provided for @splitQuickSaveHelp.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Records that 1 person owes you.} other{Records that {count} people owe you.}} Your account balance isn\'t touched — use More options to record the expense too.'**
  String splitQuickSaveHelp(int count);

  /// No description provided for @splitQuickMoreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get splitQuickMoreOptions;

  /// No description provided for @supportActionLabel.
  ///
  /// In en, this message translates to:
  /// **'Support Us'**
  String get supportActionLabel;

  /// No description provided for @splitNoteWays.
  ///
  /// In en, this message translates to:
  /// **'Split {count} ways'**
  String splitNoteWays(int count);

  /// No description provided for @splitNoteWaysWith.
  ///
  /// In en, this message translates to:
  /// **'Split {count} ways with {names}'**
  String splitNoteWaysWith(int count, String names);

  /// No description provided for @splitNoteTitled.
  ///
  /// In en, this message translates to:
  /// **'{title} — split {count} ways'**
  String splitNoteTitled(String title, int count);

  /// No description provided for @splitNoteTitledWith.
  ///
  /// In en, this message translates to:
  /// **'{title} — split {count} ways with {names}'**
  String splitNoteTitledWith(String title, int count, String names);

  /// No description provided for @splitSettleNoteFrom.
  ///
  /// In en, this message translates to:
  /// **'{name} paid you back'**
  String splitSettleNoteFrom(String name);

  /// No description provided for @splitSettleNoteTo.
  ///
  /// In en, this message translates to:
  /// **'You paid {name} back'**
  String splitSettleNoteTo(String name);

  /// No description provided for @splitSettleNoteFromIn.
  ///
  /// In en, this message translates to:
  /// **'{name} paid you back — {group}'**
  String splitSettleNoteFromIn(String name, String group);

  /// No description provided for @splitSettleNoteToIn.
  ///
  /// In en, this message translates to:
  /// **'You paid {name} back — {group}'**
  String splitSettleNoteToIn(String name, String group);

  /// No description provided for @lineItemRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose an item, or add a new one'**
  String get lineItemRequired;

  /// No description provided for @lineQuantityRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter how much you bought, and in what unit'**
  String get lineQuantityRequired;
}

class _AlayaStringsDelegate extends LocalizationsDelegate<AlayaStrings> {
  const _AlayaStringsDelegate();

  @override
  Future<AlayaStrings> load(Locale locale) {
    return SynchronousFuture<AlayaStrings>(lookupAlayaStrings(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AlayaStringsDelegate old) => false;
}

AlayaStrings lookupAlayaStrings(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AlayaStringsEn();
  }

  throw FlutterError(
    'AlayaStrings.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
```

### `lib/app/l10n/generated/app_localizations_en.dart`

```dart
// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AlayaStringsEn extends AlayaStrings {
  AlayaStringsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Alaya';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navExpenses => 'Expenses';

  @override
  String get navInventory => 'Inventory';

  @override
  String get navShopping => 'Shopping';

  @override
  String get navRecurring => 'Recurring';

  @override
  String get navServices => 'Services';

  @override
  String get navCalendar => 'Calendar';

  @override
  String get navInsights => 'Insights';

  @override
  String get navSettings => 'Settings';

  @override
  String get navThemeLab => 'Theme Lab';

  @override
  String get actionSave => 'Save';

  @override
  String get actionSaved => 'Saved';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionDeleted => 'Deleted';

  @override
  String get actionUndo => 'Undo';

  @override
  String get actionRetry => 'Try again';

  @override
  String get actionAdd => 'Add';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionDone => 'Done';

  @override
  String get actionClose => 'Close';

  @override
  String get actionSelect => 'Select';

  @override
  String get actionClear => 'Clear';

  @override
  String get actionClearAll => 'Clear all';

  @override
  String get actionSearch => 'Search';

  @override
  String get actionConfirm => 'Confirm';

  @override
  String get actionDiscard => 'Discard';

  @override
  String get actionKeepEditing => 'Keep editing';

  @override
  String get actionRemoveTag => 'Remove tag';

  @override
  String get actionClearSearch => 'Clear search';

  @override
  String get addExpense => 'Add expense';

  @override
  String get addIncome => 'Add income';

  @override
  String get addTransfer => 'Add transfer';

  @override
  String get addItem => 'Add item';

  @override
  String get addToShoppingList => 'Add to shopping list';

  @override
  String get dateToday => 'Today';

  @override
  String get dateYesterday => 'Yesterday';

  @override
  String get dateTomorrow => 'Tomorrow';

  @override
  String get emptyTitleNoTransactions => 'No transactions yet';

  @override
  String get emptyBodyNoTransactions =>
      'Add your first expense and it will appear here.';

  @override
  String get emptyTitleNoItems => 'Nothing in your inventory';

  @override
  String get emptyBodyNoItems =>
      'Add an item to start tracking what you have at home.';

  @override
  String get emptyTitleNoShopping => 'Your list is empty';

  @override
  String get emptyBodyNoShopping =>
      'Add something, or let Alaya suggest items you are low on.';

  @override
  String get emptyTitleNoRecurring => 'No recurring bills';

  @override
  String get emptyBodyNoRecurring =>
      'Set up a bill or subscription and Alaya will remind you when it is due.';

  @override
  String get emptyTitleNoResults => 'No matches';

  @override
  String get emptyBodyNoResults =>
      'Try a shorter search, or check the spelling.';

  @override
  String get loadingLabel => 'Loading';

  @override
  String get loadingTransactions => 'Loading transactions';

  @override
  String get errorTitleGeneric => 'That did not work';

  @override
  String get errorBodyGeneric => 'Something went wrong on our side. Try again.';

  @override
  String get errorTitleNotFound => 'Not found';

  @override
  String get errorBodyNotFound => 'This item may have been deleted.';

  @override
  String get errorBodyNoConnection =>
      'You are offline. Alaya works offline, but rates will not refresh.';

  @override
  String get errorFieldRequired => 'This is required';

  @override
  String get errorAmountInvalid => 'Enter an amount';

  @override
  String get errorAmountZero => 'Enter an amount greater than zero';

  @override
  String get errorAmountInvalidCharacter => 'Digits only';

  @override
  String get errorAmountNegativeNotAllowed => 'Enter a positive amount';

  @override
  String get errorAmountTooManyDecimals => 'Too many decimal places';

  @override
  String get errorAmountTooLarge => 'That amount is too large';

  @override
  String get errorQuantityTooLarge => 'That quantity is too large';

  @override
  String get errorQuantityInvalid => 'Enter a quantity';

  @override
  String get errorQuantityInvalidCharacter => 'Digits only';

  @override
  String get errorQuantityNegativeNotAllowed => 'Enter a positive quantity';

  @override
  String get errorQuantityTooPrecise => 'Too precise for this unit';

  @override
  String get errorDateInvalid => 'Choose a date';

  @override
  String get confirmDeleteTitle => 'Delete this?';

  @override
  String get confirmDeleteBody => 'You can undo this for the next few seconds.';

  @override
  String get confirmDiscardTitle => 'Discard your changes?';

  @override
  String get confirmDiscardBody => 'What you have typed will not be saved.';

  @override
  String get labelAmount => 'Amount';

  @override
  String get labelQuantity => 'Quantity';

  @override
  String get labelUnit => 'Unit';

  @override
  String get labelDate => 'Date';

  @override
  String get labelAccount => 'Account';

  @override
  String get labelPaymentMethod => 'Payment method';

  @override
  String get labelPayee => 'Payee';

  @override
  String get labelCategory => 'Category';

  @override
  String get labelTags => 'Tags';

  @override
  String get labelNote => 'Note';

  @override
  String get labelFrom => 'From';

  @override
  String get labelTo => 'To';

  @override
  String get labelItem => 'Item';

  @override
  String get labelExpiry => 'Expiry';

  @override
  String get labelTotal => 'Total';

  @override
  String get hintSelectAccount => 'Choose an account';

  @override
  String get hintSelectUnit => 'Choose a unit';

  @override
  String get hintSelectTags => 'Choose tags';

  @override
  String get hintSelectDate => 'Choose a date';

  @override
  String get hintSearchItems => 'Search items';

  @override
  String get hintNote => 'Add a note';

  @override
  String amountUnconverted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count amounts not converted',
      one: '1 amount not converted',
    );
    return '$_temp0';
  }

  @override
  String get amountApproximate => 'Approximate rate';

  @override
  String tagCountMore(int count) {
    return '+$count';
  }

  @override
  String get statusNeedsReview => 'Needs details';

  @override
  String get statusUnallocated => 'Unallocated';

  @override
  String get statusDetached => 'Receipt deleted';

  @override
  String get statusApproximate => 'Approximate';

  @override
  String get lowStockLabel => 'Low';

  @override
  String get expiringSoonLabel => 'Expiring soon';

  @override
  String get expiredLabel => 'Expired';

  @override
  String get overdueLabel => 'Overdue';

  @override
  String get dueTodayLabel => 'Due today';

  @override
  String get paidLabel => 'Paid';

  @override
  String get skippedLabel => 'Skipped';

  @override
  String get kindDeposit => 'Income';

  @override
  String get kindWithdrawal => 'Expense';

  @override
  String get kindTransfer => 'Transfer';

  @override
  String get kindAdjustmentIncrease => 'Stock added';

  @override
  String get kindAdjustmentDecrease => 'Stock removed';

  @override
  String get subtypeGrocery => 'Groceries';

  @override
  String get subtypeHousehold => 'Household';

  @override
  String get subtypeElectronics => 'Electronics';

  @override
  String get subtypeBill => 'Bill';

  @override
  String get subtypeTransferSelf => 'Between my accounts';

  @override
  String get subtypeTransferOut => 'Sent to someone';

  @override
  String get subtypeSalaryIn => 'Salary';

  @override
  String get subtypeOtherIn => 'Other income';

  @override
  String get subtypeOtherOut => 'Other expense';

  @override
  String needsReviewBanner(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transactions need details',
      one: '1 transaction needs details',
    );
    return '$_temp0';
  }

  @override
  String get needsReviewAction => 'Review';

  @override
  String get filterTitle => 'Filter';

  @override
  String get filterDateRange => 'Date range';

  @override
  String get filterKind => 'Type';

  @override
  String get filterSubtype => 'Category';

  @override
  String get filterApply => 'Show results';

  @override
  String get filterReset => 'Reset';

  @override
  String filterChipAccount(String name) {
    return 'Account: $name';
  }

  @override
  String filterChipPayee(String name) {
    return 'Payee: $name';
  }

  @override
  String filterChipRange(String label) {
    return '$label';
  }

  @override
  String get rangeToday => 'Today';

  @override
  String get rangeLast7Days => 'Last 7 days';

  @override
  String get rangeLast30Days => 'Last 30 days';

  @override
  String get rangeThisMonth => 'This month';

  @override
  String get rangeLastMonth => 'Last month';

  @override
  String get rangeThisYear => 'This year';

  @override
  String get rangeAllTime => 'All time';

  @override
  String get rangeCustom => 'Custom';

  @override
  String get searchTransactionsHint => 'Search notes';

  @override
  String get transactionDeleted => 'Transaction deleted';

  @override
  String get quickAddTitle => 'Quick add';

  @override
  String get quickAddMoneyIn => 'Income';

  @override
  String get quickAddMoneyOut => 'Expense';

  @override
  String get quickAddSave => 'Save';

  @override
  String get actionAddDetails => 'Save and add details';

  @override
  String get editorTitleNew => 'New transaction';

  @override
  String get editorTitleEdit => 'Edit transaction';

  @override
  String get sectionWhatAndHowMuch => 'What and how much';

  @override
  String get sectionWhereItCameFrom => 'Where it came from';

  @override
  String get sectionWhereItWent => 'Where it went';

  @override
  String get sectionWhatYouBought => 'What you bought';

  @override
  String get sectionWarranty => 'Warranty';

  @override
  String get sectionSchedule => 'Schedule';

  @override
  String get transferOwnAccount => 'To my own account';

  @override
  String get transferSomeoneElse => 'To someone else';

  @override
  String get transferOwnAccountHelp =>
      'Moves money between your accounts. Your total does not change.';

  @override
  String get transferSomeoneElseHelp =>
      'Money leaves your accounts, so it is recorded as an expense.';

  @override
  String get alsoAddToInventory => 'Also add to inventory';

  @override
  String get destinationNone => 'Just an expense';

  @override
  String get destinationInventory => 'Save to Inventory';

  @override
  String get destinationAsset => 'Save to Services';

  @override
  String get destinationRecurring => 'Save to Recurring';

  @override
  String get lineAdd => 'Add item';

  @override
  String get lineDescription => 'Item';

  @override
  String get lineUnitPrice => 'Unit price';

  @override
  String get lineAmount => 'Line total';

  @override
  String lineCreatedLink(String name) {
    return 'Created: $name';
  }

  @override
  String payeeCreate(String name) {
    return 'New payee “$name”';
  }

  @override
  String get saveExpense => 'Save expense';

  @override
  String get saveIncome => 'Save income';

  @override
  String get saveTransfer => 'Save transfer';

  @override
  String get detailSectionLines => 'Items';

  @override
  String get detailSectionDetails => 'Details';

  @override
  String get actionFreezeConversion => 'Show in another currency';

  @override
  String frozenConversionNote(String date, String rate) {
    return 'Frozen on $date at $rate';
  }

  @override
  String get deleteReasonHint => 'Why? (optional)';

  @override
  String get actionDeleteTransaction => 'Delete transaction';

  @override
  String get labelSubtype => 'Category';

  @override
  String get labelKind => 'Type';

  @override
  String get themeLabTitle => 'Theme Lab';

  @override
  String get themeLabSubtitle =>
      'Every token, component and semantic colour, light and dark.';

  @override
  String get themeLabSectionSpacing => 'Spacing';

  @override
  String get themeLabSectionRadii => 'Radii';

  @override
  String get themeLabSectionTypography => 'Typography';

  @override
  String get themeLabSectionElevation => 'Elevation';

  @override
  String get themeLabSectionSemantic => 'Semantic colours';

  @override
  String get themeLabSectionSurfaces => 'Surface tiers';

  @override
  String get themeLabSectionComponents => 'Components';

  @override
  String get themeLabSectionPalettes => 'Palettes';

  @override
  String get themeLabLight => 'Light';

  @override
  String get themeLabDark => 'Dark';

  @override
  String get semanticIncome => 'Income';

  @override
  String get semanticExpense => 'Expense';

  @override
  String get semanticTransfer => 'Transfer';

  @override
  String get semanticWarning => 'Warning';

  @override
  String get semanticDanger => 'Danger';

  @override
  String get semanticSuccess => 'Success';

  @override
  String get semanticMuted => 'Muted';

  @override
  String get drawerSectionMoney => 'Money';

  @override
  String get drawerSectionHome => 'Home';

  @override
  String get drawerSectionMore => 'More';

  @override
  String get inventoryGroupFavourites => 'Favourites';

  @override
  String get inventoryGroupUntagged => 'Everything else';

  @override
  String get itemKindGeneric => 'General';

  @override
  String get itemKindFood => 'Food';

  @override
  String get itemKindMedicine => 'Medicine';

  @override
  String get itemKindBeauty => 'Beauty';

  @override
  String get itemKindHousehold => 'Household';

  @override
  String get itemKindOther => 'Other';

  @override
  String get filterFavouritesOnly => 'Favourites only';

  @override
  String get actionFavourite => 'Add to favourites';

  @override
  String get actionUnfavourite => 'Remove from favourites';

  @override
  String get outOfStockLabel => 'Out of stock';

  @override
  String itemBatchCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count batches',
      one: '1 batch',
    );
    return '$_temp0';
  }

  @override
  String get loadingInventory => 'Loading inventory';

  @override
  String get detailSectionBatches => 'Batches';

  @override
  String get batchOriginPurchase => 'From a purchase';

  @override
  String get batchOriginManual => 'Added by hand';

  @override
  String get batchOriginImported => 'Imported';

  @override
  String get batchOriginAdjustment => 'From an adjustment';

  @override
  String get labelPurchased => 'Purchased';

  @override
  String get labelStorageLocation => 'Stored in';

  @override
  String get labelUnitCost => 'Unit cost';

  @override
  String get labelInitial => 'Bought';

  @override
  String get labelNearestExpiry => 'Nearest expiry';

  @override
  String get labelDisplayUnit => 'Shown in';

  @override
  String get labelItemKind => 'Kind';

  @override
  String get labelLowStockThreshold => 'Low-stock level';

  @override
  String get labelExpiryNotifyDays => 'Warn before expiry';

  @override
  String get actionConsume => 'Use some';

  @override
  String get actionAddBatch => 'Add a batch';

  @override
  String get actionViewHistory => 'Movement history';

  @override
  String get actionDeleteItem => 'Delete item';

  @override
  String get confirmDeleteItemTitle => 'Delete this item?';

  @override
  String confirmDeleteItemBody(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count batches',
      one: '1 batch',
    );
    return 'Its $_temp0 go with it. The movement history stays, so what you already used is still recorded.';
  }

  @override
  String get itemDeleted => 'Item deleted';

  @override
  String expiresInDays(num days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Expires in $days days',
      one: 'Expires tomorrow',
      zero: 'Expires today',
    );
    return '$_temp0';
  }

  @override
  String expiredDaysAgo(num days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Expired $days days ago',
      one: 'Expired yesterday',
    );
    return '$_temp0';
  }

  @override
  String get sectionWhatItIs => 'What it is';

  @override
  String get sectionStockRules => 'Stock rules';

  @override
  String get unitCategoryWeight => 'Weight';

  @override
  String get unitCategoryVolume => 'Volume';

  @override
  String get unitCategoryCount => 'Count';

  @override
  String unitCategoryLocked(Object category) {
    return 'Measured in $category';
  }

  @override
  String get unitCategoryLockedHelp =>
      'This cannot change. Every batch and movement already recorded is stored in this measure, and there is no conversion between weight, volume and count.';

  @override
  String get expiryNotifyDaysHelp => 'Days of warning before a batch expires.';

  @override
  String get labelFavourite => 'Favourite';

  @override
  String get saveItem => 'Save item';

  @override
  String get sectionHowMuch => 'How much';

  @override
  String get sectionBatchDetails => 'Batch details';

  @override
  String get saveBatch => 'Save batch';

  @override
  String get batchSaved => 'Batch saved';

  @override
  String get hintStorageLocation => 'Freezer, pantry, bathroom shelf…';

  @override
  String get consumeTitle => 'Use stock';

  @override
  String get consumeKindConsume => 'Used';

  @override
  String get consumeKindWaste => 'Thrown away';

  @override
  String get consumeKindExpired => 'Expired';

  @override
  String get consumeRecorded => 'Recorded';

  @override
  String get consumeFromLabel => 'Taking from';

  @override
  String get consumeFefoNote => 'Oldest expiry first.';

  @override
  String consumeSpansBatches(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Spans $count batches, writing $count movements',
      one: 'Takes all of 1 batch',
    );
    return '$_temp0';
  }

  @override
  String get consumeOverAvailable => 'More than you have on hand';

  @override
  String get historyTitle => 'Movement history';

  @override
  String get movementKindOpeningIn => 'Opening stock';

  @override
  String get movementKindPurchaseIn => 'Bought';

  @override
  String get movementKindManualIn => 'Added by hand';

  @override
  String get movementKindConsume => 'Used';

  @override
  String get movementKindWaste => 'Thrown away';

  @override
  String get movementKindExpired => 'Expired';

  @override
  String get movementKindAdjustIn => 'Adjusted up';

  @override
  String get movementKindAdjustOut => 'Adjusted down';

  @override
  String get movementReversed => 'Reversed';

  @override
  String get movementIsReversal => 'Reverses an earlier movement';

  @override
  String get actionReverse => 'Reverse';

  @override
  String get confirmReverseTitle => 'Reverse this movement?';

  @override
  String get confirmReverseBody =>
      'An opposite movement is appended. Nothing is erased — both entries stay in the history.';

  @override
  String get movementReversedSnack => 'Movement reversed';

  @override
  String get emptyTitleNoMovements => 'Nothing recorded yet';

  @override
  String get emptyBodyNoMovements =>
      'Using, wasting or adjusting this batch will show up here.';

  @override
  String get emptyBodyNoBatches =>
      'Add a batch and it will appear here with its expiry.';

  @override
  String get batchQuantityLockedHelp =>
      'How much is left is worked out from the movement history. Use, waste or adjust the batch to change it.';

  @override
  String daysCount(num days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get groupByFavourites => 'Group favourites first';

  @override
  String get consumeCommitUsed => 'Record as used';

  @override
  String get consumeCommitWaste => 'Record as thrown away';

  @override
  String get consumeCommitExpired => 'Record as expired';

  @override
  String lowStockWithCount(Object count) {
    return 'Low · $count';
  }

  @override
  String get actionDeleteBatch => 'Delete batch';

  @override
  String get confirmDeleteBatchTitle => 'Delete this batch?';

  @override
  String get confirmDeleteBatchBody =>
      'The stock it still holds disappears from your on-hand total. What you already used stays in the movement history.';

  @override
  String get batchDeleted => 'Batch deleted';

  @override
  String get itemCreate => 'New item';

  @override
  String get itemCreateHint =>
      'No items yet — create one so this line becomes stock.';

  @override
  String get itemCreateCategoryPrompt =>
      'How is it measured? This cannot change later.';

  @override
  String get itemDuplicateBody =>
      'You already have this item, measured the same way. Open the one you have instead of adding a second.';

  @override
  String get itemUnitsMissingBody =>
      'No units are set up for this measure yet. Pick a different measure, or add units in Settings first.';

  @override
  String get itemSimilarNote =>
      'You also have this name under a different measure. That is fine — weight, volume and count never convert into each other.';

  @override
  String get actionOpenExisting => 'Open the one I have';

  @override
  String get shoppingEstimate => 'Estimated';

  @override
  String get shoppingSwitchList => 'Switch list';

  @override
  String shoppingCheckedCount(Object checked, Object total) {
    return '$checked of $total ticked';
  }

  @override
  String get emptyTitleNoEntries => 'Nothing on this list yet';

  @override
  String get emptyBodyNoEntries =>
      'Add what you need, or pull in suggestions from what is running low.';

  @override
  String get addEntry => 'Add';

  @override
  String get shoppingGroupUntagged => 'Everything else';

  @override
  String get actionUncheckAll => 'Untick everything';

  @override
  String get entryEditorTitle => 'What do you need?';

  @override
  String get entryFreeTextLabel => 'Name it';

  @override
  String get entryFreeTextHint => 'Television, birthday card, light bulbs…';

  @override
  String get entryLinkItem => 'Link to an item';

  @override
  String get entryNoItem => 'Not in my inventory';

  @override
  String get labelEstimatedPrice => 'Estimated price';

  @override
  String get entryNeedsSomething => 'Give it a name, or link it to an item';

  @override
  String get originAutoLowStock => 'Suggested';

  @override
  String get originPromoted => 'Yours now';

  @override
  String get actionSnooze => 'Snooze a week';

  @override
  String get actionDismiss => 'Not now';

  @override
  String get snoozedUntilLabel => 'Snoozed until';

  @override
  String get generateTitle => 'Running low';

  @override
  String get generateBody =>
      'These are below the level you set. Add the ones you want.';

  @override
  String get generateShortBy => 'Short by';

  @override
  String get generateRefresh => 'Check again';

  @override
  String get generateEmptyTitle => 'Nothing is running low';

  @override
  String get generateEmptyBody =>
      'Set a low-stock level on an item and it will show up here when it drops.';

  @override
  String generateAdded(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count suggestions added',
      one: '1 suggestion added',
    );
    return '$_temp0';
  }

  @override
  String get convertTitle => 'Turn into a purchase';

  @override
  String get convertBody =>
      'Each ticked entry becomes one line, marked for inventory. You confirm the amount and account next.';

  @override
  String get convertConfirm => 'Open the expense';

  @override
  String get convertNothingTitle => 'Nothing is ticked';

  @override
  String get convertNothingBody =>
      'Tick what you actually bought, then come back.';

  @override
  String convertLineCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lines',
      one: '1 line',
    );
    return '$_temp0';
  }

  @override
  String get listManagerTitle => 'Your lists';

  @override
  String get listNameLabel => 'List name';

  @override
  String get listCreate => 'New list';

  @override
  String get listRename => 'Rename';

  @override
  String get listSetDefault => 'Make default';

  @override
  String get listDefaultBadge => 'Default';

  @override
  String get listArchive => 'Archive';

  @override
  String get listUnarchive => 'Restore';

  @override
  String get listArchivedBadge => 'Archived';

  @override
  String get listArchivedSection => 'Archived';

  @override
  String get emptyTitleNoLists => 'No lists yet';

  @override
  String get emptyBodyNoLists => 'Create one and it becomes your default.';

  @override
  String get loadingShopping => 'Loading your list';

  @override
  String get actionAddToList => 'Add to my list';

  @override
  String get suggestionDismissed => 'Turned down';

  @override
  String get lineItemsTitle => 'What you bought';

  @override
  String get lineItemsManage => 'Add or edit items';

  @override
  String get lineItemsAdd => 'Add an item';

  @override
  String get lineItemsSaveAndAnother => 'Save & add another';

  @override
  String lineItemsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
      zero: 'No items yet',
    );
    return '$_temp0';
  }

  @override
  String get emptyTitleNoLineItems => 'Nothing itemised yet';

  @override
  String get emptyBodyNoLineItems =>
      'Add what was on the receipt. Anything you leave out still counts toward the total.';

  @override
  String get actionRemove => 'Remove';

  @override
  String get lineRemoved => 'Item removed';

  @override
  String get lineItemsAllocated => 'Itemised';

  @override
  String get recurringOutflow => 'Expenses';

  @override
  String get recurringInflow => 'Income';

  @override
  String get recurringNextDue => 'Next';

  @override
  String get recurringOverdue => 'Overdue';

  @override
  String get recurringPaused => 'Paused';

  @override
  String get recurringDueToday => 'Due today';

  @override
  String get emptyTitleNoTemplates => 'Nothing recurring yet';

  @override
  String get emptyBodyNoTemplates =>
      'Add a bill, a subscription or a salary and it will appear here when it is next due.';

  @override
  String get addTemplate => 'Add';

  @override
  String get actionPause => 'Pause';

  @override
  String get actionResume => 'Resume';

  @override
  String get loadingRecurring => 'Loading your schedule';

  @override
  String get builderSectionWhat => 'What it is';

  @override
  String get builderSectionWhen => 'How often';

  @override
  String get builderSectionDefaults => 'Defaults';

  @override
  String get labelTemplateName => 'Name';

  @override
  String get labelRecurringKind => 'Kind';

  @override
  String get labelDirection => 'Direction';

  @override
  String get directionOutflow => 'Expense';

  @override
  String get directionInflow => 'Income';

  @override
  String get kindBill => 'Bill';

  @override
  String get kindSubscription => 'Subscription';

  @override
  String get kindRent => 'Rent';

  @override
  String get kindSalary => 'Salary';

  @override
  String get labelEvery => 'Every';

  @override
  String unitDay(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days',
      one: 'day',
    );
    return '$_temp0';
  }

  @override
  String unitWeek(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'weeks',
      one: 'week',
    );
    return '$_temp0';
  }

  @override
  String unitMonth(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'months',
      one: 'month',
    );
    return '$_temp0';
  }

  @override
  String unitYear(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'years',
      one: 'year',
    );
    return '$_temp0';
  }

  @override
  String get labelAnchorDay => 'On day of the month';

  @override
  String get anchorDayHelp =>
      'Kept as you set it. Anchored on the 31st, a short month falls on its last day and the next long month returns to the 31st.';

  @override
  String get labelStartDate => 'Starts';

  @override
  String get labelEndDate => 'Ends';

  @override
  String get labelDefaultAmount => 'Usual amount';

  @override
  String get labelRemindBefore => 'Remind me';

  @override
  String get saveTemplate => 'Save';

  @override
  String get previewTitle => 'Next three';

  @override
  String get previewEmpty => 'Set a start date to see when this lands.';

  @override
  String get previewClamped => 'Shortened to fit the month';

  @override
  String get payTitle => 'Record this payment';

  @override
  String get payTitleInflow => 'Record this receipt';

  @override
  String get labelActualAmount => 'Amount actually paid';

  @override
  String get labelActualAmountInflow => 'Amount actually received';

  @override
  String get payUsualWas => 'Usually';

  @override
  String get labelPaidOn => 'Paid on';

  @override
  String get payCommit => 'Record it';

  @override
  String get payRecorded => 'Recorded';

  @override
  String get payNeedsAccount => 'Choose which account it came from';

  @override
  String get payUndoTitle => 'Undo this payment?';

  @override
  String get payUndoBody =>
      'The obligation goes back to due and the transaction it created is deleted. Anything that transaction produced — stock, an asset — goes with it.';

  @override
  String get payUndone => 'Payment undone';

  @override
  String get actionSkip => 'Skip this one';

  @override
  String get occurrenceSkipped => 'Skipped';

  @override
  String get historyRecurringTitle => 'Payment history';

  @override
  String get historyDefaultVsActual => 'Differed from the usual amount';

  @override
  String get emptyTitleNoOccurrences => 'Nothing due yet';

  @override
  String get emptyBodyNoOccurrences =>
      'Occurrences appear as their due dates arrive. Nothing is ever paid for you.';

  @override
  String get statusDue => 'Due';

  @override
  String get statusPaid => 'Paid';

  @override
  String get statusDismissed => 'Dismissed';

  @override
  String get kindServiceFee => 'Service fee';

  @override
  String get kindOther => 'Something else';

  @override
  String get billDueSection => 'Due now';

  @override
  String get billSetUpAction => 'Set up a recurring bill';

  @override
  String get billNothingDue => 'Nothing is due right now.';

  @override
  String get recurringScheduleNext => 'Saved. Now set how often it repeats.';

  @override
  String get recurringNotYetDue => 'Not due yet';

  @override
  String get billSettlesLabel => 'Settling';

  @override
  String get billSettleNone => 'Not a recurring bill';

  @override
  String get billSettleHelp =>
      'Pick one and the amount below becomes what you actually paid. Saving records it once.';

  @override
  String get billAmountBecomesPaid => 'This amount is what gets recorded';

  @override
  String get billAccountAuto => 'Paid from';

  @override
  String get billAccountAskOnce =>
      'Which account does this come from? Alaya remembers it on the bill.';

  @override
  String get assetGroupAppliance => 'Appliances';

  @override
  String get assetGroupElectronics => 'Electronics';

  @override
  String get assetGroupVehicle => 'Vehicles';

  @override
  String get assetGroupFurniture => 'Furniture';

  @override
  String get assetGroupProperty => 'Property';

  @override
  String get assetGroupServiceProvider => 'People';

  @override
  String get assetGroupSubscription => 'Subscriptions';

  @override
  String get assetGroupOther => 'Other';

  @override
  String get assetUnderWarranty => 'In warranty';

  @override
  String get assetWarrantyEnding => 'Warranty ending';

  @override
  String get assetWarrantyExpired => 'Out of warranty';

  @override
  String get assetServiceDue => 'Service due';

  @override
  String get assetServiceSoon => 'Service soon';

  @override
  String get assetDisposedChip => 'Disposed';

  @override
  String get assetUnderRepair => 'Being repaired';

  @override
  String get filterShowDisposed => 'Include disposed';

  @override
  String get emptyTitleNoAssets => 'Nothing tracked yet';

  @override
  String get emptyBodyNoAssets =>
      'Add an appliance, a vehicle, or the person who helps around the house — they all live here.';

  @override
  String get addAsset => 'Add';

  @override
  String get loadingAssets => 'Loading your things';

  @override
  String get assetSectionIdentity => 'Details';

  @override
  String get assetSectionWarranty => 'Warranty';

  @override
  String get assetSectionContact => 'Contact';

  @override
  String get assetSectionService => 'Service history';

  @override
  String get assetSectionSalary => 'Salary history';

  @override
  String get assetLifetimeCost => 'Spent on service so far';

  @override
  String get assetLifetimeSalary => 'Paid so far';

  @override
  String get labelBrand => 'Brand';

  @override
  String get labelModelNo => 'Model';

  @override
  String get labelSerialNo => 'Serial';

  @override
  String get labelPurchasePrice => 'Bought for';

  @override
  String get labelWarrantyStart => 'Warranty from';

  @override
  String get labelWarrantyEnd => 'Warranty until';

  @override
  String get labelWarrantyProvider => 'Covered by';

  @override
  String get labelServiceInterval => 'Service every';

  @override
  String get labelNextService => 'Next service';

  @override
  String get labelContactName => 'Name';

  @override
  String get labelContactPhone => 'Phone';

  @override
  String get labelLocation => 'Kept in';

  @override
  String get actionCall => 'Call';

  @override
  String get callFailed => 'No app on this phone can place that call.';

  @override
  String get actionAddService => 'Record a service';

  @override
  String get actionAddSalary => 'Record a payment';

  @override
  String get actionDispose => 'Dispose of it';

  @override
  String get actionUndispose => 'Bring it back';

  @override
  String get assetLinkedRecurring => 'Paid on a schedule';

  @override
  String get emptyBodyNoServices => 'Nothing recorded against this yet.';

  @override
  String get labelAssetName => 'What is it?';

  @override
  String get labelAssetType => 'Kind';

  @override
  String get assetTypeHelpPerson =>
      'A person you pay regularly belongs here too — their payments become service records.';

  @override
  String get saveAsset => 'Save';

  @override
  String get serviceIntervalHelp =>
      'Days between services. The next due date moves on each time you record one.';

  @override
  String get labelServiceType => 'What happened';

  @override
  String get serviceTypeService => 'Serviced';

  @override
  String get serviceTypeRepair => 'Repaired';

  @override
  String get serviceTypeMaintenance => 'Maintenance';

  @override
  String get serviceTypeInspection => 'Inspection';

  @override
  String get serviceTypeSalaryPaid => 'Salary paid';

  @override
  String get serviceTypeOther => 'Something else';

  @override
  String get labelProviderName => 'Who did it';

  @override
  String get labelProviderPhone => 'Their number';

  @override
  String get labelServiceDate => 'When';

  @override
  String get labelServiceCost => 'Cost';

  @override
  String get labelNextDue => 'Next one due';

  @override
  String get alsoRecordAsExpense => 'Also record it as an expense';

  @override
  String get alsoRecordHelp =>
      'Records an expense for the cost too, so it shows in your ledger.';

  @override
  String get alsoRecordNeedsAccount => 'Choose which account it comes from';

  @override
  String get alsoRecordNeedsCost => 'Add a cost first';

  @override
  String get saveService => 'Save';

  @override
  String get disposeTitle => 'What happened to it?';

  @override
  String get disposeBody =>
      'It stays in your records either way — what you spent on it still counts. This just stops it appearing as something you own.';

  @override
  String get disposeReasonSold => 'Sold it';

  @override
  String get disposeReasonExpired => 'Wore out';

  @override
  String get disposeReasonDamaged => 'Broke';

  @override
  String get disposeReasonGifted => 'Gave it away';

  @override
  String get disposeReasonLost => 'Lost it';

  @override
  String get disposeReasonReplaced => 'Replaced it';

  @override
  String get disposeReasonOther => 'Something else';

  @override
  String get labelDisposalAmount => 'Got back';

  @override
  String get labelDisposalDate => 'When';

  @override
  String get disposeCommit => 'Record it';

  @override
  String get disposeDone => 'Recorded';

  @override
  String get undisposeDone => 'Back in your list';

  @override
  String get disposeNeedsReason => 'Pick what happened';

  @override
  String get hintSearchAssets => 'Search your things and people';

  @override
  String get errorWarrantyBackwards =>
      'The warranty cannot end before it starts';

  @override
  String get sectionMoney => 'Money';

  @override
  String get assetCreatedFromPurchase =>
      'Saved. Now say what it is and how long it is covered.';

  @override
  String get destinationHelpNone => 'Recorded as an expense and nothing else.';

  @override
  String get destinationHelpInventory =>
      'Groceries, refills, anything measured and consumed. Needs an item and a quantity, and creates stock you can run down.';

  @override
  String get destinationHelpAsset =>
      'A phone, a fridge, a chair. Creates something you own, with its own warranty and service history.';

  @override
  String get destinationHelpRecurring =>
      'Sets up a schedule so this comes back every month.';

  @override
  String get assetSameNameNote =>
      'You already have one called this. That is fine — this will be a separate one, with its own warranty and service history.';

  @override
  String get actionSetWarranty => 'Set the warranty';

  @override
  String get labelPaymentMethodOptional => 'How you paid (optional)';

  @override
  String get dashboardTitle => 'Home';

  @override
  String get fundsAvailable => 'Total available funds';

  @override
  String fundsUnconverted(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count balances not converted',
      one: '1 balance not converted',
    );
    return '$_temp0';
  }

  @override
  String get fundsApproximate => 'Rate is older than today';

  @override
  String get fundsWhyExcluded =>
      'Balances Alaya has no rate for are left out rather than guessed at.';

  @override
  String get rangeLast30 => 'Last 30 days';

  @override
  String get rangeMoneyIn => 'In';

  @override
  String get rangeMoneyOut => 'Out';

  @override
  String get rangeNothingYet => 'Nothing yet';

  @override
  String rangeExcluded(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count left out',
      one: '1 left out',
    );
    return '$_temp0';
  }

  @override
  String get insightUpcoming => 'Coming up';

  @override
  String get insightSpending => 'Where it went';

  @override
  String get insightSwitchLabel => 'Show';

  @override
  String get insightNothingUpcoming =>
      'Nothing needs attention in the next fortnight.';

  @override
  String get insightBillDue => 'Bill due';

  @override
  String get insightServiceDue => 'Service due';

  @override
  String get insightWarrantyEnding => 'Warranty ending';

  @override
  String get insightBatchExpiring => 'Expiring';

  @override
  String get moduleGridTitle => 'Where to next';

  @override
  String moduleExpenses(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count this month',
      one: '1 this month',
      zero: 'none this month',
    );
    return '$_temp0';
  }

  @override
  String moduleInventory(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count running low',
      one: '1 running low',
      zero: 'nothing tracked',
    );
    return '$_temp0';
  }

  @override
  String moduleShopping(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count to buy',
      one: '1 to buy',
      zero: 'list is clear',
    );
    return '$_temp0';
  }

  @override
  String moduleRecurring(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count due',
      one: '1 due',
      zero: 'all settled',
    );
    return '$_temp0';
  }

  @override
  String moduleServices(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count need attention',
      one: '1 needs attention',
      zero: 'nothing needs doing',
    );
    return '$_temp0';
  }

  @override
  String get fabAddIncome => 'Add income';

  @override
  String get fabAddItem => 'New item';

  @override
  String get loadingDashboard => 'Adding it up';

  @override
  String get fabOpenLabel => 'Add something';

  @override
  String get fabCloseLabel => 'Close';

  @override
  String get eventTypeTransaction => 'Transaction';

  @override
  String get eventTypeRecurringDue => 'Recurring bill';

  @override
  String get eventTypeBatchExpiry => 'Expiring';

  @override
  String get eventTypeWarrantyEnd => 'Warranty ending';

  @override
  String get eventTypeServiceDue => 'Service due';

  @override
  String get eventTypeShoppingTarget => 'Shopping target';

  @override
  String get calendarSeverityWarning => 'Needs attention';

  @override
  String get calendarSeverityDanger => 'Past its date';

  @override
  String get calendarLoadingDay => 'Loading this day…';

  @override
  String get calendarDayErrorTitle => 'Could not load this day';

  @override
  String get calendarDayEmptyTitle => 'Nothing on this day';

  @override
  String get calendarDayEmptyBody =>
      'No transactions, bills, expiries or services fall here.';

  @override
  String get calendarRetry => 'Try again';

  @override
  String get calendarLoadingMonth => 'Loading this month…';

  @override
  String get calendarErrorTitle => 'Could not load the calendar';

  @override
  String get calendarPreviousMonth => 'Previous month';

  @override
  String get calendarNextMonth => 'Next month';

  @override
  String get calendarOnDay => 'On this day';

  @override
  String get calendarRangeOn => 'Select a range';

  @override
  String get calendarRangeOff => 'Stop selecting a range';

  @override
  String calendarRangePickEnd(String start) {
    return 'From $start — tap another day to finish.';
  }

  @override
  String calendarInRange(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get calendarRangeEmptyTitle => 'Nothing in these days';

  @override
  String get calendarRangeEmptyBody =>
      'No transactions, bills, expiries or services fall inside the range.';

  @override
  String get calendarBackToToday => 'Back to this month';

  @override
  String get calendarTotalOut => 'Expenses';

  @override
  String get calendarTotalIn => 'Income';

  @override
  String get dashboardOpenCalendar => 'Open calendar';

  @override
  String dashboardCalendarSemantics(String month) {
    return '$month at a glance. Opens the calendar.';
  }

  @override
  String get navBackToDashboard => 'Back to dashboard';

  @override
  String get chartLoading => 'Working it out…';

  @override
  String chartApproximate(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count figures are indicative',
      one: '1 figure is indicative',
    );
    return '$_temp0';
  }

  @override
  String chartUnconverted(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count amounts left out',
      one: '1 amount left out',
    );
    return '$_temp0';
  }

  @override
  String get analyticsTotalSpent => 'Expenses';

  @override
  String get analyticsRangeLabel => 'Reporting window';

  @override
  String analyticsComparisonUp(Object percent) {
    return '$percent more than the window before';
  }

  @override
  String analyticsComparisonDown(Object percent) {
    return '$percent less than the window before';
  }

  @override
  String analyticsUnconvertedTotal(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count amounts need a rate',
      one: '1 amount needs a rate',
    );
    return '$_temp0';
  }

  @override
  String get analyticsInflationTitle => 'Your own inflation';

  @override
  String get analyticsInflationSubtitle =>
      'What one thing costs you, purchase by purchase';

  @override
  String analyticsInflationUp(Object percent) {
    return '$percent more than the first time in this window';
  }

  @override
  String analyticsInflationDown(Object percent) {
    return '$percent less than the first time in this window';
  }

  @override
  String get analyticsInflationSince => 'First bought';

  @override
  String get analyticsInflationEmpty =>
      'Buy something twice and its price trend appears here. Widen the window if you have.';

  @override
  String get analyticsSectionSpend => 'Where it went';

  @override
  String get analyticsSectionTime => 'Over time';

  @override
  String get analyticsSectionWhat => 'Who and what';

  @override
  String get analyticsSectionHome => 'Your home';

  @override
  String get analyticsSectionCommitments => 'Already committed';

  @override
  String get analyticsBySubtype => 'By kind';

  @override
  String get analyticsByTag => 'By tag';

  @override
  String get analyticsByTagNote =>
      'A purchase with two tags counts in both, so these add up to more than the total';

  @override
  String get analyticsByMethod => 'By payment method';

  @override
  String get analyticsConcentration => 'How concentrated';

  @override
  String analyticsTopShare(Object percent) {
    return '$percent of your spending sits in three kinds';
  }

  @override
  String analyticsGroceryShare(Object percent) {
    return 'Groceries are $percent of it';
  }

  @override
  String analyticsTagChildren(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tags inside',
      one: '1 tag inside',
    );
    return '$_temp0';
  }

  @override
  String analyticsTagDirect(Object tag) {
    return '$tag on its own';
  }

  @override
  String get analyticsTagBack => 'Back to all tags';

  @override
  String get analyticsNothingSpent => 'Nothing spent in this window';

  @override
  String get analyticsNoTaggedSpend => 'Tag a purchase and it will appear here';

  @override
  String get analyticsNoMethodSpend =>
      'Record how you paid and it will appear here';

  @override
  String get analyticsIncomeVsExpense => 'In and out';

  @override
  String get analyticsNeedTwoMonths =>
      'Two months of records and the trend appears here';

  @override
  String get analyticsNetFlow => 'What you kept';

  @override
  String get analyticsNetFlowNote =>
      'Moving money between your own accounts does not count';

  @override
  String get analyticsNoFlow => 'Nothing moved in this window';

  @override
  String get analyticsBalanceTrend => 'Balance over time';

  @override
  String analyticsBalanceIn(Object account, Object currency) {
    return '$account, in $currency';
  }

  @override
  String get analyticsAccount => 'Account';

  @override
  String get analyticsNoBalanceMovement =>
      'No movement on this account in this window';

  @override
  String get analyticsHeatmap => 'When you spend';

  @override
  String get analyticsByWeekday => 'By day of week';

  @override
  String get analyticsByDayOfMonth => 'By date';

  @override
  String get analyticsTopPayees => 'Who you paid most';

  @override
  String get analyticsNoPayees => 'Name who you paid and they will appear here';

  @override
  String get analyticsTopItems => 'What cost you most';

  @override
  String get analyticsNoItemisedSpend =>
      'Itemise a purchase and it will appear here';

  @override
  String get analyticsTopByQuantity => 'What you buy most of';

  @override
  String get analyticsTopByQuantityNote =>
      'Grouped by measure, because weight and count cannot be compared';

  @override
  String get analyticsNoQuantities =>
      'Record how much you bought and it will appear here';

  @override
  String analyticsPurchaseCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count purchases',
      one: '1 purchase',
    );
    return '$_temp0';
  }

  @override
  String get analyticsDearest => 'The most you have paid';

  @override
  String get analyticsDearestItem => 'Item';

  @override
  String get analyticsDearestPrice => 'Unit price';

  @override
  String get analyticsDearestWhen => 'When';

  @override
  String get analyticsNoUnitPrices =>
      'Record a unit price and this appears here';

  @override
  String get analyticsAverageBasket => 'Your average shop';

  @override
  String get analyticsBasketValue => 'Average value';

  @override
  String get analyticsBasketLines => 'Average items';

  @override
  String get analyticsBasketCount => 'Shops counted';

  @override
  String get analyticsNoBaskets =>
      'Record a grocery shop and it will appear here';

  @override
  String get analyticsInventoryValue => 'What is on your shelves';

  @override
  String get analyticsInventoryValueNote =>
      'Right now, whatever window you have chosen';

  @override
  String analyticsBatchesValued(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count batches valued',
      one: '1 batch valued',
    );
    return '$_temp0';
  }

  @override
  String analyticsBatchesNoCost(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count batches have no cost',
      one: '1 batch has no cost',
    );
    return '$_temp0';
  }

  @override
  String get analyticsNoStockValue =>
      'Record what a batch cost and its value appears here';

  @override
  String get analyticsWaste => 'What you threw away';

  @override
  String get analyticsNoWaste => 'Nothing wasted in this window';

  @override
  String analyticsExpiring(int days) {
    return 'Expiring within $days days';
  }

  @override
  String get analyticsNothingExpiring => 'Nothing expires soon';

  @override
  String analyticsDaysLeft(num days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days left',
      one: '1 day left',
    );
    return '$_temp0';
  }

  @override
  String get analyticsExpiredAlready => 'Past its date';

  @override
  String get analyticsLowStock => 'Running low';

  @override
  String get analyticsLowStockNote =>
      'A count for today, not a history: stock levels are not kept over time';

  @override
  String analyticsLowStockCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items below their threshold',
      one: '1 item below its threshold',
    );
    return '$_temp0';
  }

  @override
  String get analyticsAsOf => 'As of';

  @override
  String get analyticsNothingLow => 'Nothing is running low';

  @override
  String get analyticsCommitment => 'Every month, before anything else';

  @override
  String get analyticsCommitmentNote =>
      'Bills and subscriptions only. Income is not netted off';

  @override
  String analyticsCommitmentCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'from $count commitments',
      one: 'from 1 commitment',
    );
    return '$_temp0';
  }

  @override
  String get analyticsNoCommitments =>
      'Add a bill or subscription and it will appear here';

  @override
  String get analyticsRecurringSplit => 'Fixed against chosen';

  @override
  String get analyticsRecurring => 'Fixed';

  @override
  String get analyticsDiscretionary => 'Chosen';

  @override
  String analyticsRecurringShare(Object percent) {
    return '$percent of your spending was already committed';
  }

  @override
  String get analyticsServiceCost => 'What your things cost to keep';

  @override
  String analyticsServiceCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count visits',
      one: '1 visit',
    );
    return '$_temp0';
  }

  @override
  String get analyticsNoServiceCost =>
      'Record a service or repair and it will appear here';

  @override
  String get analyticsWarranty => 'Warranties';

  @override
  String get analyticsCovered => 'Covered';

  @override
  String get analyticsCoverageEnded => 'Cover ended';

  @override
  String get analyticsNoWarranties =>
      'Add a warranty date and it will appear here';

  @override
  String get analyticsEmptyTitle => 'Nothing to show for this window';

  @override
  String get analyticsEmptyBody =>
      'Widen the window above, or record something and it will appear here.';

  @override
  String get analyticsCacheClear => 'Recalculate everything';

  @override
  String get analyticsCacheClearing => 'Recalculating…';

  @override
  String get analyticsCacheExplain =>
      'Some figures are kept between visits so this screen opens quickly. Clear them if a number looks stale.';

  @override
  String get analyticsCacheCleared => 'Recalculated';

  @override
  String get analyticsCacheClearedSnack => 'Figures recalculated';

  @override
  String get analyticsCacheFailed => 'Could not clear the saved figures';

  @override
  String get analyticsDrillTitle => 'Behind this figure';

  @override
  String get analyticsDrillTotal => 'These come to';

  @override
  String get analyticsDrillLoading => 'Loading these transactions…';

  @override
  String get analyticsDrillEmptyTitle => 'Nothing here in this window';

  @override
  String get analyticsDrillEmptyBody =>
      'The window is set on the insights screen. Widen it and these may appear.';

  @override
  String get analyticsDrillUnknownTitle => 'This link does not point anywhere';

  @override
  String get analyticsDrillUnknownBody =>
      'Open insights and choose a figure to look behind.';

  @override
  String get analyticsOtherSlices => 'Everything else';

  @override
  String get analyticsTopThree => 'in three kinds';

  @override
  String get aboutHowItWorksHeader => 'How it works';

  @override
  String get aboutLicences => 'Open source licences';

  @override
  String get aboutLicencesHelp => 'The libraries Alaya is built on.';

  @override
  String get aboutOfflineBody =>
      'Everything is stored on this device. Alaya only reaches the internet to fetch exchange rates, once a day.';

  @override
  String get aboutStorageBody =>
      'Your data is not encrypted, and no copy of it exists anywhere else unless you make a backup yourself.';

  @override
  String get aboutTagline =>
      'A finance and home manager that works entirely on your phone.';

  @override
  String get accountCurrencyHeader => 'Currency';

  @override
  String get accountCurrencyLockedHelp =>
      'Fixed, because changing it would reinterpret every amount already recorded here.';

  @override
  String get accountCurrencyNewHelp =>
      'What this account holds. It cannot be changed once you start recording against it.';

  @override
  String get accountEditorEditTitle => 'Edit account';

  @override
  String get accountEditorSave => 'Save account';

  @override
  String get accountEditorTitle => 'New account';

  @override
  String get accountIncludeInNetWorth => 'Count in net worth';

  @override
  String get accountIncludeInNetWorthHelp =>
      'Off means the balance still shows here, but is left out of your total. Useful for an account you hold for someone else.';

  @override
  String get accountKindBank => 'Bank';

  @override
  String get accountKindCard => 'Card';

  @override
  String get accountKindCash => 'Cash';

  @override
  String get accountKindHeader => 'What kind?';

  @override
  String get accountKindOther => 'Other';

  @override
  String get accountKindWallet => 'Wallet';

  @override
  String get accountNameLabel => 'Name';

  @override
  String get accountOpeningBalanceLabel => 'Opening balance';

  @override
  String get accountOpeningDateLabel => 'True on';

  @override
  String get accountsAdd => 'Add an account';

  @override
  String get accountsArchive => 'Archive this account';

  @override
  String get accountsArchiveConfirmBody =>
      'It will stop appearing when you record anything. Its history stays, and you can restore it here at any time.';

  @override
  String get accountsArchiveConfirmTitle => 'Archive this account?';

  @override
  String get accountsArchiveHelp =>
      'An archived account keeps all its history. It just stops appearing when you record something.';

  @override
  String get accountsArchived => 'Account archived';

  @override
  String get accountsArchivedChip => 'Archived';

  @override
  String get accountsArchivedHeader => 'Archived';

  @override
  String get accountsEmptyBody => 'Add one so Alaya knows where your money is.';

  @override
  String get accountsEmptyTitle => 'No accounts yet';

  @override
  String get accountsExcludedChip => 'Not in net worth';

  @override
  String get accountsLoading => 'Loading your accounts…';

  @override
  String get accountsMissingBody =>
      'It may have been removed. Go back and pick another.';

  @override
  String get accountsMissingTitle => 'That account is not here';

  @override
  String get accountsRestore => 'Restore this account';

  @override
  String get accountsRestoreConfirmBody =>
      'It will appear again everywhere you choose an account.';

  @override
  String get accountsRestoreConfirmTitle => 'Restore this account?';

  @override
  String get accountsRestored => 'Account restored';

  @override
  String get accountsSaved => 'Account saved';

  @override
  String get actionBack => 'Back';

  @override
  String get actionContinue => 'Continue';

  @override
  String get appearanceModeDark => 'Always dark';

  @override
  String get appearanceModeHeader => 'Light or dark';

  @override
  String get appearanceModeLight => 'Always light';

  @override
  String get appearanceModeSystem => 'Match my phone';

  @override
  String get appearanceModeSystemHelp =>
      'Follows your phone’s light and dark setting.';

  @override
  String get appearancePaletteHeader => 'Colours';

  @override
  String get appearanceThemeLabHelp =>
      'See every colour, spacing and text style the app uses.';

  @override
  String get backupNotEncryptedWarning =>
      'This backup is not encrypted. Anyone who opens this file can read every transaction, balance and account name. Only share it somewhere you trust.';

  @override
  String get currenciesHomeLocked =>
      'Cannot be turned off — your totals are added up in this.';

  @override
  String get currenciesLoading => 'Loading currencies…';

  @override
  String get currenciesToggleFailed => 'That could not be changed';

  @override
  String get dataBackupHeader => 'Backup';

  @override
  String get dataExportBody =>
      'Sends a copy of your data to WhatsApp, Drive, or anywhere else you choose.';

  @override
  String get dataExportConfirmAction => 'Share it';

  @override
  String get dataExportConfirmTitle => 'Share a backup?';

  @override
  String get dataExportFailed => 'The backup could not be made';

  @override
  String get dataExportTitle => 'Share a backup';

  @override
  String get dataRestoreHeader => 'Restore';

  @override
  String get dataRestorePending => 'Coming in the next update.';

  @override
  String get dataRestoreTitle => 'Restore from a backup';

  @override
  String get lockBackspace => 'Delete last digit';

  @override
  String get lockBiometricFailed => 'Not recognised. Enter your PIN instead.';

  @override
  String get lockBiometricReason => 'Unlock Alaya';

  @override
  String get lockEraseFailed =>
      'The data could not be deleted. Your PIN is unchanged.';

  @override
  String get lockErasing => 'Deleting everything on this device…';

  @override
  String get lockForgotPin => 'I have forgotten my PIN';

  @override
  String get lockHonestBody =>
      'This PIN stops someone who picks up your unlocked phone from opening Alaya. It does not encrypt your data — anyone with access to the phone\'s files can still read them. Your phone\'s own lock screen is what protects the file itself.';

  @override
  String get lockThrottledWhy =>
      'The wait gets longer after each wrong attempt.';

  @override
  String get lockTitle => 'Enter your PIN';

  @override
  String get lockUseBiometric => 'Use fingerprint';

  @override
  String get lockWrongPin => 'That PIN is not right.';

  @override
  String get onboardingAccountsBody =>
      'Where do you keep your money? Add the ones you use.';

  @override
  String get onboardingAccountsTitle => 'Your accounts';

  @override
  String get onboardingAddAccount => 'Add an account';

  @override
  String get onboardingCurrencyBody =>
      'Which currency should Alaya add your totals up in?';

  @override
  String get onboardingCurrencyNote =>
      'This changes how totals are shown. It does not change any amount you have already recorded, and each account keeps its own currency.';

  @override
  String get onboardingCurrencyTitle => 'Your currency';

  @override
  String get onboardingFinish => 'Finish';

  @override
  String get onboardingLoading => 'Getting things ready…';

  @override
  String get onboardingLockOnBody =>
      'Alaya will ask for your PIN when you open it. You can change or remove it in Settings › Security.';

  @override
  String get onboardingLockOnHeader => 'Lock is on';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingNoAccountsBody =>
      'Add at least one so Alaya knows where your money is.';

  @override
  String get onboardingNoAccountsTitle => 'No accounts yet';

  @override
  String get onboardingOpeningNote =>
      'The opening balance is what was there on the date you give. Alaya needs both: a balance with no date cannot be placed in your ledger, and anything you record before that date would not be counted.';

  @override
  String get onboardingRemoveAccount => 'Remove this account';

  @override
  String get onboardingSaveAccounts => 'Save accounts';

  @override
  String get onboardingSecurityBody =>
      'You can put a PIN on Alaya. This is optional and you can add one later.';

  @override
  String get onboardingSecurityTitle => 'Lock the app?';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingSkipBody =>
      'You can change all of this later in Settings.';

  @override
  String get onboardingSkipTitle => 'Skip setting up?';

  @override
  String get onboardingTitle => 'Welcome to Alaya';

  @override
  String get payeeKindEmployer => 'Employer';

  @override
  String get payeeKindMerchant => 'Shop';

  @override
  String get payeeKindOther => 'Other';

  @override
  String get payeeKindPerson => 'Person';

  @override
  String get payeeKindUtility => 'Utility';

  @override
  String get payeeNameLabel => 'Name';

  @override
  String get payeePhoneOptionalLabel => 'Phone (optional)';

  @override
  String get payeesAdd => 'Add a payee';

  @override
  String get payeesDelete => 'Delete';

  @override
  String get payeesDeleteConfirmBody =>
      'Transactions that named them keep their record. They just stop being suggested.';

  @override
  String get payeesDeleteConfirmTitle => 'Delete this payee?';

  @override
  String get payeesDeleteFailed => 'That could not be deleted';

  @override
  String get payeesDeleted => 'Payee deleted';

  @override
  String get payeesEditTitle => 'Edit payee';

  @override
  String get payeesEmptyBody => 'These build up as you record who you paid.';

  @override
  String get payeesEmptyTitle => 'No payees yet';

  @override
  String get payeesLoading => 'Loading payees…';

  @override
  String get payeesNoMatchBody => 'Try part of the name.';

  @override
  String get payeesNoMatchTitle => 'No payees match that';

  @override
  String get payeesSave => 'Save payee';

  @override
  String get payeesSaveFailed => 'That could not be saved';

  @override
  String get payeesSaved => 'Payee saved';

  @override
  String get payeesSearchHint => 'Search payees';

  @override
  String get paymentKindBankTransfer => 'Bank transfer';

  @override
  String get paymentKindCard => 'Card';

  @override
  String get paymentKindCash => 'Cash';

  @override
  String get paymentKindCheque => 'Cheque';

  @override
  String get paymentKindOther => 'Other';

  @override
  String get paymentKindUpi => 'UPI';

  @override
  String get paymentKindWallet => 'Wallet';

  @override
  String get paymentMethodNameLabel => 'Name';

  @override
  String get paymentMethodsAdd => 'Add a payment method';

  @override
  String get paymentMethodsDelete => 'Delete';

  @override
  String get paymentMethodsDeleteConfirmBody =>
      'Transactions that used it keep their record of having done so. It just stops being offered.';

  @override
  String get paymentMethodsDeleteConfirmTitle => 'Delete this payment method?';

  @override
  String get paymentMethodsDeleteFailed => 'That could not be deleted';

  @override
  String get paymentMethodsDeleted => 'Payment method deleted';

  @override
  String get paymentMethodsEditTitle => 'Edit payment method';

  @override
  String get paymentMethodsEmptyBody =>
      'Add how you usually pay — cash, UPI, a card.';

  @override
  String get paymentMethodsEmptyTitle => 'No payment methods';

  @override
  String get paymentMethodsLoading => 'Loading payment methods…';

  @override
  String get paymentMethodsSave => 'Save payment method';

  @override
  String get paymentMethodsSaveFailed => 'That could not be saved';

  @override
  String get paymentMethodsSaved => 'Payment method saved';

  @override
  String get paymentMethodsSystemChip => 'Built in';

  @override
  String get pinSetupBackupBody =>
      'You have just put a lock on this app. A backup means a forgotten PIN never costs you your records.';

  @override
  String get pinSetupBackupHeader => 'Make a backup?';

  @override
  String get pinSetupBackupLater => 'Not now';

  @override
  String get pinSetupBackupNow => 'Back up now';

  @override
  String get pinSetupConfirmPrompt => 'Enter it again';

  @override
  String get pinSetupDone => 'Your PIN is set';

  @override
  String get pinSetupDoneBody =>
      'Alaya will ask for it when you open the app, and again after a minute in the background.';

  @override
  String get pinSetupEnterPrompt => 'Choose a PIN';

  @override
  String get pinSetupMismatch => 'Those did not match. Start again.';

  @override
  String get pinSetupRecoveryAck => 'I have saved this code somewhere safe';

  @override
  String get pinSetupRecoveryBody =>
      'This is the only way back in if you forget your PIN. It is shown once and cannot be shown again.';

  @override
  String get pinSetupRecoveryCopied => 'Recovery code copied';

  @override
  String get pinSetupRecoveryCopy => 'Copy code';

  @override
  String get pinSetupRecoveryHeader => 'Your recovery code';

  @override
  String get pinSetupRecoveryWhereToKeep =>
      'A password manager is a good place for it. A photo in your gallery is not.';

  @override
  String get pinSetupTitle => 'Set a PIN';

  @override
  String get recoveryCodeLabel => 'Recovery code';

  @override
  String get recoveryCodePrompt =>
      'Enter the recovery code you saved when you set your PIN.';

  @override
  String get recoveryDone => 'Your PIN has been changed';

  @override
  String get recoveryEraseEverything => 'Erase everything';

  @override
  String get recoveryExportFirst => 'Export a copy first';

  @override
  String get recoveryExported =>
      'A copy has been shared. Check it arrived before you erase.';

  @override
  String get recoveryForgotBoth => 'I do not have the recovery code either';

  @override
  String get recoveryForgotBothBody =>
      'Without your PIN or your recovery code there is no way back into this data. You can export a copy first, then erase everything and start again.';

  @override
  String get recoveryForgotBothTitle => 'Starting over';

  @override
  String get recoveryNewPinPrompt => 'Choose a new PIN';

  @override
  String get recoveryTitle => 'Forgotten PIN';

  @override
  String get securityAutoEraseConfirmAction => 'Turn it on';

  @override
  String get securityAutoEraseConfirmTitle =>
      'Turn on erase after repeated failures?';

  @override
  String get securityAutoEraseFailed => 'That could not be changed';

  @override
  String get securityAutoEraseHeader => 'If the PIN is entered wrongly';

  @override
  String get securityAutoEraseOff => 'Erase after repeated failures is off';

  @override
  String get securityAutoEraseOn => 'Erase after repeated failures is on';

  @override
  String get securityAutoEraseTitle =>
      'Erase everything after repeated failures';

  @override
  String get securityAutoLockHeader => 'Auto-lock';

  @override
  String get securityAutoLockTitle => 'Lock when I leave the app';

  @override
  String get securityChangePin => 'Change PIN';

  @override
  String get securityChecking => 'Checking…';

  @override
  String get securityPinHeader => 'PIN';

  @override
  String get securityRemovePin => 'Remove PIN';

  @override
  String get securityRemovePinConfirmBody =>
      'Anyone who picks up your unlocked phone will be able to open Alaya. You will be asked for your current PIN next.';

  @override
  String get securityRemovePinConfirmTitle => 'Remove the PIN?';

  @override
  String get securityRemovePinHelp =>
      'You will need your current PIN to do this.';

  @override
  String get securitySetPin => 'Set a PIN';

  @override
  String get securitySetPinHelp =>
      'Alaya will ask for it when you open the app.';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsAccounts => 'Accounts';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsCurrencies => 'Currencies';

  @override
  String get settingsData => 'Data';

  @override
  String get settingsGroupApp => 'The app';

  @override
  String get settingsGroupMoney => 'Your money';

  @override
  String get settingsGroupThings => 'Your things';

  @override
  String get settingsNoMatchBody =>
      'Try a different word — \"dark\", \"PIN\" and \"backup\" all find something.';

  @override
  String get settingsNoMatchTitle => 'Nothing matches that';

  @override
  String get settingsPayees => 'Payees';

  @override
  String get settingsPaymentMethods => 'Payment methods';

  @override
  String get settingsSearchHint => 'Search settings';

  @override
  String get settingsSecurity => 'Security';

  @override
  String get settingsTags => 'Tags';

  @override
  String get settingsUnits => 'Units';

  @override
  String get tagColourHeader => 'Colour';

  @override
  String get tagColourHelp =>
      'Optional. Kept as chosen, so it stays the same if you change the app’s palette later.';

  @override
  String get tagColourNone => 'No colour';

  @override
  String get tagColourSwatch => 'Use this colour';

  @override
  String get tagEditorEditTitle => 'Edit tag';

  @override
  String get tagEditorSave => 'Save tag';

  @override
  String get tagEditorTitle => 'New tag';

  @override
  String get tagNameLabel => 'Name';

  @override
  String get tagParentHeader => 'Group under';

  @override
  String get tagParentHelp =>
      'Optional. Grouping keeps long tag lists readable. Only one level deep.';

  @override
  String get tagParentNone => 'No group';

  @override
  String get tagScopeDeposit => 'Income';

  @override
  String get tagScopeDepositHelp => 'Offered when you record income.';

  @override
  String get tagScopeInventory => 'Items';

  @override
  String get tagScopeInventoryHelp => 'Offered on things you keep at home.';

  @override
  String get tagScopeRecurring => 'Recurring';

  @override
  String get tagScopeRecurringHelp => 'Offered on bills and subscriptions.';

  @override
  String get tagScopeService => 'Services';

  @override
  String get tagScopeServiceHelp =>
      'Offered on appliances and their service records.';

  @override
  String get tagScopeShopping => 'Shopping lists';

  @override
  String get tagScopeShoppingHelp =>
      'Used to group a shopping list under headings.';

  @override
  String get tagScopeWithdrawal => 'Expenses';

  @override
  String get tagScopeWithdrawalHelp => 'Offered when you record an expense.';

  @override
  String get tagScopesHeader => 'Where it appears';

  @override
  String get tagScopesHelp =>
      'A tag is only offered where you turn it on. This is what keeps \"Kitchen\" out of the list when you record your salary.';

  @override
  String get tagsAdd => 'Add a tag';

  @override
  String get tagsDelete => 'Delete this tag';

  @override
  String get tagsDeleteConfirmBody =>
      'Transactions and items already carrying it keep it in their history. It stops appearing when you tag something new.';

  @override
  String get tagsDeleteConfirmTitle => 'Delete this tag?';

  @override
  String get tagsDeleteHelp =>
      'Anything already tagged keeps its history. The tag just stops being offered.';

  @override
  String get tagsDeleted => 'Tag deleted';

  @override
  String get tagsEmptyBody =>
      'Tags let you group things across accounts — \"Kitchen\", \"Car\", \"Diwali\".';

  @override
  String get tagsEmptyTitle => 'No tags yet';

  @override
  String get tagsLoading => 'Loading tags…';

  @override
  String get tagsMissingBody =>
      'It may have been deleted. Go back and pick another.';

  @override
  String get tagsMissingTitle => 'That tag is not here';

  @override
  String get tagsNoScopesWarning =>
      'This tag is not offered anywhere. Turn on at least one place below, or it will never appear.';

  @override
  String get tagsSaved => 'Tag saved';

  @override
  String get tagsSystemChip => 'Built in';

  @override
  String get unitBaseGrams => 'grams';

  @override
  String get unitBaseMillilitres => 'millilitres';

  @override
  String get unitBasePieces => 'pieces';

  @override
  String get unitCategoryHeader => 'What does it measure?';

  @override
  String get unitCategoryNewHelp =>
      'Choose carefully: this cannot be changed later.';

  @override
  String get unitCodeHelp =>
      'What you will see beside a quantity — kg, ml, pc.';

  @override
  String get unitCodeLabel => 'Short code';

  @override
  String get unitCodeLockedHelp =>
      'Fixed once the unit exists, because other records point at it.';

  @override
  String get unitEditorEditTitle => 'Edit unit';

  @override
  String get unitEditorSave => 'Save unit';

  @override
  String get unitEditorTitle => 'New unit';

  @override
  String get unitFactorHeader => 'How big is it?';

  @override
  String get unitFactorMustBePositive => 'That has to be more than zero.';

  @override
  String get unitFactorThisUnit => 'this unit';

  @override
  String get unitFactorVaries => 'It varies — I cannot give one number';

  @override
  String get unitNameLabel => 'Name';

  @override
  String get unitVariesBack => 'Actually, I can give a number';

  @override
  String get unitVariesCreateItem => 'Create an item instead';

  @override
  String get unitVariesInsteadBody =>
      'Add \"Biscuit packet\" as its own item, counted in pieces. Then two packets is two of that item, and Alaya can price and track them properly.';

  @override
  String get unitVariesInsteadTitle => 'Make it an item instead';

  @override
  String get unitVariesTitle => 'Then it is not a unit';

  @override
  String get unitVariesWhy =>
      'A unit has to be the same amount every time. One packet of biscuits and one packet of rice are different weights, so Alaya could not add two packets together or work out what one cost.';

  @override
  String get unitsAdd => 'Add a unit';

  @override
  String get unitsCategoriesFixedNote =>
      'Weight, volume and count are the only three kinds there are. Alaya never converts between them, so a kilo can never become a litre by accident.';

  @override
  String get unitsDelete => 'Delete this unit';

  @override
  String get unitsDeleteConfirmBody =>
      'Anything already bought in this unit keeps its quantity, but that quantity would no longer be readable. Only delete a unit you have not used.';

  @override
  String get unitsDeleteConfirmTitle => 'Delete this unit?';

  @override
  String get unitsDeleteHelp =>
      'Only possible while nothing is measured in it.';

  @override
  String get unitsDeleted => 'Unit deleted';

  @override
  String get unitsEmptyBody =>
      'Alaya ships with the common ones. Add one if you measure something differently.';

  @override
  String get unitsEmptyTitle => 'No units';

  @override
  String get unitsLoading => 'Loading units…';

  @override
  String get unitsMissingBody =>
      'It may have been deleted. Go back and pick another.';

  @override
  String get unitsMissingTitle => 'That unit is not here';

  @override
  String get unitsSaved => 'Unit saved';

  @override
  String get unitsSystemChip => 'Built in';

  @override
  String currenciesRowSubtitle(String symbol, int digits) {
    String _temp0 = intl.Intl.pluralLogic(
      digits,
      locale: localeName,
      other: '$digits decimal places',
      one: '1 decimal place',
      zero: 'no decimal places',
    );
    return '$symbol · $_temp0';
  }

  @override
  String currenciesRowTitle(String code, String name) {
    return '$code · $name';
  }

  @override
  String dataExportDone(String fileName) {
    return 'Backup saved as $fileName';
  }

  @override
  String lockThrottled(String time) {
    return 'Too many attempts. Try again in $time';
  }

  @override
  String onboardingCurrencyChip(String code, String symbol) {
    return '$code $symbol';
  }

  @override
  String onboardingStepOf(int step, int total) {
    return 'Step $step of $total';
  }

  @override
  String pinSetupLength(int length) {
    return '$length digits';
  }

  @override
  String recoveryTypeToConfirm(String word) {
    return 'Type $word to confirm';
  }

  @override
  String securityAutoEraseBody(int count) {
    return 'When on, $count wrong PIN attempts in a row will delete everything on this device.';
  }

  @override
  String securityAutoEraseConfirmBody(int count) {
    return 'After $count failed attempts, every account, transaction and item on this device is deleted. There is no undo, and no copy unless you have made a backup.';
  }

  @override
  String securityAutoLockBody(int seconds) {
    return 'Locks again after $seconds seconds in the background.';
  }

  @override
  String settingsAccountCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count accounts',
      one: '1 account',
      zero: 'No accounts',
    );
    return '$_temp0';
  }

  @override
  String settingsCurrencyCount(int enabled, int total) {
    return '$enabled of $total enabled';
  }

  @override
  String settingsPayeeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count payees',
      one: '1 payee',
      zero: 'No payees',
    );
    return '$_temp0';
  }

  @override
  String settingsPaymentMethodCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count payment methods',
      one: '1 payment method',
      zero: 'No payment methods',
    );
    return '$_temp0';
  }

  @override
  String settingsTagCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tags',
      one: '1 tag',
      zero: 'No tags',
    );
    return '$_temp0';
  }

  @override
  String settingsUnitCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count units',
      one: '1 unit',
      zero: 'No units',
    );
    return '$_temp0';
  }

  @override
  String unitFactorHelp(String base) {
    return 'One of this unit has to be the same number of $base every time.';
  }

  @override
  String unitFactorQuestion(String base, String unit) {
    return 'How many $base is one $unit?';
  }

  @override
  String unitsEquals(String code, String amount, String base) {
    return '1 $code = $amount $base';
  }

  @override
  String unitsRowTitle(String name, String code) {
    return '$name ($code)';
  }

  @override
  String get attachmentsAdd => 'Add an attachment';

  @override
  String get attachmentsAddFailed => 'That could not be attached';

  @override
  String get attachmentsAdded => 'Attached';

  @override
  String get attachmentsChoosePhoto => 'Choose a photo';

  @override
  String get attachmentsDelete => 'Remove';

  @override
  String get attachmentsDeleteConfirmBody =>
      'The file is deleted from this phone. Backups you have already made still contain it.';

  @override
  String get attachmentsDeleteConfirmTitle => 'Remove this attachment?';

  @override
  String get attachmentsDeleteFailed => 'That could not be removed';

  @override
  String get attachmentsDeleted => 'Attachment removed';

  @override
  String get attachmentsMissing => 'That file is missing from this phone.';

  @override
  String get attachmentsNone => 'Nothing attached';

  @override
  String get attachmentsOpen => 'Open attachment';

  @override
  String get attachmentsStoredLocally =>
      'Kept on this phone only, and included in your backups.';

  @override
  String get backupConfirmAction => 'Make the backup';

  @override
  String get backupConfirmTitle => 'Make a backup?';

  @override
  String get backupDone => 'Backup saved';

  @override
  String get backupFailed => 'The backup could not be made';

  @override
  String get backupForget => 'Forget';

  @override
  String get backupForgetConfirmBody =>
      'This removes it from the list only. The backup file itself stays wherever you put it — Alaya cannot reach into your Drive or your chats.';

  @override
  String get backupForgetConfirmTitle => 'Forget this entry?';

  @override
  String get backupForgetFailed => 'That entry could not be removed';

  @override
  String get backupForgotten => 'Entry removed';

  @override
  String get backupHistoryEmptyBody =>
      'Make one now, and keep it somewhere that is not this phone.';

  @override
  String get backupHistoryEmptyTitle => 'No backups yet';

  @override
  String get backupHistoryHeader => 'Backups you have made';

  @override
  String get backupHistoryLoading => 'Loading your backups…';

  @override
  String get backupMakeHeader => 'Make a backup';

  @override
  String get backupRestoreBody =>
      'Merge a backup into what you have, or replace everything with it.';

  @override
  String get backupRestoreHeader => 'Restore';

  @override
  String get backupRestoreTitle => 'Restore from a backup';

  @override
  String get backupSaveBody =>
      'Choose where to put it. Alaya needs no storage permission — you pick the folder.';

  @override
  String get backupSaveTitle => 'Save a copy';

  @override
  String get backupShareBody => 'Send it to WhatsApp, Drive, or anywhere else.';

  @override
  String get backupShareTitle => 'Share a copy';

  @override
  String get backupTitle => 'Backup';

  @override
  String get reminderKindExpiry => 'Things going off';

  @override
  String get reminderKindExpiryHelp =>
      'Food and medicine reaching their use-by date.';

  @override
  String get reminderKindLowStock => 'Running low';

  @override
  String get reminderKindLowStockHelp =>
      'Not offered as a reminder: being low on something has no date, so it would arrive every morning until you shopped.';

  @override
  String get reminderKindRecurring => 'Bills and subscriptions';

  @override
  String get reminderKindRecurringHelp => 'When a recurring payment falls due.';

  @override
  String get reminderKindService => 'Appliance servicing';

  @override
  String get reminderKindServiceHelp =>
      'When something is due for its next service.';

  @override
  String get reminderKindWarranty => 'Warranties ending';

  @override
  String get reminderKindWarrantyHelp =>
      'Before a warranty runs out, while you can still use it.';

  @override
  String get remindersBlocked =>
      'Notifications are turned off for Alaya. Turn them on in your phone’s Settings › Apps › Alaya › Notifications.';

  @override
  String get remindersDenied => 'Alaya needs permission to send notifications.';

  @override
  String get remindersDigestExplainer =>
      'Alaya sends one message a day about what is coming up — not a notification for every item.';

  @override
  String get remindersDigestRow => 'Daily summary';

  @override
  String get remindersKindsHeader => 'What to remind me about';

  @override
  String get remindersLoading => 'Loading your reminders…';

  @override
  String get remindersNoneScheduledBody =>
      'Turn on a reminder above and Alaya will show what it has planned here.';

  @override
  String get remindersNoneScheduledTitle => 'Nothing scheduled';

  @override
  String get remindersScheduledHeader => 'Currently scheduled';

  @override
  String get remindersTimeHeader => 'When';

  @override
  String get remindersTimeSaved => 'Reminder time changed';

  @override
  String get remindersTimeTitle => 'Daily summary time';

  @override
  String get remindersTitle => 'Reminders';

  @override
  String get remindersToggleFailed => 'That could not be changed';

  @override
  String get restoreApplyMerge => 'Merge the backup';

  @override
  String get restoreApplyReplace => 'Replace everything';

  @override
  String get restoreChooseAnother => 'Choose another file';

  @override
  String get restoreChooseFile => 'Choose a file';

  @override
  String get restoreChosenHeader => 'Chosen file';

  @override
  String get restoreContinueReplace => 'Continue to replace';

  @override
  String get restoreDone => 'Restored';

  @override
  String get restoreLockNotRestored =>
      'Your PIN is never restored. It is kept outside the backup, so opening someone else’s backup can never change who can open this app.';

  @override
  String get restoreMergeBody =>
      'Adds what the backup has and updates what is newer. Nothing you have now is lost.';

  @override
  String get restoreMergeTitle => 'Merge';

  @override
  String get restoreModeHeader => 'How should it be applied?';

  @override
  String get restoreNotADatabase => 'That file is not an Alaya backup.';

  @override
  String get restorePickBody =>
      'Choose a backup file. Alaya will check it before anything changes.';

  @override
  String get restoreReplaceBody =>
      'Throws away what is on this phone and uses the backup instead.';

  @override
  String get restoreReplaceTitle => 'Replace everything';

  @override
  String get restoreReplaceWarning =>
      'Everything currently on this phone will be thrown away and replaced by the backup. Anything recorded since that backup was made will be gone.';

  @override
  String get restoreRollbackAvailable =>
      'Restored the wrong file? You can put your previous data back.';

  @override
  String get restoreRollbackPromise =>
      'Alaya takes a snapshot of your current data first, so you can undo this straight afterwards.';

  @override
  String get restoreTitle => 'Restore';

  @override
  String get restoreUndo => 'Undo the replace';

  @override
  String get supportConsentUnavailable =>
      'Adverts need a choice about personalisation that could not be loaded right now. Nothing has been requested.';

  @override
  String get supportIntro =>
      'Alaya is free, works offline, and has no accounts to sign up for. If it is useful to you, there are two ways to help.';

  @override
  String get supportLoading => 'Loading…';

  @override
  String get supportNoAd => 'No advert available right now';

  @override
  String get supportNoPaidFeatures =>
      'Nothing here unlocks anything. There are no paid features — the whole app is already yours.';

  @override
  String get supportThanks => 'Thank you. That genuinely helps.';

  @override
  String get supportTipBody =>
      'A one-time thank-you through the Play Store. It is not a subscription.';

  @override
  String get supportTipHeader => 'Leave a tip';

  @override
  String get supportTipUnavailable =>
      'Tips are not available on this device right now.';

  @override
  String get supportTitle => 'Support Alaya';

  @override
  String get supportWatchAction => 'Watch an advert';

  @override
  String get supportWatchBody =>
      'One advert, when you choose to. Alaya never shows one anywhere else in the app.';

  @override
  String get supportWatchHeader => 'Watch a short advert';

  @override
  String get trashDeletedOn => 'Deleted';

  @override
  String get trashEmptyBody =>
      'Things you delete are kept here for 30 days before they go for good.';

  @override
  String get trashEmptyNow => 'Empty now';

  @override
  String get trashEmptyNowConfirmBody =>
      'Everything in the trash is deleted permanently. This is not the trash — there is nowhere left for it to go.';

  @override
  String get trashEmptyNowConfirmTitle => 'Empty the trash?';

  @override
  String get trashEmptyTitle => 'The trash is empty';

  @override
  String get trashGoesOn => '· kept for 30 days';

  @override
  String get trashKindAsset => 'Appliances';

  @override
  String get trashKindItem => 'Items';

  @override
  String get trashKindPayee => 'Payees';

  @override
  String get trashKindRecurring => 'Recurring';

  @override
  String get trashKindShoppingList => 'Shopping lists';

  @override
  String get trashKindTag => 'Tags';

  @override
  String get trashKindTransaction => 'Transactions';

  @override
  String get trashLoading => 'Loading the trash…';

  @override
  String get trashNoMatchBody => 'Remove a filter to see the rest.';

  @override
  String get trashNoMatchTitle => 'Nothing matches that filter';

  @override
  String get trashPurgeConfirmBody =>
      'It will not go back to the trash. There is no undo.';

  @override
  String get trashPurgeConfirmTitle => 'Delete this for good?';

  @override
  String get trashPurgeFailed => 'That could not be deleted';

  @override
  String get trashPurgeOne => 'Delete for good';

  @override
  String get trashPurgedOne => 'Deleted for good';

  @override
  String get trashRestore => 'Restore';

  @override
  String get trashRestoreFailed => 'That could not be restored';

  @override
  String get trashRestored => 'Restored';

  @override
  String get trashTitle => 'Trash';

  @override
  String backupDoneNamed(String fileName) {
    return 'Backup saved as $fileName';
  }

  @override
  String backupHistorySize(String size) {
    return '· $size';
  }

  @override
  String remindersTimeBody(String time) {
    return 'Sent at $time each day';
  }

  @override
  String restoreDoneDetail(int tables) {
    String _temp0 = intl.Intl.pluralLogic(
      tables,
      locale: localeName,
      other: '$tables tables restored',
      one: '1 table restored',
    );
    return '$_temp0';
  }

  @override
  String restoreNewerSchema(int backup, int app) {
    return 'That backup is from a newer version of Alaya (version $backup) than this app understands (version $app). Update Alaya and try again.';
  }

  @override
  String restoreTypeToConfirm(String word) {
    return 'Type $word to confirm';
  }

  @override
  String supportTipAction(String price) {
    return 'Leave a tip · $price';
  }

  @override
  String trashPurged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items deleted for good',
      one: '1 item deleted for good',
      zero: 'Nothing to delete',
    );
    return '$_temp0';
  }

  @override
  String get dataBackupRowBody => 'Save a copy, share it, or restore from one.';

  @override
  String get dataTrashRowBody => 'Things you delete are kept here for 30 days.';

  @override
  String get settingsRemindersHelp => 'One daily summary of what is coming up.';

  @override
  String get settingsSupportHelp =>
      'Optional, and nothing here unlocks anything.';

  @override
  String settingsTrashCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
      zero: 'Nothing in the trash',
    );
    return '$_temp0';
  }

  @override
  String get supportWatchTooltip => 'Watch an advert to support Alaya';

  @override
  String ledgerRowSemantics(String title, String amount) {
    return '$title, $amount';
  }

  @override
  String ledgerRowSemanticsDetailed(
    String title,
    String amount,
    String detail,
  ) {
    return '$title, $amount, $detail';
  }

  @override
  String get navRecipes => 'Recipes';

  @override
  String moduleRecipes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count you can make',
      one: '1 you can make',
      zero: 'Nothing you can make',
    );
    return '$_temp0';
  }

  @override
  String get recipeSearchHint => 'Search recipes';

  @override
  String get recipeFilterCookable => 'Can cook now';

  @override
  String get recipeFilterFavourites => 'Favourites';

  @override
  String get recipeLoading => 'Loading your recipes…';

  @override
  String get recipeEmptyTitle => 'No recipes yet';

  @override
  String get recipeEmptyBody =>
      'Add one and Alaya will tell you when you have everything for it.';

  @override
  String get recipeNoMatchTitle => 'Nothing matches';

  @override
  String get recipeNoMatchBody => 'Clear the filters to see every recipe.';

  @override
  String recipeServes(int count) {
    return 'Serves $count';
  }

  @override
  String recipeServesAndTime(int count, int minutes) {
    return 'Serves $count · $minutes min';
  }

  @override
  String get recipeReady => 'Ready';

  @override
  String recipeShortBy(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count short',
      one: '1 short',
    );
    return '$_temp0';
  }

  @override
  String recipeMissingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count missing',
      one: '1 missing',
    );
    return '$_temp0';
  }

  @override
  String get recipeUncheckable => 'Can\'t tell';

  @override
  String get recipeNoIngredients => 'No ingredients';

  @override
  String get recipeDetailTitle => 'Recipe';

  @override
  String get recipeGoneTitle => 'That recipe is gone';

  @override
  String get recipeGoneBody =>
      'It may have been deleted. Check the trash if you want it back.';

  @override
  String get recipeServingsLabel => 'Servings';

  @override
  String get recipeServingsFewer => 'Fewer servings';

  @override
  String get recipeServingsMore => 'More servings';

  @override
  String get recipeIngredientsHeader => 'Ingredients';

  @override
  String get recipeMethodHeader => 'Method';

  @override
  String get recipeNotesHeader => 'Notes';

  @override
  String get recipeCheckingStock => 'Checking what you have…';

  @override
  String recipeStepMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get recipeCookAction => 'Cook this';

  @override
  String get recipeCooking => 'Cooking…';

  @override
  String get recipeCooked => 'Cooked';

  @override
  String recipeCookedDeducted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Cooked. $count ingredients deducted',
      one: 'Cooked. 1 ingredient deducted',
      zero: 'Cooked. Nothing was deducted',
    );
    return '$_temp0';
  }

  @override
  String get recipeCookFailed => 'That could not be cooked';

  @override
  String recipeCookWillSkip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ingredients will not be deducted — nothing tracks them',
      one: '1 ingredient will not be deducted — nothing tracks it',
    );
    return '$_temp0';
  }

  @override
  String get recipeShortfall => 'Not enough on hand';

  @override
  String get recipeNoneLeft => 'None left';

  @override
  String get recipeUnitMismatch =>
      'Measured differently from how you track it — can\'t compare';

  @override
  String get recipeNotTracked => 'Not tracked';

  @override
  String get recipeLinkedIngredient => 'Ingredient';

  @override
  String get recipeAddAction => 'New recipe';

  @override
  String get recipeNewTitle => 'New recipe';

  @override
  String get recipeEditTitle => 'Edit recipe';

  @override
  String get recipeNameLabel => 'Name';

  @override
  String get recipePrepLabel => 'Prep min';

  @override
  String get recipeCookLabel => 'Cook min';

  @override
  String get recipeAddIngredient => 'Add ingredient';

  @override
  String get recipeAddStep => 'Add step';

  @override
  String get recipeIngredientLabel => 'Ingredient';

  @override
  String get recipeQuantityLabel => 'Amount';

  @override
  String get recipeOptionalLabel => 'Optional — will not stop you cooking';

  @override
  String get recipeRemoveIngredient => 'Remove ingredient';

  @override
  String get recipeRemoveStep => 'Remove step';

  @override
  String recipeStepLabel(int number) {
    return 'Step $number';
  }

  @override
  String get recipeFavouriteToggle => 'Pin this recipe';

  @override
  String get recipeSaved => 'Recipe saved';

  @override
  String get recipeSaveFailed => 'That recipe could not be saved';

  @override
  String get recipeNotLinkedHelp =>
      'Not linked to inventory — pick from the list to track it';

  @override
  String get recipeQuantityHint => 'Leave blank for \"to taste\"';

  @override
  String get sectionRecipeMeasures => 'Recipe measures';

  @override
  String get labelDensity => 'Weight of 1 ml';

  @override
  String get densityHelp =>
      'Lets a recipe measure this in spoons or cups. Water is 1, oil about 0.92, honey about 1.4.';

  @override
  String get suffixGramsPerMl => 'g';

  @override
  String get labelPieceWeight => 'Weight of 1 piece';

  @override
  String get pieceWeightHelp =>
      'Lets a recipe say \"2 of these\" and still know how much to take.';

  @override
  String get suffixGrams => 'g';

  @override
  String get labelGramsPerTbsp => '1 tablespoon weighs';

  @override
  String get gramsPerTbspHelp =>
      'Flour about 8 g, sugar 12 g, oil 14 g, honey 21 g. Alaya works out teaspoons and cups from this.';

  @override
  String get recipeAmountHint => '2, 1/2, 1 1/2';

  @override
  String get recipeSpoonsNeedWeight =>
      'To measure this in spoons or cups, set \"1 tablespoon weighs\" on the item.';

  @override
  String get recipeAmountHintVessel => '1/2, 1, 1 1/2';

  @override
  String get recipeAmountHintPlain => '200';

  @override
  String recipeNeedsTbspWeight(String item) {
    return 'To measure $item in spoons or cups, set \"1 tablespoon weighs\" on the item.';
  }

  @override
  String recipeNeedsPieceWeight(String item) {
    return 'To count $item by the piece, set \"Weight of 1 piece\" on the item.';
  }

  @override
  String recipeAmountReadout(String written, String converted) {
    return '$written = $converted';
  }

  @override
  String get sectionMoreDetails => 'More details';

  @override
  String tagCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tags',
      one: '1 tag',
    );
    return '$_temp0';
  }

  @override
  String lineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get quickAddNoteHint => 'What for? (optional)';

  @override
  String get remindersNothingDueTitle => 'Nothing due this week';

  @override
  String get remindersNothingDueBody =>
      'Your reminders are on. Alaya looks a week ahead and there is nothing coming up yet — you will get a message the day something does.';

  @override
  String get remindersCheckNow => 'Check now';

  @override
  String get remindersChecking => 'Checking…';

  @override
  String remindersFoundCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count things coming up',
      one: '1 thing coming up',
    );
    return '$_temp0';
  }

  @override
  String get remindersFoundNothing => 'Nothing coming up in the next week';

  @override
  String get remindersSendTest => 'Send a test notification';

  @override
  String get remindersTestSent => 'Sent — check your notifications';

  @override
  String get shoppingEntryDeleted => 'Removed';

  @override
  String get fundsBreakdownTitle => 'Where this comes from';

  @override
  String get fundsNoAccountsTitle => 'No accounts yet';

  @override
  String get fundsNoAccountsBody =>
      'Add an account and its balance will show here.';

  @override
  String get fundsNotCounted => 'Not counted';

  @override
  String get fundsExcludedNote =>
      'Greyed accounts are excluded from your available funds.';

  @override
  String remindersZone(String zone) {
    return 'Using your phone’s time zone, $zone';
  }

  @override
  String get remindersZoneUnknown =>
      'Alaya could not work out your phone’s time zone, so the daily summary may arrive at the wrong hour. Check the date and time settings on your phone.';

  @override
  String get remindersOsHolding =>
      'Your phone has this set and will deliver it.';

  @override
  String get remindersOsMissing =>
      'Alaya has scheduled this, but your phone is not holding it. Allow Alaya to start in the background and turn off battery saver for it, then tap Check now.';

  @override
  String get recipeScaledRounding =>
      'Amounts are scaled for this serving count. Anything marked ≈ is rounded to the nearest measuring spoon or cup.';

  @override
  String get recipeUsesExpired => 'Some of this is past its date';

  @override
  String get recipeExpiredTitle => 'Use food that is past its date?';

  @override
  String recipeExpiredBody(String detail) {
    return '$detail\n\nAlaya will use up the good stock first and only take what it still needs from these. Check them before you cook.';
  }

  @override
  String recipeExpiredLine(String name, String amount, String date) {
    return '$name: $amount expired $date';
  }

  @override
  String recipeExpiredMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more ingredients',
      one: '1 more ingredient',
    );
    return 'and $_temp0';
  }

  @override
  String get recipeExpiredConfirm => 'Cook anyway';

  @override
  String get recipeCookBlockedExpired =>
      'Some of what this needs is past its date.';

  @override
  String get splitSectionHeader => 'Who owes for this';

  @override
  String get splitAdd => 'Split with someone';

  @override
  String get splitEdit => 'Edit split';

  @override
  String get splitRemove => 'Remove split';

  @override
  String get splitUnknownPerson => 'Someone';

  @override
  String get splitUnallocated => 'Not assigned';

  @override
  String get splitOverAllocated => 'Over by';

  @override
  String get splitSheetTitle => 'Split this expense';

  @override
  String get splitMethodEqual => 'Equally';

  @override
  String get splitMethodShares => 'By shares';

  @override
  String get splitMethodPercent => 'By percentage';

  @override
  String get splitMethodExact => 'Exact amounts';

  @override
  String get splitPickPeople => 'Who is sharing this?';

  @override
  String get splitPickPeopleEmpty =>
      'Add people in Settings first, then split a bill with them.';

  @override
  String get splitGroupLabel => 'Group';

  @override
  String get splitGroupNone => 'No group';

  @override
  String get splitPaidByYou => 'You';

  @override
  String splitPaidByOther(String name) {
    return '$name paid';
  }

  @override
  String get splitShareWeight => 'Shares';

  @override
  String get splitSharePercent => 'Percent';

  @override
  String get splitShareAmount => 'Amount';

  @override
  String splitPerPersonCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people',
      one: '1 person',
    );
    return '$_temp0';
  }

  @override
  String get splitNeedsAmount =>
      'Enter the amount first, then choose who is sharing it.';

  @override
  String get splitApply => 'Done';

  @override
  String get splitSelfPayeeUnset =>
      'Choose which person is you in Settings before splitting a bill.';

  @override
  String get navSplit => 'Split';

  @override
  String get splitGroupsTitle => 'Groups';

  @override
  String get splitOwedToYou => 'Owed to you';

  @override
  String get splitYouOwe => 'You owe';

  @override
  String get splitAllSettledTitle => 'All settled up';

  @override
  String get splitAllSettledBody => 'Nobody owes anybody anything right now.';

  @override
  String get splitNoSelfTitle => 'Who are you?';

  @override
  String splitOutstandingDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get splitGroupNew => 'New group';

  @override
  String get splitGroupEditTitle => 'Edit group';

  @override
  String get splitGroupNameLabel => 'Group name';

  @override
  String get splitNoGroupsTitle => 'No groups yet';

  @override
  String get splitNoGroupsBody =>
      'A group saves entering the same people every time you split a bill with them.';

  @override
  String get splitHasWeights => 'Custom shares';

  @override
  String get splitArchived => 'Archived';

  @override
  String get splitArchiveLabel => 'Archive this group';

  @override
  String get splitArchiveHelp =>
      'It keeps its history and its balances, and stops appearing when you split a bill.';

  @override
  String get splitDefaultShares => 'Default shares';

  @override
  String get splitDefaultSharesHelp =>
      'Set a percentage for everybody to prefill a split — like rent at 40/30/30. Leave them all blank to split equally.';

  @override
  String get splitWeightsPartial => 'Set a share for everybody, or none';

  @override
  String get splitDeleteGroupTitle => 'Delete this group?';

  @override
  String get splitDeleteGroupBody =>
      'A group with expenses cannot be deleted — archive it instead and its history stays.';

  @override
  String get splitBalancesHeader => 'Where you stand';

  @override
  String get splitActivityHeader => 'Activity';

  @override
  String get splitGroupEmptyTitle => 'Nothing here yet';

  @override
  String get splitGroupEmptyBody =>
      'Split a bill with this group and it will show up here.';

  @override
  String splitOwesYou(String name) {
    return '$name owes you';
  }

  @override
  String splitYouOwePerson(String name) {
    return 'You owe $name';
  }

  @override
  String splitExpenseBy(String name) {
    return '$name paid';
  }

  @override
  String splitSettlementBy(String name) {
    return '$name settled up';
  }

  @override
  String splitSettleFrom(String name) {
    return 'Settle up with $name';
  }

  @override
  String splitSettleTo(String name) {
    return 'Pay $name';
  }

  @override
  String get splitOutstandingLabel => 'Outstanding';

  @override
  String get splitSettleAmount => 'Amount';

  @override
  String get splitSettleOverpay =>
      'More than the balance — the difference will swing the other way.';

  @override
  String get splitSettleIntoAccount => 'Into which account?';

  @override
  String get splitSettleFromAccount => 'From which account?';

  @override
  String get splitSettleAction => 'Record payment';

  @override
  String get splitSimplifyTitle => 'Settle up';

  @override
  String splitSimplifySaves(int before, int after) {
    return '$before payments become $after';
  }

  @override
  String get splitSimplifyNoBetter =>
      'There is no shorter way — these are already the fewest payments.';

  @override
  String get splitSimplifyApproximate =>
      'A short way, not provably the shortest';

  @override
  String splitTransferLine(String from, String to) {
    return '$from pays $to';
  }

  @override
  String splitClearsDebt(String name) {
    return 'clears what is owed to $name';
  }

  @override
  String get splitShareTitle => 'Send this summary';

  @override
  String get splitShareCopied => 'Copied';

  @override
  String get splitShareAddUpi =>
      'Add your UPI id in Settings and each line gets a link they can tap to pay you.';

  @override
  String get actionCopy => 'Copy';

  @override
  String get actionShare => 'Share';

  @override
  String get splitShareHeading => 'Where we stand';

  @override
  String get splitShareOwesYou => 'Owes you';

  @override
  String get splitShareYouOwe => 'You owe';

  @override
  String get reminderKindSettlement => 'Debts to settle';

  @override
  String get reminderKindSettlementHelp =>
      'A reminder when a shared bill you agreed to settle by a date is coming up.';

  @override
  String get calendarSplitSettleBy => 'Settle by';

  @override
  String get eventTypeSplitSettleBy => 'Settle up';

  @override
  String get splitSettleByLabel => 'Settle by';

  @override
  String get splitSettleByHelp =>
      'Optional. Setting a date puts this on your calendar and in the daily summary.';

  @override
  String get splitSettleByHint => 'No date';

  @override
  String moduleSplit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people',
      one: '1 person',
      zero: 'all settled',
    );
    return '$_temp0';
  }

  @override
  String get splitCardTitle => 'Shared expenses';

  @override
  String get splitCardNotSpendable =>
      'Not part of your available funds until it arrives.';

  @override
  String splitCardOldest(int days) {
    return 'Oldest is $days days';
  }

  @override
  String get settingsSplit => 'Shared expenses';

  @override
  String get settingsSplitUnset => 'Not set up yet';

  @override
  String get settingsSplitSet => 'Ready';

  @override
  String get splitSettingsWhoAreYou => 'Which person is you?';

  @override
  String get splitSettingsWhoAreYouHelp =>
      'Every balance is what somebody owes you, or what you owe them. Alaya needs to know which of these people is you.';

  @override
  String get splitSettingsNoPeople =>
      'Add people under Payees first, then come back and pick yourself.';

  @override
  String splitSettingsClaimed(String name) {
    return 'You are $name';
  }

  @override
  String get splitSettingsUpi => 'Your UPI id';

  @override
  String get splitSettingsUpiLabel => 'UPI id';

  @override
  String get splitSettingsUpiHelp =>
      'Optional. Add it and every summary you share carries a link people can tap to pay you.';

  @override
  String get analyticsSectionSplit => 'Shared';

  @override
  String get analyticsSplitLensesTitle => 'What shared bills cost you';

  @override
  String get analyticsSplitLensesSubtitle =>
      'What left your account, and what you actually used';

  @override
  String get analyticsSplitOutflow => 'Left your account';

  @override
  String get analyticsSplitOutflowHelp => 'Full bills you paid';

  @override
  String get analyticsSplitMyShare => 'Your share';

  @override
  String get analyticsSplitMyShareHelp => 'What you actually used';

  @override
  String get analyticsSplitOutstanding => 'Still out';

  @override
  String get analyticsSplitOutstandingHelp =>
      'Paid out, not yours, not back yet';

  @override
  String get analyticsSplitEmpty => 'No shared expenses in this window.';

  @override
  String get analyticsSplitNoSelf =>
      'Choose which person is you in Settings to see your share.';

  @override
  String get analyticsSplitPartnersTitle => 'Who you split with';

  @override
  String get analyticsSplitPartnersSubtitle =>
      'By their share of the bills you paid';

  @override
  String analyticsSplitPartnerCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count expenses',
      one: '1 expense',
    );
    return '$_temp0';
  }

  @override
  String get analyticsSplitOccasionTitle => 'By occasion';

  @override
  String get analyticsSplitOccasionSubtitle => 'Diwali, a birthday, a trip';

  @override
  String get analyticsSplitOccasionEmpty =>
      'Add an occasion when you split a bill and it will appear here.';

  @override
  String get analyticsSplitPlaceTitle => 'By place';

  @override
  String get analyticsSplitPlaceSubtitle => 'Where the money went';

  @override
  String get analyticsSplitPlaceEmpty =>
      'Add a place when you split a bill and it will appear here.';

  @override
  String get splitBillAction => 'Split a bill';

  @override
  String get splitBillAmount => 'How much was it?';

  @override
  String get splitBillWhatFor => 'What was it for?';

  @override
  String get splitBillWhatForHint => 'Dinner at Olive';

  @override
  String get splitBillHow => 'How does it split?';

  @override
  String get splitBillYourMoney => 'Your money';

  @override
  String get splitBillRecordExpense => 'Record this as an expense';

  @override
  String get splitBillRecordExpenseHelp =>
      'The full bill left your account, so it belongs in your spending. Turn this off if somebody else paid, or if you have already recorded it.';

  @override
  String get splitBillSaved => 'Split saved';

  @override
  String get splitAddPerson => 'Add person';

  @override
  String get splitAddExtra => 'Extra';

  @override
  String get splitExtraLabel => 'Just for them';

  @override
  String get splitRemoveExtra => 'Remove extra';

  @override
  String splitShareBreakdown(String share, String extra) {
    return '$share share + $extra just for them';
  }

  @override
  String get splitTapToSettle => 'Tap anybody to record a payment';

  @override
  String get splitSettingsPayMe => 'How people can pay you';

  @override
  String get splitSettingsPayMeLabel => 'Payment details';

  @override
  String get splitSettingsPayMeHint =>
      'UPI id, PayPal link, bank details, or anything else';

  @override
  String get splitSettingsPayMeHelp =>
      'Optional, and free text — whatever works where you are. It is added to the end of any summary you share, so nobody has to ask.';

  @override
  String get splitSharePayMeAt => 'Pay me at:';

  @override
  String get splitShareAddHandle =>
      'Add your payment details so nobody has to ask.';

  @override
  String get splitHowManyPeople => 'How many people?';

  @override
  String get splitHowManyPeopleHelp =>
      'Names are optional — add them later if you want to keep this';

  @override
  String splitPersonN(int n) {
    return 'Person $n';
  }

  @override
  String get splitBillResultHint => 'Send this to the table — no names needed.';

  @override
  String get splitCopyResult => 'Copy the result';

  @override
  String get splitResultCopied => 'Copied';

  @override
  String get splitBillKeepIt => 'Keep it';

  @override
  String get splitBillKeepItHelp =>
      'Everything below is optional. Save it only if you want the debt tracked until it is paid.';

  @override
  String get splitSaveToBalances => 'Save to balances';

  @override
  String splitNameEveryoneToSave(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Name $count more people to save this',
      one: 'Name 1 more person to save this',
    );
    return '$_temp0';
  }

  @override
  String get splitPickName => 'Who is this?';

  @override
  String get splitNewPerson => 'New person';

  @override
  String get splitAlreadyOnSplit => 'Already on this split';

  @override
  String splitPercentOfBill(int percent) {
    return '$percent%';
  }

  @override
  String splitTipPercent(int percent) {
    return '$percent% tip';
  }

  @override
  String get splitRoundUp => 'Round up';

  @override
  String get splitTipAdded => 'Adding';

  @override
  String splitTipTotal(String tip, String total) {
    return 'Adding $tip · total $total';
  }

  @override
  String get splitBillTheSplit => 'The split';

  @override
  String get splitSaveAsGroup => 'Save these people as a group';

  @override
  String get splitSaveAsGroupHelp =>
      'So next time you split with them it is one tap.';

  @override
  String get splitSaveAsGroupHint => 'Flatmates';

  @override
  String get splitSaveAsGroupWeights =>
      'Their shares are saved too, so next time starts the same way.';

  @override
  String splitSaveAsGroupAction(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Save these $count as a group',
      one: 'Save as a group',
    );
    return '$_temp0';
  }

  @override
  String get splitGroupNameRequired => 'Give the group a name';

  @override
  String splitMemberWithWeight(String name, int percent) {
    return '$name · $percent%';
  }

  @override
  String get splitGroupSaved => 'Group saved';

  @override
  String get splitQuickAmount => 'What was the bill?';

  @override
  String get splitQuickPeople => 'How many of you?';

  @override
  String get splitQuickIPaid => 'I paid it all';

  @override
  String get splitQuickEachTheirOwn => 'Each their own';

  @override
  String get splitQuickEach => 'Each pays';

  @override
  String get splitQuickOwed => 'Owed to you';

  @override
  String get splitQuickHint =>
      'Type an amount and it splits as you go. Names are optional.';

  @override
  String get splitQuickAddNames => 'Add names';

  @override
  String splitQuickEachPays(String amount) {
    return 'Each pays $amount';
  }

  @override
  String splitQuickOwedToMe(String amount) {
    return 'Owed to me: $amount';
  }

  @override
  String splitQuickYouAbsorb(String amount) {
    return 'You cover the odd $amount.';
  }

  @override
  String splitQuickLeftOver(String amount) {
    return '$amount left over — add names to place it.';
  }

  @override
  String splitUnnamedWillBeSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count people are unnamed — they will be saved as \"Person N\" and you can rename them any time',
      one:
          '1 person is unnamed — they will be saved as \"Person N\" and you can rename them any time',
    );
    return '$_temp0';
  }

  @override
  String get splitNameThisPerson => 'Who is this?';

  @override
  String get splitAddPersonTitle => 'Add someone';

  @override
  String get splitAddPersonNameRequired => 'They need a name';

  @override
  String get splitAddPersonPhoneHelp =>
      'Optional — shown only when two people share a name, so you can tell them apart.';

  @override
  String get splitSetupTitle => 'First, who are you?';

  @override
  String get splitSetupBody =>
      'Alaya needs one name for you, so it can tell who owes whom. You can change it later in Settings.';

  @override
  String get splitSetupNameLabel => 'Your name';

  @override
  String get splitSetupNameRequired => 'Enter a name to continue';

  @override
  String get splitSetupAction => 'That\'s me';

  @override
  String get splitCreateSplit => 'Create a split';

  @override
  String get payeeKindSplitPlaceholder => 'Unnamed on a split';

  @override
  String get onboardingNameTitle => 'What should we call you?';

  @override
  String get onboardingNameBody =>
      'Alaya uses this to know which share is yours when you split a bill, and to sign anything you share with friends.';

  @override
  String get onboardingNameLabel => 'Your name';

  @override
  String get onboardingNameRequired => 'Enter a name, or skip for now';

  @override
  String get splitHistoryEmptyTitle => 'Nothing split yet';

  @override
  String get splitHistoryEmptyBody =>
      'Every bill you divide and every payment you record shows up here, newest first.';

  @override
  String splitHistoryPaidBy(String name) {
    return '$name paid';
  }

  @override
  String splitHistorySettledBy(String name) {
    return '$name settled up';
  }

  @override
  String get splitTabBalances => 'Balances';

  @override
  String get splitTabHistory => 'History';

  @override
  String get splitTabGroups => 'Groups';

  @override
  String get splitTransferNotYours =>
      'Between two other people — nothing for you to record.';

  @override
  String get onboardingNameOptional =>
      'Optional — leave it blank and continue if you would rather not.';

  @override
  String get splitTipTitle => 'Tip or service charge';

  @override
  String get splitTipNone => 'None';

  @override
  String splitTipPercentChip(int percent) {
    return '$percent% tip';
  }

  @override
  String get splitTipCustom => 'Custom %';

  @override
  String splitTipAdds(int percent) {
    return '$percent% of the bill';
  }

  @override
  String get splitMethodTitle => 'How it splits';

  @override
  String get splitMethodEqualHelp =>
      'The same amount each. Anything one person owes on top goes in their row.';

  @override
  String get splitMethodSharesHelp =>
      'Weights, not amounts — 2:1:1 means one person covers half.';

  @override
  String get splitMethodPercentHelp =>
      'A percentage each. They needn\'t add to 100; anything left over is shown.';

  @override
  String get splitMethodExactHelp =>
      'Type what each person owes. Any gap against the total is shown, never absorbed.';

  @override
  String get splitMethodPerLineHelp =>
      'Each item on the receipt divided among whoever ordered it.';

  @override
  String get splitMethodPerLine => 'Item by item';

  @override
  String get splitTipTotalLabel => 'total';

  @override
  String splitNamePlaceholderBody(String placeholder) {
    return '$placeholder is a stand-in Alaya created so the split could be saved. Who was it?';
  }

  @override
  String get splitNameSomebodyKnown => 'Somebody you already have';

  @override
  String get splitNameOr => 'or';

  @override
  String get splitNameSomebodyNew => 'Somebody new — their name';

  @override
  String get splitNameRequired => 'Enter a name, or pick somebody above';

  @override
  String get splitWhoPaid => 'Who paid?';

  @override
  String get splitPaidBySomebodyElseHelp =>
      'No money left your account, so nothing goes in your ledger until you settle up.';

  @override
  String get splitRecordTheyPaid => 'They paid me back';

  @override
  String get splitRecordYouPaid => 'I paid them back';

  @override
  String get splitDetailTotal => 'Total';

  @override
  String get splitDetailPaidBy => 'Paid by';

  @override
  String get splitDetailMethod => 'Split';

  @override
  String get splitDetailPlace => 'Place';

  @override
  String get splitDetailOccasion => 'Occasion';

  @override
  String splitSharePercentOf(double percent) {
    final intl.NumberFormat percentNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String percentString = percentNumberFormat.format(percent);

    return '$percentString% of the bill';
  }

  @override
  String splitShareWeightOf(int weight) {
    return '$weight share(s)';
  }

  @override
  String get splitShareIsExtra => 'Just for them';

  @override
  String get splitDeleteConfirmTitle => 'Delete this split?';

  @override
  String get splitDeleteConfirmBody =>
      'The balances it created go with it. Any expense already recorded in your ledger stays — the money did move.';

  @override
  String get splitDeleted => 'Split deleted';

  @override
  String get splitEditTitle => 'Edit split';

  @override
  String splitQuickSaveHelp(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Records that $count people owe you.',
      one: 'Records that 1 person owes you.',
    );
    return '$_temp0 Your account balance isn\'t touched — use More options to record the expense too.';
  }

  @override
  String get splitQuickMoreOptions => 'More options';

  @override
  String get supportActionLabel => 'Support Us';

  @override
  String splitNoteWays(int count) {
    return 'Split $count ways';
  }

  @override
  String splitNoteWaysWith(int count, String names) {
    return 'Split $count ways with $names';
  }

  @override
  String splitNoteTitled(String title, int count) {
    return '$title — split $count ways';
  }

  @override
  String splitNoteTitledWith(String title, int count, String names) {
    return '$title — split $count ways with $names';
  }

  @override
  String splitSettleNoteFrom(String name) {
    return '$name paid you back';
  }

  @override
  String splitSettleNoteTo(String name) {
    return 'You paid $name back';
  }

  @override
  String splitSettleNoteFromIn(String name, String group) {
    return '$name paid you back — $group';
  }

  @override
  String splitSettleNoteToIn(String name, String group) {
    return 'You paid $name back — $group';
  }

  @override
  String get lineItemRequired => 'Choose an item, or add a new one';

  @override
  String get lineQuantityRequired =>
      'Enter how much you bought, and in what unit';
}
```

### `lib/app/providers/currency_providers.dart`

```dart
/// The home currency, and the precision every amount is rendered at.
///
/// **App-level, not expense-level.** Both providers below lived in
/// `features/expense/providers/transaction_list_providers.dart`, which meant the split module, the
/// analytics cards and anything else needing a decimal precision had to import a *transaction list* to
/// get one. The split module very nearly declared its own instead — which would have been two sources
/// for one fact, and the reason JPY renders with 0 digits in some places and 2 in others.
///
/// Nothing about a home currency is about a list of transactions. It belongs beside `clockProvider`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';

/// The code the app reports in, defaulting to INR before onboarding has run.
final homeCurrencyCodeProvider = FutureProvider<String>(
  (ref) async =>
      await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ??
      'INR',
);

/// The home currency's decimal digits, so no amount hardcodes 2 (ARCH_1 §4.1).
///
/// JPY is 0 and the rest are 2, which is exactly why the figure is read from the `currencies` row
/// rather than assumed at each call site.
final homeDecimalDigitsProvider = FutureProvider<int>((ref) async {
  final code = await ref.watch(homeCurrencyCodeProvider.future);
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});
```

### `lib/app/providers/infrastructure_providers.dart`

```dart
/// The bottom of the dependency graph: the database, the DAOs, and the ambient singletons.
///
/// **Hand-written, because `@riverpod` needs `riverpod_generator` and `drift_dev` is the only
/// codegen package this project may have (ARCH_1 §7.3).** A second one makes the whole project
/// unresolvable, so the annotation is not available at any price.
///
/// Providers rather than a service locator so that a widget test can override exactly one
/// dependency — `databaseProvider` with an in-memory database, `clockProvider` with a `FixedClock` —
/// without constructing the other forty.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/text/normalizer.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/account_dao.dart';
import 'package:alaya/data/daos/analytics_cache_dao.dart';
import 'package:alaya/data/daos/calendar_dao.dart';
import 'package:alaya/data/daos/asset_dao.dart';
import 'package:alaya/data/daos/backup_history_dao.dart';
import 'package:alaya/data/daos/batch_dao.dart';
import 'package:alaya/data/daos/currency_dao.dart';
import 'package:alaya/data/daos/item_dao.dart';
import 'package:alaya/data/daos/notification_schedule_dao.dart';
import 'package:alaya/data/daos/payee_dao.dart';
import 'package:alaya/data/daos/payment_method_dao.dart';
import 'package:alaya/data/daos/recipe_dao.dart';
import 'package:alaya/data/daos/recurring_occurrence_dao.dart';
import 'package:alaya/data/daos/recurring_template_dao.dart';
import 'package:alaya/data/daos/service_record_dao.dart';
import 'package:alaya/data/daos/settings_dao.dart';
import 'package:alaya/data/daos/shopping_entry_dao.dart';
import 'package:alaya/data/daos/shopping_list_dao.dart';
import 'package:alaya/data/daos/stock_movement_dao.dart';
import 'package:alaya/data/daos/tag_dao.dart';
import 'package:alaya/data/daos/transaction_dao.dart';
import 'package:alaya/data/daos/transaction_line_dao.dart';
import 'package:alaya/data/daos/unit_dao.dart';
import 'package:alaya/data/daos/split_dao.dart';
import 'package:alaya/data/daos/split_view_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/security/secure_key_value_store.dart';

/// The open database.
///
/// **Overridden in `bootstrap` with the real connection** and in tests with
/// `AlayaDatabase(NativeDatabase.memory())`. It throws if read un-overridden, which is deliberate:
/// a provider that silently opened a second connection would violate L10's single-open-path rule and
/// the symptom would be a locked database rather than an error naming the cause.
final databaseProvider = Provider<AlayaDatabase>((ref) {
  throw StateError(
    'databaseProvider was not overridden. bootstrap() must supply the connection — see '
    'data/db/connection/open_database.dart, the only permitted open path (ARCH_1 L10).',
  );
});

/// The wall clock.
///
/// Every timestamp and every "today" in the app comes from here, which is what makes a date-sensitive
/// test reproducible instead of dependent on when it ran.
final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// The UUID v7 generator.
final uidGeneratorProvider = Provider<UidGenerator>(
  (ref) => const Uuid7Generator(),
);

/// The logger.
final loggerProvider = Provider<Logger>((ref) => const DeveloperLogger());

/// The text normaliser used for duplicate detection and search.
final normalizerProvider = Provider<Normalizer>((ref) => const Normalizer());

/// The HTTP client, configured for one job: a fire-and-forget rate fetch.
///
/// The timeouts are literal `Duration`s and not `AlayaDurations` values, deliberately. That scale is a
/// UI animation scale measured in tens of milliseconds; a network timeout is seconds, and borrowing an
/// animation token for one would be a category error rather than reuse.
///
/// They are short because `syncDailyRates` must never block a write (Law L11). A rate that arrives
/// late is worth nothing — the cached rate is already in use — so the call gives up quickly rather
/// than holding a connection open on a bad network.
final dioProvider = Provider<Dio>(
  (ref) => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
    ),
  ),
);

/// Secure key-value storage, for the app lock only.
///
/// Never the database (ARCH_3 §2.1) — that separation is what stops a restore from replacing the
/// user's PIN with the one from the backup.
final secureKeyValueStoreProvider = Provider<SecureKeyValueStore>(
  (ref) => const FlutterSecureKeyValueStore(),
);

// ── DAOs ────────────────────────────────────────────────────────────────────────────────
//
// One per aggregate, each a thin `DatabaseAccessor` over the single connection. They are separate
// providers rather than getters on the database because `@DriftDatabase` here declares no `daos:`
// list, so there are no generated accessors to reach for.

/// The accounts DAO.
final accountDaoProvider = Provider<AccountDao>(
  (ref) => AccountDao(ref.watch(databaseProvider)),
);

/// The transactions DAO.
final transactionDaoProvider = Provider<TransactionDao>(
  (ref) => TransactionDao(ref.watch(databaseProvider)),
);

/// The transaction-lines DAO.
final transactionLineDaoProvider = Provider<TransactionLineDao>(
  (ref) => TransactionLineDao(ref.watch(databaseProvider)),
);

/// The payment-methods DAO.
final paymentMethodDaoProvider = Provider<PaymentMethodDao>(
  (ref) => PaymentMethodDao(ref.watch(databaseProvider)),
);

/// The payees DAO.
final payeeDaoProvider = Provider<PayeeDao>(
  (ref) => PayeeDao(ref.watch(databaseProvider)),
);

/// The tags DAO.
final tagDaoProvider = Provider<TagDao>(
  (ref) => TagDao(ref.watch(databaseProvider)),
);

/// The currencies and rates DAO.
final currencyDaoProvider = Provider<CurrencyDao>(
  (ref) => CurrencyDao(ref.watch(databaseProvider)),
);

/// The units DAO.
final unitDaoProvider = Provider<UnitDao>(
  (ref) => UnitDao(ref.watch(databaseProvider)),
);

/// The settings DAO.
final settingsDaoProvider = Provider<SettingsDao>(
  (ref) => SettingsDao(ref.watch(databaseProvider)),
);

/// The items DAO.
final itemDaoProvider = Provider<ItemDao>(
  (ref) => ItemDao(ref.watch(databaseProvider)),
);

/// Recipes, their ingredients, steps and cook log.
final recipeDaoProvider = Provider<RecipeDao>(
  (ref) => RecipeDao(ref.watch(databaseProvider)),
);

/// The inventory-batches DAO.
final batchDaoProvider = Provider<BatchDao>(
  (ref) => BatchDao(ref.watch(databaseProvider)),
);

/// The stock-movements DAO.
final stockMovementDaoProvider = Provider<StockMovementDao>(
  (ref) => StockMovementDao(ref.watch(databaseProvider)),
);

/// The shopping-lists DAO.
final shoppingListDaoProvider = Provider<ShoppingListDao>(
  (ref) => ShoppingListDao(ref.watch(databaseProvider)),
);

/// The shopping-entries DAO.
final shoppingEntryDaoProvider = Provider<ShoppingEntryDao>(
  (ref) => ShoppingEntryDao(ref.watch(databaseProvider)),
);

/// The recurring-templates DAO.
final recurringTemplateDaoProvider = Provider<RecurringTemplateDao>(
  (ref) => RecurringTemplateDao(ref.watch(databaseProvider)),
);

/// The recurring-occurrences DAO.
final recurringOccurrenceDaoProvider = Provider<RecurringOccurrenceDao>(
  (ref) => RecurringOccurrenceDao(ref.watch(databaseProvider)),
);

/// The assets DAO.
final assetDaoProvider = Provider<AssetDao>(
  (ref) => AssetDao(ref.watch(databaseProvider)),
);

/// The service-records DAO.
final serviceRecordDaoProvider = Provider<ServiceRecordDao>(
  (ref) => ServiceRecordDao(ref.watch(databaseProvider)),
);

/// The notification-schedule DAO.
final notificationScheduleDaoProvider = Provider<NotificationScheduleDao>(
  (ref) => NotificationScheduleDao(ref.watch(databaseProvider)),
);

/// The backup-history DAO.
final backupHistoryDaoProvider = Provider<BackupHistoryDao>(
  (ref) => BackupHistoryDao(ref.watch(databaseProvider)),
);

/// The analytics-cache DAO.
final analyticsCacheDaoProvider = Provider<AnalyticsCacheDao>(
  (ref) => AnalyticsCacheDao(ref.watch(databaseProvider)),
);

/// The calendar DAO, over `v_calendar_events`.
final calendarDaoProvider = Provider<CalendarDao>(
  (ref) => CalendarDao(ref.watch(databaseProvider)),
);

/// Split groups, members, expenses, shares and settlements.
final splitDaoProvider = Provider<SplitDao>(
  (ref) => SplitDao(ref.watch(databaseProvider)),
);

/// The split module's derived reads: balances, expense summaries and the activity feed.
///
/// A second DAO rather than more methods on [splitDaoProvider], because Law L7 says repositories read
/// views and one class exposing both the tables and the views makes reaching for the wrong one a
/// matter of autocomplete. `CalendarDao` stands apart from the seven tables its view unions for the
/// same reason.
final splitViewDaoProvider = Provider<SplitViewDao>(
  (ref) => SplitViewDao(ref.watch(databaseProvider)),
);
```

### `lib/app/providers/profile_providers.dart`

```dart
/// Who the user is, app-wide.
///
/// **This is not a split concept, and it was living inside one.** Every balance in the split module is
/// "what they owe *you*" or "what *you* owe them", so the module needed to know which payee the user is —
/// and the setting ended up named `split.selfPayeeId`, read through `SplitGroupRepository`, and asked for
/// on a split screen. All three placed a fact about the person using the app inside one feature of it.
///
/// The same fact answers questions nothing to do with splitting: what to call somebody on a dashboard,
/// whose name signs a shared summary, which participant to preselect anywhere a person is one of several.
/// So it belongs here, beside `clockProvider` and the home currency.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/domain/entities/payee.dart';

/// The `app_settings` key holding which payee the user is.
///
/// **Still prefixed `split.`, deliberately.** The name is wrong — this is a profile fact, not a split one
/// — and renaming it would orphan every install that already has a value, for no benefit a user can see.
/// `split.upiId` was renamed because its *meaning* was wrong; this one's meaning is right and only its
/// label is dated. Change it when something else forces a settings migration, not before.
const String selfPayeeIdKey = 'split.selfPayeeId';

/// The payee the user has claimed as themselves, or null when nobody has been claimed.
///
/// **Null means "not asked yet", never "nobody".** On a fresh install there is no payee to point at, so
/// anything reading this has to treat null as a setup step rather than as an absence of data — the
/// distinction the split screen's two empty states exist for.
final selfPayeeIdProvider = FutureProvider<String?>(
  (ref) => ref.watch(settingsRepositoryProvider).readValue(selfPayeeIdKey),
);

/// The user, as a payee row — or null before onboarding, or if the row was deleted.
///
/// **The second null is real and worth handling.** Nothing stops somebody deleting themselves from
/// Settings › Payees; the setting would then name a row that no longer exists, and every screen reading
/// this gets null rather than a crash.
final selfPayeeProvider = FutureProvider<Payee?>((ref) async {
  final id = await ref.watch(selfPayeeIdProvider.future);
  if (id == null) return null;
  return ref.watch(payeeRepositoryProvider).byId(id);
});

/// What to call the user, or null when they have not said.
///
/// **One source, no copy.** The obvious alternative — an `app_settings` row holding the name as text —
/// would drift the first time somebody renamed themselves under Payees, and nothing would say which of
/// the two was right. The name is the payee's `name`, read through the id.
final userDisplayNameProvider = FutureProvider<String?>(
  (ref) async => (await ref.watch(selfPayeeProvider.future))?.name,
);

/// Claims a payee as the user, creating them when the name is new.
final claimSelfProvider = NotifierProvider<ClaimSelf, AsyncValue<void>>(
  ClaimSelf.new,
);

/// Writes the user's identity: a payee, and the setting that points at it.
class ClaimSelf extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Claims whoever is called [name], creating them if nobody is.
  ///
  /// **An existing person with that name is reused rather than duplicated.** Somebody who added
  /// themselves under Payees before reaching this, or who reinstalls over a restored backup, should be
  /// claimed and not cloned — two "Ravi" rows where one is the user is the worst possible state for a
  /// module built on who owes whom.
  ///
  /// **Both writes, or the caller is told.** Creating the payee without pointing the setting at it leaves
  /// the app exactly as unconfigured as before, which is the half-finished state the old redirect to
  /// Settings used to produce.
  Future<bool> claim(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;

    state = const AsyncLoading<void>();
    final normalizer = ref.read(normalizerProvider);
    final normalized = normalizer.normalize(trimmed);
    final payees = ref.read(payeeRepositoryProvider);

    var id = <String?>[
      for (final payee in await payees.watchAll().first)
        if (payee.normalizedName == normalized &&
            payee.kind == PayeeKind.person)
          payee.id,
    ].firstOrNull;

    if (id == null) {
      final saved = await payees.save(
        Payee(
          id: ref.read(uidGeneratorProvider).generate(),
          name: trimmed,
          normalizedName: normalized,
          // `person`, never `merchant` — the default that made the split module unusable, because
          // `splitPeopleProvider` filters to persons and every list came back empty.
          kind: PayeeKind.person,
        ),
      );
      final payee = saved.valueOrNull;
      if (payee == null) {
        state = AsyncError<void>(
          saved.failureOrNull ??
              const UnexpectedFailure('That name could not be saved.'),
          StackTrace.current,
        );
        return false;
      }
      id = payee.id;
    }

    final written = await ref
        .read(settingsRepositoryProvider)
        .writeValue(key: selfPayeeIdKey, value: id, valueType: 'string');
    if (written.isFailure) {
      state = AsyncError<void>(
        written.failureOrNull ??
            const UnexpectedFailure('That name could not be saved.'),
        StackTrace.current,
      );
      return false;
    }

    // Everything downstream reads through `selfPayeeIdProvider`, so invalidating it is what makes the
    // rest of the app notice. Without this the value is correct in the database and stale in memory until
    // the next launch — which is how a setup step appears to have done nothing.
    ref.invalidate(selfPayeeIdProvider);
    state = const AsyncData(null);
    return true;
  }

  /// The message from the last failure, or null.
  ///
  /// Typed, not cast: an `as dynamic` to reach `message` would compile against anything and fail at
  /// runtime the first time a non-`Failure` landed in the error slot.
  String? get lastError {
    final error = state.error;
    return error is Failure ? error.message : null;
  }
}
```

### `lib/app/providers/repository_providers.dart`

```dart
/// One provider per repository contract, typed as the **contract** and never the implementation.
///
/// Typing them as the interface is what makes the layering rule enforceable: a feature that declares
/// `ref.watch(accountRepositoryProvider)` receives an `AccountRepository` and cannot reach into
/// `AccountRepositoryImpl` for a method the contract does not expose.
///
/// **All seventeen of Phase 3A's contracts now have an implementation.** `CalendarRepository` was the
/// last but one, wired in Phase 7A; `AnalyticsCacheRepository` was the last, wired here. The note
/// that used to stand in this paragraph — two contracts unimplemented, three engines unreachable — is
/// closed (ARCH_4 §5.1 item 15).
///
/// `analyticsPortProvider` sits with the repositories rather than with the engines despite not being
/// a repository, because it has a repository's shape exactly: a contract declared in `domain/`, one
/// implementation in `data/`, and a provider typed as the contract so no feature can reach past it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/data/repositories/analytics_cache_repository_impl.dart';
import 'package:alaya/data/repositories/analytics_port_impl.dart';
import 'package:alaya/data/repositories/calendar_repository_impl.dart';
import 'package:alaya/data/repositories/account_repository_impl.dart';
import 'package:alaya/data/repositories/asset_repository_impl.dart';
import 'package:alaya/data/repositories/batch_repository_impl.dart';
import 'package:alaya/data/repositories/currency_repository_impl.dart';
import 'package:alaya/data/repositories/item_category_resolver.dart';
import 'package:alaya/data/repositories/item_repository_impl.dart';
import 'package:alaya/data/repositories/payee_repository_impl.dart';
import 'package:alaya/data/repositories/payment_method_repository_impl.dart';
import 'package:alaya/data/repositories/recurring_repository_impl.dart';
import 'package:alaya/data/repositories/service_record_repository_impl.dart';
import 'package:alaya/data/repositories/settings_repository_impl.dart';
import 'package:alaya/data/repositories/shopping_repository_impl.dart';
import 'package:alaya/data/repositories/stock_repository_impl.dart';
import 'package:alaya/data/repositories/tag_repository_impl.dart';
import 'package:alaya/data/repositories/transaction_repository_impl.dart';
import 'package:alaya/data/repositories/unconverted_count.dart';
import 'package:alaya/data/repositories/unit_repository_impl.dart';
import 'package:alaya/domain/repositories/analytics_cache_repository.dart';
import 'package:alaya/domain/repositories/calendar_repository.dart';
import 'package:alaya/domain/repositories/account_repository.dart';
import 'package:alaya/domain/repositories/asset_repository.dart';
import 'package:alaya/domain/repositories/batch_repository.dart';
import 'package:alaya/domain/repositories/currency_repository.dart';
import 'package:alaya/domain/repositories/item_repository.dart';
import 'package:alaya/domain/repositories/payee_repository.dart';
import 'package:alaya/domain/repositories/payment_method_repository.dart';
import 'package:alaya/domain/repositories/recurring_repository.dart';
import 'package:alaya/domain/repositories/service_record_repository.dart';
import 'package:alaya/data/repositories/recipe_repository_impl.dart';
import 'package:alaya/domain/repositories/recipe_repository.dart';
import 'package:alaya/domain/services/recipe_cook_service.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/repositories/shopping_repository.dart';
import 'package:alaya/domain/repositories/stock_repository.dart';
import 'package:alaya/domain/repositories/tag_repository.dart';
import 'package:alaya/domain/repositories/transaction_repository.dart';
import 'package:alaya/domain/repositories/unit_repository.dart';
import 'package:alaya/domain/services/analytics/analytics_port.dart';
import 'package:alaya/data/repositories/split_group_repository_impl.dart';
import 'package:alaya/data/repositories/split_ledger_repository_impl.dart';
import 'package:alaya/domain/repositories/split_group_repository.dart';
import 'package:alaya/domain/repositories/split_ledger_repository.dart';

/// Resolves an item's unit category, with a per-instance cache.
///
/// A single provider rather than one per consumer, because three repositories need it and its whole
/// value is the cache: constructing it twice halves the hit rate for no reason.
final itemCategoryResolverProvider = Provider<ItemCategoryResolver>(
  (ref) => ItemCategoryResolver(ref.watch(itemDaoProvider)),
);

/// Key-value app settings.
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepositoryImpl(
    ref.watch(settingsDaoProvider),
    ref.watch(clockProvider),
  ),
);

/// Currencies, rates and conversion.
///
/// Takes `CurrencyRateService` so `syncDailyRates` has one implementation. Phase 3B's
/// `DailyRateFetch` typedef is gone — the repository delegates rather than reimplementing the
/// once-daily check, which the earlier version omitted entirely.
final currencyRepositoryProvider = Provider<CurrencyRepository>(
  (ref) => CurrencyRepositoryImpl(
    ref.watch(currencyDaoProvider),
    ref.watch(clockProvider),
    ref.watch(settingsRepositoryProvider),
    rateService: ref.watch(currencyRateServiceProvider),
    // Phase 7B: `watchUnconvertedCount` was a `Stream.value(0)` stub until this arrived, so the
    // `+N unconverted` chip could never report anything (ARCH_3 §1.5, ARCH_5 §7.3).
    unconvertedCounter: ref.watch(unconvertedCounterProvider),
  ),
);

/// Counts the transactions no cached rate can convert, for the `+N unconverted` chip.
///
/// Not a repository, and not in `service_providers.dart` either: it is the collaborator
/// `CurrencyRepositoryImpl` delegates one method to, so it belongs beside the repository that owns
/// it. It takes `CurrencyRateService` for the same reason that service takes closures over the DAO —
/// depending on `currencyRepositoryProvider` from here would be a cycle.
final unconvertedCounterProvider = Provider<UnconvertedCounter>(
  (ref) => UnconvertedCounter(
    database: ref.watch(databaseProvider),
    rates: ref.watch(currencyRateServiceProvider),
    settings: ref.watch(settingsRepositoryProvider),
  ),
);

/// Units and conversion factors.
final unitRepositoryProvider = Provider<UnitRepository>(
  (ref) =>
      UnitRepositoryImpl(ref.watch(unitDaoProvider), ref.watch(clockProvider)),
);

/// Accounts and balances.
final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepositoryImpl(
    ref.watch(accountDaoProvider),
    ref.watch(transactionDaoProvider),
    ref.watch(currencyRepositoryProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// Payment methods.
final paymentMethodRepositoryProvider = Provider<PaymentMethodRepository>(
  (ref) => PaymentMethodRepositoryImpl(
    ref.watch(paymentMethodDaoProvider),
    ref.watch(clockProvider),
  ),
);

/// Payees.
final payeeRepositoryProvider = Provider<PayeeRepository>(
  (ref) => PayeeRepositoryImpl(
    ref.watch(payeeDaoProvider),
    ref.watch(clockProvider),
  ),
);

/// Tags.
final tagRepositoryProvider = Provider<TagRepository>(
  (ref) =>
      TagRepositoryImpl(ref.watch(tagDaoProvider), ref.watch(clockProvider)),
);

/// Transactions, with their lines and stock side effects.
final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepositoryImpl(
    ref.watch(transactionDaoProvider),
    ref.watch(transactionLineDaoProvider),
    ref.watch(accountDaoProvider),
    ref.watch(unitDaoProvider),
    ref.watch(batchDaoProvider),
    ref.watch(stockMovementDaoProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(currencyRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// The item catalogue.
final itemRepositoryProvider = Provider<ItemRepository>(
  (ref) =>
      ItemRepositoryImpl(ref.watch(itemDaoProvider), ref.watch(clockProvider)),
);

/// Recipes, their ingredients and their cook log.
final recipeRepositoryProvider = Provider<RecipeRepository>(
  (ref) => RecipeRepositoryImpl(
    ref.watch(recipeDaoProvider),
    ref.watch(itemDaoProvider),
    ref.watch(unitDaoProvider),
    ref.watch(uidGeneratorProvider),
    ref.watch(clockProvider),
  ),
);

/// Cooking a recipe: deducts stock through the inventory module and records that it happened.
///
/// Depends on `StockRepository` rather than reimplementing consumption — FEFO ordering, the atomic
/// application and the shortfall refusal all already live there.
final recipeCookServiceProvider = Provider<RecipeCookService>(
  (ref) => RecipeCookService(
    recipes: ref.watch(recipeRepositoryProvider),
    stock: ref.watch(stockRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Inventory batches.
final batchRepositoryProvider = Provider<BatchRepository>(
  (ref) => BatchRepositoryImpl(
    ref.watch(batchDaoProvider),
    ref.watch(itemCategoryResolverProvider),
    ref.watch(clockProvider),
  ),
);

/// Stock levels and movements.
final stockRepositoryProvider = Provider<StockRepository>(
  (ref) => StockRepositoryImpl(
    ref.watch(batchDaoProvider),
    ref.watch(stockMovementDaoProvider),
    ref.watch(itemCategoryResolverProvider),
    ref.watch(uidGeneratorProvider),
    ref.watch(clockProvider),
  ),
);

/// Shopping lists and entries.
final shoppingRepositoryProvider = Provider<ShoppingRepository>(
  (ref) => ShoppingRepositoryImpl(
    ref.watch(shoppingListDaoProvider),
    ref.watch(shoppingEntryDaoProvider),
    ref.watch(itemDaoProvider),
    ref.watch(transactionLineDaoProvider),
    ref.watch(itemCategoryResolverProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(uidGeneratorProvider),
    ref.watch(clockProvider),
  ),
);

/// Recurring templates and occurrences.
final recurringRepositoryProvider = Provider<RecurringRepository>(
  (ref) => RecurringRepositoryImpl(
    ref.watch(recurringTemplateDaoProvider),
    ref.watch(recurringOccurrenceDaoProvider),
    ref.watch(transactionRepositoryProvider),
    ref.watch(uidGeneratorProvider),
    ref.watch(clockProvider),
  ),
);

/// Assets.
final assetRepositoryProvider = Provider<AssetRepository>(
  (ref) => AssetRepositoryImpl(
    ref.watch(assetDaoProvider),
    ref.watch(clockProvider),
  ),
);

/// Service records.
final serviceRecordRepositoryProvider = Provider<ServiceRecordRepository>(
  (ref) => ServiceRecordRepositoryImpl(
    ref.watch(serviceRecordDaoProvider),
    ref.watch(assetDaoProvider),
    ref.watch(transactionRepositoryProvider),
    ref.watch(uidGeneratorProvider),
    ref.watch(clockProvider),
  ),
);

/// The calendar feed. Phase 3A declared the contract and no phase implemented it until 7A
/// (ARCH_4 §5.1 item 15), which is why `calendarAggregatorProvider` could not exist.
final calendarRepositoryProvider = Provider<CalendarRepository>(
  (ref) => CalendarRepositoryImpl(ref.watch(calendarDaoProvider)),
);

/// Memoised analytics results. Phase 3A declared the contract and no phase implemented it until 7B
/// (ARCH_4 §5.1 item 15), which is why `analyticsCacheServiceProvider` could not exist.
///
/// The `Clock` is the impl's own, not the DAO's: `AnalyticsCacheDao` takes absolute millis so it
/// stays assertable under a `FixedClock`, and the contract takes a `Duration`.
final analyticsCacheRepositoryProvider = Provider<AnalyticsCacheRepository>(
  (ref) => AnalyticsCacheRepositoryImpl(
    ref.watch(analyticsCacheDaoProvider),
    ref.watch(clockProvider),
  ),
);

/// The raw aggregates behind ARCH_3 §5.1's twenty-four queries.
///
/// Typed as the **port**, so `AnalyticsService` cannot reach into the adapter for a query the
/// contract does not declare — and so a fake in a test substitutes without the service noticing
/// (ARCH_4 R19).
final analyticsPortProvider = Provider<AnalyticsPort>(
  (ref) =>
      AnalyticsPortImpl(ref.watch(databaseProvider), ref.watch(clockProvider)),
);

/// Split groups and their membership, plus which payee the user has claimed as themselves.
///
/// Takes `SettingsDao` for `split.selfPayeeId` — a setting rather than a flag on `payees`, so no two
/// rows can claim it and a table five other modules read stays untouched.
final splitGroupRepositoryProvider = Provider<SplitGroupRepository>(
  (ref) => SplitGroupRepositoryImpl(
    ref.watch(splitDaoProvider),
    ref.watch(settingsDaoProvider),
    ref.watch(clockProvider),
  ),
);

/// Shared expenses, settlements, and every balance derived from them.
///
/// Takes `AccountDao` so a settlement can be checked against the account it claims to have moved
/// through — the currency match in particular, which is Law L8's money-side twin. That is ordinary
/// cross-module DAO composition: `TransactionRepositoryImpl` holds six DAOs across three modules and
/// its own class doc calls it *"normal DAO composition, not a layering violation."*
final splitLedgerRepositoryProvider = Provider<SplitLedgerRepository>(
  (ref) => SplitLedgerRepositoryImpl(
    ref.watch(splitDaoProvider),
    ref.watch(splitViewDaoProvider),
    ref.watch(splitGroupRepositoryProvider),
    ref.watch(accountDaoProvider),
    ref.watch(clockProvider),
  ),
);
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
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_auth/local_auth.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/data/backup/backup_service.dart';
import 'package:alaya/data/backup/restore_service.dart';
import 'package:alaya/data/remote/currency_api_client.dart';
import 'package:alaya/data/repositories/mappers/rate_mappers.dart';
import 'package:alaya/data/security/app_lock_store.dart';
import 'package:alaya/data/backup/erase_service.dart';
import 'package:alaya/data/attachments/attachment_store.dart';
import 'package:alaya/data/backup/restore_service.dart';
import 'package:alaya/data/backup/share_backup_transfer.dart';
import 'package:alaya/data/reminders/local_notification_scheduler.dart';
import 'package:alaya/data/support/ads_and_billing.dart';
import 'package:alaya/data/trash/trash_adapter.dart';
import 'package:alaya/data/security/local_auth_biometric_gate.dart';
import 'package:alaya/data/security/pin_service.dart';
import 'package:alaya/data/security/recovery_code.dart';
import 'package:alaya/domain/services/analytics/analytics_cache_service.dart';
import 'package:alaya/domain/services/analytics/analytics_service.dart';
import 'package:alaya/domain/services/attachments/attachment_port.dart';
import 'package:alaya/domain/services/backup/data_transfer_port.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';
import 'package:alaya/domain/services/lock/app_lock.dart';
import 'package:alaya/domain/services/lock/biometric_gate.dart';
import 'package:alaya/domain/services/reminders/reminder_port.dart';
import 'package:alaya/domain/services/support/support_port.dart';
import 'package:alaya/domain/services/trash/trash_port.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';
import 'package:alaya/domain/services/date_range_service.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';
import 'package:alaya/domain/services/low_stock_suggestion_engine.dart';
import 'package:alaya/domain/services/purchase_fan_out_service.dart';
import 'package:alaya/domain/services/recurring_engine.dart';
import 'package:alaya/domain/services/stock_reconciler.dart';
import 'package:alaya/domain/services/unit_engine.dart';
import 'package:alaya/domain/services/split/settlement_service.dart';
import 'package:alaya/domain/services/split/split_balance_service.dart';
import 'package:alaya/domain/services/split/split_expense_service.dart';

// ── stateless engines ───────────────────────────────────────────────────────────────────

/// Unit conversion within a category.
final unitEngineProvider = Provider<UnitEngine>((ref) => const UnitEngine());

/// Date-range presets for filters and analytics.
final dateRangeServiceProvider = Provider<DateRangeService>(
  (ref) => const DateRangeService(),
);

/// Net worth and per-account balances.
final balanceServiceProvider = Provider<BalanceService>(
  (ref) => const BalanceService(),
);

/// FEFO consumption planning.
final inventoryConsumptionServiceProvider =
    Provider<InventoryConsumptionService>(
      (ref) => const InventoryConsumptionService(),
    );

/// Cache-versus-ledger reconciliation and repair.
final stockReconcilerProvider = Provider<StockReconciler>(
  (ref) => const StockReconciler(),
);

/// Idempotent low-stock suggestion decisions.
final lowStockSuggestionEngineProvider = Provider<LowStockSuggestionEngine>(
  (ref) => const LowStockSuggestionEngine(),
);

/// Recurring schedule arithmetic — next due, materialisation, settlement.
final recurringEngineProvider = Provider<RecurringEngine>(
  (ref) => const RecurringEngine(),
);

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
    restore: ref.watch(restoreServiceProvider),
    history: ref.watch(backupHistoryDaoProvider),
    database: ref.watch(databaseProvider),
    attachments: ref.watch(attachmentPortProvider),
  ),
);

/// Attaching, viewing and deleting files (ARCH_5 §7's `attachments` row).
///
/// Typed as the contract, so no feature can reach `file_picker` — and so a widget test substitutes a fake instead
/// of needing a platform channel.
final attachmentPortProvider = Provider<AttachmentPort>(
  (ref) => AttachmentStore(
    database: ref.watch(databaseProvider),
    uids: ref.watch(uidGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// The trash, and the one hard delete in the codebase (ARCH_3 §4.2).
final trashPortProvider = Provider<TrashPort>(
  (ref) => TrashAdapter(
    database: ref.watch(databaseProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// One daily digest, inexactly scheduled (ARCH_3 §7).
final reminderPortProvider = Provider<ReminderPort>(
  (ref) => LocalNotificationScheduler(
    plugin: FlutterLocalNotificationsPlugin(),
    database: ref.watch(databaseProvider),
    scheduleDao: ref.watch(notificationScheduleDaoProvider),
    calendar: ref.watch(calendarAggregatorProvider),
    settings: ref.watch(settingsRepositoryProvider),
    uids: ref.watch(uidGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Rewarded ads and the one-time tip.
///
/// **Constructing this initialises nothing.** `AdsAndBilling` brings the SDKs up only when `initialise()` is
/// called, which the Support screen does in `initState` and nothing else does at all — so watching this provider
/// from anywhere would still make no ad call.
final supportPortProvider = Provider<SupportPort>((ref) => AdsAndBilling());

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
  final home =
      await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ??
      analyticsFallbackHomeCurrencyCode;
  return AnalyticsService(
    port: ref.watch(analyticsPortProvider),
    rates: rates,
    homeCurrencyCode: home,
  );
});

/// Turning split instructions into stored shares.
///
/// Holds `SplitResolver` by default rather than taking one per call: the resolver is stateless and
/// `const`, and threading it through every call site would be a parameter that never varies.
final splitExpenseServiceProvider = Provider<SplitExpenseService>(
  (ref) => SplitExpenseService(
    ledger: ref.watch(splitLedgerRepositoryProvider),
    uids: ref.watch(uidGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Recording money that changed hands to settle a split debt.
///
/// **The one write in this module whose failure a user could not see**, which is why it goes through a
/// single repository call that writes the settlement and its transaction in one database transaction.
/// Splitwise's "settle up" is a marker it cannot back with anything; here the deposit or withdrawal is
/// an ordinary `transactions` row, so the two ledgers cannot diverge.
final settlementServiceProvider = Provider<SettlementService>(
  (ref) => SettlementService(
    ledger: ref.watch(splitLedgerRepositoryProvider),
    groups: ref.watch(splitGroupRepositoryProvider),
    uids: ref.watch(uidGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Who owes what, how long they have owed it, and the shortest way to settle up.
///
/// Takes `Clock` because the balance views cannot: ARCH_2 §12.2 forbids any view from consulting the
/// current time, so the ageing that the daily digest reads — *"owed for three weeks"* — is computed
/// here against an injected clock and stays reproducible under a `FixedClock`.
final splitBalanceServiceProvider = Provider<SplitBalanceService>(
  (ref) => SplitBalanceService(
    ledger: ref.watch(splitLedgerRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
);
```

### `lib/app/router/app_router.dart`

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/analytics/presentation/screens/analytics_home_screen.dart';
import 'package:alaya/features/analytics/presentation/screens/drill_down_screen.dart';
import 'package:alaya/features/analytics/state/drill_down_spec.dart';
import 'package:alaya/features/backup/presentation/screens/backup_screen.dart';
import 'package:alaya/features/backup/presentation/screens/restore_flow.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_detail_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_editor_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_list_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_editor_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_history_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/inventory_list_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/item_detail_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/item_editor_screen.dart';
import 'package:alaya/features/lock/presentation/screens/lock_screen.dart';
import 'package:alaya/features/lock/presentation/screens/pin_setup_flow.dart';
import 'package:alaya/features/lock/presentation/screens/recovery_flow.dart';
import 'package:alaya/features/onboarding/presentation/screens/onboarding_flow.dart';
import 'package:alaya/features/recipe/presentation/screens/recipe_detail_screen.dart';
import 'package:alaya/features/recipe/presentation/screens/recipe_editor_screen.dart';
import 'package:alaya/features/recipe/presentation/screens/recipe_list_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/occurrence_history_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/template_builder_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/template_list_screen.dart';
import 'package:alaya/features/reminders/presentation/screens/reminders_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_detail_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_editor_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_list_screen.dart';
import 'package:alaya/features/service/presentation/screens/service_editor_screen.dart';
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
import 'package:alaya/features/settings/presentation/screens/split_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/tag_editor_screen.dart';
import 'package:alaya/features/settings/presentation/screens/tags_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/unit_editor_screen.dart';
import 'package:alaya/features/settings/presentation/screens/units_settings_screen.dart';
import 'package:alaya/features/shopping/presentation/screens/convert_to_purchase_screen.dart';
import 'package:alaya/features/shopping/presentation/screens/shopping_list_screen.dart';
import 'package:alaya/features/split/presentation/screens/split_bill_screen.dart';
import 'package:alaya/features/split/presentation/screens/split_group_editor_screen.dart';
import 'package:alaya/features/split/presentation/screens/split_home_screen.dart';
import 'package:alaya/features/support/presentation/screens/support_screen.dart';
import 'package:alaya/features/support/presentation/widgets/support_action.dart';
import 'package:alaya/features/trash/presentation/screens/trash_screen.dart';
import 'package:alaya/shared/widgets/alaya_drawer.dart';

/// Whether the app is currently locked, consulted on every navigation.
typedef LockGate = bool Function();

/// Whether the first-run flow still has to happen, consulted on every navigation.
typedef OnboardingGate = bool Function();

/// The app's `go_router` configuration — hand-written, per ARCH_1 §7.3.
///
/// **The eleven drawer destinations sit inside the shell; every detail and editor route sits outside
/// it** (U18). `AppBar` resolves its leading slot by checking `hasDrawer` *before* `canPop`, so a
/// detail screen rendered inside the drawer shell gets a hamburger where a back arrow belongs.
///
/// Literal-path segments are declared before their parameterised siblings, because go_router walks
/// its route list in order and `:itemId` would otherwise swallow the word `new`.
///
/// **Phase 7B: `/insights` is now a real screen and `/insights/drill/...` is its drill-down.** The
/// drill-down is a top-level route rather than a child of `/insights`, unlike the calendar's day
/// route: a day is a view *of* the month and keeps the drawer (Law U27), while a drill-down leaves
/// analytics for the ledger and needs a back arrow, which a shell owning a drawer can never imply.
///
/// **`_detail` was removed in 7B and `_destination` in 8A.** Both were declared and then called by
/// nothing once the last placeholder became a real screen, and `very_good_analysis` reports
/// `unused_element` on each. `_DetailScaffold` below is now in the same position and is kept only
/// because removing it is a separate decision from adding a route.
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
        final inLockBranch =
            location == Routes.lockBranch ||
            location.startsWith('${Routes.lockBranch}/');
        if (locked()) return inLockBranch ? null : Routes.lock;
        if (inLockBranch) return Routes.dashboard;
        // **Checked after the lock, not before.** A lock protects data that onboarding is about to add
        // to; asking somebody to finish setting up an app they cannot yet open would be the wrong
        // order.
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
          // No `location` passed: `_ShellScaffold` reads it from the router, because the state handed
          // to a pathless `ShellRoute`'s builder reports `/` for every screen inside it.
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
              path: Routes.recipes,
              builder: (context, state) => const RecipeListScreen(),
            ),
            GoRoute(
              path: Routes.split,
              builder: (context, state) => const SplitHomeScreen(),
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
        // **Outside the shell, all of them.** `AppBar` resolves its leading slot by checking
        // `hasDrawer` before `canPop`, so a screen rendered inside the drawer shell gets a hamburger
        // where a back arrow belongs (Law U18). Only `/split` itself is a destination; these are
        // reached from it.
        //
        // `/split/new` is declared first. There is no `/split/:id` route today, so nothing can swallow
        // it — but go_router takes the first match rather than the most specific, and the day somebody
        // adds one this ordering is what stops the bill screen quietly becoming unreachable.
        GoRoute(
          path: Routes.splitNew,
          // **`extra` carries the split being edited.** A `/split/:id/edit` route would be a fifth on a module
          // that just went from eight routes to four, and this screen's draft is in-memory — so a deep
          // link into a half-edited split could not restore what the URL promised.
          builder: (context, state) =>
              SplitBillScreen(expenseId: state.extra as String?),
        ),
        // Literal before parameterised, or `:groupId` swallows the word `new`.
        GoRoute(
          path: Routes.splitGroupNew,
          builder: (context, state) => const SplitGroupEditorScreen(),
        ),
        GoRoute(
          path: Routes.splitGroupEdit,
          builder: (context, state) => SplitGroupEditorScreen(
            groupId: state.pathParameters[Routes.pGroupId],
          ),
        ),
        GoRoute(
          path: Routes.settingsSplit,
          builder: (context, state) => const SplitSettingsScreen(),
        ),
        GoRoute(
          path: Routes.itemNew,
          builder: (context, state) => const ItemEditorScreen(),
        ),
        GoRoute(
          path: Routes.batchNewPattern,
          builder: (context, state) =>
              BatchEditorScreen(itemId: state.pathParameters[Routes.pItemId]!),
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
          builder: (context, state) =>
              ItemEditorScreen(itemId: state.pathParameters[Routes.pItemId]),
        ),
        GoRoute(
          path: Routes.itemDetailPattern,
          builder: (context, state) =>
              ItemDetailScreen(itemId: state.pathParameters[Routes.pItemId]!),
        ),
        GoRoute(
          path: Routes.shoppingConvertPattern,
          builder: (context, state) => ConvertToPurchaseScreen(
            listId: state.pathParameters[Routes.pListId]!,
          ),
        ),
        GoRoute(
          path: Routes.shoppingListPattern,
          builder: (context, state) =>
              ShoppingListScreen(listId: state.pathParameters[Routes.pListId]),
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
          builder: (context, state) =>
              AssetEditorScreen(assetId: state.pathParameters[Routes.pAssetId]),
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
          builder: (context, state) =>
              TagEditorScreen(tagId: state.pathParameters[Routes.pTagId]),
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
        // Phase 8B. `/settings/data/backup/restore` before `/settings/data/backup`, and both before
        // `/settings/data`, for the same first-match reason every other nesting here has.
        GoRoute(
          path: Routes.settingsRestore,
          builder: (context, state) => const RestoreFlow(),
        ),
        GoRoute(
          // Before `recipeDetail`, or `/recipes/new` matches `/recipes/:id` and the editor never
          // opens — go_router takes the first match, not the most specific.
          path: Routes.recipeNew,
          builder: (context, state) => const RecipeEditorScreen(recipeId: ''),
        ),
        GoRoute(
          path: Routes.recipeEdit,
          builder: (context, state) =>
              RecipeEditorScreen(recipeId: state.pathParameters['id'] ?? ''),
        ),
        GoRoute(
          // Outside the shell, like every other drill-down: a detail screen owns its own app bar
          // and back arrow rather than inheriting the shell's.
          path: Routes.recipeDetail,
          builder: (context, state) =>
              RecipeDetailScreen(recipeId: state.pathParameters['id'] ?? ''),
        ),
        GoRoute(
          path: Routes.settingsBackup,
          builder: (context, state) => const BackupScreen(),
        ),
        GoRoute(
          path: Routes.settingsTrash,
          builder: (context, state) => const TrashScreen(),
        ),
        GoRoute(
          path: Routes.settingsReminders,
          builder: (context, state) => const RemindersScreen(),
        ),
        GoRoute(
          path: Routes.support,
          builder: (context, state) => const SupportScreen(),
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
    // **Read from the router, not from the builder's `state`.** `ShellRoute` declares no `path`, so
    // the `GoRouterState` handed to its builder describes the *shell's* match rather than the leaf's —
    // and a pathless route's `matchedLocation` is its parent's, which here is `/`. Every screen inside
    // the shell therefore looked like the dashboard: the home action never rendered, `AlayaDrawer`
    // highlighted Dashboard wherever you were, and `titleFor` named it too.
    //
    // `currentConfiguration` is the delegate's live `RouteMatchList`, so its `uri` is the leaf location
    // no matter which builder asks.
    final here = GoRouter.of(
      context,
    ).routerDelegate.currentConfiguration.uri.path;
    // **`context.canPop()` cannot answer this question from here.** This widget is the `ShellRoute`
    // builder, so its context sits *above* the shell's own `Navigator`; `canPop` resolves against the
    // root navigator, which only ever holds the shell itself. It therefore returns false however the
    // screen was reached, `leading` was always null, and the back arrow this once tried to show could
    // never appear.
    //
    // So the way home is stated outright instead of inferred from a stack this context cannot see:
    // every shell screen except the dashboard carries a home action. The hamburger keeps its slot,
    // because the drawer is still how you move between peers (Law U27).
    return Scaffold(
      drawer: AlayaDrawer(currentLocation: here),
      appBar: AppBar(
        // **The title is the second way home, and it costs nothing.** Somebody reading "Inventory" at
        // the top of the screen is already looking at the name of where they are; tapping it to leave
        // is the one gesture that needs no new affordance and no explanation once found.
        //
        // Not a replacement for the button — an undiscoverable path cannot be the only path. It is the
        // one a returning user finds by accident and then keeps using, which is the best kind.
        title: here == Routes.dashboard
            ? Text(AlayaDrawer.titleFor(context, here))
            : InkWell(
                onTap: () => context.go(Routes.dashboard),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AlayaSpacing.xs,
                    horizontal: AlayaSpacing.xxs,
                  ),
                  child: Text(AlayaDrawer.titleFor(context, here)),
                ),
              ),
        actions: [
          // Home moved to a floating button; see [_HomeFab]. The ternary that was here read
          // `canPop() ? pop() : go(dashboard)`, and **the first branch could never run** — the comment
          // above explains why `canPop` is always false from a `ShellRoute` builder.
          //
          // `SupportAction` loads nothing until pressed. ARCH_4 §5.1 said rewarded ads live "only in
          // Support Us"; this amends the entry point and keeps the constraint — no `MobileAds`
          // initialisation, no consent fetch and no ad request happen on build, so a user who never
          // taps it never has an advertising identifier collected.
          const SupportAction(),
        ],
      ),
      body: child,
      // **In the shell, so it reaches every screen** — which is what makes it worth having. Only the
      // dashboard defines an expandable FAB, so "above the existing FAB" would have placed Home on the
      // one screen where you are already home.
      //
      // `here`, not `canPop`: this context cannot see the shell's navigator, and the leaf path can.
      floatingActionButton: here == Routes.dashboard ? null : const _HomeFab(),
      // `startFloat` — bottom-left, diagonally opposite where a screen's own FAB sits. Two buttons in
      // one corner is a collision; using the other corner removes it rather than managing it: no
      // stacking, no offset arithmetic, and nothing to interact with an unfolding menu.
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
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

/// A floating way back to the dashboard.
///
/// **Small, and bottom-left.** A screen's own FAB is its primary action and owns the bottom-right
/// corner; this is navigation, which is secondary, so it takes the opposite corner and a smaller
/// footprint.
///
/// `go`, not `push`: the dashboard is a peer destination, and pushing it would grow a stack of
/// dashboards behind the user (Law U27).
class _HomeFab extends StatelessWidget {
  const _HomeFab();

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    return FloatingActionButton.small(
      // An explicit tag: two `FloatingActionButton`s in one route throw on the default hero tag, and
      // seven of the twelve shell screens already have one.
      heroTag: 'alaya-home-fab',
      // **Low emphasis, and this is the point.** In primary colour a bottom-left FAB reads as *the*
      // action on the screen, competing with the create button diagonally opposite it — two saturated
      // circles, equal weight, different jobs. Surface-toned with a muted glyph, it reads as a way
      // *out* rather than a thing to do, which is what navigation should look like.
      //
      // The position was never the problem. Two primary actions was.
      backgroundColor: scheme.surfaceContainerHighest,
      foregroundColor: semantic.muted,
      elevation: 1,
      highlightElevation: 2,
      onPressed: () => context.go(Routes.dashboard),
      tooltip: strings.navBackToDashboard,
      child: const Icon(Icons.home_outlined, size: AlayaIconSize.md),
    );
  }
}
```

### `lib/app/router/placeholder_screen.dart`

```dart
// PLACEHOLDER: PHASE_06
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// Stands in for a feature screen until the phase that owns it lands.
///
/// One parameterised placeholder rather than nine near-identical stub files: nine stubs would each
/// need deleting, and a stub left behind is indistinguishable from a real screen that does nothing.
///
/// It carries no destination name of its own. The surrounding scaffold titles itself from
/// `AlayaDrawer.titleFor`, so every visible name is localised in one place instead of appearing here
/// as a dozen English literals that no translator would ever see.
class PlaceholderScreen extends StatelessWidget {
  /// Creates a placeholder owned by [owningPhase], e.g. `Phase 6A`.
  const PlaceholderScreen({required this.owningPhase, super.key});

  /// The phase that will replace this. Developer text, deliberately not localised.
  final String owningPhase;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AlayaSpacing.xxl),
        child: Text(
          owningPhase,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
```

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

  /// The recipe catalogue.
  static const String recipes = '/recipes';

  /// One recipe.
  static const String recipeDetail = '/recipes/:id';

  /// Builds the path to one recipe.
  static String recipeDetailFor(String id) => '/recipes/$id';

  /// A new recipe.
  ///
  /// Declared before [recipeDetail] and matched before it too: `/recipes/new` would otherwise be
  /// read as a recipe whose id is the word "new" — the same first-match ordering every nested route
  /// in this file depends on.
  static const String recipeNew = '/recipes/new';

  /// Editing an existing recipe.
  static const String recipeEdit = '/recipes/:id/edit';

  /// Builds the path to a recipe's editor.
  static String recipeEditFor(String id) => '/recipes/$id/edit';

  /// Shared expenses, and who owes what.
  ///
  /// **One destination for the whole module.** `/split/groups`, `/split/groups/:groupId` and
  /// `/split/groups/:groupId/settle` were deleted: the groups list is a tab here, and a group's balances
  /// and its settle-up plan are bottom sheets. Nothing in any of the three was an editor, so each route
  /// bought a back arrow, an app bar competing for a 320dp title, and a place for somebody to end up
  /// without knowing how they got there.
  static const String split = '/split';

  /// Splitting a bill, on one screen.
  ///
  /// **Declared before every `/split/:something` route**, for the reason [recipeNew] and
  /// [splitGroupNew] both record: go_router takes the first match rather than the most specific, so a
  /// parameterised sibling declared earlier would read `new` as an id. There is no `/split/:id` route
  /// today; this ordering is what keeps adding one from silently breaking this path.
  static const String splitNew = '/split/new';

  /// A new group.
  ///
  /// Declared before [splitGroupEdit] and matched before it too: `/split/groups/new` would otherwise
  /// be read as a group whose id is the word "new" — the same first-match ordering every nested route
  /// in this file depends on.
  static const String splitGroupNew = '/split/groups/new';

  /// Editing an existing group.
  static const String splitGroupEdit = '/split/groups/:groupId/edit';

  /// Builds the path to a group's editor.
  static String splitGroupEditFor(String id) => '/split/groups/$id/edit';

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

  /// Who you are in a split, and where people can pay you.
  static const String settingsSplit = '/settings/split';

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
  /// [lockBranch] while locked; anywhere else and a locked user would be bounced back to `/lock` the
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

  /// Settings › Data › Backup.
  static const String settingsBackup = '/settings/data/backup';

  /// Restoring from a backup file.
  ///
  /// Under Backup rather than beside it: a restore is something you reach *from* the list of backups
  /// you have taken, and the route saying so is what gives it a back arrow to somewhere sensible.
  static const String settingsRestore = '/settings/data/backup/restore';

  /// Settings › Data › Trash.
  static const String settingsTrash = '/settings/data/trash';

  /// Settings › Reminders.
  static const String settingsReminders = '/settings/reminders';

  /// Support Us — rewarded ads and a one-time tip.
  ///
  /// **Outside every settings branch, and that is deliberate.** Ads load when this screen opens and
  /// nowhere else (ARCH_4 §5.1); burying it under Settings › About would make it look like a
  /// disclosure rather than a choice, and putting it in the shell would load an SDK for people who
  /// never asked.
  static const String support = '/support';

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
  static const String transactionLinesPattern =
      '/expenses/:transactionId/lines';

  /// Path pattern for one item.
  static const String itemDetailPattern = '/inventory/:itemId';

  /// Path pattern for editing one item.
  static const String itemEditPattern = '/inventory/:itemId/edit';

  /// Path pattern for adding a batch to one item.
  static const String batchNewPattern = '/inventory/:itemId/batch/new';

  /// Path pattern for editing one batch.
  static const String batchEditPattern = '/inventory/:itemId/batch/:batchId';

  /// Path pattern for one batch's movement history.
  static const String batchHistoryPattern =
      '/inventory/:itemId/batch/:batchId/history';

  /// Path pattern for one shopping list.
  static const String shoppingListPattern = '/shopping/:listId';

  /// Path pattern for turning a shopping list's ticked entries into a purchase.
  static const String shoppingConvertPattern = '/shopping/:listId/convert';

  /// Path pattern for editing one recurring template.
  static const String recurringEditPattern = '/recurring/:templateId/edit';

  /// Path pattern for one template's occurrence history.
  static const String recurringHistoryPattern =
      '/recurring/:templateId/history';

  /// Path pattern for one recurring template.
  static const String recurringDetailPattern = '/recurring/:templateId';

  /// Path pattern for editing one asset.
  static const String assetEditPattern = '/services/:assetId/edit';

  /// Path pattern for a new service record against one asset.
  static const String serviceNewPattern = '/services/:assetId/service/new';

  /// Path pattern for editing one service record.
  static const String serviceEditPattern =
      '/services/:assetId/service/:recordId';

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
  /// **Outside the shell**, unlike [calendarDayPattern]. A day is a view *of* the month, so it keeps
  /// the drawer and the grid stays behind it (Law U27); a drill-down leaves analytics for the ledger
  /// and needs a back arrow, which a shell owning a drawer can never imply (Law U18).
  ///
  /// **The window is deliberately absent from the path.** ARCH_5 §5.7 keeps a selected range in the
  /// view-model — the URL is the record's identity and nothing else — so a drill-down inherits
  /// whatever range the analytics screen is showing.
  static const String insightsDrillDownPattern =
      '/insights/drill/:drillKind/:drillValue';

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

  /// The split-group id parameter.
  static const String pGroupId = 'groupId';

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
  static String assetEdit(String? id) =>
      id == null ? assetNew : '$services/$id/edit';

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
  static String tagEdit(String? id) =>
      id == null ? tagNew : '$settingsTags/$id';

  /// The location for editing [code], or for a new unit when null.
  static String unitEdit(String? code) =>
      code == null ? unitNew : '$settingsUnits/$code';

  /// The location for the analytics drill-down on [kind] with [value].
  static String insightsDrillDown(String kind, String value) =>
      '$insights/drill/$kind/$value';

  /// The eleven drawer destinations, in drawer order.
  ///
  /// Named for the drawer rather than the shell because `AlayaDrawer` reads it by this name — a route
  /// cannot exist in the router and be missing from the drawer without this list disagreeing.
  ///
  /// **`AlayaDrawer` switches on this list exhaustively, twice**, for a label and an icon, so adding a
  /// destination fails to compile until both know about it. That is the check, and it is why the
  /// count in this sentence is the only part of the arrangement that can go stale — it said "nine"
  /// while the list held eleven.
  static const List<String> drawerDestinations = [
    dashboard,
    expenses,
    inventory,
    recipes,
    split,
    shopping,
    recurring,
    services,
    calendar,
    insights,
    settings,
  ];
}
```

### `lib/app/theme/alaya_theme.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/palettes/palette.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_durations.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// Turns a palette plus the tokens into light and dark `ThemeData` (ARCH_3 §8).
///
/// Every component theme is configured here rather than left to Material's defaults, because a
/// default is a colour and a radius chosen by someone who had not seen this palette. Leaving them
/// unset is how an app ends up with a purple ripple on an indigo button.
abstract final class AlayaTheme {
  /// The light theme for [palette], defaulting to the active preset.
  static ThemeData light([AlayaPalette palette = AlayaPresets.activePreset]) =>
      _build(palette: palette, isDark: false);

  /// The dark theme for [palette], defaulting to the active preset.
  static ThemeData dark([AlayaPalette palette = AlayaPresets.activePreset]) =>
      _build(palette: palette, isDark: true);

  static ThemeData _build({
    required AlayaPalette palette,
    required bool isDark,
  }) {
    final colors = palette.forMode(isDark: isDark);
    final scheme = _scheme(colors, isDark: isDark);
    final text = _textTheme(colors);

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.surfaceBase,
      canvasColor: colors.surfaceBase,
      dividerColor: colors.divider,
      textTheme: text,
      // Splash and highlight derive from the accent rather than Material's default ink, so a tap
      // never flashes a colour that is not in the palette.
      splashColor: colors.accent.withValues(alpha: 0.10),
      highlightColor: colors.accent.withValues(alpha: 0.06),
      extensions: [AlayaSemanticColors.fromColorSet(colors)],
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surfaceBase,
        foregroundColor: colors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AlayaTypography.screenTitle.copyWith(
          color: colors.textPrimary,
        ),
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: colors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderMd),
      ),
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceSunken,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AlayaSpacing.sm,
          vertical: AlayaSpacing.sm,
        ),
        border: const OutlineInputBorder(
          borderRadius: AlayaRadii.borderSm,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AlayaRadii.borderSm,
          borderSide: BorderSide(color: colors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AlayaRadii.borderSm,
          borderSide: BorderSide(color: colors.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AlayaRadii.borderSm,
          borderSide: BorderSide(color: colors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AlayaRadii.borderSm,
          borderSide: BorderSide(color: colors.danger, width: 2),
        ),
        labelStyle: AlayaTypography.label.copyWith(color: colors.textSecondary),
        floatingLabelStyle: AlayaTypography.label.copyWith(
          color: colors.accent,
        ),
        hintStyle: AlayaTypography.body.copyWith(color: colors.textMuted),
        errorStyle: AlayaTypography.caption.copyWith(color: colors.danger),
        prefixIconColor: colors.textSecondary,
        suffixIconColor: colors.textSecondary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          disabledBackgroundColor: colors.surfaceSunken,
          disabledForegroundColor: colors.textMuted,
          minimumSize: const Size(0, AlayaSpacing.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.lg),
          textStyle: AlayaTypography.button,
          shape: const RoundedRectangleBorder(
            borderRadius: AlayaRadii.borderSm,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primary,
          side: BorderSide(color: colors.divider),
          minimumSize: const Size(0, AlayaSpacing.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.lg),
          textStyle: AlayaTypography.button,
          shape: const RoundedRectangleBorder(
            borderRadius: AlayaRadii.borderSm,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.accent,
          minimumSize: const Size(0, AlayaSpacing.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.sm),
          textStyle: AlayaTypography.button,
          shape: const RoundedRectangleBorder(
            borderRadius: AlayaRadii.borderSm,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderMd),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceSunken,
        selectedColor: colors.primary,
        disabledColor: colors.surfaceSunken,
        labelStyle: AlayaTypography.overline.copyWith(
          color: colors.textSecondary,
        ),
        secondaryLabelStyle: AlayaTypography.overline.copyWith(
          color: colors.onPrimary,
        ),
        side: BorderSide(color: colors.divider),
        padding: const EdgeInsets.symmetric(
          horizontal: AlayaSpacing.xs,
          vertical: AlayaSpacing.xxs,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderXs),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceOverlay,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.sheetTop),
        showDragHandle: true,
        dragHandleColor: colors.divider,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceOverlay,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderLg),
        titleTextStyle: AlayaTypography.cardTitle.copyWith(
          color: colors.textPrimary,
        ),
        contentTextStyle: AlayaTypography.body.copyWith(
          color: colors.textSecondary,
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: colors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(AlayaRadii.lg),
            bottomRight: Radius.circular(AlayaRadii.lg),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.textSecondary,
        textColor: colors.textPrimary,
        titleTextStyle: AlayaTypography.body.copyWith(
          color: colors.textPrimary,
        ),
        subtitleTextStyle: AlayaTypography.caption.copyWith(
          color: colors.textSecondary,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.md),
        minVerticalPadding: AlayaSpacing.xs,
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderSm),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surfaceOverlay,
        contentTextStyle: AlayaTypography.body.copyWith(
          color: colors.textPrimary,
        ),
        actionTextColor: colors.accent,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderSm),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.accent,
        linearTrackColor: colors.surfaceSunken,
        circularTrackColor: colors.surfaceSunken,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.onAccent
              : colors.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.accent
              : colors.surfaceSunken,
        ),
        trackOutlineColor: WidgetStateProperty.all(colors.divider),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.accent
              : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.all(colors.onAccent),
        side: BorderSide(color: colors.divider, width: 1.5),
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderXs),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colors.textPrimary,
        unselectedLabelColor: colors.textMuted,
        labelStyle: AlayaTypography.bodyEmphasis,
        unselectedLabelStyle: AlayaTypography.body,
        indicatorColor: colors.accent,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: colors.divider,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colors.accent.withValues(alpha: 0.14),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.all(
          AlayaTypography.overline.copyWith(color: colors.textSecondary),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colors.accent
                : colors.textMuted,
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.surfaceOverlay,
          borderRadius: AlayaRadii.borderXs,
          border: Border.all(color: colors.divider),
        ),
        textStyle: AlayaTypography.caption.copyWith(color: colors.textPrimary),
        waitDuration: AlayaDurations.slow,
      ),
      iconTheme: IconThemeData(color: colors.textSecondary, size: 22),
    );
  }

  static ColorScheme _scheme(AlayaColorSet colors, {required bool isDark}) =>
      ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: colors.primary,
        onPrimary: colors.onPrimary,
        secondary: colors.accent,
        onSecondary: colors.onAccent,
        error: colors.danger,
        onError: colors.onStatus,
        surface: colors.surfaceBase,
        onSurface: colors.textPrimary,
        surfaceContainerLowest: colors.surfaceSunken,
        surfaceContainerLow: colors.surfaceBase,
        surfaceContainer: colors.surfaceRaised,
        surfaceContainerHigh: colors.surfaceRaised,
        surfaceContainerHighest: colors.surfaceOverlay,
        onSurfaceVariant: colors.textSecondary,
        outline: colors.divider,
        outlineVariant: colors.divider,
      );

  /// The Material `TextTheme`, mapped from the app's semantic scale.
  ///
  /// Material's slots exist because framework widgets read them; the app's own widgets use
  /// `AlayaTypography` directly. Mapping both ways round would give two names for one style, so the
  /// rule is: framework widgets get this, Alaya widgets get the token.
  static TextTheme _textTheme(AlayaColorSet colors) {
    final primary = colors.textPrimary;
    final secondary = colors.textSecondary;
    return TextTheme(
      displayLarge: AlayaTypography.displayAmount.copyWith(color: primary),
      displayMedium: AlayaTypography.amountLarge.copyWith(color: primary),
      headlineSmall: AlayaTypography.screenTitle.copyWith(color: primary),
      titleLarge: AlayaTypography.screenTitle.copyWith(color: primary),
      titleMedium: AlayaTypography.cardTitle.copyWith(color: primary),
      titleSmall: AlayaTypography.label.copyWith(color: secondary),
      bodyLarge: AlayaTypography.body.copyWith(color: primary),
      bodyMedium: AlayaTypography.body.copyWith(color: primary),
      bodySmall: AlayaTypography.caption.copyWith(color: secondary),
      labelLarge: AlayaTypography.button.copyWith(color: primary),
      labelMedium: AlayaTypography.label.copyWith(color: secondary),
      labelSmall: AlayaTypography.overline.copyWith(color: secondary),
    );
  }
}
```

### `lib/app/theme/palettes/palette.dart`

```dart
import 'package:flutter/widgets.dart';

/// A complete palette as **data**, which is the whole point of ARCH_3 §8.
///
/// Every colour the app can render is a field here. Nothing is computed from a seed and nothing is
/// derived at use time, because both make "change the palette later, easily" false: a seeded scheme
/// means you cannot adjust one colour without moving others, and a derived colour means the value
/// you see on screen exists in no file you can edit.
///
/// A preset supplies light **and** dark in one object rather than two, so a half-migrated palette —
/// light updated, dark forgotten — cannot compile.
@immutable
class AlayaPalette {
  /// Creates a palette.
  const AlayaPalette({
    required this.name,
    required this.description,
    required this.light,
    required this.dark,
  });

  /// The identifier shown in Settings and the Theme Lab.
  final String name;

  /// One line on what this palette is for — read by a human choosing between them.
  final String description;

  /// The light-mode colours.
  final AlayaColorSet light;

  /// The dark-mode colours.
  final AlayaColorSet dark;

  /// The set for [isDark].
  AlayaColorSet forMode({required bool isDark}) => isDark ? dark : light;
}

/// One mode's complete colour set.
///
/// The four surface tiers are the structural idea. Rather than one background colour plus shadows,
/// depth is expressed by stepping through tiers — which is what makes dark mode legible, since a
/// shadow on a near-black surface conveys nothing.
@immutable
class AlayaColorSet {
  /// Creates a colour set.
  const AlayaColorSet({
    required this.surfaceBase,
    required this.surfaceRaised,
    required this.surfaceOverlay,
    required this.surfaceSunken,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.onAccent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.divider,
    required this.income,
    required this.expense,
    required this.transfer,
    required this.warning,
    required this.danger,
    required this.success,
    required this.onStatus,
  });

  /// Tier 0 — the screen behind everything.
  final Color surfaceBase;

  /// Tier 1 — a card sitting on the base.
  final Color surfaceRaised;

  /// Tier 2 — a sheet, dialog or menu above a card.
  final Color surfaceOverlay;

  /// Tier -1 — an inset well: a text field's fill, a disabled row, a chart's plot area.
  ///
  /// Below the base rather than above it, which is why it is not simply "tier 3". An input needs to
  /// read as a hole you type into, not a card you might tap.
  final Color surfaceSunken;

  /// The brand colour. App bar accents, selected states, the primary button.
  final Color primary;

  /// Text and icons on [primary].
  final Color onPrimary;

  /// The interactive accent, used sparingly — the FAB, a focused field's border.
  ///
  /// Separate from [primary] so that "the brand" and "the thing you tap" can differ. When they are
  /// the same colour, every branded surface looks tappable.
  final Color accent;

  /// Text and icons on [accent].
  final Color onAccent;

  /// Primary reading colour.
  final Color textPrimary;

  /// Supporting text — an account name beneath a payee.
  final Color textSecondary;

  /// De-emphasised text — a timestamp, a disabled label, placeholder text.
  final Color textMuted;

  /// Hairlines and borders.
  final Color divider;

  /// Money arriving.
  final Color income;

  /// Money leaving.
  final Color expense;

  /// Money moving between the user's own accounts — neither a gain nor a loss.
  final Color transfer;

  /// Something needs attention soon.
  final Color warning;

  /// Something is wrong or overdue.
  final Color danger;

  /// Something completed.
  final Color success;

  /// Text and icons on any of [warning], [danger] or [success] used as a fill.
  final Color onStatus;
}
```

### `lib/app/theme/palettes/presets.dart`

```dart
import 'package:flutter/widgets.dart';

import 'package:alaya/app/theme/palettes/palette.dart';

/// The palettes that ship, and the one constant that switches the app's entire look (ARCH_3 §8).
///
/// **Deliberate constraint on income and expense: they differ in lightness as well as hue.** Roughly
/// eight percent of men have some red-green deficiency, and a finance app that encodes gain and loss
/// in hue alone is unreadable for them. In every preset below, income is the lighter of the pair —
/// so even with hue removed the two remain distinguishable, and `AmountText` additionally renders an
/// explicit sign rather than relying on colour at all.
abstract final class AlayaPresets {
  /// The palette the app boots with.
  ///
  /// **Changing this one constant changes the entire app's look**, which is the requirement ARCH_3 §8
  /// exists to satisfy. Nothing else needs editing.
  static const AlayaPalette activePreset = alaya;

  /// Every preset, for Settings and the Theme Lab.
  static const List<AlayaPalette> all = [
    alaya,
    royalSapphire,
    material,
    nord,
  ];

  static const AlayaPalette alaya = AlayaPalette(
    name: 'Alaya',
    description: 'Midnight black, ivory white, and warm saffron gold.',
    light: AlayaColorSet(
      surfaceBase: Color(0xFFF8F8F6),
      surfaceRaised: Color(0xFFFFFFFF),
      surfaceOverlay: Color(0xFFFFFFFF),
      surfaceSunken: Color(0xFFEDEDEA),

      primary: Color(0xFF000000),
      onPrimary: Color(0xFFFDFDFD),

      accent: Color(0xFFFDB424),
      onAccent: Color(0xFF1A1200),

      textPrimary: Color(0xFF111111),
      textSecondary: Color(0xFF555555),
      textMuted: Color(0xFF888888),

      divider: Color(0xFFE1E1DE),

      income: Color(0xFF21865B),
      expense: Color(0xFFD64545),
      transfer: Color(0xFF5B6472),

      warning: Color(0xFFFDB424),
      danger: Color(0xFFD64545),
      success: Color(0xFF21865B),

      onStatus: Color(0xFFFFFFFF),
    ),

    dark: AlayaColorSet(
      surfaceBase: Color(0xFF0A0A0A),
      surfaceRaised: Color(0xFF141414),
      surfaceOverlay: Color(0xFF1E1E1E),
      surfaceSunken: Color(0xFF050505),

      primary: Color(0xFFFDFDFD),
      onPrimary: Color(0xFF000000),

      accent: Color(0xFFFDB424),
      onAccent: Color(0xFF1A1200),

      textPrimary: Color(0xFFF5F5F3),
      textSecondary: Color(0xFFB4B4B1),
      textMuted: Color(0xFF777774),

      divider: Color(0xFF2A2A28),

      income: Color(0xFF5ED69A),
      expense: Color(0xFFFF7777),
      transfer: Color(0xFF9BA3B0),

      warning: Color(0xFFFDB424),
      danger: Color(0xFFFF7777),
      success: Color(0xFF5ED69A),

      onStatus: Color(0xFF000000),
    ),
  );

  static const AlayaPalette royalSapphire = AlayaPalette(
    name: 'Royal Sapphire',
    description:
        'Deep sapphire, midnight blue, and antique gold inspired by luxury banking and fine watchmaking.',

    light: AlayaColorSet(
      surfaceBase: Color(0xFFF5F7FA),
      surfaceRaised: Color(0xFFFFFFFF),
      surfaceOverlay: Color(0xFFFFFFFF),
      surfaceSunken: Color(0xFFE7EBF2),

      primary: Color(0xFF243B6B),
      onPrimary: Color(0xFFFFFFFF),

      accent: Color(0xFFB9924A),
      onAccent: Color(0xFF211704),

      textPrimary: Color(0xFF172033),
      textSecondary: Color(0xFF526078),
      textMuted: Color(0xFF8490A6),

      divider: Color(0xFFD9DEE7),

      income: Color(0xFF277A61),
      expense: Color(0xFFB54A58),
      transfer: Color(0xFF5577A8),

      warning: Color(0xFFB9924A),
      danger: Color(0xFFB54A58),
      success: Color(0xFF277A61),

      onStatus: Color(0xFFFFFFFF),
    ),

    dark: AlayaColorSet(
      surfaceBase: Color(0xFF080D18),
      surfaceRaised: Color(0xFF101827),
      surfaceOverlay: Color(0xFF182337),
      surfaceSunken: Color(0xFF050912),

      primary: Color(0xFF8FAEE8),
      onPrimary: Color(0xFF101A2E),

      accent: Color(0xFFD1AD62),
      onAccent: Color(0xFF211806),

      textPrimary: Color(0xFFEFF3FA),
      textSecondary: Color(0xFFB4C0D3),
      textMuted: Color(0xFF78869D),

      divider: Color(0xFF29354A),

      income: Color(0xFF63C39C),
      expense: Color(0xFFE37A82),
      transfer: Color(0xFF8FAEE8),

      warning: Color(0xFFD1AD62),
      danger: Color(0xFFE37A82),
      success: Color(0xFF63C39C),

      onStatus: Color(0xFF080D18),
    ),
  );

  static const AlayaPalette material = AlayaPalette(
    name: 'Material',
    description:
        'Clean surfaces, expressive blue, and balanced Material-inspired accents.',
    light: AlayaColorSet(
      surfaceBase: Color(0xFFF9F9FC),
      surfaceRaised: Color(0xFFFFFFFF),
      surfaceOverlay: Color(0xFFFFFFFF),
      surfaceSunken: Color(0xFFECECF1),

      primary: Color(0xFF6750A4),
      onPrimary: Color(0xFFFFFFFF),

      accent: Color(0xFF7D5260),
      onAccent: Color(0xFFFFFFFF),

      textPrimary: Color(0xFF1C1B1F),
      textSecondary: Color(0xFF49454F),
      textMuted: Color(0xFF79747E),

      divider: Color(0xFFE3E0E5),

      income: Color(0xFF2E7D5B),
      expense: Color(0xFFBA1A1A),
      transfer: Color(0xFF4F5D75),

      warning: Color(0xFF8A6500),
      danger: Color(0xFFBA1A1A),
      success: Color(0xFF2E7D5B),

      onStatus: Color(0xFFFFFFFF),
    ),

    dark: AlayaColorSet(
      surfaceBase: Color(0xFF141218),
      surfaceRaised: Color(0xFF1D1B20),
      surfaceOverlay: Color(0xFF26232B),
      surfaceSunken: Color(0xFF100E13),

      primary: Color(0xFFD0BCFF),
      onPrimary: Color(0xFF381E72),

      accent: Color(0xFFEFB8C8),
      onAccent: Color(0xFF492532),

      textPrimary: Color(0xFFE6E1E5),
      textSecondary: Color(0xFFCAC4D0),
      textMuted: Color(0xFF938F99),

      divider: Color(0xFF49454F),

      income: Color(0xFF6FCB9F),
      expense: Color(0xFFFFB4AB),
      transfer: Color(0xFFA9B7D0),

      warning: Color(0xFFE5C36A),
      danger: Color(0xFFFFB4AB),
      success: Color(0xFF6FCB9F),

      onStatus: Color(0xFF1C1B1F),
    ),
  );

  static const AlayaPalette nord = AlayaPalette(
    name: 'Nord',
    description:
        'Arctic blue-gray surfaces with frost blue and aurora accents.',
    light: AlayaColorSet(
      surfaceBase: Color(0xFFECEFF4),
      surfaceRaised: Color(0xFFF5F7FA),
      surfaceOverlay: Color(0xFFFFFFFF),
      surfaceSunken: Color(0xFFE5E9F0),

      primary: Color(0xFF5E81AC),
      onPrimary: Color(0xFFFFFFFF),

      accent: Color(0xFF88C0D0),
      onAccent: Color(0xFF16323A),

      textPrimary: Color(0xFF2E3440),
      textSecondary: Color(0xFF4C566A),
      textMuted: Color(0xFF7B8494),

      divider: Color(0xFFD8DEE9),

      income: Color(0xFFA3BE8C),
      expense: Color(0xFFBF616A),
      transfer: Color(0xFF81A1C1),

      warning: Color(0xFFEBCB8B),
      danger: Color(0xFFBF616A),
      success: Color(0xFFA3BE8C),

      onStatus: Color(0xFF2E3440),
    ),

    dark: AlayaColorSet(
      surfaceBase: Color(0xFF2E3440),
      surfaceRaised: Color(0xFF3B4252),
      surfaceOverlay: Color(0xFF434C5E),
      surfaceSunken: Color(0xFF242933),

      primary: Color(0xFF88C0D0),
      onPrimary: Color(0xFF24343A),

      accent: Color(0xFF81A1C1),
      onAccent: Color(0xFF17232E),

      textPrimary: Color(0xFFECEFF4),
      textSecondary: Color(0xFFD8DEE9),
      textMuted: Color(0xFF9AA5B5),

      divider: Color(0xFF4C566A),

      income: Color(0xFFA3BE8C),
      expense: Color(0xFFBF616A),
      transfer: Color(0xFF81A1C1),

      warning: Color(0xFFEBCB8B),
      danger: Color(0xFFBF616A),
      success: Color(0xFFA3BE8C),

      onStatus: Color(0xFF2E3440),
    ),
  );
}
```

### `lib/app/theme/semantic_colors.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/palettes/palette.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';

/// The app's semantic colours, reachable from any `BuildContext` (ARCH_3 §8).
///
/// A `ThemeExtension` rather than a set of top-level constants, because the palette can change at
/// runtime and a widget holding a `const` colour would not rebuild. Reached through
/// [AlayaSemanticColorsContext.semantic] on the context.
@immutable
class AlayaSemanticColors extends ThemeExtension<AlayaSemanticColors> {
  /// Creates the extension.
  const AlayaSemanticColors({
    required this.income,
    required this.expense,
    required this.transfer,
    required this.warning,
    required this.danger,
    required this.success,
    required this.muted,
    required this.onStatus,
    required this.surfaceBase,
    required this.surfaceRaised,
    required this.surfaceOverlay,
    required this.surfaceSunken,
  });

  /// Builds the extension from one mode of a palette.
  factory AlayaSemanticColors.fromColorSet(AlayaColorSet colors) =>
      AlayaSemanticColors(
        income: colors.income,
        expense: colors.expense,
        transfer: colors.transfer,
        warning: colors.warning,
        danger: colors.danger,
        success: colors.success,
        muted: colors.textMuted,
        onStatus: colors.onStatus,
        surfaceBase: colors.surfaceBase,
        surfaceRaised: colors.surfaceRaised,
        surfaceOverlay: colors.surfaceOverlay,
        surfaceSunken: colors.surfaceSunken,
      );

  /// Money arriving.
  final Color income;

  /// Money leaving.
  final Color expense;

  /// Money moving between the user's own accounts.
  final Color transfer;

  /// Something needs attention soon.
  final Color warning;

  /// Something is wrong or overdue.
  final Color danger;

  /// Something completed.
  final Color success;

  /// De-emphasised — and the colour a zero amount takes.
  final Color muted;

  /// Text and icons on a [warning], [danger] or [success] fill.
  final Color onStatus;

  /// Tier 0 — the screen.
  final Color surfaceBase;

  /// Tier 1 — a card.
  final Color surfaceRaised;

  /// Tier 2 — a sheet or dialog.
  final Color surfaceOverlay;

  /// Tier -1 — an inset well, such as a text field's fill.
  final Color surfaceSunken;

  /// **The red/green rule, implemented exactly once (ARCH_3 §8.1).**
  ///
  /// Every amount in the app takes its colour from this method and no other. That is what makes the
  /// convention uniform by construction rather than by 200 widgets each remembering it — and it is
  /// what makes the convention changeable, since inverting it for a user who reads red as auspicious
  /// is one edit here.
  ///
  /// Zero is [muted], not [income]. A zero amount has no direction, and colouring it green would
  /// assert something the number does not say.
  Color forAmount(Money amount) {
    if (amount.isZero) return muted;
    return amount.isNegative ? expense : income;
  }

  /// The colour for an amount belonging to a transaction of [kind].
  ///
  /// Delegates to [forAmount] for everything except a transfer, which is the one case the amount's
  /// sign cannot express: moving ₹5,000 between your own accounts is neither a gain nor a loss, but
  /// its leg is signed like any other. Colouring it green on the way in and red on the way out would
  /// make one movement of money look like income and expense at once.
  Color forTransactionKind(TransactionKind kind, Money amount) =>
      kind == TransactionKind.transfer ? transfer : forAmount(amount);

  /// The surface colour for [tier] 0 to 2, or -1 for a sunken well.
  Color surfaceForTier(int tier) => switch (tier) {
    -1 => surfaceSunken,
    0 => surfaceBase,
    1 => surfaceRaised,
    _ => surfaceOverlay,
  };

  /// Every semantic colour by name, so the Theme Lab enumerates them without a list to maintain.
  Map<String, Color> get byName => {
    'income': income,
    'expense': expense,
    'transfer': transfer,
    'warning': warning,
    'danger': danger,
    'success': success,
    'muted': muted,
    'surfaceBase': surfaceBase,
    'surfaceRaised': surfaceRaised,
    'surfaceOverlay': surfaceOverlay,
    'surfaceSunken': surfaceSunken,
  };

  @override
  AlayaSemanticColors copyWith({
    Color? income,
    Color? expense,
    Color? transfer,
    Color? warning,
    Color? danger,
    Color? success,
    Color? muted,
    Color? onStatus,
    Color? surfaceBase,
    Color? surfaceRaised,
    Color? surfaceOverlay,
    Color? surfaceSunken,
  }) => AlayaSemanticColors(
    income: income ?? this.income,
    expense: expense ?? this.expense,
    transfer: transfer ?? this.transfer,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    success: success ?? this.success,
    muted: muted ?? this.muted,
    onStatus: onStatus ?? this.onStatus,
    surfaceBase: surfaceBase ?? this.surfaceBase,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
    surfaceSunken: surfaceSunken ?? this.surfaceSunken,
  );

  @override
  AlayaSemanticColors lerp(AlayaSemanticColors? other, double t) {
    if (other == null) return this;
    return AlayaSemanticColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      transfer: Color.lerp(transfer, other.transfer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      onStatus: Color.lerp(onStatus, other.onStatus, t)!,
      surfaceBase: Color.lerp(surfaceBase, other.surfaceBase, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceOverlay: Color.lerp(surfaceOverlay, other.surfaceOverlay, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
    );
  }
}

/// Reaches [AlayaSemanticColors] from a `BuildContext`.
extension AlayaSemanticColorsContext on BuildContext {
  /// This context's semantic colours.
  ///
  /// Throws if the extension is absent, which can only happen inside a `MaterialApp` that is not
  /// `AlayaTheme`'s — a programming error worth failing loudly rather than silently falling back to
  /// Material defaults and shipping a screen whose amounts are the wrong colour.
  AlayaSemanticColors get semantic {
    final extension = Theme.of(this).extension<AlayaSemanticColors>();
    assert(
      extension != null,
      'AlayaSemanticColors is missing. Wrap this subtree in AlayaTheme.light or AlayaTheme.dark.',
    );
    return extension ?? AlayaSemanticColors.fromColorSet(_fallback);
  }
}

const AlayaColorSet _fallback = AlayaColorSet(
  surfaceBase: Color(0xFFF6F5F1),
  surfaceRaised: Color(0xFFFFFFFF),
  surfaceOverlay: Color(0xFFFFFFFF),
  surfaceSunken: Color(0xFFECEAE3),
  primary: Color(0xFF2A3A6B),
  onPrimary: Color(0xFFFFFFFF),
  accent: Color(0xFF9A6A1E),
  onAccent: Color(0xFFFFFFFF),
  textPrimary: Color(0xFF1B2033),
  textSecondary: Color(0xFF515873),
  textMuted: Color(0xFF868CA3),
  divider: Color(0xFFDDDAD1),
  income: Color(0xFF2E7D5B),
  expense: Color(0xFF9E2A2B),
  transfer: Color(0xFF4A5578),
  warning: Color(0xFF9A6A1E),
  danger: Color(0xFF9E2A2B),
  success: Color(0xFF2E7D5B),
  onStatus: Color(0xFFFFFFFF),
);
```

### `lib/app/theme/tokens/alaya_durations.dart`

```dart
/// The animation duration scale (ARCH_3 §8).
///
/// Four values, and no widget writes its own. The figures are the ones ARCH_3 §8 specifies, and the
/// reason they are short is that this app is used in twenty-second bursts — logging a purchase at a
/// till. An animation the user waits through is a cost, not polish.
abstract final class AlayaDurations {
  /// 120 ms — a colour change, a check mark, a ripple settling.
  static const Duration fast = Duration(milliseconds: 120);

  /// 220 ms — the default. An expanding card, a chip toggling, a sheet's content settling.
  static const Duration base = Duration(milliseconds: 220);

  /// 380 ms — the expandable FAB unfolding, a large surface reflowing.
  static const Duration slow = Duration(milliseconds: 380);

  /// 90 ms — one leg of the error shake, which is four legs plus a settle.
  static const Duration shakeLeg = Duration(milliseconds: 90);

  /// 2.5 s — how long a snack bar stays.
  static const Duration snack = Duration(milliseconds: 2500);

  /// 300 ms — how long a search field waits after the last keystroke before querying.
  ///
  /// An interaction delay rather than an animation, and it sits here because Law U6 says every
  /// duration in a widget comes from a token — so the token file has to hold every duration a widget
  /// needs. It is deliberately longer than [base]: a debounce tuned to an animation scale fires
  /// mid-word and makes typing feel like it is fighting the field.
  ///
  /// A **network** timeout still does not belong here. That scale is seconds and lives with the
  /// client that owns the call (see `infrastructure_providers.dart`).
  static const Duration debounce = Duration(milliseconds: 300);
}
```

### `lib/app/theme/tokens/alaya_elevation.dart`

```dart
import 'package:flutter/widgets.dart';

/// The elevation scale (ARCH_3 §8).
///
/// Expressed as shadow lists rather than Material `elevation` doubles, because the same numeric
/// elevation reads very differently against a light and a dark surface — and in dark mode a
/// shadow is nearly invisible, so depth has to come from surface tiers instead. `AlayaTheme`
/// selects between [light] and [dark] accordingly, which is why both live here.
///
/// **The hex literals below are the one intentional exception to "no hex colours outside the
/// palette", and they are not palette colours.** A shadow is occlusion — light that a raised
/// surface blocked — so it is always neutral black and only its opacity changes. Deriving it from
/// the palette would tint the shadow, which is a different visual effect (a coloured glow) and one
/// no preset here asks for. The values are alpha steps, and the palette has no say in them.
abstract final class AlayaElevation {
  /// Flat. A surface that sits directly on its parent.
  static const List<BoxShadow> none = [];

  /// A card at rest, on a light background.
  static const List<BoxShadow> lightRaised = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 3)),
  ];

  /// A pressed or dragged card, a menu, on a light background.
  static const List<BoxShadow> lightFloating = [
    BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x0F000000), blurRadius: 18, offset: Offset(0, 8)),
  ];

  /// A sheet or dialog, on a light background.
  static const List<BoxShadow> lightOverlay = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, -4)),
  ];

  /// A card at rest, on a dark background.
  ///
  /// Darker and tighter than its light counterpart. A soft black shadow on a near-black surface is
  /// invisible, so the shadow's job in dark mode is only to separate an edge, and the sense of
  /// height comes from the palette's surface tiers.
  static const List<BoxShadow> darkRaised = [
    BoxShadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1)),
  ];

  /// A pressed or dragged card, on a dark background.
  static const List<BoxShadow> darkFloating = [
    BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 3)),
  ];

  /// A sheet or dialog, on a dark background.
  static const List<BoxShadow> darkOverlay = [
    BoxShadow(color: Color(0x59000000), blurRadius: 20, offset: Offset(0, -2)),
  ];

  /// The raised shadow for [isDark].
  static List<BoxShadow> raised({required bool isDark}) =>
      isDark ? darkRaised : lightRaised;

  /// The floating shadow for [isDark].
  static List<BoxShadow> floating({required bool isDark}) =>
      isDark ? darkFloating : lightFloating;

  /// The overlay shadow for [isDark].
  static List<BoxShadow> overlay({required bool isDark}) =>
      isDark ? darkOverlay : lightOverlay;
}
```

### `lib/app/theme/tokens/alaya_icon_size.dart`

```dart
/// The icon size scale (ARCH_5 §2.7) — the last literal class the token rules did not cover.
///
/// Phase 5 shipped 18, 20, 22 and 40 as raw numbers across six files (ARCH_4 A52). Four steps is
/// enough for every icon in the app, and having exactly four is what stops a fifth appearing.
abstract final class AlayaIconSize {
  /// 16 — inline with `caption` or `overline` text: a chip's dismiss, a status glyph.
  static const double sm = 16;

  /// 20 — the default. List-row leading icons, field affixes, app-bar actions.
  static const double md = 20;

  /// 24 — a primary action's icon, a FAB, a drawer destination.
  static const double lg = 24;

  /// 40 — the single illustrative icon on an empty or error state.
  static const double xl = 40;
}
```

### `lib/app/theme/tokens/alaya_radii.dart`

```dart
import 'package:flutter/widgets.dart';

/// The corner-radius scale (ARCH_3 §8).
///
/// Four steps, deliberately shallow. A finance app is read in columns, and a heavily rounded card
/// fights the vertical alignment that makes a column of amounts scannable — so the radius is enough
/// to soften a surface and not enough to make it feel like a separate object floating away.
abstract final class AlayaRadii {
  /// 4 — chips, tags, small inline surfaces.
  static const double xs = 4;

  /// 8 — inputs, buttons.
  static const double sm = 8;

  /// 12 — cards, sheets' inner surfaces. The default.
  static const double md = 12;

  /// 20 — bottom sheets and dialogs, where the corner is a large visible arc.
  static const double lg = 20;

  /// A fully round shape, for avatars and the expandable FAB's collapsed state.
  static const double full = 999;

  /// [xs] as a [BorderRadius].
  static const BorderRadius borderXs = BorderRadius.all(Radius.circular(xs));

  /// [sm] as a [BorderRadius].
  static const BorderRadius borderSm = BorderRadius.all(Radius.circular(sm));

  /// [md] as a [BorderRadius].
  static const BorderRadius borderMd = BorderRadius.all(Radius.circular(md));

  /// [lg] as a [BorderRadius].
  static const BorderRadius borderLg = BorderRadius.all(Radius.circular(lg));

  /// A sheet's top-only radius, since its bottom edge meets the screen.
  static const BorderRadius sheetTop = BorderRadius.only(
    topLeft: Radius.circular(lg),
    topRight: Radius.circular(lg),
  );
}
```

### `lib/app/theme/tokens/alaya_spacing.dart`

```dart
/// The spacing scale (ARCH_3 §8) — the only source of padding and gap values in the app.
///
/// Eight steps on a 4-point grid. A widget writing `EdgeInsets.all(13)` is a bug, not a preference:
/// once one exists, nothing keeps the next screen's rhythm consistent with this one.
///
/// The names are sizes rather than roles (`md`, not `cardPadding`) because a role-named scale
/// invites a ninth value the moment a role appears that does not fit — and then the grid is gone.
abstract final class AlayaSpacing {
  /// 4 — hairline separation, icon-to-label.
  static const double xxs = 4;

  /// 8 — inside a chip, between stacked labels.
  static const double xs = 8;

  /// 12 — between related rows.
  static const double sm = 12;

  /// 16 — the default. Card padding, screen margin.
  static const double md = 16;

  /// 20 — a slightly generous card.
  static const double lg = 20;

  /// 24 — between sections.
  static const double xl = 24;

  /// 32 — around a section header.
  static const double xxl = 32;

  /// 48 — empty-state breathing room, above a primary action.
  static const double xxxl = 48;

  /// The screen edge margin, named because it must not drift between screens.
  static const double screenEdge = md;

  /// The minimum tap target, per Material's accessibility floor.
  ///
  /// Not a spacing value so much as a constraint, but it belongs on the scale because every
  /// icon-button-sized widget in the app needs to reach it and there must be one number to reach.
  static const double minTapTarget = 48;
}
```

### `lib/app/theme/tokens/alaya_typography.dart`

```dart
import 'dart:ui' show FontFeature;

import 'package:flutter/widgets.dart';

/// The type scale (ARCH_3 §8) — one scale, semantic names, no colours.
///
/// Every style here is colourless on purpose. Colour arrives from the palette through
/// `AlayaTheme`, so a widget that needs a warning-coloured label composes
/// `AlayaTypography.label.copyWith(color: semantic.warning)` rather than reaching for a second
/// style that happens to be the right colour. One axis per token.
///
/// **The scale carries this app's personality, because no custom font can.** Bundling a display
/// face needs either a font package or assets declared under `android/`, and this phase may do
/// neither — so the character comes from weight, size and figure treatment instead. That turns out
/// to suit the subject: a household ledger is read in columns, and what makes a column legible is
/// that the digits line up, not that the headings are expressive.
abstract final class AlayaTypography {
  /// Amounts and any figure that appears in a column.
  ///
  /// **Tabular figures are the one deliberate typographic risk in this design.** By default most
  /// fonts render proportional digits, so `1` is narrower than `8` and a column of amounts jitters
  /// left and right as the values change. `FontFeature.tabularFigures()` forces every digit to the
  /// same advance width, so a ledger column aligns on the decimal without a monospace font — and
  /// with Indian grouping (`2,50,000`) that matters more than usual, because the group widths differ
  /// from Western grouping and the eye has fewer landmarks.
  static const List<FontFeature> figures = [FontFeature.tabularFigures()];

  /// Slashed zero, where a zero could be misread as an O — account numbers, recovery codes.
  static const List<FontFeature> slashedZero = [
    FontFeature.tabularFigures(),
    FontFeature.slashedZero(),
  ];

  /// The dashboard's headline figure. One per screen, at most.
  static const TextStyle displayAmount = TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w300,
    height: 1.1,
    // Negative tracking at display size: default tracking is set for body text and looks loose
    // once the glyphs are this large.
    letterSpacing: -1.2,
    fontFeatures: figures,
  );

  /// A card's primary amount.
  static const TextStyle amountLarge = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w500,
    height: 1.2,
    letterSpacing: -0.4,
    fontFeatures: figures,
  );

  /// A ledger row's amount. The most-rendered style in the app.
  static const TextStyle amountMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.25,
    letterSpacing: -0.1,
    fontFeatures: figures,
  );

  /// A secondary or converted amount, shown beneath the original.
  static const TextStyle amountSmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.3,
    fontFeatures: figures,
  );

  /// A quantity, which is a figure and so shares the tabular treatment.
  static const TextStyle quantity = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.3,
    fontFeatures: figures,
  );

  /// An app-bar or screen title.
  static const TextStyle screenTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: -0.2,
  );

  /// A section header inside a scrolling screen.
  static const TextStyle sectionHeader = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.2,
    // Positive tracking and upper case in the widget: at this size a header needs to read as a
    // label rather than as small body text, and tracking does that without another weight.
    letterSpacing: 0.8,
  );

  /// A card's title.
  static const TextStyle cardTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// Default running text.
  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  /// Running text that needs emphasis without becoming a heading.
  static const TextStyle bodyEmphasis = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.45,
  );

  /// A form field's label.
  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  /// Metadata — a date, an account name beneath a title, a unit suffix.
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  /// A small eyebrow above a section, and a chip's text.
  static const TextStyle overline = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.6,
  );

  /// A button's label.
  static const TextStyle button = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.1,
  );

  /// Every style, for the Theme Lab to enumerate without a hand-maintained list going stale.
  static const Map<String, TextStyle> all = {
    'displayAmount': displayAmount,
    'amountLarge': amountLarge,
    'amountMedium': amountMedium,
    'amountSmall': amountSmall,
    'quantity': quantity,
    'screenTitle': screenTitle,
    'sectionHeader': sectionHeader,
    'cardTitle': cardTitle,
    'body': body,
    'bodyEmphasis': bodyEmphasis,
    'label': label,
    'caption': caption,
    'overline': overline,
    'button': button,
  };
}
```

### `lib/main.dart`

```dart
import 'package:alaya/app/bootstrap.dart';

/// The Android entry point.
///
/// Deliberately empty of logic. Everything that could fail — opening the database, building the
/// provider graph — lives in `bootstrap` where it can be exercised by a test without a platform
/// binding hard-coded into `main`.
///
/// Returns the future rather than dropping it: a discarded future's error goes nowhere, so a failure
/// to open the database would present as a blank screen with nothing in the log naming the cause.
Future<void> main() => bootstrap();
```
