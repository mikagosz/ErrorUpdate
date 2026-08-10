# Local update test server

Lets you exercise the whole update cycle (check → download → SHA-256 + Ed25519
verification → codesign → install) with no hosting and no paid Apple Developer
account.

## Usage

```bash
# 1. Prepare the files (build the demo app + a ZIP of "version 9.9.9" + a signed manifest)
./TestServer/prepare.sh

# 2. Start the server (leave it running in a terminal)
./TestServer/start.sh

# 3. Run the demo app (DemoApp/ErrorUpdate.xcodeproj) and click
#    "Check for updates" — it will see "version 9.9.9" and download it.
```

> [!note] The app still reports version 1.0 after installing — that is expected
> `prepare.sh` packages the **current build** as "9.9.9" without bumping
> `CFBundleShortVersionString` in `Info.plist`. The install is real (the bundle is
> swapped, the app relaunches), but the version does not change.
>
> Since 0.4.0 the library notices: on the first launch after an install it compares
> the promised version with the actual one, sets `ineffectiveUpdate`, calls
> `updateDidNotTakeEffect(_:)`, writes to stderr and **stops offering 9.9.9**
> automatically. A manual "Check for updates" still shows it.
>
> In a test script this is a deliberate shortcut. In a real release the same
> symptom means you forgot to bump the version in Xcode before packaging.

The script generates Ed25519 keys in `keys/` if they are not there yet.
The demo app is configured for `http://127.0.0.1:8000`
(see `DemoApp/MyApp/ContentView.swift`).

## Server layout

```
www/
├── api/error-update/version-check   <- JSON manifest (what the "server" returns)
└── downloads/ErrorUpdate-9.9.9.zip  <- the update file
```

This is exactly the layout you will publish on real hosting — any static file
server will do (GitHub Pages, any web host). To release a new version of your own
app:

```bash
swift run errorupdate-tool release \
    --file MyApp-1.2.0.zip --version 1.2.0 \
    --url https://your-server.com/downloads/MyApp-1.2.0.zip \
    --key keys/errorupdate_private_key.txt \
    --notes "What's new..." \
    --out version-check
```

then upload `version-check` and the ZIP to your server.

## Notes

- Keep the private key (`keys/errorupdate_private_key.txt`) local — it is in
  `.gitignore`; never commit it and never upload it to a server.
- `http://127.0.0.1` works without HTTPS because macOS exempts loopback
  connections from App Transport Security. A real server must use HTTPS.
- `www/` and `.build/` are generated — they are in `.gitignore` too.
