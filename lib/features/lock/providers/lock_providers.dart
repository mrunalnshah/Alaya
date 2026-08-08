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

/// Whether a lock was configured when the app started.
///
/// **Overridden by `bootstrap()` with an awaited answer, which is what removes the race.** Reading secure storage
/// is asynchronous, so a `Notifier` that starts at [LockPhase.unknown] and resolves a frame later forces the
/// router to guess — and either guess is wrong for somebody. Guessing "locked" showed a lock screen to a fresh
/// install that had no PIN and no way past it; guessing "open" would flash the dashboard, balances included, at
/// somebody who does.
///
/// One awaited read before `runApp` costs a few milliseconds and removes the question.
final lockConfiguredAtStartupProvider = Provider<bool>((ref) {
  throw StateError(
    'lockConfiguredAtStartupProvider was not overridden. bootstrap() must supply it — see '
    'lib/app/bootstrap.dart. A widget test supplies false.',
  );
});

/// Whether the app is locked, and the one place that changes.
final lockPhaseProvider = NotifierProvider<LockNotifier, LockPhase>(
  LockNotifier.new,
);

/// Holds the lock phase and the three transitions it has.
class LockNotifier extends Notifier<LockPhase> {
  @override
  LockPhase build() {
    // **Synchronous, from a value `bootstrap()` already awaited.** No `unknown`, so the router never redirects on
    // a guess. `refresh()` remains for later changes — a lock enabled or removed in Settings.
    return ref.read(lockConfiguredAtStartupProvider)
        ? LockPhase.locked
        : LockPhase.open;
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
  final stored = await ref
      .watch(settingsRepositoryProvider)
      .readValue(autoEraseSettingKey);
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
