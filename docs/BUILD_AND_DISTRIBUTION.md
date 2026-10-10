# Build and distribution

## Requirements

- Apple Silicon Mac running macOS 26 or later.
- Xcode with the macOS 26 SDK and Swift 6.2 or later, selected with `xcode-select`.
- Your own OpenAI Platform API key for extraction/transcription. Offline unit tests do not need a key.

From a clean source checkout:

```sh
swift test --disable-sandbox
bash scripts/build-app.sh release
open "dist/Live Scorecard 2.app"
```

The app has a separate bundle identifier (`ai.cranston.live-scorecard-2`) and local data directory (`~/Library/Application Support/LiveScorecard2`). It does not replace an older Live Scorecard app. Enter a key in Settings; the packaged app uses Keychain and does not need the source directory or a developer `.env` file.

## First launch

1. Open Settings, enter your API key, Save to Keychain, then Test text APIs.
2. Choose OpenAI cloud transcription and your meeting browser. Use headphones to separate the microphone from remote voices.
3. Enter an event name and, optionally, a stable firm name. Press Start. Calendar is optional.
4. macOS may request Microphone and Screen & System Audio Recording access. These permissions are needed for live capture. Transcript-only mode and synthetic replay do not require them.
5. If permissions were changed in System Settings, restart the app and reconnect audio.

Add Google Calendar through macOS Internet Accounts, enable Calendars, then choose Connect calendars in Settings. Automatic event matching/naming is deferred.

## Sharing this build

The default build uses an ad-hoc signature. It is **not Developer ID signed or notarized**. You can share the source and app ZIP, but macOS may prevent a downloaded copy from opening normally. Recipients can build locally or use Apple's standard per-app approval flow in System Settings → Privacy & Security after attempting to open a trusted download. Do not disable Gatekeeper globally. Some managed Macs require administrator approval.

For a signed release, supply a Developer ID Application identity you control:

```sh
SIGNING_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" bash scripts/build-app.sh release
```

That command signs only; it does not notarize. A distributable notarized release additionally needs Apple developer credentials, hardened-runtime signing/entitlements appropriate to the app, notarization submission, and stapling. This project's ad-hoc artifacts do not claim those checks passed.

## Release archives

After committing the intended source revision, run:

```sh
bash scripts/package-release.sh
```

This builds the native release app, archives the committed source, scans both archives for credentials/private runtime data, and writes SHA-256 checksums. A dirty source tree is rejected so the source archive corresponds to the binary's input revision. The ZIP is an Apple Silicon build; it is not an Intel/universal build.

## Privacy and retention

Transcripts are sent to OpenAI when cloud processing is enabled. The app keeps company facts locally, with raw transcript retention set to 30 days by default. Cleanup on launch skips unfinished/pending calls. Evidence excerpts and the change ledger remain with the company. History can export company JSON or permanently delete a company and its calls from this Mac. This does not remove provider-held processing records.

Screen-sharing exclusion is requested by default through the macOS window policy. A real Google Meet capture-mode check is still required; do not treat that preference as proof that every capture method hides the window.
