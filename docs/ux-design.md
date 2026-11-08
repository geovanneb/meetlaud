# Information architecture, navigation, and UX

## Mental model

The user thinks about one thing: **the meeting**. Everything revolves around the recording.

```
Recording
├── Audio + markers, notes, and photos
├── Transcript + speakers
├── Summaries (one per template)
└── Conversations
```

The other objects serve that center: **People** (voice prints), **Templates**, **Folders**, and **Models**.

## Navigation structure

Decision [D-001](decisions.md): a side menu on iPhone, a native sidebar on iPad.

```
Side menu
├── Home
│   ├── Upcoming ─ Calendar view
│   ├── Meeting notes ─ Recording detail
│   └── Prompt bar ─ Chat
├── Library
│   ├── My files ─ Folders ─ Recording detail
│   ├── Search
│   └── ⋯ Select, Sort by, Trash
├── Ask Meetlaud
│   ├── New chat
│   └── History
├── Tools
│   └── Skills, Templates, Connectors
├── ──────────
├── Settings
│   ├── Workspace: Personalization, Preferences, AI models, People, Storage & backup
│   ├── General: Notifications, Theme, Language
│   ├── Privacy: Privacy & security, Network activity
│   └── Help: Help center, Share ideas, About, Licenses
└── Help center

Always reachable
├── Record (top of Home, Action Button, Control Center, widget)
├── Active recording pill (above the prompt bar, on every screen)
└── Search (top of the side menu)
```

### Two deliberate choices

1. **`Record` is the main action.** There is no hardware to pair, so recording takes the top-right place, next to `+` for importing.
2. **People and AI models live in Settings.** They are set up once and rarely changed.

### Side menu implementation

iOS has no native drawer for iPhone, so this is a custom component (`DrawerContainer`) with these rules:

- Opens through the button and an edge gesture, active only at the root, so it does not conflict with `NavigationStack` back swipe.
- VoiceOver: focus is trapped in the menu, and the escape gesture closes it.
- Motion, tuned frame by frame: the page slides 76% of the width in about 0.2 seconds, with no bounce, and fades back by 43%. The menu does not move. It grows from 97% to 100% and fades in from 60%.
- Reduce Motion: slide becomes fade.
- On iPad at regular width, it uses a native `NavigationSplitView` with the same items. In a narrow Split View, it falls back to the drawer.
- Content keeps its state when switching destinations: each destination has its own `NavigationStack`.

### Routes and deep links

All navigation goes through an `AppRouter` with a typed `AppRoute`. This unifies taps, widgets, Shortcuts, and notifications.

```
meetlaud://record
meetlaud://recording/{id}?t=125.4
meetlaud://ask?recording={id}
meetlaud://settings/models
```

## Main screens

### Home

```
┌───────────────────────────────┐
│ ☰              ⏺ Record    +  │
│ Upcoming        Calendar view │
│ ┌───────────────────────────┐ │
│ │ 14:00 Quarterly review   ⏺│ │
│ └───────────────────────────┘ │
│ Meeting notes              ↕  │
│ Sales meeting                 │
│ Today 10:49 · 32 min · Summary│
│ Product memo                  │
│ Yesterday · 2 min · Transcribing│
│                               │
│ ╭ ● 12:04 Recording       ⏸ ╮ │
│ ╭ Ask me anything…        ☑ ╮ │
└───────────────────────────────┘
```

- Each row shows a clear state: Not transcribed, Queued, Transcribing 42%, Ready.
- Empty state: "Start by recording or importing audio".
- Without calendar permission, the card with `Connect` appears. No screen blocks because of it.

### Recording screen

```
┌───────────────────────────────┐
│ ⌄ Minimize         New meeting│
│                               │
│           00:12:04            │
│     ▁▂▅▇▅▃▂▅▇▆▃▁▂▅▇▅▃▂        │
│                               │
│ 03:12 ⚑ Pricing decision      │
│ 07:40 📷 Whiteboard           │
│ 11:02 ✎ Call legal            │
│                               │
│     ⚑        📷        ✎      │
│         ⏸        ⏹            │
└───────────────────────────────┘
```

- Everything is one tap with large targets, usable without looking.
- Minimizing interrupts nothing: it becomes a pill on every screen.
- Stop asks for confirmation only if the recording is under 2 seconds.
- After stopping, the detail screen opens. Based on the preference, it offers "Transcribe now".

### Recording detail

```
┌───────────────────────────────┐
│ ‹                          ⋯  │
│ Sales meeting                 │
│ Today 10:49 · 32 min · 3 people│
│ [ Summary ][ Transcript ][ Notes ] + │
│                               │
│ Ana  00:12                    │
│ Let's start with pricing…     │
│ Bruno  00:31                  │
│ Agreed, but the deadline… ◀ active │
│                               │
│ ─●───⚑─────⚑────────── 12:04  │
│ 1x   ↺15     ▶     30↻        │
│ ╭ Ask about this meeting    ╮ │
└───────────────────────────────┘
```

- **Tapping a phrase jumps to the audio** and starts playing. The active phrase is highlighted and scrolling follows it.
- Scrolling manually releases the follow mode, and a "Back to current" button appears.
- Tapping a name offers: rename, pick a saved person, apply to all lines or just this one.
- Long press on a phrase: edit, copy, mark, ask about this.
- `+` creates another summary in a new tab.
- **Speakers** sits at the top of the Summary tab once two or more speakers are found. Closed, it is one line: "Ana 62% · Bruno 38%". Open, each person has a row with their share, a bar, time spoken, turns, and longest turn. Tapping a row opens the same sheet as a name in the transcript, to rename or confirm. It stays closed or open as the person left it. Numbers follow the transcript, so corrections count (D-074).
- `⋯`: Name speakers, Find & Replace, Rename, Move, Merge, Export, Trash.

