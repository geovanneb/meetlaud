# On-device AI

Everything here is a **hypothesis until the spikes run on real devices**. The public numbers we found mostly come from Macs or blogs. There is almost no data for iPhones with long audio.

## Confidence legend

- **[V]** Verified by us during this research (local SDK, official model card, or official documentation)
- **[R]** Reported by third parties, not confirmed
- **[?]** To be measured

## Strategy: one engine per function, behind ports

| Function | Default | Alternatives |
|---|---|---|
| Transcription with no in-app download | Apple SpeechTranscriber | - |
| Widest-coverage transcription | Whisper large-v3-turbo (WhisperKit) | Whisper small on lower-memory devices |
| Fast transcription | Parakeet v3 (FluidAudio) | Parakeet Japanese for Japanese |
| VAD | Silero (FluidAudio) | - |
| Diarization | Pyannote community-1 (FluidAudio) | SpeakerKit, if the spike points that way |
| Voice print | WeSpeaker (FluidAudio) | - |
| Summary and chat with no download | Foundation Models | - |
| Quality summary and chat | Qwen 3.5 2B/4B or Gemma 4 E2B (MLX) | To be decided in SP-1 |
| Text embeddings | `NLContextualEmbedding`, for now ([SP-5](research/SP-5-embeddings.md)) | A small multilingual model, if real meetings need it |

## Transcription candidates

| Model | Languages | Size | License | Notes |
|---|---|---|---|---|
| Apple SpeechTranscriber | en, es, pt-BR, pt-PT, ja, among 30 locales **[V]** | System asset | System | No in-app download, iOS fetches it. List queried on macOS 26.6, confirm on iOS. Third-party benchmark shows good results on short audio **[R]** |
| Whisper large-v3-turbo | Multilingual | 626 MB **[R]** | MIT conversion **[V]** | Covers all four languages. Formal list to be confirmed |
| Whisper small | Multilingual | [?] | MIT conversion **[V]** | For lower-memory devices |
| Parakeet TDT v3 | 25 European languages, including en, es, pt **[V]** | ~494 MB **[R]** | CC-BY-4.0 **[V]**: requires attribution | Very fast. **No Japanese.** Trained on European Portuguese, as NVIDIA itself warns **[V]**. Needs evaluation on pt-BR |
| Parakeet TDT Japanese | Japanese | [?] | CC-BY-4.0 **[V]**: requires attribution | 6.85% CER on JSUT, measured on M2 **[R]** |

**Key point:** no model wins everywhere. The app picks per language, and this should be invisible to regular users: they choose **Fast, Balanced, or Maximum quality**. Details are available in Settings.

### Initial policy per language (to validate in SP-2)

| Language | Fast | Balanced | Maximum quality |
|---|---|---|---|
| en | Apple | Parakeet v3 | Whisper turbo |
| es | Apple | Parakeet v3 | Whisper turbo |
| pt-BR | Apple | Whisper turbo | Whisper turbo |
| ja | Apple | Parakeet JA | Whisper turbo |

### Long audio

Meetings run 1 to 3 hours. Every engine processes overlapping chunks, cut at silence by the VAD, with a checkpoint per chunk. This also reduces memory and allows resumption. Timestamps are composed at the end.

We found no long-audio benchmark for any engine. **Measuring this is one of the goals of SP-2.**

## Before the model hears the audio

Each transcription window is cleaned in memory first (`SpeechConditioner`, D-076). The file on disk stays as recorded.

- **High-pass at 80 Hz.** Removes rumble from air conditioning, traffic, and the phone touching the table.
- **Speech leveling.** Raises quiet speech toward -23 dBFS, by up to 18 dB, and leaves silence alone. A phone on a table hears the near person much louder than the far one, and Whisper scales each 30 seconds by its loudest moment, so the far voice gets lost.
- **Splitting at pauses.** WhisperKit cuts each window at silences into pieces of up to 30 seconds (VAD), two at a time. Long pieces with silence are where Whisper invents or repeats text.
- **Hints.** Vocabulary spellings go to the engine as a Whisper prompt or Apple contextual strings, up to 40 terms, and are still corrected afterwards.

Next, with its own decision: a neural noise suppressor (such as DeepFilterNet or RNNoise) as a downloadable model, for loud rooms.

## Diarization and voice prints

Pipeline: VAD, segmentation, embeddings, clustering, speech assignment.

