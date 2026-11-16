# Third-party notices

Meetlaud is licensed under Apache-2.0. It uses the following software and models, under their own licenses. Audit details are in [SP-6](docs/research/SP-6-license-audit.md).

This file lists what the plan uses. Each entry is confirmed when its dependency is added to the app. The final notices must be verified against the pinned revisions before release.

## Software

| Package | License |
|---|---|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | MIT |
| [argmax-oss-swift (WhisperKit)](https://github.com/argmaxinc/argmax-oss-swift) | MIT |
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | Apache-2.0 |
| [swift-transformers](https://github.com/huggingface/swift-transformers) | Apache-2.0 |
| [mlx-swift](https://github.com/ml-explore/mlx-swift) | MIT |
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | MIT |

### Android

| Package | License |
|---|---|
| [whisper.cpp](https://github.com/ggml-org/whisper.cpp) v1.9.5, with ggml, built from source | MIT |
| [llama.cpp](https://github.com/ggml-org/llama.cpp) b12405, with ggml, built from source | MIT |
| [ONNX Runtime](https://github.com/microsoft/onnxruntime) 1.31.1 | MIT |
| [Jetpack Compose, AndroidX](https://developer.android.com/jetpack/androidx) (core, activity, lifecycle, sqlite) | Apache-2.0 |
| [kotlinx.coroutines](https://github.com/Kotlin/kotlinx.coroutines), [kotlinx.serialization](https://github.com/Kotlin/kotlinx.serialization) | Apache-2.0 |
| [Lucide](https://lucide.dev) icons 0.460.0, in place of SF Symbols | ISC |
| [Inter](https://rsms.me/inter/) typeface, in place of SF Pro | OFL-1.1 |
| [ICU4J](https://github.com/unicode-org/icu) (tests only) | Unicode-3.0 |

## Models

Models are downloaded by the user from their original sources, except Silero VAD, which ships in the app.

| Model | Source | License |
|---|---|---|
| Silero VAD | [snakers4/silero-vad](https://github.com/snakers4/silero-vad) | MIT |
| Whisper | [OpenAI](https://huggingface.co/openai/whisper-large-v3-turbo), converted by [Argmax](https://huggingface.co/argmaxinc/whisperkit-coreml) | MIT |
| Qwen 3.5 | [Qwen](https://huggingface.co/Qwen/Qwen3.5-2B) | Apache-2.0 |
| Gemma 4 | [Google](https://huggingface.co/google/gemma-4-E2B) | Apache-2.0 |
| Whisper (Android) | [OpenAI](https://huggingface.co/openai/whisper-small), converted to ggml by [ggerganov](https://huggingface.co/ggerganov/whisper.cpp) | MIT |
| Qwen 3.5 2B (Android) | [Qwen](https://huggingface.co/Qwen/Qwen3.5-2B), quantized to GGUF by [Unsloth](https://huggingface.co/unsloth/Qwen3.5-2B-GGUF) | Apache-2.0 |
| Qwen3 Embedding 0.6B (Android) | [Qwen](https://huggingface.co/Qwen/Qwen3-Embedding-0.6B-GGUF) | Apache-2.0 |
| pyannote segmentation 3.0 (Android) | [pyannote](https://huggingface.co/pyannote/segmentation-3.0), exported to ONNX by [ONNX Community](https://huggingface.co/onnx-community/pyannote-segmentation-3.0) | MIT |

## Bundled audio

`speed-test.m4a`, a 30-second clip used for speed tests, comes from the LibriVox recording of *The Art of War* by Sun Tzu. LibriVox recordings are in the public domain.

## Connector icons

The Get Things Done icon comes from [Get Things Done](https://github.com/geovanneb/get-things-done), MIT, by the same author.

## Attribution required (CC-BY-4.0)

Licensed under [Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).

- **Parakeet TDT 0.6B v3** by NVIDIA. [Source](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3). Modified: converted to Core ML by [Fluid Inference](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml).
- **Parakeet TDT-CTC 0.6B Japanese** by NVIDIA. [Source](https://huggingface.co/nvidia/parakeet-tdt_ctc-0.6b-ja). Modified: converted to Core ML by [Fluid Inference](https://huggingface.co/FluidInference/parakeet-0.6b-ja-coreml).
- **Speaker diarization Community-1** by pyannote, with WeSpeaker embeddings and PLDA parameters by BUT Speech@FIT. [Source](https://huggingface.co/pyannote/speaker-diarization-community-1). Modified: converted to Core ML by [Fluid Inference](https://huggingface.co/FluidInference/speaker-diarization-coreml), with fixed input shapes, mixed-precision storage, and a separated FBank frontend.
- **WeSpeaker ResNet34-LM** (Android) by WeSpeaker, trained on VoxCeleb. [Source](https://huggingface.co/pyannote/wespeaker-voxceleb-resnet34-LM). Modified: exported to ONNX by [ONNX Community](https://huggingface.co/onnx-community/wespeaker-voxceleb-resnet34-LM).
