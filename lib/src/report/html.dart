/// The standalone HTML report: one file, no server, opens in any browser.
/// Manual checks are remembered in the browser's localStorage per version.
library;

import 'dart:convert';

import 'report.dart';

/// Renders [report] as a self-contained HTML page.
String renderHtml(Report report) {
  // `</` inside the inline JSON would close the <script> element early.
  final json = jsonEncode(report.toJson()).replaceAll('</', r'<\/');
  return _template.replaceFirst('__REPORT_JSON__', json);
}

const String _template = r'''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Store Check</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>
  /* Layout: a submission sheet. Verdict band on top, then one ruled list per store,
     worst first, with manual checks tickable and shared per release. */
  :root {
    --bg: #f6f7f9;
    --surface: #ffffff;
    --fg: #15181d;
    --muted: #5d6573;
    --line: #dfe3ea;
    --accent: #0e7fa6;
    --fail: #c62f2f;
    --fail-bg: #fdeceb;
    --warn: #a86400;
    --warn-bg: #fdf3e2;
    --manual: #2f5fb3;
    --manual-bg: #e9effb;
    --pass: #1e7c48;
    --pass-bg: #e6f4ec;
    --waived: #6b7280;
    --waived-bg: #eef0f3;
    --sans: "IBM Plex Sans", system-ui, -apple-system, "Segoe UI", sans-serif;
    --mono: "IBM Plex Mono", ui-monospace, "SF Mono", Menlo, monospace;
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      --bg: #101317; --surface: #171b21; --fg: #e7eaef; --muted: #9aa3b2; --line: #2a3039;
      --accent: #4cc2e6; --fail: #ff7b72; --fail-bg: #3a1d1d; --warn: #f0b350; --warn-bg: #352812;
      --manual: #8fb2ff; --manual-bg: #1c2740; --pass: #5fd394; --pass-bg: #15301f;
      --waived: #9aa3b2; --waived-bg: #23282f; color-scheme: dark;
    }
  }
  :root[data-theme="dark"] {
    --bg: #101317; --surface: #171b21; --fg: #e7eaef; --muted: #9aa3b2; --line: #2a3039;
    --accent: #4cc2e6; --fail: #ff7b72; --fail-bg: #3a1d1d; --warn: #f0b350; --warn-bg: #352812;
    --manual: #8fb2ff; --manual-bg: #1c2740; --pass: #5fd394; --pass-bg: #15301f;
    --waived: #9aa3b2; --waived-bg: #23282f; color-scheme: dark;
  }
  body { margin: 0; background: var(--bg); color: var(--fg); font: 15px/1.5 var(--sans); }
  .wrap { max-width: 960px; margin: 0 auto; padding-inline: 16px; padding-block: 28px 64px; display: grid; gap: 24px; }
  header { display: grid; gap: 14px; }
  .eyebrow { font: 500 12px/1 var(--mono); letter-spacing: .08em; text-transform: uppercase; color: var(--muted); }
  h1 { margin: 0; font-size: 28px; font-weight: 600; text-wrap: balance; display: flex; flex-wrap: wrap; align-items: center; gap: 12px; }
  .verdict { font: 600 13px/1 var(--mono); letter-spacing: .06em; padding: 7px 10px; border-radius: 6px; }
  .meta { color: var(--muted); font: 13px/1.6 var(--mono); overflow-wrap: anywhere; }
  .counts { display: flex; flex-wrap: wrap; gap: 8px; }
  .count { font: 500 13px/1 var(--mono); padding: 6px 9px; border-radius: 6px; font-variant-numeric: tabular-nums; }
  .s-fail { color: var(--fail); background: var(--fail-bg); }
  .s-warn { color: var(--warn); background: var(--warn-bg); }
  .s-manual { color: var(--manual); background: var(--manual-bg); }
  .s-pass { color: var(--pass); background: var(--pass-bg); }
  .s-waived { color: var(--waived); background: var(--waived-bg); }
  .tabs { display: flex; gap: 4px; border-bottom: 1px solid var(--line); overflow-x: auto; }
  .tab { appearance: none; border: 0; background: none; color: var(--muted); font: 500 15px var(--sans); padding: 10px 14px; border-bottom: 2px solid transparent; cursor: pointer; white-space: nowrap; }
  .tab[aria-selected="true"] { color: var(--fg); border-bottom-color: var(--accent); }
  .tab:focus-visible, summary:focus-visible, input:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
  .tab .n { font: 12px var(--mono); color: var(--fail); margin-inline-start: 6px; }
  ol.rules { list-style: none; margin: 0; padding: 0; background: var(--surface); border: 1px solid var(--line); border-radius: 10px; }
  li.rule { display: grid; grid-template-columns: 76px 1fr; gap: 4px 16px; padding: 16px; border-top: 1px solid var(--line); }
  li.rule:first-child { border-top: 0; }
  .chip { font: 600 11px/1 var(--mono); letter-spacing: .06em; padding: 6px 0; border-radius: 5px; text-align: center; align-self: start; text-transform: uppercase; }
  .body { min-width: 0; display: grid; gap: 6px; }
  .title { font-weight: 600; display: flex; flex-wrap: wrap; gap: 4px 10px; align-items: baseline; }
  .id { font: 500 12px var(--mono); color: var(--muted); }
  .guide { font: 12px var(--mono); color: var(--muted); }
  .msg { margin: 0; color: var(--fg); max-width: 72ch; }
  .fix { margin: 0; color: var(--muted); max-width: 72ch; font-size: 14px; }
  .fix b { color: var(--fg); font-weight: 500; }
  details { font-size: 13px; }
  summary { cursor: pointer; color: var(--accent); font-weight: 500; }
  .ev { margin: 8px 0 0; padding: 10px 12px; background: var(--bg); border-radius: 6px; overflow-x: auto; font: 12.5px/1.7 var(--mono); white-space: pre; }
  .tick { display: flex; align-items: center; gap: 8px; font-size: 14px; }
  .tick input { width: 18px; height: 18px; accent-color: var(--pass); }
  .tick .who { color: var(--muted); font-size: 12.5px; }
  .note { color: var(--muted); font-size: 13px; }
</style>
</head>
<body>

<div class="wrap">
  <header>
    <div class="eyebrow">Pre-submission review · Google Play + App Store</div>
    <h1><span id="name">Store Check</span><span id="verdict" class="verdict"></span></h1>
    <div id="meta" class="meta"></div>
    <div id="counts" class="counts"></div>
  </header>
  <nav class="tabs" role="tablist" id="tabs"></nav>
  <ol class="rules" id="rules"></ol>
  <p class="note" id="note">Manual checks are remembered in this browser, per app version.</p>
</div>
<script>
const REPORT = __REPORT_JSON__;
const STORES = [
  { key: 'appStore', label: 'App Store' },
  { key: 'googlePlay', label: 'Google Play' },
];
const ORDER = ['fail', 'warn', 'manual', 'waived', 'pass'];
const release = REPORT.version.replace(/[^A-Za-z0-9_-]/g, '-');
let tab = STORES[0].key;
try { tab = localStorage.getItem('tab') || tab; } catch (_) {}
let ticks = {};
const KEY = `store_check:${REPORT.version}`;
try { ticks = JSON.parse(localStorage.getItem(KEY) || '{}'); } catch (_) {}
const $ = (id) => document.getElementById(id);
const el = (tag, cls, text) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text != null) n.textContent = text;
  return n;
};

function statusOf(r) {
  return r.status === 'manual' && ticks[r.id]?.done ? 'pass' : r.status;
}

function rulesFor(store) {
  return REPORT.results
    .filter((r) => r.store === store || r.store === 'both')
    .sort((a, b) => ORDER.indexOf(statusOf(a)) - ORDER.indexOf(statusOf(b)));
}

function renderHeader() {
  const all = REPORT.results.map(statusOf);
  const n = (s) => all.filter((x) => x === s).length;
  const verdict = n('fail') ? 'REJECT' : n('warn') + n('manual') ? 'REVIEW' : 'READY';
  const v = $('verdict');
  v.textContent = verdict;
  v.className = 'verdict ' + (verdict === 'REJECT' ? 's-fail' : verdict === 'REVIEW' ? 's-warn' : 's-pass');
  const when = new Date(REPORT.generatedAt).toLocaleString();
  $('meta').textContent =
    `v${REPORT.version} · ${REPORT.branch || 'detached'} @ ${REPORT.commit} · ${when}` +
    (REPORT.artifacts.length ? ` · checked ${REPORT.artifacts.join(', ')}` : ' · source only, no AAB/IPA');
  const counts = $('counts');
  counts.replaceChildren(...ORDER.filter(n).map((s) => el('span', 'count s-' + s, `${n(s)} ${s}`)));
}

function renderTabs() {
  $('tabs').replaceChildren(...STORES.map((s) => {
    const b = el('button', 'tab', s.label);
    b.id = 'tab-' + s.key;
    b.setAttribute('role', 'tab');
    b.setAttribute('aria-selected', String(s.key === tab));
    const fails = rulesFor(s.key).filter((r) => statusOf(r) === 'fail').length;
    if (fails) b.append(el('span', 'n', `${fails} fail`));
    b.onclick = () => {
      tab = s.key;
      try { localStorage.setItem('tab', tab); } catch (_) {}
      render();
    };
    return b;
  }));
}

function tickControl(r) {
  const row = el('label', 'tick');
  const box = document.createElement('input');
  box.type = 'checkbox';
  box.id = 'tick-' + r.id;
  box.checked = !!ticks[r.id]?.done;
  box.onchange = () => {
    ticks[r.id] = box.checked ? { done: true, at: Date.now() } : { done: false };
    try { localStorage.setItem(KEY, JSON.stringify(ticks)); } catch (_) {}
    render();
  };
  row.append(box, el('span', null, box.checked ? 'Done for this release' : 'Mark done for this release'));
  if (ticks[r.id]?.done && ticks[r.id].at) {
    row.append(el('span', 'who', '· ' + new Date(ticks[r.id].at).toLocaleDateString()));
  }
  return row;
}

function renderRules() {
  $('rules').replaceChildren(...rulesFor(tab).map((r) => {
    const s = statusOf(r);
    const li = el('li', 'rule');
    li.append(el('span', 'chip s-' + s, s === 'pass' && r.status === 'manual' ? 'done' : s));
    const body = el('div', 'body');
    const title = el('div', 'title');
    title.append(el('span', 'id', r.id), el('span', null, r.title), el('span', 'guide', r.guideline));
    body.append(title, el('p', 'msg', r.message));
    if (r.waiver) body.append(el('p', 'fix', 'Waived: ' + r.waiver));
    if (r.evidence.length) {
      const d = el('details');
      d.append(el('summary', null, `Evidence (${r.evidence.length})`), el('pre', 'ev', r.evidence.join('\n')));
      if (s === 'fail' && r.evidence.length <= 6) d.open = true;
      body.append(d);
    }
    if (r.status !== 'pass') {
      const fix = el('p', 'fix');
      fix.append(el('b', null, 'Fix: '), document.createTextNode(r.fix));
      body.append(fix);
    }
    if (r.status === 'manual') body.append(tickControl(r));
    li.append(body);
    return li;
  }));
}

function render() {
  renderHeader();
  renderTabs();
  renderRules();
}

render();
</script>
</body>
</html>
''';
