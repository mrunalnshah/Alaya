/// Shared scaffolding for the Split module's widget tests.
///
/// Overrides the feature's view-model providers rather than faking every repository: a widget test's
/// job is the widget — four states, a doubled text scale, the tap-target floor (ARCH_5 §9.1).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/split_group.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/features/split/providers/split_providers.dart';

/// The narrowest phone this app supports (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// Tall enough that a lazy list builds its whole body.
///
/// Content assertions get this; the U15 gate stays narrow. A `ListView` does not build rows below the
/// fold, so `findsNothing` at 320×640 passes for the wrong reason.
const Size kTallViewport = Size(320, 3200);

/// A stream that never emits, so an `AsyncValue` stays loading.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// A person who can be chosen for a split.
Payee person(String id, String name, {String? phone}) => Payee(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  kind: PayeeKind.person,
  phone: phone,
);

/// A row this app wrote because a split had to name somebody.
///
/// Appears on balances so it can be renamed, and nowhere a real contact belongs — see
/// [splitOverrides], which feeds these to `splitParticipantsProvider` only.
Payee placeholder(String id, String name) => Payee(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  kind: PayeeKind.splitPlaceholder,
);

/// A group with [members], optionally carrying default weights.
///
/// **Named `splitGroup`, not `group`.** `flutter_test` exports a top-level `group` for suites, and a
/// harness that shadows it makes every `group('...', ...)` in every test file that imports this one
/// ambiguous — five errors in one file, none of them pointing at the fixture that caused them.
SplitGroup splitGroup(
  String id,
  String name, {
  required List<String> members,
  Map<String, int>? weights,
  bool archived = false,
}) => SplitGroup(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  defaultSplitMethod: weights == null ? SplitMethod.equal : SplitMethod.shares,
  isArchived: archived,
  sortOrder: 0,
  members: [
    for (var i = 0; i < members.length; i++)
      SplitMember(
        id: 'm-${members[i]}',
        groupId: id,
        payeeId: members[i],
        defaultWeightBasisPoints: weights?[members[i]],
        sortOrder: i,
      ),
  ],
);

/// Somebody owes the user.
SplitBalance owedToMe(String payeeId, int minor, {DateKey? since}) =>
    SplitBalance(
      payeeId: payeeId,
      owedToMe: Money(minor, 'INR'),
      iOwe: const Money(0, 'INR'),
      oldestUnsettledDateKey: since,
    );

/// The user owes somebody.
SplitBalance iOwe(String payeeId, int minor, {DateKey? since}) => SplitBalance(
  payeeId: payeeId,
  owedToMe: const Money(0, 'INR'),
  iOwe: Money(minor, 'INR'),
  oldestUnsettledDateKey: since,
);

/// An account a settlement or an expense can move through.
///
/// **Every required field supplied, including the three a fixture is tempted to skip.**
/// `openingBalance`, `openingBalanceDateKey` and `includeInNetWorth` are required on `Account` because
/// anomaly A03 made them load-bearing — a balance is opening balance plus movements, and an account
/// that silently defaulted to zero would make every derived figure quietly wrong.
Account account(String id, String name) => Account(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  kind: AccountKind.bank,
  currencyCode: 'INR',
  openingBalance: const Money(0, 'INR'),
  openingBalanceDateKey: const DateKey(20260101),
  isArchived: false,
  includeInNetWorth: true,
  sortOrder: 0,
);

/// The overrides every split screen needs to render at all.
///
/// **Defaults that make the screen work, not defaults that make it empty.** A harness whose defaults
/// leave every provider loading forces each test to restate the same five overrides before it can
/// assert anything, and the restating is where they drift apart.
///
/// **Both people providers are overridden, and forgetting the second cost a failing test.**
/// `splitPeopleProvider` answers *"who may I add?"* and holds [people]; `splitParticipantsProvider`
/// answers *"who is this?"* and holds [people] **plus** [placeholders]. `splitPayeeProvider` — which
/// every balance row uses to turn an id into a name — reads the second. Override only the first and
/// the second falls through to the real implementation, `payeeRepositoryProvider` is absent in a
/// widget test, and every name renders as "Someone".
///
/// **Totals and ageing are derived from [balances] rather than passed in.** In production they come
/// from the same rows, so a harness that let a test state them independently would let it assert a
/// screen showing "₹4,000 owed" above a list containing nobody — a state the app cannot reach, tested
/// as though it could.
List<Override> splitOverrides({
  List<Payee> people = const [],
  List<Payee> placeholders = const [],
  List<SplitGroup> groups = const [],
  List<SplitBalance> balances = const [],
  List<Account> accounts = const [],
  String? self = 'me',
  int digits = 2,
  DateKey today = const DateKey(20260814),
  int ageingThresholdDays = 14,
}) {
  var owed = const Money(0, 'INR');
  var owing = const Money(0, 'INR');
  final ageing = <AgeingDebt>[];
  for (final balance in balances) {
    if (balance.isSettled) continue;
    if (balance.theyOweMe) {
      owed += balance.outstanding;
    } else {
      owing += balance.outstanding;
    }
    final age = balance.ageInDays(today);
    if (age != null && age >= ageingThresholdDays) {
      ageing.add(AgeingDebt(balance: balance, ageInDays: age));
    }
  }
  ageing.sort((a, b) => b.ageInDays.compareTo(a.ageInDays));

  return [
    splitPeopleProvider.overrideWith((ref) => Stream.value(people)),
    splitParticipantsProvider.overrideWith(
      (ref) => Stream.value([...people, ...placeholders]),
    ),
    splitAllGroupsProvider.overrideWith((ref) => Stream.value(groups)),
    splitBalancesProvider.overrideWith((ref) => Stream.value(balances)),
    splitAccountsProvider.overrideWith((ref) => Stream.value(accounts)),
    splitSelfProvider.overrideWith((ref) async => self),
    splitDecimalDigitsProvider.overrideWith((ref) async => digits),
    splitTodayProvider.overrideWithValue(today),
    splitTotalsProvider.overrideWith(
      (ref) async =>
          balances.isEmpty ? {} : {'INR': (owedToMe: owed, iOwe: owing)},
    ),
    splitAgeingProvider.overrideWith((ref) async => ageing),
  ];
}

/// Pumps [child] inside the app's theme and localisations.
///
/// **Two frames, not one, and the second is not padding.** The overrides above are `Stream.value(...)`
/// and async closures, so each provider resolves on its own microtask turn. After a single frame a
/// balance row could render while `splitPayeeProvider` still read null and fell back to "Someone" — a
/// test asserting on a name then failed while the screen was perfectly correct.
///
/// `pumpAndSettle` would also work and is worse: it spins until no frame is scheduled, so a screen
/// with any repeating animation hangs the suite instead of failing it.
Future<void> pumpSplit(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// Pumps a screen that lives **inside the drawer shell**, which owns the `Scaffold` and the `AppBar`.
///
/// **`SplitHomeScreen` supplies neither**, so pumping it bare would leave `AmountText` and the rest
/// without a `Material` ancestor and fail for a reason that has nothing to do with the test. This
/// wrapper stands in for `_ShellScaffold` — and because it provides the only `AppBar` in the tree, a
/// test can assert `findsOneWidget` and prove the screen is not adding a second.
Future<void> pumpInShell(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
}) => pumpSplit(
  tester,
  Scaffold(
    appBar: AppBar(title: const Text('Split')),
    body: child,
  ),
  overrides: overrides,
  size: size,
  textScale: textScale,
);
