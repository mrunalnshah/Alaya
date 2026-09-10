/// Resolves the device's own IANA time zone in pure Dart, with no platform channel.
///
/// **Why this file exists.** `initializeTimeZones()` loads the zone database; it does not choose a zone.
/// `tz.local` stays UTC until something calls `setLocalLocation`, and nothing ever did — so every digest
/// this app has scheduled was booked against UTC wall time. In Ahmedabad that is 5½ hours late; in Los
/// Angeles it is 7 or 8 hours early; in Auckland it lands on the wrong day. The symptom is identical
/// everywhere and it never looks like a timezone bug: the screen shows the time the user picked, and the
/// notification arrives at some other hour.
///
/// **Pure Dart, and that is the design rather than a constraint.** The obvious fix is to ask Android for
/// `ZoneId.systemDefault()`. That is the wrong fix here for two reasons that have nothing to do with
/// ARCH_1 §7.4:
///
/// 1. `daily_job.dart` reschedules from a `workmanager` isolate. A channel registered in
///    `MainActivity.configureFlutterEngine` is not registered in that isolate — so the caller that
///    matters most after a reboot would be the only caller with no zone.
/// 2. A platform channel cannot be exercised in a widget test. That is the stated reason `ReminderPort`
///    exists, and a fix that inherits the same untestability inherits the same class of bug: green suite,
///    broken device.
///
/// **How it works: match behaviour, not names.** `dart:core` already knows the device's UTC offset at any
/// instant, DST included — `DateTime.fromMillisecondsSinceEpoch(ms).timeZoneOffset` asks the OS. So sample
/// the device's offset across fourteen months, ask every zone in the database the same questions, and keep
/// the zones whose answers agree at every probe. A zone that reproduces the device's entire DST behaviour
/// for a year either *is* the device's zone or is indistinguishable from it for scheduling purposes.
///
/// This is why no name lookup is needed, and why it is more robust than one: `DateTime.now().timeZoneName`
/// returns an abbreviation on Android, and abbreviations are ambiguous — `IST` is India, Israel *and* Irish
/// Summer Time, three zones and two hemispheres. An offset fingerprint cannot be ambiguous in that way.
library;

import 'package:timezone/timezone.dart' as tz;

/// How well the resolved zone reproduced the device's own behaviour.
enum TimeZoneMatch {
  /// Exactly one zone matched the device at every probe.
  exact,

  /// Several zones matched at every probe, including the fine pass.
  ///
  /// Not a degraded result. Zones that agree at every probe across fourteen months are interchangeable
  /// for a daily wall-clock reminder — `Asia/Kolkata` and `Asia/Calcutta` are the same rules under two
  /// names. Only the label is a guess; the delivery time is not.
  ambiguous,

  /// No zone matched every probe, so the closest was taken.
  ///
  /// Reachable when a device has a manually-skewed clock or a zone newer than the bundled database.
  /// Scheduling still works; it may be an hour out during a DST window.
  approximate,

  /// Nothing in the database shared the device's current offset. UTC was kept.
  fallback,
}

/// The outcome of one resolution, including enough to explain itself.
final class ResolvedTimeZone {
  /// Creates a resolution result.
  const ResolvedTimeZone({
    required this.location,
    required this.match,
    required this.deviceOffset,
    required this.candidates,
    required this.probes,
    required this.mismatches,
  });

  /// The zone to hand to `setLocalLocation`.
  final tz.Location location;

  /// How much to trust [location]'s name. Never affects whether delivery is correct.
  final TimeZoneMatch match;

  /// The device's offset at the moment of resolution.
  ///
  /// Kept so a caller can notice the device has changed zone — a flight — and re-resolve, which is what
  /// makes the port's "still 9am after you fly somewhere" promise true rather than aspirational.
  final Duration deviceOffset;

  /// How many zones matched at every probe.
  final int candidates;

  /// How many instants were compared.
  final int probes;

  /// How many probes the chosen zone disagreed on. Zero unless [match] is [TimeZoneMatch.approximate].
  final int mismatches;

  /// The IANA name, e.g. `Asia/Kolkata`.
  String get name => location.name;

  @override
  String toString() =>
      'ResolvedTimeZone($name, ${match.name}, offset=$deviceOffset, '
          'candidates=$candidates, probes=$probes, mismatches=$mismatches)';
}

