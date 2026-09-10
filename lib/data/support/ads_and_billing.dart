import 'dart:async';

import 'package:flutter/foundation.dart' show kReleaseMode;

import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/services/support/support_port.dart';

/// The production [SupportPort], over `google_mobile_ads` and `in_app_purchase`.
///
/// **The only file in the project that imports either SDK.** That is the enforcement of "the rest of the app
/// makes zero ad calls": not a rule anybody has to remember, but the fact that no other file can make one. A
/// grep for `google_mobile_ads` returning exactly this path is the check, and it is cheap to run.
///
/// **Nothing initialises at construction.** [initialise] is called by the Support screen's `initState` and by
/// nothing else, so an install where nobody opens that screen never starts the SDK, never fetches a consent
/// form, and never collects an advertising identifier.
///
/// Both plugin surfaces are ARCH_4 R22 exposure and neither could be compiled against: `MobileAds.instance`,
/// `ConsentInformation`, `RewardedAd.load` and `InAppPurchase.instance` have all moved between majors. 8A's
/// `local_auth` needed three attempts; expect the same here, and expect it to cost this file alone.
final class AdsAndBilling implements SupportPort {
  /// Creates the adapter.
  AdsAndBilling();

  /// Google's public test unit. Always used in debug builds.
  static const String rewardedTestUnitId =
      'ca-app-pub-3940256099942544/5224354917';

  /// The live rewarded unit, used in release builds only.
  static const String rewardedLiveUnitId =
      'ca-app-pub-3214315776823567/6343130187';

  /// Whichever of the two this build should request.
  ///
  /// **Chosen by `kReleaseMode`, not by remembering to swap a constant.** A debug build serving live adverts is
  /// how an AdMob account gets flagged for invalid traffic, and the appeal is slow — so the guarantee is
  /// structural rather than a discipline. The App ID has the same split, through `manifestPlaceholders` in
  /// `app/build.gradle.kts`, because a manifest cannot read `kReleaseMode`.
  ///
  /// Register your device under **AdMob → Settings → Test devices** as well: that stops a *release* build on your
  /// own phone generating billable events while you are testing.
  static String get rewardedAdUnitId =>
      kReleaseMode ? rewardedLiveUnitId : rewardedTestUnitId;

  /// The one-time tip product, as declared in Play Console.
  static const String tipProductId = 'alaya_tip_once';

  /// How long an advert request may take before it is treated as unavailable.
  ///
  /// The SDK's callbacks can simply never fire — no fill, no network, a mediation adapter stalling — and a
  /// screen whose button says *Loading…* forever is worse than one that admits there is no advert.
  static const Duration loadTimeout = Duration(seconds: 20);

  bool _initialised = false;
  bool _consentInfoRequested = false;
  RewardedAd? _loaded;

