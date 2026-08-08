import 'package:alaya/app/bootstrap.dart';

/// The Android entry point.
///
/// Deliberately empty of logic. Everything that could fail — opening the database, building the
/// provider graph — lives in `bootstrap` where it can be exercised by a test without a platform
/// binding hard-coded into `main`.
///
/// Returns the future rather than dropping it: a discarded future's error goes nowhere, so a failure
/// to open the database would present as a blank screen with nothing in the log naming the cause.
Future<void> main() => bootstrap();
