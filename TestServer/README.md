# Lokalny serwer testowy aktualizacji

Pozwala przetestować pełny cykl aktualizacji (sprawdzenie → pobranie →
weryfikacja SHA-256 + Ed25519 → codesign → instalacja) bez żadnego hostingu
i bez płatnego konta Apple Developer.

## Użycie

```bash
# 1. Przygotuj pliki (build aplikacji demo + ZIP "wersji 9.9.9" + podpisany manifest)
./TestServer/prepare.sh

# 2. Uruchom serwer (zostaw działający w terminalu)
./TestServer/start.sh

# 3. Uruchom aplikację demo z Xcode i kliknij "Sprawdź dostępność"
#    — aplikacja zobaczy "wersję 9.9.9", pobierze ją i będzie mogła zainstalować.
```

Aplikacja demo jest już skonfigurowana na `http://127.0.0.1:8000`
(patrz `MyApp/ContentView.swift`) z kluczem publicznym z `keys/`.

## Struktura serwera

```
www/
├── api/error-update/version-check   <- manifest JSON (to zwraca "serwer")
└── downloads/ErrorUpdate-9.9.9.zip  <- plik aktualizacji
```

To dokładnie ta sama struktura, którą wystawisz na prawdziwym hostingu —
wystarczy dowolny serwer statycznych plików (GitHub Pages, dowolny hosting www).
Przy publikacji nowej wersji swojego programu użyj:

```bash
cd ErrorUpdate
swift run errorupdate-tool release \
    --file MojaApka-1.2.0.zip --version 1.2.0 \
    --url https://twoj-serwer.com/downloads/MojaApka-1.2.0.zip \
    --key ../keys/errorupdate_private_key.txt \
    --notes "Co nowego..." \
    --out version-check
```

i wgraj `version-check` + ZIP na serwer.

## Uwagi

- Klucz prywatny (`keys/errorupdate_private_key.txt`) trzymaj lokalnie —
  jest w `.gitignore`, nie commituj go i nie wgrywaj na serwer.
- Adres `http://127.0.0.1` działa bez HTTPS, bo macOS zwalnia połączenia
  loopback z wymogów App Transport Security. Prawdziwy serwer musi mieć HTTPS.
- Folder `www/` i `.build/` są generowane — też są w `.gitignore`.
