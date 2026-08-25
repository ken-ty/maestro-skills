# Flow の書き方

Maestro 2.8.0 時点。コマンド名とセレクタは
[公式リファレンス](https://docs.maestro.dev/reference/) を典拠にしている。

## ファイルの形

```yaml
appId: com.example.app       # 必須。Android は package 名、iOS は bundle ID
name: ログイン               # 任意。レポートに出る
tags:                        # 任意。--include-tags / --exclude-tags で絞る
  - smoke
env:                         # 任意。既定値。実行時に -e で上書きできる
  USERNAME: "user@example.com"
---
- launchApp
- inputText: ${USERNAME}
```

`---` の**上が設定、下がコマンド列**。コマンド列は上から順に実行される。

複数の Flow を 1 つのディレクトリに置き、ディレクトリごと `maestro test <dir>` で回すのが基本形。

## コマンド一覧

44 個ある。用途別に並べる。

### アプリのライフサイクル

| コマンド | 何をするか |
| --- | --- |
| `launchApp` | アプリを起動。`clearState: true` で初期状態にできる |
| `stopApp` | アプリを止める |
| `killApp` | アプリを強制終了する |
| `clearState` | アプリのデータを消す |
| `clearKeychain` | iOS の Keychain を消す |
| `openLink` | ディープリンク / URL を開く |

### 操作

| コマンド | 何をするか |
| --- | --- |
| `tapOn` | タップ |
| `doubleTapOn` | ダブルタップ |
| `longPressOn` | 長押し |
| `swipe` | スワイプ |
| `scroll` | スクロール |
| `scrollUntilVisible` | 要素が見えるまでスクロール |
| `inputText` | テキスト入力 |
| `eraseText` | 入力を消す |
| `pasteText` | クリップボードから貼り付け |
| `copyTextFrom` | 要素のテキストをクリップボードへ |
| `setClipboard` | クリップボードに値を入れる |
| `pressKey` | キー入力（`Enter`、`Backspace` など） |
| `hideKeyboard` | キーボードを閉じる |
| `back` | 戻る |

### 検証

| コマンド | 何をするか |
| --- | --- |
| `assertVisible` | 要素が見えていること |
| `assertNotVisible` | 要素が見えていないこと |
| `assertTrue` | JavaScript 式が true であること |
| `assertScreenshot` | スクリーンショットの比較 |

`assertWithAI` / `assertNoDefectsWithAI` / `extractTextWithAI` もあるが、**AI 系は API キーと
ネットワークを要する**ので、ローカル関門には向かない。

### 待ち

| コマンド | 何をするか |
| --- | --- |
| `extendedWaitUntil` | 要素が出る / 消えるまで待つ。タイムアウトを指定できる |
| `waitForAnimationToEnd` | アニメーションが終わるまで待つ |

### 制御

| コマンド | 何をするか |
| --- | --- |
| `runFlow` | サブフローの実行。条件分岐にも使う |
| `repeat` | 繰り返し |
| `retry` | 失敗したらやり直す |
| `evalScript` | JavaScript を評価する |
| `runScript` | JavaScript ファイルを実行する |

### デバイスの状態

| コマンド | 何をするか |
| --- | --- |
| `setPermissions` | 権限を allow / deny する |
| `setLocation` | 位置情報を設定する |
| `setOrientation` | 画面の向きを変える |
| `setAirplaneMode` / `toggleAirplaneMode` | 機内モード |
| `travel` | 位置を移動させる（GPS の連続変化） |
| `addMedia` | 端末のギャラリーに画像・動画を入れる |

### 証跡

| コマンド | 何をするか |
| --- | --- |
| `takeScreenshot` | スクリーンショットを撮る |
| `startRecording` / `stopRecording` | 録画の開始 / 終了 |

出力先と扱いは [artifacts.md](artifacts.md)。

---

## セレクタ

**要素の掴み方がテストの寿命を決める。** 4 系統ある。

### 基本セレクタ

| プロパティ | 説明 | 正規表現 |
| --- | --- | --- |
| `text` | 表示テキスト、またはアクセシビリティラベル | ✅ |
| `id` | アクセシビリティ識別子 | ✅ |
| `index` | 複数マッチしたときの順番（0 始まり） | ❌ |
| `point` | 画面座標（`"50%, 50%"` または `"100, 250"`） | ❌ |
| `css` | Web のみ。CSS セレクタ | ❌ |

```yaml
- tapOn: ログイン                  # 短縮形。text 扱い
- tapOn:
    text: ".*続ける.*"             # 正規表現
- tapOn:
    id: "login_button"
- tapOn:
    id: "buy_button"
    index: 2                      # 3 番目
```

> `text` と `id` は正規表現として解釈される。**`$` や `[` を含む文字列を完全一致させたいときは
> バックスラッシュでエスケープが要る。**

> `point` は最後の手段。レイアウトが変わると黙って別の場所を押す。

### 位置関係セレクタ

**同じ文言が並ぶリストで効く。**

```yaml
- tapOn:
    below: "メールアドレス"        # 「メールアドレス」の下にあるもの
- tapOn:
    above: "決済に進む"
- tapOn:
    leftOf: "利用規約に同意する"
- tapOn:
    rightOf:
      id: "input_text"
```

### 階層セレクタ

```yaml
- tapOn:
    containsChild:                # この子を持つ親を掴む
      text: "注文 12345"
- tapOn:
    text: "削除"
    childOf:                      # この親の直下にあるもの
      id: "basket_container"
- assertVisible:
    id: "list_item"
    containsDescendants:          # 子孫すべてを含むもの（深さ不問）
      - text: "ワイヤレスヘッドホン"
      - text: "¥9,900"
```

`containsDescendants` は**リストの 1 行を、その中身の組み合わせで特定する**のに強い。

### 状態セレクタ

すべて真偽値。**基本セレクタと組み合わせて使う。**

| プロパティ | 用途 |
| --- | --- |
| `enabled` | 押せる状態か（グレーアウトしていないか） |
| `checked` | チェックボックス・スイッチの状態 |
| `focused` | キーボードフォーカスがあるか |
| `selected` | タブなどで選択状態か |

```yaml
- tapOn:
    id: "submit_button"
    enabled: true                 # 押せるようになってから押す
- assertVisible:
    id: "remember_me"
    checked: true
```

---

## 待ち方

**固定待ちを書かない。** 遅い端末で落ち、速い端末で無駄になる。

```yaml
- extendedWaitUntil:
    visible: "注文が完了しました"
    timeout: 15000                # ミリ秒
```

```yaml
- extendedWaitUntil:
    notVisible:
      id: "loading_spinner"
    timeout: 10000
```

各コマンドは既定でも少し待つが、**ネットワークを跨ぐ遷移は既定のタイムアウトを超えることが
ある**。そこだけ明示する。

アニメーション中に掴むと不安定になるので、遷移直後は `waitForAnimationToEnd` を挟む。

---

## 条件分岐

**「出るかもしれないもの」を無条件に触ると、出なかった回に落ちる。**

### 単発なら `optional`

```yaml
- tapOn:
    text: "あとで"
    optional: true
    label: "レビュー依頼が出ていたら閉じる"
```

要素が無くても失敗にならず、そのまま進む。

### 複数コマンドや複雑な条件は `runFlow` + `when`

```yaml
- runFlow:
    when:
      visible: "通知を許可しますか"
    commands:
      - tapOn: "許可"
```

`when` に置けるもの:

| 条件 | 意味 |
| --- | --- |
| `visible` | その要素が見えていれば実行 |
| `notVisible` | 見えていなければ実行 |
| `platform` | `Android` / `iOS` / `Web` が一致すれば実行 |
| `true` | JavaScript 式が true なら実行 |

**複数書くと AND。**

```yaml
- runFlow:
    when:
      platform: Android
      visible: "通知の送信を許可しますか"
    commands:
      - tapOn: "許可"
```

```yaml
- runFlow:
    when:
      true: ${NEW_CHECKOUT == 'true'}
    file: subflows/new-checkout.yaml
```

---

## サブフロー

**同じ手順を何度も書かない。** ログインは特に使い回す。

```yaml
- runFlow: subflows/login.yaml
```

```yaml
- runFlow:
    file: subflows/login.yaml
    env:
      USERNAME: "admin@example.com"
```

インラインでも書ける。**ラベルを付けるとレポートが読みやすくなる。**

```yaml
- runFlow:
    label: "並び順を新着にする"
    commands:
      - tapOn:
          id: "sort_icon"
      - tapOn: "新着順"
```

---

## 不安定な Flow への対処

順番に試す。**最後の手段から始めないこと。**

1. **セレクタを直す。** `text` を `id` に、`index` を位置関係セレクタに
2. **待ちを足す。** `extendedWaitUntil` で「次の画面の目印」を待つ
3. **条件で包む。** 出たり出なかったりするものを `optional` / `when` に
4. **`retry` を使う。** ここまでやっても残る揺らぎにだけ

`retry` を最初に使うと、**本物のバグを揺らぎとして握り潰す**。
