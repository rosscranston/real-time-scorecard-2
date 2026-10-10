# Overnight execution: Real-time Scorecard 2

Target delivery: **Saturday, October 10, 2026, 08:00 America/Los_Angeles**. Work window: approximately eight hours tonight. Finish core implementation by 06:30, then protect time for regression checks, packaging, and the delivery report. These times are planning targets, not guarantees.

This plan is the current execution order and overrides older provider/deadline references. Product behavior is specified in PROJECT_PLAN.md, the conversation, and configurations/company-scorecard.draft.json. Do not use ElevenLabs. Use OpenAI Decisions for classification, OpenAI Responses for other extracted values, and OpenAI streaming transcription for cloud audio. Retain Apple Speech as an explicit optional choice only; never silently switch to local transcription or local LLM extraction after an API failure.

## Preflight result and overnight operating rules

Read PREFLIGHT.md before starting. Decisions and Responses work with the configured key. OpenAI streaming transcription configuration failed with `credit_balance_exhausted`. Do not retry that quota failure in a loop. Implement and test the audio adapter using synthetic replay while the account issue is unresolved; mark live cloud transcription blocked until an actual successful audio test. Do not call the key globally invalid: text endpoints passed.

The Mac was on battery with about two hours remaining at preflight. It must be plugged in and kept awake with the local Codex run available. A goal does not supply an always-on cloud machine or override account usage limits. Use a bounded keep-awake assertion during an active overnight run when plugged in; do not alter permanent power settings or assume this prevents lid-close sleep. No separate recurring automation or duplicate build worker is required for this goal.

Continue all independent work when one integration is blocked. Record progress and failures in PROGRESS.md after each milestone or meaningful interruption so a later goal turn resumes from actual state. Use synthetic inputs for unattended paid tests, a conservative $5 maximum estimated API-test spend, request/output limits, and a local usage ledger. Stop paid testing at the cap or a quota error for that endpoint. No purchases, recharge changes, provider switching, or unbounded retry loops. If prices/usage cannot be estimated safely, use bounded smoke tests and mocked tests until the uncertainty is resolved.

## Milestone 1 — Independent app and reliable cloud extraction

Target: 23:30–01:00 Pacific.

- Copy only relevant Swift source/resources from the prior project into this independent repository. Keep a distinct app name, bundle identifier, and data directory. Preserve the old app.
- Remove inherited automatic GitHub transcript publication and disable local FoundationModels extraction. Exclude unrelated Circleback automation from the critical path.
- Implement a shared OpenAI client with safe error handling, bounded retries for transient errors, quota-stop behavior, and no credential logging.
- Implement native Settings → Connections: masked key entry, Keychain save/remove, synthetic Test connection. Developer .env support must never become a bundled release dependency.
- Connect Decisions choices and Responses typed extraction to the reducer. Start benchmarking gpt-6-luna Responses with reasoning disabled, which passed the 1.71-second preflight; increase reasoning only where measured correctness requires it. Keep independent extraction parallel rather than always stacking sequential calls.
- Build a replay path that can populate the live scorecard without microphone permissions or a meeting. Label replay mode visibly.

Gate: build succeeds, synthetic transcript fills software/hosting/number/text fields with matching evidence, invalid API output cannot commit facts, and failure states are visible. Key leakage checks pass. This gate is more important than UI polish.

## Milestone 2 — JSON catalog, company memory, and correction rules

Target: 01:00–02:30.

- Replace the fixed enum as the runtime catalog with the supplied JSON design, up to 50 fields. The draft has 41 catalog fields, 33 marked for automatic extraction; metadata-only entries do not become transcript-triggered actions.
- Validate IDs/types/options/aliases/layout references; atomically import configurations, keep previous versions, switch active configuration, and export edits. Preserve hidden historical facts.
- Implement company-scoped current answers and evidence with persistent SQLite storage. Preserve calls and full transcript views, calendar matching, manual company selection, and independent contact identity.
- Enforce automatic updates for unlocked fields, manual-edit auto-lock, immutable locked values, proposed conflicting replacements, acceptance remaining locked, source policies, undo, evidence watermarks for cleared fields, and company/config/segment-version checks for late responses.
- Apply midpoint and aggregate arithmetic rules only to supported inputs. Preserve approximate evidence instead of representing inferred numbers as measured facts.

Gate: meaningful tests prove locks, stale-result rejection, firm separation, persistence, configuration switching, and correction/undo behavior. Restarting the app retains state.

## Milestone 3 — Approved scorecard interface

Target: 02:30–04:00.

- Preserve narrow black/green monospaced styling and approved spacing; window is resizable.
- Show one value per field, yellow ? for unknown, red tentative values, source dots, and evidence behind +.
- Sections remain collapsed until manually opened; display the number of distinct fields changed while collapsed and a separate conflict marker. Persist collapse preferences by company.
- Support inline editing, lock/unlock, hover/focus full-value disclosure, brief update highlights, keyboard navigation/undo, and initial/demo/review order. Keep transcript preview hidden but preserve the transcript view.
- Keep source mappings and internal implementation details out of normal call UI. No overall score or follow-up-question generator.

