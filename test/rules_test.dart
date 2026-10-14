import 'dart:typed_data';

import 'package:flutter_store_check/flutter_store_check.dart';
import 'package:flutter_store_check/src/binary.dart';
import 'package:flutter_store_check/src/rules/android.dart';
import 'package:flutter_store_check/src/rules/ios.dart';
import 'package:flutter_store_check/src/rules/policy.dart';
import 'package:flutter_store_check/src/sources.dart';
import 'package:test/test.dart';

const String _plistPath = 'ios/Runner/Info.plist';
const String _manifest = 'android/app/src/main/AndroidManifest.xml';
const String _purpose =
    'MyApp uses this so you can share moments with friends.';

String _plist(Map<String, String> keys) =>
    '<plist><dict>\n${keys.entries.map((e) => '<key>${e.key}</key>\n<string>${e.value}</string>').join('\n')}\n</dict></plist>';

String _pubspec(List<String> deps, {String version = '1.0.0+10'}) =>
    'name: app\nversion: $version\ndependencies:\n${deps.map((d) => '  $d: ^1.0.0').join('\n')}\n';

Status _run(
  Rule rule,
  Map<String, String> files, {
  List<String> tags = const [],
  Config config = const Config(),
}) => rule.check(Context(MemoryRepo(files, tags: tags), config)).status;

