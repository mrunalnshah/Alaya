# Setting up Support Us — AdMob and the one-time tip

Everything in this document is **release configuration**, not code. Alaya ships with Google's public test
identifiers so that a debug build never touches live ad serving; nothing here needs changing to develop,
run, or test the app.

Read this in full before creating the AdMob account, because two of the steps have to happen in an order
that is not obvious and one of them blocks a Play release.

---

## What is already true in the code

| | |
|---|---|
| One file talks to both SDKs | `lib/data/support/ads_and_billing.dart`. Nothing else imports `google_mobile_ads` or `in_app_purchase` — `grep -r google_mobile_ads lib/` returning one path is the check |
| Nothing initialises on launch | `SupportPort.initialise()` is called from `SupportScreen.initState` and nowhere else. An install where nobody opens that screen never starts the SDK and never collects an advertising identifier |
| Consent precedes every ad request | `SupportController.start()` settles UMP consent first and only loads an advert when it comes back `obtained` or `notRequired` |
| Nothing is unlocked by paying | There are no paid features. A tip is a tip, and the screen says so |

Three identifiers exist. All three are Google test values today:

| Where | Constant | Test value |
|---|---|---|
| `android/app/src/main/AndroidManifest.xml` | `com.google.android.gms.ads.APPLICATION_ID` | `ca-app-pub-3940256099942544~3347511713` |
| `lib/data/support/ads_and_billing.dart` | `AdsAndBilling.rewardedTestUnitId` | `ca-app-pub-3940256099942544/5224354917` |
| `lib/data/support/ads_and_billing.dart` | `AdsAndBilling.tipProductId` | `alaya_tip_once` |

Note the punctuation: an **App ID** contains `~`, an **ad unit ID** contains `/`. Swapping them produces a
crash at initialisation with a message that does not mention which one is wrong.

---

## Part 1 — AdMob

### 1.1 Create the account and the app

1. Sign in at **https://admob.google.com** with the Google account that will receive payments.
2. **Apps → Add app → Android**.
3. When asked *"Is your app listed on a supported app store?"*: answer **No** the first time. You do not
   need a Play listing to get an App ID, and you will link the real listing later.
4. Name it `Alaya`.

You now have an **App ID** shaped `ca-app-pub-################~##########`.

### 1.2 Create the rewarded ad unit

1. Inside the app: **Ad units → Add ad unit → Rewarded**.
2. Name it something you will recognise in reports — `Alaya rewarded — support` is fine.
3. **Reward amount `1`, reward item `support`.** The app ignores both: `showRewardedAd()` returns whether
   the reward callback fired, and nothing in Alaya grants anything. They are required fields, not features.
4. Leave frequency capping off. The user chooses when to watch one; there is nothing to cap.

You now have an **ad unit ID** shaped `ca-app-pub-################/##########`.

### 1.3 Set up UMP consent — do this before your first release

This is the step most easily missed, and shipping without it risks removal in the EEA.

1. **Privacy & messaging → European regulations**.
2. Create a message, select the app, publish it.
3. **GDPR** and **US state regulations** are separate messages. Create both if you will publish in either
   region.

The app calls `ConsentForm.loadAndShowConsentFormIfRequired` on the Support screen and re-reads the status
afterwards. **If no message is published, the status comes back `unavailable` and Alaya requests no
advert at all** — the screen says so rather than showing a button that cannot work. That is the intended
failure mode, so an unconfigured account degrades safely rather than serving unconsented ads.

### 1.4 Put the real identifiers in

**`android/app/src/main/AndroidManifest.xml`**

```xml
<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="ca-app-pub-YOUR~APPID"/>
```

**`lib/data/support/ads_and_billing.dart`**

```dart
static const String rewardedTestUnitId = 'ca-app-pub-YOUR/UNITID';
```

Rename that constant when you do — `rewardedTestUnitId` holding a live unit is exactly the kind of stale
name that survives for years.

> **Do not commit live identifiers to a branch you build debug from.** A debug build serving live ads is
> how an AdMob account gets flagged for invalid traffic, and the appeal process is slow. Keep the test
> values on `main` and inject the real ones in your release pipeline, or gate them on `kReleaseMode`.

### 1.5 Register your test devices

Even with live identifiers, you must not click your own ads.

1. **Settings → Test devices → Add test device**.
2. Run the app once and find the device ID in logcat — the SDK prints a line containing
   `RequestConfiguration.Builder().setTestDeviceIds`.
3. Add it. That device then sees test ads against your live unit and generates no billable events.

---

## Part 2 — The one-time tip

### 2.1 The ordering constraint that blocks everything

