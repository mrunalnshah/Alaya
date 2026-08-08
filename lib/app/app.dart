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