void main() {
  group('sources', () {
    test('dependencies reads only the dependencies section', () {
      final repo = MemoryRepo({
        'pubspec.yaml':
            '${_pubspec(['camera'])}dev_dependencies:\n  test: ^1.0.0\n',
      });
      expect(dependencies(repo), {'camera'});
    });

    test('plistKeys reads strings and booleans', () {
      expect(plistKeys('<key>A</key><string>x</string><key>B</key><true/>'), {
        'A': 'x',
        'B': 'true',
      });
    });
  });

  group('iOS', () {
    test('I1 warns without a manifest, fails when not bundled', () {
      expect(_run(privacyManifestRule, {}), Status.warn);
      const manifest = {'ios/Runner/PrivacyInfo.xcprivacy': '<plist/>'};
      expect(_run(privacyManifestRule, manifest), Status.fail);
      expect(
        _run(privacyManifestRule, {
          ...manifest,
          'ios/Runner.xcodeproj/project.pbxproj': 'PrivacyInfo.xcprivacy',
        }),
        Status.pass,
      );
    });

    test('I2 needs a purpose string per Podfile macro and plugin', () {
      final files = {
        'ios/Podfile': "'PERMISSION_CAMERA=1'",
        'pubspec.yaml': _pubspec(['local_auth']),
        _plistPath: _plist({'NSCameraUsageDescription': _purpose}),
      };
      expect(_run(usageDescriptionsRule, files), Status.fail);
      files[_plistPath] = _plist({
        'NSCameraUsageDescription': _purpose,
        'NSFaceIDUsageDescription': 'Face ID',
      });
      expect(_run(usageDescriptionsRule, files), Status.warn);
      files[_plistPath] = _plist({
        'NSCameraUsageDescription': _purpose,
        'NSFaceIDUsageDescription': _purpose,
      });
      expect(_run(usageDescriptionsRule, files), Status.pass);
    });

    test('I3 fails when ATT is declared but never requested', () {
      final files = {
        'pubspec.yaml': _pubspec(['google_mobile_ads']),
        _plistPath: _plist({'NSUserTrackingUsageDescription': _purpose}),
      };
      expect(_run(trackingRule, files), Status.fail);
      files['lib/ads.dart'] =
          'AppTrackingTransparency.requestTrackingAuthorization();';
      expect(_run(trackingRule, files), Status.pass);
    });

    test('I4 needs Sign in with Apple and account deletion', () {
      final files = {
        'pubspec.yaml': _pubspec(['google_sign_in']),
      };
      expect(_run(appleSignInRule, files), Status.fail);
      files['pubspec.yaml'] = _pubspec([
        'google_sign_in',
        'sign_in_with_apple',
      ]);
      expect(_run(appleSignInRule, files), Status.fail);
      files['lib/settings.dart'] = 'onTap: deleteAccount,';
      expect(_run(appleSignInRule, files), Status.pass);
    });

    test('I5 fails on the Google sample ad id', () {
      expect(
        _run(plistHygieneRule, {
          'pubspec.yaml': _pubspec(['google_mobile_ads']),
          _plistPath:
              '${_plist({'GADApplicationIdentifier': 'ca-app-pub-3940256099942544~1458002511'})}'
              '<key>ITSAppUsesNonExemptEncryption</key><false/>',
        }),
        Status.fail,
      );
    });
  });

  group('Android', () {
    test('A1 compares targetSdk with the configured floor', () {
      const gradle = 'android/app/build.gradle';
      expect(_run(targetSdkRule, {gradle: 'targetSdkVersion 34'}), Status.fail);
      expect(_run(targetSdkRule, {gradle: 'targetSdkVersion 35'}), Status.pass);
      expect(
        _run(targetSdkRule, {
          gradle: 'targetSdkVersion 35',
        }, config: const Config(playMinTargetSdk: 36)),
        Status.fail,
      );
      expect(
        _run(targetSdkRule, {gradle: 'targetSdk = flutter.targetSdkVersion'}),
        Status.warn,
      );
    });

    test('A2 needs a build number above the highest tag', () {
      final files = {'pubspec.yaml': _pubspec([], version: '1.2.0+10')};
      expect(_run(versionCodeRule, files, tags: ['v1.1.0+10']), Status.fail);
      expect(_run(versionCodeRule, files, tags: ['v1.1.0+9']), Status.pass);
      expect(_run(versionCodeRule, files), Status.pass);
    });

    test('A3 fails on an unused restricted permission, warns when used', () {
      const perm =
          '<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />';
      expect(_run(sensitivePermissionsRule, {_manifest: perm}), Status.fail);
      expect(
        _run(sensitivePermissionsRule, {
          _manifest: perm,
          'lib/call.dart': 'AndroidNotificationDetails(fullScreenIntent: true)',
        }),
        Status.warn,
      );
    });

    test('A4 fails when a service type lacks its permission', () {
      const service =
          '<service android:foregroundServiceType="camera|mediaPlayback" />';
      expect(_run(foregroundServiceRule, {_manifest: service}), Status.fail);
      expect(missingForegroundPermissions(service), [
        'android.permission.FOREGROUND_SERVICE_CAMERA',
        'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK',
      ]);
    });

    test('A5 fails on an intent-filter component without exported', () {
      const bad =
          '<activity android:name=".Main"><intent-filter></intent-filter></activity>';
      const good =
          '<activity android:name=".Main" android:exported="true"><intent-filter></intent-filter></activity>';
      expect(_run(componentsRule, {_manifest: bad}), Status.fail);
      expect(_run(componentsRule, {_manifest: good}), Status.pass);
    });

    test('A6 catches the flutter create debug-key template', () {
      const kts = '''
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }''';
      const groovy = '''
    buildTypes {
        release {
            signingConfig signingConfigs.debug
        }
    }''';
      const fallback = '''
    buildTypes {
        release {
            signingConfig = if (f.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }''';
      expect(
        _run(signingRule, {'android/app/build.gradle.kts': kts}),
        Status.fail,
      );
      expect(
        _run(signingRule, {'android/app/build.gradle': groovy}),
        Status.fail,
      );
      expect(
        _run(signingRule, {'android/app/build.gradle.kts': fallback}),
        Status.fail,
      );
      expect(
        _run(signingRule, {
          'android/app/build.gradle.kts': fallback,
          'android/key.properties': '',
        }),
        Status.pass,
      );
    });
  });

  group('policy', () {
    const stripe = 'Stripe.instance.presentPaymentSheet();';

    test('P1 fails on an iOS bypass, warns when goods are unknown', () {
      expect(
        _run(iosPaymentsRule, {
          'lib/w.dart': 'bool get iap => isIOS && !bypass;\n$stripe',
        }),
        Status.fail,
      );
      expect(_run(iosPaymentsRule, {'lib/w.dart': stripe}), Status.warn);
      expect(
        _run(iosPaymentsRule, {
          'lib/w.dart': stripe,
        }, config: const Config(sellsDigitalGoods: false)),
        Status.pass,
      );
    });

    test('P2 fails for digital goods without Play Billing', () {
      expect(
        _run(playBillingRule, {
          'lib/w.dart': stripe,
        }, config: const Config(sellsDigitalGoods: true)),
        Status.fail,
      );
      expect(
        _run(playBillingRule, {
          'lib/w.dart': stripe,
          'pubspec.yaml': _pubspec(['in_app_purchase']),
        }, config: const Config(sellsDigitalGoods: true)),
        Status.pass,
      );
    });

    test('P3 flags review switches in UI, not in models', () {
      expect(
        _run(hiddenFeaturesRule, {
          'lib/features/x/models/m.dart': 'bool isInReview;',
        }),
        Status.pass,
      );
      expect(
        _run(hiddenFeaturesRule, {
          'lib/features/x/pages/p.dart': 'if (config.isInReview) return;',
        }),
        Status.fail,
      );
    });

    test('P4 is manual until ugc.dirs is set, then needs report + block', () {
      final files = {
        'lib/feed/a.dart': 'ReportSheet()',
        'lib/chat/a.dart': 'Bubble()',
        'lib/profile/b.dart': 'blockUser();',
      };
      expect(_run(ugcSafetyRule, files), Status.manual);
      const config = Config(ugcDirs: ['lib/feed', 'lib/chat']);
      expect(_run(ugcSafetyRule, files, config: config), Status.fail);
      files['lib/chat/a.dart'] = 'showReportSheet()';
      expect(_run(ugcSafetyRule, files, config: config), Status.pass);
    });

    test('P6 only counts .env under flutter: assets', () {
      const text =
          'flutter:\n  assets:\n    - .env.dev\nflutter_gen:\n  exclude:\n    - .env.dev\n';
      final finding = bundledSecretsRule.check(
        Context(MemoryRepo({'pubspec.yaml': text}), const Config()),
      );
      expect(finding.status, Status.warn);
      expect(finding.evidence, hasLength(1));
    });
  });

  test('waivers and disabled rules', () {
    final ctx = Context(
      MemoryRepo({'android/app/build.gradle': 'targetSdkVersion 1'}),
      const Config(waivers: {'A1': 'accepted'}, disabled: {'A2'}),
    );
    final results = runRules(ctx, [targetSdkRule, versionCodeRule]);
    expect(results.single.status, Status.waived);
  });

  test('minLoadAlign reads the LOAD segment alignment', () {
    Uint8List elf(int align) {
      final b = ByteData(0x40 + 0x38)
        ..setUint32(0, 0x464c457f, Endian.little)
        ..setUint8(4, 2)
        ..setUint8(5, 1)
        ..setUint64(0x20, 0x40, Endian.little)
        ..setUint16(0x36, 0x38, Endian.little)
        ..setUint16(0x38, 1, Endian.little)
        ..setUint32(0x40, 1, Endian.little)
        ..setUint64(0x40 + 0x30, align, Endian.little);
      return b.buffer.asUint8List();
    }

    expect(minLoadAlign(elf(4096)), 4096);
    expect(minLoadAlign(elf(16384)), 16384);
    expect(minLoadAlign(Uint8List(10)), isNull);
  });
}
