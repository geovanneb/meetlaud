<p align="center"><img src="docs/assets/logo.png" width="120" alt="Meetlaud のロゴ"></p>

<h1 align="center">Meetlaud</h1>

<p align="center"><strong>会議の記憶を、あなたのスマートフォンに。誰かのクラウドではなく。</strong></p>

<p align="center">
<a href="README.md">English</a> · 日本語 · <a href="README.pt-BR.md">Português</a> · <a href="README.es.md">Español</a>
</p>

<p align="center">
<img alt="ライセンス: Apache-2.0" src="https://img.shields.io/badge/license-Apache--2.0-blue">
<img alt="対応: iOS / iPadOS 26 以降" src="https://img.shields.io/badge/iOS%20%7C%20iPadOS-26%2B-black">
<img alt="対応: Android 10 以降" src="https://img.shields.io/badge/Android-10%2B-3ddc84">
<img alt="Swift 6 と Kotlin 2" src="https://img.shields.io/badge/Swift%206%20%7C%20Kotlin%202-orange">
<img alt="オフラインで動作" src="https://img.shields.io/badge/AI-100%25%20%E7%AB%AF%E6%9C%AB%E5%86%85-2ea44f">
</p>

<p align="center">
<a href="https://play.google.com/store/apps/details?id=com.meetlaud.app"><img alt="Google Play で手に入れよう" src="https://play.google.com/intl/en_us/badges/static/images/badges/ja_badge_web_generic.png" height="80"></a>
</p>

Meetlaud は会議を録音し、文字に起こし、誰が何を話したかを示し、要約を書き、会議についての質問に答えます。すべてスマートフォンの中で動きます。iPhone、iPad、Android に対応しています。

- **買うものはありません。** 専用レコーダーもクリップ型デバイスも不要です。ポケットの iPhone には、優れたマイクと AI のためのチップがすでに入っています。
- **毎月払うものもありません。** サブスクリプションも、分数の上限もありません。3 時間のワークショップも、何度でも録音できます。
- **データの行き先がありません。** アカウントもサーバーもありません。あなた自身が送らない限り、録音が端末の外に出ることはありません。
- **信じるだけではありません。** コードは公開されています。このページの約束はすべて、誰でも読んで確かめられます。

<p align="center">
<picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/01-home-dark.png"><img src="docs/screenshots/01-home-light.png" width="180" alt="ホーム: 会議の一覧とこれからの予定"></picture>
<picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/02-transcript-dark.png"><img src="docs/screenshots/02-transcript-light.png" width="180" alt="話者名つきの文字起こし"></picture>
<picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/03-summary-dark.png"><img src="docs/screenshots/03-summary-light.png" width="180" alt="要点・決定事項・タスクの要約。それぞれ発言の瞬間にリンク"></picture>
<picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/04-ask-dark.png"><img src="docs/screenshots/04-ask-light.png" width="180" alt="質問すると出典つきで答えが返る"></picture>
</p>

<p align="center"><sub>画像の会議と人物は架空のものです。画像は英語表示ですが、アプリは日本語にも対応しています。画像は iPhone 版ですが、Android 版も同じ画面です。</sub></p>

