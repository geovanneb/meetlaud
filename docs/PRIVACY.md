# Privacy

English · [日本語](PRIVACY.ja.md) · [Português](PRIVACY.pt-BR.md) · [Español](PRIVACY.es.md)

This page is the plain-language version of what the code does. The build enforces most of it: see `Tools/check-privacy` and `Tools/privacy-allowlist.json`.

## What leaves your device

Nothing you record, type, or ask. Recording, transcription, speaker separation, summaries, and chat all run on the device.

The app makes two kinds of connection. The second is optional and off until you set it up.

1. **AI model downloads you start.** They go to Hugging Face, at pinned versions with checked hashes. Settings > Network activity lists every one, with the date, the host, and the size. You can clear that list; after that, the screen says so instead of claiming nothing ever left.

iOS can fetch its own language models for Apple Speech and for search. iOS does that, not this app, and no meeting content is involved.

2. **Connectors you pair.** If you connect Get Things Done, new meetings go to that one computer, on your own network, encrypted for it. Only audio goes by default. Transcripts and photos need their own switches. Nothing goes through the internet, and each delivery appears in Network activity.

## What the app does not have

No accounts. No analytics. No crash reporting service. No advertising. No server.

## What stays on the device, and where

| Data | Where | In an iOS backup? |
|---|---|---|
| Recordings, transcripts, summaries, chats, memory, voice prints | The app's private storage | No, unless you turn it on in Storage & backup |
| AI models | The app's private storage | Never |
| Next event and recent meeting names | A file shared with the app's widget | No. Written only if you turn on "Show meeting names in widgets", and removed when you turn it off |

If you turn backup on, your recordings follow your iPhone's backup settings, which may mean iCloud.

## Your controls

- **Lock the app:** asks for Face ID or your passcode, and hides content in the app switcher.
- **Export library:** one file protected by your password (AES-256-GCM). Without the password nobody can open it, and it cannot be recovered. Voice prints stay out unless you include them.
- **Delete a recording:** removes its audio, transcript, summaries, search data, chats about it, and any answer that quotes it.
- **Erase everything:** removes all of the above, plus models and settings. iOS's own language models stay, since they belong to iOS.

## Voice prints

Voice prints are biometric data. They are optional, need your consent for each person, and can be deleted in People.

## Recording other people

Recording people may require their consent, depending on where you are. That is your responsibility, and the app reminds you before your first recording.

## The honest limits

- AI can be wrong. Summaries and answers link to their source so that you can check them.
- Anyone who can unlock your phone can open the app, unless you turn on the app lock.
