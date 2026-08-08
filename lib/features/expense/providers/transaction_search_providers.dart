/// Full-text search over transaction notes, kept separate from the filter providers.
///
/// A different concern with a different shape: the filter narrows a live stream, search resolves a
/// one-shot query against FTS5. Folding them into one provider would mean a stream that sometimes
/// is not one.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/transaction.dart';

/// The current search query, empty when the user is not searching.
final transactionSearchQueryProvider =
    NotifierProvider<TransactionSearchQueryNotifier, String>(
      TransactionSearchQueryNotifier.new,
    );

/// Holds the search box's settled query.
class TransactionSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  /// Replaces the query. Already debounced by `AlayaSearchField`.
  void set(String query) => state = query;

  /// Clears the query, returning the list to its filtered view.
  void clear() => state = '';
}

/// Whether the list is showing search results rather than the filtered window.
final isSearchingProvider = Provider<bool>(
  (ref) => ref.watch(transactionSearchQueryProvider).isNotEmpty,
);

/// Search results for the current query, best match first.
///
/// Capped rather than unbounded: FTS over ten thousand notes can match most of them, and a list the
/// user has to scroll for a minute is not a search result.
final transactionSearchResultsProvider = FutureProvider<List<Transaction>>((
  ref,
) async {
  final query = ref.watch(transactionSearchQueryProvider);
  if (query.isEmpty) return const <Transaction>[];
  return ref.watch(transactionRepositoryProvider).search(query, limit: 100);
});
