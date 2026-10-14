/// Google Play rules that read the Android project.
library;

import '../model.dart';
import '../sources.dart';

final List<Rule> androidRules = [
  targetSdkRule,
  versionCodeRule,
  sensitivePermissionsRule,
  foregroundServiceRule,
  componentsRule,
  signingRule,
];

final Rule targetSdkRule = Rule(
  id: 'A1',
  store: Store.googlePlay,
  guideline: 'Target API level requirement',
  title: 'targetSdk meets the Play floor',
  fix:
      'Set targetSdk in the app Gradle file to at least the Play floor (android.min_target_sdk).',
  check: (ctx) {
    final path = gradleFile(ctx);
    final text = ctx.repo.read(path);
    final floor = ctx.config.playMinTargetSdk;
    final m = RegExp(
      r'targetSdk(?:Version)?\s*=?\s*(\S+)',
    ).firstMatch(text ?? '');
    final value = int.tryParse(m?[1] ?? '');
    if (value == null) {
      return Finding(
        Status.warn,
        'targetSdk is not a literal (${m?[1] ?? 'not found'}); cannot verify it is ≥ $floor. '
        'flutter.targetSdkVersion follows your Flutter version.',
      );
    }
    if (value < floor) {
      return Finding(
        Status.fail,
        'targetSdk $value < $floor: Play blocks the update.',
        evidence: [at(path, text, m![0]!)],
      );
    }
    return Finding.pass('targetSdk $value.');
  },
);

final Rule versionCodeRule = Rule(
  id: 'A2',
  store: Store.both,
  guideline: 'Upload: versionCode / CFBundleVersion must increase',
  title: 'Build number above the last release',
  fix:
      'Bump the +N part of `version:` in pubspec.yaml above the highest released build.',
  check: (ctx) {
    final current = buildNumber(ctx.repo.read(pubspec));
    final released = [
      for (final t in ctx.repo.tags)
        int.tryParse(RegExp(r'\+(\d+)$').firstMatch(t)?[1] ?? '') ?? 0,
    ];
    if (current == null) {
      return const Finding(
        Status.fail,
        'pubspec.yaml `version:` has no +build number.',
      );
    }
    if (released.isEmpty) {
      return Finding.pass(
        'Build $current (no `v*+N` release tags to compare with).',
      );
    }
    final highest = released.reduce((a, b) => a > b ? a : b);
    if (current <= highest) {
      return Finding(
        Status.fail,
        'Build $current is not above the last tagged release (+$highest). Both stores reject it.',
      );
    }
    return Finding.pass('Build $current > last tag +$highest.');
  },
);

/// Restricted permission → code that proves the app uses it. An unused one
/// is removed; a used one needs a Play Console declaration.
final Map<String, RegExp> restrictedPermissions = {
  'android.permission.USE_FULL_SCREEN_INTENT': RegExp(
    r'fullScreenIntent|setFullScreenIntent',
  ),
  'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS': RegExp(
    r'ignoreBatteryOptimizations|IGNORE_BATTERY_OPTIMIZATION|isIgnoringBatteryOptimizations',
  ),
  'android.permission.QUERY_ALL_PACKAGES': RegExp(
    r'getInstalledPackages|getInstalledApps',
  ),
  'android.permission.MANAGE_EXTERNAL_STORAGE': RegExp(
    r'manageExternalStorage|MANAGE_ALL_FILES',
  ),
  'android.permission.SCHEDULE_EXACT_ALARM': RegExp(
    r'exactAllowWhileIdle|setExact|exact:\s*true',
  ),
  'android.permission.ACCESS_BACKGROUND_LOCATION': RegExp(
    r'locationAlways|BACKGROUND_LOCATION',
  ),
  'android.permission.REQUEST_INSTALL_PACKAGES': RegExp(
    r'installApk|REQUEST_INSTALL_PACKAGES|open_filex',
  ),
  'android.permission.READ_SMS': RegExp(r'readSms|SmsManager|telephony'),
  'android.permission.RECEIVE_SMS': RegExp(
    r'SmsReceiver|telephony|sms_autofill',
  ),
  'android.permission.READ_CALL_LOG': RegExp(r'CallLog|call_log'),
  'android.permission.BIND_ACCESSIBILITY_SERVICE': RegExp(
    r'AccessibilityService',
  ),
};

