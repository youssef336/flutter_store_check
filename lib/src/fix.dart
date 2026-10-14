/// `store_check fix`: the mechanical fixes that are safe to apply without a
/// person deciding anything. Each transform is a pure text function, so it is
/// testable; [applyFixes] does the file I/O.
library;

import 'dart:io';

import 'model.dart';
import 'rules/android.dart';
import 'rules/ios.dart';
import 'sources.dart';

/// One change `fix` made (or would make, with `--dry-run`).
class FixChange {
  const FixChange(this.ruleId, this.path, this.description);

  final String ruleId;
  final String path;
  final String description;

  @override
  String toString() => '$ruleId  $path: $description';
}

/// Removes every `<uses-permission>` for [names] (with the line it sits on).
String removePermissions(String manifest, Iterable<String> names) {
  var out = manifest;
  for (final n in names) {
    out = out.replaceAll(
      RegExp(
        '[ \\t]*<uses-permission\\b[^>]*android:name="${RegExp.escape(n)}"[^>]*>[ \\t]*\\r?\\n?',
      ),
      '',
    );
  }
  return out;
}

/// Adds `android:maxSdkVersion="32"` to READ_EXTERNAL_STORAGE when it has none.
String capReadExternalStorage(String manifest) => manifest.replaceAllMapped(
  RegExp(
    r'<uses-permission\b([^>]*android:name="android\.permission\.READ_EXTERNAL_STORAGE"[^>]*?)(\s*/?>)',
  ),
  (m) => m[1]!.contains('maxSdkVersion')
      ? m[0]!
      : '<uses-permission${m[1]}\n        android:maxSdkVersion="32"${m[2]}',
);

/// Inserts `<uses-permission>` lines for [names] before `<application`.
String addPermissions(String manifest, Iterable<String> names) {
  if (names.isEmpty) {
    return manifest;
  }
  final i = manifest.indexOf('<application');
  if (i < 0) {
    return manifest;
  }
  final lineStart = manifest.lastIndexOf('\n', i) + 1;
  final indent = manifest.substring(lineStart, i);
  final lines = names
      .map((n) => '$indent<uses-permission android:name="$n" />\n')
      .join();
  return '${manifest.substring(0, lineStart)}$lines\n${manifest.substring(lineStart)}';
}

/// Approved reason codes for the categories store_check knows.
const Map<String, String> reasonCodes = {
  'NSPrivacyAccessedAPICategoryUserDefaults': 'CA92.1',
  'NSPrivacyAccessedAPICategoryFileTimestamp': 'C617.1',
  'NSPrivacyAccessedAPICategorySystemBootTime': '35F9.1',
  'NSPrivacyAccessedAPICategoryDiskSpace': 'E174.1',
};

/// A starter PrivacyInfo.xcprivacy declaring [categories], no tracking and
/// no collected data (fill NSPrivacyCollectedDataTypes from your App Privacy
/// label).
String privacyManifestTemplate(Iterable<String> categories) {
  final apis = [
    for (final c in categories)
      '''
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>$c</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>${reasonCodes[c]}</string>
			</array>
		</dict>
''',
  ].join();
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<key>NSPrivacyCollectedDataTypes</key>
	<array/>
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
$apis	</array>
</dict>
</plist>
''';
}

/// Applies (or with [dryRun] only lists) every safe fix in [root].
List<FixChange> applyFixes(String root, Context ctx, {bool dryRun = false}) {
  final changes = <FixChange>[];
  final c = ctx.config;

  final manifestPath = c.androidManifest;
  final manifest = ctx.repo.read(manifestPath);
  if (manifest != null) {
    var next = manifest;
    final unused = unusedRestrictedPermissions(ctx);
    if (unused.isNotEmpty) {
      next = removePermissions(next, unused);
      changes.add(
        FixChange(
          'A3',
          manifestPath,
          'removed unused ${unused.map(_short).join(', ')}',
        ),
      );
    }
    final capped = capReadExternalStorage(next);
    if (capped != next) {
      next = capped;
      changes.add(
        FixChange(
          'A3',
          manifestPath,
          'READ_EXTERNAL_STORAGE maxSdkVersion="32"',
        ),
      );
    }
    final fgs = missingForegroundPermissions(next);
    if (fgs.isNotEmpty) {
      next = addPermissions(next, fgs);
      changes.add(
        FixChange('A4', manifestPath, 'added ${fgs.map(_short).join(', ')}'),
      );
    }
    if (next != manifest && !dryRun) {
      File('$root/$manifestPath').writeAsStringSync(next);
    }
  }

  if (ctx.repo.read(c.infoPlist) != null &&
      !ctx.repo.exists(c.privacyManifest)) {
    final deps = dependencies(ctx.repo);
    final categories = {
      'NSPrivacyAccessedAPICategoryUserDefaults',
      'NSPrivacyAccessedAPICategoryFileTimestamp',
      for (final e in requiredReasonApis.entries)
        if (e.value.any(deps.contains)) e.key,
    };
    if (!dryRun) {
      File(
        '$root/${c.privacyManifest}',
      ).writeAsStringSync(privacyManifestTemplate(categories));
    }
    changes.add(
      FixChange(
        'I1',
        c.privacyManifest,
        'created with ${categories.length} API categories. Now add it to the Runner target in '
            'Xcode and fill NSPrivacyCollectedDataTypes.',
      ),
    );
  }
  return changes;
}

String _short(String permission) =>
    permission.replaceFirst('android.permission.', '');
