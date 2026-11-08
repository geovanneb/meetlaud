# Decisions and risks

The log of choices that shaped the app, so that nobody has to guess why. IDs such as `US-` and `F1` to `F8` refer to the original delivery plan, which is no longer published. To change a closed decision, open an issue first.

## Decisions

Status: **Closed** (decided by the project owner or confirmed by data), **Proposed** (the plan's default, can change).

| ID | Decision | Reason | Status |
|---|---|---|---|
| D-001 | Side menu on iPhone. Native sidebar on iPad | Familiar to people coming from other recorders, and keeps the record button in reach. Requires a custom drawer with full accessibility | Closed |
| D-002 | Data excluded from iOS backup by default, with an option in Settings and encrypted export | Keeps the promise without trapping the user | Closed |
| D-003 | iOS 26 minimum. AI adapted to the device, in tiers | SpeechAnalyzer, `BGContinuedProcessingTask`, and maximum reach | Closed |
| D-004 | GRDB instead of SwiftData | Migration control, FTS5 with a custom tokenizer, predictable performance | Proposed |
| D-005 | Vectors in BLOBs with brute force (Accelerate), instead of `sqlite-vec` | Simple, sufficient for one person, avoids a custom SQLite | Proposed |
| D-006 | Public name **Meetlaud** | Owner's choice. The name lives only in `Config/Product.xcconfig` and the String Catalog, so it can change quickly | Closed |
| D-007 | Apache-2.0 license | Permissive, with patent protection, compatible with the App Store. GPL has a known conflict with App Store terms | Proposed |
| D-008 | Local SPM + XcodeGen | No `.pbxproj` conflicts, modules with real boundaries | Proposed |
| D-009 | MVVM with `@Observable`, no architecture framework | Lower barrier to contributing | Proposed |
| D-010 | Multiple engines behind ports | No model wins in every language | Closed by data |
| D-011 | FluidAudio for diarization and voice prints | Only path with documented embeddings in an open tier | Proposed, depends on SP-3 and SP-6 |
| D-012 | External connectors out. Share sheet and Shortcuts instead | Consistent with "no data leaves". Replaced by D-067 at the owner's request | Superseded |
| D-013 | No Private Cloud Compute, ever | It would leave the device, even with Apple's guarantees | Closed |
| D-014 | Model catalog embedded in the app, with no server | Traffic only happens when the user downloads | Proposed |
| D-015 | Auto-transcribe defaults to Ask | The owner asked for it to be optional, and transcription uses battery | Proposed |
| D-016 | Skills and Mind map after 1.0 | Focus on core quality. Skills moved up by D-068 at the owner's request. Mind map stays after 1.0 | Superseded in part |
| D-017 | All documentation, code, and commits in English | Owner's decision, suits an open-source project | Closed |
| D-018 | One independently selectable model per role, replacing fixed download packs | Owner's request. Onboarding still offers one recommended setup | Closed |
| D-019 | Speed test on the user's device, labeling values as Estimated or Measured | Owner's request. Public data for iPhones is scarce, and hardware varies | Closed |
| D-020 | Device Advisor monitors the device continuously, event driven, local only | Owner's request. Event driven so monitoring does not drain the battery | Closed |
| D-021 | The advisor only suggests. Automatic mode may only switch among installed models | Keeps the user in control, with no surprise downloads or deletions | Proposed |
| D-022 | Model recommendation is a pure Domain function | Deterministic and testable with tables | Proposed |
| D-023 | Silero VAD ships inside the app | Small, MIT licensed, and also powers the device probe | Proposed |
| D-024 | URLs never start capture. `meetlaud://record` only navigates | Any app can open a URL, so a URL must not turn on the microphone. Capture starts from a user tap or an App Intent | Closed |
| D-025 | One `Package.swift` with one target per module, iOS only | One readable dependency graph. macOS is added when Evals or the Mac app need it | Proposed |
| D-026 | `EmptyState` replaces `ContentUnavailableView` | The system view failed the Dynamic Type audit | Closed by data |
| D-027 | Screenshots of other products never go into the repository | They may carry other companies' designs and personal data | Closed |
| D-028 | Raw PCM segments while recording, encoded to M4A at the end | AAC in CAF, the original plan, lost its audio after SIGKILL, and M4A was unreadable. PCM in CAF survived, but raw data depends on no container at all | Closed by data |
| D-034 | Transcription works on 3-minute windows cut at the quietest moment | Whole files take over 1 GB in memory for 3 hours. Windows keep memory flat and give each save point | Closed |
| D-035 | `ModelArbiter` gives one owner at a time to heavy models | A speed test unloaded the model under a running transcription and crashed the app on a real iPhone | Closed by data |
| D-036 | The tokenizer ships as part of each Whisper model, and the engine refuses to run without it | WhisperKit silently downloads a missing tokenizer, from a place no check can see | Closed |
| D-037 | Transcript search uses FTS5 with the trigram tokenizer, plus `LIKE` under 3 characters | Handles Japanese with no custom tokenizer, replacing the plan in the Architecture doc | Proposed |
| D-038 | The device probe waits for the bundled VAD in F4 | Estimates use reference devices until then, which is honest with one reference device | Proposed |
| D-039 | The diarization model is pinned to the revision FluidAudio is built for | The package refuses any other revision, and model and code must move together. `ModelHub.offlineMode` stays on, so it can never download | Closed by data |
| D-040 | Speakers run after transcription, and a failure there never costs the transcript | Speakers are a bonus on top of the text. With no model, transcripts simply have no speakers | Closed |
| D-041 | A recognized voice is only ever a suggestion until someone confirms it | A wrong name in a meeting record is worse than no name | Closed |
| D-042 | F4 comes before SP-1 while the iPhone is unavailable | MLX needs a real GPU, and the simulator cannot answer SP-1 | Closed |
| D-043 | Qwen 3.5 2B, text weights only, is the working language model for 8 GB devices | Ran on iPhone 17 in 3 languages. Dropping vision weights saves 663 MB | Proposed |
| D-044 | Every claim in a summary links to its moment in the audio | The model assigned a task to the wrong person in SP-1, and evidence lets people catch that | Proposed |
| D-046 | A short meeting goes straight to the model, and only long ones are condensed into notes first | Every summarizing step loses detail, and SP-1 showed how easily details go wrong | Proposed |
| D-047 | A language model stops at any step away from `.active`, and when a recording starts, then resumes from its last saved step | GPU work must end before iOS suspends the app, and recording comes first. Stopping costs one section at most | Proposed |
| D-048 | Each template section is one request, and tasks use owner, task, and date lines with rules for who owns what | SP-1's worst error was a wrong owner in free text | Proposed |
| D-049 | A citation that points at no phrase is removed, and the item is flagged for review. So is an owner nobody mentioned | A link to nowhere looks like proof. The model's claims are never trusted on their own | Proposed |
| D-045 | The icon is a flat black mark on full-bleed white, and the app uses the same mark as a transparent template | iOS rounds the corners itself. The template follows Light and Dark, and dark and tinted icons are generated from the same shape | Closed |
| D-030 | Files arrive through document types ("Open in Meetlaud"), not a Share Extension | Same result in the share sheet, with no App Group, entitlement, or extra target | Proposed |
| D-031 | Search uses `LIKE` over titles and notes until transcripts exist | Works in Japanese today. FTS5 with a custom tokenizer arrives in F3, where volume justifies it | Proposed |
| D-032 | The Recordings folder is virtual: `folderID` nil | No default row to create, migrate, or protect from deletion | Proposed |
| D-033 | Trash moves merged originals instead of deleting them | Merging must be reversible | Closed |
| D-029 | Pause keeps the microphone open and drops samples | Keeps the app alive in the background, so that Resume works from the Lock Screen. The orange indicator stays on | Proposed |
| D-050 | Apple's `NLContextualEmbedding` is the working Search model | No download and no new license. Recall is uneven ([SP-5](research/SP-5-embeddings.md)), so this is the first choice behind `TextEmbeddingEngine`, not the final one. iOS fetches the assets, like Apple Speech | Proposed |
| D-051 | No similarity threshold. The model refuses with a fixed word, and an answer with no valid citation counts as a refusal | SP-5: scores for right and unrelated matches overlap. Same rule as D-049: a claim with no link to the transcript is not shown | Closed by data |
| D-052 | A meeting that fits in the context goes to the model whole. Larger scopes use hybrid search, merged by rank | Same reason as D-046. Chat about a short meeting does not depend on embedding quality, and citations land on the exact phrase | Proposed |
| D-053 | Deleting a recording removes its chunks, its scoped chats, and every answer that cites it | Citations quote the transcript, and a deleted meeting must leave no words behind. Trash keeps them, and only hides them from search | Closed |
| D-054 | "Remember that..." is matched by fixed phrases in each language, never by the model | Text from a meeting must never be able to write to memory. See R-13 | Closed |
| D-055 | After an answer, the language model stays loaded and keeps the arbiter for 45 seconds, and lets go at once on leaving the foreground or when a recording starts | Follow-ups feel instant, with no reload of about 2 seconds (SP-1). Other work waits 45 seconds at most. If search needs embeddings, the language model unloads first, so the one-model rule holds | Closed |
| D-056 | The app asks iOS for the search models by itself, the first time Ask opens | Nobody should have to find a setting for search to work. iOS does the fetching, and word search works until it finishes | Closed |
| D-057 | A citation from a passage lands on the phrase sharing the most words with the claim | A link to the start of a minute-long passage is not "the exact time". With no shared words, as in a translated answer, it stays at the start of the passage | Proposed |
| D-058 | App Intents may start capture. They open the app first, because iOS only allows capture to start in the foreground | Extends D-024: an intent needs a person or a Shortcut they made, and a URL can come from any app. A press that launches the app waits in a queue until the app is ready | Closed |
| D-059 | One App Group, used only for the medium widget's snapshot. Meeting names reach it only with a preference that is off by default, and they are removed when it is turned off | A widget runs in another process, so it needs a shared file. Reverses the "no App Group" note in D-030. It is the first entitlement in the allowlist | Proposed |
| D-060 | On iPad, Home, Library, and Settings use three columns. Other destinations use two | Lists keep their place while the detail opens beside them | Proposed |
| D-061 | The app lock covers every scene from its own window, and only the background locks it | Sheets and the recording screen float above any view in the main window. Face ID itself makes the app inactive, so locking on inactive would loop | Closed |
| D-062 | The library archive uses AES-256-GCM in 1 MB blocks, with PBKDF2-SHA256 at 600,000 rounds. Each block's position and "last" flag are authenticated | Cut, reordered, or edited files fail. Three-hour recordings never have to fit in memory. Apple's system crypto, with no new dependency | Closed |
| D-063 | Importing a library replaces what is on the device, and only after the whole file reads correctly | The story is moving to a new phone. Merging two libraries is a different feature, with conflicts to resolve | Proposed |
| D-064 | Leaving voice prints out of an archive also clears each speaker's embedding, and voice prints are left out by default | A meeting's speaker embedding identifies a voice as much as a saved voice print does | Closed |
| D-065 | Erasing happens in place, with no restart: delete every row, `VACUUM` with `secure_delete`, remove files and models, and reset preferences | An app cannot relaunch itself, and iOS treats a self-quit as a crash | Closed |
| D-066 | Transcript notifications carry no meeting content | They show on the Lock Screen | Closed |
| D-067 | Connectors are plug-ins: `Connectors` holds the protocol and imports only Foundation, each connector is its own target that sees nothing else, and the app registers them in one place. The catalog ships with the app (decided by the owner), and nothing is downloaded or sent. The first one, Get Things Done over local Wi-Fi, shows as coming soon | The owner wants a marketplace and, last of all, sending to their own apps. A real download or send breaks "no networking outside `ModelDelivery`", and downloading code breaks App Review, so each needs its own decision first | Proposed |
| D-068 | A skill is saved instructions that shape an answer, added after the rule on sources, and kept in UserDefaults on the device | A skill changes the form of an answer and never where it comes from, so citations still hold. Skills are few and small | Proposed |
| D-069 | A section keeps 5 tasks or 6 other items at most, enforced in code, with repeats removed. Long meetings are read in 3 consecutive parts, and the parts take turns filling the section | On an iPhone 17, Qwen 3.5 wrote 21 key points against a limit of 6, and a 3-hour summary covered only the last project. A prompt cannot fix either. A section with more than 6 real points loses the rest | Proposed |
| D-070 | Type, buttons, and timing come from `DesignSystem`, and SwiftLint rejects raw fonts and bordered buttons in features. Lists are grouped, not plain | Each screen had chosen its own sizes and two different blues. Plain lists pin section titles, and rows slide under them | Proposed |
| D-071 | Spotlight is off by default, holds titles and dates only, and turning it off clears the index | The index reaches the Lock Screen, so showing meeting names must be the person's choice, as with widgets (D-059) | Proposed |
| D-072 | `ConnectorGTD` may use the local network, only to a computer paired by QR code, with files sealed end to end, on a hotspot or a shared network. The iPhone always starts, and the computer never pulls. Only audio goes by default, and only meetings recorded after pairing. `check-privacy` allows this one module, and it refuses any address that is not local | Approved by the owner. Meetings reach their own computer with no account and no cloud | Closed |
| D-073 | A transcription can wait for a charger. It is a job state (`waitingForPower`) in the existing column, so no migration. It starts once the device charges and is not hot, also after a relaunch. A note shows before a job of 10 minutes or more, or when the device is not Great. A folder word in Vocabulary replaces the global word with the same spelling instead of running after it | US-310 asks to offer waiting for power. Running a global word after a folder word would correct it twice ("Ana Paula" becoming "Anna Paula") | Proposed |
| D-074 | Speaker stats live in a "Speakers" section at the top of the Summary tab, closed by default to one line ("Ana 62% · Bruno 38%"). No fourth tab. Numbers come from the transcript, so merging speakers or moving a phrase updates them. Shown only with two or more speakers | Who spoke how much is part of "what happened", which is the Summary's job. It is glanceable and short, so a tab of its own would be mostly empty, and four segments do not fit at large text sizes in Japanese and Portuguese. The diarizer's own talk time ignores later corrections | Proposed |
| D-075 | Voice matching scores every speaker against every saved person and settles the closest pairs first. A name needs a score of 0.6 and a lead of 0.08 over the next free person. Embeddings are unit-normalized per turn, and before blending | Two people recorded together were named only one at a time: both speakers chased the same person, and 0.75 (picked on synthetic voices that scored 0.97) was out of reach for real voices. The lead keeps "a wrong name is worse than no name". Still provisional until SP-3 runs on real people | Proposed |
| D-076 | Each window is cleaned before transcription: an 80 Hz high-pass and gentle speech leveling (up to +18 dB, never applied to silence). The file on disk is never changed. Whisper splits windows at pauses (VAD, two workers), and vocabulary spellings go to the engine as hints (Whisper prompt, Apple contextual strings), not only as corrections afterwards. Neural noise suppression needs its own model and decision | A phone on a table hears the near voice much louder than the far one, and Whisper scales each 30 seconds by its loudest moment. Long pieces of silence are where Whisper invents text | Proposed |
| D-077 | Network activity can be cleared by the person, with a confirmation. After that, the empty screen says "No connections since you cleared the history", never "Nothing has left this device" | Requested by the owner. The screen must stay true, so it cannot claim nothing ever left | Proposed |
| D-078 | The person can separate voices again with the number of people who spoke, or let the model decide. A count they give goes to the diarizer as an exact number. With the automatic count, a voice heard for less than 2 seconds in a recording does not become a speaker. The text never changes, and names come back as suggestions | On a real 2-minute meeting, four people came out as one voice, and the same audio decoded slightly differently came out as three (SP-3). A known count gave four every time. The model's own default stays until more real meetings are measured |
| D-081 | With the automatic count, the diarizer tries one more speaker at a time, up to 8, and keeps the largest count whose voices all score below 0.5 against each other. Voices are found once, and only the grouping is repeated | Four people with plainly different voices (0.12 to 0.25) came out as one. On real meetings, one person split in two scored 0.77 to 0.94, so 0.5 never cuts a person in two. Two similar voices (0.75 to 0.78) still need the count from the person (D-078, SP-3) | Proposed |
| D-079 | Feedback has one vocabulary in `DesignSystem`: `ActivityBar`, `ProgressRing`, `StepList`, `StatusBadge`, `UsageBar`, and `.dsCard()`. A bar never stands still: an unknown fraction moves. Long work names its steps, shows elapsed time, and shows time left only once it can be measured. Every movement has a Reduce Motion form | The owner could not tell transcribing from stuck. A bar at 0% while a model loads, then a jump to 100%, reads as frozen. Research in [UX-1](research/UX-1-feedback-review.md) |
| D-080 | Before text is saved, a phrase repeated 6 or more times in a row keeps one copy followed by "[×N]", and a piece with no letter or digit is dropped. Numbers are never folded | Whisper loops on noise. The mark has no words, so it reads the same in all four languages. Same rules as Get Things Done, where they hold up on real meetings |
| D-082 | A pull request runs lint, unit tests, and a UI smoke set (`Tools/ui-smoke-tests.txt`). Every UI test runs on `main`, every night, and on a pull request that changes the UI tests, CI, or the build. A documentation-only pull request skips the macOS jobs (`Tools/ci-scope`) | Every UI test on every pull request meant six macOS jobs and about 30 minutes, even for a typo, on GitHub's queued 3-core Macs. Contributors need an answer in about 10 minutes. A UI regression the smoke set misses fails on `main` or overnight, close to the change that caused it | Closed |

## Risks

| ID | Risk | Impact | Probability | Mitigation |
|---|---|---|---|---|
| R-01 | LLM is unstable or slow on iPhone | High | Medium | Short meetings ran well in SP-1. Long meetings and heat are still unknown. Map-reduce, checkpoints, tiered models, Foundation Models as an alternative |
| R-22 | Summaries state wrong facts, such as the wrong owner of a task | High | High | Seen in SP-1. Evidence links, a dedicated task step, and a rubric that measures ownership |
| R-23 | Search quality is uneven, and weak in Spanish | High | High | Measured in SP-5. Hybrid search, whole-meeting context, and citations. A downloadable model can replace it behind the port |
| R-24 | A model may cite a real line for a false claim. Citations prove the line exists, not that it supports the claim | High | Medium | Citations are visible and open the audio. Not yet measured with the real model |
| R-25 | `ITSAppUsesNonExemptEncryption` is false, and the archive now encrypts with AES through CryptoKit | Medium | Medium | It uses only Apple's system crypto for the person's own data, which is usually exempt. Needs a review of the export rules before submission, with SP-7 |
| R-26 | Restoring swaps the database, then the audio folder. A crash between the two leaves old audio paired with new data | Medium | Low | The window is short, and the archive still exists to restore again. Not handled further |
| R-02 | Memory: iOS kills the app with a model loaded | High | High | `ModelArbiter`, entitlement, one model at a time, conservative budget |
| R-03 | No background GPU on iPhone | Medium | High | Transcription on ANE/CPU. LLM in the foreground. Clear communication |
| R-04 | Overheating in long meetings | Medium | High | Watch `thermalState`, pause and resume |
| R-05 | Lost recording | Critical | Low | Segments, recovery, resilience script, dedicated slice 1 |
| R-06 | App Review rejects background mode or downloaded models | High | Low | SP-7, early TestFlight, clear review notes |
| R-07 | A model license blocks distribution | High | Low | SP-6 done. CC-BY models need attribution, and the catalog pins only cleared artifacts. Re-verify before release |
| R-08 | pt-BR or ja quality below expectations | High | Medium | Per-language eval, per-language engine selection, glossary |
| R-10 | Legal rules for recording and biometrics | High | Medium | Consent notices, optional and deletable voice prints. Legal advice before launch |
| R-11 | Abandoned dependency | Medium | Medium | Ports allow replacement |
| R-12 | Models use too much space | Medium | High | Packs, explicit sizes, easy deletion, Apple option with no in-app download |
| R-13 | Prompt injection through meeting content | Medium | Low | Content treated as data, no action without confirmation |
| R-21 | Voice recognition was measured only on synthetic voices | High | High | Suggestions need confirmation, and thresholds stay provisional until SP-3 runs on real people |
| R-20 | Whisper's transcript is verified only on one device and short audio, and airplane mode is not tested on a device | High | Medium | Sockets watched during real inference showed no traffic (SP-4). Long audio in SP-2, and an airplane run needs a cable |
| R-19 | Calendar and import were tested with fakes and simulators only | Medium | Medium | Manual check on a real iPhone before closing F2 |
| R-14 | Hugging Face changes or goes offline | Medium | Low | Pinned commit, SHA-256, `ModelRegistry.baseURL` allows a mirror |
| R-15 | Estimates mislead users | Medium | Medium | SP-8, ranges instead of single values, Estimated and Measured labels, real runs replace estimates |
| R-16 | Speed tests heat the device and drain battery | Low | Medium | Condition checks, foreground only, cancelable, sustained test is opt-in |
| R-17 | Too many options confuse regular users | High | Medium | Automatic by default, one-tap setup, technical details only in the hub |
| R-18 | Reference benchmarks need a device lab | Medium | High | Start with the devices we have (Q-03), plus community reports shared by choice |

## Open questions

| ID | Question | Owner | Blocks |
|---|---|---|---|
| Q-06 | Results of the SP-4 manual scenarios, especially resuming after a call in the background | Owner | Closing F1 |
| Q-02 | Can we get real meetings with consent for the eval, in all 4 languages? | Owner | SP-2, F3 |
| Q-03 | We have iPhone 17 (T2). Which devices can cover T0, T1, and T3? | Owner | SP-1, SP-2, SP-8 |
| Q-04 | Will this ship under a personal or a company Apple Developer account? | Owner | F1 (entitlements, TestFlight) |
