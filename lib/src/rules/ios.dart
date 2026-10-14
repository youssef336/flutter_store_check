/// App Store rules that read the iOS project.
library;

import '../model.dart';
import '../sources.dart';

final List<Rule> iosRules = [
  privacyManifestRule,
  usageDescriptionsRule,
  trackingRule,
  appleSignInRule,
  plistHygieneRule,
];

/// Required-reason API category → plugins that commonly need it declared.
/// Plugins that ship their own manifest cover themselves; the IPA check (B3)
/// tells which ones do not.
const Map<String, List<String>> requiredReasonApis = {
  'NSPrivacyAccessedAPICategoryUserDefaults': ['shared_preferences'],
  'NSPrivacyAccessedAPICategoryFileTimestamp': [
    'path_provider',
    'sqflite',
    'hive',
    'isar',
  ],
  'NSPrivacyAccessedAPICategorySystemBootTime': [
    'flutter_webrtc',
    'livekit_client',
    'agora_rtc_engine',
  ],
  'NSPrivacyAccessedAPICategoryDiskSpace': ['disk_space_plus', 'storage_info'],
};

final Rule privacyManifestRule = Rule(
  id: 'I1',
  store: Store.appStore,
  guideline: 'ITMS-91053 · 5.1.1',
  title: 'Privacy manifest (PrivacyInfo.xcprivacy)',
  fix:
      'Run `store_check fix` to generate ios/Runner/PrivacyInfo.xcprivacy, then add it to the '
      'Runner target in Xcode (File → Add Files, tick "Runner"). Fill NSPrivacyCollectedDataTypes '
      'to match your App Privacy label.',
  check: (ctx) {
    final c = ctx.config;
    final manifest = ctx.repo.read(c.privacyManifest);
    if (manifest == null) {
      return Finding(
        Status.warn,
        'No ${c.privacyManifest}. Required when your own native code, or a plugin that ships '
        'no manifest of its own, uses required-reason APIs (ITMS-91053). Run with --ipa to see '
        'which frameworks lack one.',
      );
    }
    if (!(ctx.repo.read(c.pbxproj) ?? '').contains('PrivacyInfo.xcprivacy')) {
      return const Finding(
        Status.fail,
        'PrivacyInfo.xcprivacy exists but is not in the Xcode project, so it never ships.',
      );
    }
    final deps = dependencies(ctx.repo);
    final missing = [
      for (final e in requiredReasonApis.entries)
        if (!manifest.contains(e.key) && e.value.any(deps.contains))
          '${e.key}  (${e.value.where(deps.contains).join(', ')})',
    ];
    if (missing.isNotEmpty) {
      return Finding(
        Status.warn,
        'Categories your plugins use are not declared. Fine if those plugins ship their own '
        'manifest — check with `--ipa`.',
        evidence: missing,
      );
    }
    return const Finding.pass('Privacy manifest present and bundled.');
  },
);

/// permission_handler Podfile macro → Info.plist key it needs.
const Map<String, String> _macroKeys = {
  'CAMERA': 'NSCameraUsageDescription',
  'MICROPHONE': 'NSMicrophoneUsageDescription',
  'PHOTOS': 'NSPhotoLibraryUsageDescription',
  'LOCATION': 'NSLocationWhenInUseUsageDescription',
  'LOCATION_WHENINUSE': 'NSLocationWhenInUseUsageDescription',
  'LOCATION_ALWAYS': 'NSLocationAlwaysAndWhenInUseUsageDescription',
  'CONTACTS': 'NSContactsUsageDescription',
  'EVENTS': 'NSCalendarsUsageDescription',
  'REMINDERS': 'NSRemindersUsageDescription',
  'BLUETOOTH': 'NSBluetoothAlwaysUsageDescription',
  'SPEECH': 'NSSpeechRecognitionUsageDescription',
  'SENSORS': 'NSMotionUsageDescription',
  'MEDIA_LIBRARY': 'NSAppleMusicUsageDescription',
  'APP_TRACKING_TRANSPARENCY': 'NSUserTrackingUsageDescription',
};

