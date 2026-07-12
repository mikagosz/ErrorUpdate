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

echo "==> Buduję aplikację demo..."
xcodebuild -project "$ROOT/ErrorUpdate.xcodeproj" -scheme ErrorUpdate \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$ROOT/TestServer/.build" -quiet build

APP="$ROOT/TestServer/.build/Build/Products/Debug/ErrorUpdate.app"

echo "==> Pakuję do ZIP..."
mkdir -p "$WWW/downloads"
rm -f "$WWW/downloads/ErrorUpdate-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$WWW/downloads/ErrorUpdate-$VERSION.zip"

echo "==> Generuję manifest (SHA-256 + podpis Ed25519)..."
cd "$ROOT/ErrorUpdate"
swift run -c release errorupdate-tool release \
    --file "$WWW/downloads/ErrorUpdate-$VERSION.zip" \
    --version "$VERSION" \
    --url "http://127.0.0.1:8000/downloads/ErrorUpdate-$VERSION.zip" \
    --key "$ROOT/keys/errorupdate_private_key.txt" \
    --notes "Testowa aktualizacja $VERSION — wygenerowana przez TestServer/prepare.sh" \
    --out "$WWW/api/error-update/version-check"

echo ""
echo "Gotowe! Uruchom serwer:  $ROOT/TestServer/start.sh"
