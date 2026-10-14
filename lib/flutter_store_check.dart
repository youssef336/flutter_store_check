/// Catch Google Play and App Store rejection causes in a Flutter project
/// before you upload.
library;

export 'src/cli.dart' show exampleConfig, runCli;
export 'src/config.dart' show Config, ConfigException, configFileName;
export 'src/engine.dart' show allRules, runRules;
export 'src/fix.dart' show FixChange, applyFixes;
export 'src/model.dart';
export 'src/report/html.dart' show renderHtml;
export 'src/report/report.dart' show Report;
