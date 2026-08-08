/// The recurring bills a payment can settle (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/domain/repositories/recurring_repository.dart';

/// Outflow templates with an occurrence outstanding today, soonest first.
///
/// **`watchDue()` was built in Phase 3A and used nowhere until now.** It already excludes paused and
/// ended templates and picks each one's soonest outstanding occurrence, which is exactly the read the
/// bill form needs — reimplementing that filter over `watchAllTemplates` would have been a second
/// definition of "due" to keep in step.
final dueBillsProvider = StreamProvider.autoDispose<List<RecurringDue>>(
  (ref) => ref
      .watch(recurringRepositoryProvider)
      .watchDue()
      .map(
        (all) =>
            [
              for (final due in all)
                if (due.template.direction == RecurringDirection.outflow &&
                    due.occurrence != null)
                  due,
            ]..sort(
              (a, b) =>
                  a.occurrence!.dueDateKey.compareTo(b.occurrence!.dueDateKey),
            ),
      ),
);
