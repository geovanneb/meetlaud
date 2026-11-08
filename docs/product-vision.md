# Product vision

## Proposition

Meetlaud is the memory of your meetings on iPhone and iPad. You press record, put the device down, and afterwards you have a transcript, a summary, and a chat about everything that was said. Everything runs on the device. Nothing goes to a cloud.

## Why it exists

AI meeting notes usually come with two costs: a dedicated recorder to buy, and a subscription that limits minutes and sends audio to someone else's servers. Most people already carry a good microphone and a chip with a Neural Engine in their pocket. Only the software was missing.

| | Typical AI meeting recorder | Meetlaud |
|---|---|---|
| Hardware | Often a dedicated device | None. Your iPhone or iPad |
| Price | Device and/or subscription | Free |
| Usage limit | Minutes per month | None. The device is yours |
| Where AI runs | Usually a cloud service | On the device |
| Account | Usually required | Does not exist |
| Works without internet | Often capture only | Everything, after the models are downloaded |
| Code | Usually closed | Open and auditable |

The left column describes the category in general, not any one product. Some products differ.

## Audience

- **Professionals tired of subscriptions.** Consultants, managers, sales and marketing teams who want notes from every meeting without per-minute pricing.
- **People who handle sensitive information.** Lawyers, doctors, HR, researchers, and executives who cannot send audio elsewhere.
- **Students and researchers.** Lectures and interviews with no per-minute cost.
- **The technical community.** People who want to audit, contribute, and trust the privacy promise.

## Product principles

1. **Recording is sacred.** No feature may put a recording at risk. If everything else fails, the audio must still be there.
2. **Privacy you can prove.** The promise is verifiable: open code, a single network module for model downloads, and an automated check that blocks new connections.
3. **One tap for what matters.** Recording takes one tap. Everything else appears when it makes sense.
4. **Honesty about the device.** If an iPhone cannot run a model well, the app says so clearly. It never pretends and never freezes.
5. **Fast and native.** System components first. The interface stays responsive even with a model running.
6. **Familiar from the first minute.** Someone who has used any meeting recorder finds recordings, transcripts, and summaries where they expect them.

## What we do not do

- Accounts, login, our own sync, or servers.
- Analytics, telemetry, or remote crash reporting.
- Connectors to cloud services (Gmail, Slack, Notion, and the like). The share sheet and Shortcuts cover this, under the person's control. Connectors to the person's own computer over the local network are optional (D-067, D-072).
- Hardware.
- Bots that join meetings.

## Technical limits to communicate plainly

These points must appear in the public documentation and in the app, when relevant.

- **Phone calls.** Apple offers no supported way for an app to record calls. Our path is to import the recording iOS makes itself, where it exists.
- **Audio from other apps.** The app captures the microphone. A video call on speaker on the same iPhone depends on how the system handles the audio session.
- **Starting a recording.** It must happen with the app in the foreground. Controls and widgets open the app, because the system does not allow capture to start fully in the background.
- **Background summaries.** iPhones may not give apps GPU access in the background. Summaries with a downloaded model may need the app to be open. See [On-device AI](on-device-ai.md).
- **AI quality.** On-device models are smaller than cloud models. Quality is good for summaries and direct questions, but does not match frontier models at long reasoning.
- **Older devices.** Summaries and chat need more memory. Every iPhone on iOS 26 records and transcribes, but not all of them summarize.

## Success metrics

With no telemetry, we measure what is public: App Store ratings, stars, issues, and download numbers reported by Apple. Quality is measured with the evaluation harness ([Testing](testing.md)).

- Zero confirmed reports of a lost recording.
- Zero network connections outside model downloads and connectors the person set up.
- 95% or more of core flows completed without help in usability tests.
