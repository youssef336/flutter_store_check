/// Runs the rule set over a project.
library;

import 'model.dart';
import 'rules/android.dart';
import 'rules/ios.dart';
import 'rules/manual.dart';
import 'rules/policy.dart';

/// Every source rule, in report order.
List<Rule> get allRules => [
  ...iosRules,
  ...androidRules,
  ...policyRules,
  ...manualRules,
];

/// Runs [rules] (minus the ones the config disables), applies waivers and
/// sorts the results worst first.
List<Result> runRules(Context ctx, List<Rule> rules) => [
  for (final rule in rules)
    if (!ctx.config.disabled.contains(rule.id))
      Result(rule, rule.check(ctx), waiver: ctx.config.waivers[rule.id]),
]..sort((a, b) => a.status.index.compareTo(b.status.index));
