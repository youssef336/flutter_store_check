/// Policy rules that read the Dart code: payments, review switches,
/// user-generated content, ads consent, and leftovers that crash or leak.
library;

import '../model.dart';
import '../sources.dart';
import 'ios.dart' show adSdks, sampleAdmobPrefix;

final List<Rule> policyRules = [
  iosPaymentsRule,
  playBillingRule,
  hiddenFeaturesRule,
  ugcSafetyRule,
  adsConsentRule,
  bundledSecretsRule,
  adIdsRule,
];

/// Lines that look like an iOS gate with an escape hatch:
/// `isIOS && !something`, `bypassIos…`, `skipIap…`.
final RegExp _iosBypass = RegExp(
  r'[bB]ypass(Ios|IOS|Iap|IAP)\w*|skip(Iap|IAP)\w*|(isIOS|TargetPlatform\.iOS)[^;\n]*&&\s*!',
);
final RegExp _iosGate = RegExp(r'Platform\.isIOS|TargetPlatform\.iOS|isApple');

final Rule iosPaymentsRule = Rule(
  id: 'P1',
  store: Store.appStore,
  guideline: '3.1.1 In-App Purchase',
  title: 'Digital goods on iOS go through IAP only',
  needsDecision: true,
  fix:
      'On iOS, sell every digital item (coins, subscriptions, premium content) through '
      'in_app_purchase with no bypass by level, flag or remote switch. Card / web checkout must '
      'not be reachable on iOS for digital goods.',
  check: (ctx) {
    final c = ctx.config;
    final external = ctx.repo.grep(
      anyOf(c.externalPaymentPatterns),
      c.codeDirs,
    );
    if (external.isEmpty || c.sellsDigitalGoods == false) {
      return Finding.pass(
        external.isEmpty
            ? 'No external checkout in the code.'
            : 'Physical goods only (config).',
      );
    }
    final bypass = ctx.repo.grep(_iosBypass, c.codeDirs);
    if (bypass.isNotEmpty) {
      return Finding(
        Status.fail,
        'The iOS in-app-purchase gate has an escape hatch, so iOS users (or a reviewer) can '
        'reach an external checkout.',
        evidence: [...bypass, ...external.take(3)],
      );
    }
    final ungated = [
      for (final e in external)
        if (!_iosGate.hasMatch(ctx.repo.read(e.split(':').first) ?? '')) e,
    ];
    if (ungated.isNotEmpty) {
      return Finding(
        c.sellsDigitalGoods == true ? Status.fail : Status.warn,
        c.sellsDigitalGoods == true
            ? 'External checkout with no iOS gate in the same file.'
            : 'External checkout found. If it sells digital goods on iOS, Apple rejects it '
                  '(set payments.sells_digital_goods in store_check.yaml).',
        evidence: ungated.take(6).toList(),
      );
    }
    return const Finding.pass('External checkout is gated away from iOS.');
  },
);

final Rule playBillingRule = Rule(
  id: 'P2',
  store: Store.googlePlay,
  guideline: 'Payments policy (Google Play Billing)',
  title: 'Digital goods on Android use Play Billing',
  needsDecision: true,
  fix:
      'Sell digital goods on Android through in_app_purchase (Play Billing), or enrol in '
      'User Choice / Alternative Billing for your markets and add a waiver.',
  check: (ctx) {
    final c = ctx.config;
    final external = ctx.repo.grep(
      anyOf(c.externalPaymentPatterns),
      c.codeDirs,
    );
    if (external.isEmpty || c.sellsDigitalGoods == false) {
      return const Finding.pass('No external checkout for digital goods.');
    }
    final hasIap =
        dependencies(ctx.repo).contains('in_app_purchase') ||
        dependencies(ctx.repo).contains('purchases_flutter');
    final iapIosOnly = ctx.repo.grep(
      RegExp(
        r'(iap|IAP|Iap|InAppPurchase)\w*\s*(=>|=)[^;]*(isIOS|TargetPlatform\.iOS)',
      ),
      c.codeDirs,
    );
    if (!hasIap || iapIosOnly.isNotEmpty) {
      return Finding(
        c.sellsDigitalGoods == true ? Status.fail : Status.warn,
        hasIap
            ? 'In-app purchase is iOS-only, so Android sells through the external checkout.'
            : 'External checkout and no in_app_purchase: fine for physical goods only.',
        evidence: [...iapIosOnly, ...external.take(4)],
      );
    }
    return const Finding.pass('Play Billing is available on Android.');
  },
);

final Rule hiddenFeaturesRule = Rule(
  id: 'P3',
  store: Store.appStore,
  guideline: '2.3.1 Hidden features · 2.3 Accurate metadata',
  title: 'No review-only switches',
  needsDecision: true,
  fix:
      'Remove UI gates keyed on "this build is under review / TestFlight". What the reviewer sees '
      'must be what users get.',
  check: (ctx) {
    final hits = [
      for (final h in ctx.repo.grep(
        anyOf(ctx.config.reviewFlagPatterns),
        ctx.config.codeDirs,
      ))
        if (!h.contains('/models/') &&
            !h.contains('/services/') &&
            !h.contains('/data/'))
          h,
    ];
    if (hits.isNotEmpty) {
      return Finding(
        Status.fail,
        'UI behaves differently while the app is under review.',
        evidence: hits,
      );
    }
    return const Finding.pass('No review-mode switches in the UI.');
  },
);

