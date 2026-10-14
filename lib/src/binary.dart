/// Checks on the built artifacts (AAB / IPA). These see what actually ships:
/// merged manifests, plugin native libraries, embedded frameworks and the
/// real signing entitlements, which the source rules cannot.
library;

import 'dart:io';
import 'dart:typed_data';

import 'model.dart';

const int _pageSize16k = 16384;

/// Smallest LOAD-segment alignment of a 64-bit ELF, or null when [bytes] is
/// not a 64-bit little-endian ELF (32-bit ABIs are exempt from the 16 KB rule).
int? minLoadAlign(Uint8List bytes) {
  if (bytes.length < 64 ||
      bytes[0] != 0x7f ||
      bytes[1] != 0x45 ||
      bytes[4] != 2 ||
      bytes[5] != 1) {
    return null;
  }
  final d = ByteData.sublistView(bytes);
  final phoff = d.getUint64(0x20, Endian.little);
  final phentsize = d.getUint16(0x36, Endian.little);
  final phnum = d.getUint16(0x38, Endian.little);
  int? min;
  for (var i = 0; i < phnum; i++) {
    final off = phoff + i * phentsize;
    if (off + 0x38 > bytes.length) {
      break;
    }
    if (d.getUint32(off, Endian.little) == 1) {
      final align = d.getUint64(off + 0x30, Endian.little);
      min = min == null || align < min ? align : min;
    }
  }
  return min;
}

/// Binary checks are computed up front; the rule just reports the result.
Rule _binary(
  String id,
  Store store,
  String guideline,
  String title,
  String fix,
  Finding finding,
) => Rule(
  id: id,
  store: store,
  guideline: guideline,
  title: title,
  fix: fix,
  check: (_) => finding,
);

List<String> _zipEntries(String archive) {
  final r = Process.runSync('unzip', ['-Z1', archive]);
  return r.exitCode == 0
      ? (r.stdout as String).split('\n').where((e) => e.isNotEmpty).toList()
      : const [];
}

Uint8List _zipRead(String archive, String entry) {
  final r = Process.runSync('unzip', [
    '-p',
    archive,
    entry,
  ], stdoutEncoding: null);
  return Uint8List.fromList(r.stdout as List<int>);
}

/// Rules B1–B2 for an Android App Bundle at [aab].
List<Rule> aabRules(String aab) {
  final entries = _zipEntries(aab);
  final libs = entries
      .where((e) => RegExp(r'/lib/(arm64-v8a|x86_64)/[^/]+\.so$').hasMatch(e))
      .toList();
  final bad = <String>[];
  for (final lib in libs) {
    final align = minLoadAlign(_zipRead(aab, lib));
    if (align != null && align < _pageSize16k) {
      bad.add('$lib  (p_align $align)');
    }
  }
  final rules = [
    _binary(
      'B1',
      Store.googlePlay,
      '16 KB page size (targetSdk 35+)',
      'Native libraries are 16 KB aligned',
      'Rebuild the listed libraries with NDK r28+ / -Wl,-z,max-page-size=16384, or upgrade the '
          'plugin that ships them (see the library name for which plugin it is).',
      entries.isEmpty
          ? Finding(Status.fail, 'Could not read $aab.')
          : bad.isEmpty
          ? Finding.pass(
              '${libs.length} 64-bit .so files, all ≥ 16 KB aligned.',
            )
          : Finding(
              Status.fail,
              '${bad.length}/${libs.length} libraries are 4 KB aligned.',
              evidence: bad,
            ),
    ),
  ];

  final dump = Process.runSync('bundletool', [
    'dump',
    'manifest',
    '--bundle',
    aab,
  ], runInShell: true);
  rules.add(
    _binary(
      'B2',
      Store.googlePlay,
      'Merged manifest',
      'Merged manifest (plugins included)',
      'Remove plugin-added permissions you do not need with tools:node="remove" in the app manifest.',
      dump.exitCode != 0
          ? const Finding(
              Status.warn,
              'bundletool not on PATH — merged manifest not checked (brew install bundletool).',
            )
          : _mergedManifest(dump.stdout as String),
    ),
  );
  return rules;
}

