# 証跡の出方・サイズ・始末

## 出力ツリー

`maestro test --test-output-dir <DIR>` を付けると、`<DIR>/<日時>/<Flow名>/` の下に出る。

```text
<DIR>/2026-08-26_052903/smoke/
├── manifest.json          # 全成果物の索引（$schema つき）
├── commands.json          # 1 ステップ 1 エントリ。status / duration / artifacts
├── logs/
│   ├── maestro.log
│   ├── device-logcat.txt        # Android。iOS は device-simulator.log / device-xctest.log
│   ├── crash-report.txt         # クラッシュしたときだけ
│   └── anr-report.txt           # Android で ANR が出たときだけ
├── screenshots/           # ★ 失敗したステップだけ。成功した Flow では存在しない
├── screen-hierarchy/      # 失敗ステップの view 階層 JSON。セレクタが当たらない原因調べ用
├── takeScreenshot/        # ★ Flow が takeScreenshot で撮ったもの
└── startRecording/        # ★ Flow が startRecording で録ったもの
```

> **成功した Flow は `screenshots/` を作らない。** 「成功時も証跡を残す」には Flow の中に
> `takeScreenshot` を自分で置く。これを知らないと「成功したのに何も残らない」で悩む。

## manifest.json の読み方と、その限界

```json
{
  "$schema": "https://storage.googleapis.com/maestro-schemas/artifact-manifest/v1.schema.json",
  "entries": [
    { "kind": "MAESTRO_LOG",   "format": "TXT", "relativePath": "logs/maestro.log", "sizeBytes": 32735 },
    { "kind": "START_SCREEN_RECORDING", "format": "MP4", "relativePath": "startRecording", "count": 1 },
    { "kind": "TAKE_SCREENSHOT",        "format": "PNG", "relativePath": "takeScreenshot", "count": 1 }
  ]
}
```

> [!IMPORTANT]
> **フォルダ単位のエントリ（`takeScreenshot` / `startRecording` / `screenshots`）は `count` しか
> 持たず、`sizeBytes` が無い。** つまり「manifest を見れば重さが分かる」は成り立たない。
> **サイズで足切りしたいなら実ファイルを `find` / `stat` で測る。**
> `sizeBytes` を持つのは単一ファイルのエントリ（ログ・`commands.json`）だけ。

`commands.json` は 1 ステップ 1 エントリで `status` / `duration` / `sequenceNumber` / `artifacts` を持つ。
**どのステップがどのファイルを産んだか**はこちらにしか無い（manifest には無い）。

## 実測サイズ — 重いのは動画ではなく画像

Android エミュレータ（Pixel 6 相当・1080×2400）での実測:

| 種類 | サイズ | 換算 |
| --- | --- | --- |
| `takeScreenshot` の PNG | **1.14 MB / 枚** | — |
| 同じものを幅 540 の JPEG へ | **19.8 KB** | **1/57** |
| `startRecording` の MP4 (h264) | 245 KB / 1.65 秒 | **約 148 KB/秒** |

**直感に反するが、スクリーンショット 1 枚は動画 8 秒分より重い。** PNG は無圧縮に近く、
Maestro の録画は h264 で既によく効いているため。

導かれる方針:

- **動画に ffmpeg の再エンコードをかける意味は薄い。** 効くのは**長さを短くすること**
  （148 KB/秒 なので、1 Flow 30 秒なら約 4.4 MB）
- **画像は貼る前に必ず縮小する。** 素の PNG を PR に貼るのは 1 枚 1 MB を積むということ

```bash
sips -Z 540 -s format jpeg "<元.png>" --out "<軽量.jpg>"     # macOS 標準。追加依存なし
```

## 置き場と世代管理

**リポジトリにコミットしない。** 証跡は毎回の実行で増え続けるので、追跡すると履歴が肥大する。

```text
.artifacts/device-gate/<日時>/...
```

`.gitignore` に `.artifacts/` を足す。**そのうえで、放っておくとディスクを食い潰す**ので、
実行のたびに古い世代を捨てる。3 つの上限のどれかに当てれば十分:

```bash
ROOT=.artifacts/device-gate

# (a) 直近 N 世代だけ残す
ls -dt "$ROOT"/*/ 2>/dev/null | tail -n +11 | xargs -r rm -rf

# (b) N 日より古いものを捨てる
find "$ROOT" -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf {} +

# (c) 合計サイズの上限を超えたら古い順に捨てる
while [ "$(du -sm "$ROOT" 2>/dev/null | cut -f1)" -gt 2048 ]; do
  oldest=$(ls -dt "$ROOT"/*/ 2>/dev/null | tail -1)
  [ -z "$oldest" ] && break
  rm -rf "$oldest"
done
```

**動画はここに置いたまま。** 見返すのは自分だけで、GitHub へ運ぶ理由が無い。
必要になったらローカルのパスを開けばよい。

## PR に画像を貼る

**縮小してから、枚数を絞って貼る。** 全ステップ分を貼ると読む側が追えない。

```bash
# 最新世代の takeScreenshot を軽量化して 1 か所に集める
SRC=$(ls -dt .artifacts/device-gate/*/ | head -1)
mkdir -p .artifacts/for-pr
find "$SRC" -path '*/takeScreenshot/*.png' | while read -r f; do
  sips -Z 540 -s format jpeg "$f" --out ".artifacts/for-pr/$(basename "${f%.png}").jpg" >/dev/null
done
ls -l .artifacts/for-pr
```

貼り方は 2 通り。**どちらも外部への公開になるので、貼る前に中身を見ること**
（テスト用とはいえ、画面に個人情報や検証環境の情報が写り込む）。

- **GitHub の Web UI に drag & drop** — `user-images.githubusercontent.com` へ上がる。リポジトリを
  汚さない。手作業が要る
- **`gh` で本文に含める** — 画像そのものは別途どこかに上げる必要がある。リポジトリにコミットする
  形は避けたいので、実務上は Web UI に貼るほうが素直

> **AI エージェントは、証跡を PR や外部へ上げる前に必ず人間の承認を取る。** 画面の写り込みは
> 撮った本人にしか判断できない。
