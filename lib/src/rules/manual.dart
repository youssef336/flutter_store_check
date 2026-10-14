/// What no script can see: the console forms and the reviewer's experience.
/// Each item is a MANUAL rule, so it shows up as a checkbox in the HTML report.
library;

import '../model.dart';
import '../sources.dart';

/// Package → what it makes you declare in Data safety / App Privacy.
const Map<String, String> sdkDisclosures = {
  'firebase_analytics': 'App interactions, device IDs (Analytics)',
  'firebase_crashlytics': 'Crash logs, diagnostics',
  'firebase_performance': 'Performance diagnostics',
  'firebase_messaging': 'Device / push token',
  'firebase_auth': 'Email, phone number, user IDs',
  'supabase_flutter': 'Email, user IDs, whatever your tables store',
  'sentry_flutter': 'Crash logs, diagnostics',
  'google_sign_in': 'Email, name (Google account)',
  'sign_in_with_apple': 'Email, name (Apple ID)',
  'flutter_facebook_auth': 'Email, name, user IDs (Facebook)',
  'google_mobile_ads': 'Advertising ID, approximate location, ad interactions',
  'unity_ads_plugin': 'Advertising ID, ad interactions (Unity)',
  'unity_levelplay_mediation':
      'Advertising ID, ad interactions (LevelPlay and networks)',
  'applovin_max': 'Advertising ID, ad interactions (AppLovin)',
  'clarity_flutter':
      'Session replay: screen content and app interactions (Microsoft Clarity)',
  'mixpanel_flutter': 'App interactions, device IDs (Mixpanel)',
  'amplitude_flutter': 'App interactions, device IDs (Amplitude)',
  'onesignal_flutter': 'Device / push token, app interactions (OneSignal)',
  'flutter_stripe': 'Payment info (Stripe)',
  'in_app_purchase': 'Purchase history',
  'purchases_flutter': 'Purchase history (RevenueCat)',
  'geolocator': 'Precise or approximate location',
  'location': 'Precise or approximate location',
  'livekit_client': 'Audio and video',
  'agora_rtc_engine': 'Audio and video',
  'record': 'Voice recordings',
  'image_picker': 'Photos and videos (if uploaded)',
  'flutter_contacts': 'Contacts',
  'local_auth': 'Biometrics (stays on device: declare as not collected)',
};

Rule _manual(
  String id,
  Store store,
  String guideline,
  String title,
  String fix,
) => Rule(
  id: id,
  store: store,
  guideline: guideline,
  title: title,
  fix: fix,
  check: (_) => Finding(Status.manual, fix),
);

final List<Rule> manualRules = [
  Rule(
    id: 'M1',
    store: Store.both,
    guideline: 'Apple 5.1.2 App Privacy · Play Data safety',
    title: 'Privacy label and Data safety match the SDKs in this build',
    fix:
        'Open App Store Connect → App Privacy and Play Console → Data safety, and make sure '
        'every line below is declared.',
    check: (ctx) {
      final deps = dependencies(ctx.repo);
      final lines = [
        for (final e in sdkDisclosures.entries)
          if (deps.contains(e.key)) '${e.key} → ${e.value}',
      ];
      return Finding(
        Status.manual,
        lines.isEmpty
            ? 'No known data-collecting SDKs.'
            : 'SDKs in this build that collect data:',
        evidence: lines,
      );
    },
  ),
  _manual(
    'M2',
    Store.both,
    'Apple 2.1 App Completeness · Play App access',
    'Demo account works end to end',
    'Log in with the reviewer account on a clean install and walk the main flows. Paste fresh '
        'credentials into App Review Information and Play → App access.',
  ),
  _manual(
    'M3',
    Store.appStore,
    'Apple 2.1 · 4.0 Design',
    'Clean install on an iPad and the oldest supported iPhone',
    'Apple reviews iPhone apps on iPad too. Fresh install, deny every permission once, then '
        'allow: no crash, no blank screen, no stuck spinner.',
  ),
  _manual(
    'M4',
    Store.both,
    'Apple 2.3 Accurate metadata · Play Metadata policy',
    'Screenshots, description and age rating are current',
    'Screenshots show the current UI, the description makes no claims the app cannot back, the '
        'age rating reflects chat / UGC / purchases, and "What\'s new" is filled.',
  ),
  _manual(
    'M5',
    Store.both,
    'Review notes',
    'Reviewer notes explain anything non-obvious',
    'Explain features that need setup (hardware, a second user, a live event), how purchases '
        'work, where report and block are, and a support contact.',
  ),
  _manual(
    'M6',
    Store.googlePlay,
    'Play pre-launch report',
    'Internal track pre-launch report is green',
    'Upload the AAB to the internal track first and read the pre-launch report: no crashes, '
        'no ANRs, no security warnings. Then promote the same build.',
  ),
];
