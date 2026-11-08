# Klarblick – Finanzen im Blick (Android & iOS)

Kostenlose, rein lokale Finanz-App: Konten verbinden, Einnahmen und Ausgaben automatisch
auswerten, Abos erkennen und Sparpotenzial finden. Alle Daten bleiben verschlüsselt auf dem
Gerät – es gibt keinen Klarblick-Server. Lizenz: GPL-3.0 (siehe `LICENSE`, `PRIVACY.md`).

## Was die App kann

| Bereich | Inhalt |
|---|---|
| **Übersicht** | Gesamtsaldo mit Verlauf, Einnahmen / Ausgaben / Übrig (inkl. Sparquote und Vergleich zur Vorperiode), Einnahmen-&-Ausgaben-Diagramm, Top-Kategorien, Top-Firmen, Sparpotenzial, demnächst fällige Abbuchungen, Konten |
| **Zeiträume** | **1W · 1M · 3M · 6M · YTD · 1J · 5J · Max** – gilt app-weit für Diagramme, Kategorien und Firmen |
| **Ausgaben** | *Wofür* (Kategorien mit Donut, Unterkategorien, Veränderung), *Wo* (alle Firmen sortiert nach Betrag, Häufigkeit oder Anstieg), *Wann* (Verlauf, Wochentage, Monatsanfang/-mitte/-ende, größte Einzelausgaben) |
| **Umsätze** | Suche (Firma, Zweck, Betrag), Filter nach Typ, Zeitraum, Kategorie; Kategorie ändern inkl. Regel „für alle Umsätze dieser Firma“ |
| **Abos & Verträge** | Automatische Erkennung (SEPA-Mandat, Gläubiger-ID, Regelmäßigkeit), Fixkosten pro Monat/Jahr und Anteil am Einkommen, Preiserhöhungen, Kalender, Kündigungsschreiben zum Teilen |
| **Sparen** | Sparpotenzial pro Jahr aus den eigenen Daten: Doppel-Abos, Preiserhöhungen, Bankgebühren, Doppelabbuchungen, Lieferdienste/Restaurants, „Kleinvieh“, Kfz-/Versicherungs- und Strom-Check, zinsloses Guthaben, auffällig gestiegene Kategorien; größte Hebel; Monatsbudgets |
| **Sicherheit** | AES-256-GCM-Verschlüsselung (Schlüssel im iOS-Keychain / Android-Keystore), App-Sperre per Face ID / Fingerabdruck, Diskret-Modus, Netzwerk-Protokoll |

## Bankanbindung

**FinTS (direkt zur Bank, ohne Server)** – unterstützt PIN/TAN mit pushTAN/App-Freigabe,
photoTAN und TAN-Eingabe; lädt bis zu 5 Jahre Umsätze (so weit die Bank liefert).
Voreingetragen sind u. a. ING, DKB, comdirect, Commerzbank, Deutsche Bank, Postbank,
Consorsbank und Volks-/Raiffeisenbanken; für Sparkassen und andere Banken BLZ und
FinTS-Adresse eingeben.

> **Wichtig:** Banken akzeptieren nur registrierte FinTS-Programme. Die Registrierung bei der
> Deutschen Kreditwirtschaft ist kostenlos: <https://www.fints.org/de/hersteller/produktregistrierung>
> (Dauer ca. 2 Wochen). Die Produkt-ID wird entweder in der App unter *Einstellungen →
> FinTS-Produkt-ID* eingetragen oder beim Bauen mitgegeben:
> `flutter build apk --dart-define=FINTS_PRODUCT_ID=…` (in der CI als Secret `FINTS_PRODUCT_ID`).

**Datei-Import** (für Banken ohne FinTS wie N26, Trade Republic, C24, Revolut oder ohne
Produkt-ID): CSV der gängigen Banken (Sparkasse, ING, DKB, comdirect, N26, Volksbank …),
CAMT.052/053 und MT940. Doppelte Umsätze werden erkannt.

**Demo-Daten:** 5 Jahre Beispielumsätze zum Ausprobieren – rein lokal.

## Installieren / Bauen

```
flutter pub get
flutter test
flutter run                       # Gerät oder Emulator
```

- **Android:** Jeder Push baut eine installierbare APK (GitHub → *Actions* → *Build (Android & iOS)*
  → Artefakt `klarblick-android-apk`). Lokal: `flutter build apk --release`. Für eine
  Store-Version `android/key.properties` mit `storeFile`, `storePassword`, `keyAlias`,
  `keyPassword` anlegen – ohne diese Datei wird mit dem Debug-Schlüssel signiert.
- **iOS:** Die CI prüft `flutter build ios --no-codesign`. Zum Installieren in Xcode
  `ios/Runner.xcworkspace` öffnen, Team wählen und auf ein Gerät bauen (Apple-Developer-Account nötig).
- **Web:** `flutter build web` (Bankverbindung im Browser nicht möglich – dort nur Datei-Import).
  Pushes auf `main` werden nach GitHub Pages veröffentlicht: <https://baum97.github.io/vielnanzen/>
  (einmalig: *Settings → Pages → Source: gh-pages / root*).

## Aufbau

```
lib/
  core/analytics/   Zeiträume (time_range.dart) und Auswertungen (analytics.dart)
  core/engine/      Kategorisierung, Vertrags-/Abo-Erkennung, Spar-Hinweise
  core/import/      CSV-/CAMT-/MT940-Import
  connectors/       FinTS-Anbindung (Paket `fints`)
  data/             Modelle, verschlüsselter Speicher, Schlüsselablage
  services/         Bank-Abruf
  state/            Riverpod-Zustand, Navigation
  ui/               Tabs, Detailseiten, Diagramme
assets/data/        Kategorien, ~135 Händler, Gläubiger-IDs, Banken
test/               Engine-, Import-, Speicher- und Widget-Tests
```