final Rule sensitivePermissionsRule = Rule(
  id: 'A3',
  store: Store.googlePlay,
  guideline:
      'Permissions and APIs that Access Sensitive Information · Photo and Video Permissions',
  title: 'Sensitive permissions',
  fix:
      'Delete every permission marked "unused" (`store_check fix` does it). For the ones in use, '
      'file the Permissions Declaration in Play Console. READ_EXTERNAL_STORAGE needs '
      'android:maxSdkVersion="32"; READ_MEDIA_IMAGES/VIDEO need the Photo & Video declaration, '
      'or switch to the system photo picker.',
  check: (ctx) {
    final path = ctx.config.androidManifest;
    final text = ctx.repo.read(path);
    final perms = manifestPermissions(text);
    final fails = <String>[];
    final warns = <String>[];
    for (final p in unusedRestrictedPermissions(ctx)) {
      fails.add('${at(path, text, p)}  (unused)');
    }
    for (final p in restrictedPermissions.keys) {
      if (perms.containsKey(p) && !fails.any((f) => f.contains(p))) {
        warns.add('${at(path, text, p)}  (used: needs Play declaration)');
      }
    }
    final read = perms['android.permission.READ_EXTERNAL_STORAGE'];
    if (read != null && !read.contains('maxSdkVersion')) {
      warns.add(
        '${at(path, text, 'android.permission.READ_EXTERNAL_STORAGE')}  (no maxSdkVersion)',
      );
    }
    for (final p in [
      'android.permission.READ_MEDIA_IMAGES',
      'android.permission.READ_MEDIA_VIDEO',
    ]) {
      if (perms.containsKey(p)) {
        warns.add('${at(path, text, p)}  (Photo & Video declaration required)');
      }
    }
    if (fails.isNotEmpty) {
      return Finding(
        Status.fail,
        'Restricted permissions declared but never used: Play rejects these.',
        evidence: [...fails, ...warns],
      );
    }
    if (warns.isNotEmpty) {
      return Finding(
        Status.warn,
        'Sensitive permissions need a console declaration.',
        evidence: warns,
      );
    }
    return const Finding.pass('No restricted permissions.');
  },
);

/// Restricted permissions in the manifest that no code in the project uses.
List<String> unusedRestrictedPermissions(Context ctx) {
  final perms = manifestPermissions(ctx.repo.read(ctx.config.androidManifest));
  return [
    for (final e in restrictedPermissions.entries)
      if (perms.containsKey(e.key) &&
          ctx.repo.grep(e.value, [
            ...ctx.config.codeDirs,
            ...nativeAndroidDirs,
          ]).isEmpty &&
          ctx.repo.grep(e.value, nativeAndroidDirs, ext: '.kt').isEmpty &&
          ctx.repo.grep(e.value, nativeAndroidDirs, ext: '.java').isEmpty)
        e.key,
  ];
}

/// Foreground service types used in the manifest that lack their
/// `FOREGROUND_SERVICE_<TYPE>` permission.
List<String> missingForegroundPermissions(String? manifest) {
  final perms = manifestPermissions(manifest);
  final types = <String>{
    for (final m in RegExp(
      r'foregroundServiceType="([^"]+)"',
    ).allMatches(manifest ?? ''))
      ...m[1]!.split('|'),
  };
  return [
    for (final t in types)
      if (!perms.containsKey(
        'android.permission.FOREGROUND_SERVICE_${snake(t)}',
      ))
        'android.permission.FOREGROUND_SERVICE_${snake(t)}',
  ];
}

/// `mediaPlayback` → `MEDIA_PLAYBACK`.
String snake(String camel) =>
    camel.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m[0]}').toUpperCase();

