/// Small, dependency-free readers for the project files the rules look at.
///
/// They are regex-based on purpose: the inputs are hand-maintained XML,
/// plist, Gradle and YAML files with a stable shape.
library;

import 'model.dart';

const String pubspec = 'pubspec.yaml';
const List<String> nativeAndroidDirs = [
  'android/app/src/main/kotlin',
  'android/app/src/main/java',
];

/// Top-level `<key>` → value of a plist: the raw string for `<string>`,
/// `'true'`/`'false'` for booleans, the inner XML for dicts and arrays.
Map<String, String> plistKeys(String? xml) {
  if (xml == null) {
    return const {};
  }
  final out = <String, String>{};
  final re = RegExp(
    r'<key>([^<]+)</key>\s*(?:<string>([^<]*)</string>|<(true|false)\s*/>|<(dict|array)>(.*?)</\4>)',
    dotAll: true,
  );
  for (final m in re.allMatches(xml)) {
    out.putIfAbsent(m[1]!, () => m[2] ?? m[3] ?? m[5] ?? '');
  }
  return out;
}

/// Names of the packages under pubspec `dependencies:` (not dev / overrides).
Set<String> dependencies(Repo repo) {
  final out = <String>{};
  var inDeps = false;
  for (final line in (repo.read(pubspec) ?? '').split('\n')) {
    if (RegExp(r'^\S').hasMatch(line)) {
      inDeps = line.startsWith('dependencies:');
      continue;
    }
    final m = RegExp(r'^  ([a-z0-9_]+):').firstMatch(line);
    if (inDeps && m != null) {
      out.add(m[1]!);
    }
  }
  return out;
}

/// `version: 1.2.8+160` → 160.
int? buildNumber(String? pubspecText) {
  final m = RegExp(
    r'^version:\s*\S+\+(\d+)',
    multiLine: true,
  ).firstMatch(pubspecText ?? '');
  return m == null ? null : int.parse(m[1]!);
}

/// `version: 1.2.8+160` → `1.2.8+160`.
String? versionOf(String? pubspecText) => RegExp(
  r'^version:\s*(\S+)',
  multiLine: true,
).firstMatch(pubspecText ?? '')?[1];

/// `uses-permission` names declared in a manifest, mapped to their tag.
Map<String, String> manifestPermissions(String? xml) => {
  for (final m in RegExp(
    r'<uses-permission\b[^>]*?android:name="([^"]+)"[^>]*>',
  ).allMatches(xml ?? ''))
    m[1]!: m[0]!,
};

/// The app's Gradle file: the configured one, else `.kts`, else Groovy.
String gradleFile(Context ctx) =>
    ctx.config.gradle ??
    (ctx.repo.exists('android/app/build.gradle.kts')
        ? 'android/app/build.gradle.kts'
        : 'android/app/build.gradle');

/// 1-based line of the first occurrence of [needle] in [text], or null.
int? lineOf(String? text, String needle) {
  final i = (text ?? '').indexOf(needle);
  return i < 0 ? null : '\n'.allMatches(text!.substring(0, i)).length + 1;
}

/// `path:line  needle`, or just `path` when [needle] is not in [text].
String at(String path, String? text, String needle) {
  final l = lineOf(text, needle);
  return l == null ? path : '$path:$l  ${needle.trim()}';
}

/// One regex that matches any of [patterns].
RegExp anyOf(List<String> patterns) =>
    RegExp(patterns.map((p) => '(?:$p)').join('|'));
