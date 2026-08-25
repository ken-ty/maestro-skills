---
name: maestro
description: Maestro でモバイルアプリの E2E テストを書き、実機・エミュレータ・シミュレータでの動作確認をローカルに閉じて push 前の関門にする手順。「E2E テストを書きたい」「実機で確認して」「エミュレータ立てて」「Maestro を入れたい」「Flow が要素を見つけられない」「tapOn が当たらない」「テストが不安定」「権限ダイアログで止まる」「CI の実行分を食う E2E を手元に落としたい」「pre-push で動作確認したい」「動作確認の証跡（スクショ・動画）を自動で撮りたい」といった場面で使う。Android 実機/エミュレータと iOS シミュレータを同じ YAML で扱い、フレームワーク（Flutter / React Native / ネイティブ）を問わない。
---

# Maestro — 書き方と、ローカル関門としての回し方

[Maestro](https://maestro.dev/) は YAML で書くモバイル E2E テストのフレームワーク。
**同じ Flow が Android 実機・Android エミュレータ・iOS シミュレータで回り**、アプリ側の
フレームワーク（Flutter / React Native / ネイティブ）を問わない。ビルド済みの APK / IPA に
そのまま当てるので、アプリのコードに手を入れる必要がない。

このスキルは 2 つを扱う:

1. **Flow の書き方** — コマンド、セレクタ、待ち、条件分岐。LLM が間違えやすいところを中心に
2. **ローカル関門としての回し方** — 端末の用意、pre-push への組み込み、証跡の始末、CI との線引き

## 索引

**必要になったときだけ読む。** SKILL.md には入口しか置いていない。

| 知りたいこと | 参照先 |
| --- | --- |
| コマンド一覧、セレクタ、待ち、条件分岐、サブフロー | `references/flows.md` |
| Flutter / React Native / ネイティブごとの要素の掴み方、権限ダイアログ | `references/platforms.md` |
| 初回セットアップ（JDK / Android SDK / Maestro / AVD） | `references/setup.md` |
| 証跡の出方・実測サイズ・世代管理・PR への貼り方 | `references/artifacts.md` |
| CI に何を残すか、public / private で変わる課金 | `references/ci.md` |
| 実測で見つけた罠 | `references/pitfalls.md` |
| pre-push フックの実装 | `recipes/pre-push.sh` |

---

## 最小の Flow

```yaml
# login.yaml
appId: com.example.app
---
- launchApp:
    clearState: true
- tapOn:
    id: "email_field"
- inputText: "user@example.com"
- tapOn: "ログイン"
- assertVisible: "ようこそ"
```

`---` の**上が設定、下がコマンド列**。`appId` は必須。

回す:

```bash
maestro test login.yaml --udid "<deviceId>"
```

**成功で終了コード 0、失敗で非 0。** これがそのまま関門に使える。

---

## 書くときの原則

### 1. セレクタは id を第一候補にする

`text` は翻訳・A/B テスト・コピー変更で壊れる。**アプリ側に安定した識別子を仕込むのが正解。**

```yaml
- tapOn:
    id: "login_button"      # ◎ 安定
- tapOn: "ログイン"          # △ 文言が変われば壊れる
```

識別子をどう仕込むかは**フレームワークごとに違う** → `references/platforms.md`。
特に **Flutter の `Key` は Maestro からは見えない**（アクセシビリティ層に出ないため）。
ここは踏みやすいので先に読むこと。

### 2. 「待つ」を明示する

Maestro は各コマンドで暗黙に待つが、既定のタイムアウトは短い。**ネットワークを跨ぐ遷移には
明示的に待ちを置く。**

```yaml
- extendedWaitUntil:
    visible: "注文が完了しました"
    timeout: 15000
```

`sleep` 相当で誤魔化さないこと。固定待ちは遅い端末で落ち、速い端末で無駄になる。

### 3. 「出るかもしれないもの」は条件で包む

権限ダイアログ、レビュー依頼、キャンペーンのポップアップ。**出たり出なかったりするものを
無条件に `tapOn` すると、出なかった回に落ちる。**

```yaml
- tapOn:
    text: "あとで"
    optional: true            # 単発ならこれで足りる
```

```yaml
- runFlow:                    # 複数コマンドや複雑な条件はこちら
    when:
      visible: "通知を許可しますか"
    commands:
      - tapOn: "許可"
```

### 4. 証跡は自分で置く

> [!IMPORTANT]
> **成功した Flow は screenshot を 1 枚も残さない。** Maestro が自動で撮るのは
> **失敗したステップだけ**。「通ったこと」を人に見せたいなら `takeScreenshot` を明示的に置く。

```yaml
- startRecording: run
- takeScreenshot: 01-起動直後
- tapOn: "はじめる"
- takeScreenshot: 02-次の画面
- stopRecording
```

---

## ローカル関門として回す

**動作確認を CI から手元へ移し、push 前の関門にする。** 実機 E2E は課金ランナーで最も高くつく
部分なので、private リポジトリではここを落とすと効きが大きい。

### Step 1: 前提を確かめる

```bash
java -version        # 17 以上（Maestro の要件）
maestro --version
adb devices          # 実機を繋いでいれば見える
maestro list-devices # 作成可能なデバイス一覧
```

欠けていたら `references/setup.md` へ。**`java` が 16 以下だと Maestro は動かない**、
**Android SDK のコマンドは既定で PATH に無い**、の 2 つが典型的な詰まりどころ。

### Step 2: まず構文だけ検査する（デバイス不要）

```bash
maestro check-syntax <flowsディレクトリ>
```

**数秒で終わり、デバイスが要らない。不正なコマンドがあれば非 0 で終わる。**
壊れた Flow のためにエミュレータを起動して数分待つのは無駄なので、関門の最初に置く。

### Step 3: デバイスを確保する

優先順は **実機 > 起動中の仮想デバイス > 事前に作っておいた AVD を起動**。

```bash
adb devices | awk 'NR>1 && $2=="device" {print $1}'   # Android
xcrun simctl list devices booted                       # iOS
```

> [!WARNING]
> **`maestro start-device --platform android` をフックの中で呼んではいけない。**
> 必要な system image が無いと `y/n` の対話プロンプトを出す。git hook は stdin が端末では
> ないのでそこで止まる。**AVD は人間が一度だけ作る**（`references/setup.md`）。
> iOS シミュレータでは起きないので `start-device` を使ってよい。

### Step 4: 回す

```bash
maestro test <flowsディレクトリ> \
  --udid "<deviceId>" \
  --test-output-dir "<証跡の置き場>" \
  --format JUNIT --output "<証跡の置き場>/report.xml"
```

- `--format` は `JUNIT` / `HTML` / `HTML-DETAILED` / `NOOP`(既定)
- `--include-tags` / `--exclude-tags` で Flow を絞れる。**重い Flow を pre-push から外す**のに使う

> [!CAUTION]
> **`--flatten-debug-output` を付けてはいけない。** ヘルプに "Useful for CI" とあるが、
> Maestro 2.8.0 で実測したところ**証跡が 1 つも出力されなくなる**。→ `references/pitfalls.md`

### Step 5: 証跡を始末する

実測（1080×2400）: **スクショ PNG は 1 枚 1.14 MB、動画は約 148 KB/秒。画像のほうが重い。**

```bash
sips -Z 540 -s format jpeg "<元.png>" --out "<軽量.jpg>"   # 1.14MB → 19.8KB
```

置き場（`.gitignore` に入れる）と世代管理、PR への貼り方は `references/artifacts.md`。

### Step 6: 関門に組み込む

`recipes/pre-push.sh` をリポジトリの `hooks/` に置き、`git config core.hooksPath hooks`。

- **アプリのコードが変わっていない push では回さない。** ドキュメントだけの修正で数分待たされると
  `--no-verify` が日常化し、関門が形骸化する
- **デバイスが無く AVD も未作成なら、黙って通さず落とす。** 何をすれば直るかを 1 行で出す
- **タイムアウトを必ず置く。** 仮想デバイスは無言で固まることがある

CI 側に何を残すか、public / private で課金がどう変わるかは `references/ci.md`。

---

## 探索と関門は別物

Maestro CLI は **MCP サーバを内蔵**している。

```bash
claude mcp add maestro -- maestro mcp
```

`list_devices` / `inspect_screen` / `take_screenshot` / `run` / `cheat_sheet` /
`open_maestro_viewer` などが使える。

| | MCP | このスキルの関門 |
| --- | --- | --- |
| いつ | 開発中に**探索的に**画面を触り、Flow を組み立てる | push 時に**決定的に**通す |
| 誰が | エージェントが対話的に | git hook が無人で |
| 出力 | その場のスクショ・階層 | 世代管理された証跡 |

**併用するもの。** Flow を書くときは MCP で画面を見ながら、書けたら関門に載せる。
