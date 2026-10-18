# App refinement — 18 October 2026

Reviewed on iPhone 18 Pro simulator (iOS 27), built with Xcode 27.1. The existing learning profile was preserved. Text size and appearance were restored after testing.

## Flow review and changes

1. **Learn — improved.** The original slogan panel and XP card put the learning destinations below the first screen. The next lesson now shows its actual title and algorithm; Lessons and Practice precede XP. See 01-learn-before.jpg and 04-learn-after.jpg.
2. **Play — improved.** Removed the oversized gradient promotion and redundant statistics. Create and Join are now visible on the first screen at standard text size. See 02-play-before.jpg and 05-play-after.jpg.
3. **Lesson library and review — working in exercised flow.** Opened Lessons → BFS → completed first lesson, revealed Hint 2/3, selected B and checked the answer. Review reports that XP is already saved. Fixed review hints without rewriting earned attempts. Added a solid bottom action dock after observing lesson text behind its labels.
4. **Join sheet — improved; submission not verified.** Open/cancel works and empty code cannot submit. The sheet scrolls and uses a solid background to prevent underlying actions bleeding through; the input uses a separate surface. The automation typing tool did not reliably enter text, so normalization/keyboard interaction and a live room join remain unverified in this run.
5. **Map — working in exercised flow.** Walking route loaded; Next moved step 1/34 to 2/34; expansion showed the current search explanation; swapping endpoints rebuilt the graph and reset playback to 1/33. See 03-visualize-before.jpg and 08-map-replay-dark.jpg.
6. **Profile — working in exercised flow.** Opened from map and saved the unchanged profile, returning to the map. No user data was reset.
7. **Accessibility presentation — spot checked.** Learn and Play were inspected in dark appearance at accessibility-large text size. Labels wrap and content remains scrollable. See 06-learn-dark-large-text.jpg and 07-play-dark-large-text.jpg. This is not a VoiceOver or full accessibility audit.

## Automated validation

- Simulator build/install/launch passed after all source changes.
- Swift package: 71 core (including five invitation test methods with 42 cases), 19 learning and 8 progression tests passed.
- DuelStore: 13 checks passed, including late success, structured failure and disconnect after closing a result while a new request runs.
- Campus adapters: 14 checks passed. LearningStore: 7 checks passed.
- Independent checks: 22 search traces, 120 duel questions, 12 authored challenges.
- Core contracts CI previously failed on non-Sendable MapKit response objects in the Xcode 16.4 SDK. Both place search and walking directions now extract value types inside callbacks before resuming their continuations.
- PR #34 run 39110158955 (Core contracts) and 39110158963 (Duel variety/database) passed on commit 7474454. The QR follow-up is covered by a subsequent CI run on the same PR.

## Limits

No physical-device camera runtime, AR, live two-player duel, VoiceOver, or exhaustive offline/backend outage run was performed. Recovery is covered with deterministic service tests. The user's pre-existing Package.resolved modification is excluded from the PR.

## QR room joining follow-up

- Lobby displays the canonical invitation QR and retains the six-character room code/share action. The invitation card follows the refined visual style.
- Join a duel opens manual entry and Scan QR code. Valid scans populate the field; Join remains explicit. Malformed/unrelated QR codes show guidance.
- Camera permission is requested only after Scan; denied, unsupported, simulator, and scanner-start failure paths retain manual entry.
- The parser follows the backend schema: exactly six ASCII hexadecimal characters. Tests cover round trips, lower-case normalization, old raw codes, unrelated URLs, extra/duplicate fields, fragments, encodings, non-ASCII and oversized payloads.
- Both simulator build/run and unsigned generic iOS device build passed. Device build compiles the real camera-permission path, but does not validate physical scanning.
- Created a live test duel and captured 10-room-qr.jpg. Apple's Core Image QR decoder read the exact expected invitation from that rendered screenshot. Left the test duel afterward.
- Tapping Scan in Simulator showed the expected manual-entry fallback (09-qr-join-fallback.jpg).
- Scanner error handling follows Apple's DataScannerViewControllerDelegate availability callback: https://developer.apple.com/documentation/visionkit/datascannerviewcontrollerdelegate/datascanner(_:becameunavailablewitherror:)
