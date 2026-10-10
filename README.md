# Real-time Scorecard 2

This workspace contains the implementation plan and an independent Swift app under development. The core supports the JSON catalog, SQLite company state, correction rules, and a real OpenAI Decisions + Responses pipeline. A native interface now supports named calls without Calendar, inline corrections/locks/undo, history, transcript input, JSON import/export, Keychain setup, and synthetic replay. Audio capture and final release verification remain in progress; this is not yet a release build.

## Overnight execution

See `OVERNIGHT_PLAN.md` for the October 10, 08:00 Pacific target and `PREFLIGHT.md` for verified blockers. Cloud transcription uses OpenAI; ElevenLabs is excluded.

## Enter your API key

Open `.env` in this directory and put your own OpenAI Platform API key after `OPENAI_API_KEY=`. Create a key at https://platform.openai.com/api-keys if needed. Do not paste it in chat. The file is excluded by `.gitignore`; `.env.example` contains placeholders for distribution. The connection test does not print keys or API error bodies.

For a fresh checkout, copy `.env.example` to `.env` first. Environment variables override file settings. No shell evaluation of the file occurs.

Run from this directory:

```sh
python3 scripts/test_decisions.py
```

This makes one billable API request using synthetic sales text. It checks that software is classified as Drake and hosting as on-premises, and reports confidence and request duration. It does not capture audio, upload customer calls, or update the Mac app. A successful check confirms access for this request, not sufficient credits for a full meeting or achievement of the five-second target.

Without a key or network call:

```sh
python3 scripts/test_decisions.py --dry-run
python3 -m unittest discover -s tests -v
```

Mac Settings now provides masked key entry, Save/Remove, and Test text APIs. Packaged apps store keys in macOS Keychain; developer runs can use `.env`. Keys will never be bundled into the downloadable app or exported in criteria JSON.

See `PROJECT_PLAN.md` for components, milestones, defaults, acceptance gates, and a future implementation-goal prompt.

## Starting criteria configuration

`configurations/company-scorecard.draft.json` adapts the supplied 39-field catalog into a 41-field draft, adding exact team size and separate hosting provider. It includes suggested call-type priorities, one answer per field, uncertainty and lock defaults, and extraction routes. The native app and probe load this configuration at runtime. The older Python smoke test uses only its two built-in questions.

The untouched source is stored under ignored `private-data/imports/company-fields.original.json`. Contact/company examples are omitted from the distributable draft. Attio mappings are metadata only and do not enable synchronization or writes.

## Official references

- Decisions API: https://developers.openai.com/api/docs/guides/decisions
- API pricing: https://developers.openai.com/api/docs/pricing
- ChatGPT pricing: https://learn.chatgpt.com/docs/pricing

API-key requests use the API project's billing. Do not assume ChatGPT subscription credits are the same balance; this test reports authentication/quota failures without exposing credentials.

## Build and test the native app

Requires macOS 26 or later and a compatible Swift/Xcode toolchain.

```sh
swift test --disable-sandbox
bash scripts/build-app.sh debug
open "dist/Live Scorecard 2.app"
```

The default build is ad-hoc signed, not notarized. Set SIGNING_IDENTITY explicitly for a certificate you control. Signing alone does not perform notarization.

Enter an event name and press Start; firm name is optional. Calendar is optional in Settings, where Google can be added through macOS Internet Accounts. Automatic Calendar naming is deferred. Transcript input currently supports manual synthetic snippets and post-call debrief. Live audio integration is still being implemented.

Paced replay of the supplied synthetic discovery scripts:

```sh
swift build --disable-sandbox --product ScorecardProbe
.build/debug/ScorecardProbe --replay --call 01-owner-story --interval 5
```

Intervals must be 3–30 seconds. Sentence arrivals continue independently of API completion. Reports and synthetic response diagnostics are saved under ignored test-results; the test spending ledger is under ignored private-data. The native Settings replay button loads the same JSON pack and uses five-second intervals. Its UI replay uses the app's own API usage ledger. Use Settings to save your key, or explicitly run ScorecardProbe --save-key to copy your development key into the local app Keychain entry. Neither method includes a key in the app bundle.
