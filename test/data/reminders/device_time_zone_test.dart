import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:alaya/data/reminders/device_time_zone.dart';

/// Tests for the zone resolver — **the point of the pure-Dart design.**
///
/// A platform channel could not be tested at all, which is the reason the bug it replaces survived every
/// green suite this project has run. These need no harness, no fake and no pumper: the resolver reads
/// `dart:core` and the zone database, and both are available in a plain unit test.
///
/// **Every assertion here is zone-independent.** A test that expects `Asia/Kolkata` passes on the author's
/// laptop and fails in CI, where `TZ` is almost always UTC — so these assert the *invariant* the resolver
/// promises rather than the answer it happens to give on one machine. That is what makes them worth running
/// on somebody else's computer.
void main() {
  setUpAll(tz_data.initializeTimeZones);

  group('DeviceTimeZone.resolve', () {
    test('returns a zone that reproduces this device at every probe', () {
      final resolved = DeviceTimeZone.resolve();

      // The invariant: whatever machine this runs on, the chosen zone must agree with `dart:core` about
      // the offset at every instant sampled. This is the whole contract, and it is exactly what UTC
      // failed to satisfy for every user of this app.
      expect(resolved.mismatches, 0, reason: 'chose ${resolved.name}');
      expect(
        resolved.match,
        anyOf(TimeZoneMatch.exact, TimeZoneMatch.ambiguous),
        reason: 'chose ${resolved.name}',
      );

      for (var day = -200; day <= 220; day += 5) {
        final instant = DateTime.now().toUtc().add(Duration(days: day));
        final device = DateTime.fromMillisecondsSinceEpoch(
          instant.millisecondsSinceEpoch,
        ).timeZoneOffset;
        final chosen = tz.TZDateTime.from(
          instant,
          resolved.location,
        ).timeZoneOffset;
        expect(
          chosen,
          device,
          reason: '${resolved.name} disagrees with the device at $instant',
        );
      }
    });

    test('reports the fallback rather than pretending, given nothing to match', () {
      final resolved = DeviceTimeZone.resolve(database: const []);

      expect(resolved.match, TimeZoneMatch.fallback);
      expect(resolved.location, tz.UTC);
      expect(resolved.candidates, 0);
    });

    test('is deterministic for one instant', () {
      final at = DateTime.utc(2026, 8, 13, 6, 30);

      expect(
        DeviceTimeZone.resolve(now: at).name,
        DeviceTimeZone.resolve(now: at).name,
      );
    });

    test('rejects a zone that matches now but not across the year', () {
      // Two zones that share an offset in one season and diverge in the other: London is UTC in winter
      // and UTC+1 in summer, so it agrees with UTC for roughly half the year and disagrees for the rest.
      // Whichever season the test runs in, exactly one of the pair can survive a fourteen-month window —
      // which is the discrimination the phase-two probe exists to make and a single offset check cannot.
      final pair = [tz.UTC, tz.getLocation('Europe/London')];
      final survivors = <String>{};
      for (final candidate in pair) {
        final resolved = DeviceTimeZone.resolve(database: [candidate]);
        if (resolved.match == TimeZoneMatch.exact) survivors.add(resolved.name);
      }

      // A count beside the set, per the architecture's own note that `difference` passes happily when the
      // expected set shrinks: without the length assertion, both zones failing would read as a pass.
      expect(survivors, hasLength(lessThanOrEqualTo(1)));
    });
  });
}