/// Finds the zone whose offsets match this device's.
///
/// Stateless and synchronous: it reads `dart:core` and the already-loaded zone database and nothing else.
/// The caller loads the database and applies the result, because caching policy differs between the UI
/// isolate (long-lived, can change zone mid-flight) and the daily job's (born and dies in one run).
abstract final class DeviceTimeZone {
  /// The coarse pass's step, in days.
  ///
  /// Five days observes both sides of any DST period, since no zone's summer time is shorter than that.
  /// It deliberately does *not* try to separate zones whose transition dates differ by a week — the EU
  /// switches on the last Sunday of October and the US on the first Sunday of November — because that is
  /// what the fine pass is for, and running the fine step over 600 zones to discriminate a handful is
  /// work for nothing.
  static const int coarseStepDays = 5;

  /// The fine pass's step, in days. One, so a single-day difference in transition dates separates.
  static const int fineStepDays = 1;

  /// How far back the probe window reaches.
  static const int probeDaysBefore = 200;

  /// How far forward it reaches.
  ///
  /// Together with [probeDaysBefore] this spans fourteen months, so the window contains a full DST cycle
  /// whatever day of the year it runs on, in either hemisphere. A twelve-month window anchored at *now*
  /// can straddle a rule change and see each state once, which is not enough to tell two rules apart.
  static const int probeDaysAfter = 220;

  /// Resolves the device's zone.
  ///
  /// [now] is injectable so this can be tested against a fixed instant; [database] so a test can supply
  /// three known zones instead of six hundred. Neither is used in production.
  static ResolvedTimeZone resolve({
    DateTime? now,
    Iterable<tz.Location>? database,
  }) {
    final reference = (now ?? DateTime.now()).toUtc();
    final deviceOffset = _deviceOffsetAt(reference);

    // **Phase 1: the current offset, over everything.** One comparison per zone cuts six hundred to
    // roughly thirty before any DST work happens. Every zone the device could be is in this shortlist,
    // because a zone that disagrees about *now* cannot be the device's zone.
    final shortlist = <tz.Location>[];
    for (final location in database ?? _allLocations()) {
      if (_offsetAt(location, reference) == deviceOffset) shortlist.add(location);
    }

    if (shortlist.isEmpty) {
      // **UTC, and this is not silent.** `match` records it, so the caller can surface "we could not
      // work out your time zone" instead of quietly scheduling against the wrong one — which is the
      // failure this whole file exists to end.
      return ResolvedTimeZone(
        location: tz.UTC,
        match: TimeZoneMatch.fallback,
        deviceOffset: deviceOffset,
        candidates: 0,
        probes: 0,
        mismatches: 0,
      );
    }

    // **Phase 2: fourteen months of DST behaviour, over the shortlist only.**
    final coarse = _probeInstants(reference, coarseStepDays);
    var narrowed = _survivors(shortlist, coarse);

    // **Phase 3: the fine pass, and only when it can change the answer.** Skipped for a single survivor
    // and skipped when the coarse pass eliminated everything, which are the two common cases.
    var probesRun = coarse.length;
    if (narrowed.matched.length > 1) {
      final fine = _probeInstants(reference, fineStepDays);
      final refined = _survivors(narrowed.matched, fine);
      if (refined.matched.isNotEmpty) {
        narrowed = refined;
        probesRun = fine.length;
      }
    }

    if (narrowed.matched.isNotEmpty) {
      return ResolvedTimeZone(
        location: _preferred(narrowed.matched),
        match: narrowed.matched.length == 1
            ? TimeZoneMatch.exact
            : TimeZoneMatch.ambiguous,
        deviceOffset: deviceOffset,
        candidates: narrowed.matched.length,
        probes: probesRun,
        mismatches: 0,
      );
    }

    // Nothing matched every probe. The best of the shortlist still shares the device's offset today, so
    // it is right now and may drift for one DST window — strictly better than UTC, which is wrong now.
    return ResolvedTimeZone(
      location: narrowed.best ?? shortlist.first,
      match: TimeZoneMatch.approximate,
      deviceOffset: deviceOffset,
      candidates: shortlist.length,
      probes: probesRun,
      mismatches: probesRun - narrowed.bestHits,
    );
  }

