# Generated-speech transcription benchmark

Run on 2026-11-13 using `make eval-transcription`, Whisper Small from the app's
SHA-256-verified catalog, macOS system voices, and the app's actual audio reader,
speech conditioner, Whisper adapter, and text cleanup. Inference ran under
`sandbox-exec` with network operations denied. This is a Mac benchmark, not an
iPhone speed or battery claim. UI tests were also running, so timings are indicative.

| Fixture | Audio | Error rate | Real-time factor | Windows |
|---|---:|---:|---:|---:|
| en | 24.7 s | 4.0% WER | 0.061 | 1 |
| pt | 33.5 s | 5.0% WER | 0.056 | 1 |
| es | 24.5 s | 2.5% WER | 0.080 | 1 |
| ja | 34.6 s | 5.0% CER | 0.059 | 1 |
| en-quiet | 24.7 s | 4.0% WER | 0.058 | 1 |
| en-long | 360.0 s | 4.0% WER | 0.047 | 3 |
| silence | 10.0 s | 0 invented words | 0.025 | 1 |

Every fixture was read through its final audio window. The long fixture repeats the
English script fourteen times with pauses, reaching three windows. This checks window
continuity, not the linguistic diversity of a real long meeting. Quiet English uses
8% of the original amplitude plus deterministic low-level noise; it is not room noise.

The four-language scripts are fictional and defined in
[generate.py](../TranscriptionEval/generate.py). English uses Samantha, Portuguese
Luciana, Spanish Mónica, and Japanese Kyoko. Voice names are validated because macOS
can fall back to a different-language voice when a requested name is misspelled.

## Whisper Turbo, and the path the app takes

Run the same day with `make eval-transcription ASR_EVAL_MODEL=whisper-turbo`, after the two fixes below.

| Fixture | Error rate | Real-time factor | Windows |
|---|---:|---:|---:|
| en | 4.0% WER | 0.074 | 1 |
| pt | 3.8% WER | 0.066 | 1 |
| es | 2.5% WER | 0.088 | 1 |
| ja | 3.1% CER | 0.074 | 1 |
| en-quiet | 4.0% WER | 0.069 | 1 |
| en-long | 4.1% WER | 0.052 | 3 |
| en-long-app | 4.1% WER | 0.046 | 3 |
| silence | 0 invented words | 0.001 | 1 |

`en-long-app` runs the way the app runs by default: the first window detects the language, the windows after it
are told, and vocabulary spellings go along as hints. The other fixtures name the language and give no hints,
which is why they did not catch the following bug.

- **Hints emptied the transcript.** With a vocabulary, every window after the first came back with no text and
  no error, and the transcript was marked as done with only its first three minutes. WhisperKit 0.18 stops a
  piece when the model predicts "end of text" while the prompt is still being fed in (fixed upstream in 1.1,
  argmax-oss-swift #514). Before the fix, a 400-second clip gave 2,164 characters with hints and about 5,000
  without. The engine no longer sends a prompt; spellings are corrected in the text.
- **Silence became "Thank you."** Turbo wrote two words for ten seconds of digital silence. A piece with no
  signal above −60 dBFS is now skipped. Room noise is above that level and still goes to the model.

## What the score means

WER uses case/punctuation-normalized word edit distance. Japanese uses character edit
distance. Number spellings and digits are deliberately different: English's “eight
thousand dollars” became “$8,000”, and Spanish's “ocho mil” became “8000”. Those account
for the errors in the clean English and Spanish clips, although their numerical
meaning is preserved. Do not subtract such differences without inspecting the text.

Portuguese still misrecognized part of the final instruction. Japanese still confused
some terms, including the delivery-date phrase. These are real model errors, not
formatting differences. The benchmark does not justify calling transcription fully
accurate, especially for names, dates, technical vocabulary, or noisy human speech.

The initial silence case emitted `[BLANK_AUDIO]`. Cleanup now discards that exact
standalone model annotation, with regression coverage; it retains text that merely
mentions the annotation. This does not solve arbitrary hallucinations on room noise.

No audio or personal data is checked in. Reproduce the generated files and inspect
`build/transcription-eval/results.json`. The runner excludes model-load time from its
inference timing and does not evaluate diarization, summaries, or interruption recovery.