- FluidAudio documents offline and streaming diarization and embedding extraction, with an Apache-2.0 package license **[V]**. The per-person enrollment API is still to be confirmed.
- SpeakerKit (Argmax) does not document embedding extraction. That is why we chose FluidAudio.
- **License:** the Community-1 artifacts in `speaker-diarization-coreml` are CC-BY-4.0, with attribution required **[V]**. The legacy `wespeaker` files are out of that scope. The catalog pins only Community-1 artifacts, and voice print uses its `Embedding.mlmodelc`. See [SP-6](research/SP-6-license-audit.md).

### Voice print

1. The user confirms that a person is "Ana".
2. We select clean speech with no overlap and compute the embedding centroid.
3. With consent, we save the vector, never the audio.
4. In new recordings, we compare by cosine similarity:
   - High confidence: apply the name, marked as "suggested".
   - Medium: ask.
   - Low: keep "Speaker 1".
5. Each confirmation improves the voice print.

**Caveats:** a voice print is biometric data under several laws (GDPR, LGPD, among others). The app shows a consent notice and allows deleting everything. Thresholds must be calibrated per model and language, with real false positive measurements in SP-3.

## LLM candidates

| Model | Size | License | Runtime | Speed (iPhone 17 Pro) |
|---|---|---|---|---|
| Foundation Models (Apple) | System | System | System | [?] |
| Qwen 3.5 2B 4-bit | [?] | Apache-2.0 **[V]** | MLX | 61 tok/s **[R]** |
| Qwen 3.5 4B 4-bit | [?] | Apache-2.0 **[V]** | MLX | [?] |
| Gemma 4 E2B | [?] | Apache-2.0 **[V]** | LiteRT-LM (55 tok/s **[R]**), MLX | To measure on MLX |

Cautions:

- `mlx-community` Gemma 4 conversions list `license:gemma`, while Google's original lists Apache-2.0 **[V]**. If SP-1 selects Gemma 4, we convert from Google's weights ourselves.
- LiteRT-LM would add a second runtime dependency. It is only worth it if the gain is very clear.
- No source tests Japanese quality. We will test it.

### Foundation Models

Advantages: no download, native, integrated with the system. Limits:

- Requires a device with Apple Intelligence turned on.
- Small context: 4,096 tokens on iOS 26 **[R]**, with 8,192 reported for iOS 27 **[R]**. We read `contextSize` at runtime (the API exists in the iOS 26.5 SDK **[V]**) instead of hardcoding a value.
- Needs handling for guardrail refusals. Meeting content may trigger them.
- `supportedLanguages` is available at runtime **[V]**. It may not include all of our languages on a given device.
- `PrivateCloudComputeLanguageModel` will **never** be used: content would leave the device.

## Memory and device tiers

There is a report of a ceiling near 6 GB per app, even on 12 GB iPhones with the `com.apple.developer.kernel.increased-memory-limit` entitlement **[R]**. We use the entitlement, but budget conservatively.

| Tier | Devices (examples) | Transcription | Summary and chat |
|---|---|---|---|
| T0 | RAM < 6 GB | Apple | Not available, explained on screen |
| T1 | 6 GB, no Apple Intelligence | Apple, Whisper small | Small experimental model, if SP-1 approves |
| T2 | 8 GB (iPhone 15 Pro, 16, iPad M) | All | Qwen 2B, Foundation Models |
| T3 | 12 GB+ (iPhone 17 Pro, iPad Pro) | All | Qwen 4B |

The tier comes from `os_proc_available_memory`, `ProcessInfo.physicalMemory`, and a quick device probe, not from a list of iPhone model names. New devices therefore fit in automatically. Tiers are only a starting point: the Device Advisor refines recommendations with real measurements.

## Model selection and delivery

Users choose one model per role: Transcription, Speaker separation, Voice print, Chat & summary, and Search. Onboarding offers one recommended setup, and the Device Advisor keeps pointing to the best option as the device and its use change. The full specification is in [Model management](model-management.md).

- Source: Hugging Face, pinned to a commit revision. This connection exposes IP and time to the server, like any download, and the app says so clearly.
- On first run, compiling Core ML for the Neural Engine can take seconds **[R]**. This appears as a "Preparing" step and runs only once.
- Apple SpeechTranscriber: `AssetInventory` downloads the language through the system.

## Summarizing long meetings

One hour of speech is about 12,000 tokens, far above a 4,000 to 8,000 context. So the strategy is **hierarchical map-reduce**.

```
Transcript ─► Split by topic and time (~70% of context)
    ├─► Map: extract points, decisions, and tasks as JSON per chunk
    └─► Reduce: merge until it fits in context
              └─► Final generation following the template
```

