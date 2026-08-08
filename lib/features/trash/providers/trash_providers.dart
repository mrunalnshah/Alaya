/// View-model state for the trash screen (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/domain/services/trash/trash_port.dart';

/// Everything currently in the trash.
final trashProvider = StreamProvider<List<TrashEntry>>(
  (ref) => ref.watch(trashPortProvider).watchAll(),
);

/// Which kinds the user is filtering to, empty meaning all.
final trashFilterProvider =
    NotifierProvider<TrashFilterNotifier, Set<TrashKind>>(
      TrashFilterNotifier.new,
    );

/// Holds the active filter.
class TrashFilterNotifier extends Notifier<Set<TrashKind>> {
  @override
  Set<TrashKind> build() => const {};

  /// Adds or removes [kind].
  void toggle(TrashKind kind) {
    final next = {...state};
    next.contains(kind) ? next.remove(kind) : next.add(kind);
    state = next;
  }

  /// Clears the filter.
  void clear() => state = const {};
}

/// The trash after the active filter.
final filteredTrashProvider = Provider<List<TrashEntry>>((ref) {
  final all = ref.watch(trashProvider).valueOrNull ?? const <TrashEntry>[];
  final filter = ref.watch(trashFilterProvider);
  if (filter.isEmpty) return all;
  return [
    for (final entry in all)
      if (filter.contains(entry.kind)) entry,
  ];
});

/// Restoring and purging.
final trashControllerProvider =
    NotifierProvider<TrashController, AsyncValue<void>>(TrashController.new);

/// Runs the restore and the one hard delete.
class TrashController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// How many rows the last purge removed.
  int get lastPurged => _lastPurged;
  int _lastPurged = 0;

  /// Un-deletes an entry.
  Future<bool> restore(TrashEntry entry) async {
    state = const AsyncLoading<void>();
    final result = await ref.read(trashPortProvider).restore(entry);
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  /// Hard-deletes one entry.
  Future<bool> purge(TrashEntry entry) async {
    state = const AsyncLoading<void>();
    final result = await ref.read(trashPortProvider).purge(entry);
    _lastPurged = result.isOk ? 1 : 0;
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  /// Hard-deletes everything.
  Future<bool> purgeAll() async {
    state = const AsyncLoading<void>();
    final result = await ref.read(trashPortProvider).purgeAll();
    _lastPurged = result.valueOrNull ?? 0;
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  bool _settle(Object? failure) {
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }
}
