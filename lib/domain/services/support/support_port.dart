import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';

/// Whether the user has been asked about personalised ads, and what they said.
enum AdConsent {
  /// Not required in this region, or already settled outside the EEA rules.
  notRequired,

  /// A form is available and has not been shown.
  required,

  /// The user has answered.
  obtained,

  /// The form could not be fetched.
  unavailable,
}

/// What a tip costs, as the store reports it.
class TipProduct {
  /// Creates a product.
  const TipProduct({
    required this.id,
    required this.title,
    required this.price,
  });

  /// The store's product identifier.
  final String id;

  /// Its display name.
  final String title;

  /// **The store's own formatted price string**, never a number this app formats.
  ///
  /// Play returns it already localised, with the right currency and the right separators for the user's account
  /// — which may not be the account's country, and is certainly not Alaya's home currency. Reformatting it would
  /// be the one place in this app where money is displayed without `AmountText`, and it would be wrong.
  final String price;
}

/// Rewarded ads and a one-time tip (ARCH_4 §5.1, ARCH_5 §3 archetype F).
///
/// **Nothing here runs until the Support screen asks it to.** ARCH_4 records rewarded ads as belonging to the
/// `support/` feature, lazy-loaded, and the rest of the app making zero ad calls is a requirement rather than an
/// optimisation: an SDK that initialises on launch collects an identifier from every user who never opens this
/// screen, which is a data-safety declaration nobody wants to have to make.
///
/// **UMP consent comes before any ad request**, not after. ARCH_1 §7 pins `google_mobile_ads` with "resolver +
/// UMP consent", and requesting an ad before consent is settled is what gets an app pulled in the EEA.
abstract interface class SupportPort {
  /// Brings the SDKs up. Called by the Support screen and nowhere else.
  ///
  /// Idempotent, because the screen can be opened repeatedly and initialising twice is a plugin error rather
  /// than a no-op.
  Future<Result<void, Failure>> initialise();

  /// Where consent currently stands.
  Future<AdConsent> consentStatus();

  /// Shows the UMP form if one is required.
  Future<AdConsent> requestConsent();

  /// Loads a rewarded ad, ready to show.
  Future<Result<void, Failure>> loadRewardedAd();

  /// Shows the loaded ad, completing when the user has earned the reward or dismissed it.
  ///
  /// Returns whether a reward was earned. **A dismissed ad is not a failure** — somebody who changes their mind
  /// halfway through has done nothing wrong, and an error message would say otherwise.
  Future<Result<bool, Failure>> showRewardedAd();

  /// The one-time tip products the store offers.
  Future<Result<List<TipProduct>, Failure>> tipProducts();

  /// Starts the purchase flow for [productId].
  ///
  /// Returns whether it completed. Non-consumable and one-time: this is a tip, not a subscription, and nothing
  /// in the app changes behaviour when it succeeds — there are no paid features to unlock, which is what keeps
  /// this honest rather than a paywall wearing a friendly label.
  Future<Result<bool, Failure>> buyTip(String productId);
}
