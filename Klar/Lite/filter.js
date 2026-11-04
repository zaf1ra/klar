// Wird in jede Seite in Slop eingeschleust. window.__klarRules wird vorher von Swift gesetzt.
(function () {
  if (window.__klarRunning) return;
  window.__klarRunning = true;

  const R = window.__klarRules;

  // Regeln nur auf der Domain des Dienstes anwenden, nicht auf Anmeldeseiten von Google,
  // Facebook usw., die im selben Fenster oder in einem Anmelde-Fenster laufen.
  const ownDomain = new URL(R.home).hostname.split('.').slice(-2).join('.');
  if (location.hostname !== ownDomain && !location.hostname.endsWith('.' + ownDomain)) return;
  const post = (msg) => {
    try { window.webkit.messageHandlers.klar.postMessage(msg); } catch (e) {}
  };

  // Nur Fehler im eigenen Code melden. Fehler aus den Skripten der Seite selbst sind normal
  // und gehören nicht ins Kontrollzentrum.
  const safe = (name, fn) => function () {
    try { return fn.apply(this, arguments); }
    catch (e) { post({ type: 'jsError', message: name + ': ' + String(e && e.message || e) }); }
  };

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

  // Für die eigene Leiste unten: klickt den ersten gefundenen Knopf der Seite an.
  // Links werden direkt geöffnet, alles andere bekommt ein echtes Klick-Ereignis.
  window.__klarClick = function (selectors) {
    for (const sel of selectors) {
      let el = null;
      try { el = document.querySelector(sel); } catch (e) { continue; }
      if (!el) continue;
      const target = el.closest('a[href],button,[role="button"],[role="link"]') || el;
      const href = target.tagName === 'A' ? target.getAttribute('href') : null;
      if (href && !href.startsWith('#') && !href.startsWith('javascript:')) {
        location.assign(target.href);
      } else {
        target.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
      }
      return true;
    }
    return false;
  };

  // KI-Scanner: sammelt alles über den Beitrag in der Bildschirmmitte – Bilder, KI-Kennzeichnungen
  // der Plattform und Hashtags. Die Bilddateien selbst prüft Slop danach in Swift.
  window.__klarScan = function () {
    const visibleArea = (el) => {
      const r = el.getBoundingClientRect();
      const w = Math.max(0, Math.min(r.right, innerWidth) - Math.max(r.left, 0));
      const h = Math.max(0, Math.min(r.bottom, innerHeight) - Math.max(r.top, 0));
      return w * h;
    };
    // Der Beitrag in der Bildschirmmitte: erst bekannte Beitrags-Bausteine der Dienste, sonst das
    // kleinste Element um die Mitte, das etwa einen Bildschirm hoch ist (keine ganze Liste).
    const center = document.elementFromPoint(innerWidth / 2, innerHeight * 0.45);
    const known = 'article, [data-grid-item], [data-test-id="pin"], ytm-video-with-context-renderer, ' +
      'ytm-rich-item-renderer, ytm-compact-video-renderer, ytm-watch, ytm-slim-video-metadata-section-renderer';
    let container = center && center.closest(known);
    if (!container && location.pathname === '/watch') container = document.querySelector('ytm-watch, #player');
    for (let n = center; !container && n && n !== document.body; n = n.parentElement) {
      const r = n.getBoundingClientRect();
      if (r.height >= innerHeight * 0.55 && r.width >= innerWidth * 0.8 && r.height <= innerHeight * 2) container = n;
    }
    container = container || document.body;

    const pickImages = (root) => Array.from(root.querySelectorAll('img'))
      .filter((img) => /^https?:/.test(img.currentSrc || img.src) && img.naturalWidth >= 150 && visibleArea(img) > 2000)
      .sort((a, b) => visibleArea(b) - visibleArea(a))
      .slice(0, 3)
      .map((img) => ({ src: img.currentSrc || img.src, width: img.naturalWidth, height: img.naturalHeight, alt: (img.alt || '').slice(0, 300) }));
    let images = pickImages(container);
    if (!images.length && container !== document.body) images = pickImages(document.body);

    const aria = Array.from(container.querySelectorAll('[aria-label]')).map((e) => e.getAttribute('aria-label')).join('\n');
    let text = (container.innerText || '') + '\n' + aria;
    // Auf YouTube steht die Kennzeichnung in der Videobeschreibung, nicht im Player. Nur auf der
    // Videoseite die ganze Seite lesen – in Ergebnislisten gehörte der Text zu anderen Videos.
    if (/youtube\.com$/.test(location.hostname) && location.pathname === '/watch') {
      text += '\n' + document.body.innerText.slice(0, 30000);
    }

    const labelRe = /(KI-Infos?|Mit KI (?:erstellt|generiert|bearbeitet)|KI-generiert|KI-bearbeitet|KI-modifiziert|AI info|Made with AI|AI[- ]generated|Generated with AI|Created with AI|Imagined with AI|AI modified|AI-modified|Altered or synthetic content|Veränderte oder synthetische Inhalte|Synthetic content|Synthetische Inhalte)/gi;
    const tagRe = /#(ai|aiart|aiartwork|aiartist|aigenerated|aiimage|generativeai|genai|midjourney|stablediffusion|dalle|dalle3|sora|chatgpt|flux|runwayml|kiart|kikunst|kibild|aivideo|aimodel|aigirl|digitalhuman)\b/gi;
    const unique = (arr) => Array.from(new Set(arr.map((x) => x.trim()))).slice(0, 8);

    return {
      url: location.href,
      host: location.hostname,
      images,
      hasVideo: Array.from(container.querySelectorAll('video')).some((v) => visibleArea(v) > 2000),
      labels: unique(text.match(labelRe) || []),
      hashtags: unique((text.match(tagRe) || []).map((t) => t.toLowerCase())),
      caption: (container.innerText || '').trim().slice(0, 500),
    };
  };

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

  // 3b. Die Original-Leiste unten ausblenden, wenn Slop eine eigene zeigt. Gesucht wird das
  //     fest unten angeheftete Element, das einen typischen Link enthält – unabhängig von
  //     Klassennamen. Es bleibt im Code, damit __klarClick seine Links noch findet.
  //     Die Leiste kann aus mehreren verschachtelten, fest angehefteten Ebenen bestehen –
  //     ausgeblendet wird die äußerste, damit kein Rand oder Hintergrund stehen bleibt.
  function hideSiteBar() {
    for (const sel of R.siteBarContains || []) {
      for (const el of safeQuery(sel)) {
        if (el.closest('[data-klar-sitebar]')) continue;
        let bar = null;
        for (let node = el.parentElement; node && node !== document.body; node = node.parentElement) {
          const rect = node.getBoundingClientRect();
          if (rect.top < innerHeight * 0.6) break;
          if (getComputedStyle(node).position === 'fixed' && rect.bottom >= innerHeight - 4) bar = node;
        }
        if (bar) {
          bar.dataset.klarSitebar = '1';
          bar.style.setProperty('display', 'none', 'important');
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
      hideSiteBar();
      skipVideoAds();
    }, 300);
  }

  scanContainers = safe('Container', scanContainers);
  hideSiteBar = safe('Leiste', hideSiteBar);
  skipVideoAds = safe('Videowerbung', skipVideoAds);
  probe = safe('Probe', probe);

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
