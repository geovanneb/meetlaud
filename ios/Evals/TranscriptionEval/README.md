# Offline transcription evaluation

Run `make eval-transcription` on an Apple silicon Mac with Xcode 26 and the Samantha,
Luciana, Mónica, and Kyoko system voices installed. No microphone or personal recordings
are used. This is a synthetic regression benchmark, not a claim about real meetings.

The explicit setup downloads the catalog-pinned Whisper Small model (about 220 MB),
checks every SHA-256, and resolves the same dependencies as the app. Inference then
runs under a macOS sandbox denying network operations. No new runtime dependency is
added to the app. Source links compile the app's real Domain, AudioEditing, and
ASRWhisperKit code, including speech conditioning, windowing, and repeat cleanup.

`generate.py` uses macOS `say` to create four fictional meeting scripts and audio in
English, Portuguese, Spanish, and Japanese. Additional English cases lower the volume
with deterministic noise, repeat the meeting across multiple three-minute windows,
and provide ten seconds of silence. Generated audio, text, build products, and raw
results stay under the ignored `build/transcription-eval` folder.

`score.py` measures case/punctuation-normalized word error rate (WER), or character
error rate (CER) for Japanese, using edit distance. It deliberately does not equate
written numbers with digits, remove stop words, or suppress insertions. Silence reports
hallucinated words instead of dividing by zero. Timing excludes model preparation and
includes window reading, conditioning, inference, and cleanup; real-time factor (RTF)
is elapsed seconds divided by audio seconds. Coverage means every audio window was
read, not that every spoken word was transcribed correctly.

Inspect `results.json` alongside the scores, especially negations, money, dates, and
actions. Timing is Mac-specific and includes contention from other running work.
System voice versions can change results. This benchmark does not establish iPhone
battery life, interruption recovery, speaker separation, or robustness to overlapping
human speech and room acoustics. Those remain separate real-device acceptance tests.

Run scorer regressions with `python3 -m unittest discover -s Evals/TranscriptionEval -p 'test_*.py'`.

To compare the catalog's larger Whisper Turbo model (about 648 MB), use a separate
directory so model files and results cannot be confused with Small:

```sh
make eval-transcription ASR_EVAL_MODEL=whisper-turbo ASR_EVAL_DIR="$PWD/build/transcription-eval-turbo"
```