  /// Brings the consent framework up to date, once.
  ///
  /// **Without this, `getConsentStatus()` answers `unknown` forever** — the UMP framework has no opinion until
  /// it has been asked to fetch one, and `unknown` is not `notRequired`. This was the reason the Support screen
  /// showed *"No advert available"* even outside the EEA where no consent is needed: `unknown` mapped to
  /// `required`, `required` meant the controller never requested an advert, and nothing said why.
  Future<void> _ensureConsentInfo() async {
    if (_consentInfoRequested) return;
    _consentInfoRequested = true;
    final settled = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () {
        if (!settled.isCompleted) settled.complete();
      },
      (FormError error) {
        // A failure here is not fatal: the status stays whatever it was, and outside the EEA that is
        // `notRequired`. Completing rather than throwing keeps a network blip from disabling the whole screen.
        if (!settled.isCompleted) settled.complete();
      },
    );
    await settled.future.timeout(loadTimeout, onTimeout: () {});
  }

  @override
  Future<Result<void, Failure>> initialise() async {
    if (_initialised) return const Result.ok(null);
    try {
      await MobileAds.instance.initialize();
      _initialised = true;
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('Support could not be loaded.', cause: error),
      );
    }
  }

  @override
  Future<AdConsent> consentStatus() async {
    try {
      await _ensureConsentInfo();
      final status = await ConsentInformation.instance.getConsentStatus();
      return switch (status) {
        ConsentStatus.notRequired => AdConsent.notRequired,
        ConsentStatus.obtained => AdConsent.obtained,
        // **`required` and `unknown` both defer to `canRequestAds`, which is Google's own gate.** The status enum
        // describes the *form*; `canRequestAds` answers the question actually being asked. They differ exactly
        // when no consent message is published: the SDK logs "No available form can be built", the status stays
        // where it was, and outside the EEA ads are nonetheless permitted. Reading the enum alone was why the
        // Support screen said "No advert available" on a correctly configured account.
        ConsentStatus.required || ConsentStatus.unknown =>
          await ConsentInformation.instance.canRequestAds()
              ? AdConsent.notRequired
              : AdConsent.required,
      };
    } on Object {
      return AdConsent.unavailable;
    }
  }

  @override
  Future<AdConsent> requestConsent() async {
    await _ensureConsentInfo();
    try {
      // The callback is positional and required: it reports a form error rather than throwing, so the `await`
      // alone would not tell us anything.
      await ConsentForm.loadAndShowConsentFormIfRequired((error) {});
    } on Object {
      // Swallowed deliberately. A form that could not be built is not a refusal — the question below is what
      // decides, and it is asked either way.
    }
    try {
      return await ConsentInformation.instance.canRequestAds()
          ? AdConsent.obtained
          : AdConsent.unavailable;
    } on Object {
      return AdConsent.unavailable;
    }
  }

  @override
  Future<Result<void, Failure>> loadRewardedAd() async {
    final ready = await initialise();
    if (ready.isFailure) return ready;
    try {
      // **`RewardedAd.load` completes when the request is *dispatched*, not when an advert arrives.** Returning
      // `ok` from the awaited call therefore reported success while `_loaded` was still null — the button would
      // enable and then refuse with "no advert is ready yet". The completer is what makes this method mean what
      // its name says.
      final settled = Completer<Result<void, Failure>>();
      await RewardedAd.load(
        adUnitId: rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _loaded = ad;
            if (!settled.isCompleted) settled.complete(const Result.ok(null));
          },
          onAdFailedToLoad: (error) {
            _loaded = null;
            if (!settled.isCompleted) {
              // The SDK's own message, which names the actual cause — "No fill", a bad unit id, a missing App ID
              // — rather than a sentence of ours that would hide it (Law U9).
              settled.complete(
                Result.failure(
                  BusinessRuleFailure(error.message, rule: 'adLoadFailed'),
                ),
              );
            }
          },
        ),
      );
      return settled.future.timeout(
        loadTimeout,
        onTimeout: () => const Result.failure(
          BusinessRuleFailure(
            'No advert arrived in time.',
            rule: 'adLoadTimeout',
          ),
        ),
      );
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('No advert was available.', cause: error),
      );
    }
  }

  @override
  Future<Result<bool, Failure>> showRewardedAd() async {
    final ad = _loaded;
    if (ad == null) {
      return const Result.failure(
        BusinessRuleFailure('No advert is ready yet.', rule: 'adNotLoaded'),
      );
    }
    try {
      var earned = false;
      await ad.show(onUserEarnedReward: (view, reward) => earned = true);
      // One ad per load. Holding a shown ad would replay it, which the SDK treats as invalid traffic.
      _loaded = null;
      return Result.ok(earned);
    } on Object catch (error) {
      _loaded = null;
      return Result.failure(
        UnexpectedFailure('The advert could not be shown.', cause: error),
      );
    }
  }

  @override
  Future<Result<List<TipProduct>, Failure>> tipProducts() async {
    try {
      final available = await InAppPurchase.instance.isAvailable();
      if (!available) {
        return const Result.failure(
          BusinessRuleFailure(
            'In-app purchases are unavailable on this device.',
            rule: 'billingUnavailable',
          ),
        );
      }
      final response = await InAppPurchase.instance.queryProductDetails({
        tipProductId,
      });
      return Result.ok([
        for (final product in response.productDetails)
          TipProduct(
            id: product.id,
            title: product.title,
            // The store's own formatted string, never reformatted here.
            price: product.price,
          ),
      ]);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The tip could not be loaded.', cause: error),
      );
    }
  }

  @override
  Future<Result<bool, Failure>> buyTip(String productId) async {
    try {
      final response = await InAppPurchase.instance.queryProductDetails({
        productId,
      });
      if (response.productDetails.isEmpty) {
        return const Result.failure(
          BusinessRuleFailure(
            'That tip is not available.',
            rule: 'productMissing',
          ),
        );
      }
      final started = await InAppPurchase.instance.buyConsumable(
        purchaseParam: PurchaseParam(
          productDetails: response.productDetails.first,
        ),
      );
      return Result.ok(started);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The tip could not be completed.', cause: error),
      );
    }
  }
}
