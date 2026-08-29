# フレームワークごとの要素の掴み方

Maestro は**アクセシビリティ層**を見る。だから「画面に出ているのに掴めない」は、たいてい
**その要素がアクセシビリティ層に出ていない**という意味になる。何を仕込めばそこに出るかが
フレームワークごとに違う。

**結論の早見表:**

| フレームワーク | `id` として掴めるもの | 落とし穴 |
| --- | --- | --- |
| Flutter | `Semantics(identifier:)` | **`Key` は掴めない** |
| React Native | `testID` | iOS の深いネストでタッチが吸われる |
| Android ネイティブ | `android:id` / `contentDescription` | 装飾用 View に id が無い |
| iOS ネイティブ | `accessibilityIdentifier` | SwiftUI は明示しないと出ないことがある |

---

## Flutter

### `Key` は使えない

> [!IMPORTANT]
> **Flutter の `Key`（`ValueKey` / `GlobalKey`）はアクセシビリティ層に公開されない。**
> Maestro からは原理的に見えない。`ValueKey('login_button')` を付けても `tapOn: {id: ...}` は
> 当たらない。`integration_test` の `find.byKey` の感覚で書くと必ず詰まる。

### 正解は `Semantics(identifier:)`

Flutter 3.19 以降。

```dart
Semantics(
  identifier: 'login_button',
  child: ElevatedButton(
    onPressed: _login,
    child: const Text('ログイン'),
  ),
)
```

```yaml
- tapOn:
    id: "login_button"
```

**翻訳や A/B テストで文言が変わっても壊れない**ので、これを第一候補にする。

### テキストを持つウィジェットはそのまま掴める

`Text` / `TextField` などは既定でセマンティクスを出すので、`text` セレクタが当たる。

```yaml
- tapOn: "ログイン"
```

### テキストを持たないものはラベルが要る

`Icon`、`Container`、装飾用の `GestureDetector` は、そのままでは何も出ない。

```dart
Icon(Icons.add, semanticLabel: 'add_button')
```

### `ensureSemantics()` は Android でも要る

> [!CAUTION]
> **公式ドキュメントは「Flutter Web でのみ必要」と書いているが、実測では Android でも要る。**
> 無いと、**最初の 1 画面だけ掴めて、その後アクセシビリティツリーが空になる**。
> 「起動直後は動くのに、画面遷移した途端に何も見つからなくなる」という形で出る。

```dart
import 'package:flutter/semantics.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();   // これ
  runApp(const MyApp());
}
```

Flutter はアクセシビリティサービスが有効なときだけ semantics ツリーを作る。Maestro の
Android ドライバは接続時に一時的に有効化するが、**そのまま維持されない**。
`ensureSemantics()` は常時オンに固定する。

実測（Flutter 3.41.2 / Android 14 エミュレータ / Maestro 2.8.0）:

| | 遷移後の画面のツリー |
| --- | --- |
| `ensureSemantics()` **なし** | システム UI のみ。アプリの要素は **0 件** |
| `ensureSemantics()` **あり** | アプリの要素が全部出る |

**これはテスト専用の分岐ではない。** semantics を常時オンにするのは、スクリーンリーダー
利用者に対しても正しい状態なので、本番ビルドに入れてよい。

### Flutter のテキストは `text` ではなく `accessibilityText` に入る

階層をダンプして `text` 属性だけを探すと「何も無い」と誤解する。Flutter の `Text` は
**`accessibilityText`**（Android の `content-desc`）として出る。
Maestro の `text` セレクタはこちらも見るので、Flow の書き方は変わらない。**階層を目で
調べるときだけ注意する。**

### 制約

- **Flutter Desktop は非対応**

---

## React Native

### `testID` が `id` になる

```jsx
<TextInput testID="username_input" />
```

```yaml
- tapOn:
    id: "username_input"
```

**Android と iOS で同じ書き方が通る**ので、これを第一候補にする。

### 表示テキストでも掴めるが壊れやすい

```yaml
- tapOn: "はじめる"
```

文言変更・多言語対応で壊れる。`testID` を足すほうが安い。

### iOS でタッチが吸われるとき

深くネストしたコンポーネントで、外側がタッチを吸ってしまうことがある。
**内側に `accessible={true}`、外側に `accessible={false}`** を置くと通る。

### Expo Go

カスタム `appId` では `launchApp` が使えない。**`openLink` で開発 URL を開く。**

---

## Android ネイティブ

- `android:id` が `id` セレクタに対応する
- `contentDescription` は `text` セレクタで掴める
- 装飾用の `View` には id が振られていないことが多い。**掴みたいなら振る**

階層を確認する:

```bash
maestro hierarchy          # あるいは MCP の inspect_screen
```

---

## iOS ネイティブ

- `accessibilityIdentifier` が `id` セレクタに対応する
- `accessibilityLabel` は `text` セレクタで掴める
- **SwiftUI では `.accessibilityIdentifier("...")` を明示しないと出ないことがある**

---

## 権限ダイアログ

**これが E2E を最も不安定にする。** 「出るかもしれないもの」の代表。

### 起動時に決めてしまうのが最も安定

ダイアログを出させないのが一番確実。

```yaml
- launchApp:
    clearState: true
    permissions:
      all: deny                                       # まとめて拒否
```

```yaml
- launchApp:
    permissions:
      notifications: unset
      android.permission.ACCESS_FINE_LOCATION: deny
```

値は **`allow` / `deny` / `unset`** の 3 つ。`all` でまとめて指定できる。

途中で変えたいときは `setPermissions`:

```yaml
- setPermissions:
    permissions:
      camera: allow
      notifications: deny
```

### 出てしまったものを閉じる

権限ダイアログは**プラットフォームで文言が違う**。条件で包む。

```yaml
- runFlow:
    when:
      platform: Android
    commands:
      - tapOn:
          text: "許可|ALLOW|Allow"
          optional: true
```

```yaml
- runFlow:
    when:
      platform: iOS
    commands:
      - tapOn:
          text: "許可|OK|Allow"
          optional: true
```

**`optional: true` を必ず付ける。** 権限を既に持っている 2 回目以降の実行では出ないため。

### 端末の言語を固定する

そもそも文言が揺れないようにするほうが根本的。

```bash
maestro start-device --platform ios --device-locale ja_JP
```

証跡を日本語で残したいときにも要る。
