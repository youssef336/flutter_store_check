/// Core types: a [Rule] inspects a [Repo] and returns a [Finding].
///
/// Rules never touch the filesystem directly, so every rule can be tested
/// against an in-memory [MemoryRepo].
library;

import 'dart:io';

import 'config.dart';

/// Which store a rule speaks for.
enum Store { appStore, googlePlay, both }

/// Ordered from most to least severe; reports sort by this.
enum Status { fail, warn, manual, waived, pass }

/// What a rule found.
class Finding {
  const Finding(this.status, this.message, {this.evidence = const []});

  const Finding.pass(this.message) : status = Status.pass, evidence = const [];

  final Status status;
  final String message;

  /// `path:line  snippet` entries pointing at what triggered the finding.
  final List<String> evidence;
}

/// Everything a rule can read: the project and its config.
class Context {
  const Context(this.repo, this.config);

  final Repo repo;
  final Config config;
}

/// One store-review rule.
class Rule {
  const Rule({
    required this.id,
    required this.store,
    required this.guideline,
    required this.title,
    required this.fix,
    required this.check,
    this.needsDecision = false,
  });

  final String id;
  final Store store;

  /// Guideline / policy reference as the store cites it, e.g. `3.1.1`.
  final String guideline;
  final String title;

  /// How to make the rule pass.
  final String fix;
  final Finding Function(Context ctx) check;

  /// The fix is a product or business decision (payments, review switches),
  /// not something a tool should change on its own.
  final bool needsDecision;
}

/// A rule paired with its finding and, optionally, an accepted-risk waiver.
class Result {
  const Result(this.rule, this.finding, {this.waiver});

  final Rule rule;
  final Finding finding;

  /// Why a failing rule was accepted (from the config); null when not waived.
  final String? waiver;

  Status get status => waiver != null && finding.status != Status.pass
      ? Status.waived
      : finding.status;

  Map<String, Object?> toJson() => {
    'id': rule.id,
    'store': rule.store.name,
    'guideline': rule.guideline,
    'title': rule.title,
    'fix': rule.fix,
    'needsDecision': rule.needsDecision,
    'status': status.name,
    'message': finding.message,
    'evidence': finding.evidence,
    'waiver': waiver,
  };
}

/// Read-only view of the project the rules inspect.
abstract class Repo {
  String? read(String path);

  bool exists(String path) => read(path) != null;

  /// Every file path under [dir] ending in [ext] (repo-relative, `/`-separated).
  List<String> files(String dir, String ext);

  /// Release tags (`v1.2.3+45`) known to git.
  List<String> get tags;

  /// `path:line  snippet` for each line of the files under [dirs] matching
  /// [pattern]. Generated code is skipped.
  List<String> grep(
    RegExp pattern,
    List<String> dirs, {
    String ext = '.dart',
  }) => [
    for (final dir in dirs)
      for (final path in files(dir, ext))
        if (!_generated(path)) ...hits(pattern, path),
  ];

  /// `path:line  snippet` for each line of [path] matching [pattern].
  List<String> hits(RegExp pattern, String path) {
    final lines = (read(path) ?? '').split('\n');
    return [
      for (var i = 0; i < lines.length; i++)
        if (pattern.hasMatch(lines[i])) '$path:${i + 1}  ${lines[i].trim()}',
    ];
  }

  static bool _generated(String path) =>
      path.contains('/generated/') ||
      path.endsWith('.g.dart') ||
      path.endsWith('.freezed.dart') ||
      path.endsWith('.gr.dart');
}

/// A project on disk.
class DiskRepo extends Repo {
  DiskRepo(this.root, {List<String>? tags}) : _tags = tags;

  final String root;
  List<String>? _tags;

  @override
  String? read(String path) {
    final f = File('$root/$path');
    return f.existsSync() ? f.readAsStringSync() : null;
  }

  /// Existence only, so secrets such as android/key.properties are never read.
  @override
  bool exists(String path) =>
      FileSystemEntity.typeSync('$root/$path') != FileSystemEntityType.notFound;

  @override
  List<String> files(String dir, String ext) {
    final d = Directory('$root/$dir');
    if (!d.existsSync()) {
      return const [];
    }
    return [
      for (final e in d.listSync(recursive: true))
        if (e is File && e.path.endsWith(ext))
          e.path.substring(root.length + 1),
    ]..sort();
  }

  @override
  List<String> get tags => _tags ??= _gitTags();

  List<String> _gitTags() {
    try {
      final r = Process.runSync('git', [
        'tag',
        '-l',
        'v*',
      ], workingDirectory: root);
      if (r.exitCode != 0) {
        return const [];
      }
      return (r.stdout as String)
          .split('\n')
          .where((t) => t.isNotEmpty)
          .toList();
    } on ProcessException {
      return const [];
    }
  }
}

/// A project held in memory, for tests.
class MemoryRepo extends Repo {
  MemoryRepo(this.contents, {this.tags = const []});

  final Map<String, String> contents;

  @override
  final List<String> tags;

  @override
  String? read(String path) => contents[path];

  @override
  List<String> files(String dir, String ext) => [
    for (final p in contents.keys)
      if (p.startsWith('$dir/') && p.endsWith(ext)) p,
  ]..sort();
}
