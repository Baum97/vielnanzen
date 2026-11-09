#!/usr/bin/env python3
"""Erzeugt assets/data/bank_directory.json aus der öffentlichen Institutsliste.

Quelle: hbci4java (LGPL-2.1), Datei blz.properties – die Liste stammt aus den
Bankleitzahlen der Bundesbank und den FinTS-Angaben der Deutschen Kreditwirtschaft.
Zeilenformat:  BLZ=Name|Ort|BIC|Prüfziffer|Host|FinTS-URL|Version|Version|

Aufruf:  python3 tool/build_bank_directory.py [pfad/zur/blz.properties]
Ohne Argument wird die Liste von GitHub geladen.
"""
import json
import re
import sys
import urllib.request

SOURCE = "https://raw.githubusercontent.com/hbci4j/hbci4java/master/src/main/resources/blz.properties"
OUT = "assets/data/bank_directory.json"
ATRUVIA = "https://fints2.atruvia.de/cgi-bin/hbciservlet"


def load(path):
    if path:
        return open(path, encoding="utf-8").read()
    with urllib.request.urlopen(SOURCE, timeout=60) as r:
        return r.read().decode("utf-8")


def normalize_url(url):
    url = url.strip()
    # Volks-/Raiffeisenbanken: Fiducia- und GAD-Server laufen seit der Fusion zur Atruvia
    # über eine gemeinsame Adresse.
    host = re.sub(r"^https?://", "", url).split("/")[0].lower()
    if host.endswith("fiducia.de") or host.endswith("gad.de"):
        return ATRUVIA
    return url


def main():
    text = load(sys.argv[1] if len(sys.argv) > 1 else None)
    urls, url_index, banks = [], {}, []
    seen = set()
    for line in text.splitlines():
        if "=" not in line or line.startswith("#"):
            continue
        blz, rest = line.split("=", 1)
        parts = rest.split("|")
        if not re.fullmatch(r"\d{8}", blz) or len(parts) < 6:
            continue
        name, city, bic, _, _, url = [p.strip() for p in parts[:6]]
        if not url.startswith("https://"):
            continue  # kein FinTS-Zugang für Privatkunden bekannt
        url = normalize_url(url)
        if url not in url_index:
            url_index[url] = len(urls)
            urls.append(url)
        if blz in seen:
            continue
        seen.add(blz)
        banks.append([blz, name, city, bic, url_index[url]])
    banks.sort(key=lambda b: (b[1].lower(), b[0]))
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump({"source": "hbci4java blz.properties (LGPL-2.1)", "urls": urls, "banks": banks},
                  f, ensure_ascii=False, separators=(",", ":"))
    print(f"{len(banks)} Banken, {len(urls)} verschiedene Adressen -> {OUT}")


if __name__ == "__main__":
    main()
