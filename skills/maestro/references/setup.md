# 初回セットアップ

**一度だけ人間がやる。** ここを済ませておけば、以降フックは「起動して回す」だけで済む。
逆に、ここをフックの中で遅延実行させようとすると対話プロンプトや数 GB のダウンロードで詰まる。

## 1. JDK 17 以上

Maestro の要件。**システム全体の `java` を差し替えないこと** — 他のツール（古い Gradle など）が
壊れる。スキルの実行時だけ `JAVA_HOME` を向ける。

```bash
java -version                      # 17 未満なら以下
brew install openjdk@17            # 入っていなければ
export JAVA_HOME="$(brew --prefix openjdk@17)"
export PATH="$JAVA_HOME/bin:$PATH"
```

`brew list --formula | grep openjdk` で、**既に入っているのに `java` が古いまま**というケースが
よくある。その場合は新規インストール不要で、`JAVA_HOME` を向けるだけでよい。

## 2. Android SDK のパス

Android Studio を入れていれば SDK は `$HOME/Library/Android/sdk`（macOS の既定）にあるが、
**PATH には通っていない**。

```bash
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
```

`adb` `emulator` `avdmanager` `sdkmanager` がこれで揃う。

## 3. Maestro

```bash
curl -fsSL "https://get.maestro.mobile.dev" | bash
```

`$HOME/.maestro/bin` へ入り、**インストーラが `~/.zshrc` と `~/.bash_profile` に PATH 行を追記する**
（副作用。嫌なら後で消して、自分で PATH を通す）。

**バージョンを固定したいとき**は環境変数で指定する。インストーラは値があれば
`releases/download/cli-$MAESTRO_VERSION/maestro.zip` を、無ければ latest を取りに行く。

```bash
MAESTRO_VERSION=2.8.0 curl -fsSL "https://get.maestro.mobile.dev" | bash
```

> Homebrew 版（`brew install mobile-dev-inc/tap/maestro`）とは排他。brew 版が入っていると
> curl のインストーラは拒否して終了する。どちらか一方に寄せること。

## 4. AVD を作る（Android・最重要）

**`maestro start-device` に作らせない。** 理由は `pitfalls.md` の「対話プロンプト」を参照。
`avdmanager` で、**手元に既にある system image を使って**作る。

まず何を持っているか見る:

```bash
ls -d "$ANDROID_HOME"/system-images/*/*/* | sed "s|$ANDROID_HOME/system-images/||"
```

**Apple Silicon では `arm64-v8a` を選ぶ。** `x86_64` のイメージはエミュレーションになり、
E2E の関門として使える速度が出ない。

```bash
echo no | avdmanager create avd \
  -n <AVD名> \
  -k "system-images;android-34;google_apis_playstore;arm64-v8a" \
  -d pixel_6
```

- `-k` は上で確認した実在のイメージを `;` 区切りにしたもの。**持っていないものを指定すると
  ダウンロードが始まる**ので、必ず一覧で確認してから
- `echo no` はカスタムハードウェアプロファイルの対話を断るため
- `Warning: This version only understands SDK XML versions up to 3 but ... version 4` が出ることが
  あるが、**AVD の作成自体は成功する**（cmdline-tools と SDK のリリース時期のズレ。無害）

確認と起動:

```bash
avdmanager list avd
"$ANDROID_HOME/emulator/emulator" -avd <AVD名> -no-window -no-audio -no-snapshot -no-boot-anim &
until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 3; done
adb devices
```

`-no-window` は関門用途では推奨。速く、フォーカスを奪わない。**画面を目で見たいときだけ外す**
（スクリーンショットと録画は `-no-window` でも問題なく撮れる）。

作り直したいとき: `avdmanager delete avd -n <AVD名>`

## 5. iOS シミュレータ

Xcode が入っていれば追加のセットアップは要らない。Android と違い、**`maestro start-device` を
そのまま使ってよい**（既存のシミュレータ定義から起動でき、巨大なダウンロードを伴わない）。

```bash
maestro list-devices                                    # 使えるモデルと OS
maestro start-device --platform ios --device-model iPhone-16 --device-os iOS-18-2
xcrun simctl list devices booted                        # 起動中の確認
```

`--device-locale ja_JP` で言語・地域を固定できる（`de_DE` 形式）。**証跡を日本語で撮りたいときに要る。**

## 6. 動作確認

適当な Flow を 1 本書いて通す。アプリを入れる前でも、OS 標準アプリで配線だけ確かめられる:

```yaml
# smoke.yaml
appId: com.android.settings
---
- launchApp
- startRecording: run
- takeScreenshot: 01-launched
- stopRecording
```

```bash
maestro test smoke.yaml --udid <deviceId> --test-output-dir ./out
find ./out -type f
```

`takeScreenshot/01-launched.png` と `startRecording/run.mp4` が出れば配線は完了。
