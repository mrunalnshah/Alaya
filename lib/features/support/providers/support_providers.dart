/// View-model state for the Support screen (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/domain/services/support/support_port.dart';

/// What the Support screen is holding.
class SupportState {
  /// Creates a state.
  const SupportState({
    this.isReady = false,
    this.isWorking = false,
    this.consent = AdConsent.required,
    this.adLoaded = false,
    this.products = const [],
    this.thanksShown = false,
    this.failureMessage,
  });

  /// Whether the SDKs have been brought up.
  ///
  /// **False until the screen asks**, which is the whole design: nothing initialises anywhere else.
  final bool isReady;

  /// Whether something is in flight.
  final bool isWorking;

  /// Where consent stands.
  final AdConsent consent;

  /// Whether an advert is ready to show.
  final bool adLoaded;

  /// The tip products the store offers.
  final List<TipProduct> products;

  /// Whether the thank-you has been shown for this visit.
  final bool thanksShown;

  /// The adapter's own message from the last failure (Law U9).
  final String? failureMessage;

  /// A copy with the given fields replaced.
  SupportState copyWith({
    bool? isReady,
    bool? isWorking,
    AdConsent? consent,
    bool? adLoaded,
    List<TipProduct>? products,
    bool? thanksShown,
    String? failureMessage,
    bool clearFailure = false,
  }) => SupportState(
    isReady: isReady ?? this.isReady,
    isWorking: isWorking ?? this.isWorking,
    consent: consent ?? this.consent,
    adLoaded: adLoaded ?? this.adLoaded,
    products: products ?? this.products,
    thanksShown: thanksShown ?? this.thanksShown,
    failureMessage: clearFailure
        ? null
        : (failureMessage ?? this.failureMessage),
  );
}

/// What a one-tap watch ended in.
///
/// Four outcomes rather than a bool, because three of them need different words and one needs silence. A
/// dismissed advert is not a failure — collapsing it into one would either thank somebody who watched nothing or
/// show them an error for changing their mind.
enum SupportWatchOutcome {
  /// Watched through; the reward callback fired.
  rewarded,

  /// Dismissed part way. Not a failure.
  dismissed,

  /// Nothing was available to show.
  unavailable,

  /// Consent could not be settled, so no advert was requested at all.
  blocked,
}

/// The Support screen's state.
final supportProvider = NotifierProvider<SupportController, SupportState>(
  SupportController.new,
);

/// Brings the SDKs up on demand, settles consent, then loads.
class SupportController extends Notifier<SupportState> {
  @override
  SupportState build() => const SupportState();

  /// Called from the screen's `initState`, and from nowhere else in the app.
  ///
  /// **Consent is settled before any ad is requested.** Requesting first and asking afterwards is what gets an
  /// app pulled in the EEA, and the ordering here is the only thing preventing it.
  Future<void> start() async {
    if (state.isReady) return;
    state = state.copyWith(isWorking: true, clearFailure: true);
    final port = ref.read(supportPortProvider);

    final ready = await port.initialise();
    if (ready.isFailure) {
      state = state.copyWith(
        isWorking: false,
        failureMessage: ready.failureOrNull?.message,
      );
      return;
    }

    var consent = await port.consentStatus();
    if (consent == AdConsent.required) consent = await port.requestConsent();

    final products = await port.tipProducts();
    state = state.copyWith(
      isReady: true,
      isWorking: false,
      consent: consent,
      products: products.valueOrNull ?? const [],
    );

    // An advert is only fetched once consent is settled — and never when it could not be.
    if (consent == AdConsent.obtained || consent == AdConsent.notRequired) {
      await loadAd();
    }
  }

  /// Fetches an advert.
  Future<void> loadAd() async {
    state = state.copyWith(isWorking: true, clearFailure: true);
    final result = await ref.read(supportPortProvider).loadRewardedAd();
    state = state.copyWith(
      isWorking: false,
      adLoaded: result.isOk,
      failureMessage: result.isFailure ? result.failureOrNull?.message : null,
    );
  }

  /// Shows the advert and records whether it was watched through.
  Future<bool> watchAd() async {
    state = state.copyWith(isWorking: true, clearFailure: true);
    final result = await ref.read(supportPortProvider).showRewardedAd();
    final earned = result.valueOrNull ?? false;
    state = state.copyWith(
      isWorking: false,
      adLoaded: false,
      thanksShown: earned,
      // Dismissing halfway is not a failure — somebody who changes their mind has done nothing wrong.
      failureMessage: result.isFailure ? result.failureOrNull?.message : null,
    );
    return earned;
  }

  /// Initialise, settle consent, load and show — in one action, on demand.
  ///
  /// **Written for the app bar button, and the ordering is the whole point.** Nothing here runs until it is
  /// called, so a user who never taps the button never has an advertising identifier collected. A pre-loaded
  /// button would feel faster and would give that away on every app open.
  ///
  /// Safe to call from anywhere: `initialise()` is idempotent, and consent is only fetched once per session.
  Future<SupportWatchOutcome> watchNow() async {
    state = state.copyWith(isWorking: true, clearFailure: true);
    final port = ref.read(supportPortProvider);

    final ready = await port.initialise();
    if (ready.isFailure) {
      state = state.copyWith(
        isWorking: false,
        failureMessage: ready.failureOrNull?.message,
      );
      return SupportWatchOutcome.unavailable;
    }

    var consent = await port.consentStatus();
    if (consent == AdConsent.required) consent = await port.requestConsent();
    if (consent != AdConsent.obtained && consent != AdConsent.notRequired) {
      // No advert is requested when consent could not be settled. Asking afterwards is what gets an app pulled
      // in the EEA.
      state = state.copyWith(isWorking: false, consent: consent);
      return SupportWatchOutcome.blocked;
    }

    final loaded = await port.loadRewardedAd();
    if (loaded.isFailure) {
      state = state.copyWith(
        isWorking: false,
        consent: consent,
        failureMessage: loaded.failureOrNull?.message,
      );
      return SupportWatchOutcome.unavailable;
    }

    final shown = await port.showRewardedAd();
    final earned = shown.valueOrNull ?? false;
    state = state.copyWith(
      isWorking: false,
      consent: consent,
      adLoaded: false,
      thanksShown: earned,
      failureMessage: shown.isFailure ? shown.failureOrNull?.message : null,
    );
    if (shown.isFailure) return SupportWatchOutcome.unavailable;
    return earned
        ? SupportWatchOutcome.rewarded
        : SupportWatchOutcome.dismissed;
  }

  /// Starts the one-time tip purchase.
  Future<bool> tip(String productId) async {
    state = state.copyWith(isWorking: true, clearFailure: true);
    final result = await ref.read(supportPortProvider).buyTip(productId);
    final ok = result.valueOrNull ?? false;
    state = state.copyWith(
      isWorking: false,
      thanksShown: ok,
      failureMessage: result.isFailure ? result.failureOrNull?.message : null,
    );
    return ok;
  }
}
