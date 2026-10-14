/// The `store_check` command line.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'binary.dart';
import 'config.dart';
import 'engine.dart';
import 'fix.dart';
import 'model.dart';
import 'report/html.dart';
import 'report/report.dart';
import 'sources.dart';

const String _usage = '''
store_check: catch Google Play and App Store rejections before you upload.

Usage:
  store_check [check] [options]   review the project (default command)
  store_check fix [--dry-run]     apply the safe, mechanical fixes
  store_check init                write a commented store_check.yaml
  store_check explain <RULE_ID>   what a rule checks and how to fix it

Exit codes: 0 no FAIL · 1 at least one FAIL (or WARN with --strict) · 2 usage or config error.
''';

/// Runs the CLI with [arguments] and returns the exit code.
int runCli(List<String> arguments, {String? root}) {
  final parser = ArgParser()
    ..addOption('root', help: 'Project root.', defaultsTo: root ?? '.')
    ..addOption(
      'config',
      help: 'Config file, relative to the root.',
      defaultsTo: configFileName,
    )
    ..addOption('aab', help: 'Also check a built Android App Bundle.')
    ..addOption(
      'ipa',
      help: 'Also check an exported .ipa (signing check needs macOS).',
    )
    ..addOption(
      'format',
      allowed: ['text', 'json', 'markdown', 'github'],
      defaultsTo: 'text',
      help: 'What to print to stdout.',
    )
    ..addOption('html', help: 'Write the HTML report to this path.')
    ..addOption('markdown', help: 'Write the Markdown report to this path.')
    ..addOption('json', help: 'Write the JSON report to this path.')
    ..addFlag('strict', negatable: false, help: 'Fail on WARN too.')
    ..addFlag(
      'dry-run',
      negatable: false,
      help: 'fix: list the changes without writing.',
    )
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n$_usage${parser.usage}');
    return 2;
  }
  if (args.flag('help')) {
    stdout.writeln('$_usage\n${parser.usage}');
    return 0;
  }
  final command = args.rest.isEmpty ? 'check' : args.rest.first;
  final dir = args.option('root')!;
  final repo = DiskRepo(Directory(dir).absolute.path);

  if (command == 'init') {
    return _init(repo.root);
  }
  if (command == 'explain') {
    return _explain(args.rest.length > 1 ? args.rest[1] : null);
  }

  final Config config;
  try {
    config = Config.parse(repo.read(args.option('config')!));
  } on ConfigException catch (e) {
    stderr.writeln(e);
    return 2;
  }
  final ctx = Context(repo, config);

  if (command == 'fix') {
    final changes = applyFixes(repo.root, ctx, dryRun: args.flag('dry-run'));
    if (changes.isEmpty) {
      stdout.writeln('store_check fix: nothing to fix automatically.');
    }
    for (final c in changes) {
      stdout.writeln('${args.flag('dry-run') ? 'would fix' : 'fixed'}  $c');
    }
    stdout.writeln(
      'Run `store_check` again to see what is left (some fixes need a person).',
    );
    return 0;
  }
  if (command != 'check') {
    stderr.writeln('Unknown command "$command".\n\n$_usage');
    return 2;
  }

  final aab = args.option('aab');
  final ipa = args.option('ipa');
  final results = runRules(ctx, [
    ...allRules,
    if (aab != null) ...aabRules(aab),
    if (ipa != null) ...ipaRules(ipa),
  ]);
  final report = Report(
    results: results,
    version: versionOf(repo.read(pubspec)) ?? '?',
    commit: _git(repo.root, ['rev-parse', '--short', 'HEAD']),
    branch: _git(repo.root, ['branch', '--show-current']),
    generatedAt: DateTime.now().toUtc(),
    artifacts: [?aab, ?ipa],
  );

  switch (args.option('format')) {
    case 'json':
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert(report.toJson()),
      );
    case 'markdown':
      stdout.write(report.toMarkdown());
    case 'github':
      stdout.write(report.toGithub());
      stdout.write(report.toConsole());
    default:
      stdout.write(
        report.toConsole(
          color: stdout.hasTerminal && stdout.supportsAnsiEscapes,
        ),
      );
  }
  _write(args.option('html'), () => renderHtml(report));
  _write(args.option('markdown'), report.toMarkdown);
  _write(
    args.option('json'),
    () => const JsonEncoder.withIndent('  ').convert(report.toJson()),
  );

  final failing =
      report.count(Status.fail) +
      (args.flag('strict') ? report.count(Status.warn) : 0);
  return failing > 0 ? 1 : 0;
}

void _write(String? path, String Function() render) {
  if (path == null) {
    return;
  }
  final f = File(path)..parent.createSync(recursive: true);
  f.writeAsStringSync(render());
  stderr.writeln('store_check: wrote ${f.path}');
}

String _git(String root, List<String> args) {
  try {
    final r = Process.runSync('git', args, workingDirectory: root);
    return r.exitCode == 0 ? (r.stdout as String).trim() : '';
  } on ProcessException {
    return '';
  }
}

int _explain(String? id) {
  final rule = allRules.where((r) => r.id == id?.toUpperCase()).firstOrNull;
  if (rule == null) {
    stdout.writeln('Rules:');
    for (final r in allRules) {
      stdout.writeln('  ${r.id.padRight(3)} ${r.title}  [${r.guideline}]');
    }
    stdout.writeln('  B1–B4 binary checks (with --aab / --ipa)');
    return id == null ? 0 : 2;
  }
  stdout
    ..writeln('${rule.id}  ${rule.title}')
    ..writeln('Store:     ${rule.store.name}')
    ..writeln('Guideline: ${rule.guideline}')
    ..writeln(
      rule.needsDecision ? 'Decision:  yes (product / business call)' : '',
    )
    ..writeln('Fix:       ${rule.fix}');
  return 0;
}

int _init(String root) {
  final f = File('$root/$configFileName');
  if (f.existsSync()) {
    stderr.writeln('$configFileName already exists; leaving it alone.');
    return 2;
  }
  f.writeAsStringSync(exampleConfig);
  stdout.writeln(
    'Wrote $configFileName. Fill in ugc.dirs and payments.sells_digital_goods.',
  );
  return 0;
}

/// The file `store_check init` writes.
const String exampleConfig = r'''
# store_check.yaml: every key is optional.

# Play's target API floor. Bump it every August 31.
android:
  min_target_sdk: 35
  # manifest: android/app/src/main/AndroidManifest.xml
  # gradle: android/app/build.gradle.kts

# ios:
#   info_plist: ios/Runner/Info.plist
#   privacy_manifest: ios/Runner/PrivacyInfo.xcprivacy

payments:
  # true: coins, subscriptions, premium content (must use IAP / Play Billing).
  # false: physical goods or real-world services (card checkout is fine).
  sells_digital_goods: false
  # external_patterns: ['presentPaymentSheet', 'launchUrl\([^)]*checkout']

# Folders that show other users' content: feeds, comments, chat, live.
ugc:
  dirs: []
  #  - lib/features/feed
  #  - lib/features/chat
  # report_pattern: 'ReportSheet|reportUser'
  # block_pattern: 'blockUser'

# review_flag_patterns: ['isInReview']

# Accepted risks: the rule still shows but no longer fails the run.
waivers: {}
#  P2: Enrolled in User Choice Billing for EEA (2026-03)

# Rules that do not apply to this app.
disabled: []
''';
