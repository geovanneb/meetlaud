# Changelog

All notable changes to Meetlaud are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org).

## [Unreleased]

The first public version. Everything below runs on the device.

### Record
- One-tap recording from the app, widgets, the Lock Screen, Control Center, the Action Button, and Shortcuts.
- Background recording with a Live Activity, and recovery after a crash or interruption.
- Moments, notes, and photos during a recording. Audio import.

### Understand
- Transcription with Whisper or Apple Speech, tested in English, Japanese, Portuguese, and Spanish.
- Speaker separation, and optional voice prints that suggest names in later meetings.
- Summaries from templates or your own, with every claim linked to its moment in the audio. Long meetings are summarized in parts, so the beginning is never lost.
- Ask about one meeting, a folder, or the whole library, with cited sources. Memory of facts you ask it to remember.
- Action items to Reminders, mind maps, vocabulary per folder or for everything, and a polished reading mode.

### Stay in control
- Folders, full-text search, trash, and a calendar of meetings and recordings.
- App lock, and password-protected library export.
- AI models screen: one model per job, a recommendation for your device, speed tests, run history, and "try on my audio" to compare two models on a recording you choose.
- A note before long jobs with the expected time, and the option to start when the device is charging.
- Network activity screen listing every connection the app makes.
- Optional, encrypted delivery of new meetings to Get Things Done on your own computer, over your local network.
- Interface in English, Japanese, Portuguese, and Spanish.

### Fixed and improved since the first build
- Work in progress is always visible: after recording, the Summary and Transcript tabs show the steps of the transcription, a bar that keeps moving while the model loads, elapsed time, and time left once it can be measured. Home and Library rows show the same state as a badge.
- Speakers: when the app finds too few voices, "Detect again" lets you say how many people spoke. A voice heard for less than 2 seconds no longer becomes a speaker.
- Speakers: the automatic count now finds people whose voices are clearly different even when the model first merges them. Four people at a table were found as one before.
- The recording pill reacts to the finger and can be tapped anywhere on it, not only on its text line.
- Transcripts: a phrase the model repeats over and over is folded into one copy with "[×N]", and pieces with only punctuation are dropped.
- Storage & backup and AI model storage show space as one bar, next to what is free on the device. Model downloads show progress for every step, not only the download.
- AI models: after "Download all", the screen shows the download progress and the state of each function, instead of "Not installed". Each model counts only its own bytes, and pausing keeps what was received.
- Folders and the Speakers section open and close with motion, and with a fade when Reduce Motion is on.
- Home: "No recordings yet" no longer covers the upcoming meetings. It now sits under Meeting notes.
- Speakers: two saved people in the same meeting are both recognized. Matching scores every voice against every person, and voice prints no longer depend on how long or loud each stretch was.
- Speakers: a "Speakers" section at the top of the Summary shows how much each person spoke, their turns, and their longest turn.
- Calendars: Settings lists every calendar on the device by account, and each can be turned off, so a personal calendar stays out of Upcoming, Calendar view, widgets, and reminders. Calendars can also be turned off altogether.
- Home: the "See your meetings" card can be closed. Upcoming then shows one line that leads to Settings > Calendars, and turning calendars off in Settings does the same.
- Transcription: each window is cleaned before the model hears it (rumble filter and leveling of quiet voices), Whisper splits audio at pauses, and vocabulary spellings are given to the engine as hints. The recording itself is never changed.
- Network activity: the note now mentions the computer you paired, and the history can be cleared.
- AI models: a model with several files could report a failed install while it was actually fine, when two downloads finished at the same moment.
- CI: unit tests and UI tests run side by side, UI tests in four groups, with packages and build products cached. A failed job keeps its test results for a week.
- CI: pull requests answer in about 10 minutes. They run lint, unit tests, and a UI smoke set; documentation-only ones skip the macOS jobs. Every UI test still runs on `main` and every night. CI picks a simulator the machine has, the accessibility audit looks twice before it fails, and every UI test tap waits for its element. Pull requests never run every UI test.
- Contributors: `Config/Local.xcconfig` can set `APP_BUNDLE_IDENTIFIER`, so a fork can run on its own iPhone. The widget, App Group, test, and background task identifiers follow it.
