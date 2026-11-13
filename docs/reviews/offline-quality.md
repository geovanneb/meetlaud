# Offline meeting quality review

Branch: `fix/offline-meeting-quality`. Review date: 2026-11-13.

This is a quality pass over the existing application, not a complete redesign or a
claim of feature parity with another product. The established monochrome identity,
blue actions, recording red, semantic type scale, native navigation, and accessibility
rules remain the basis of the interface (D-001, D-045, D-070, D-079).

## Changes

- Backup restore checks the authenticated end of the stream, rejects trailing data,
  early terminators, duplicate destinations, invalid frame flags, and NUL path
  characters. Invalid input is rejected before replacing the live database. Archive
  copying checks cancellation between chunks and before committing a restore.
- Repeat cleanup no longer mistakes the beginning of a longer word for another
  repetition. English, Portuguese, and Spanish regression cases preserve those words.
  The standalone `[BLANK_AUDIO]` annotation from Whisper is excluded from meeting text.
- Playback caches the active transcript index instead of searching by UUID on every
  100 ms timer tick. Refresh invalidates the cache; seeking updates highlighting
  immediately. Speaker-turn headers use the row's index instead of rescanning the
  transcript. This reduces algorithmic work; no device frame-rate claim is made.
- Canceled searches cannot publish results after the database finishes a superseded
  query.
- Empty Ask history and Memory use natural-height list content, so they scroll with
  their page and grow with Dynamic Type. Shared EmptyState content uses semantic
  primary/secondary colors in both full-screen and inline layouts. Related: #10.
- Export sheets own separate temporary directories, preventing one scene from removing
  another's file. Preparation errors show a localized explanation and retry action
  instead of an endless spinner. The two new strings have machine-assisted en, ja,
  pt-BR, and es translations and still need native-language review.
- A meeting with vocabulary entries kept only its first three minutes of text. The spellings went to Whisper
  as a prompt, and WhisperKit 0.18 returns no text and no error for a piece that has one (fixed upstream in
  1.1, argmax-oss-swift #514). Only the first window, which detects the language, runs without a prompt. The
  prompt is no longer sent; `VocabularyCorrector` still fixes spellings in the text. Moving to WhisperKit 1.1
  would bring the prompt back and is separate work, with its own license and device checks.
- A piece of audio with no signal above −60 dBFS is skipped. Whisper Turbo answered digital silence with
  "Thank you."
- The calendar month strip honors Reduce Motion.
- Segmented tabs can be dragged. The drawer's drag is now a UIKit pan that refuses to begin unless the drawer
  will use it, and the recording page asks its scroll view whether the person is scrolling instead of adding
  a drag gesture. A SwiftUI drag over a whole screen takes the touch from the controls under it.
- The template editor keeps the keyboard while a section title is typed (rows were identified by their text),
  and says what is missing while Save is off.
- The iPad Settings test scrolls to the About row, which is below the fold in landscape.
- `make eval-transcription` generates fictional speech and evaluates the actual
  conditioning/windowing/Whisper/cleanup code on a Mac, with network access denied
  during inference. Model download verification streams its hash instead of reading
  an entire weight file into memory. No new application dependencies are introduced.

## Capability review

The comparison uses published feature categories, not copied layouts or assets:
[Plaud transcription and summaries](https://support.plaud.ai/hc/en-us/articles/53793130069657-Transcribe-and-summarize)
and [Plaud Intelligence](https://www.plaud.ai/pages/plaud-intelligence).

| Area | Existing implementation | Remaining validation or gap |
|---|---|---|
| Capture and import | Native recording, pauses, markers, photos, audio import, recovery | Real-device long capture, interruption, and disk-pressure tests |
| Transcription | Local Whisper/Apple adapters, vocabulary, versions, editing | Generated speech benchmark is limited; human voices, accents, and room noise still need evaluation |
| Speakers | Diarization, correction, suggestions, voice prints, talk-time statistics | Consented multi-speaker meetings, overlap, and similar voices |
| Summaries | Templates, tasks, citations, translation, mind maps | Real-model factuality and multilingual long meetings |
| Questions | One meeting, folder, or library; source links; explicit memory | Retrieval precision and citation entailment; a citation alone does not prove truth |
| Organization | Folders, full-text search, calendar, trash | Larger libraries and device-specific responsiveness |
| Export and security | Text/subtitles/PDF/audio, encrypted library archive, app lock | Restore crash atomicity (R-26) and real-device security/airplane-mode acceptance |
| Visual identity | Shared semantic colors, typography, spacing, buttons and progress | Manual VoiceOver, dark mode, Reduce Motion, iPad, and native-language review |
| Cloud/hardware features | Deliberately excluded by product policy | Accounts, cloud sync, web access, meeting bots, and proprietary hardware are not offline parity goals |

Live transcription, Watch capture, and a native Mac application remain roadmap work.
A full feature expansion needs separate scoped changes and must preserve the offline
and one-heavy-model rules.

## Evidence and release gates

The [generated-speech results](../../Evals/results/transcription-synthetic.md) record
four-language accuracy, the quiet/noisy and long English cases, and silence. The
benchmark's raw synthetic data stays in ignored `build/`; only aggregate results
belong in the repository.

Results on 2026-11-13:

- Full `make ci` before the last three changes above: lint, build, unit tests, and every UI test passed
  (80 passed, 13 skipped as iPad-only).
- After them: `make lint` clean, unit tests 525 passed and 1 skipped, and the generated-speech evaluation
  with Whisper Turbo, including the path the app takes (language detection and hints).
- After the tab and template changes: `make lint` clean, the unit tests again, the Shell, Speakers, Summary,
  Models, and Ask UI classes (50 passed), and the iPad class (4 passed). The Summary accessibility audit
  failed once in a class run and passed alone.
- On an iPhone 17, the debug probe (`--transcribe-probe`) ran a 31-minute recording with a vocabulary set:
  11 of 11 windows had text, to the end of the audio, the last four in the background.

Do not treat simulator tests as real-device acceptance. Do not ship an accuracy claim
based solely on synthetic speech. Capture interruption/recovery, airplane mode on an
iPhone, actual room acoustics, speaker recognition, and manual assistive-technology
review remain release gates from ROADMAP.md. The known restore crash window between
database and audio replacement (R-26) is not solved by stricter archive validation.