**An in-app product cannot be created until an app bundle has been uploaded to a Play track**, and
`in_app_purchase` cannot see a product until it is **active** and the account querying it is a **licence
tester**. Expect this sequence:

1. Create the Play Console app entry.
2. Build a signed AAB and upload it to **Internal testing**. It does not need to be reviewed or released
   publicly, but it must be uploaded.
3. Only then does **Monetise → In-app products → Create product** become available.

If `tipProducts()` returns an empty list, this is almost always why — the Support screen shows *"Tips are
not available on this device right now"* rather than an error, because from the app's side an absent
product and an unconfigured store are indistinguishable.

### 2.2 Create the product

| Field | Value |
|---|---|
| Product ID | `alaya_tip_once` |
| Name | Something plain — *Tip the developer* |
| Description | Say explicitly that it unlocks nothing |
| Price | Your choice. Play localises it per account |
| Status | **Active** |

The product ID must match `AdsAndBilling.tipProductId` exactly. It cannot be changed after creation, so
if you want a different one, change the constant rather than trying to rename the product.

### 2.3 Licence testers

**Setup → Licence testing** → add the Google accounts that will test purchases. Those accounts see a test
card and are never charged. The account must also be on the Internal testing track's tester list.

### 2.4 A note on the price string

Alaya displays `product.price` — the string Play returns — and never reformats it. Play localises it for
the *user's account*, which need not match the app's home currency or the device locale. This is the one
place in the app where money is shown without `AmountText`, deliberately: reformatting it would render a
Japanese account's ¥ price with Indian grouping, or worse, in the wrong currency entirely.

---

## Part 3 — Play policy, and the thing that blocks a release

### 3.1 The privacy policy URL is needed **before** your first upload

Not at launch — at upload. Play requires a reachable privacy policy URL for any app that requests the
advertising identifier, and `google_mobile_ads` does. Have the URL live before you submit, because the
listing cannot be saved without it.

The policy must state, at minimum:

- that the app shows advertising supplied by Google
- that Google may collect an advertising identifier for that purpose
- that financial data entered into Alaya stays on the device and is not transmitted

That last point is worth stating plainly, because it is unusual and true: the only network calls Alaya
makes are the daily exchange-rate fetch and the ad requests from this one screen.

### 3.2 The Data safety form

Declare **Device or other IDs → Advertising ID**, collected, shared with third parties, for advertising.
That declaration is required by the presence of the SDK, **not** by whether a user ever opens the Support
screen — the lazy loading is a privacy improvement, not an exemption from disclosure.

Declare **no** financial data collection. Alaya's database never leaves the device except through a backup
the user exports themselves.

### 3.3 An `app-ads.txt` file

Only needed if you later run mediation or want to be verified as a seller. Not required for a single
rewarded unit through AdMob's own network. Skip it until you need it.

---

## Verifying it works

```bash
flutter run
```

1. Open **Settings → Support Alaya**.
2. Watch logcat. You should see the Mobile Ads SDK initialise **only now**, not at launch. If it
   initialises at startup, something outside `SupportScreen` is calling `initialise()` — find it, because
   that is the requirement this whole design protects.
3. If you are in the EEA or using a VPN, the consent form should appear before any ad request.
4. Tap **Watch an advert**. A test ad plays.
5. Tap the tip button. With a licence-tester account you get the test purchase dialog.

If the tip button is missing entirely, `tipProducts()` returned empty — go back to §2.1, it is nearly
always the upload ordering.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| Crash on opening Support, message mentions `APPLICATION_ID` | The manifest meta-data is missing or malformed. The SDK throws at initialisation rather than failing quietly |
| `Nothing has been requested` on the ad card | UMP consent came back `unavailable` — no message published (§1.3), or no network |
| *"No advert available right now"* | Normal on a fresh unit. AdMob takes hours to start filling a new ad unit; test IDs always fill |
| *"Tips are not available"* | No active product, no uploaded bundle, or the account is not a licence tester |
| Ads work in debug and not release | The release build has different identifiers, or ProGuard stripped something. `google_mobile_ads` ships its own consumer rules, so check the identifiers first |
| Account flagged for invalid traffic | A live unit was served in a debug build, or you clicked your own live ad. See §1.5 |

---

## What Alaya deliberately does not do

Worth knowing, because each was a decision rather than an omission:

- **No banner or interstitial ads.** One rewarded ad, on one screen, when the user asks for it.
- **No ad calls anywhere else.** Enforced by `AdsAndBilling` being the only file importing the SDK.
- **No subscription.** The tip is non-recurring and grants nothing.
- **No reward.** `showRewardedAd()` returns whether the reward fired and the app does nothing with it.
  The advert *is* the support; there is no currency to award.
- **No tracking of who tipped.** Nothing is written to the database when a purchase completes.
