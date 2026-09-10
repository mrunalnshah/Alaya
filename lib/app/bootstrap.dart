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
