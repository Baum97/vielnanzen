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
Die Bank wird per Name, Ort, BLZ oder **IBAN** gesucht (rund 2.700 Banken); die FinTS-Adresse
trägt Klarblick selbst ein und sie bleibt änderbar. Die Liste stammt aus
[hbci4java](https://github.com/hbci4j/hbci4java) (LGPL-2.1, Daten der Bundesbank/Deutschen
Kreditwirtschaft) und wird mit `python3 tool/build_bank_directory.py` neu erzeugt; einzelne Adressen
können veraltet sein.

> **Wichtig:** Banken akzeptieren nur registrierte FinTS-Programme. Die Registrierung bei der
> Deutschen Kreditwirtschaft ist kostenlos: <https://www.fints.org/de/hersteller/produktregistrierung>
> (Dauer ca. 2 Wochen). Die Produkt-ID wird entweder in der App unter *Einstellungen →
> FinTS-Produkt-ID* eingetragen oder beim Bauen mitgegeben:
> `flutter build apk --dart-define=FINTS_PRODUCT_ID=…` (in der CI als Secret `FINTS_PRODUCT_ID`).

**Datei-Import** (Banken ohne FinTS wie N26, Trade Republic, C24, Revolut – oder wenn noch keine
Produkt-ID vorliegt):
- **Teilen statt suchen (Android):** In der Bank-App den Export wählen → *Teilen* → *Klarblick*.
  Die Datei öffnet sich direkt im Import (auch *Öffnen mit* funktioniert). Die App-Sperre bleibt
  aktiv: geteilte Dateien werden erst nach dem Entsperren übernommen.
- **Konto wird erkannt:** Klarblick liest die IBAN aus der Datei (CAMT, MT940, CSV mit Kontospalte
  oder IBAN im Kopf) und ordnet die Umsätze dem passenden Konto zu – oder legt es mit dem Namen der
  Bank an. Exporte ohne IBAN (z. B. Trade Republic) merkt sich die App pro Dateiformat.
- **Jedes CSV:** Gängige Bank-Exporte (Sparkasse, ING, DKB, comdirect, N26, Volksbank …) werden
  automatisch erkannt. Bei einem unbekannten Format ordnest du die Spalten einmal zu
  (Datum, Betrag oder Soll/Haben, Empfänger, Zweck) – die Zuordnung wird gemerkt.
- Dazu CAMT.052/053 und MT940, mehrere Dateien auf einmal, doppelte Umsätze werden übersprungen.

**Trade Republic:** Es gibt keine offizielle Schnittstelle, deshalb gibt es keinen Direktabruf.
Wenn die TR-App einen Export anbietet, teile ihn per *Teilen → Klarblick*.

**Demo-Daten:** 5 Jahre Beispielumsätze zum Ausprobieren – rein lokal.

## Installieren / Bauen

```
flutter pub get
flutter test
flutter run                       # Gerät oder Emulator
```

- **Android:** Jeder Push baut eine installierbare APK und ein App-Bundle (GitHub → *Actions* →
  *Build (Android & iOS)* → Artefakt `klarblick-android-apk`). Lokal: `flutter build apk --release`.
- **Android-Release:** Einen Tag pushen, z. B. `git tag v1.1.0 && git push origin v1.1.0` – der
  Workflow *Android Release* erstellt ein GitHub-Release mit `klarblick-1.1.0.apk` und `.aab`.
  Für den Play Store einen eigenen Schlüssel als Repository-Secrets hinterlegen:
  `ANDROID_KEYSTORE_BASE64` (`base64 -w0 upload-keystore.jks`), `ANDROID_KEYSTORE_PASSWORD`,
  `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` – ohne Secrets wird mit dem Debug-Schlüssel
  signiert (installierbar, aber nicht Play-Store-tauglich). Lokal dasselbe über
  `android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`).
- **Flutter-Version:** Die Workflows nutzen fest Flutter 3.47.9, passend zu den Gradle-/AGP-/
  Kotlin-Versionen in `android/`. Bei einem Flutter-Update alle Workflows mit anpassen.
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
assets/data/        Kategorien, ~135 Händler, Gläubiger-IDs, Bankverzeichnis, Banken ohne FinTS
tool/               Skript für das Bankverzeichnis
test/               Engine-, Import-, Speicher- und Widget-Tests
```
