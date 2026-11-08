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
