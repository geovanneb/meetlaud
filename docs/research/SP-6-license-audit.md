# SP-6. License audit

**Status:** done, with re-verification required before release.  
**Date:** 2026-11-06  
**Question:** do all package and model licenses allow distribution in a free, open-source app on the App Store?

**Answer: yes for the planned stack.** Three models require attribution in the app. One conversion must be avoided, and one group of artifacts must be used with care.

This is an engineering review, not legal advice. Legal review remains on the plan (R-10).

## Method

Licenses were read from the GitHub API, the Hugging Face model API, and the model cards and `NOTICE.md` files. Downloads from Hugging Face happen from the user's device, so the app distributes no weights inside the binary, except Silero VAD.

## Packages

| Package | License | Last activity | Verdict |
|---|---|---|---|
| GRDB.swift | MIT | 2026-11-05 | OK |
| argmax-oss-swift (WhisperKit) | MIT | 2026-10-27 | OK |
| FluidAudio | Apache-2.0 | 2026-11-02 | OK |
| mlx-swift | MIT | 2026-11-04 | OK |
| mlx-swift-lm | MIT | 2026-11-04 | OK |
| swift-transformers | Apache-2.0 | 2026-11-02 | OK, if needed by MLX |

All are compatible with the project's Apache-2.0 license.

## Models

| Model | License | Obligation | Verdict |
|---|---|---|---|
| Silero VAD | MIT | Keep the notice | OK, can ship in the app |
| Whisper (OpenAI) | MIT | Keep the notice | OK |
| WhisperKit Core ML conversions | MIT | Keep the notice | OK |
| Parakeet TDT v3 | CC-BY-4.0 | **Attribution** | OK |
| Parakeet 0.6B Japanese Core ML | CC-BY-4.0 | **Attribution** | OK |
| Pyannote Community-1 Core ML | CC-BY-4.0 | **Attribution** | OK, within the scope below |
| Qwen 3.5 | Apache-2.0 | Keep the notice | OK |
| Gemma 4 (Google original) | Apache-2.0 | Keep the notice | OK |

## Findings

### Diarization license: resolved

`speaker-diarization-coreml` shows `license: other` because it is a **mixed scope** repository (`scoped-cc-by-4.0`). This was the open item in R-07.

- **Covered by CC-BY-4.0:** `Segmentation.mlmodelc`, `FBank.mlmodelc`, `Embedding.mlmodelc`, `PLDA.mlmodelc`, `PldaRho.mlmodelc`, `plda-parameters.json`, and `xvector-transform.json`.
- **Commercial use:** allowed. The rights holder of the PLDA parameters states this explicitly.
- **Attribution must name:** pyannote, WeSpeaker, BUT Speech@FIT, and Fluid Inference, link CC-BY-4.0, and say the files are modified Core ML conversions.
- **Not in that scope:** the legacy artifacts (`pyannote_segmentation`, `wespeaker`, `wespeaker_v2`, `wespeaker_int8`). They have their own upstream licenses.

**Rule:** the catalog pins only Community-1 artifacts. Voice print uses `Embedding.mlmodelc`, not the legacy `wespeaker` files. FluidAudio's legacy online diarizer stays out unless SP-3 needs it, and then its upstream licenses must be reviewed.

### Gemma 4 conversions: avoid

Google's original is Apache-2.0, but `mlx-community` conversions, including `gemma-4-e2b-it-4bit`, are tagged `license:gemma`. If SP-1 selects Gemma 4, convert from Google's Apache-2.0 weights ourselves, or confirm the tag is only a stale label. Qwen 3.5 conversions are tagged Apache-2.0, with no such issue.

### Sortformer: not cleared

FluidAudio's Sortformer is reported to use the NVIDIA Open Model License. We did not read it, and it is not in the plan. Do not add it without review.

### Pyannote originals are gated

`pyannote/speaker-diarization-community-1` needs a Hugging Face login to download. The Fluid Inference conversion does not, which keeps "no accounts" true. Never point the catalog at the gated original.

### Parakeet Japanese

The correct repository is `FluidInference/parakeet-0.6b-ja-coreml`, based on `nvidia/parakeet-tdt_ctc-0.6b-ja`. Earlier notes used a different name.

## Requirements for the app

1. Settings > Help > Licenses shows `THIRD_PARTY_NOTICES.md` content.
2. Each model's detail screen shows license and source (already in the Model management doc).
3. `check-catalog` rejects a model with no license data (already in the Testing doc).
4. Before release, re-verify this table against the exact pinned revisions.
