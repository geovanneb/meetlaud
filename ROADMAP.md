# Roadmap

Where Meetlaud is going. No dates: this is a volunteer project, and things ship when they are solid. Want to help with something here? Comment on its issue, or open one.

## Now: getting to 1.0

Every 1.0 feature is built and tested in the simulator. What is left is proving it on real devices and real meetings.

- [ ] Real-device runs: 3-hour recordings with the screen locked, phone calls and AirPods interrupting, power loss
- [ ] Summaries of real long meetings, in all four languages (synthetic 1-hour and 3-hour runs already pass on iPhone 17)
- [ ] Speaker recognition across meetings with real voices
- [ ] Manual VoiceOver and Reduce Motion passes
- [ ] Native review of the Japanese, Portuguese, and Spanish text
- [ ] Siri on a device, and Lock Screen controls for the player
- [ ] Public TestFlight, then the App Store with the "Data Not Collected" label

## Next

- **Live transcription**, while you record
- **Import your own model** from Files, clearly marked as untested
- **Apple Watch**: start and stop recording from the wrist
- **Connectors that wake up**: deliver to your computer even when the app is closed
- More summary templates, written by people who use them

## Later

- **Android**, as a separate native app sharing formats and prompts with this one. See [Bringing Meetlaud to Android](docs/porting-android.md)
- **Mac app** for video-call meetings
- More interface languages

## Not planned

These go against the core promise, so they are out of scope: accounts, cloud sync of our own, analytics, bots that join meetings, and hardware.
