import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/stock_movement.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/services/inventory_consumption_service.dart';
import 'package:alaya/domain/services/low_stock_suggestion_engine.dart';
import 'package:alaya/domain/services/purchase_fan_out_service.dart';
import 'package:alaya/domain/services/stock_reconciler.dart';

/// FEFO consumption, reconciliation, low-stock idempotency and the purchase fan-out.
///
/// Every service under test is pure, so none of this touches a database or a mock.
void main() {
  const consumption = InventoryConsumptionService();
  const reconciler = StockReconciler();
  const suggestions = LowStockSuggestionEngine();
  const fanOut = PurchaseFanOutService();

  Qty grams(int g) => Qty(g * 1000, UnitCategory.weight);

  group('FEFO consumption', () {
    // The three batches exactly as specified, and deliberately in an order where neither the
    // nearest expiry nor the undated batch is first — so a service that trusted input order would
    // fail this.
    final batches = [
      ConsumableBatch(
        batchId: 'b_exp_10aug',
        remaining: grams(500),
        purchasedDateKey: DateKey.fromYmd(2026, 7, 15),
        expiryDateKey: DateKey.fromYmd(2026, 8, 10),
      ),
      ConsumableBatch(
        batchId: 'b_no_expiry',
        remaining: grams(1000),
        purchasedDateKey: DateKey.fromYmd(2026, 7, 1),
      ),
      ConsumableBatch(
        batchId: 'b_exp_05aug',
        remaining: grams(300),
        purchasedDateKey: DateKey.fromYmd(2026, 7, 20),
        expiryDateKey: DateKey.fromYmd(2026, 8, 5),
      ),
    ];

    test('consuming 600 g draws 300 from 05 Aug then 300 from 10 Aug', () {
      final result = consumption.plan(batches: batches, needed: grams(600));

      expect(result.isFailure, isFalse);
      final plan = result.valueOrNull!;

      expect(plan.draws.map((d) => d.batchId).toList(), [
        'b_exp_05aug',
        'b_exp_10aug',
      ], reason: 'nearest expiry first');
      expect(
        plan.draws[0].quantity,
        grams(300),
        reason: 'the 05 Aug batch is drained',
      );
      expect(
        plan.draws[1].quantity,
        grams(300),
        reason: 'the balance comes from 10 Aug',
      );
    });

    test('the no-expiry batch is left untouched', () {
      final plan = consumption
          .plan(batches: batches, needed: grams(600))
          .valueOrNull!;

      expect(
        plan.touchedBatchIds,
        isNot(contains('b_no_expiry')),
        reason:
            'undated stock cannot spoil on a deadline, so dated stock goes first (A08)',
      );
    });

    test('exactly two movement rows', () {
      final plan = consumption
          .plan(batches: batches, needed: grams(600))
          .valueOrNull!;

      // One movement per draw, which is the 1:1 mapping `StockRepository.consume` applies.
      expect(plan.movementCount, 2);
      expect(plan.draws, hasLength(2));
    });

    test('the draws sum to exactly what was asked for', () {
      final plan = consumption
          .plan(batches: batches, needed: grams(600))
          .valueOrNull!;
      final total = plan.draws.fold<int>(
        0,
        (sum, d) => sum + d.quantity.milliBase,
      );

      expect(total, grams(600).milliBase);
    });

    test('ordering puts undated last regardless of input order', () {
      final ordered = consumption.orderFefo(batches);

      expect(ordered.map((b) => b.batchId).toList(), [
        'b_exp_05aug',
        'b_exp_10aug',
        'b_no_expiry',
      ]);
    });

    test('a batch holding nothing never produces a movement', () {
      final withEmpty = [
        ConsumableBatch(
          batchId: 'b_empty',
          remaining: grams(0),
          purchasedDateKey: DateKey.fromYmd(2026, 1, 1),
          expiryDateKey: DateKey.fromYmd(2026, 1, 2),
        ),
        ...batches,
      ];

      final plan = consumption
          .plan(batches: withEmpty, needed: grams(100))
          .valueOrNull!;

      expect(
        plan.touchedBatchIds,
        isNot(contains('b_empty')),
        reason:
            'stock_movements has CHECK (quantity_milli > 0), and a zero movement is noise',
      );
      expect(plan.draws.single.batchId, 'b_exp_05aug');
    });

    test(
      'consuming exactly one batch\'s remaining does not spill into the next',
      () {
        final plan = consumption
            .plan(batches: batches, needed: grams(300))
            .valueOrNull!;

        expect(plan.draws, hasLength(1));
        expect(plan.draws.single.batchId, 'b_exp_05aug');
      },
    );

    test('draining everything touches all three, undated last', () {
      final plan = consumption
          .plan(batches: batches, needed: grams(1800))
          .valueOrNull!;

      expect(plan.draws.map((d) => d.batchId).toList(), [
        'b_exp_05aug',
        'b_exp_10aug',
        'b_no_expiry',
      ]);
      expect(plan.movementCount, 3);
    });

    group('consuming more than total stock', () {
      test('fails rather than partially consuming', () {
        // One milli-gram beyond the 1800 g on hand.
        final result = consumption.plan(
          batches: batches,
          needed: Qty(grams(1800).milliBase + 1, UnitCategory.weight),
        );

        expect(result.isFailure, isTrue);
        expect(result.failureOrNull, isA<BusinessRuleFailure>());
        expect(
          (result.failureOrNull! as BusinessRuleFailure).rule,
          'insufficientStock',
        );
      });

      test('and produces NO draws at all, so no partial write is possible', () {
        final result = consumption.plan(batches: batches, needed: grams(5000));

        expect(
          result.valueOrNull,
          isNull,
          reason:
              'a half-applied consumption describes something that did not happen',
        );
      });

      test('an empty inventory fails the same way', () {
        final result = consumption.plan(batches: const [], needed: grams(1));

        expect(result.isFailure, isTrue);
      });
    });

    test('a zero or negative request is rejected before anything else', () {
      expect(
        consumption.plan(batches: batches, needed: grams(0)).isFailure,
        isTrue,
      );
      expect(
        consumption
            .plan(batches: batches, needed: Qty(-1000, UnitCategory.weight))
            .isFailure,
        isTrue,
      );
    });

    test('a cross-category request is refused, not converted (L8)', () {
      final result = consumption.plan(
        batches: batches,
        needed: Qty(600000, UnitCategory.volume),
      );

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<ValidationFailure>());
    });
  });

  group('stock reconciliation', () {
    StockMovement movement(StockMovementKind kind, int g) => StockMovement(
      id: 'm-${kind.name}-$g',
      batchId: 'b1',
      itemId: 'potato',
      kind: kind,
      quantity: grams(g),
      occurredAtUtc: DateTime.utc(2026, 7, 20),
      dateKey: DateKey.fromYmd(2026, 7, 20),
    );

    test('a consistent batch shows zero discrepancy', () {
      final result = reconciler.reconcile(
        batchId: 'b1',
        cached: grams(1700),
        movements: [
          movement(StockMovementKind.openingIn, 2000),
          movement(StockMovementKind.consume, 300),
        ],
      );

      expect(result.fromLedger, grams(1700));
      expect(result.discrepancy, grams(0));
      expect(result.isConsistent, isTrue);
    });

    test('a consume that never updated the cache is detected', () {
      final result = reconciler.reconcile(
        batchId: 'b1',
        cached: grams(2000),
        movements: [
          movement(StockMovementKind.openingIn, 2000),
          movement(StockMovementKind.consume, 300),
        ],
      );

      expect(result.fromLedger, grams(1700));
      expect(result.discrepancy, grams(300));
      expect(result.isConsistent, isFalse);
    });

    test('waste and expired both reduce stock', () {
      final ledger = reconciler.remainingFromLedgerMilli([
        movement(StockMovementKind.openingIn, 1000),
        movement(StockMovementKind.waste, 250),
        movement(StockMovementKind.expired, 250),
      ]);

      expect(ledger, grams(500).milliBase);
    });

    test('a reversal cancels the movement it points at', () {
      final ledger = reconciler.remainingFromLedgerMilli([
        movement(StockMovementKind.openingIn, 1000),
        movement(StockMovementKind.consume, 200),
        movement(StockMovementKind.adjustIn, 200),
      ]);

      expect(
        ledger,
        grams(1000).milliBase,
        reason: 'summing with the opposite sign is all a reversal needs to do',
      );
    });

    test('a cache BELOW the ledger is a discrepancy too', () {
      final result = reconciler.reconcile(
        batchId: 'b1',
        cached: grams(500),
        movements: [movement(StockMovementKind.openingIn, 1000)],
      );

      expect(
        result.isConsistent,
        isFalse,
        reason: 'hiding stock the user has is the harder error to notice',
      );
      expect(result.discrepancy.milliBase, lessThan(0));
    });

    test(
      'every incoming kind is classified as incoming, every outgoing as outgoing',
      () {
        const incoming = [
          StockMovementKind.openingIn,
          StockMovementKind.purchaseIn,
          StockMovementKind.manualIn,
          StockMovementKind.adjustIn,
        ];
        const outgoing = [
          StockMovementKind.consume,
          StockMovementKind.waste,
          StockMovementKind.expired,
          StockMovementKind.adjustOut,
        ];

        // Exhaustive: if a kind is ever added, this fails until it is classified, which is the point.
        expect({
          ...incoming,
          ...outgoing,
        }, hasLength(StockMovementKind.values.length));
        for (final kind in incoming) {
          expect(reconciler.isIncoming(kind), isTrue, reason: kind.name);
        }
        for (final kind in outgoing) {
          expect(reconciler.isIncoming(kind), isFalse, reason: kind.name);
        }
      },
    );

    test('a summary reports the worst offender', () {
      final summary = reconciler.summarise([
        reconciler.reconcile(
          batchId: 'ok',
          cached: grams(100),
          movements: [movement(StockMovementKind.openingIn, 100)],
        ),
        reconciler.reconcile(
          batchId: 'small',
          cached: grams(110),
          movements: [movement(StockMovementKind.openingIn, 100)],
        ),
        reconciler.reconcile(
          batchId: 'big',
          cached: grams(900),
          movements: [movement(StockMovementKind.openingIn, 100)],
        ),
      ]);

      expect(summary.batchesChecked, 3);
      expect(summary.batchesNeedingRepair, 2);
      expect(summary.largestDiscrepancy, grams(800));
      expect(summary.isHealthy, isFalse);
    });
  });

  group('low-stock suggestion idempotency', () {
    final today = DateKey.fromYmd(2026, 7, 28);

    ItemStock lowPotato({int remainingG = 2500, int thresholdG = 3000}) =>
        ItemStock(
          itemId: 'potato',
          totalRemaining: grams(remainingG),
          batchCount: 1,
          isLowStock: true,
          lowStockThreshold: grams(thresholdG),
        );

    ShoppingEntry autoEntry({
      String id = 'e1',
      ShoppingEntryOrigin origin = ShoppingEntryOrigin.autoLowStock,
      ShoppingEntryAutoState autoState = ShoppingEntryAutoState.active,
      int? stockAtGenerationG,
      DateKey? snoozeUntil,
    }) => ShoppingEntry(
      id: id,
      listId: 'L',
      origin: origin,
      autoState: autoState,
      isChecked: false,
      sortOrder: 0,
      itemId: 'potato',
      quantity: grams(500),
      stockAtGeneration: stockAtGenerationG == null
          ? null
          : grams(stockAtGenerationG),
      snoozeUntilDateKey: snoozeUntil,
    );

    test('running generation five times yields exactly one entry', () {
      // The engine is pure, so "running it five times" means: create once, then refresh — never a
      // second create. Simulated by feeding back the entry the previous run would have written.
      final existing = <ShoppingEntry>[];
      final actions = <SuggestionAction>[];

      for (var run = 0; run < 5; run++) {
        final decisions = suggestions.decide(
          lowStock: [lowPotato()],
          existingAutoEntries: existing,
          today: today,
        );
        final decision = decisions.single;
        actions.add(decision.action);

        if (decision.action == SuggestionAction.create) {
          existing.add(autoEntry(stockAtGenerationG: 2500));
        }
      }

      expect(actions.first, SuggestionAction.create);
      expect(
        actions.skip(1),
        everyElement(SuggestionAction.refresh),
        reason: 'runs 2-5 must refresh in place, never create again',
      );
      expect(
        existing,
        hasLength(1),
        reason: 'exactly ONE auto entry after five runs',
      );
    });

    test('the suggested quantity is the shortfall against the threshold', () {
      final decision = suggestions
          .decide(
            lowStock: [lowPotato()],
            existingAutoEntries: const [],
            today: today,
          )
          .single;

      expect(
        decision.suggestedQuantity,
        grams(500),
        reason: '3000 threshold - 2500 on hand',
      );
      expect(decision.stockAtDecision, grams(2500));
    });

    test('after the user edits it, regeneration does not touch it', () {
      // Editing promotes origin to manual — that is what ShoppingRepository.saveEntry does.
      final edited = autoEntry(
        origin: ShoppingEntryOrigin.manual,
        stockAtGenerationG: 2500,
      );

      final decision = suggestions
          .decide(
            lowStock: [lowPotato()],
            existingAutoEntries: [edited],
            today: today,
          )
          .single;

      expect(decision.action, SuggestionAction.leaveAlone);
      expect(
        decision.suggestedQuantity,
        isNull,
        reason:
            'nothing is suggested, so nothing can overwrite the user\'s quantity',
      );
      expect(decision.reason, contains('user'));
    });

    test('an item no longer low is left alone', () {
      final decision = suggestions
          .decide(
            lowStock: [
              ItemStock(
                itemId: 'potato',
                totalRemaining: grams(4000),
                batchCount: 1,
                isLowStock: false,
                lowStockThreshold: grams(3000),
              ),
            ],
            existingAutoEntries: const [],
            today: today,
          )
          .single;

      expect(decision.action, SuggestionAction.leaveAlone);
    });

    test('an item with no threshold is never suggested', () {
      final decision = suggestions
          .decide(
            lowStock: [
              ItemStock(
                itemId: 'salt',
                totalRemaining: grams(10),
                batchCount: 1,
                isLowStock: false,
              ),
            ],
            existingAutoEntries: const [],
            today: today,
          )
          .single;

      expect(decision.action, SuggestionAction.leaveAlone);
    });

    group('dismissal is not a timer', () {
      test('dismissed and stock unchanged stays suppressed', () {
        final decision = suggestions
            .decide(
              lowStock: [lowPotato()],
              existingAutoEntries: [
                autoEntry(
                  autoState: ShoppingEntryAutoState.dismissed,
                  stockAtGenerationG: 2500,
                ),
              ],
              today: today,
            )
            .single;

        expect(decision.action, SuggestionAction.leaveAlone);
      });

      test('dismissed and stock fell FURTHER still stays suppressed', () {
        final decision = suggestions
            .decide(
              lowStock: [lowPotato(remainingG: 1000)],
              existingAutoEntries: [
                autoEntry(
                  autoState: ShoppingEntryAutoState.dismissed,
                  stockAtGenerationG: 2500,
                ),
              ],
              today: today,
            )
            .single;

        expect(
          decision.action,
          SuggestionAction.leaveAlone,
          reason:
              'they said no to this shortage; a worse one is the same shortage',
        );
      });

      test(
        'restocked above the dismissal reading, then low again, brings it back',
        () {
          final decision = suggestions
              .decide(
                lowStock: [lowPotato(remainingG: 2800)],
                existingAutoEntries: [
                  autoEntry(
                    autoState: ShoppingEntryAutoState.dismissed,
                    stockAtGenerationG: 2500,
                  ),
                ],
                today: today,
              )
              .single;

          expect(
            decision.action,
            SuggestionAction.refresh,
            reason:
                'stock rose above 2500, so they bought some and ran low again',
          );
        },
      );

      test('a snooze still in force suppresses', () {
        final decision = suggestions
            .decide(
              lowStock: [lowPotato()],
              existingAutoEntries: [
                autoEntry(
                  autoState: ShoppingEntryAutoState.snoozed,
                  stockAtGenerationG: 2500,
                  snoozeUntil: DateKey.fromYmd(2026, 8, 5),
                ),
              ],
              today: today,
            )
            .single;

        expect(decision.action, SuggestionAction.leaveAlone);
      });

      test('an expired snooze returns, because a snooze IS a timer', () {
        final decision = suggestions
            .decide(
              lowStock: [lowPotato()],
              existingAutoEntries: [
                autoEntry(
                  autoState: ShoppingEntryAutoState.snoozed,
                  stockAtGenerationG: 2500,
                  snoozeUntil: DateKey.fromYmd(2026, 7, 20),
                ),
              ],
              today: today,
            )
            .single;

        expect(decision.action, SuggestionAction.refresh);
      });
    });
  });

  group('purchase fan-out', () {
    final transaction = Transaction(
      id: 't1',
      kind: TransactionKind.withdrawal,
      subtype: TransactionSubtype.electronics,
      occurredAtUtc: DateTime.utc(2026, 7, 28),
      dateKey: DateKey.fromYmd(2026, 7, 28),
      originalAmount: const Money(4500000, 'INR'),
      needsReview: false,
      fromAccountId: 'bank',
    );

    TransactionLine line({
      required TransactionLineDestination destination,
      String description = 'LG 55 inch TV',
      String? itemId,
      Qty? quantity,
      Money? lineAmount = const Money(4500000, 'INR'),
      // A line bound for inventory must name a unit: `unit_code_at_purchase` is a foreign key into
      // `units`, and `_planBatch` refuses a null rather than defaulting it to `''` and failing later
      // as `FOREIGN KEY constraint failed`.
      String? unitCode = 'pc',
    }) => TransactionLine(
      id: 'l1',
      transactionId: 't1',
      lineNo: 1,
      description: description,
      destination: destination,
      itemId: itemId,
      quantity: quantity,
      unitCode: unitCode,
      lineAmount: lineAmount,
    );

    test('destination=asset creates an Asset and NO batch', () {
      final plan = fanOut
          .plan(
            line: line(destination: TransactionLineDestination.asset),
            transaction: transaction,
            newArtefactId: 'a1',
          )
          .valueOrNull!;

      expect(plan.target, FanOutTarget.asset);
      expect(plan.asset, isNotNull);
      expect(
        plan.batch,
        isNull,
        reason:
            'a television is serviced and warrantied, not consumed in portions (A12)',
      );
      expect(plan.isWellFormed, isTrue);
    });

    test(
      'the created asset carries the line back, so createdAssetId can be written',
      () {
        final plan = fanOut
            .plan(
              line: line(destination: TransactionLineDestination.asset),
              transaction: transaction,
              newArtefactId: 'a1',
            )
            .valueOrNull!;

        expect(
          plan.lineId,
          'l1',
          reason: 'the caller writes createdAssetId back to this line',
        );
        expect(plan.asset!.id, 'a1');
        expect(plan.asset!.sourceTransactionLineId, 'l1');
        expect(plan.asset!.name, 'LG 55 inch TV');
        expect(plan.asset!.purchasePrice, const Money(4500000, 'INR'));
        expect(plan.asset!.purchaseDateKey, DateKey.fromYmd(2026, 7, 28));
      },
    );

    test('a line bound for inventory with no unit is refused, not defaulted', () {
      // The empty-string default turned a missing value into `FOREIGN KEY constraint failed` several
      // layers away, after the transaction had already committed (ARCH_4 R30's family).
      final result = fanOut.plan(
        line: line(
          destination: TransactionLineDestination.inventory,
          itemId: 'i1',
          quantity: const Qty(2000, UnitCategory.count),
          unitCode: null,
        ),
        transaction: transaction,
        newArtefactId: 'b1',
      );
      expect(result.isFailure, isTrue);
      expect(result.failureOrNull!.message, contains('no unit'));
    });

    test('destination=inventory creates a Batch and NO asset', () {
      final plan = fanOut
          .plan(
            line: line(
              destination: TransactionLineDestination.inventory,
              description: 'Potatoes',
              itemId: 'potato',
              quantity: grams(2000),
            ),
            transaction: transaction,
            newArtefactId: 'b1',
          )
          .valueOrNull!;

      expect(plan.target, FanOutTarget.batch);
      expect(plan.batch, isNotNull);
      expect(plan.asset, isNull);
      expect(plan.batch!.initialQuantity, grams(2000));
      expect(
        plan.batch!.remainingQuantity,
        grams(2000),
        reason:
            'nothing consumed yet, and BatchRepository.create requires this',
      );
      expect(plan.batch!.origin, BatchOrigin.purchase);
      expect(plan.batch!.sourceTransactionLineId, 'l1');
    });

    test('destination=none creates nothing', () {
      final plan = fanOut
          .plan(
            line: line(
              destination: TransactionLineDestination.none,
              description: 'Service fee',
            ),
            transaction: transaction,
            newArtefactId: 'x1',
          )
          .valueOrNull!;

      expect(plan.createsArtefact, isFalse);
      expect(plan.batch, isNull);
      expect(plan.asset, isNull);
      expect(plan.isWellFormed, isTrue);
    });

    test(
      'destination=recurring names a template but does not invent a schedule',
      () {
        final plan = fanOut
            .plan(
              line: line(
                destination: TransactionLineDestination.recurring,
                description: 'Netflix',
              ),
              transaction: transaction,
              newArtefactId: 'r1',
            )
            .valueOrNull!;

        expect(plan.target, FanOutTarget.recurringTemplate);
        expect(plan.recurringTemplateName, 'Netflix');
        expect(plan.batch, isNull);
        expect(plan.asset, isNull);
      },
    );

    test('an inventory line without an item is refused', () {
      final result = fanOut.plan(
        line: line(
          destination: TransactionLineDestination.inventory,
          quantity: grams(100),
        ),
        transaction: transaction,
        newArtefactId: 'b1',
      );

      expect(result.isFailure, isTrue);
    });

    test(
      'an inventory line without a quantity is refused rather than guessed',
      () {
        final result = fanOut.plan(
          line: line(
            destination: TransactionLineDestination.inventory,
            itemId: 'potato',
          ),
          transaction: transaction,
          newArtefactId: 'b1',
        );

        expect(
          result.isFailure,
          isTrue,
          reason:
              'a batch with a guessed quantity is stock the user never bought',
        );
      },
    );

    test(
      'planAll skips lines that already produced an artefact, so a retry is safe',
      () {
        final lines = [
          TransactionLine(
            id: 'l1',
            transactionId: 't1',
            lineNo: 1,
            description: 'Already done',
            destination: TransactionLineDestination.asset,
            createdAssetId: 'a-existing',
          ),
          line(
            destination: TransactionLineDestination.asset,
            description: 'New TV',
          ),
        ];

        final plans = fanOut
            .planAll(
              lines: lines,
              transaction: transaction,
              newArtefactIds: ['x', 'a2'],
            )
            .valueOrNull!;

        expect(plans, hasLength(1));
        expect(plans.single.asset!.name, 'New TV');
      },
    );
  });
}