final Rule foregroundServiceRule = Rule(
  id: 'A4',
  store: Store.googlePlay,
  guideline: 'Foreground service types (Android 14)',
  title: 'Foreground services',
  fix:
      'Declare FOREGROUND_SERVICE_<TYPE> for each type (`store_check fix` adds them), and file '
      'the Foreground service declaration with a demo video per type in Play Console.',
  check: (ctx) {
    final text = ctx.repo.read(ctx.config.androidManifest) ?? '';
    final types = {
      for (final m in RegExp(
        r'foregroundServiceType="([^"]+)"',
      ).allMatches(text))
        ...m[1]!.split('|'),
    };
    if (types.isEmpty) {
      return const Finding.pass('No foreground services.');
    }
    final missing = missingForegroundPermissions(text);
    if (missing.isNotEmpty) {
      return Finding(
        Status.fail,
        'Foreground service types without their permission (SecurityException on start).',
        evidence: missing,
      );
    }
    return Finding(
      Status.manual,
      'Types in use: ${types.join(', ')}. Each needs the Play Console declaration and a video.',
    );
  },
);

final Rule componentsRule = Rule(
  id: 'A5',
  store: Store.googlePlay,
  guideline: 'Upload: android:exported (API 31+) · cleartext',
  title: 'Manifest components',
  fix:
      'Give every activity, service and receiver with an <intent-filter> an explicit '
      'android:exported, and remove android:usesCleartextTraffic="true".',
  check: (ctx) {
    final path = ctx.config.androidManifest;
    final text = ctx.repo.read(path) ?? '';
    final issues = <String>[];
    final re = RegExp(
      r'<(activity|service|receiver)\b([^>]*?)(?<!/)>(.*?)</\1>',
      dotAll: true,
    );
    for (final m in re.allMatches(text)) {
      if (m[3]!.contains('<intent-filter') &&
          !m[2]!.contains('android:exported')) {
        final name =
            RegExp(r'android:name="([^"]+)"').firstMatch(m[2]!)?[1] ?? m[1]!;
        issues.add('${at(path, text, name)}  (intent-filter without exported)');
      }
    }
    final fail = issues.isNotEmpty;
    if (text.contains('android:usesCleartextTraffic="true"')) {
      issues.add(at(path, text, 'android:usesCleartextTraffic="true"'));
    }
    if (issues.isEmpty) {
      return const Finding.pass(
        'Components declare exported; no global cleartext.',
      );
    }
    return Finding(
      fail ? Status.fail : Status.warn,
      'Manifest component issues.',
      evidence: issues,
    );
  },
);

final Rule signingRule = Rule(
  id: 'A6',
  store: Store.googlePlay,
  guideline: 'Upload: signed with the upload key, not debuggable',
  title: 'Release signing',
  fix:
      'Create android/key.properties with your upload keystore, and sign release with it. The '
      '`flutter create` template signs release with the DEBUG key until you change it.',
  check: (ctx) {
    final path = gradleFile(ctx);
    final text = ctx.repo.read(path) ?? '';
    final release =
        RegExp(
          r'release\s*\{(.*?)\n\s{8}\}',
          dotAll: true,
        ).firstMatch(text)?[1] ??
        '';
    if (RegExp(r'(isD|d)ebuggable\s*=?\s*true').hasMatch(release)) {
      return Finding(
        Status.fail,
        'Release build type is debuggable.',
        evidence: [at(path, text, 'ebuggable')],
      );
    }
    final debugKey = RegExp(
      r'''signingConfig(s\.getByName\("debug"\)|\s*=?\s*signingConfigs\.debug)''',
    );
    final usesDebug = debugKey.hasMatch(release);
    final hasRelease = RegExp(
      r'''getByName\("release"\)|signingConfigs\.release''',
    ).hasMatch(release);
    if (usesDebug && !hasRelease) {
      return Finding(
        Status.fail,
        'Release is always signed with the debug key: Play rejects the upload.',
        evidence: [at(path, text, 'debug')],
      );
    }
    if (usesDebug && !ctx.repo.exists('android/key.properties')) {
      return Finding(
        Status.fail,
        'android/key.properties is missing here, so release falls back to the DEBUG key.',
        evidence: [at(path, text, 'debug')],
      );
    }
    return const Finding.pass('Release signs with the upload key.');
  },
);