final Rule ugcSafetyRule = Rule(
  id: 'P4',
  store: Store.both,
  guideline: 'Apple 1.2 User-Generated Content · Play UGC policy',
  title: 'Report and block on every UGC surface',
  fix:
      'Add a report action to each folder listed and a way to block users. Show the Terms with a '
      '"no tolerance for objectionable content" line at sign-up.',
  check: (ctx) {
    final c = ctx.config;
    if (c.ugcDirs.isEmpty) {
      return const Finding(
        Status.manual,
        'List the folders that show other users\' content under ugc.dirs in store_check.yaml '
        'to check them. Apple 1.2 needs report, block and a content filter there.',
      );
    }
    final report = RegExp(c.reportPattern);
    final missing = [
      for (final dir in c.ugcDirs)
        if (ctx.repo.grep(report, [dir]).isEmpty) '$dir: no report action',
    ];
    if (ctx.repo.grep(RegExp(c.blockPattern), c.codeDirs).isEmpty) {
      missing.add('no block-user flow anywhere');
    }
    if (missing.isNotEmpty) {
      return Finding(
        Status.fail,
        'UGC surfaces without moderation tools.',
        evidence: missing,
      );
    }
    return const Finding.pass('Every UGC folder has report; block exists.');
  },
);

final Rule adsConsentRule = Rule(
  id: 'P5',
  store: Store.both,
  guideline: 'AdMob EU User Consent Policy · Play Ads policy',
  title: 'Ads consent (UMP)',
  fix:
      'Gather consent with the Google UMP SDK (ConsentInformation / ConsentForm in '
      'google_mobile_ads) before the first ad request, and pass it to mediation networks.',
  check: (ctx) {
    final ads = dependencies(ctx.repo).intersection(adSdks);
    if (ads.isEmpty) {
      return const Finding.pass('No ad SDKs.');
    }
    if (ctx.repo
        .grep(
          RegExp(r'ConsentInformation|ConsentForm|ConsentRequestParameters'),
          ctx.config.codeDirs,
        )
        .isEmpty) {
      return Finding(
        Status.warn,
        'Ad SDKs (${ads.join(', ')}) without a consent flow: an AdMob policy strike in the '
        'EEA/UK, though not a store rejection by itself.',
      );
    }
    return const Finding.pass('Consent flow present.');
  },
);

final Rule bundledSecretsRule = Rule(
  id: 'P6',
  store: Store.both,
  guideline: 'Security (not a rejection)',
  title: 'No .env files inside the app bundle',
  fix:
      'Stop listing .env files under flutter: assets and pass values with '
      '--dart-define-from-file. Anything bundled is readable by unzipping the AAB/IPA.',
  check: (ctx) {
    final text = ctx.repo.read(pubspec) ?? '';
    final hits = [
      for (final h in ctx.repo.hits(RegExp(r'^\s+- \S*\.env'), pubspec))
        if (_inFlutterSection(
          text,
          int.parse(h.split(':')[1].split(' ').first),
        ))
          h,
    ];
    if (hits.isEmpty) {
      return const Finding.pass('No .env assets.');
    }
    return Finding(
      Status.warn,
      '${hits.length} .env file(s) ship inside the app.',
      evidence: hits,
    );
  },
);

/// Whether 1-based [line] sits under the top-level `flutter:` key.
bool _inFlutterSection(String text, int line) {
  final lines = text.split('\n');
  for (var i = line - 1; i >= 0; i--) {
    if (RegExp(r'^\S').hasMatch(lines[i])) {
      return lines[i].startsWith('flutter:');
    }
  }
  return false;
}

final Rule adIdsRule = Rule(
  id: 'P7',
  store: Store.both,
  guideline: 'Crash on launch (2.1) · AdMob',
  title: 'Real AdMob app id on Android',
  fix:
      'Put your production AdMob app id in AndroidManifest.xml (meta-data APPLICATION_ID).',
  check: (ctx) {
    if (!dependencies(ctx.repo).contains('google_mobile_ads')) {
      return const Finding.pass('google_mobile_ads not used.');
    }
    final path = ctx.config.androidManifest;
    final text = ctx.repo.read(path) ?? '';
    final m = RegExp(
      r'gms\.ads\.APPLICATION_ID"\s*android:value="([^"]+)"',
    ).firstMatch(text);
    if (m == null) {
      return const Finding(
        Status.fail,
        'com.google.android.gms.ads.APPLICATION_ID missing: the app crashes on launch.',
      );
    }
    if (m[1]!.startsWith(sampleAdmobPrefix)) {
      return Finding(
        Status.fail,
        'Android uses the Google sample AdMob app id.',
        evidence: [at(path, text, m[1]!)],
      );
    }
    return const Finding.pass('Production AdMob app id.');
  },
);
