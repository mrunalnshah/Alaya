# Getting on Play — the parts that block you

You already have `docs/PUBLISHING_FROM_SCRATCH.md` from Phase 8B for the build and signing mechanics. This
covers what happens after the AAB exists, in the order Play asks for it, with the two things that reject
releases.

---

## Blocker 1 — the privacy policy needs a public URL

Play will not let you publish without one, and "it's in the app" does not count. It must be a live web page.

**Free options, ten minutes each:**

| Where | How |
|---|---|
| **GitHub Pages** | A *separate public* repo — `wildewulf.github.io` — with `privacy.html`. Your app repo stays private. Free, permanent, no account beyond GitHub |
| **A Notion page** | Publish to web, use the public link. Fastest, but a slightly unprofessional URL |
| **A one-page site** | Best long-term. Carrd, or a static host. Also gives you somewhere to put the tagline |

**Recommended: GitHub Pages.** You already have GitHub, the URL is stable, and a separate public repo keeps
your source private while giving you a real domain.

Paste `PRIVACY_POLICY.md` in, replace `[YOUR EMAIL]` with a real address you will read, and use that URL in
both Play Console and AdMob.

---

## Blocker 2 — the Data safety form, and the honest answers

This is where most solo developers get rejected: they answer "we collect nothing" and forget the ads SDK.
**Google cross-checks your declaration against the libraries in your AAB.** `google_mobile_ads` reads the
advertising ID, so declaring no collection is a false declaration and it will be caught.

Answer it like this:

| Question | Answer | Why |
|---|---|---|
| Does your app collect or share user data? | **Yes** | Because of AdMob. Saying no here is the rejection |
| Data types collected | **Device or other IDs** — advertising ID | The only one. Not financial info: your transactions never leave the device |
| Is it collected or shared? | **Shared** — with Google | AdMob is a third party |
| Purpose | **Advertising or marketing** | |
| Is collection optional? | **Yes** | Only on a screen the user chooses to open |
| Is data encrypted in transit? | **Yes** | Google's SDK handles it |
| Can users request deletion? | **Yes** | Advertising ID is resettable in Android settings |
| Financial info collected? | **No** | It is on the device. Nothing is transmitted |

**Do not declare your transactions, accounts or inventory.** They are stored, not collected — the form asks
what leaves the device, and none of it does. Declaring financial data collection you don't perform would put
you in a stricter review category for no reason.

---

## Content rating

Fill the questionnaire honestly and you will get **Everyone / PEGI 3**. The one question that matters:
**"Does your app contain advertising?" — Yes.** It is one ad on one screen, and lying about it is a policy
violation over nothing.

## App category and tags

- **Category: Finance.** Not Productivity — Finance has lower volume but the intent is right, and you win
  nothing by competing with note apps
- **Tags:** budgeting, expense tracker, inventory, personal finance, offline

## Target audience

**18 and over.** Not because the app is unsuitable, but because declaring a child audience pulls you into
Families policy, ad-content restrictions and additional review. A household finance app has no reason to
invite that.

---

## Graphics you need

| Asset | Size | Note |
|---|---|---|
| App icon | 512×512 PNG, 32-bit with alpha | The full mark. Not the adaptive foreground |
| Feature graphic | 1024×500 | Shown at the top of the listing. No text near the edges — it gets cropped |
| Phone screenshots | 2–8, 16:9 or 9:16, 320–3840px | **From a real device.** Emulator screenshots look subtly wrong |

Captions and the recommended order are in `BRANDING.md` Part 5. **Lead with the recipe cookability screen**,
not the dashboard — it is the only screenshot a competitor cannot copy.

---

## Before you upload — a real checklist

```bash
# Suite green, including goldens
flutter test

# Release build with symbols kept, keyed to the commit
flutter build appbundle --release --obfuscate \
  --split-debug-info=build/symbols/$(git rev-parse --short HEAD)

# allowBackup must be false in the BUILT artefact, not just the source
flutter build apk --release
$ANDROID_HOME/build-tools/34.0.0/aapt2 dump xmltree \
  build/app/outputs/apk/release/app-release.apk --file AndroidManifest.xml | grep -i allowBackup
# expect: android:allowBackup(0x0101000c)=(type 0x12)0x0
```

Then, on a real device:

- [ ] **Airplane mode, every screen.** Nothing errors, nothing hangs
- [ ] **Backup → uninstall → reinstall → restore.** Record counts identical
- [ ] Real AdMob unit swapped in, and the Support Us screen loads a live ad
- [ ] The EEA consent form appears if you can test with a VPN
- [ ] `showLicensePage` reachable from Settings › About — see `LICENSE_AND_REPO.md` Part 2. **This is
      currently missing and it is a licensing obligation, not a nicety**
- [ ] Privacy policy URL live and matching what you put in AdMob
- [ ] Icon looks right on a circular-mask launcher *and* a squircle one
- [ ] Notification icon is a white silhouette, not a white square

---

## Release strategy

**Internal testing first.** Up to 100 testers by email, available in minutes rather than days, and it is
the only way to find the difference between a debug build and a signed release build before strangers do.

Then **closed testing** if you have anyone willing, then **production**.

**Staged rollout at 20% for the first production release.** If something is wrong you halt it and four
users in five never saw it. There is no reason to go to 100% on day one.

---

## Two things that will surprise you

**First review takes days, not hours** for a new developer account — sometimes up to a week. Subsequent
updates are usually quick. Plan the launch around that rather than discovering it.

**The Play Console developer account is a one-time $25 fee**, and since 2023 new personal accounts must
complete identity verification and, for personal accounts created after November 2023, run a closed test
with 12 testers for 14 days before production access. **Check the current requirement in Console before you
plan a date** — this rule has changed more than once and I may be out of date. It is the single most common
reason a first launch slips by a fortnight.