### Model missing?

This is never an error. If the user asks to transcribe without a model:

1. If Apple supports the language, offer system transcription, which needs no in-app download.
2. Open a sheet with the recommendation for that role, based on the device: "Recommended for your iPhone: Whisper turbo, 626 MB".
3. Show the size, wait for Wi-Fi by default, and download in the background.
4. When finished, the work starts by itself.

The full model experience is specified in [Model management](model-management.md).

### Library

Title, search, and `⋯`, then `My files ⌄` with `+` for a new folder, and expandable rows.

### Tools

A segmented control switches between Skills, Templates, and Connectors. Templates shows My templates, then a category filter, then sections by category with horizontal cards. `+` opens Create template with AI and Create template manually.

### Calendar view

The title opens the week into the month, with a row of months below it, and the chosen day's meetings and recordings are listed in time order. Today returns to today. Swiping moves by a week or a month.

### Settings

In this order:

```
Workspace   Personalization · Preferences · AI models · People · Storage & backup
General     Notifications · Theme · Language
Privacy     Privacy & security · Network activity
Help        Help center · Share ideas · About Meetlaud · Licenses
```

- **AI models** is the new centerpiece. It shows the device status and one model per function (Transcription, Speaker separation, Voice print, Chat & summary, Search), with speed test, download, pause, delete, storage, and continuous recommendations. See [Model management](model-management.md).
- **Storage & backup** replaces Private Cloud Sync: usage by type, clear cache, iOS backup (off by default, with an explanation), encrypted export.
- **Network activity** lists each download and each delivery to a paired computer, with date and destination. It proves the promise. "Clear History" empties it after a confirmation, and the empty screen then says the history was cleared.

## Onboarding

Short and skippable. It only asks for what it needs, at the right moment.

1. **Promise:** "Your meetings stay on your iPhone." No accounts.
2. **Microphone:** explanation, then the system prompt.
3. **Models:** one recommended setup for the device, with total size. "Download all", "Customize", or "Not now". The app is usable right after this step.
4. Done: Home with a sample recording in **Welcome to Meetlaud**, already transcribed and summarized, to show value with no download.

Calendar, notification, and camera permissions are requested only on first use.

## System surfaces

| Surface | What it does | Priority |
|---|---|---|
| Live Activity and Dynamic Island | Time, pause, stop, mark | Essential |
| Control Center and Lock Screen control | Opens the app and records | Essential |
| Action Button | Records with one press | Essential |
| App Intents and Siri | Record, stop, mark, "last meeting" | Essential |
| Small Home widget | Record and time | High |
| Medium Home widget | Next event and recent meetings | High |
| Lock Screen widget | One-tap record | High |
| Open in Meetlaud | Import audio from other apps, through the share sheet | High |
| Spotlight | Search meetings, opt-in | Medium |
| Local notifications | Transcript ready, event reminder | Medium |
| Apple Watch | Remote control | After 1.0 |

When opened from a control or widget, the app starts recording in the foreground and the user can leave right after. Apple requires the session to start with the app in the foreground.

## iPad

- Three-column `NavigationSplitView` in the Library: menu, list, detail.
- In the detail screen, Transcript and Summary side by side at wide widths.
- Keyboard: `⌘N` record, `⌘F` search, space to play, `⌘K` Ask.
- Stage Manager and Split View with no broken state.

## Visual principles

What matters: near-white background, strong typography, lots of space, discreet gray, one action blue. On iOS 26, floating round buttons are exactly what Liquid Glass delivers natively.

- System typography (SF Pro, Hiragino for Japanese) with full Dynamic Type.
- Color only with a purpose: red to record, blue for actions.
- SF Symbols everywhere.
- Light, Dark, and System.
- Light haptics on record, stop, and mark.
- Every screen has states: empty, loading, error, no permission, no model.

### Feedback

Anything that takes longer than a moment uses the feedback components in `DesignSystem` (D-079): a bar that fills or keeps moving, named steps, elapsed time, and a badge in list rows. The research and the screen-by-screen review are in [UX-1](research/UX-1-feedback-review.md).

### Design tokens

`DesignSystem` owns these, and `make lint` rejects anything else in a feature.

| Level | Token | Used for |
|---|---|---|
| Display | `dsDisplay` | The recording timer |
| Page title | `dsPageTitle` | A meeting's title, "My files", the title of a choice sheet |
| Section title | `dsSectionTitle` | Empty states, locked screen |
| Heading | `dsHeading` | Inside a card or a document |
| Row title | `dsRowTitle` | The main line of a row, and running text |
| Meta | `dsMeta` | The line under a row's title, and status |
| Note | `dsNote` | Hints and explanations |
| Timestamp | `dsTimestamp` | Any moment in the audio |
| Badge | `dsBadge` | A tag next to a title |

- Buttons: `primaryAction()` for the one main action, `secondaryAction()` for the rest, and plain text for a minor action. Size comes from the control size, never from a frame on the label.
- A setting with a few values opens `ChoiceSheet` from the bottom, as in the Theme reference.
- Timing: `Motion.quick` inside a control, `Motion.standard` for something entering or leaving, and `Motion.drawer` for the side menu. All of them respect Reduce Motion.

## Accessibility and languages

- Full VoiceOver, including the transcript (each phrase is an element with speaker and time) and the waveform (text summary).
- Dynamic Type up to accessibility sizes.
- Contrast, Reduce Motion, Reduce Transparency.
- String Catalog with en (fallback), ja, pt-BR, and es.
- Japanese is the hardest test: no italics, correct line breaking, and different text lengths.
- Dates and durations always use `FormatStyle`.
- The app language is independent of the meeting language. The summary uses the chosen language, defaulting to the spoken language.
