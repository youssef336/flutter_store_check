import 'dart:io';

import 'package:flutter_store_check/flutter_store_check.dart';
import 'package:flutter_store_check/src/fix.dart';
import 'package:test/test.dart';

const String _manifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
    <application android:label="app">
        <service android:name=".S" android:foregroundServiceType="camera" android:exported="false" />
    </application>
</manifest>
''';

void main() {
  group('fix transforms', () {
    test('removePermissions drops the whole line', () {
      final out = removePermissions(_manifest, [
        'android.permission.USE_FULL_SCREEN_INTENT',
      ]);
      expect(out, isNot(contains('USE_FULL_SCREEN_INTENT')));
      expect(out, contains('READ_EXTERNAL_STORAGE'));
    });

    test('capReadExternalStorage adds maxSdkVersion once', () {
      final once = capReadExternalStorage(_manifest);
      expect(once, contains('android:maxSdkVersion="32"'));
      expect(capReadExternalStorage(once), once);
    });

    test('addPermissions inserts before <application', () {
      final out = addPermissions(_manifest, [
        'android.permission.FOREGROUND_SERVICE_CAMERA',
      ]);
      expect(
        out.indexOf('FOREGROUND_SERVICE_CAMERA'),
        lessThan(out.indexOf('<application')),
      );
    });

    test('privacyManifestTemplate declares each category with its reason', () {
      final out = privacyManifestTemplate([
        'NSPrivacyAccessedAPICategoryUserDefaults',
      ]);
      expect(out, contains('NSPrivacyAccessedAPICategoryUserDefaults'));
      expect(out, contains('CA92.1'));
    });
  });

  test('applyFixes edits a project on disk and the rules then pass', () {
    final dir = Directory.systemTemp.createTempSync('store_check_fix');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/android/app/src/main/AndroidManifest.xml')
      ..createSync(recursive: true)
      ..writeAsStringSync(_manifest);
    final repo = DiskRepo(dir.path, tags: const []);
    final ctx = Context(repo, const Config());

    expect(applyFixes(dir.path, ctx, dryRun: true), hasLength(3));
    expect(repo.read('android/app/src/main/AndroidManifest.xml'), _manifest);

    applyFixes(dir.path, ctx);
    final ids = runRules(
      ctx,
      allRules,
    ).where((r) => r.status == Status.fail).map((r) => r.rule.id);
    expect(ids, isNot(contains('A3')));
    expect(ids, isNot(contains('A4')));
  });

  group('reports', () {
    final report = Report(
      results: runRules(
        Context(
          MemoryRepo({'android/app/build.gradle': 'targetSdkVersion 1'}),
          const Config(),
        ),
        allRules,
      ),
      version: '1.0.0+1',
      commit: 'abc',
      branch: 'main',
      generatedAt: DateTime.utc(2026),
    );

    test('github output is one annotation per fail / warn', () {
      final lines = report
          .toGithub()
          .split('\n')
          .where((l) => l.startsWith('::'))
          .toList();
      expect(lines, isNotEmpty);
      expect(lines.first, startsWith('::error'));
      expect(lines.every((l) => !l.contains('\n')), isTrue);
    });

    test('html embeds the report and cannot close its script early', () {
      final html = renderHtml(report);
      expect(html, startsWith('<!doctype html>'));
      expect(html, isNot(contains('__REPORT_JSON__')));
      expect(html.split('</script>'), hasLength(2));
    });

    test('config parsing rejects bad types and reads every section', () {
      expect(() => Config.parse('android: 3'), throwsA(isA<ConfigException>()));
      final c = Config.parse(exampleConfig);
      expect(c.sellsDigitalGoods, isFalse);
      expect(c.playMinTargetSdk, 35);
      expect(c.ugcDirs, isEmpty);
    });
  });
}
