/// A value that is either a success [T] or a failure [F], forcing callers to handle both
/// paths explicitly instead of relying on a thrown exception for an expected, recoverable
/// outcome (e.g. a malformed amount the user is still typing).
sealed class Result<T, F> {
  const Result();

  /// A successful result wrapping [value].
  const factory Result.ok(T value) = Ok<T, F>;

  /// A failed result wrapping [failure].
  const factory Result.failure(F failure) = Err<T, F>;

  /// True if this is a success.
  bool get isOk => this is Ok<T, F>;

  /// True if this is a failure.
  bool get isFailure => this is Err<T, F>;

  /// The success value, or `null` if this is a failure.
  T? get valueOrNull => switch (this) {
    Ok<T, F>(:final value) => value,
    Err<T, F>() => null,
  };

  /// The failure, or `null` if this is a success.
  F? get failureOrNull => switch (this) {
    Err<T, F>(:final failure) => failure,
    Ok<T, F>() => null,
  };

  /// Transforms a success value with [transform]; a failure passes through unchanged.
  Result<R, F> map<R>(R Function(T value) transform) => switch (this) {
    Ok<T, F>(:final value) => Result.ok(transform(value)),
    Err<T, F>(:final failure) => Result.failure(failure),
  };

  /// Transforms a failure with [transform]; a success passes through unchanged.
  Result<T, R> mapFailure<R>(R Function(F failure) transform) => switch (this) {
    Ok<T, F>(:final value) => Result.ok(value),
    Err<T, F>(:final failure) => Result.failure(transform(failure)),
  };

  /// Reduces both branches to a single value of type [R].
  R fold<R>(R Function(T value) onOk, R Function(F failure) onFailure) => switch (this) {
    Ok<T, F>(:final value) => onOk(value),
    Err<T, F>(:final failure) => onFailure(failure),
  };
}

/// The success branch of a [Result].
final class Ok<T, F> extends Result<T, F> {
  /// Wraps a successful [value].
  const Ok(this.value);

  /// The success payload.
  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T, F> && other.value == value;

  @override
  int get hashCode => Object.hash(Ok, value);

  @override
  String toString() => 'Ok($value)';
}

/// The failure branch of a [Result].
final class Err<T, F> extends Result<T, F> {
  /// Wraps a [failure].
  const Err(this.failure);

  /// The failure payload.
  final F failure;

  @override
  bool operator ==(Object other) => other is Err<T, F> && other.failure == failure;

  @override
  int get hashCode => Object.hash(Err, failure);

  @override
  String toString() => 'Err($failure)';
}