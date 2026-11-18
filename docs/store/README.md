# Google Play listing

Everything the Play Console asks for, in one place. The listing text and pictures live in
[`fastlane/metadata/android`](../../fastlane/metadata/android), the layout Play tools and F-Droid both read:

```
fastlane/metadata/android/<locale>/
  title.txt                     30 characters at most
  short_description.txt         80 at most
  full_description.txt          4000 at most
  changelogs/default.txt        500 at most: "What's new" for the next release
  images/icon.png               512 x 512 (en-US only; Play uses it for every language)
  images/featureGraphic.jpg     1024 x 500
  images/phoneScreenshots/N.jpg 1080 x 1920, in the order Play shows them
```

Locales: `en-US` (the default), `ja-JP`, `pt-BR`, and `es-419` (Latin America). Add `es-ES` in the Console as a copy
of `es-419` if Spain should get Spanish too.

## Making the pictures again

Every picture is a real screen of the debug app, showing the fictional showcase library in that language. After a
screen changes:

1. Start the emulator (`docs/android.md`) or connect a phone, then install:
   `cd android && ./gradlew installDebug installDebugAndroidTest`.
2. Put the models in the showcase's own folder, so its screens show them as installed without logging a download.
   For each model in `android/app/src/main/assets/models.json` except Whisper Turbo, download its files at the pinned
   URLs, check the hashes, push the folder to `/data/local/tmp/<id>`, and copy it with
   `adb shell run-as com.meetlaud.app cp -r /data/local/tmp/<id> files/Showcase/models/<id>`, then create
   `files/Showcase/models/<id>/.complete`.
3. `Tools/store-screenshots build/store-shots` takes the screens in the four languages (about two minutes each).
4. `Tools/store-art build/store-shots fastlane/metadata/android` adds the captions from
   [captions.json](captions.json) and writes the pictures. It needs Google Chrome.

The captions avoid price and promotional words ("free", "best", "no subscription"), which Play does not allow in
pictures. The description can say them.

The feature graphic keeps its text in the middle 600 x 316 pixels. Play crops the edges in some places and puts a play
button in the middle when the listing has a video, so with a video, move the text or leave the video out.

## Play Console answers

### App details

| Field | Answer |
|---|---|
| App name | Meetlaud: AI Meeting Notes |
| Default language | English (United States), en-US |
| App or game | App |
| Free or paid | Free |
| Category | Productivity |
| Tags | Note-taking, Productivity, Business |
| Email | The developer's public contact email (required, shown on the listing) |
| Website | https://github.com/geovanneb/meetlaud |
| Privacy policy | https://github.com/geovanneb/meetlaud/blob/main/docs/PRIVACY.md |

### App content

| Declaration | Answer | Why |
|---|---|---|
| Privacy policy | The URL above | Public, in four languages, and it states what the code does |
| App access | All functionality is available without special access | No account, no login. Note for reviewers: the first launch offers to download the AI models (about 2 GB over Wi-Fi) |
| Ads | No, the app does not contain ads | |
| Content rating | Questionnaire below | |
| Target audience | 18 and over | Meeting recording for work. Not for children, so the Families policy does not apply |
| News app | No | |
| COVID-19 apps | Not a COVID-19 app | |
| Data safety | Below | |
| Government app | No | |
| Financial features | None | |
| Health apps | None | |
| Advertising ID | No, the app does not use an advertising ID | No `AD_ID` permission in the merged manifest |
| Foreground services | Below | |

### Content rating (IARC)

Category: **All other app types** (reference, productivity, utility).

| Question | Answer |
|---|---|
| Violence, fear, sexuality, nudity, crude humor, drugs, alcohol, tobacco, gambling | No |
| Simulated gambling | No |
| Does the app let users interact or exchange content with other users? | No. Recordings never leave the device. Sharing a file goes through Android's share sheet, to another app the person picks |
| Does the app share the user's current physical location with other users? | No |
| Does the app allow users to purchase digital goods? | No |
| Is the app a web browser or search engine? | No |
| If asked about AI-generated content | Yes. Summaries and answers are generated on the device from the person's own recordings, and only that person sees them |

Expected rating: Everyone / PEGI 3 / USK 0, or the equivalent.

### Data safety

Google counts data as collected when it leaves the device. Meetlaud processes everything on the device and has no
server, so:

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **No** |
| Is all of the user data collected by your app encrypted in transit? | Not asked after "No" |
| Do you provide a way for users to request that their data is deleted? | Not asked after "No". The app deletes everything itself (Delete, Trash, Erase everything) |

The listing then reads "No data collected" and "No data shared with third parties". Why each borderline case is not
collection, in Google's terms:

- **Microphone, recordings, transcripts, voice prints, calendar:** processed only on the device ("on-device access").
- **Model downloads:** the request reveals an IP address to Hugging Face, like any download. No user data is sent.
- **Android backup:** off by default. When the person turns it on, the files go to their own backup, which the
  Android system handles, not the developer.
- **Get Things Done connector (iOS only for now):** user-initiated transfer to the person's own computer on the local
  network, end-to-end encrypted for it. Review this answer when it comes to Android.

### Foreground services

Android 14 and later need each type declared, with a short video of the feature (unlisted YouTube or a Drive link).

| Type | Feature | What the video shows |
|---|---|---|
| Microphone | Recording a meeting with the screen off. The person starts it with the Record button, and a notification with Pause and Stop stays while it runs | Tap Record, lock the phone, unlock, show the notification and the time still counting, stop |
| Media processing (Android 15+) | Transcribing a recording on the device. The person starts it with "Transcribe"; a notification shows the progress | Open a recording, tap Transcribe, go home, show the progress notification, come back to the transcript |
| Data sync (Android 10 to 14) | The same transcription, and the AI model downloads the person starts from AI models | Start a model download, go home, show the download notification |

Known issue to fix before the first review: on Android 15 and later, `WorkService` also runs model downloads as media
processing. A download is data transfer, so it should use data sync there too.

### Production access

Personal developer accounts created after November 13, 2023 need a closed test with at least 12 testers for 14 days
before they can publish to production. Accounts created earlier, and organization accounts, do not.