  /// Every zone the loaded database knows.
  ///
  /// **The one expression in this file that could not be compiled against** (ARCH_M §7, and the scheduler's
  /// own note that this plugin surface "has moved between major versions"). If the analyzer rejects
  /// `tz.timeZoneDatabase.locations`, read the declaration in `package:timezone` rather than trying a
  /// second remembered name — the doc's rule is that a second guess after the first fails is worse than
  /// the first. Nothing else in this file changes either way.
  static Iterable<tz.Location> _allLocations() =>
      tz.timeZoneDatabase.locations.values;

  /// The device's own offset at [instant], from the OS rather than the zone database.
  ///
  /// `fromMillisecondsSinceEpoch` without `isUtc` yields a *local* `DateTime` for that instant, and its
  /// `timeZoneOffset` is therefore the device's offset then — DST included. This is the measurement the
  /// whole file is built on and it needs no plugin.
  static Duration _deviceOffsetAt(DateTime instant) =>
      DateTime.fromMillisecondsSinceEpoch(
        instant.millisecondsSinceEpoch,
      ).timeZoneOffset;

  /// What [location] thinks the offset is at [instant].
  ///
  /// Deliberately via `TZDateTime.timeZoneOffset` rather than the database's own zone lookup:
  /// `TZDateTime` implements `DateTime`, so this is the one member guaranteed to exist by an interface
  /// this project already depends on.
  static Duration _offsetAt(tz.Location location, DateTime instant) =>
      tz.TZDateTime.from(instant, location).timeZoneOffset;

  /// Instants to compare, [stepDays] apart, spanning the probe window.
  static List<DateTime> _probeInstants(DateTime reference, int stepDays) {
    final instants = <DateTime>[];
    for (var day = -probeDaysBefore; day <= probeDaysAfter; day += stepDays) {
      instants.add(reference.add(Duration(days: day)));
    }
    return instants;
  }

  /// Which of [candidates] agree with the device at every instant in [probes].
  static _Narrowing _survivors(
      List<tz.Location> candidates,
      List<DateTime> probes,
      ) {
    final expected = [for (final probe in probes) _deviceOffsetAt(probe)];
    final matched = <tz.Location>[];
    tz.Location? best;
    var bestHits = -1;

    for (final location in candidates) {
      var hits = 0;
      for (var i = 0; i < probes.length; i++) {
        if (_offsetAt(location, probes[i]) == expected[i]) hits++;
      }
      if (hits == probes.length) matched.add(location);
      if (hits > bestHits) {
        bestHits = hits;
        best = location;
      }
    }
    return _Narrowing(matched: matched, best: best, bestHits: bestHits);
  }

  /// Picks one name from several behaviourally identical zones.
  ///
  /// **Cosmetic by construction.** Every zone reaching here agreed with the device at every probe, so the
  /// choice cannot change when a notification arrives — only what a diagnostic line would print. The
  /// ordering prefers a real region over a fixed-offset pseudo-zone (`Etc/GMT-5`) and over a legacy alias
  /// (`US/Pacific`), then sorts by name so the answer is stable across runs rather than dependent on map
  /// iteration order.
  static tz.Location _preferred(List<tz.Location> candidates) {
    final sorted = [...candidates]..sort((a, b) {
      final tier = _tier(a.name).compareTo(_tier(b.name));
      return tier != 0 ? tier : a.name.compareTo(b.name);
    });
    return sorted.first;
  }

  static int _tier(String name) {
    final slash = name.indexOf('/');
    if (slash < 0 || name.startsWith('Etc/')) return 3;
    return _legacyRoots.contains(name.substring(0, slash)) ? 2 : 1;
  }

  /// Roots kept in the database for compatibility, each an alias of a `Region/City` zone.
  static const Set<String> _legacyRoots = {
    'SystemV',
    'US',
    'Canada',
    'Brazil',
    'Chile',
    'Mexico',
  };
}

/// One pass's result: who matched everything, and who came closest if nobody did.
final class _Narrowing {
  const _Narrowing({
    required this.matched,
    required this.best,
    required this.bestHits,
  });

  final List<tz.Location> matched;
  final tz.Location? best;
  final int bestHits;
}