- Each step stores a checkpoint in `job`.
- Maps preserve `speaker_id` and time, so each claim can trace back to the audio.
- Partial results appear while generating.
- Estimate for 1 hour at 30 tok/s: about 1 to 2 minutes in the foreground. **This is arithmetic, not a measurement.**

Heat and throttling can slow this down significantly in long sessions. The app warns the user and allows resuming.

### Templates

Open, versioned, shareable file format (`.meetlaud-template.json`):

```json
{
  "schema": 1,
  "id": "discussion-summary",
  "name": { "en": "Discussion Summary", "pt-BR": "Resumo da discussão" },
  "category": "meeting",
  "instructions": "...",
  "sections": [
    { "title": "Key points", "kind": "bullets" },
    { "title": "Decisions", "kind": "bullets" },
    { "title": "Action items", "kind": "tasks" }
  ]
}
```

Structured `sections` help small models, allow section-by-section generation, and improve output. Tasks become checkable items.

Initial categories, with our own text: General, Meeting, Speech, Interview, Call, Medical, Legal. Fewer templates, each one tested by the eval.

## Chat (Ask)

Local RAG with citations.

```
Question
  ├─► Light rewrite, using history
  ├─► Hybrid search (FTS5 + vectors, RRF)
  ├─► Scope filter (current meeting, folder, everything)
  ├─► Build context with numbered sources, within the limit
  └─► Streaming LLM with citations [1] [2]
          └─► Tap a citation ─► open the recording at the exact time
```

- For a short meeting scope, use the whole transcript, with no search.
- If there is no basis, reply that nothing was found. The prompt forbids inventing, and the eval measures this.
- Aggregate questions ("what did we decide about pricing this quarter?") are the hardest case. We expect good, not perfect, results.

## Memory, Personalization, and prompt

Prompt order: system, user profile, relevant Memory, sources, question. All meeting content is **untrusted data**: a sentence spoken in a recording cannot become an instruction to the model. The prompt delimits it, and the app never performs an action without confirmation.

## Spikes (slice 0)

Each spike produces a report in `docs/research/` and updates this document.

| ID | Question | Success criterion |
|---|---|---|
| SP-1 | Which LLM gives the best quality, speed, and stability on 8 GB? | 1-hour summary with no crash or overheating, in all four languages |
| SP-2 | Which ASR wins per language on 1-hour audio in a real room? | WER/CER, RTF, and memory table on real devices |
| SP-3 | Do voice prints work across recordings? | Acceptable precision and low false positives, with 10 voices |
| SP-4 | Do capture and transcription survive background, lock, calls, and crashes? | Manual test suite passing on a real iPhone |
| SP-5 | Which embedding serves en, ja, pt, es? | Good recall@5 on our own set |
| SP-6 | Do all package and model licenses allow distribution? | Complete table, with attribution text ready |
| SP-7 | Does App Review accept the audio background mode and downloaded models? | TestFlight evidence and a question to Apple |
| SP-8 | Do a short test and a device probe predict a real 1-hour job? | Quick and sustained tests compared with full jobs, estimates within ±30% |

## Sources

- [FluidAudio](https://github.com/FluidInference/FluidAudio) and [benchmarks](https://docs.fluidinference.com/reference/benchmarks.md)
- [Argmax OSS (WhisperKit, SpeakerKit)](https://github.com/argmaxinc/argmax-oss-swift)
- [Parakeet TDT v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)
- [Runtimes on iPhone](https://rockyshikoku.medium.com/local-llm-on-iphone-which-runtime-is-actually-fastest-58096685481e)
- [Foundation Models, WWDC 2026](https://dev.to/hariharanjagan/whats-new-in-apples-foundation-models-framework-at-wwdc-2026-5227)
- [Context management in Foundation Models](https://infoq.com/news/2026/03/apple-foundation-models-context)
- [Gemma 4 under Apache 2.0](https://www.techwyse.com/news/ai-search/google-deepmind-gemma-4-open-models-apache-2-0-release)
- [Per-app memory ceiling](https://developer.apple.com/forums/thread/834805)
- [GPU in BGContinuedProcessingTask](https://developer.apple.com/forums/thread/816774)
- [Metal crash in the background](https://github.com/ggml-org/whisper.cpp/issues/3531)
- [SpeechAnalyzer benchmark](https://www.developersdigest.tech/blog/apple-speechanalyzer-vs-whisper-benchmark)
