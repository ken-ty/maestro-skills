# CI に何を残すか

**ローカル関門に移す目的は「CI を無くすこと」ではない。** 手元は 1 台・1 バージョンでしか
確かめられず、環境差を吸えない。**関門を手元に、追認を CI に**という二段構えにする。

## 役割分担

| どこで | 何を | なぜ |
| --- | --- | --- |
| **pre-push（手元）** | 実機/仮想デバイスでの E2E、証跡撮影 | 実機が手元にある。private では課金ランナーで最も高い |
| **CI（標準ランナー）** | ビルド・単体テスト・静的解析 | 手元の環境差を吸収する。実機を要さないので軽い |
| **CI（手動トリガー）** | リリース前の全 Flow 通し | 常時回す必要が無い。必要なときに人が押す |

## その前に — public にできないか確かめる

**ここが一番効く。** 実行分の課金は public かどうかで決まる。

| | 課金 |
| --- | --- |
| **public + 標準 GitHub-hosted ランナー** | **無料** |
| self-hosted ランナー | 無料（public / private を問わない） |
| larger runner | **public でも常に課金** |
| private + 標準ランナー | プランの included minutes を消費 |

> "GitHub Actions usage is free for self-hosted runners and for public repositories
> that use standard GitHub-hosted runners."
> — [About billing for GitHub Actions](https://docs.github.com/en/billing/managing-billing-for-your-products/about-billing-for-github-actions)

**public にできるなら、実行分を理由に E2E を削る必要はない。** macOS ランナーも標準ランナー
なので、iOS シミュレータでの E2E を遠慮なく回せる。

**private のときだけ**、以下が効いてくる:

- macOS ランナーは Linux の **10 倍**の倍率で included minutes を消費する
- `if:` で落とした job は **skipped になり課金されない**。トリガーではなく job の条件で切ると
  「必要なときだけ回す」を安く実現できる

## self-hosted ランナーを public リポジトリで使わない

課金は 0 になるが、**public リポジトリと組み合わせてはいけない。**

> "We recommend that you only use self-hosted runners with **private** repositories.
> This is because forks of your public repository can potentially run **dangerous code**
> on your self-hosted runner machine by creating a pull request that executes the code
> in a workflow."
> — [Adding self-hosted runners](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners)

fork から PR を投げるだけで、そのマシンで任意のコードが動く。**自宅や社内の共有機なら
なおさら。** 共有機を使う場合は、そもそも自分の一存で決められるのかも確かめること。

## private リポジトリでの型

**フィーチャーブランチのうちは手元で回し、main に入ったときだけ CI が回る。**

```yaml
on:
  push:
    branches: [main]
  workflow_dispatch:      # 手動確認の逃げ道は残す
```

担保は pre-push フック（`../recipes/pre-push.sh`）。**意志では守れないので仕組みにする。**

重い E2E をラベルで呼び出す形にするなら、**トリガーではなく job の `if` で落とす**:

```yaml
jobs:
  e2e:
    if: >-
      github.event_name != 'pull_request' ||
      (github.event.pull_request.draft == false &&
       contains(github.event.pull_request.labels.*.name, 'e2e'))
```

`pull_request` の `types` に **`labeled` を足しておく**こと。既定には含まれないので、
無いと「後からラベルを付けたのに回らない」になる。

## CI で Maestro を回すとき

```yaml
- name: Install Maestro
  run: |
    curl -fsSL "https://get.maestro.mobile.dev" | bash
    echo "$HOME/.maestro/bin" >> "$GITHUB_PATH"
```

- **バージョンを固定する。** `MAESTRO_VERSION=<version>` を付けないと latest を引き、
  ある日突然壊れる
- **Java 17 以上**が要る。`actions/setup-java` で明示する
- `--format JUNIT --output` でレポートを出し、テスト結果として表示させる
- **`--flatten-debug-output` を付けない**（証跡が消える。[pitfalls.md](pitfalls.md)）
- 証跡は `actions/upload-artifact` で上げる。**`retention-days` を短く**しないとストレージを食う
