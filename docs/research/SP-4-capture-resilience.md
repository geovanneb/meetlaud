# SP-4. Capture resilience

**Status:** in progress. Automated results are in. Manual scenarios need a person with the phone.  
**Device:** iPhone 17, iOS 26.6.2  
**Question:** do capture and storage survive background, lock, calls, and crashes?

## Results so far

| Scenario | How | Result |
|---|---|---|
| Format survives SIGKILL | Mac probe with CAF, WAV, and M4A | Only PCM in CAF survived. See below |
| Raw segments survive an abandoned writer | Unit test | Passed |
| Real recording, stop, save, play | Test on iPhone | Passed |
| Process killed mid-recording, audio recovered on next launch | Test on iPhone | Passed |
| 45 seconds in the background, audio keeps flowing | Test on iPhone | Passed |
| Interruption logic, including failed resume | Unit tests with fake engine | Passed |
| Critical storage stops and saves | Unit test | Passed |

## Finding: compressed containers do not survive a crash

The plan proposed AAC in CAF. We tested it by writing 60 seconds of audio and sending SIGKILL with no close.

| Format | Bytes on disk | Result with `AVAudioFile` |
|---|---|---|
| PCM in CAF | 2.9 MB | **Readable: 60 seconds** |
| PCM in WAV | 2.9 MB | Opens, reports 0 seconds |
| AAC in CAF (the original plan) | 453 KB | Opens, reports 0 seconds |
| AAC in M4A | 470 KB | Could not be read |

**Correction:** the first run of this probe reported all four as unreadable. That was a bug in the probe: `AVAudioFile.read` throws at end of file, and the reader counted that as corruption, so PCM in CAF looked broken when it was fine. The decision below was first justified with that wrong claim. The table above is the corrected result. The AAC failures are real.

The bytes reached the disk in every case. What differs is how much depends on metadata finalized on close.

**Decision (D-028):** segments are raw 16-bit mono samples at 24 kHz, with no header. PCM in CAF would also work, but raw samples depend on no container behavior at all: file size is the length, and the format is a constant in the code. The M4A is created when recording ends, and segments are deleted only after it is saved.

**What this costs:** about 170 MB per hour of temporary disk space, plus encoding time when recording stops. A crash during encoding is safe, because the segments stay until the final file is in place.

**What it guarantees:**

- Process crash or force quit: nothing lost that reached `write()`.
- Sudden power loss: up to 5 seconds, the `fsync` interval.

## Finding: the 30-second suspension does not apply

A forum report described suspension after 30 seconds with the audio background mode. We measured 45 seconds in the background on a real device, with the recorded time advancing the whole way. Active capture with the mode enabled keeps running. The 3-hour run is still pending.

## Design notes confirmed by testing

- **Pause keeps the microphone open (D-029).** Samples are dropped, and the engine keeps running. If the engine stopped, iOS could suspend the app, and Resume from the Lock Screen might fail. The orange indicator stays on during a pause, and that is honest: the microphone is open, but nothing is stored.
- **The clock follows audio frames, not wall time.** The timer shows what was actually captured.

## Network silence of the engines

While Whisper and diarization ran on real models in the simulator, the test processes were watched from the Mac with `lsof`: 2 processes, 115 samples, about 3 minutes of inference, and 0 internet sockets. A positive control confirmed that the same method detects a real connection.

This is sampled every 1.5 seconds, so a very short connection could slip through, and it covers the engines, not the whole app. An airplane mode run on the iPhone is still pending, and only safe with a cable: the phone is connected over the local network, and turning networking off would strand it.

## Manual scenarios

Pending. Each needs a person, and answers a question that a test cannot.

| # | Scenario | What to check | Result |
|---|---|---|---|
| 1 | Record with the screen locked, 10 minutes | Time matches, audio plays | Pending |
| 2 | Lock Screen and Dynamic Island | Live Activity appears, timer runs | Pending |
| 3 | Pause, mark, stop from the Lock Screen | Each one works without opening the app | Pending |
| 4 | Incoming call, decline | Resumes alone | Pending |
| 5 | Incoming call, answer, hang up, **in background** | **Key question:** does it resume, or show Resume? | Pending |
| 6 | Siri, alarm, timer during recording | Audio kept, recording continues | Pending |
| 7 | Connect and remove AirPods during recording | No stop, no gap beyond a moment | Pending |
| 8 | Take a photo during recording | Audio continues behind the camera | Pending |
| 9 | Play a video in another app during recording | See how iOS arbitrates | Pending |
| 10 | Zoom or Meet on speaker on the same iPhone | Is it captured? | Pending |
| 11 | Record 3 hours | No loss, battery used | Pending |
| 12 | Power off during recording | Recovered on next launch | Pending |
| 13 | Playback on the Lock Screen | Controls work, audio continues | Pending |

Scenario 5 matters most. Apple's guidance suggests that a recording session cannot start from the background, and resuming after a call may count. If it fails, the app shows Resume on the Live Activity, and the design already covers that.