const List<String> _restricted = [
  'USE_FULL_SCREEN_INTENT',
  'REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
  'QUERY_ALL_PACKAGES',
  'MANAGE_EXTERNAL_STORAGE',
  'SCHEDULE_EXACT_ALARM',
  'ACCESS_BACKGROUND_LOCATION',
  'REQUEST_INSTALL_PACKAGES',
  'READ_SMS',
  'READ_CALL_LOG',
];

Finding _mergedManifest(String xml) {
  final issues = [
    if (xml.contains('android:debuggable="true"')) 'application is debuggable',
    for (final p in _restricted)
      if (xml.contains('android.permission.$p"'))
        'android.permission.$p in the merged manifest',
  ];
  return issues.isEmpty
      ? const Finding.pass(
          'Merged manifest: not debuggable, no restricted permissions.',
        )
      : Finding(Status.fail, 'Merged manifest problems.', evidence: issues);
}

/// Rules B3–B4 for an exported iOS archive at [ipa] (B4 needs macOS).
List<Rule> ipaRules(String ipa) {
  final tmp = Directory.systemTemp.createTempSync('store_check_ipa');
  try {
    final unzip = Process.runSync('unzip', [
      '-q',
      ipa,
      'Payload/*',
      '-d',
      tmp.path,
    ]);
    final payload = Directory('${tmp.path}/Payload');
    final app = unzip.exitCode == 0 && payload.existsSync()
        ? payload
              .listSync()
              .whereType<Directory>()
              .where((d) => d.path.endsWith('.app'))
              .firstOrNull
        : null;
    if (app == null) {
      return [
        _binary(
          'B3',
          Store.appStore,
          'IPA',
          'IPA readable',
          'Pass the exported .ipa.',
          Finding(Status.fail, 'Could not unpack $ipa.'),
        ),
      ];
    }
    final frameworks = Directory('${app.path}/Frameworks');
    final noManifest = [
      if (frameworks.existsSync())
        for (final f in frameworks.listSync().whereType<Directory>())
          if (f.path.endsWith('.framework') &&
              !File('${f.path}/PrivacyInfo.xcprivacy').existsSync())
            f.path.split('/').last,
    ];
    final hasAppManifest = File(
      '${app.path}/PrivacyInfo.xcprivacy',
    ).existsSync();
    final ent = _run('codesign', [
      '-d',
      '--entitlements',
      '-',
      '--xml',
      app.path,
    ]);
    final entitlements = '${ent?.stdout ?? ''}';
    final entIssues = [
      if (!RegExp(
            r'aps-environment</key>\s*<string>production',
          ).hasMatch(entitlements) &&
          entitlements.contains('aps-environment'))
        'aps-environment is not production (push will not work for users)',
      if (RegExp(r'get-task-allow</key>\s*<true').hasMatch(entitlements))
        'get-task-allow = true (development-signed)',
    ];
    return [
      _binary(
        'B3',
        Store.appStore,
        'ITMS-91053 / ITMS-91061',
        'Privacy manifests inside the IPA',
        'Bundle PrivacyInfo.xcprivacy in Runner; upgrade the listed SDKs to versions that ship '
            'their own manifest (Apple lists the SDKs that must).',
        !hasAppManifest
            ? Finding(
                Status.fail,
                'The app bundle has no PrivacyInfo.xcprivacy.',
                evidence: noManifest,
              )
            : noManifest.isEmpty
            ? const Finding.pass(
                'App and every framework ship a privacy manifest.',
              )
            : Finding(
                Status.warn,
                'Frameworks without a privacy manifest.',
                evidence: noManifest,
              ),
      ),
      _binary(
        'B4',
        Store.appStore,
        'Distribution signing',
        'App Store signing entitlements',
        'Export with the App Store distribution profile (Xcode → Distribute App → App Store Connect).',
        ent == null || ent.exitCode != 0
            ? const Finding(
                Status.warn,
                'codesign could not read entitlements (macOS only).',
              )
            : entIssues.isEmpty
            ? const Finding.pass('Distribution-signed, production push.')
            : Finding(
                Status.fail,
                'IPA is not App Store signed.',
                evidence: entIssues,
              ),
      ),
    ];
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

/// Runs [cmd], or null when it is not installed (e.g. codesign off macOS).
ProcessResult? _run(String cmd, List<String> args) {
  try {
    return Process.runSync(cmd, args);
  } on ProcessException {
    return null;
  }
}
