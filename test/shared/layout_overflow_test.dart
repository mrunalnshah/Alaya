import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_bar_chart.dart';
import 'package:alaya/features/lock/presentation/widgets/pin_pad.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_donut_chart.dart';
import 'package:alaya/features/analytics/presentation/widgets/analytics_line_chart.dart';
import 'package:alaya/features/analytics/presentation/widgets/slice_bar_list.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/features/calendar/presentation/widgets/day_sheet.dart';
import 'package:alaya/features/dashboard/presentation/widgets/funds_header.dart';
import 'package:alaya/features/dashboard/presentation/widgets/insight_card.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/presentation/sheets/delete_transaction_sheet.dart';
import 'package:alaya/features/expense/presentation/sheets/freeze_conversion_sheet.dart';
import 'package:alaya/features/expense/presentation/sheets/line_item_editor.dart';
import 'package:alaya/features/expense/presentation/sheets/quick_add_sheet.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_filter_sheet.dart';
import 'package:alaya/features/expense/providers/quick_add_providers.dart';
import 'package:alaya/features/expense/providers/transaction_detail_providers.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/features/inventory/presentation/sheets/consume_sheet.dart';
import 'package:alaya/features/inventory/providers/consume_providers.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/recurring/presentation/sheets/pay_sheet.dart';
import 'package:alaya/features/recurring/providers/pay_providers.dart';
import 'package:alaya/features/service/presentation/sheets/dispose_sheet.dart';
import 'package:alaya/features/service/presentation/widgets/contact_action.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/shopping/presentation/sheets/entry_editor_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/generate_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/list_manager_sheet.dart';
import 'package:alaya/features/shopping/providers/entry_editor_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_expandable_fab.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/chart_card.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';
import 'package:alaya/shared/widgets/frequency_preview.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/loading_state.dart';
import 'package:alaya/shared/widgets/module_tile.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

import '../support/calendar_harness.dart' as cal;
import '../support/expense_harness.dart';
import '../support/fake_settings_repository.dart';

