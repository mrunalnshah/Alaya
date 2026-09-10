import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/features/lock/presentation/screens/lock_screen.dart';
import 'package:alaya/features/lock/presentation/widgets/pin_pad.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

import '../../support/settings_harness.dart';

/// `LockScreen` — archetype A's shape, all four states (Law U4, ARCH_5 §9.1).
///
/// **These tests exist only because `AppLock` is an interface.** `PinService` is `final class` and reaches
/// `flutter_secure_storage`, so there was no way to fake it and no way to run a platform channel here — the
/// contract is what makes the §9.1 gate reachable at all.
void main() {
  group('the four states', () {
    testWidgets('loading shows the keypad and no refusal', (tester) async {
      // The screen has no spinner: it is usable the instant it mounts, and the PIN length arriving a frame later
      // changes the dot count rather than gating the keys.
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(lock: FakeAppLock(enabled: true)),
      );
      expect(find.byType(PinKeypad), findsOneWidget);
      expect(find.text('That PIN is not right.'), findsNothing);
    });

    testWidgets('populated draws one dot per configured digit', (tester) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(
          lock: FakeAppLock(enabled: true, pinLength: 6),
        ),
      );
      await tester.pumpAndSettle();
      // Six, not four. `readPinLength` was added to the port for exactly this — a six-digit PIN entered into four
      // boxes is a confusing failure rather than a wrong one.
      final dots = tester.widget<PinDots>(find.byType(PinDots));
      expect(dots.length, 6);
    });

    testWidgets('a wrong PIN shakes, clears, and says so', (tester) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(
          lock: FakeAppLock(enabled: true, correctPin: '9999'),
        ),
      );
      await tester.pumpAndSettle();
      final before = tester
          .widget<ShakeOnError>(find.byType(ShakeOnError))
          .trigger;

      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('That PIN is not right.'), findsOneWidget);
      // The trigger increments, so two failures in a row shake twice rather than once (ARCH_5 §2.6).
      expect(
        tester.widget<ShakeOnError>(find.byType(ShakeOnError)).trigger,
        greaterThan(before),
      );
      // Cleared, so the next attempt starts empty rather than making the user delete four digits they already
      // know are wrong.
      expect(tester.widget<PinDots>(find.byType(PinDots)).filled, 0);
    });

    testWidgets('a throttle states a duration and refuses taps', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(
          lock: FakeAppLock(
            enabled: true,
            lockout: const Duration(seconds: 65),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // `m:ss` for anything past a minute, formatted in Dart because a plural on "second" cannot express 1:05.
      expect(find.textContaining('1:05'), findsOneWidget);
      expect(find.textContaining('The wait gets longer'), findsOneWidget);

      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();
      // Still nothing entered: a throttled keypad accepts no digits, so the delay cannot be spent guessing.
      expect(tester.widget<PinDots>(find.byType(PinDots)).filled, 0);
    });
  });

  group('the honest copy', () {
    testWidgets('says it does not encrypt, and shows no padlock', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(lock: FakeAppLock(enabled: true)),
      );
      await tester.pumpAndSettle();

      // **ARCH_3 §2.5, asserted rather than trusted.** This is the one string in the app whose absence would be a
      // Play listing risk as well as a lie, so the test names the phrase rather than the key.
      expect(find.textContaining('does not encrypt your data'), findsOneWidget);
      // No padlock: a closed padlock is the universal icon for encryption and would undo the sentence beside it.
      expect(find.byIcon(Icons.lock), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(find.textContaining('bank-grade'), findsNothing);
      expect(find.textContaining('military'), findsNothing);
    });
  });

  group('the biometric shortcut', () {
    testWidgets('is absent, not disabled, where the device has none', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(
          lock: FakeAppLock(enabled: true),
          biometric: FakeBiometricGate(),
        ),
      );
      await tester.pumpAndSettle();
      // A disabled control that can never become enabled is the dead affordance ARCH_5 §10 objects to.
      expect(find.byIcon(Icons.fingerprint), findsNothing);
    });

    testWidgets('appears where the device has one', (tester) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(
          lock: FakeAppLock(enabled: true),
          biometric: FakeBiometricGate(available: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.fingerprint), findsOneWidget);
    });
  });

  group('the gate', () {
    testWidgets('renders at 320x640 with a doubled text scale', (tester) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(
          lock: FakeAppLock(enabled: true, pinLength: 6),
        ),
        textScale: 2,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('every target is large enough and named', (tester) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(
          lock: FakeAppLock(enabled: true),
          biometric: FakeBiometricGate(available: true),
        ),
      );
      await tester.pumpAndSettle();
      // The keypad is why this passes without special pleading: every key is a labelled 48dp target, which the
      // system keyboard could not have guaranteed.
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  });
}
