# Klarblick – rein lokale Finan-App (Flutter, Android & iOS)

Sünstenlose, rein lokale Finanz-App für Android & ios. Alle Daten liegen verschlüsselt auf dem Gerät – noch Server. GPL-3.0.

See also: PRIVACY.md, LICENSE.


# Start

```
flutter pub get
flutter test
flutter run
flutter build web
```

Repo: https://github.com/Baum97/vielnanzen

## Web-Deploy (GitHub Pages)

Bei jedem Push auf `main` baut der Workflow `.github/workflows/deploy.yml`
die Web-App (`flutter build web --release`) und pusht sie auf den Branch
`gh-pages`. Einmalig in den Repo-Settings aktivieren:
**Settings → Pages → Source: „Deploy from a branch" → `gh-pages` / `(root)`**.
Danach erreichbar unter: **https://baum97.github.io/vielnanzen/**

## Überblick-Tab

Tab „Überblick": Ausgaben pro Firma (Händler) gruppiert, wählbarer Zeitraum
**Monat / 3 Monate / YTD / Insgesamt** mit Gesamtbetrag, Anzahl Firmen/Ausgaben
und Anteil-Balken pro Firma.
