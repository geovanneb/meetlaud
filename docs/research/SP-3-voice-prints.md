# SP-3. Voice prints across recordings

**Status:** in progress. The pipeline works. Quality on real people is not measured yet.  
**Question:** do voice prints recognize a person across recordings?

## What was measured

The real Community-1 model, running in the iOS simulator on the CPU, on two meetings built from two synthetic macOS voices.

### Speaker separation

| Reference | Detected |
|---|---|
| Voice A, 0 to 10.5 s | S1, 0 to 10 s |
| Voice B, 11 to 20.3 s | S2, 10 to 20 s |
| Voice A, 20.8 to 30.8 s | S1, 20 to 30 s |
| Voice B, 31.3 to 40.7 s | S2, 31 to 40 s |
| Voice A, 41.2 to 49.6 s | S1, 41 to 49 s |

Two speakers found, and every turn attributed correctly.

### Recognition across recordings

Cosine similarity between each speaker in meeting 1 and each speaker in meeting 2, with different text in each.

| | Voice in meeting 2 | Other voice in meeting 2 |
|---|---|---|
| Voice A | 0.97 | 0.17 |
| Voice B | 0.97 | 0.17 |

## First real meeting: four people, one voice (November 2026)

A 2-minute recording on an iPhone 17 on a table, with four people talking, came out with one speaker holding 113 of 121 seconds. The diarizer itself returned one cluster: alignment and screens were not the cause.

The same file, run on a Mac with the same FluidAudio version (0.18.2) and the same model files, gives the same result. Changing only how the 24 kHz AAC file is decoded to 16 kHz changes the answer:

| Decoding | Speakers found |
|---|---|
| FluidAudio's own reader (what the app does) | 1 |
| `AVAudioConverter`, mastering quality | 1 |
| `AVAudioConverter`, normal quality | 3 |
| `afconvert` | 3 |

So the automatic count sits on a knife edge: differences far below hearing flip it between one voice and three. VBx with `Fa = 0.07` (the Community-1 default, tuned on long meetings with good microphones) leans hard toward fewer speakers on short, far-field audio.

Changing `Fa` on two real recordings:

| Setting | 2-minute meeting, 4 people | 9-minute meeting, 3 people |
|---|---|---|
| Default (`Fa` 0.07) | 1 to 3, depending on decoding | 3 |
| `Fa` 0.11 | 3 to 4 | 3 to 4 (a 5-second extra voice) |
| `Fa` 0.15 | 4 to 6 | 4 to 5 |
| Exact count of 4 | 4, with every decoding | |

No single `Fa` fixed both without adding voices that were not there, and two recordings are not a benchmark. What holds steady is a count the person knows. So (D-078):

- The person can separate voices again with a count, or let the model decide. The text stays as it is.
- With the automatic count, a voice heard for less than 2 seconds in the whole recording does not become a speaker. Its phrases go to whoever else spoke then.
- The default `Fa` is unchanged until more real meetings are measured.

## Trying more voices, and keeping only clearly different ones (November 2026)

A second real meeting, 2 minutes with three people (one reading an article aloud, two talking over it), also came out as one voice. Each meeting was then grouped again with a fixed count from 2 to 6, measuring how close the two closest voices were (cosine of each voice's blended print):

| Meeting | Truth | Automatic | Closest pair with 2, 3, 4, 5 voices |
|---|---|---|---|
| 2 min, people talking | 4 | 1 | 0.14, 0.12, 0.25, **0.85** |
| 9 min, Geovanne, Karen, and one short voice | 3, not confirmed | 3 | 0.27, 0.39, **0.77**, 0.78 |
| 2 min, reader and two people | 3 | 1 | **0.75**, 0.76, 0.94, 0.93 |

Lining the turns up with the transcript showed what the high scores were. In the 9-minute meeting, 4 voices split Karen in two: talking, and reading aloud (0.77). In the last meeting, the reader and one of the people scored 0.78, and 4 voices split the reader in two (0.94).

One person split in two scored 0.77 to 0.94. Different people scored 0.01 to 0.39, except one pair at 0.75 to 0.78. No bar can tell 0.77 (one person) from 0.78 (two people). A bar at 0.5 never splits a person and still recovers clearly different voices. So the engine now:

1. Finds the voices once. That is the slow part (0.6 s for 2 minutes on a Mac).
2. Groups them with the model's own count, then tries one more speaker at a time, up to 8, keeping each step while every pair of voices stays below 0.5. Each try takes about 0.03 s.

On these three meetings it gives 4, 3, and 1. The third needs the person to give the count, which "Detect again" offers.

## What this does not prove

- **Synthetic voices are the easy case.** They have no room noise, no distance from the microphone, no overlap, and no variation from day to day. Real scores will be lower, and possibly much lower.
- **Two voices are very different from each other.** The hard cases are similar voices, such as relatives or people with the same accent.
- **The thresholds are provisional.** They started at 0.75 (suggest) and 0.6 (uncertain), chosen by reasoning. On a real iPhone, with two saved people talking in the same meeting, only one of them was named, twice. They are now 0.6 and 0.45, with a lead of 0.08 over the next person (D-075). This is still a guess, now leaning on the lead instead of on a high score.
- **The two-voice test ran in the simulator.** On a real iPhone 17 the model downloaded, ran after a transcription, and labeled a one-voice clip. Speed and memory there are not measured yet.

## Design that follows from the risk

A wrong name in a meeting record is worse than no name.

- A match never appears as fact. It shows as "Suggested" until someone confirms it.
- Below the threshold, the transcript keeps "Speaker N".
- One person is never given to two speakers in a recording. Every speaker is scored against every person, and the closest pairs are settled first, so two voices never chase the same name while the second person goes unnamed.
- Embeddings are unit-normalized per turn before the centroid, and before blending into a saved print. FluidAudio returns raw vectors, and the old weighted sum grew with speech time.
- Confirming a suggestion teaches the voice print, weighted by speech time.
- A voice print needs at least 10 seconds of speech.
- Saving one requires consent every time, because it is biometric data.
- Deleting a person removes the voice print for good. Names in past transcripts stay.

## To finish this spike

Record 10 people, twice each, on different days, in a real room. Measure the equal error rate, then set both thresholds from the data.
