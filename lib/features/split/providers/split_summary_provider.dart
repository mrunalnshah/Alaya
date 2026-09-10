/// The shareable summary (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/data/ports/split_share_port.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/features/split/providers/split_providers.dart';

/// Where the user's payment details are stored.
///
/// **Renamed from `split.upiId`, and the rename is the feature.** A UPI id is India's rail; the value
/// this key now holds is whatever a user anywhere writes down — a PayPal link, an IBAN, a Venmo
/// handle, "cash is fine". Naming the key after one country's payment system was what made the
/// original field impossible to generalise without a migration.
///
/// No migration accompanies the rename: the old key belonged to an unreleased module and a fallback
/// read for a value that existed for one session is more code than the data is worth.
const String splitPaymentHandleKey = 'split.paymentHandle';

/// The system share sheet.
final splitShareProvider = Provider<SplitSharePort>(
  (ref) => const SystemSplitShare(),
);

/// How people can pay the user, or null when they have not said.
///
/// Free text on purpose. The app makes no claim about how money moves, which is the only way one field
/// works in every country it might be installed in.
final splitPaymentHandleProvider = FutureProvider<String?>(
  (ref) =>
      ref.watch(settingsRepositoryProvider).readValue(splitPaymentHandleKey),
);

/// The balances a summary should cover: one group, or everything outstanding.
///
/// **Balances only — the summary itself is composed in the sheet.** `SplitSummaryBuilder` needs four
/// sentences from the ARB, and `AlayaStrings` needs a `BuildContext` that no provider has. A provider
/// gathers data; a widget adds copy.
final splitSummaryBalancesProvider =
    FutureProvider.family<List<SplitBalance>, String?>((ref, groupId) {
      return groupId == null
          ? ref.watch(splitBalancesProvider.future)
          : ref.watch(splitGroupBalancesProvider(groupId).future);
    });
