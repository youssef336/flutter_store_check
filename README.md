[العربية](README.ar.md)

<p align="center"><img src="https://raw.githubusercontent.com/youssef336/flutter_store_check/main/screenshots/banner.png" alt="flutter_store_check banner" width="100%"></p>

<h1 align="center">Flutter Store Check</h1>

<p align="center">
  Catch Google Play and App Store rejections in your Flutter project before you upload.
</p>

<p align="center">
  <a href="https://github.com/youssef336/flutter_store_check/actions/workflows/test.yml"><img src="https://img.shields.io/github/actions/workflow/status/youssef336/flutter_store_check/test.yml?branch=main&style=for-the-badge&label=tests" alt="Tests"></a>
  <img src="https://img.shields.io/badge/Dart-%5E3.9-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart">
  <img src="https://img.shields.io/badge/Flutter-ready-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/GitHub%20Action-composite-2088FF?style=for-the-badge&logo=githubactions&logoColor=white" alt="GitHub Action">
  <img src="https://img.shields.io/badge/License-MIT-blue?style=for-the-badge" alt="MIT">
</p>

Every rejection costs days: you upload, wait for review, read a guideline number, fix it, and
upload again. Most rejections come from things a script can see: a missing privacy manifest, a
restricted permission nobody uses, a release build signed with the debug key, coins sold through
Stripe on iOS. `store_check` reads your project the way a reviewer would and fails on those
before you upload.

A human reviewer can't be fully simulated. What a script can't see (the demo account, screenshots,
the Data safety form) becomes a checklist in the HTML report, generated from the SDKs actually in
your `pubspec.yaml`.

## Install

```bash
dart pub global activate --source git https://github.com/youssef336/flutter_store_check
cd my_flutter_app
store_check init          # writes store_check.yaml (optional, every key has a default)
store_check --html store_check_report.html
```

Exit codes: `0` no FAIL · `1` at least one FAIL (or WARN with `--strict`) · `2` usage or config error.

## What it checks

| Id | Store | Rule |
|---|---|---|
| I1 | App Store | `PrivacyInfo.xcprivacy` exists, is in the Xcode project, and declares the required-reason APIs your plugins use (ITMS-91053) |
| I2 | App Store | Every permission (Podfile `PERMISSION_*` macros and ~25 known plugins) has a purpose string long enough to say why (5.1.1) |
| I3 | App Store | The ATT key and the ATT prompt agree; warns when ad SDKs run without ATT (5.1.2) |
| I4 | App Store | Sign in with Apple next to Google/Facebook login (4.8), and in-app account deletion (5.1.1(v)) |
| I5 | App Store | No `NSAllowsArbitraryLoads`, no LAN/localhost ATS exceptions, export-compliance key set, real AdMob id |
| A1 | Play | targetSdk ≥ Play's floor (configurable, bump every August 31) |
| A2 | Both | Build number above the highest `v*+N` git tag |
| A3 | Play | Restricted permissions (full-screen intent, battery optimizations, all-packages, SMS, call log, ...) are actually used; Photo & Video and storage declarations |
| A4 | Play | Each foreground-service type has its `FOREGROUND_SERVICE_*` permission (Android 14) |
| A5 | Play | Components with an intent-filter declare `android:exported`; no global cleartext |
| A6 | Play | Release isn't debuggable and isn't signed with the debug key (the `flutter create` default) |
| P1 | App Store | Digital goods on iOS go through IAP: external checkout is gated away from iOS with no bypass (3.1.1) |
| P2 | Play | Digital goods on Android use Play Billing |
| P3 | App Store | No UI switches keyed on "under review" (2.3.1) |
| P4 | Both | Every user-generated-content folder has report, and block exists (Apple 1.2) |
| P5 | Both | Ads have a consent flow (Google UMP) |
| P6 | Both | No `.env` files bundled as assets |
| P7 | Both | Real AdMob app id on Android (a missing one crashes on launch) |
| M1–M6 | Manual | Privacy label / Data safety vs the SDKs in this build, demo account, iPad clean install, metadata, reviewer notes, Play pre-launch report |
| B1 | Play | `--aab`: every 64-bit `.so` is 16 KB aligned (read from the ELF headers) |
| B2 | Play | `--aab`: merged manifest (plugins included) isn't debuggable and has no restricted permissions (needs `bundletool`) |
| B3 | App Store | `--ipa`: the app and each embedded framework ship a privacy manifest |
| B4 | App Store | `--ipa`: distribution-signed, production push (`codesign`, macOS) |

Run `store_check explain P1` for any rule's details and fix.

## Fix what can be fixed safely

```bash
store_check fix --dry-run   # list the changes
store_check fix             # apply them
```

`fix` removes restricted permissions nobody uses, caps `READ_EXTERNAL_STORAGE` at API 32, adds
missing foreground-service permissions and writes a starter `PrivacyInfo.xcprivacy`. Rules that
are business decisions (payments, review switches, ATT) are never changed automatically. The
report marks them "decision".

## Configure

Every key in `store_check.yaml` is optional. The ones that matter most:

```yaml
payments:
  sells_digital_goods: true      # coins, subscriptions, premium content → IAP / Play Billing
ugc:
  dirs: [lib/features/feed, lib/features/chat]   # where other users' content shows
android:
  min_target_sdk: 35
waivers:
  P2: Enrolled in User Choice Billing (EEA)      # accepted risk: shown, no longer fails
disabled: [P5]
```

See [`example/store_check.yaml`](example/store_check.yaml) for every key.

## Reports

- `--format text|json|markdown|github` on stdout (`github` prints workflow annotations).
- `--html report.html`: a single file you can open in any browser. It has App Store and Google
  Play tabs, a verdict (REJECT / REVIEW / READY), evidence with `file:line`, and checkboxes for
  the manual items, remembered per app version.
- `--markdown` / `--json`: write those formats to files.

## GitHub Action

```yaml
- uses: actions/checkout@v4
- uses: youssef336/flutter_store_check@v1
  with:
    args: --strict
- uses: actions/upload-artifact@v4
  if: always()
  with:
    name: store-check
    path: store_check_report.html
```

## When a store rejects you anyway

Open an issue with the guideline number and the rejection text. Every real rejection should
become a rule, so the same mistake can't ship twice.

## License

MIT