/// Plugin → Info.plist keys it needs.
const Map<String, List<String>> pluginKeys = {
  'camera': ['NSCameraUsageDescription', 'NSMicrophoneUsageDescription'],
  'camerawesome': ['NSCameraUsageDescription', 'NSMicrophoneUsageDescription'],
  'mobile_scanner': ['NSCameraUsageDescription'],
  'image_picker': [
    'NSPhotoLibraryUsageDescription',
    'NSCameraUsageDescription',
  ],
  'photo_manager': ['NSPhotoLibraryUsageDescription'],
  'wechat_assets_picker': ['NSPhotoLibraryUsageDescription'],
  'wechat_camera_picker': [
    'NSCameraUsageDescription',
    'NSMicrophoneUsageDescription',
  ],
  'gal': ['NSPhotoLibraryAddUsageDescription'],
  'record': ['NSMicrophoneUsageDescription'],
  'flutter_sound': ['NSMicrophoneUsageDescription'],
  'speech_to_text': [
    'NSSpeechRecognitionUsageDescription',
    'NSMicrophoneUsageDescription',
  ],
  'livekit_client': [
    'NSCameraUsageDescription',
    'NSMicrophoneUsageDescription',
  ],
  'flutter_webrtc': [
    'NSCameraUsageDescription',
    'NSMicrophoneUsageDescription',
  ],
  'agora_rtc_engine': [
    'NSCameraUsageDescription',
    'NSMicrophoneUsageDescription',
  ],
  'local_auth': ['NSFaceIDUsageDescription'],
  'geolocator': ['NSLocationWhenInUseUsageDescription'],
  'location': ['NSLocationWhenInUseUsageDescription'],
  'google_maps_flutter': ['NSLocationWhenInUseUsageDescription'],
  'flutter_contacts': ['NSContactsUsageDescription'],
  'device_calendar': ['NSCalendarsUsageDescription'],
  'flutter_blue_plus': ['NSBluetoothAlwaysUsageDescription'],
  'health': ['NSHealthShareUsageDescription', 'NSHealthUpdateUsageDescription'],
  'app_tracking_transparency': ['NSUserTrackingUsageDescription'],
};

/// Shorter than this, a purpose string rarely says *why* (5.1.1 asks for it).
const int minPurposeLength = 25;

final Rule usageDescriptionsRule = Rule(
  id: 'I2',
  store: Store.appStore,
  guideline: '5.1.1(i) · ITMS-90683',
  title: 'Permission purpose strings',
  fix:
      'Add each missing NS*UsageDescription to Info.plist with a sentence that names the feature '
      'and why it needs the data, e.g. "MyApp uses the camera so you can scan receipts."',
  check: (ctx) {
    final c = ctx.config;
    final text = ctx.repo.read(c.infoPlist);
    final keys = plistKeys(text);
    final needed = <String, String>{};
    for (final m in RegExp(
      r'PERMISSION_(\w+)=1',
    ).allMatches(ctx.repo.read(c.podfile) ?? '')) {
      final key = _macroKeys[m[1]];
      if (key != null) {
        needed[key] = 'Podfile PERMISSION_${m[1]}';
      }
    }
    final deps = dependencies(ctx.repo);
    for (final e in pluginKeys.entries) {
      if (deps.contains(e.key)) {
        for (final k in e.value) {
          needed.putIfAbsent(k, () => 'pubspec ${e.key}');
        }
      }
    }
    final missing = [
      for (final e in needed.entries)
        if (!keys.containsKey(e.key)) '${e.key} — required by ${e.value}',
    ];
    final weak = [
      for (final e in keys.entries)
        if (e.key.endsWith('UsageDescription') &&
            e.value.trim().length < minPurposeLength)
          '${at(c.infoPlist, text, '<key>${e.key}</key>')}  "${e.value}"',
    ];
    if (missing.isNotEmpty) {
      return Finding(
        Status.fail,
        'Info.plist is missing purpose strings.',
        evidence: [...missing, ...weak],
      );
    }
    if (weak.isNotEmpty) {
      return Finding(
        Status.warn,
        'Purpose strings too short to explain the use.',
        evidence: weak,
      );
    }
    return Finding.pass(
      'All ${needed.length} required purpose strings present.',
    );
  },
);

const Set<String> adSdks = {
  'google_mobile_ads',
  'unity_ads_plugin',
  'unity_levelplay_mediation',
  'applovin_max',
  'facebook_audience_network',
  'easy_ads_flutter',
};

