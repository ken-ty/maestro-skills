# maestro-skills

**[Maestro](https://maestro.dev/) でモバイル E2E テストを書き、実機・エミュレータ・
シミュレータでの動作確認をローカルに閉じて push 前の関門にする**ための Agent Skill。

Claude Code / Codex / Cursor などのコーディングエージェントに読ませて使う。

> **English**: An agent skill for [Maestro](https://maestro.dev/) mobile E2E testing —
> how to write Flows, and how to run device verification locally as a pre-push gate
> instead of burning CI minutes. Covers Android devices/emulators and iOS simulators,
> independent of the app framework (Flutter / React Native / native).
> Written in Japanese.

## 入れ方

```bash
npx skills add ken-ty/maestro-skills
```

手で入れるなら `skills/maestro/` をそのまま `.claude/skills/maestro/` にコピーすればよい。

## 何が入っているか

`skills/maestro/` の 1 スキル。**SKILL.md は入口だけで、詳細は必要になったときだけ読ませる**
構成にしている。

| ファイル | 内容 |
| --- | --- |
| `SKILL.md` | 最小の Flow、書くときの原則、ローカル関門として回す 6 ステップ |
| `references/flows.md` | 44 コマンドの分類、セレクタ 4 系統、待ち、条件分岐、サブフロー |
| `references/platforms.md` | Flutter / React Native / ネイティブでの要素の掴み方、権限ダイアログ |
| `references/setup.md` | JDK 17 / Android SDK / Maestro / AVD の事前作成 |
| `references/artifacts.md` | 証跡の出力ツリー、実測サイズ、世代管理、PR への貼り方 |
| `references/ci.md` | CI との役割分担、public / private で変わる課金、self-hosted の危険 |
| `references/pitfalls.md` | 実測で見つけた罠 |
| `recipes/pre-push.sh` | pre-push フックの実装 |

## なぜ書いたか

Maestro の書き方を教える資料は既にある。**足りていないのは「書いた Flow をどう回すか」**
だった — 端末をどう用意し、いつ発火させ、出てきた証跡をどう始末するか。
CI の実行分を食う実機 E2E を手元に落とすには、そこが要る。

Maestro 2.8.0 / macOS (Apple Silicon) で実際に回して書いている。ドキュメントからは
読み取れなかったものが `references/pitfalls.md` に入っている。抜粋:

- **`--flatten-debug-output` を付けると証跡が 1 つも出力されない**（ヘルプには "Useful for CI" とある）
- **`maestro start-device --platform android` は `y/n` の対話プロンプトを出す**ので git hook から呼べない
- **成功した Flow は screenshot を 1 枚も残さない**（自動撮影は失敗ステップのみ）
- **スクショ PNG 1 枚 1.14MB に対し動画は約 148KB/秒** — 画像のほうが重い

## 参考にしたもの

- [Maestro 公式ドキュメント](https://docs.maestro.dev/) — コマンドとセレクタの典拠
- [raphaelbarbosaqwerty/maestro-dev-skills](https://github.com/raphaelbarbosaqwerty/maestro-dev-skills)
  （MIT） — 構成の参考にした。本文は引用しておらず、すべて書き下ろし

## ライセンス

MIT