Gate: inspect actual rendered UI using available desktop tools; compare against approved previews. Exercise narrow/resized layouts, large catalogs, long values, keyboard editing, and collapsed updates. If desktop inspection is unavailable, report that validation gap rather than substituting a generated mockup for evidence.

## Milestone 4 — Live audio, calendar, recovery, and realistic replay

Target: 04:00–05:30.

- Preserve separate microphone and Chrome audio channels using existing capture code. Use separate OpenAI transcription streams to preserve salesperson/customer roles, with client-side turn boundaries and stable segment revisions. Do not rely on the model to return speaker labels it does not provide.
- Implement reconnect, bounded audio buffering, explicit gaps, transcript-job persistence, post-call drain, and manual debrief mode. Never send a stale response into a new company or call.
- Ensure capture permissions and calendar permissions have clear onboarding states. Only capture after the user starts a session; unattended tests use files or synthetic audio.
- Use the five existing labeled fixtures and three longer synthetic conversations. Add a synthetic audio-file input path and at least one 45-minute replay/soak run. Real Google recordings are currently unlocated; do not wait for them to implement the app.
- If OpenAI audio quota becomes available, run a bounded actual transcription test. Until then, keep audio access blocked and use replay to test the rest of the pipeline.

Gate: successful replay and restart/reconnect tests with no lost/duplicated company facts; actual cloud audio success required before claiming it works. Measure sentence-end → transcript → API → reducer → visible UI separately. Preserve screen-sharing exclusion default, but mark Google Meet capture-mode testing pending if not actually observed.

## Milestone 5 — Accuracy, latency, and release candidate

Target: 05:30–06:30.

- Evaluate corrections, negations, historical versus current software, uncertain hosting, speaker attribution, short answers, named entities, numerical ranges, and irrelevant demo talk on labeled cases.
- Target at least 95% committed-answer precision, 90% answerable-field recall, zero lock overwrites, zero cross-company writes, and p95 end-to-end latency ≤5 seconds. Report real sample sizes and distinguish transcript-only from audio-to-screen timing.
- Fix observed failures. Avoid tests that merely mirror implementation and avoid endless reruns after stable passes.
- Measure CPU/memory during replay. A true Google Meet interference check requires a live call, so do not infer that it passed from a replay.
- Freeze features by 06:30; switch effort to reliability and packaging.

Gate: test report with measured results, clear remaining failures, and an identified release candidate. Never convert an unmet target into a pass because the deadline is close.

## Milestone 6 — Package and deliver

Target: 06:30–08:00.

- Produce dist/Live Scorecard 2.app, an app ZIP or DMG, a clean source ZIP, checksums, reproducible build instructions, and release notes. Check license/ownership of reused source and assets before attaching an open-source license.
- Verify release artifacts contain no API keys, private fixtures, contact examples, databases, logs, source-machine paths required at runtime, or automatic transcript publishing credentials.
- Use available development signing for a local build. Developer ID/notarization is not currently available; label distribution status honestly. Do not disable system security settings.
- Publish source and release assets to the intended dedicated GitHub repository only with verified access and an appropriate isolated target. SSH read access to the old repository is not proof that release uploads work, and its parent checkout contains unrelated private material. If publication remains blocked, still deliver local app/source artifacts and exact upload steps by 08:00.
- Write FINAL_REPORT.md with artifact links, build/test evidence, measured latency/cost, implemented versus deferred features, blockers, and the short first-launch checklist.

Delivery gate: the built artifact launches, the configured synthetic replay exercises the real app pipeline, manual locks and persistence work, API settings are usable, source rebuild instructions are accurate, and remaining cloud-audio/live-Meet/publishing limitations are explicit. Full goal completion requires all required functionality and verification, not merely generation of a report.

## Scope protection

Keep JSON import/export, supplied field definitions, correct evidence, locked-value safety, persistence, key setup, transcript replay, and a real app binary. If time runs short, defer rich per-field Settings editors (JSON remains editable), automatic alias learning, exhaustive shortcut customization, advanced usage dashboards, and cosmetic polish. Record all deferrals. Multi-user sync, hosted admin, CRM writeback, multi-package UI, and a self-modifying model harness remain out of scope.

Missing real recordings, signing credentials, GitHub release access, or audio quota must not prevent the independent core app and local artifacts from being built. These remain blockers to the corresponding acceptance gates, not excuses to stop unrelated work.

## Goal-mode objective

Build and verify Real-time Scorecard 2 in this workspace by October 10, 2026 at 08:00 Pacific, following OVERNIGHT_PLAN.md, PROJECT_PLAN.md, the supplied configuration, and the approved UI decisions. Use OpenAI Decisions and Responses; use OpenAI for cloud transcription and exclude ElevenLabs. Work autonomously through implementation, testing, bug fixes, packaging, and an evidence-based final report, resuming from PROGRESS.md after interruptions. Preserve the old app and private data. Use bounded API testing and continue offline work when an endpoint or external release step is blocked. Prioritize the actual usable app and reproducible local artifacts, then public release where access permits. Report any unmet requirement honestly; do not mark the goal complete while required work remains. At 08:00 deliver the current release artifacts and explicit blocker/verification status, even if some acceptance gates remain unmet. The deadline does not automatically stop or complete the goal; the user's Goal-mode controls govern further execution.
