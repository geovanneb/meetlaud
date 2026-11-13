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
- A template library you can browse: categories at the top, a row of cards per category, and a page with every template in a category.
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
- Transcription: a meeting no longer keeps only its first three minutes when the vocabulary has entries. The spellings were given to Whisper as a prompt, and the Whisper library returns no text, and no error, for audio that has a prompt. Only the first window runs without one, so only that window had text, and the transcript was still marked as done. The prompt is no longer sent; spellings are corrected in the text, as before.
- Transcription: audio with no signal at all, such as a muted microphone, is skipped instead of being given to Whisper, which answered silence with "Thank you."
- Calendar: the month strip no longer slides when Reduce Motion is on.
- Tabs: the segmented tabs in Tools, in a recording, and in AI models can be dragged from one tab to the next, like everywhere else in iOS. The side menu watched every sideways drag and took the touch away, so the tabs only answered taps. A recording's page had a second gesture that did the same.
- Templates: typing a section title no longer closes the keyboard after the first letter. While Save is off, a note under the sections says what is missing: a name, and a title for every section.
- Offline quality: long transcripts avoid repeated row scans during playback, canceled searches cannot replace newer results, and repeat cleanup preserves words that begin with a repeated phrase. Ask and Memory empty states scroll with their lists. Exports have independent temporary files and offer a retry on failure. Backup restore rejects malformed stream endings and duplicate paths before changing the library. A generated-speech evaluation measures the real offline transcription pipeline in four languages.
- Ask about this meeting: broad questions like "What was the main topic?" now get an answer on long meetings. The chat reads the meeting's summary along with the passages it finds, and answers the part it can instead of saying it found nothing.
- Ask: answers no longer appear and then turn into "I could not find that". The chat model now reads the meeting's summary first and the transcript as a few passages instead of one numbered line per phrase, which made it skip its sources or recite them after answering. If it starts reciting anyway, the answer ends there. An answer is kept when the model only says it cannot answer part of the question, and earlier refusals no longer steer the next answer. The scope menu keeps the meeting a chat was opened from, and changing scope starts a new chat so that answers from another scope are not mixed in.
- Summaries: a summary in another language now comes out in that language. Asking for Japanese about a Portuguese meeting used to give mostly Portuguese, copied line by line. The model now writes the summary in the language that was spoken, then translates it, keeping names, amounts, and links to the audio. Each section is told what belongs in it, so "Open questions" lists the questions left unanswered instead of repeating the decisions. Lines copied from the transcript as "Name: ...", the example task from the prompt, and lines stuck in a loop no longer reach the summary. `make eval-summary` runs every template in every language on a Mac with the real model.
- Work in progress is always visible: after recording, the Summary and Transcript tabs show the steps of the transcription, a bar that keeps moving while the model loads, elapsed time, and time left once it can be measured. Home and Library rows show the same state as a badge.
- Speakers: when the app finds too few voices, "Detect again" lets you say how many people spoke. A voice heard for less than 2 seconds no longer becomes a speaker.
- Speakers: the automatic count now finds people whose voices are clearly different even when the model first merges them. Four people at a table were found as one before.
- The recording pill reacts to the finger and can be tapped anywhere on it, not only on its text line.
- Transcripts: a phrase the model repeats over and over is folded into one copy with "[×N]", and pieces with only punctuation are dropped.
- Storage & backup and AI model storage show space as one bar, next to what is free on the device. Model downloads show progress for every step, not only the download.
- AI models: after "Download all", the screen shows the download progress and the state of each function, instead of "Not installed". Each model counts only its own bytes, and pausing keeps what was received.
- Folders and the Speakers section open and close with motion, and with a fade when Reduce Motion is on.
- Folders in My files now really open and close with motion on iPhone: the side menu was cancelling it. Animations across the app are a little shorter, and My files sorts its list once per update instead of once per folder, so the app feels quicker.
- Home: with calendars off, "Calendars are off" now sits in a card like "See your meetings", and the whole card opens Settings > Calendars.
- Fewer missed taps: the player's back, play, and forward buttons, the Library selection bar, and search results now take taps across their full 44-point area, not only on the icon or text.
- Home: "No recordings yet" no longer covers the upcoming meetings. It now sits under Meeting notes.
- Speakers: two saved people in the same meeting are both recognized. Matching scores every voice against every person, and voice prints no longer depend on how long or loud each stretch was.
- Speakers: a "Speakers" section at the top of the Summary shows how much each person spoke, their turns, and their longest turn.
- Calendars: Settings lists every calendar on the device by account, and each can be turned off, so a personal calendar stays out of Upcoming, Calendar view, widgets, and reminders. Calendars can also be turned off altogether.
- Home: the "See your meetings" card can be closed. Upcoming then shows one line that leads to Settings > Calendars, and turning calendars off in Settings does the same.
- Transcription: the app no longer crashes, over and over, when iOS ends the background task that keeps a transcription going. This happened most after an update, while the model was being prepared again, and the system showed "Task failed" for each crash.
- Transcription: the system no longer shows "Task failed" while a transcription is still running in the background. iOS ends background work that stops reporting progress, and the app reported nothing while it prepared the model or separated voices. It now reports progress all the way through.
- Transcription: long meetings are transcribed to the end. The audio reader threw away every window that arrived while the model was still busy, so text stopped after the second window (about six minutes at most), and the transcript was still marked as done. It now reads the next window only when the model asks for it. A transcript is marked as done only when its text reaches the end of the audio.
- Transcription: a part of the audio that the engine fails on is never saved as silence. Whisper used to drop a failed 30-second piece without a word. Now the window is tried again with the model loaded again, and if it still fails, the job keeps its text, shows "Paused after a problem", and goes on when the app is opened. Whisper no longer uses the GPU at all, since iOS refuses GPU work from an app in the background.
- Transcription: progress moves during each window instead of once every three minutes, and the screen leaves "Preparing" as soon as the model is ready. The note while preparing says that after an install or update this can take a few minutes, and to keep the app open: leaving during that step could get the app closed by iOS for memory.
- Transcription: each window is cleaned before the model hears it (rumble filter and leveling of quiet voices), Whisper splits audio at pauses, and vocabulary spellings are given to the engine as hints. The recording itself is never changed.
- Network activity: the note now mentions the computer you paired, and the history can be cleared.
- AI models: a model with several files could report a failed install while it was actually fine, when two downloads finished at the same moment.
- CI: unit tests and UI tests run side by side, UI tests in four groups, with packages and build products cached. A failed job keeps its test results for a week.
- CI: pull requests answer in about 10 minutes. They run lint, unit tests, and a UI smoke set; documentation-only ones skip the macOS jobs. Every UI test still runs on `main` and every night. CI picks a simulator the machine has, the accessibility audit looks twice before it fails, and every UI test tap waits for its element. Pull requests never run every UI test.
- Contributors: `Config/Local.xcconfig` can set `APP_BUNDLE_IDENTIFIER`, so a fork can run on its own iPhone. The widget, App Group, test, and background task identifiers follow it.
