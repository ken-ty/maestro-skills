# 踏んだ罠

いずれも Maestro 2.8.0 / macOS (Apple Silicon) で実際に確認したもの。

## `--flatten-debug-output` は証跡を全消しする

**症状**: `--test-output-dir` を指定しているのに、出力先が空。`manifest.json` も
`takeScreenshot/` も `startRecording/` も、何一つ出ない。Flow 自体は成功して終了コード 0。

**原因**: `--flatten-debug-output` を併用していた。ヘルプには

> All file outputs from the test case are created in the folder without subfolders or timestamps
> for each run. It can be used with --debug-output. **Useful for CI.**

とあり、いかにも関門向きに読めるが、実測では**成果物が 1 つも生成されない**。

**切り分けの実測**:

| 指定 | 結果 |
| --- | --- |
| `--test-output-dir` のみ | 証跡すべて出る ✅ |
| `--test-output-dir` + `--format JUNIT --output` | 証跡すべて + `report.xml` ✅ |
| `--test-output-dir` + `--flatten-debug-output` | **完全に空** ❌ |

**対処**: 付けない。「毎回同じパスに置きたい」なら、実行後に最新の世代ディレクトリを
symlink するなり、`ls -dt <DIR>/*/ | head -1` で拾うなりする。

## `check-syntax` はディレクトリを受け取らない

**症状**: `maestro check-syntax <dir>` がスタックトレースを吐いて落ちる。

```text
/path/to/e2e/flows (Is a directory)
java.io.FileNotFoundException: /path/to/e2e/flows (Is a directory)
	at maestro.cli.command.CheckSyntaxCommand.call(CheckSyntaxCommand.kt:29)
```

`maestro test` はディレクトリを受け取るので、同じ感覚で渡すと踏む。

**まとめ渡しも駄目。** 引数は**ちょうど 1 ファイル**しか取らないので、
`find ... -exec maestro check-syntax {} +` や `xargs`（`-n1` なし）は別の形で落ちる。

```text
Unmatched argument at index 2: 'e2e/flows/smoke.yaml'
Usage: maestro check-syntax <file>
```

**対処**: ファイルごとに回す（`-n1` / `{} \;` を忘れない）。

```bash
find e2e/flows -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 |
  xargs -0 -n1 maestro check-syntax
```

不正な Flow に対しては**正しく非 0 を返す**ので、関門としては使える。

## `maestro start-device --platform android` は対話プロンプトを出す

**症状**: フックの中から呼ぶと止まる、あるいは何もせず終わる。

**原因**: 必要な system image が無いと標準出力に

```text
The required system image system-images;android-34;google_apis;arm64-v8a is not installed.
Would you like to install it? y/n
```

を出して入力を待つ。**git hook は stdin が端末ではない**ので、ここが破綻する。

**さらに悪いこと**: Maestro は `google_apis` を名指しで要求する。手元に
`google_apis_playstore;arm64-v8a` があっても**別物として扱い、再利用しない**。
つまり数 GB のダウンロードが始まる。

**対処**: AVD は人間が `avdmanager` で一度だけ作る（`setup.md`）。フックは
`emulator -avd <名前>` で起動するだけにする。**iOS では起きない** — シミュレータは
既存の定義から起動でき、巨大なダウンロードを伴わないので `start-device` を使ってよい。

## 成功した Flow は screenshot を 1 枚も残さない

**症状**: 通ったのに証跡が無い。

**原因**: Maestro が自動で撮るのは**失敗したステップだけ**。仕様。

**対処**: Flow の中に `takeScreenshot: <名前>` を明示的に置く。「この画面が出ていること」を
人が見て確かめたいポイントに置くとよい。

## `tapOn` は要素の中心を叩く — 縁の要素で「成功したのに何も起きない」

**症状**: `Tap on id: xxx... COMPLETED` と出るのに、UI は何も変わらない。
落ちるのは**数手先**の `assertVisible` なので、原因が離れていて見つけにくい。

