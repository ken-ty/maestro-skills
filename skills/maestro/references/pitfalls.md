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