final Rule trackingRule = Rule(
  id: 'I3',
  store: Store.appStore,
  guideline: '5.1.2(i)',
  title: 'App Tracking Transparency',
  needsDecision: true,
  fix:
      'Either add NSUserTrackingUsageDescription, call ATT (app_tracking_transparency) before '
      'the first ad request and declare tracking in App Privacy; or skip ATT and make sure App '
      'Privacy says "Data not used to track you" and ads are non-personalized.',
  check: (ctx) {
    final ads = dependencies(ctx.repo).intersection(adSdks);
    final hasKey = plistKeys(
      ctx.repo.read(ctx.config.infoPlist),
    ).containsKey('NSUserTrackingUsageDescription');
    final asks = ctx.repo.grep(
      RegExp(r'requestTrackingAuthorization|AppTrackingTransparency'),
      ctx.config.codeDirs,
    );
    if (hasKey && asks.isEmpty) {
      return const Finding(
        Status.fail,
        'NSUserTrackingUsageDescription is declared but the app never shows the ATT prompt. '
        'Reviewers reject a declared permission that is never requested.',
      );
    }
    if (ads.isNotEmpty && !hasKey) {
      return Finding(
        Status.warn,
        'Ad SDKs (${ads.join(', ')}) without ATT. Fine only if App Privacy declares no tracking.',
      );
    }
    return const Finding.pass('ATT setup is consistent.');
  },
);

const Set<String> thirdPartyLogins = {
  'google_sign_in',
  'flutter_facebook_auth',
  'twitter_login',
  'flutter_login_facebook',
  'sign_in_with_linkedin',
};

const Set<String> authPackages = {
  'firebase_auth',
  'supabase_flutter',
  'amplify_auth_cognito',
  ...thirdPartyLogins,
  'sign_in_with_apple',
};

final Rule appleSignInRule = Rule(
  id: 'I4',
  store: Store.appStore,
  guideline: '4.8 · 5.1.1(v)',
  title: 'Sign in with Apple + account deletion',
  fix:
      'Offer Sign in with Apple wherever another social login is offered, and give every user '
      'an in-app way to delete their account (revoke the Apple token on deletion).',
  check: (ctx) {
    final deps = dependencies(ctx.repo);
    final social = deps.intersection(thirdPartyLogins);
    if (social.isNotEmpty && !deps.contains('sign_in_with_apple')) {
      return Finding(
        Status.fail,
        '${social.join(', ')} offered without Sign in with Apple.',
      );
    }
    if (deps.intersection(authPackages).isEmpty) {
      return const Finding.pass('No user accounts.');
    }
    final deletion = ctx.repo.grep(
      RegExp(ctx.config.deleteAccountPattern, caseSensitive: false),
      ctx.config.codeDirs,
    );
    if (deletion.isEmpty) {
      return const Finding(
        Status.fail,
        'The app has accounts but no in-app account deletion was found.',
      );
    }
    return const Finding.pass(
      'Sign in with Apple offered and deletion flow present.',
    );
  },
);

const String sampleAdmobPrefix = 'ca-app-pub-3940256099942544';

final Rule plistHygieneRule = Rule(
  id: 'I5',
  store: Store.appStore,
  guideline: '2.5.1 · ATS · export compliance',
  title: 'Info.plist hygiene',
  fix:
      'Remove NSAllowsArbitraryLoads and LAN/localhost ATS exceptions from release builds, set '
      'ITSAppUsesNonExemptEncryption, and use your real GADApplicationIdentifier.',
  check: (ctx) {
    final path = ctx.config.infoPlist;
    final text = ctx.repo.read(path);
    if (text == null) {
      return Finding(Status.warn, 'No $path (not an iOS project?).');
    }
    final keys = plistKeys(text);
    final issues = <String>[];
    var fail = false;
    if (RegExp(r'<key>NSAllowsArbitraryLoads</key>\s*<true').hasMatch(text)) {
      fail = true;
      issues.add(at(path, text, '<key>NSAllowsArbitraryLoads</key>'));
    }
    for (final m in RegExp(
      r'<key>((?:\d+\.){3}\d+|localhost)</key>',
    ).allMatches(text)) {
      issues.add('${at(path, text, m[0]!)}  (dev-only ATS exception)');
    }
    if (!keys.containsKey('ITSAppUsesNonExemptEncryption')) {
      issues.add(
        'ITSAppUsesNonExemptEncryption missing: every upload stalls on export compliance',
      );
    }
    if (dependencies(ctx.repo).contains('google_mobile_ads')) {
      final gad = keys['GADApplicationIdentifier'];
      if (gad == null) {
        fail = true;
        issues.add(
          'GADApplicationIdentifier missing: Google Mobile Ads crashes on launch',
        );
      } else if (gad.startsWith(sampleAdmobPrefix)) {
        fail = true;
        issues.add('${at(path, text, gad)}  (Google sample app id)');
      }
    }
    if (issues.isEmpty) {
      return const Finding.pass('No ATS, export-compliance or ad-id problems.');
    }
    return Finding(
      fail ? Status.fail : Status.warn,
      'Info.plist needs cleanup.',
      evidence: issues,
    );
  },
);
