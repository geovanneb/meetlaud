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
- Home: "No recordings yet" no longer covers the upcoming meetings. It now sits under Meeting notes.
- Speakers: two saved people in the same meeting are both recognized. Matching scores every voice against every person, and voice prints no longer depend on how long or loud each stretch was.
- Speakers: a "Speakers" section at the top of the Summary shows how much each person spoke, their turns, and their longest turn.
- Transcription: each window is cleaned before the model hears it (rumble filter and leveling of quiet voices), Whisper splits audio at pauses, and vocabulary spellings are given to the engine as hints. The recording itself is never changed.
- Network activity: the note now mentions the computer you paired, and the history can be cleared.
- AI models: a model with several files could report a failed install while it was actually fine, when two downloads finished at the same moment.
- CI: unit tests and UI tests run side by side, UI tests in three groups, with packages and build products cached. A failed job keeps its test results for a week.
