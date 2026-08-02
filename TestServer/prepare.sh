#!/bin/bash
#
# Przygotowuje lokalny serwer testowy aktualizacji:
#  1. buduje aplikację demo,
#  2. pakuje ją do ZIP jako "wersję 9.9.9",
#  3. generuje podpisany manifest version-check.
#
# Potem uruchom serwer:  ./start.sh
# i w aplikacji kliknij "Sprawdź dostępność".
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WWW="$ROOT/TestServer/www"
VERSION="9.9.9"

if [ ! -f "$ROOT/keys/errorupdate_private_key.txt" ]; then
    echo "==> Brak kluczy — generuję parę Ed25519 w keys/ ..."
    (cd "$ROOT" && swift run -c release errorupdate-tool keygen --out keys)
fi

echo "==> Buduję aplikację demo..."
# Bez ERRORUPDATE_SIGNING_IDENTITY demo podpisuje się ad-hoc, co wystarcza do
# uruchomienia, ale instalator pominie wtedy kontrolę pochodzenia aktualizacji:
# designated requirement podpisu ad-hoc pinuje cdhash jednego builda, więc żadna
# nowa wersja nie może go spełnić. Aby przejść pełną ścieżkę weryfikacji, podaj
# odcisk własnego certyfikatu:
#   ERRORUPDATE_SIGNING_IDENTITY=$(security find-identity -p codesigning \
#       | grep "Local Developer" | awk '{print $2}' | head -1) ./TestServer/prepare.sh
SIGN_IDENTITY="${ERRORUPDATE_SIGNING_IDENTITY:--}"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "    (podpis ad-hoc — kontrola pochodzenia aktualizacji będzie pominięta)"
else
    echo "    (podpis certyfikatem $SIGN_IDENTITY)"
fi

# Schemat MUSI być "DemoApp", nie "ErrorUpdate": ta druga nazwa należy również do
# biblioteki z pakietu SPM, więc xcodebuild potrafi zbudować pakiet zamiast aplikacji,
# zameldować sukces i nie wyprodukować żadnego .app.
xcodebuild -project "$ROOT/DemoApp/ErrorUpdate.xcodeproj" -scheme DemoApp \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$ROOT/TestServer/.build" -quiet \
    EU_CODE_SIGN_IDENTITY="$SIGN_IDENTITY" build

APP="$ROOT/TestServer/.build/Build/Products/Debug/ErrorUpdate.app"

# xcodebuild potrafi zwrócić 0 bez zbudowania czegokolwiek — sprawdź produkt,
# zamiast pakować to, co zostało po poprzednim przebiegu.
if [ ! -d "$APP" ]; then
    echo "BŁĄD: build nie wyprodukował $APP" >&2
    exit 1
fi

ACTUAL_REQ="$(codesign -d -r- "$APP" 2>&1 | grep 'designated =>' || true)"
case "$ACTUAL_REQ" in
    *cdhash*)
        if [ "$SIGN_IDENTITY" != "-" ]; then
            echo "BŁĄD: żądano podpisu certyfikatem, a pakiet jest ad-hoc." >&2
            echo "      Xcode uznał build za aktualny i nie przepodpisał — usuń TestServer/.build." >&2
            exit 1
        fi
        ;;
esac

echo "==> Pakuję do ZIP..."
mkdir -p "$WWW/downloads"
rm -f "$WWW/downloads/ErrorUpdate-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$WWW/downloads/ErrorUpdate-$VERSION.zip"

echo "==> Generuję manifest (SHA-256 + podpis Ed25519)..."
cd "$ROOT"
swift run -c release errorupdate-tool release \
    --file "$WWW/downloads/ErrorUpdate-$VERSION.zip" \
    --version "$VERSION" \
    --url "http://127.0.0.1:8000/downloads/ErrorUpdate-$VERSION.zip" \
    --key "$ROOT/keys/errorupdate_private_key.txt" \
    --notes "Testowa aktualizacja $VERSION — wygenerowana przez TestServer/prepare.sh" \
    --out "$WWW/api/error-update/version-check"

echo ""
echo "Gotowe! Uruchom serwer:  $ROOT/TestServer/start.sh"
