# SP-1. Language model on iPhone

**Status:** short meetings measured in 3 languages, and 1-hour and 3-hour meetings measured on 2026-11-08.  
**Device:** iPhone 17 (8 GB), iOS 26.6.2  
**Model:** Qwen 3.5 2B, mixed 4-bit, through MLX Swift  
**Question:** can a language model summarize real meetings on this phone, and at what cost?

## Answer so far

Yes for short meetings, in all three languages tested. Speed and memory are comfortable. Accuracy needs work: the model mixed up who owns a task, which is exactly the kind of mistake a meeting summary must not make.

## Measurements

| | English | Portuguese | Japanese |
|---|---|---|---|
| Prompt size | 905 characters | 644 characters | 282 characters |
| Time to first text | 7.9 s (first run) | 0.3 s | 0.4 s |
| Speed | 37 chunks/s | 36 chunks/s | 36 chunks/s |
| Lowest available memory | 1.8 GB | 1.8 GB | 1.8 GB |
| Thermal state | Nominal to fair | Fair | Fair |
| Crash | None | None | None |

Model load took 2.1 seconds. A chunk is roughly one token. The app stayed in the foreground for the whole run.

### Size

The repository holds 2.2 GB, of which 663 MB are vision weights this app never uses. The catalog downloads text only: **1.55 GB**.

## Quality

Read by hand against the transcripts. These are three short invented meetings, so this is an impression, not an evaluation.

| Language | What went well | What went wrong |
|---|---|---|
| English | Decisions and dates correct | The action table lost what each task was. It lists only owner and date |
| Portuguese | Decision, date, and reason correct | **Assigned Lucas's testing task to Pedro.** Also said marketing was told, when Lucas only said he would do it |
| Japanese | Price and tasks correct | "10% off (9,500 yen)" is misleading: 9,500 yen is the price before the discount |

The Portuguese error matters most. A summary that names the wrong owner is worse than none, because people will trust it.

## What this does not prove

- **Background.** MLX uses the GPU, and iOS can refuse it in the background. This ran in the foreground only.
- **Other devices.** Only 8 GB was tested. 6 GB and 12 GB devices are unknown.
- **Comparison.** Qwen 4B, Gemma 4, and Foundation Models were not tested.
- **Transcript quality.** These prompts were clean text. Real transcripts have errors and no names.

## Long meetings (2026-11-08)

iPhone 17, Qwen 3.5 2B, map-reduce by time (parts condensed separately, then merged). Synthetic English transcripts with four speakers and repeated project updates.

| Meeting | Transcript | Time | Heat at the end | Lowest free memory | Claims to review |
|---|---|---|---|---|---|
| 1 hour | 600 lines, about 10,400 tokens | 3 min 38 s | Fair | 1,162 MB | 0 of 17 |
| 3 hours | 1,800 lines, about 31,100 tokens | 10 min 2 s | Serious | 1,172 MB | 0 of 17 |

- **Coverage:** the 3-hour summary cites moments from minute 4 to minute 158. Before parts were split by time, the beginning of long meetings was lost.
- **Limits held:** 5 action items at most, and no placeholders or invented dates.
- **Weakness:** a few "Decisions" are quoted lines rather than decisions ("Next item is project 45"). The repetitive synthetic transcript makes this worse, and a real meeting is needed to judge it.
- **Heat:** the 3-hour job reached Serious. The app slows down then, and pauses at Critical.

## Decisions

- Qwen 3.5 2B is the working default for 8 GB devices.
- `MLXLanguageEngine` declares that it needs the foreground.

## Implications for F5

1. **Show evidence next to every claim.** Each task and decision links to the moment in the audio, so that people can check it.
2. **Extract tasks in a dedicated step** with a structured output of owner, task, and date, instead of free text.
3. **Build the rubric from these errors.** Owner attribution is the first metric.
4. **Try a low temperature and a two-pass check** that asks the model to verify each owner against the transcript.
5. **Test Qwen 4B on 12 GB devices** and Foundation Models for comparison.
