# Winmail Extractor

<p align="center">
  <img src="WinmailExtractor/Design/WinmailExtractor-AppIcon-Source.png" width="128" alt="Winmail Extractor icon">
</p>

`winmail.dat`（Microsoft TNEF形式）から添付ファイルを取り出す、macOS用のネイティブアプリです。

## ダウンロード

[GitHub Releases](https://github.com/macostrail/WinmailExtractor/releases/latest) から最新の `WinmailExtractor-*-macOS.zip` をダウンロードし、展開したアプリを「アプリケーション」フォルダへ移動してください。

現在の配布版はDeveloper IDによる公証を行っていません。初回起動時にmacOSで確認が表示された場合は、FinderでアプリをControlキーを押しながらクリックして「開く」を選択してください。

配布版はApple SiliconとIntel Macの両方に対応するUniversal Binaryです。

## 特長

- Finderで `winmail.dat` を開くだけで、添付ファイルを `~/Downloads` へ自動展開
- 展開後に保存したファイル名をポップアップで通知
- 同名ファイルを上書きせず、自動的に連番を付与
- 日本語ファイル名、Unicode MAPIプロパティ、Windowsコードページに対応
- アプリ画面からファイル選択、ドラッグ＆ドロップ、保存先指定も可能

## 使い方

1. `WinmailExtractor.xcodeproj` をXcodeで開きます。
2. `WinmailExtractor` スキームを実行、または Archive してアプリを書き出します。
3. Finderで `winmail.dat` を右クリックし、「このアプリケーションで開く」から Winmail Extractor を選びます。
4. 以後は `winmail.dat` をダブルクリックするだけで、メイン画面を表示せず `~/Downloads` へ自動展開されます。完了後、保存したファイル名をポップアップでお知らせします。

Winmail Extractorアプリ自体を直接起動した場合は、従来どおりアプリ画面が開きます。画面の「winmail.datを選ぶ」や、Finderからのドラッグ＆ドロップでは保存先を選択できます。同名ファイルがすでにある場合は `ファイル名 (2).ext` のように連番を付け、既存ファイルを上書きしません。

毎回このアプリで開く場合は、Finderで `winmail.dat` の「情報を見る」を開き、「このアプリケーションで開く」で Winmail Extractor を選んで「すべてを変更」を押します。

## 動作要件

- macOS 13 Ventura以降
- Apple Silicon / Intel Mac
- 開発時は Xcode 15以降

## 開発用コマンド

```sh
xcodebuild -project WinmailExtractor.xcodeproj \
  -scheme WinmailExtractor \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO test
```

TNEFの解析処理は、Microsoftの公式仕様 [MS-OXTNEF](https://learn.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-oxtnef/1f0544d7-30b7-4194-b58f-adc82f3763bb) に基づいています。
