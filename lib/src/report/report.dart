/// Renders results as JSON, Markdown, console text and GitHub annotations.
library;

import '../model.dart';

/// The outcome of one run, in every output format.
class Report {
  const Report({
    required this.results,
    required this.version,
    required this.commit,
    required this.branch,
    required this.generatedAt,
    this.artifacts = const [],
  });

  final List<Result> results;
  final String version;
  final String commit;
  final String branch;
  final DateTime generatedAt;
  final List<String> artifacts;

  int count(Status s) => results.where((r) => r.status == s).length;

  String get verdict => count(Status.fail) > 0
      ? 'REJECT'
      : count(Status.manual) + count(Status.warn) > 0
      ? 'REVIEW'
      : 'READY';

  Map<String, Object?> toJson() => {
    'version': version,
    'commit': commit,
    'branch': branch,
    'generatedAt': generatedAt.toIso8601String(),
    'artifacts': artifacts,
    'verdict': verdict,
    'counts': {for (final s in Status.values) s.name: count(s)},
    'results': [for (final r in results) r.toJson()],
  };

  static const Map<Status, String> _icon = {
    Status.fail: '❌',
    Status.warn: '⚠️',
    Status.manual: '☐',
    Status.waived: '➖',
    Status.pass: '✅',
  };

  static const Map<Store, String> _store = {
    Store.appStore: 'App Store',
    Store.googlePlay: 'Google Play',
    Store.both: 'Both',
  };

  String toMarkdown() {
    final b = StringBuffer()
      ..writeln('# Store Check — $version ($verdict)')
      ..writeln()
      ..writeln(
        'Branch `$branch` @ `$commit`, ${generatedAt.toIso8601String().substring(0, 16)} UTC.',
      )
      ..writeln(
        artifacts.isEmpty
            ? 'Source rules only (no AAB/IPA passed).'
            : 'Artifacts: ${artifacts.join(', ')}.',
      )
      ..writeln()
      ..writeln(
        Status.values
            .map((s) => '${_icon[s]} ${s.name}: ${count(s)}')
            .join(' · '),
      )
      ..writeln()
      ..writeln('| | Rule | Store | Guideline | Finding |')
      ..writeln('|---|---|---|---|---|');
    for (final r in results) {
      b.writeln(
        '| ${_icon[r.status]} | **${r.rule.id}** ${r.rule.title} | ${_store[r.rule.store]} '
        '| ${r.rule.guideline} | ${r.finding.message.replaceAll('|', '\\|')} |',
      );
    }
    b
      ..writeln()
      ..writeln('## Details');
    for (final r in results.where((r) => r.status != Status.pass)) {
      b
        ..writeln()
        ..writeln('### ${_icon[r.status]} ${r.rule.id} — ${r.rule.title}')
        ..writeln()
        ..writeln(r.finding.message);
      if (r.waiver != null) {
        b.writeln('\n**Waived:** ${r.waiver}');
      }
      for (final e in r.finding.evidence) {
        b.writeln('- `$e`');
      }
      b.writeln('\n**Fix:** ${r.rule.fix}');
    }
    return b.toString();
  }

  /// GitHub Actions workflow commands: an error per FAIL, a warning per WARN.
  String toGithub() {
    String esc(String v) => v
        .replaceAll('%', '%25')
        .replaceAll('\r', '%0D')
        .replaceAll('\n', '%0A');
    String prop(String v) =>
        esc(v).replaceAll(':', '%3A').replaceAll(',', '%2C');
    final b = StringBuffer();
    for (final r in results) {
      final level = switch (r.status) {
        Status.fail => 'error',
        Status.warn => 'warning',
        _ => null,
      };
      if (level == null) {
        continue;
      }
      final first = r.finding.evidence.isEmpty
          ? null
          : r.finding.evidence.first;
      final loc = first == null
          ? null
          : RegExp(r'^([^:\s]+):(\d+)').firstMatch(first);
      final where = loc == null ? '' : ' file=${loc[1]},line=${loc[2]},';
      final body = [
        r.finding.message,
        ...r.finding.evidence,
        'Fix: ${r.rule.fix}',
      ].join('\n');
      b.writeln(
        '::$level${where.isEmpty ? ' ' : where}title=${prop('${r.rule.id} ${r.rule.title}')}::${esc(body)}',
      );
    }
    return b.toString();
  }

  String toConsole({bool color = false}) {
    String paint(Status s, String text) {
      if (!color) {
        return text;
      }
      const codes = {
        Status.fail: 31,
        Status.warn: 33,
        Status.manual: 36,
        Status.waived: 90,
        Status.pass: 32,
      };
      return '\x1B[${codes[s]}m$text\x1B[0m';
    }

    final b = StringBuffer()..writeln('Store Check — $version — $verdict\n');
    for (final r in results) {
      b.writeln(
        '${paint(r.status, r.status.name.toUpperCase().padRight(6))} '
        '${r.rule.id.padRight(3)} ${r.rule.title}  [${r.rule.guideline}]',
      );
      if (r.status == Status.fail || r.status == Status.warn) {
        b.writeln('       ${r.finding.message}');
        for (final e in r.finding.evidence.take(6)) {
          b.writeln('         · $e');
        }
      }
    }
    b.writeln(
      '\n${Status.values.map((s) => '${s.name} ${count(s)}').join(' · ')}',
    );
    return b.toString();
  }
}