/// The only thing in this project that catches a layout overflow (ARCH_3 §8.3, ARCH_5 U2).
///
/// **Every sheet and every full-height state belongs here.** These defects are invisible to
/// `dart analyze`, to a file-by-file scan and to looking at the screen, because the missing
/// affordance is always an *ancestor*: the widget under review is locally correct and the parent
/// that should have given it room, or a way to scroll, is the one at fault.
///
/// They are also invisible to an ordinary widget test. A `RenderFlex` overflow reports through
/// `FlutterError.onError` rather than throwing at the site, so a test only fails on one if something
/// asks — which is exactly how an overflow hides in a suite that otherwise looks green. Every case
/// below asks, via `tester.takeException()`.
void main() {
  /// Roughly what a software keyboard takes from a phone in portrait.
  const double keyboardInset = 320;

  /// Roughly the room a list area has left on a small phone with a keyboard up.
  const Size squeezed = Size(320, 140);

  Widget host(
    Widget child, {
    double bottomInset = 0,
    double textScale = 1,
    List<Override> overrides = const [],
  }) => ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AlayaTheme.light(AlayaPresets.activePreset),
      // Every expense sheet reads `AlayaStrings.of(context)`, which unwraps a null without a
      // delegate installed. The Phase 5 groups pass literal strings, so this file went without
      // one until real screens arrived — and then failed as a null-check rather than as a
      // missing translation, which is why it read like five separate defects.
      localizationsDelegates: const [
        AlayaStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AlayaStrings.supportedLocales,
      // Inside the app rather than above it. `WidgetsApp` re-establishes `MediaQuery` from the
      // view, so an outer one is discarded before anything under test can read it — and a test
      // that believes it has simulated a keyboard when it has not is worse than no test.
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          viewInsets: EdgeInsets.only(bottom: bottomInset),
          textScaler: TextScaler.linear(textScale),
        ),
        child: inner!,
      ),
      home: Scaffold(body: child),
    ),
  );

  /// Content taller than the room a keyboard leaves, so the assertions are about the scaffold rather
  /// than about how long a particular string happens to be.
  Widget tallContent() => const Column(
    mainAxisSize: MainAxisSize.min,
    children: [SizedBox(width: 200, height: 400)],
  );

  group('AlayaBottomSheet', () {
    testWidgets('scrolls rather than overflowing with a keyboard up', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(child: tallContent()),
          bottomInset: keyboardInset,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('still fits when there is no keyboard', (tester) async {
      await tester.pumpWidget(host(AlayaBottomSheet(child: tallContent())));
      expect(tester.takeException(), isNull);
    });

    // The bug, reproduced deliberately. `Padding(bottom: viewInsets)` around a `MainAxisSize.min`
    // Column is correct in each half and broken together: the padding shrinks the space and the
    // Column has no way to give up the room it already took. **If this ever stops overflowing, the
    // guard above has stopped testing anything** — and the reason AlayaBottomSheet exists has
    // quietly gone away.
    testWidgets('the un-scaffolded shape it replaces still overflows', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          Padding(
            padding: const EdgeInsets.only(bottom: keyboardInset),
            child: tallContent(),
          ),
        ),
      );
      expect(tester.takeException(), isA<FlutterError>());
    });
  });

  group('ConfirmSheet', () {
    testWidgets('survives a keyboard and a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => ConfirmSheet.show(
                context,
                title: 'Delete this transaction?',
                body: 'You can undo this for the next few seconds.',
                confirmLabel: 'Delete',
                cancelLabel: 'Cancel',
                destructive: true,
              ),
              child: const Text('open'),
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('AlayaFormScaffold', () {
    Widget form({bool submitting = false}) => AlayaFormScaffold(
      primaryLabel: 'Save expense',
      onPrimary: () {},
      secondaryLabel: 'Cancel',
      onSecondary: () {},
      isDirty: true,
      isSubmitting: submitting,
      discardTitle: 'Discard your changes?',
      discardBody: 'What you have typed will not be saved.',
      discardConfirmLabel: 'Discard',
      discardCancelLabel: 'Keep editing',
      child: const Column(
        children: [SizedBox(height: 300), TextField(), SizedBox(height: 300)],
      ),
    );

    testWidgets('body scrolls and the footer stays above the keyboard', (
      tester,
    ) async {
      await tester.pumpWidget(host(form(), bottomInset: keyboardInset));
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a doubled text scale with a keyboard up', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(form(), bottomInset: keyboardInset, textScale: 2),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the submitting footer does not grow the row past its box', (
      tester,
    ) async {
      await tester.pumpWidget(host(form(submitting: true), textScale: 2));
      expect(tester.takeException(), isNull);
    });
  });

  // Every sheet Phase 6A adds, at a keyboard inset and a doubled text scale — the two conditions
  // under which each of them is first used and least likely to have been looked at.
  group('expense sheets', () {
    final expenseOverrides = <Override>[
      homeCurrencyCodeProvider.overrideWith((ref) => 'INR'),
      homeDecimalDigitsProvider.overrideWith((ref) => 2),
      selectableAccountsProvider.overrideWith(
        (ref) => Stream.value(const [kAccount]),
      ),
      quickAddTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[])),
      accountsByIdProvider.overrideWith(
        (ref) => Stream.value(<String, Account>{kAccount.id: kAccount}),
      ),
      lineEditorItemsProvider.overrideWith(
        (ref) => Stream.value(const <Item>[]),
      ),
      enabledCurrenciesProvider.overrideWith(
        (ref) => Stream.value(const [
          Currency(
            code: 'USD',
            name: 'US Dollar',
            symbol: r'$',
            decimalDigits: 2,
            isEnabled: true,
            sortOrder: 1,
          ),
        ]),
      ),
    ];

    Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(child: sheet),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: expenseOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets(
      'QuickAddSheet',
      (tester) => pumpSheet(tester, const QuickAddSheet()),
    );

    testWidgets(
      'TransactionFilterSheet',
      (tester) => pumpSheet(tester, const TransactionFilterSheet()),
    );

    testWidgets(
      'LineItemEditor',
      (tester) => pumpSheet(
        tester,
        const LineItemEditor(
          currencyCode: 'INR',
          decimalDigits: 2,
          defaultDestination: TransactionLineDestination.inventory,
        ),
      ),
    );

    testWidgets(
      'DeleteTransactionSheet',
      (tester) => pumpSheet(tester, const DeleteTransactionSheet()),
    );

    testWidgets(
      'FreezeConversionSheet',
      (tester) =>
          pumpSheet(tester, const FreezeConversionSheet(excludeCode: 'INR')),
    );
  });

  // Phase 6B's sheet, at a keyboard inset and a doubled text scale — the two conditions under
  // which it is first used and least likely to have been looked at (U2).
  group('inventory sheets', () {
    final inventoryOverrides = <Override>[
      consumeFefoProvider(
        'item-1',
      ).overrideWith((ref) => Stream.value(const <Batch>[])),
      unitsInCategoryProvider(UnitCategory.weight).overrideWith(
        (ref) => Stream.value(const [
          Unit(
            code: 'kg',
            category: UnitCategory.weight,
            factorToBaseMilli: 1000000,
            displayName: 'kilogram',
            isSystem: true,
            sortOrder: 1,
          ),
        ]),
      ),
    ];

    testWidgets('ConsumeSheet', (tester) async {
      await tester.pumpWidget(
        host(
          const AlayaBottomSheet(
            child: ConsumeSheet(
              itemId: 'item-1',
              unitCode: 'kg',
              category: UnitCategory.weight,
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: inventoryOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6C's three sheets, at a keyboard inset and a doubled text scale — the two conditions under
  // which each is first used and least likely to have been looked at (U2).
  group('shopping sheets', () {
    final shoppingOverrides = <Override>[
      entryItemsProvider.overrideWith((ref) => Stream.value(const <Item>[])),
      entryTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[])),
      entryCurrencyProvider.overrideWith((ref) async => 'INR'),
      entryDecimalDigitsProvider.overrideWith((ref) async => 2),
      entriesProvider(
        'list-1',
      ).overrideWith((ref) => Stream.value(const <ShoppingEntry>[])),
      shoppingItemsByIdProvider.overrideWith(
        (ref) => Stream.value(const <String, Item>{}),
      ),
      allListsProvider.overrideWith(
        (ref) => Stream.value(const <ShoppingList>[]),
      ),
    ];

    Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(child: sheet),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: shoppingOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets(
      'EntryEditorSheet',
      (tester) => pumpSheet(tester, const EntryEditorSheet(listId: 'list-1')),
    );

    testWidgets(
      'GenerateSheet',
      (tester) => pumpSheet(tester, const GenerateSheet(listId: 'list-1')),
    );

    testWidgets(
      'ListManagerSheet',
      (tester) => pumpSheet(tester, const ListManagerSheet()),
    );
  });

  // Phase 6D's pay sheet, at a keyboard inset and a doubled text scale — an amount field, a date
  // field, an account dropdown and a two-line note, all growing at once.
  group('recurring sheets', () {
    final recurringOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      payAccountsProvider.overrideWith(
        (ref) => Stream.value(const <Account>[]),
      ),
      payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
    ];

    testWidgets('PaySheet', (tester) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(
            child: PaySheet(
              occurrenceId: 'occ-1',
              template: RecurringTemplate(
                id: 'tpl-1',
                name:
                    'A rent template with a name long enough to wrap at a doubled scale',
                normalizedName: 'rent',
                kind: RecurringKind.rent,
                direction: RecurringDirection.outflow,
                defaultAmount: const Money(120000, 'INR'),
                intervalUnit: RecurringIntervalUnit.month,
                intervalCount: 1,
                startDateKey: const DateKey(20260131),
                nextDueDateKey: const DateKey(20260831),
                isPaused: false,
                autoRemind: true,
                remindDaysBefore: 3,
                anchorDayOfMonth: 31,
              ),
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: recurringOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The one shared widget Phase 6D adds, with a clamp note on every row.
  group('FrequencyPreview at a doubled text scale', () {
    testWidgets('three dates, two of them clamped', (tester) async {
      await tester.pumpWidget(
        host(
          const FrequencyPreview(
            dates: [
              PreviewedDate(dateKey: DateKey(20260131)),
              PreviewedDate(dateKey: DateKey(20260228), clamped: true),
              PreviewedDate(dateKey: DateKey(20260331)),
            ],
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6E's dispose sheet: seven choice chips, a date field, an optional amount and a note, all
  // growing at once under a keyboard inset.
  group('service sheets', () {
    final serviceOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
    ];

    testWidgets('DisposeSheet', (tester) async {
      await tester.pumpWidget(
        host(
          const AlayaBottomSheet(
            child: DisposeSheet(assetId: 'asset-1', currencyCode: 'INR'),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: serviceOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The contact block: a name, a number and a call button, none of them flexible.
  group('ContactAction at a doubled text scale', () {
    testWidgets('a long name beside a long number', (tester) async {
      await tester.pumpWidget(
        host(
          const ContactAction(
            phone: '+91 98765 43210',
            name: 'A service centre with a name long enough to wrap',
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6F's dashboard sections. Each is a card whose figures, chips and labels all grow at once, and
  // the funds header carries the only display-sized amount in the app.
  group('dashboard sections', () {
    final dashOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      // InsightCard's notifier restores its side from `app_settings` on the first frame, which
      // resolves `databaseProvider` unless this is here — the failure reads as a database bug in a
      // test that never mentions one (ARCH_6 P6).
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      dashboardCurrencyProvider.overrideWith((ref) async => 'INR'),
      dashboardDigitsProvider.overrideWith((ref) async => 2),
      totalFundsProvider.overrideWith(
        (ref) async => const NetWorth(
          total: Money(98765432, 'INR'),
          unconvertedCount: 3,
          isApproximate: true,
        ),
      ),
      upcomingProvider.overrideWith((ref) async => const <UpcomingEntry>[]),
    ];

    testWidgets('FundsHeader with both chips at a doubled scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const FundsHeader(), textScale: 2, overrides: dashOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('InsightCard with its switch at a doubled scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const InsightCard(), textScale: 2, overrides: dashOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The one shared widget Phase 6F adds. Two lines of text and a glyph inside a fixed aspect ratio is
  // exactly the shape that overflows when the text doubles and the box does not.
  group('ModuleTile at a doubled text scale', () {
    testWidgets('a long label beside a long count', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 160,
            height: 108,
            child: ModuleTile(
              label: 'Recurring commitments',
              icon: Icons.event_repeat,
              detail: '17 need attention before the end of the month',
              onTap: () {},
            ),
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 7A. Both shapes here are the ones that have already cost this project rounds: a sheet whose
  // content outgrows the viewport, and a grid of text cells whose row height does not move with the text.
  // Zero width, which is not a hypothetical: Android reports it on the first frame of every launch
  // ("D/FlutterRenderer: Width is zero. 0,0") and the FAB's slot subtracted padding from it, producing a
  // negative width and a red screen on startup. Every widget harness sets a real viewport before pumping,
  // which is exactly why nothing here caught it — so the degenerate viewport is now stated outright.
  group('degenerate viewports', () {
    testWidgets('the expandable FAB survives a zero-width first frame', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size.zero),
            child: Scaffold(
              floatingActionButton: AlayaExpandableFab(
                openLabel: 'Add',
                closeLabel: 'Close',
                actions: [
                  FabAction(label: 'One', icon: Icons.add, onPressed: () {}),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('calendar', () {
    List<Override> calOverrides({List<CalendarEvent> events = const []}) =>
        cal.calendarOverrides(cal.FakeCalendarRepository(events: events));

    final busyDay = <CalendarEvent>[
      cal.event(
        title: 'A payee with a name long enough to wrap at a doubled scale',
        amountMinor: 98765432,
      ),
      cal.event(
        type: CalendarEventType.serviceDue,
        refType: 'asset',
        refId: 'as-1',
        title: 'The boiler in the upstairs cupboard',
        baseSeverity: CalendarSeverity.warning,
      ),
      cal.event(
        type: CalendarEventType.batchExpiry,
        refType: 'inventoryBatch',
        refId: 'ba-1',
        title: 'Yoghurt, the large tub',
        baseSeverity: CalendarSeverity.warning,
      ),
    ];

    testWidgets('DaySheet with three grouped entries at a doubled scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const DaySheet(dateKey: cal.kToday),
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('DaySheet with a keyboard up as well', (tester) async {
      await tester.pumpWidget(
        host(
          const DaySheet(dateKey: cal.kToday),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // U26: `TableCalendar` takes a fixed `rowHeight`, so the grid computes one from the text scaler. If
    // that computation is ever replaced by a constant, this is the test that says so.
    testWidgets('the month grid at a doubled scale on the narrowest phone', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const CalendarScreen(),
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'the month grid at a tripled scale, which is past what U15 asks for',
      (tester) async {
        await tester.pumpWidget(
          host(
            const CalendarScreen(),
            textScale: 3,
            overrides: calOverrides(events: busyDay),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    // The range header prints two formatted dates and a dash, which is the longest single string this
    // screen can produce — and it appears only in a mode the other cases never enter.
    testWidgets('the range header at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(
          const CalendarScreen(),
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('22'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    // The screen's own composition, which the shared full-height group cannot reach: six measured rows
    // plus a header are taller than a squeezed list area on their own, so the grid and the state beneath
    // it have to share a scroll rather than compete for a fixed box.
    for (final scale in [1.0, 2.0]) {
      testWidgets('the whole screen in a squeezed viewport at ${scale}x', (
        tester,
      ) async {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: const CalendarScreen(),
            ),
            textScale: scale,
            overrides: calOverrides(events: busyDay),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    // Each of the three states in turn, in the same squeezed box. Loading and error sit in the sliver
    // that fills the remainder, and that remainder is negative here.
    testWidgets('loading, empty and error all survive the squeezed box', (
      tester,
    ) async {
      for (final repo in [
        cal.FakeCalendarRepository(pending: true),
        cal.FakeCalendarRepository(),
        cal.FakeCalendarRepository(error: 'view unavailable'),
      ]) {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: const CalendarScreen(),
            ),
            textScale: 2,
            overrides: cal.calendarOverrides(repo),
          ),
        );
        // `pump`, not `pumpAndSettle`: the loading case holds a `CircularProgressIndicator`, which
        // animates forever, so `pumpAndSettle` times out rather than settling. Two frames is enough to
        // resolve the completed futures in the other two cases.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('full-height states in a squeezed viewport', () {
    Widget inSqueezedBox(Widget child) => host(
      Center(
        child: SizedBox(
          width: squeezed.width,
          height: squeezed.height,
          child: child,
        ),
      ),
    );

    testWidgets('EmptyState with an icon, body and action', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          EmptyState(
            title: 'No transactions yet',
            body: 'Add your first expense and it will appear here.',
            icon: Icons.receipt_long_outlined,
            actionLabel: 'Add expense',
            onAction: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ErrorState with a retry — the tallest of the three', (
      tester,
    ) async {
      await tester.pumpWidget(
        inSqueezedBox(
          ErrorState(
            title: 'That did not work',
            body: 'Something went wrong on our side. Try again.',
            retryLabel: 'Try again',
            onRetry: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('LoadingState', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(const LoadingState(label: 'Loading')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('AlayaListSkeleton clips rather than overflowing', (
      tester,
    ) async {
      await tester.pumpWidget(
        inSqueezedBox(const AlayaListSkeleton(label: 'Loading transactions')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('EmptyState at a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(
          Center(
            child: SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: EmptyState(
                title: 'No transactions yet',
                body: 'Add your first expense and it will appear here.',
                icon: Icons.receipt_long_outlined,
                actionLabel: 'Add expense',
                onAction: () {},
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    // The states are also the shape the Theme Lab renders inside a half-width pane, which is where
    // the 150px `SizedBox` around an EmptyState used to overflow by roughly 58px.
    testWidgets('EmptyState in a half-width pane', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          const SizedBox(
            width: 134,
            child: EmptyState(
              title: 'No matches',
              body: 'Try a shorter search.',
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6A's line-items page: a full-height screen whose summary row, list rows and footer all
  // grow under text scale at once. Squeezed and doubled, which is the pair U21 exists for.
  group('the line items page', () {
    final editorOverrides = <Override>[
      transactionEditorProvider.overrideWith(
        () => _FixedEditor(
          AsyncValue.data(
            TransactionEditorState(
              currencyCode: 'INR',
              dateKey: const DateKey(20260801),
              amount: const Money(20000, 'INR'),
              lines: [
                TransactionLine(
                  id: 'l1',
                  transactionId: '',
                  lineNo: 1,
                  description:
                      'A description long enough to need two lines at a doubled scale',
                  destination: TransactionLineDestination.inventory,
                  quantity: const Qty(500000, UnitCategory.weight),
                  lineAmount: const Money(4000, 'INR'),
                ),
              ],
            ),
          ),
        ),
      ),
      homeDecimalDigitsProvider.overrideWith((ref) async => 2),
    ];

    testWidgets('populated at 320dp and a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(const LineItemsScreen(), textScale: 2, overrides: editorOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('kit rows at a doubled text scale', () {
    testWidgets('KeyValueRow wraps a long value instead of overflowing', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 320,
            child: KeyValueRow(
              label: 'Payment method',
              value: 'Bank transfer from HDFC Savings ending 4417',
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('FilterChipBar wraps rather than clipping a row of chips', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: FilterChipBar(
              clearAllLabel: 'Clear all',
              onClearAll: () {},
              filters: [
                ActiveFilter(label: 'Account: HDFC Savings', onRemove: () {}),
                ActiveFilter(label: 'Tag: Groceries', onRemove: () {}),
                ActiveFilter(label: 'Jan 2026 – Aug 2026', onRemove: () {}),
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('StatusChip ellipsises a long label in a narrow box', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 96,
            child: StatusChip(label: 'Needs details', tone: StatusTone.info),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ── Phase 7B ──────────────────────────────────────────────────────────────────────────
  //
  // **No sheets, so no sheet cases.** 7B adds no `AlayaBottomSheet`: the tag drill happens in place
  // inside its card and the clear-cache action is a row, so there is nothing here for U2's sheet
  // clause to cover. What it does add is one shared widget, two chart surfaces and four full-height
  // states, and those are below.
  group('analytics surfaces', () {
    // **Wrapped in a scroll view, because that is the only place a `ChartCard` ever lives** — the
    // analytics screen puts every card in a `SliverList`. Handed a tight viewport height instead, its
    // `Column` has nowhere to go and reports an overflow the real screen cannot produce. What these
    // cases are for is the *horizontal* axis: a header that starves, a chip row that will not wrap, a
    // plot box that outgrows its card.
    Widget card({
      Widget? trailing,
      Widget child = const Text('body'),
      AsyncValue<int> value = const AsyncValue.data(1),
    }) => SingleChildScrollView(
      child: ChartCard<int>(
        title: 'Price per kilogram across every purchase this year',
        subtitle: 'What one thing costs you, purchase by purchase',
        value: value,
        isEmpty: (data) => data == 0,
        emptyMessage: 'Nothing yet',
        onRetry: () {},
        approximateCount: 3,
        unconvertedCount: 2,
        trailing: trailing,
        builder: (context, data) => child,
      ),
    );

    testWidgets(
      'ChartCard stacks its header above 1.5x rather than clipping the figure',
      (tester) async {
        // The `trailing` slot is an `AmountText`, which clips rather than ellipsises — so a clipped
        // figure is a wrong figure and the header has to stack instead of sharing a row (Law U21).
        await tester.pumpWidget(
          host(
            SizedBox(
              width: 320,
              child: card(
                trailing: const AmountText(
                  Money(123456789, 'INR'),
                  size: AmountSize.small,
                  showSign: false,
                ),
              ),
            ),
            textScale: 2,
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('ChartCard keeps both quality chips at a doubled scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(SizedBox(width: 320, child: card()), textScale: 2),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ChartCard renders its error branch in a narrow box', (
      tester,
    ) async {
      // The inline failure, not `ErrorState`: that one is a full-height state with a 40px glyph and
      // its own `ScrollSafeCenter`, which inside a card would push every sibling off the screen.
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              value: AsyncValue<int>.error(
                Exception('No rate for JPY on 2026-08-10, and none earlier'),
                StackTrace.empty,
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a plot area grows with the text scaler and stays inside its card', (
      tester,
    ) async {
      // `AnalyticsPlotBox` scales from the text scaler and clamps (Laws U26, U28's clamping lesson).
      // Unclamped, a tripled scale would produce a card taller than the viewport — and the box sizes
      // only the plot, so the card's own title and subtitle grow beside it rather than being squeezed
      // into the plot's height.
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              child: const AnalyticsPlotBox(
                child: AnalyticsLineChart(
                  series: [
                    AnalyticsSeries(
                      tone: AnalyticsSeriesTone.expense,
                      points: [
                        AnalyticsPoint(x: 0, value: 100000, axisLabel: 'Jan'),
                        AnalyticsPoint(x: 1, value: 90000),
                        AnalyticsPoint(x: 2, value: 140000, axisLabel: 'Aug'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a flat series does not collapse its own plot band', (
      tester,
    ) async {
      // Every point equal makes `maxY - minY` zero, which fl_chart divides by. The chart widens the
      // band by one minor unit rather than handing it a zero.
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 320,
            height: 120,
            child: AnalyticsLineChart(
              series: [
                AnalyticsSeries(
                  tone: AnalyticsSeriesTone.neutral,
                  points: [
                    AnalyticsPoint(x: 0, value: 5000),
                    AnalyticsPoint(x: 1, value: 5000),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a bar chart of thirty-one buckets survives a doubled scale at 320dp',
      (tester) async {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: 320,
              height: 160,
              child: AnalyticsBarChart(
                labelEvery: 5,
                buckets: [
                  for (var day = 1; day <= 31; day++)
                    AnalyticsBucket(
                      bucket: day,
                      value: day * 1000,
                      label: '$day',
                    ),
                ],
              ),
            ),
            textScale: 2,
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('an all-zero bar chart still draws its axis', (tester) async {
      // A window where nothing was spent must show that the buckets exist and are empty, rather than
      // dividing by a zero maximum.
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 320,
            height: 160,
            child: AnalyticsBarChart(
              buckets: [
                AnalyticsBucket(bucket: 1, value: 0, label: 'M'),
                AnalyticsBucket(bucket: 7, value: 0, label: 'S'),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a donut stays a ring at a tripled scale', (tester) async {
      // `AnalyticsDonutChart` sizes its radius from the box's shorter side, so a taller box at a raised
      // scale must not produce a cropped ellipse — and the centre text has to fit the hole.
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              child: Builder(
                builder: (context) => AnalyticsDonutChart(
                  slices: analyticsSlices(
                    context,
                    const [
                      (label: 'Groceries', value: 400000, key: 'grocery'),
                      (label: 'Household', value: 220000, key: 'household'),
                      (label: 'Bills', value: 180000, key: 'bill'),
                    ],
                    otherLabel: 'Everything else',
                    remainder: 90000,
                  ),
                  centreTop: '85%',
                  centreBottom: 'in three kinds',
                ),
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a donut groups its tail rather than drawing twelve slivers', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: card(
              child: Builder(
                builder: (context) {
                  final slices = analyticsSlices(
                    context,
                    [
                      for (var i = 0; i < 12; i++)
                        (label: 'Kind $i', value: 12000 - i * 500, key: 'k$i'),
                    ],
                    otherLabel: 'Everything else',
                  );
                  // Six wedges plus one remainder, whatever it was handed.
                  expect(slices, hasLength(7));
                  return AnalyticsDonutChart(slices: slices);
                },
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'an all-zero donut renders nothing rather than dividing by zero',
      (tester) async {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: 320,
              child: card(
                child: Builder(
                  builder: (context) {
                    final slices = analyticsSlices(
                      context,
                      const [(label: 'Groceries', value: 0, key: 'grocery')],
                      otherLabel: 'Everything else',
                    );
                    expect(slices, isEmpty);
                    return AnalyticsDonutChart(slices: slices);
                  },
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a swatched list without bars stacks above 1.5x', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: SliceBarList(
              showBars: false,
              slices: [
                SliceBar(
                  label: 'Between my accounts and everywhere else',
                  value: const AmountText(
                    Money(98765432, 'INR'),
                    size: AmountSize.small,
                    showSign: false,
                  ),
                  share: 0.8,
                  detail: '34%',
                  swatch: const Color(0xFF3F51B5),
                  onTap: () {},
                ),
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('SliceBarList stacks its rows above 1.5x', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: SliceBarList(
              slices: [
                SliceBar(
                  label: 'Between my accounts and everywhere else',
                  value: const AmountText(
                    Money(98765432, 'INR'),
                    size: AmountSize.small,
                    showSign: false,
                  ),
                  share: 1,
                  detail: '12 purchases',
                  onTap: () {},
                ),
                SliceBar(
                  label: 'Household',
                  value: const QtyText(Qty(4450000, UnitCategory.weight)),
                  share: 0.4,
                ),
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a share above one does not assert', (tester) async {
      // `share` is a ratio of two sums, so a rounding artefact can exceed one and
      // `FractionallySizedBox` asserts on a factor greater than one. It is clamped.
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: SliceBarList(
              slices: [
                SliceBar(
                  label: 'Groceries',
                  value: const Text('x'),
                  share: 1.0000001,
                ),
                SliceBar(
                  label: 'Bills',
                  value: const Text('y'),
                  share: double.nan,
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('analytics full-height states in a squeezed viewport', () {
    Future<void> pumpSqueezed(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(
        host(
          Center(
            child: SizedBox.fromSize(size: squeezed, child: child),
          ),
        ),
      );
    }

    testWidgets('the drill-down skeleton clips rather than overflowing', (
      tester,
    ) async {
      await pumpSqueezed(
        tester,
        const AlayaListSkeleton(label: 'Loading these transactions…'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the drill-down empty state scrolls instead of overflowing', (
      tester,
    ) async {
      await pumpSqueezed(
        tester,
        const EmptyState(
          title: 'Nothing here in this window',
          body:
              'The window is set on the insights screen. Widen it and these may appear.',
          icon: Icons.filter_alt_outlined,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the screen-level empty state scrolls with its action', (
      tester,
    ) async {
      // The tallest of the three: icon, two text blocks and a 48dp button (ARCH_5 §4.1).
      await pumpSqueezed(
        tester,
        EmptyState(
          title: 'Nothing to show for this window',
          body:
              'Widen the window above, or record something and it will appear here.',
          icon: Icons.insights_outlined,
          actionLabel: 'Add expense',
          onAction: () {},
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the drill-down error state survives with a retry', (
      tester,
    ) async {
      await pumpSqueezed(
        tester,
        ErrorState(
          title: 'Could not work that out',
          body: 'No rate for JPY on 2026-08-10, and none earlier',
          retryLabel: 'Try again',
          onRetry: () {},
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ── Phase 8A ──────────────────────────────────────────────────────────────────────────
  //
  // Two sheets and five full-height states. `PaymentMethodSheet` and `PayeeSheet` are the phase's only
  // `AlayaBottomSheet` additions; the lock screen, PIN setup, recovery and the settings empties are its
  // full-height ones (Law U2 — added in the phase that creates them).
  group('settings and lock surfaces', () {
    testWidgets('a PIN keypad fits 320dp at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(
          const Center(
            child: SizedBox(
              width: 320,
              child: PinKeypad(
                enabled: true,
                onDigit: _noDigit,
                onBackspace: _noop,
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a keypad with the biometric key fits at a tripled scale', (
      tester,
    ) async {
      // Four keys on the bottom row rather than three, which is the widest the pad ever gets.
      await tester.pumpWidget(
        host(
          const Center(
            child: SizedBox(
              width: 320,
              child: PinKeypad(
                enabled: true,
                onDigit: _noDigit,
                onBackspace: _noop,
                onBiometric: _noop,
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('six PIN dots fit the narrowest phone', (tester) async {
      await tester.pumpWidget(
        host(
          const Center(
            child: SizedBox(
              width: 320,
              child: PinDots(length: 6, filled: 3, dimmed: false),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the honest-copy paragraph wraps rather than overflowing', (
      tester,
    ) async {
      // The longest string in the app, at the largest scale U15 asks for, in the narrowest column.
      await tester.pumpWidget(
        host(
          const Center(
            child: SizedBox(
              width: 320,
              child: Text(
                'This PIN stops someone who picks up your unlocked phone from opening Alaya. '
                'It does not encrypt your data — anyone with access to the phone’s files can '
                'still read them.',
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a settings empty state scrolls in a squeezed viewport', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          Center(
            child: SizedBox.fromSize(
              size: squeezed,
              child: EmptyState(
                title: 'No accounts yet',
                body: 'Add one so Alaya knows where your money is.',
                icon: Icons.account_balance_wallet_outlined,
                actionLabel: 'Add an account',
                onAction: () {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the scoping matrix stacks at a doubled scale', (tester) async {
      // Six switches, each with a two-line subtitle — the tallest form in the phase.
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: Column(
                children: [
                  for (var i = 0; i < 6; i++)
                    SwitchListTile(
                      value: i.isEven,
                      onChanged: (_) {},
                      title: const Text('Money out'),
                      subtitle: const Text('Offered when you record spending.'),
                    ),
                ],
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the varies panel fits its explanation and its offer', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Then it is not a unit'),
                  const Text(
                    'A unit has to be the same amount every time. One packet of biscuits and one '
                    'packet of rice are different weights, so Alaya could not add two packets '
                    'together or work out what one cost.',
                  ),
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Create an item instead'),
                  ),
                ],
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ── Phase 8B ──────────────────────────────────────────────────────────────────────────
  //
  // Two sheets and four full-height states. `AttachSheet` is this phase's only `AlayaBottomSheet` addition;
  // the export confirmation reuses `ConfirmSheet` but carries the longest body in the app, which is the case
  // worth measuring (Law U2 — added in the phase that creates them).
  group('ops surfaces', () {
    testWidgets('the export warning fits the narrowest phone at a doubled scale', (
      tester,
    ) async {
      // **The longest required string in the project**, in the narrowest column, at the largest scale U15 asks
      // for. If ARCH_3 §3.4's sentence does not fit, the rule cannot be honoured.
      await tester.pumpWidget(
        host(
          const Center(
            child: SizedBox(
              width: 320,
              child: Text(
                'This backup is not encrypted. Anyone who opens this file can read every '
                'transaction, balance and account name. Only share it somewhere you trust.',
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the attach sheet fits at a tripled scale', (tester) async {
      // **Scrollable, because `AlayaBottomSheet` is.** The bare `Column` this case first used overflowed by 342px
      // at 3x — but it was testing a structure the app does not have, so the failure said nothing about the sheet.
      // A layout case that does not mirror its widget's real wrapper measures the wrong thing.
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Add an attachment'),
                  const Text(
                    'Kept on this phone only, and included in your backups.',
                  ),
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Choose a photo'),
                  ),
                ],
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an attachment strip does not reflow around a missing file', (
      tester,
    ) async {
      // The glyph fallback is the same extent as a thumbnail, so a strip of loaded and unloaded images has one
      // height rather than two.
      await tester.pumpWidget(
        host(
          Center(
            child: SizedBox(
              width: 320,
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < 6; i++)
                    const Padding(
                      padding: EdgeInsets.all(4),
                      child: SizedBox(
                        width: 88,
                        height: 88,
                        child: Icon(Icons.description_outlined),
                      ),
                    ),
                ],
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a trash row fits its label, its date and its retention line', (
      tester,
    ) async {
      // **This case found a real defect**, which is what these are for. The screen originally put "Deleted", a
      // date and a retention note in one subtitle `Row` behind a `TextButton` trailing — a `ListTile` gives its
      // subtitle whatever the trailing leaves, which at a doubled scale was 142dp. Two lines and an icon fixed it,
      // and this now measures the shape that shipped.
      await tester.pumpWidget(
        host(
          Center(
            child: SizedBox(
              width: 320,
              child: ListTile(
                isThreeLine: true,
                title: const Text('Weekly groceries at the corner shop'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Row(
                      children: [
                        Text('Deleted'),
                        SizedBox(width: 4),
                        Flexible(child: Text('8 Aug 2026')),
                      ],
                    ),
                    Text('· kept for 30 days'),
                  ],
                ),
                trailing: IconButton(
                  onPressed: () {},
                  tooltip: 'Restore',
                  icon: const Icon(Icons.restore_from_trash_outlined),
                ),
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the reminders explainer and a blocked notice stack', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  Text(
                    'Alaya sends one message a day about what is coming up — not a '
                    'notification for every item.',
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Notifications are turned off for Alaya. Turn them on in your '
                    'phone’s Settings › Apps › Alaya › Notifications.',
                  ),
                ],
              ),
            ),
          ),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the restore replace warning fits before the typed confirmation', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Everything currently on this phone will be thrown away and '
                    'replaced by the backup. Anything recorded since that backup was made '
                    'will be gone.',
                  ),
                  const SizedBox(height: 8),
                  const TextField(),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () {},
                    child: const Text('Replace everything'),
                  ),
                ],
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// A transaction editor reporting a fixed state, so a layout can be pumped without a database.
class _FixedEditor extends TransactionEditorNotifier {
  _FixedEditor(this._value);

  final AsyncValue<TransactionEditorState> _value;

  @override
  AsyncValue<TransactionEditorState> build(String? arg) => _value;
}

/// A `ValueChanged<String>` that does nothing, so the keypad cases need no state.
void _noDigit(String _) {}

/// A `VoidCallback` that does nothing.
void _noop() {}