> **ステータス: Android 版 1.0 を公開中。** Android 版の Meetlaud は [Google Play](https://play.google.com/store/apps/details?id=com.meetlaud.app) で入手できます。iPhone と iPad のアプリはまだ App Store にありません。自分でビルドする(「自分でビルドする」を参照)か、[Releases](../../releases) ページの署名なしビルドをインストールできます。次は公開 TestFlight と App Store を予定しています。

## なぜ Meetlaud なのか

多くの AI 議事録ツールは、デバイスの購入、月額プラン、そして見えないサーバーへの音声送信を求めます。商談、役員会議、診察、採用面接では、それは大きな負担です。

今のスマートフォンは、この仕事を自分でこなせるほど速くなりました。Meetlaud はオープンな AI モデルを端末で直接動かします。iPhone では Neural Engine と GPU、Android ではプロセッサを使います。モデルを一度ダウンロードすれば、機内モードでも使えます。

| | Meetlaud |
|---|---|
| ハードウェア | お手持ちの iPhone、iPad、または Android 端末 |
| 価格 | 無料・オープンソース |
| 録音の上限 | なし |
| AI が動く場所 | あなたの端末の中 |
| アカウント | 不要。登録するものがありません |
| オフライン | 対応(モデルのダウンロード後) |
| ソースコード | 公開、Apache-2.0 |

## できること

**録音する**
- ワンタップで録音。iPhone ではウィジェット、ロック画面、コントロールセンター、アクションボタン、ショートカットからも録音できます。
- 画面をロックしても、アプリがバックグラウンドでも録音を続けます。iPhone ではライブアクティビティ、Android では操作ボタン付きの通知が表示されます。
- 障害や中断に強い設計: 電話やクラッシュで途切れた録音も復元します。
- 録音中に、瞬間のマーク、メモ、写真を残せます。
- 手元の音声ファイルも読み込めます。

**理解する**
- **文字起こし**は Whisper で(iPhone では Apple Speech も)。英語・日本語・ポルトガル語・スペイン語で検証済みです。どの行もタップすればその部分を再生します。
- **話者の識別:** 誰がいつ話したかを文字起こしに表示します。一度声に名前をつければ、次の会議でその人を提案できます。声紋は任意で、端末の外には出ません。
- **要約**はテンプレート(会議、面接、講義、通話など)または自作のテンプレートから。要点・決定事項・タスクのそれぞれが発言の瞬間にリンクしているので、すぐに確認できます。
- **質問する:** 1 つの会議、フォルダ、ライブラリ全体に質問できます。答えには出典がつきます。
- タスクは iPhone ではリマインダーへ、Android では好きなタスクアプリへ。マインドマップ、人名や専門用語のための単語登録、「えーと」「あのー」を省いた読みやすい表示もあります。

**自分で管理する**
- フォルダ、全文字起こしの検索、会議と録音のカレンダー表示。
- Face ID、指紋、または画面ロックによるアプリのロックと、パスワードで保護したライブラリ全体の書き出し。一方のプラットフォームで書き出したライブラリは、もう一方でも開けます。
- **AI モデル画面:** 処理ごとにモデルを選び、端末に合うものを確認し、自分の音声で速度テストができます。
- **ネットワークアクティビティ画面:** モデルのダウンロードや、ペアリングしたコンピュータへの送信など、アプリの通信をすべて表示します。新しくインストールした状態では「このデバイスから何も送信されていません」と表示されます。履歴は消去できます。
- 英語・日本語・ポルトガル語・スペイン語のインターフェース。VoiceOver と TalkBack、大きな文字に対応。

<p align="center">
<picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/05-recording-dark.png"><img src="docs/screenshots/05-recording-light.png" width="180" alt="マーク・写真・メモのボタンがある録音画面"></picture>
<picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/06-network-dark.png"><img src="docs/screenshots/06-network-light.png" width="180" alt="ネットワークアクティビティ: このデバイスから何も送信されていません"></picture>
</p>

## 確かめられるプライバシー

Meetlaud の通信は 2 種類だけで、どちらも **設定 > ネットワークアクティビティ** に表示されます。

1. **あなたが開始する AI モデルのダウンロード。** Hugging Face から、固定したバージョンとハッシュ検証つきで取得します。会議の内容は一切送りません。
2. **任意: あなた自身のコンピュータ。** 自分のネットワーク上のデスクトップアプリとペアリングすると、新しい会議が暗号化されて直接そこへ届きます。現在は [Get Things Done](https://github.com/geovanneb/get-things-done)(コンピュータ上で動く、AI ツールのためのオープンソースのワークメモリ)に対応しています。インターネットは経由しません。

アナリティクス、クラッシュレポートサービス、広告、アカウントはありません。これはビルドで強制しています。ダウンロード用モジュールとコンピュータへのコネクタ以外のコードが通信を開くと、`make check` が失敗します。詳しくは [プライバシー](docs/PRIVACY.ja.md) をご覧ください。

## 動作環境

| | 録音と文字起こし | 要約と質問 |
|---|---|---|
| iOS / iPadOS 26 の iPhone または iPad | 対応 | 約 8 GB のメモリが必要(例: iPhone 15 Pro 以降、M チップ搭載の iPad) |
| Android 10 以降(64 ビット) | 対応 | 約 4 GB のメモリが必要。エントリー機でも動きますが時間がかかります(4 GB の端末で 10 分の会議の要約に 24 分) |

モデルのダウンロードは一度だけで、標準では Wi-Fi 接続時のみです。文字起こし用に約 0.2〜0.7 GB、要約用に 1.3〜1.6 GB。iPhone では Apple Speech と検索にダウンロードは不要で、Android では 0.6 GB の検索モデルをダウンロードします。

## 自分でビルドする

```sh
git clone <このリポジトリ>
cd meetlaud
```

**iPhone と iPad。** Xcode 26 と [Homebrew](https://brew.sh) が入った Mac が必要です。

```sh
make bootstrap        # ツールを入れて Xcode プロジェクトを生成
open ios/Meetlaud.xcodeproj
```

シミュレータで `Meetlaud` スキームを実行します。自分の iPhone で動かすには、`ios/Config/Local.xcconfig` にチーム ID と自分用のバンドル ID を書きます([CONTRIBUTING.md](CONTRIBUTING.md)、英語)。

**Android。** JDK 17 と、NDK を含む Android SDK が必要です。macOS、Linux、Windows で動きます。

```sh
make android-install  # アプリをビルドして、USB で接続した端末にインストール
```

Android Studio で `android/` フォルダを開くこともできます。詳しくは [The Android app](docs/android.md)(英語)をご覧ください。

## 仕組み

1 つのリポジトリに 2 つのネイティブアプリがあります。`ios/` は Swift 6 と SwiftUI、`android/` は Kotlin と Jetpack Compose です。どちらも同じルールに従います。ドメイン層は純粋で、AI エンジンはすべてポートの向こう側、メモリに載る大きなモデルは常に 1 つだけです。Android のドメインは iOS のものを 1 行ずつ移植したもので、ビルド時に両者が同じ答えを返すことを確認しています。画面の文言は 1 組の String Catalog から作られます。

| 処理 | iPhone と iPad | Android | モデルのライセンス |
|---|---|---|---|
| 文字起こし | [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift)(Core ML)、Apple Speech | [whisper.cpp](https://github.com/ggml-org/whisper.cpp) | MIT(Whisper) |
| 話者の識別と声紋 | [FluidAudio](https://github.com/FluidInference/FluidAudio)(pyannote Community-1) | [ONNX Runtime](https://github.com/microsoft/onnxruntime)(pyannote と WeSpeaker) | MIT、CC-BY-4.0 |
| 要約と質問 | [MLX Swift](https://github.com/ml-explore/mlx-swift) と Qwen 3.5 2B | [llama.cpp](https://github.com/ggml-org/llama.cpp) と Qwen 3.5 2B | Apache-2.0 |
| 検索 | Apple の端末内埋め込み、[GRDB](https://github.com/groue/GRDB.swift) による SQLite FTS5 | llama.cpp による Qwen3 Embedding、SQLite FTS5 | Apache-2.0 |

技術ドキュメントは英語です: [アーキテクチャ](docs/architecture.md) · [Android アプリ](docs/android.md) · [端末内 AI](docs/on-device-ai.md) · [モデル管理](docs/model-management.md) · [コネクタ](docs/connectors.md) · [ドキュメント一覧](docs/README.md)

## コントリビュート

誤字の修正から新しい言語モデルまで、どんな貢献も歓迎します。まず [CONTRIBUTING.md](CONTRIBUTING.md) をご覧ください。Issue は日本語で書いても大丈夫です。始めやすいのは次のような分野です。

- **翻訳:** 日本語・ポルトガル語・スペイン語のネイティブチェック。
- **実機テスト:** 古い iPhone、iPad、さまざまなメーカーの Android 端末、長時間の会議、騒がしい部屋。
- **あなたの職種に合った要約テンプレート。**
- **両プラットフォーム:** 新機能も修正も、iPhone と Android に同時に届けます。片方のプラットフォームしか知らなくても大丈夫です。変更をそちらに移植したり、不具合がそちらでも起きるか確かめたりできます。

今後の予定は [ロードマップ](ROADMAP.md) にあります。プライバシーやセキュリティの問題を見つけた場合は、公開 Issue ではなく [SECURITY.md](SECURITY.md) の手順に従ってください。

## ご注意

- **AI は間違えることがあります。** 要約と回答には出典へのリンクがあるので、確認できます。医療・法律・金融の判断に使う前には、必ず確認してください。
- **録音の前に同意を。** 会話の録音に関する法律は国や地域によって異なり、全員の同意が必要な場合もあります。これは利用者の責任であり、アプリは最初の録音の前にお知らせします。
- **電話の録音:** iOS と Android はアプリによる通話の録音を許可していません。端末自身が作成した録音は読み込めます。

## ライセンスと商標

コードは [Apache-2.0](LICENSE) で公開しています。モデルとライブラリにはそれぞれのライセンスがあり、[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) にまとめています。

Apache ライセンスの対象はコードであり、Meetlaud の名前とロゴは含まれません。フォークは自由です。利用者が区別できるよう、別の名前とアイコンをつけてください。

Meetlaud は独立したプロジェクトです。録音デバイスやノートサービスのメーカーとは提携関係になく、推奨や後援も受けていません。iPhone、iPad、Apple は Apple Inc. の商標です。Android と Google Play は Google LLC の商標です。その他の商標はそれぞれの所有者に帰属します。
