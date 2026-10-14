/// Loading `store_check.yaml`. Every key is optional; the defaults fit a
/// standard `flutter create` layout.
library;

import 'package:yaml/yaml.dart';

/// Default config file name, at the project root.
const String configFileName = 'store_check.yaml';

/// Thrown for an unreadable or invalid config.
class ConfigException implements Exception {
  ConfigException(this.message);

  final String message;

  @override
  String toString() => 'store_check.yaml: $message';
}

/// Project-specific knowledge the rules cannot guess.
class Config {
  const Config({
    this.infoPlist = 'ios/Runner/Info.plist',
    this.privacyManifest = 'ios/Runner/PrivacyInfo.xcprivacy',
    this.pbxproj = 'ios/Runner.xcodeproj/project.pbxproj',
    this.podfile = 'ios/Podfile',
    this.androidManifest = 'android/app/src/main/AndroidManifest.xml',
    this.gradle,
    this.codeDirs = const ['lib'],
    this.playMinTargetSdk = 35,
    this.sellsDigitalGoods,
    this.externalPaymentPatterns = defaultExternalPaymentPatterns,
    this.reviewFlagPatterns = defaultReviewFlagPatterns,
    this.ugcDirs = const [],
    this.reportPattern = r'[Rr]eport',
    this.blockPattern = r'[Bb]lock(ed)?[A-Z_(]|blockUser|unblock',
    this.deleteAccountPattern =
        r'delete[-_ ]?account|deleteAccount|DeleteAccount',
    this.waivers = const {},
    this.disabled = const {},
  });

  /// Parses [yamlText]; null or empty text gives the defaults.
  factory Config.parse(String? yamlText) {
    if (yamlText == null || yamlText.trim().isEmpty) {
      return const Config();
    }
    final Object? doc;
    try {
      doc = loadYaml(yamlText);
    } on YamlException catch (e) {
      throw ConfigException(e.message);
    }
    if (doc == null) {
      return const Config();
    }
    if (doc is! YamlMap) {
      throw ConfigException('the top level must be a map');
    }
    final ios = _map(doc, 'ios');
    final android = _map(doc, 'android');
    final payments = _map(doc, 'payments');
    final ugc = _map(doc, 'ugc');
    const d = Config();
    return Config(
      infoPlist: _str(ios, 'info_plist') ?? d.infoPlist,
      privacyManifest: _str(ios, 'privacy_manifest') ?? d.privacyManifest,
      pbxproj: _str(ios, 'pbxproj') ?? d.pbxproj,
      podfile: _str(ios, 'podfile') ?? d.podfile,
      androidManifest: _str(android, 'manifest') ?? d.androidManifest,
      gradle: _str(android, 'gradle'),
      playMinTargetSdk: _int(android, 'min_target_sdk') ?? d.playMinTargetSdk,
      codeDirs: _list(doc, 'code_dirs') ?? d.codeDirs,
      sellsDigitalGoods: _bool(payments, 'sells_digital_goods'),
      externalPaymentPatterns:
          _list(payments, 'external_patterns') ?? d.externalPaymentPatterns,
      reviewFlagPatterns:
          _list(doc, 'review_flag_patterns') ?? d.reviewFlagPatterns,
      ugcDirs: _list(ugc, 'dirs') ?? d.ugcDirs,
      reportPattern: _str(ugc, 'report_pattern') ?? d.reportPattern,
      blockPattern: _str(ugc, 'block_pattern') ?? d.blockPattern,
      deleteAccountPattern:
          _str(doc, 'delete_account_pattern') ?? d.deleteAccountPattern,
      waivers: {
        for (final e in (_map(doc, 'waivers') ?? YamlMap()).entries)
          '${e.key}': '${e.value}',
      },
      disabled: {...?_list(doc, 'disabled')},
    );
  }

  static const List<String> defaultExternalPaymentPatterns = [
    r'presentPaymentSheet|initPaymentSheet', // flutter_stripe
    r'Razorpay\(|razorpay\.open', // razorpay_flutter
    r'PaystackPlugin|FlutterwaveUI|Paymob',
    r'launchUrl\([^)]*(checkout|payment|pay\.)',
  ];

  static const List<String> defaultReviewFlagPatterns = [
    r'isInReview|inReview|underReview|appReviewMode|isAppleReview|reviewMode|isTestFlight',
  ];

  final String infoPlist;
  final String privacyManifest;
  final String pbxproj;
  final String podfile;
  final String androidManifest;

  /// null = auto-detect `android/app/build.gradle(.kts)`.
  final String? gradle;
  final List<String> codeDirs;

  /// Play's target API floor. Bump every August 31 (2025 → 35, 2026 → 36).
  final int playMinTargetSdk;

  /// true: coins, subscriptions, premium content. false: physical goods or
  /// services only. null: unknown, payment rules only warn.
  final bool? sellsDigitalGoods;
  final List<String> externalPaymentPatterns;
  final List<String> reviewFlagPatterns;

  /// Folders that show other users' content (feeds, chat, comments, live).
  final List<String> ugcDirs;
  final String reportPattern;
  final String blockPattern;
  final String deleteAccountPattern;

  /// Rule id → why the risk is accepted.
  final Map<String, String> waivers;

  /// Rule ids that do not apply to this project.
  final Set<String> disabled;

  static YamlMap? _map(YamlMap? m, String key) {
    final v = m?[key];
    if (v == null) {
      return null;
    }
    if (v is! YamlMap) {
      throw ConfigException('`$key` must be a map');
    }
    return v;
  }

  static String? _str(YamlMap? m, String key) {
    final v = m?[key];
    if (v == null) {
      return null;
    }
    if (v is! String) {
      throw ConfigException('`$key` must be a string');
    }
    return v;
  }

  static int? _int(YamlMap? m, String key) {
    final v = m?[key];
    if (v == null) {
      return null;
    }
    if (v is! int) {
      throw ConfigException('`$key` must be an integer');
    }
    return v;
  }

  static bool? _bool(YamlMap? m, String key) {
    final v = m?[key];
    if (v == null) {
      return null;
    }
    if (v is! bool) {
      throw ConfigException('`$key` must be true or false');
    }
    return v;
  }

  static List<String>? _list(YamlMap? m, String key) {
    final v = m?[key];
    if (v == null) {
      return null;
    }
    if (v is! YamlList) {
      throw ConfigException('`$key` must be a list');
    }
    return [for (final x in v) '$x'];
  }
}
