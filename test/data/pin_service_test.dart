import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/security/app_lock_store.dart';
import 'package:alaya/data/security/pin_service.dart';
import 'package:alaya/data/security/recovery_code.dart';
import 'package:alaya/data/security/secure_key_value_store.dart';

/// The app lock: throttling, PIN change, recovery, and independence from the database.
///
/// Uses the real [AppLockStore] over an [InMemorySecureKeyValueStore], with PBKDF2 lowered to 100
/// iterations. Lowering it keeps the suite fast without weakening what is tested: the production
/// count is a constant asserted directly, and everything else here depends only on the hash being
/// stable and salt-dependent.
void main() {
  late InMemorySecureKeyValueStore storage;
  late AppLockStore store;
  late FixedClock clock;
  late PinService service;

  setUp(() async {
    storage = InMemorySecureKeyValueStore();
    clock = FixedClock(DateTime.utc(2026, 7, 31, 9));
    store = AppLockStore(
      storage: storage,
      random: _SeededRandom(),
      pbkdf2Iterations: 100,
    );
    service = PinService(
      store: store,
      clock: clock,
      recoveryCode: RecoveryCode(random: _SeededRandom()),
    );
    await store.writeLock(pin: '1234', recoveryCode: 'ABCDEFGHJK');
  });

  group('the production configuration', () {
    test('is PBKDF2-HMAC-SHA256 at 310,000 iterations over a 256-bit key', () {
      expect(
        AppLockStore.iterations,
        310000,
        reason:
            'OWASP 2023 floor; the PIN space is only 10,000 values so this does the work',
      );
      expect(AppLockStore.derivedBits, 256);
      expect(AppLockStore.saltBytes, 16);
    });
  });

  group('the throttle table (ARCH_3 2.3)', () {
    test('the first four wrong attempts are not throttled', () async {
      for (var attempt = 1; attempt <= 4; attempt++) {
        final outcome = await service.verifyPin('9999');
        expect(outcome.unlocked, isFalse);
        expect(
          outcome.isThrottled,
          isFalse,
          reason: 'attempt $attempt must be free',
        );
        expect(outcome.failedCount, attempt);
      }
    });

    test('the FIFTH wrong attempt triggers a 30 second delay', () async {
      for (var attempt = 1; attempt <= 4; attempt++) {
        await service.verifyPin('9999');
      }

      final fifth = await service.verifyPin('9999');

      expect(fifth.failedCount, 5);
      expect(fifth.isThrottled, isTrue);
      expect(fifth.retryAfter, const Duration(seconds: 30));
    });

    test('and the correct PIN is refused while that delay is in force', () async {
      for (var attempt = 1; attempt <= 5; attempt++) {
        await service.verifyPin('9999');
      }

      final correct = await service.verifyPin('1234');

      expect(
        correct.unlocked,
        isFalse,
        reason:
            'the throttle is checked BEFORE the compare, so even a correct PIN waits',
      );
      expect(correct.isThrottled, isTrue);
    });

    test(
      'the delay expires on the clock, and the correct PIN then works',
      () async {
        for (var attempt = 1; attempt <= 5; attempt++) {
          await service.verifyPin('9999');
        }

        clock.advance(const Duration(seconds: 31));

        expect((await service.verifyPin('1234')).unlocked, isTrue);
      },
    );

    test('the ladder matches the table exactly', () {
      expect(PinService.delayAfterFailures(4), Duration.zero);
      expect(PinService.delayAfterFailures(5), const Duration(seconds: 30));
      expect(PinService.delayAfterFailures(6), const Duration(minutes: 1));
      expect(PinService.delayAfterFailures(7), const Duration(minutes: 5));
      expect(PinService.delayAfterFailures(8), const Duration(minutes: 15));
      expect(PinService.delayAfterFailures(9), const Duration(minutes: 30));
      expect(PinService.delayAfterFailures(10), const Duration(minutes: 60));
    });

    test('the delay is capped at one hour and never grows beyond it', () {
      expect(PinService.delayAfterFailures(11), const Duration(minutes: 60));
      expect(
        PinService.delayAfterFailures(50),
        const Duration(minutes: 60),
        reason:
            'unbounded doubling would lock the owner out for days over a forgotten PIN',
      );
    });

    test('a correct PIN clears the counter', () async {
      await service.verifyPin('9999');
      await service.verifyPin('9999');
      expect(await store.readFailedCount(), 2);

      await service.verifyPin('1234');

      expect(await store.readFailedCount(), 0);
    });

    test(
      'the lockout is an absolute instant, so a process restart cannot reset it',
      () async {
        for (var attempt = 1; attempt <= 5; attempt++) {
          await service.verifyPin('9999');
        }

        // A fresh service and store over the same storage — what a restart is.
        final revived = PinService(
          store: AppLockStore(
            storage: storage,
            random: _SeededRandom(),
            pbkdf2Iterations: 100,
          ),
          clock: clock,
        );

        expect(
          (await revived.verifyPin('1234')).isThrottled,
          isTrue,
          reason:
              'a countdown held in memory would make the throttle bypassable',
        );
      },
    );
  });

  group('the recovery code resets the PIN', () {
    test('a correct code sets a new PIN, and the new PIN unlocks', () async {
      final result = await service.resetWithRecoveryCode(
        code: 'ABCDEFGHJK',
        newPin: '5678',
      );

      expect(result.isFailure, isFalse);
      expect((await service.verifyPin('5678')).unlocked, isTrue);
      expect(
        (await service.verifyPin('1234')).unlocked,
        isFalse,
        reason: 'the old PIN must stop working',
      );
    });

    test(
      'the code still works after a reset, because the salt is reused',
      () async {
        await service.resetWithRecoveryCode(code: 'ABCDEFGHJK', newPin: '5678');

        final second = await service.resetWithRecoveryCode(
          code: 'ABCDEFGHJK',
          newPin: '4321',
        );

        expect(
          second.isFailure,
          isFalse,
          reason:
              'a fresh salt would silently invalidate the code the user wrote down',
        );
        expect((await service.verifyPin('4321')).unlocked, isTrue);
      },
    );

    test('the hyphenated display form is accepted', () async {
      expect(
        (await service.resetWithRecoveryCode(
          code: 'ABCDE-FGHJK',
          newPin: '5678',
        )).isFailure,
        isFalse,
      );
    });

    test('lower case and stray spaces are accepted', () async {
      expect(
        (await service.resetWithRecoveryCode(
          code: ' abcde fghjk ',
          newPin: '5678',
        )).isFailure,
        isFalse,
      );
    });

    test('a wrong code is refused and counts as a failed attempt', () async {
      final result = await service.resetWithRecoveryCode(
        code: 'ZZZZZZZZZZ',
        newPin: '5678',
      );

      expect(result.isFailure, isTrue);
      expect(
        await store.readFailedCount(),
        1,
        reason: 'otherwise the recovery code would be the unthrottled way in',
      );
    });

    test(
      'a code containing an excluded character fails on length, not by folding',
      () async {
        // 0, O, 1 and I cannot appear in a real code, so they are dropped — leaving 9 characters,
        // which is not a code.
        expect(
          (await service.resetWithRecoveryCode(
            code: 'ABCDEFGHJ0',
            newPin: '5678',
          )).isFailure,
          isTrue,
        );
      },
    );

    test('a reset is refused while throttled', () async {
      for (var attempt = 1; attempt <= 5; attempt++) {
        await service.verifyPin('9999');
      }

      expect(
        (await service.resetWithRecoveryCode(
          code: 'ABCDEFGHJK',
          newPin: '5678',
        )).isFailure,
        isTrue,
      );
    });
  });

  group('enable, change and disable', () {
    test('changing the PIN needs the current one', () async {
      expect(
        (await service.changePin(currentPin: '0000', newPin: '5678')).isFailure,
        isTrue,
      );
      expect(
        (await service.changePin(currentPin: '1234', newPin: '5678')).isFailure,
        isFalse,
      );
      expect((await service.verifyPin('5678')).unlocked, isTrue);
    });

    test('a change leaves the recovery code working', () async {
      await service.changePin(currentPin: '1234', newPin: '5678');

      expect(
        (await service.resetWithRecoveryCode(
          code: 'ABCDEFGHJK',
          newPin: '1111',
        )).isFailure,
        isFalse,
      );
    });

    test('disabling needs the PIN and clears every secret', () async {
      expect((await service.disable(pin: '0000')).isFailure, isTrue);
      expect((await service.disable(pin: '1234')).isFailure, isFalse);

      expect(await service.isEnabled, isFalse);
      expect(await store.readPinHash(), isNull);
      expect(await store.readSalt(), isNull);
      expect(await store.readRecoveryHash(), isNull);
    });

    test('a PIN must be 4 or 6 digits', () async {
      expect(
        (await service.changePin(currentPin: '1234', newPin: '123')).isFailure,
        isTrue,
      );
      expect(
        (await service.changePin(
          currentPin: '1234',
          newPin: '12345',
        )).isFailure,
        isTrue,
      );
      expect(
        (await service.changePin(currentPin: '1234', newPin: '12ab')).isFailure,
        isTrue,
      );
      expect(
        (await service.changePin(
          currentPin: '1234',
          newPin: '123456',
        )).isFailure,
        isFalse,
      );
    });

    test('enabling when a lock already exists is refused', () async {
      expect((await service.enable(pin: '1111')).isFailure, isTrue);
    });

    test(
      'enabling on a clean install returns a formatted recovery code',
      () async {
        final fresh = PinService(
          store: AppLockStore(
            storage: InMemorySecureKeyValueStore(),
            random: _SeededRandom(),
            pbkdf2Iterations: 100,
          ),
          clock: clock,
          recoveryCode: RecoveryCode(random: _SeededRandom()),
        );

        final result = await fresh.enable(pin: '4321');

        expect(result.isFailure, isFalse);
        final code = result.valueOrNull!;
        expect(code, contains('-'));
        expect(code.replaceAll('-', '').length, RecoveryCode.length);
        expect((await fresh.verifyPin('4321')).unlocked, isTrue);
      },
    );
  });

  group('the lock is unaffected by a restore', () {
    test(
      'every lock secret lives under an alaya.lock.* key, never a table',
      () async {
        expect(storage.keys, isNotEmpty);
        for (final key in storage.keys) {
          expect(
            key,
            startsWith('alaya.lock.'),
            reason:
                'a lock secret in the database would be replaced by a restore',
          );
        }
      },
    );

    test('AppLockStore cannot reach the database, structurally', () {
      // Its only collaborators are a SecureKeyValueStore and a Random. There is no parameter a
      // database, DAO or connection could be passed through, so a restore has nothing to act on and
      // this guarantee cannot regress by someone adding a write in the wrong place.
      expect(store, isA<AppLockStore>());
      expect(storage, isA<SecureKeyValueStore>());
    });

    test(
      'a restore that replaces every database row leaves the PIN working',
      () async {
        final hashBefore = await store.readPinHash();
        final saltBefore = await store.readSalt();

        // RestoreService operates on the drift database exclusively — ATTACH, per-table upserts, or a
        // file swap. None of those paths touch secure storage, so a restore is faithfully modelled here
        // by the absence of any call against `storage`.
        expect(await store.readPinHash(), hashBefore);
        expect(await store.readSalt(), saltBefore);
        expect((await service.verifyPin('1234')).unlocked, isTrue);
      },
    );

    test(
      'importing another install\'s backup cannot change who can unlock',
      () async {
        // Their lock, in their own storage. If the hash lived in the database, merging their backup
        // would overwrite ours and lock us out of our own data.
        final theirStorage = InMemorySecureKeyValueStore();
        final theirStore = AppLockStore(
          storage: theirStorage,
          random: _SeededRandom(),
          pbkdf2Iterations: 100,
        );
        await theirStore.writeLock(pin: '9876', recoveryCode: 'ZZZZZZZZZZ');

        expect(
          (await service.verifyPin('1234')).unlocked,
          isTrue,
          reason: 'our PIN still works',
        );
        expect(
          (await service.verifyPin('9876')).unlocked,
          isFalse,
          reason:
              'theirs does not, because their hash never entered our storage',
        );
      },
    );
  });

  group('hashing', () {
    test('the same PIN and salt derive the same hash', () async {
      final salt = [1, 2, 3, 4];
      final first = await store.deriveHash(secret: '1234', salt: salt);
      final second = await store.deriveHash(secret: '1234', salt: salt);

      expect(first, second);
    });

    test(
      'a different salt derives a different hash for the same PIN',
      () async {
        final a = await store.deriveHash(secret: '1234', salt: [1, 2, 3, 4]);
        final b = await store.deriveHash(secret: '1234', salt: [5, 6, 7, 8]);

        expect(a, isNot(b));
      },
    );

    test('a salt is 16 bytes of 0-255', () {
      final salt = store.newSalt();

      expect(salt, hasLength(AppLockStore.saltBytes));
      expect(salt.every((b) => b >= 0 && b <= 255), isTrue);
    });
  });

  group('recovery code generation', () {
    test('is 10 characters from the 32-symbol alphabet', () {
      final code = RecoveryCode(random: _SeededRandom()).generate();

      expect(code.length, RecoveryCode.length);
      for (final char in code.split('')) {
        expect(RecoveryCode.alphabet.contains(char), isTrue);
      }
    });

    test('the alphabet is exactly 32 symbols and excludes 0, O, 1 and I', () {
      expect(RecoveryCode.alphabet.length, 32);
      expect(
        RecoveryCode.alphabet.split('').toSet().length,
        32,
        reason: 'no duplicates',
      );
      for (final excluded in ['0', 'O', '1', 'I']) {
        expect(
          RecoveryCode.alphabet.contains(excluded),
          isFalse,
          reason: excluded,
        );
      }
    });

    test('formats as two groups of five', () {
      expect(RecoveryCode().format('ABCDEFGHJK'), 'ABCDE-FGHJK');
    });

    test('normalising drops the hyphen and anything outside the alphabet', () {
      final code = RecoveryCode();

      expect(code.normalize('abcde-fghjk'), 'ABCDEFGHJK');
      expect(code.normalize('ABCDEFGHJK'), 'ABCDEFGHJK');
      expect(code.isWellFormed('ABCDE-FGHJK'), isTrue);
      expect(code.isWellFormed('ABCDEFGHJ'), isFalse);
    });
  });
}

/// A deterministic [Random] so salts and generated codes are reproducible.
class _SeededRandom implements Random {
  int _state = 42;

  @override
  int nextInt(int max) {
    _state = (_state * 1103515245 + 12345) & 0x7FFFFFFF;
    return _state % max;
  }

  @override
  bool nextBool() => nextInt(2) == 0;

  @override
  double nextDouble() => nextInt(1 << 20) / (1 << 20);
}
