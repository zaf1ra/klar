# Slop

Instagram, YouTube, Snapchat und Pinterest ohne Reels, Shorts, Vorschläge und Werbung. Nur für den eigenen Gebrauch.
Für jede volle Stunde ohne Social Media gibt es +10 XP.

Das Xcode-Projekt und der Ordner heißen weiterhin `Klar`; auf dem iPhone heißt die App „Slop“.

## Aufs iPhone bringen (kostenlos)

1. `Klar.xcodeproj` in Xcode öffnen.
2. Projekt „Klar“ → Target „Klar“ → **Signing & Capabilities** → bei **Team** deine Apple-ID wählen („Personal Team“).
3. Falls Xcode meckert, dass die Bundle-ID vergeben ist: `local.klar.app7341` in irgendetwas Eigenes ändern.
4. iPhone per Kabel anschließen, oben als Ziel auswählen, ▶︎ drücken.
5. Auf dem iPhone: **Einstellungen → Datenschutz & Sicherheit → Entwicklermodus** einschalten, und unter **Allgemein → VPN & Geräteverwaltung** deiner Apple-ID vertrauen.

Mit dem kostenlosen Konto läuft die App 7 Tage. Danach einfach wieder ▶︎ in Xcode drücken. Das Kontrollzentrum warnt dich rechtzeitig.

## Filterregeln

Alle Regeln stehen in [`Klar/Rules/rules.json`](Klar/Rules/rules.json):

- `blockedPaths`: Adressen, die sofort zurück zur Startseite führen (Reels, Shorts, Explore)
- `hideSelectors`: Elemente, die per CSS ausgeblendet werden
- `containerRules`: ganze Beiträge ausblenden, wenn sie z. B. „Gesponsert“ enthalten
- `probes`: Prüfpunkte für das Kontrollzentrum und den nächtlichen Check
- `adDomains`: Werbe-Domains, die gar nicht erst geladen werden
- `tabs`: eigene Leiste unten (Knöpfe mit Adresse, Suche, Klick auf einen Knopf der Seite oder Menü)
- `siteBarContains`: erkennt die Original-Leiste der Seite, die statt der eigenen ausgeblendet wird
- `desktopMode`: Seite als Mac-Browser laden (Snapchat)

Wenn du etwas änderst, **erhöhe `version`**. Nur dann holt sich die App die neue Datei.

## Automatische Updates über GitHub

1. Repo **öffentlich** als `klar` auf GitHub anlegen und diesen Ordner hochladen.
2. In `Klar/App/Config.swift` `DEIN-GITHUB-NAME` durch deinen GitHub-Namen ersetzen und die App einmal neu installieren.
3. Ab dann lädt die App bei jedem Start die neueste `rules.json` von GitHub.

Der Workflow `.github/workflows/filter-check.yml` prüft jede Nacht um 4 Uhr (UTC) mit einem iPhone-Browser, ob die Filter noch greifen. Wenn nicht, öffnet er ein Issue mit Bericht und Screenshot. GitHub schickt dir dazu eine Mail.

**Instagram im Nachtcheck (optional):** Instagram zeigt ohne Login fast nichts. Lege dafür einen **Wegwerf-Account** an (nicht deinen echten), melde dich damit in einem Browser an, kopiere den Cookie `sessionid` und speichere ihn im Repo unter **Settings → Secrets and variables → Actions** als `IG_SESSIONID`. Ohne das Secret wird Instagram im Nachtcheck übersprungen.

Das App-Icon entsteht aus [`tools/make-icon.swift`](tools/make-icon.swift):

```bash
swift tools/make-icon.swift Klar/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

Lokal prüfen:

```bash
node tools/check-rules.mjs --validate
```
