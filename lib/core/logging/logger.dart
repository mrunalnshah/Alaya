import 'dart:developer' as developer;

/// Severity levels for [Logger] output, ordered from least to most severe.
enum LogLevel {
  /// Verbose, developer-only detail.
  debug,

  /// Routine, expected events.
  info,

  /// Something unexpected happened but the app can continue normally.
  warning,

  /// An operation failed and could not recover on its own.
  error,
}

/// A minimal, injectable logging facade so call sites never depend on `dart:developer`
/// directly, and tests can capture or silence output.
abstract interface class Logger {
  /// Records [message] at [level], with an optional [error]/[stackTrace] pair and a [tag]
  /// identifying which subsystem logged it.
  void log(
      String message, {
        LogLevel level = LogLevel.info,
        String? tag,
        Object? error,
        StackTrace? stackTrace,
      });
}

/// The production [Logger]: writes to `dart:developer`'s `log()`, so output is visible in
/// DevTools and `flutter logs` without adding a third-party logging package.
final class DeveloperLogger implements Logger {
  /// Creates a logger that writes via `dart:developer`.
  const DeveloperLogger();

  @override
  void log(
      String message, {
        LogLevel level = LogLevel.info,
        String? tag,
        Object? error,
        StackTrace? stackTrace,
      }) {
    developer.log(
      message,
      name: tag ?? 'alaya',
      level: _severity(level),
      error: error,
      stackTrace: stackTrace,
    );
  }

  static int _severity(LogLevel level) => switch (level) {
    LogLevel.debug => 500,
    LogLevel.info => 800,
    LogLevel.warning => 900,
    LogLevel.error => 1000,
  };
}

/// A [Logger] that discards everything. Useful as a default in tests that don't care about
/// log output but still need to inject something.
final class NoopLogger implements Logger {
  /// Creates a logger that discards everything it's given.
  const NoopLogger();

  @override
  void log(
      String message, {
        LogLevel level = LogLevel.info,
        String? tag,
        Object? error,
        StackTrace? stackTrace,
      }) {}
}