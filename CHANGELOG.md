## 0.1.0

- First release: 18 source rules (iOS, Android, policy), 6 manual checks,
  4 binary checks for `--aab` / `--ipa` (16 KB alignment, merged manifest,
  bundled privacy manifests, distribution entitlements).
- `store_check fix` for the safe mechanical fixes (unused restricted
  permissions, READ_EXTERNAL_STORAGE cap, foreground-service permissions,
  privacy manifest template).
- Text, JSON, Markdown, GitHub-annotation and standalone HTML reports.
- Composite GitHub Action.