```text
Tap on id: marker_0_0... COMPLETED       ← 成功扱い。だが選択されていない
Take screenshot 02-selected... COMPLETED
Tap on "送信"... COMPLETED                ← ボタンは無効のまま。これも成功扱い
Assert that ".*結果.*" is visible... FAILED           ← ここで初めて落ちる
```

**Maestro は要素の中心座標を計算し、そこをタップする。** 要素が「見えている」ことと
「その中心が当たり判定の中にある」ことは別なので、両者がズレると成功したまま空振りする。

**原因の典型**: 親からはみ出して描画されている要素。Flutter なら
`Stack(clipBehavior: Clip.none)` の上に `Positioned(top: y - size/2)` で置いたもの。
`Clip.none` は**描画のクリップを外すだけで、ヒットテストは親の矩形で止まる**。
グリッドの縁に置いた要素は、中心がちょうど親の境界線に乗る。

さらに **Maestro は中心座標を整数に切り捨てる**。境界が `x=31.5` なら `31` を叩くので、
**半ピクセルだけ外側**に落ちてヒットしない。

> [!IMPORTANT]
> **上端・左端だけが死ぬ。下端・右端は当たる。** 切り捨ての向きが、
> 上/左では外へ、下/右では内へ転ぶため。この非対称が犯人捜しを狂わせる。

実測（格子状に並ぶ 54 個のタップ対象 / 1080×2400 / Maestro 2.8.0）:
中心タップが効かないのは 5 個だけで、**すべて上端（3 個）と左端（2 個）**だった。
残り 49 個はそのまま当たる。

**切り分け**: 落ちたステップの `screen-hierarchy/*.json` に要素の `bounds` が入っている。
中心座標を出し、親の描画領域と突き合わせる。`clickable=true` でも当たらないことがあるので、
**属性だけ見て「掴めているから大丈夫」と判断しない。**

```python
# bounds="[312,795][361,844]" → 中心 (336, 819)。親の上端が 819.5 なら外れている
cx, cy = (x1 + x2) // 2, (y1 + y2) // 2   # Maestro と同じく切り捨て
```

**対処は 2 つ。**

1. **Flow 側で縁の要素を避ける**（安い。E2E を通すのが目的ならこれで足りる）
   — 縁でない要素を選び、**なぜそれを選んだかを Flow のヘッダに書く**。
   書かないと、後から「どれでもいいだろう」と縁に戻されて再発する
2. **アプリ側で親に余白を持たせ、要素がはみ出さないようにする**（正しいが、
   レイアウトに触る）。なお**この空振りは実ユーザーにも起きている** —
   縁の要素は上半分／左半分がタップに反応しない。E2E が先に見つけただけで、
   本当は UI のバグであることが多い

## Flutter の `Key` は Maestro から見えない

要素が掴めない話は全部 [platforms.md](platforms.md) にまとめた。**Flutter の `Key` は
アクセシビリティ層に出ないので Maestro からは原理的に見えない**、が最も踏まれやすい。

## java 16 以下だと Maestro は起動しない

**症状**: Maestro が動かない。`brew list` には `openjdk@17` があるのに直らない。

**原因**: brew で入れた JDK が**リンクされておらず**、`java -version` は古いままなことがある。

**対処**: システムの `java` を差し替えるのではなく、`JAVA_HOME="$(brew --prefix openjdk@17)"` を
このスキルの実行時にだけ立てる。古い Gradle など、17 で壊れるものが同居していることがあるため。

## Apple Silicon で x86_64 の system image を選ぶと関門にならない

**症状**: エミュレータが遅すぎて E2E が現実的な時間で終わらない。

**原因**: `x86_64` イメージは Apple Silicon 上でエミュレーションになる。

**対処**: `arm64-v8a` を選ぶ。`ls -d "$ANDROID_HOME"/system-images/*/*/*` で手元にあるものを
確認してから AVD を作る。

## cmdline-tools の XML バージョン警告は無害

```text
Warning: This version only understands SDK XML versions up to 3 but an SDK XML file of
version 4 was encountered.
```

cmdline-tools と SDK 本体のリリース時期のズレ。**AVD の作成は成功する**ので無視してよい。
気になるなら `sdkmanager --install "cmdline-tools;latest"` で更新する。
