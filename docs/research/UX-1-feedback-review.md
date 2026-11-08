# UX-1. Feedback and progress review

**Status:** first pass done (November 2026). The feedback components exist and cover transcription, speakers, storage, model downloads, summaries, and search indexing. The rest of the screens are listed with what to do next.
**Question:** does every screen tell the person what the app is doing, and does it do so with the same components everywhere?

## Why this matters

The owner tested a real recording and could not tell, after pressing stop, whether the app was transcribing, thinking, or stuck. Folders opened with no motion. Settings showed sizes and downloads as plain lines of text. The app is meant to stay minimal, but minimal is not the same as silent.

## What the literature says

| Source | Finding | What it means here |
|---|---|---|
| Nielsen, *10 Usability Heuristics* (1994), heuristic 1 "Visibility of system status" | The system should always keep users informed about what is going on, through appropriate feedback within reasonable time | Every long job needs a visible state, on the screen the person is looking at |
| Miller (1968); Nielsen, *Usability Engineering* (1993), [Response Time Limits](https://www.nngroup.com/articles/response-times-3-important-limits/) | 0.1 s feels instant. 1 s keeps the flow of thought. Past 10 s, show a percent-done indicator and a clear way to stop | Transcription and speaker separation take minutes: they need progress, elapsed time, and Cancel |
| Myers, "The Importance of Percent-Done Progress Indicators" (CHI 1985), [paper](https://www.researchgate.net/publication/234791131_The_importance_of_percent-done_progress_indicators_for_computer-human_interfaces), [CMU](https://hcii.cmu.edu/news/nyt-highlights-myers-role-popularizing-progress-bars) | 86% of participants preferred having a progress bar, even when it did not make the task faster | A bar is worth adding even when the work itself does not change |
| Harrison, Yeo, Hudson, "Faster Progress Bars" (CHI 2010), [project page](https://www.figlab.com/research/2010/faster-progress-bars) | How a bar moves changes how long the wait feels. A bar with backward-moving ripples felt about 10% faster | Motion inside a bar is not decoration. A bar that stands still feels longer and reads as frozen |
| Maister, "The Psychology of Waiting Lines" (1985), [article](https://davidmaister.com/blog/201/The-Psychology-of-Waiting-Lines.html) | Uncertain waits feel longer than known ones. Unexplained waits feel longer than explained ones | Name each step, say why the app waits (heat, charger, queue), and give time left once it can be measured |
| Norman, *The Design of Everyday Things* (1988, 2013) | The gulf of evaluation: people must be able to see the state of the system and judge whether their action worked | A tap on "Detect again" or "Transcribe" must change something on screen at once |
| Baecker and Small, "Animation at the Interface" (1990); Chang and Ungar, "Animation: From Cartoons to the User Interface" (UIST 1993), [paper](https://www.researchgate.net/publication/213800371_Animation_From_Cartoons_to_the_User_Interface) | Animation keeps objects consistent through a change, so people do not have to work out what happened | Folders that open with motion show where the new rows came from |
| Heer and Robertson, "Animated Transitions in Statistical Data Graphics" (InfoVis 2007), [paper](https://idl.uw.edu/papers/animated-transitions) | Controlled experiments: animated transitions improve perception of what changed. Keep them as long as needed and no longer | Bars and rings animate between values, in about 0.3 s |
| Tversky, Morrison, Bétrancourt, "Animation: Can It Facilitate?" (2002), [paper](https://www.researchgate.net/publication/222528842_Animation_Can_it_facilitate) | Animation helps only when it matches what it shows. Gratuitous motion can hurt | Motion only for state: progress, entering, leaving, opening. Nothing that moves for its own sake |
| Apple, Human Interface Guidelines: [Progress indicators](https://developers.apple.com/design/human-interface-guidelines/components/status/progress-indicators/) and [Motion](https://developer-mdn.apple.com/design/human-interface-guidelines/foundations/motion) | Switch from indeterminate to determinate once the duration is known. Use motion to keep people oriented and to give feedback. With Reduce Motion on, minimize or remove it | The same component goes from a sweep to a fill. Every movement has a Reduce Motion form |
| Apple, [Reduced Motion evaluation criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/reduced-motion-evaluation-criteria) | Spinning and large movement must change when Reduce Motion is on | Rings and sweeps become a gentle opacity pulse |
| Apple, WWDC 2018 "Designing Fluid Interfaces" | Fluid interfaces respond at once, and can be interrupted and redirected | Cancel is always one tap away while work runs |
| NN/g, [The Role of Animation and Motion in UX](https://www.nngroup.com/topic/animation/) | Animation must be unobtrusive, brief, and subtle, and used for feedback and state change | Short durations from `Motion`, no bounce |
| Viget, "A Bone to Pick with Skeleton Screens" (2017), [study](https://www.viget.com/articles/a-bone-to-pick-with-skeleton-screens) | In a test with 136 people, skeleton screens felt slower than a spinner or a blank screen | No skeleton screens. A real indicator in the place the content will appear |

Secondary sources repeat claims such as "skeletons cut perceived wait by 30%" or exact productivity losses per second of delay. They could not be traced to a primary study, so they are not used here.

## Rules that follow

1. **Never a bar standing still.** A known fraction fills. An unknown one keeps moving. A bar stuck at 0% or 100% reads as frozen, which is what the owner saw.
2. **Name the steps.** Long work shows its steps, the current one turning, done ones checked (Maister: explained waits).
3. **Show time passing.** Elapsed time ticks every second. Time left appears only once at least 5% is done and 5 seconds have passed, from this run's own speed. A wrong promise is worse than none.
4. **Say why it waits.** Queue, heat, and charger each get a symbol, a color that is not red, and one line on what happens next.
5. **Feedback where the person is.** After recording, the detail screen opens on Summary. The work shows there, not only on another tab.
6. **Same component, same meaning.** A ring means "working on this item". A bar means "how far along". A badge means "the state of this item in a list".
7. **Motion for state only**, from `Motion`, and every movement has a Reduce Motion form. State is never told by motion or color alone.

## The components

All in `DesignSystem/Feedback.swift`. Text comes from the caller, since `DesignSystem` has no strings.

| Component | Use | Reduce Motion |
|---|---|---|
| `ActivityBar(fraction:)` | How far along. Nil fraction sweeps | Opacity pulse |
| `ProgressRing(fraction:)` | Small inline "working". Nil fraction spins | Opacity pulse |
| `StepList` | Steps of a long job: waiting, active, done | Steps change without movement |
| `StatusBadge` | A list row's state: working with a ring, waiting or attention with a symbol | Ring pulses |
| `UsageBar` and `UsageDot` | Parts of a whole, as in iPhone Storage | Values change without sliding |
| `.dsCard()` | A raised group for status and summaries | None needed |

New tokens: `dsPositive` (done), `dsAttention` (needs the person, not an error), `dsTrack` (empty part of a bar), and `dsSeries` (five colors for parts of a whole, red left out because it belongs to recording).

`TranscriptionStatusCard` in `FeatureShared` puts them together for transcription, and is used on both the Summary and Transcript tabs.

## Screen by screen

Status: **Done** in this pass, **Next** for the following pass, **OK** where nothing needs to change.

### After recording, on the detail screen: Done

- *Before:* Summary, where the person lands, said "Needs a transcript" with a button, even while transcription ran. Transcript showed a system bar that stayed at 0% while the model loaded (which can take over a minute the first time), jumped to 100% in one step on a short recording because progress moves only per 3-minute window, and stayed at 100% while voices were separated.
- *Now:* one card on both tabs, with three named steps, a bar that sweeps while the fraction means nothing and fills while text is written, elapsed time, time left once measurable, one line on what is happening, and Cancel.

### Speakers: Done

- *Before:* with one voice found, the section disappeared, so a wrong count could not be fixed.
- *Now:* "One voice found · Wrong number of people? Detect again". With more voices, the same action sits under the list. The person picks a count or lets the model decide. While it runs, the section shows a turning ring and what is happening. See D-078 and SP-3.

### Home and Library rows: Done

- *Before:* status was a word at the end of the meta line, and Library showed no status at all.
- *Now:* both show a `StatusBadge`: a ring filling with the percentage, or a symbol for queued, hot, or waiting for a charger.

### Library folders: Done

- *Before:* `DisclosureGroup` in a list opened with no animation, because the change was not animated where it happened.
- *Now:* folders and the Speakers section open and close with `Motion.standard`, and `Motion.reduced` with Reduce Motion.

### Settings, Storage & backup: Done

- *Before:* four lines of text, and a bare spinner while measuring.
- *Now:* "1.6 GB used by the app" over one bar split by recordings, models, transcripts, and cache, next to the space still free on the device, with a legend. Measuring shows a sweeping bar in the same place, so the page does not jump. Export and import progress shows a bar with a percentage.

### Settings, AI models, Storage: Done

- A bar of what each model takes, with a matching dot on each row, so the heaviest model is visible before reading.

### AI model downloads: Done

- *Before:* a bar while downloading, and nothing visual for queued, verifying, preparing, or testing, which can take minutes.
- *Now:* every step between asking and having a model shows a ring and a bar that sweeps when there is no fraction.

### Summaries in progress: Done

- *Before:* a system bar, and a borderless Cancel styled unlike every other Cancel.
- *Now:* the same card, bar, badge, and secondary Cancel as transcription.

### Ask, search indexing: Done

- Uses `ActivityBar`, so it matches the rest.

### Ask, chat: OK

- A native spinner with a status line, then the answer streams in. This is the right pattern for waits of a few seconds.

### Recording screen: OK, one Next

- Large timer, live waveform, markers that slide in, symbols that swap with `.symbolEffect(.replace)`. It already communicates well.
- *Next:* a short confirmation when a moment, note, or photo is added (a brief highlight of the new row), so the action is acknowledged without looking down for long.

### Home empty state and calendar: OK

- The empty state and the calendar's expanding month already animate and respect Reduce Motion.

### People: Next

- Rows are a name and a footer. Next: show how many meetings each person appears in and whether a voice print exists, as a small badge, so the screen explains why a name is suggested.

### Privacy & security, erase everything: Next

- A bare spinner during erase. Next: steps ("Deleting meetings", "Removing models", "Resetting settings") with `StepList`, since erasing a large library takes a while and must be seen to finish.

### Network activity: Next

- A list of text rows. Next: a total at the top (bytes received, per model), using the same heading and `UsageBar` as Storage.

### Tools and templates: Next

- Not reviewed in depth in this pass.

## How it was checked

- Unit tests for the new rules: time left, measurable phases, speaker count, short voices, repeats (`DomainTests`).
- A UI test runs a slow fake transcription and checks the card, its steps, and elapsed time (`ModelsTests.testATranscriptionShowsItsStepsWhileItRuns`), with screenshots kept in the result bundle.
- A UI test checks the storage bar (`SystemTests.testStorageShowsWhatTakesSpaceAsOneBar`).
- The existing accessibility audits run over the changed screens.
- Still to do by hand: a VoiceOver pass over the card and the badges, and a Reduce Motion pass on a device.
