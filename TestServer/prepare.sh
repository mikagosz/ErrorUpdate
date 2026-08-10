#!/bin/bash
#
# Przygotowuje lokalny serwer testowy aktualizacji:
#  1. builds the demo app,
#  2. packages it into a ZIP as "version 9.9.9",
#  3. generuje podpisany manifest version-check.
#
# Potem uruchom serwer:  ./start.sh
# then click "Check for updates" in the app.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WWW="$ROOT/TestServer/www"
VERSION="9.9.9"

if [ ! -f "$ROOT/keys/errorupdate_private_key.txt" ]; then
    echo "==> No keys found — generating an Ed25519 pair in keys/ ..."
    (cd "$ROOT" && swift run -c release errorupdate-tool keygen --out keys)
fi

echo "==> Building the demo app..."
# Without ERRORUPDATE_SIGNING_IDENTITY the demo is ad-hoc signed, which is enough
# to run it, but the installer then skips the update's origin check: the designated
# requirement of an ad-hoc signature pins one build's cdhash, so no later version
# can ever satisfy it. To exercise the full verification path, pass the fingerprint
# of your own certificate:
#   ERRORUPDATE_SIGNING_IDENTITY=$(security find-identity -p codesigning \
#       | grep "Local Developer" | awk '{print $2}' | head -1) ./TestServer/prepare.sh
SIGN_IDENTITY="${ERRORUPDATE_SIGNING_IDENTITY:--}"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "    (ad-hoc signature — the update origin check will be skipped)"
else
    echo "    (podpis certyfikatem $SIGN_IDENTITY)"
fi

# The scheme MUST be "DemoApp", not "ErrorUpdate": the latter name also belongs to
# the SPM package library, so xcodebuild can build the package instead of the app,
# report success and produce no .app at all.
xcodebuild -project "$ROOT/DemoApp/ErrorUpdate.xcodeproj" -scheme DemoApp \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$ROOT/TestServer/.build" -quiet \
    EU_CODE_SIGN_IDENTITY="$SIGN_IDENTITY" build

APP="$ROOT/TestServer/.build/Build/Products/Debug/ErrorUpdate.app"

# xcodebuild can return 0 without building anything — check for the product
# instead of packaging whatever the previous run left behind.
if [ ! -d "$APP" ]; then
    echo "ERROR: the build did not produce $APP" >&2
    exit 1
fi

ACTUAL_REQ="$(codesign -d -r- "$APP" 2>&1 | grep 'designated =>' || true)"
case "$ACTUAL_REQ" in
    *cdhash*)
        if [ "$SIGN_IDENTITY" != "-" ]; then
            echo "ERROR: a certificate signature was requested, but the bundle is ad-hoc." >&2
            echo "      Xcode considered the build up to date and did not re-sign — delete TestServer/.build." >&2
            exit 1
        fi
        ;;
esac

echo "==> Packaging into a ZIP..."
mkdir -p "$WWW/downloads"
rm -f "$WWW/downloads/ErrorUpdate-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$WWW/downloads/ErrorUpdate-$VERSION.zip"

echo "==> Generating the manifest (SHA-256 + Ed25519 signature)..."
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
