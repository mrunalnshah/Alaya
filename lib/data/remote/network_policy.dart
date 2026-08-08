/// The complete list of hosts this app may contact, and the single gate every HTTP call passes
/// through (ARCH_3 §1.4).
///
/// Three purposes, and nothing else: currency rates, rewarded ads, and the tip purchase. No crash
/// reporter, no analytics SDK, no font CDN, no image loader. The value of an allowlist is that it
/// is checked in code rather than asserted in a document — a package that quietly wants a fourth
/// host fails [ensureAllowed] instead of shipping.
///
/// Ads and billing are Phase 8B and route through Google's own SDKs rather than this client, so
/// their hosts are recorded here for completeness but are not yet reachable through [isAllowed].
final class NetworkPolicy {
  /// Creates the policy.
  const NetworkPolicy();

  /// Hosts serving currency rates — the only hosts this app's own HTTP client may reach.
  ///
  /// `latest.currency-api.pages.dev` and `{date}.currency-api.pages.dev` are both real: the
  /// fawazahmed0 mirror puts the date in the subdomain for historical lookups, which is why
  /// [isAllowed] matches that host by suffix rather than exactly.
  static const Set<String> currencyHosts = {
    'cdn.jsdelivr.net',
    'api.frankfurter.dev',
  };

  /// The suffix that admits any `*.currency-api.pages.dev` subdomain.
  static const String currencyHostSuffix = '.currency-api.pages.dev';

  /// Hosts reached by Google's ad SDK, not by this app's HTTP client (Phase 8B).
  static const Set<String> adHosts = {'googleads.g.doubleclick.net'};

  /// Hosts reached by Google Play Billing, not by this app's HTTP client (Phase 8B).
  static const Set<String> billingHosts = {'play.google.com'};

  /// True when [url] may be requested by this app's own HTTP client.
  ///
  /// Requires HTTPS and rejects a URL carrying credentials — a rate endpoint never needs either,
  /// so anything presenting them is not the endpoint it claims to be.
  bool isAllowed(Uri url) {
    if (url.scheme != 'https') return false;
    if (url.userInfo.isNotEmpty) return false;
    final host = url.host.toLowerCase();
    return currencyHosts.contains(host) || host.endsWith(currencyHostSuffix);
  }

  /// Throws [DisallowedHostError] unless [url] passes [isAllowed].
  ///
  /// Throws rather than returning a failure deliberately: a disallowed host is a programming
  /// mistake, not a runtime condition a user can act on, and it should surface in development
  /// rather than degrade into a silent no-op.
  void ensureAllowed(Uri url) {
    if (!isAllowed(url)) throw DisallowedHostError(url);
  }
}

/// Thrown when code attempts an HTTP request to a host outside [NetworkPolicy]'s allowlist.
final class DisallowedHostError extends Error {
  /// Creates the error for [url].
  DisallowedHostError(this.url);

  /// The rejected URL.
  final Uri url;

  @override
  String toString() =>
      'DisallowedHostError: $url is not on the network allowlist (ARCH_3 §1.4). '
          'If a package needs this host, it does not go in the app.';
}