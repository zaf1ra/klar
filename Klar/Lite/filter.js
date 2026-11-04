// Wird in jede Lite-Seite eingeschleust. window.__klarRules wird vorher von Swift gesetzt.
(function () {
  if (window.__klarRunning) return;
  window.__klarRunning = true;

  const R = window.__klarRules;
  const post = (msg) => {
    try { window.webkit.messageHandlers.klar.postMessage(msg); } catch (e) {}
  };

  window.addEventListener('error', (e) => {
    post({ type: 'jsError', message: String(e.message || 'Unbekannter Fehler'), source: String(e.filename || '') });
  });

  function safeQuery(selector, root) {
    try { return (root || document).querySelectorAll(selector); }
    catch (e) { post({ type: 'badSelector', selector }); return []; }
  }

  // 1. Ausblenden per CSS: greift sofort, auch bevor die Seite fertig geladen ist.
  //    Kann so früh laufen, dass es noch kein <html> gibt – dann warten, bis es da ist.
  const style = document.createElement('style');
  style.textContent = R.hideSelectors.map((s) => s + '{display:none!important}').join('\n');
  function insertStyle() {
    const root = document.head || document.documentElement;
    if (!root) return false;
    root.appendChild(style);
    return true;
  }
  if (!insertStyle()) {
    const waiter = new MutationObserver(() => { if (insertStyle()) waiter.disconnect(); });
    waiter.observe(document, { childList: true, subtree: true });
  }

  // 2. Gesperrte Pfade und Umleitungen. Auch für Seitenwechsel ohne Neuladen (pushState).
  const blocked = R.blockedPaths.map((p) => new RegExp(p));
  const redirects = R.redirects.map((r) => ({ re: new RegExp(r.path), unless: r.unlessQuery, to: r.to }));

  function checkPath() {
    const path = location.pathname;
    if (blocked.some((re) => re.test(path))) {
      post({ type: 'blocked', path });
      location.replace(R.home);
      return true;
    }
    for (const r of redirects) {
      if (r.re.test(path) && !(r.unless && location.search.includes(r.unless))) {
        location.replace(r.to);
        return true;
      }
    }
    return false;
  }

  for (const fn of ['pushState', 'replaceState']) {
    const original = history[fn];
    history[fn] = function () {
      const result = original.apply(this, arguments);
      setTimeout(checkPath, 0);
      return result;
    };
  }
  window.addEventListener('popstate', checkPath);
  if (checkPath()) return;

  // 3. Ganze Container ausblenden (Werbung, Vorschläge, Reels im Feed).
  const hits = {};
  function scanContainers() {
    for (const rule of R.containerRules) {
      for (const el of safeQuery(rule.container)) {
        if (el.dataset.klarHidden) continue;
        let match = false;
        if (rule.has && el.querySelector(rule.has)) match = true;
        if (!match && rule.text) {
          const text = el.innerText || '';
          match = rule.text.some((t) => text.includes(t));
        }
        if (match) {
          el.style.setProperty('display', 'none', 'important');
          el.dataset.klarHidden = rule.id;
          hits[rule.id] = (hits[rule.id] || 0) + 1;
          post({ type: 'hidden', rule: rule.id });
        }
      }
    }
  }

  // 4. Videowerbung überspringen.
  function skipVideoAds() {
    if (!R.skipVideoAds) return;
    const video = document.querySelector(R.skipVideoAds.adShowing);
    if (video && isFinite(video.duration) && video.duration > 0) {
      video.currentTime = video.duration;
      post({ type: 'hidden', rule: 'video-ad' });
    }
    for (const button of safeQuery(R.skipVideoAds.skipButtons)) button.click();
  }

  // 5. Proben für das Kontrollzentrum: Gibt es die Elemente noch, die wir ausblenden?
  //    "visible" zählt, was trotz Filter noch auf dem Bildschirm ist – sollte immer 0 sein.
  function probe() {
    const results = {};
    const visible = {};
    for (const p of R.probes) {
      if (!new RegExp(p.path).test(location.pathname)) continue;
      const found = Array.from(safeQuery(p.selector));
      results[p.id] = found.length;
      visible[p.id] = found.filter((el) => el.getClientRects().length > 0).length;
    }
    post({ type: 'probe', path: location.pathname, results, visible });
  }

  let scheduled = false;
  function scan() {
    if (scheduled) return;
    scheduled = true;
    setTimeout(() => {
      scheduled = false;
      if (checkPath()) return;
      scanContainers();
      skipVideoAds();
    }, 300);
  }

  function start() {
    new MutationObserver(scan).observe(document.documentElement, { childList: true, subtree: true });
    scan();
    setTimeout(probe, 4000);
    setInterval(probe, 15000);
    setInterval(skipVideoAds, 1000);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
