// Prüft Klar/Rules/rules.json: Aufbau, gültige Regex und Selektoren, und ob die Proben auf den echten Seiten noch etwas finden.
// Aufruf: node tools/check-rules.mjs            (voller Check mit Playwright/WebKit)
//         node tools/check-rules.mjs --validate (nur Aufbau prüfen, kein Browser)
import { readFile, writeFile } from 'node:fs/promises';

const RULES_PATH = new URL('../Klar/Rules/rules.json', import.meta.url);
const validateOnly = process.argv.includes('--validate');
const problems = [];
const report = [];

const rules = JSON.parse(await readFile(RULES_PATH, 'utf8'));
const filterJS = await readFile(new URL('../Klar/Lite/filter.js', import.meta.url), 'utf8');

// 1. Aufbau
const required = ['id', 'name', 'icon', 'home', 'allowedHosts', 'blockedPaths', 'redirects', 'hideSelectors', 'containerRules', 'probes', 'loginCookie'];
if (!Number.isInteger(rules.version)) problems.push('version fehlt oder ist keine Zahl');
if (!Array.isArray(rules.adDomains)) problems.push('adDomains fehlt');
for (const site of rules.sites ?? []) {
  for (const key of required) if (!(key in site)) problems.push(`${site.id}: Feld "${key}" fehlt`);
  for (const p of [...(site.blockedPaths ?? []), ...(site.redirects ?? []).map((r) => r.path), ...(site.probes ?? []).map((p) => p.path)]) {
    try { new RegExp(p); } catch { problems.push(`${site.id}: ungültige Regex ${p}`); }
  }
}

if (problems.length || validateOnly) await finish();

// 2. Live-Check im iPhone-Browser (WebKit, wie auf dem iPhone)
const { webkit, devices } = await import('playwright');
const browser = await webkit.launch();

for (const site of rules.sites) {
  const check = site.ciCheck;
  if (!check) continue;
  const context = await browser.newContext({ ...devices['iPhone 14'], locale: 'de-DE' });

  if (check.cookieEnv) {
    const value = process.env[check.cookieEnv];
    if (!value) {
      report.push(`- ${site.name}: übersprungen (Secret ${check.cookieEnv} fehlt)`);
      await context.close();
      continue;
    }
    await context.addCookies([{ name: check.cookieName, value, domain: check.cookieDomain, path: '/', secure: true, httpOnly: true }]);
  }

  const page = await context.newPage();
  // Derselbe Filter wie in der App, damit wir prüfen können, ob noch etwas durchrutscht.
  await page.addInitScript(`window.__klarRules = ${JSON.stringify(site)};\n${filterJS}`);
  try {
    await page.goto(check.url, { waitUntil: 'domcontentloaded', timeout: 45000 });
    await page.waitForTimeout(8000);

    // Selektoren gegen die echte Seite testen (wirft bei ungültiger Syntax)
    const all = [...site.hideSelectors, ...site.containerRules.map((r) => r.container), ...site.containerRules.filter((r) => r.has).map((r) => r.has)];
    const invalid = await page.evaluate((list) => list.filter((s) => { try { document.querySelector(s); return false; } catch { return true; } }), all);
    for (const s of invalid) problems.push(`${site.name}: Selektor ungültig: ${s}`);

    for (const id of check.probes) {
      const probe = site.probes.find((p) => p.id === id);
      const { count, visible } = await page.evaluate((sel) => {
        const found = Array.from(document.querySelectorAll(sel));
        return { count: found.length, visible: found.filter((el) => el.getClientRects().length > 0).length };
      }, probe.selector);
      report.push(`- ${site.name} / ${probe.label}: ${count} gefunden, ${visible} sichtbar`);
      if (count === 0) problems.push(`${site.name}: Probe "${probe.label}" findet nichts mehr (${probe.selector}). Die Seite hat sich wahrscheinlich geändert.`);
      if (visible > 0 && probe.expectHidden) problems.push(`${site.name}: "${probe.label}" ist trotz Filter sichtbar (${visible}×). Eine Ausblende-Regel fehlt.`);
    }
    await page.screenshot({ path: `check-${site.id}.png` });
  } catch (e) {
    problems.push(`${site.name}: Seite konnte nicht geladen werden (${e.message.split('\n')[0]})`);
  }
  await context.close();
}
await browser.close();
await finish();

async function finish() {
  const text = [
    `Regeln v${rules.version} (${rules.updated})`,
    '',
    ...report,
    '',
    problems.length ? '### Probleme' : 'Keine Probleme gefunden.',
    ...problems.map((p) => `- ${p}`),
  ].join('\n');
  console.log(text);
  await writeFile('check-report.md', text);
  process.exit(problems.length ? 1 : 0);
}
