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

**既存の `Key` は消さず、`Semantics` を外側に足す。** `Key` は widget テストが
`find.byKey` で使っているので、置き換えるとそちらが壊れる。両立させる:

```dart
Semantics(
  identifier: 'marker_${cell.x}_${cell.y}',
  child: GestureDetector(
    key: ValueKey(cell),          // widget テスト用。そのまま残す
    onTap: () => onTap(cell),
    child: ...,
  ),
)
```

**`identifier` の形式は Flow との契約**なので、widget テストで固定しておくとよい。
変えたときに `flutter test` の時点で気づける（エミュレータが要らない）。

```dart
final ids = tester
    .widgetList<Semantics>(find.byType(Semantics))
    .map((s) => s.properties.identifier)
    .whereType<String>()
    .toSet();
expect(ids, contains('marker_0_1'));
```

**振りすぎない。** レイアウト用の `Row` / `Column` / `Padding` に振ると木が太り、
iOS のスナップショット深さ制限（60）に近づいて有害。**停止条件は「その Flow が
通ること」であって、網羅率ではない。**

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

### `ensureSemantics()` — 入れておく。ただし「Android で必ず要る」ではない

```dart
import 'package:flutter/semantics.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();   // これ
  runApp(const MyApp());
}
```

Flutter は**アクセシビリティサービスが有効なときだけ** semantics ツリーを作る。
`ensureSemantics()` はそれを常時オンに固定する。公式ドキュメントは
「Flutter Web でのみ必要」と書いている。

> [!IMPORTANT]
> **Android で要るかどうかは、実測が 2 回あって食い違っている。**
> どちらの結果も消さずに残す。同じバージョンの組み合わせでも結果が割れているので、
> 「必ず要る」とも「要らない」とも言えない。

| 実測 | 環境 | 結果 |
| --- | --- | --- |
| 2026-08-26 | Flutter 3.41.2 / Android 14 エミュ / Maestro 2.8.0 | **無いと遷移後のツリーが空**（アプリの要素 0 件、システム UI のみ） |
| 2026-09-03 | 同上（別アプリ・別 Flow） | **無くても全ステップ通った**。対照ビルドの差し替えは APK 内 `kernel_blob.bin` の SHA-1 差で確認済み |

推測（未検証）: Maestro の Android ドライバは UiAutomator ベースで、UiAutomator は
内部的に AccessibilityService として接続する。Flutter はその接続を検知すると
自前で semantics を有効化するので、明示の `ensureSemantics()` が無くても掴める
ことがある――という筋。**有効化のタイミングと `launchApp` の順序で結果が割れている
可能性が高い**（アタッチ済みのドライバの下で起動した回は通った）。

**実務上の結論: 入れておく。** 害が無く、要る回に効く。

- semantics を常時オンにするのは**スクリーンリーダー利用者に対しても正しい状態**なので、
  テスト専用の分岐ではない。本番ビルドに入れてよい
- ただし**「掴めない ＝ これを入れれば直る」と決め打ちしない。** 入れても直らないときは
  セレクタ側（`text` の全体マッチ、`Key` を使っていないか）を先に疑う
- 逆に**これが入っているから大丈夫、とも言えない。** 通っている Flow の
  合格条件がこれかどうかは、外した対照ビルドを 1 回作れば分かる

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
