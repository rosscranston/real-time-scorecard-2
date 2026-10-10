# Overnight preflight — October 9, 2026, approximately 23:20 Pacific

These are observed checks, not promises of eventual performance. Credentials were read locally by the test processes and not printed.

| Check | Result | Consequence |
|---|---|---|
| OpenAI Decisions key/access | PASS: two synthetic classifications in 0.85s | Can implement and test fixed-option extraction |
| OpenAI Responses structured extraction | PASS: correct number and exact evidence, 6.73s with low reasoning; 1.71s with reasoning disabled | Start with the faster setting, then benchmark quality and p95 over realistic cases |
| OpenAI Realtime transcription | BLOCKED: session configuration returned `credit_balance_exhausted` | API billing/credits or model entitlement needs account-side resolution; do not assume other successful endpoints share the same eligibility |
| API secret handling | .env is Git-ignored; no key output in probes | Keep keys in Keychain for packaged app and out of all release archives |
| Toolchain | Xcode 27.0, Swift 6.4, arm64 macOS 26.6.2 | Meets the existing package's stated baseline |
| Disk | About 549 GiB free | No current disk-space blocker |
| Native baseline build | PASS: prior app built in 7.88s using the installed toolchain | Existing source is a usable starting point; the new app is not yet implemented |
| Labeled transcript fixtures | Five short calls with 74 gold fields total, plus three longer synthetic scripts (about 9–10 minutes each) | Enough to begin unattended replay; gold mapping must be adapted to the new configuration |
| Real audio/Google recordings | No audio files found in the project inventory; connected Drive searches found no Meet Recordings folder or audio/video files | No verified real audio benchmark yet; this is not a claim that none exist anywhere |
| GitHub CLI | Not logged in | `gh` cannot currently create/upload a release |
| GitHub SSH | Read access to rosscranston/live-scorecard succeeded | Source access works; write permission and release-asset upload are not established |
| GitHub connector | Authenticated as rosscranston; current repository listing returned only private ai-os | Not a verified publishing route for the new app |
| Apple signing | Apple Development identities available outside sandbox; no Developer ID Application identity found | Can attempt local development signing; notarized external distribution remains unverified/unavailable |
| Power | Battery 45%, approximately 2:06 remaining; not plugged in | Must connect power before an eight-hour local run |
| Codex allowance | Current account permits ordinary usage; weekly usage 47% at check | Not currently rate-limited; this does not guarantee eight hours of future availability or fund the OpenAI audio API |
| Mic/system-audio/calendar permissions | New bundle not built yet; permissions cannot be verified for it | First live capture/calendar launch may require user interaction; replay can run unattended |
| Google Meet sharing exclusion | Not tested in a live Meet session | Preserve setting, but do not claim invisibility verified |

## User actions that remove external blockers

1. Plug the Mac into power; keep the local run available, network connected, and lid open.
2. Check the billing/project behind the OpenAI API key for the audio `credit_balance_exhausted` response. A successful Decisions request or ChatGPT credit balance is not proof of Realtime audio availability. No additional key needs to be pasted into chat.
3. For automatic GitHub release upload, authenticate the GitHub CLI on this Mac and make the intended dedicated repository available. The agent can still produce local source/app archives without this.
4. If available, designate a real Google Meet audio recording plus transcript for final audio validation. Existing synthetic fixtures suffice to build and evaluate extraction overnight.

Development continues independently of these actions. Cloud transcription, actual Meet capture behavior, and public distribution cannot be reported as verified until their respective checks pass.

## Payment-method recheck

After the user added a payment method, the explicit Realtime transcription session recheck still failed, now with `rate_limit_exceeded`. Text extraction has already passed. No successful audio transcription is claimed. GitHub login can be completed in Terminal with `gh auth login --hostname github.com --git-protocol https --web`. Developer ID/notarization remain distribution requirements for a smooth download; they do not prohibit sharing the source or an explicitly labeled development build.

## Audio access cleared by actual test — October 10 ~00:07

The implemented OpenAITranscriber successfully accepted a session, transcribed 7.58 seconds of synthetic macOS Samantha speech, and fed the transcript into Decisions/Responses. Software, team size and return count matched expected values. The prior quota/rate-limit failures are historical, not a current blocker for this tested request. Raw microphone/Meet capture is still untested. No real customer audio was used.
