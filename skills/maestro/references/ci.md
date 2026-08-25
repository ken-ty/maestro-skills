# CI に何を残すか

> **ここで言う「リポジトリ」は、テストが走る対象＝アプリのリポジトリ**を指す。
> スキルやツールを置いているリポジトリの話ではない。課金も self-hosted の可否も、
> **E2E が実際に走るリポジトリの性質**で決まる。

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

## self-hosted ランナーを使うか

課金は 0（public / private を問わない）。**モバイルの E2E とは相性がよい。**

- macOS ランナーは included minutes を **10 倍**で消費する。iOS シミュレータの E2E を
  丸ごと逃がせる
- **1 台の Mac で Android エミュレータと iOS シミュレータの両方**を賄える
- **実機を USB で繋いだままにできる。** GitHub-hosted では原理的に不可能
- 通信は **outbound のみ**（GitHub へ long-poll する）。受信ポートを開けないので、
  「LAN に何も晒さない」方針のネットワークとも両立する

### 判断軸は public / private ではなく「誰が PR を開けるか」

**ここを取り違えやすい。** self-hosted ランナーは、**workflow を起こせる人全員に、その
マシンでの任意コード実行を許す**のと同じことになる。

> "any user capable of invoking workflows has access to this environment"
> — [Secure use reference](https://docs.github.com/en/actions/reference/security/secure-use)

そのうえで:

| リポジトリ | PR を開けるのは | 判断 |
| --- | --- | --- |
| **public** | **誰でも** | **使わない** |
| private / internal・**read 権限が自分だけ** | 自分だけ | 実質リスクなし。**有力な選択肢** |
| private / internal・**他人にも read がある**（受託、複数人、org 全体） | **read 権限を持つ全員** | 慎重に。下の緩和策が要る |

3 行目を見落とさないこと。GitHub は private でもこう書いている:

> "be cautious when using self-hosted runners on **private or internal** repositories,
> as **anyone who can fork the repository and open a pull request (generally those with
> read access to the repository)** are able to compromise the self-hosted runner
> environment, including gaining access to secrets and the `GITHUB_TOKEN`"
> — [Secure use reference](https://docs.github.com/en/actions/reference/security/secure-use)

public について GitHub の推奨はもっと端的:

> "We recommend that you only use self-hosted runners with **private** repositories.
> This is because forks of your public repository can potentially run **dangerous code**
> on your self-hosted runner machine by creating a pull request that executes the code
> in a workflow."
> — [Adding self-hosted runners](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners)

### 立てる前に確かめること

- [ ] **そのマシンを自分の裁量で変更してよいか。** 共有機や、他人が管理する IaC の配下なら
      承認が要る。「自宅にある」は「自分が管理者である」を意味しない
- [ ] **Xcode と Android SDK が載るか。** 合わせて数十 GB。別用途（Docker サーバー等）と
      同居させてよいかも含めて
- [ ] **常時起動しているか。** ランナーが落ちていると job は失敗せず待ち続ける
- [ ] **同時実行は 1 本になる。** 並列を前提にした workflow は詰まる
- [ ] **secrets がそのマシンに降りる。** ジョブ間で残留させない

### 緩和策

- **ランナーを使い捨てにする。** ジョブごとに環境を捨てれば、前のジョブの残留物を
  次のジョブが拾わない。GitHub は just-in-time (JIT) ランナーを案内している
  （`./run.sh --jitconfig ${encoded_jit_config}`）
- **外部からの PR に承認を要求する。** リポジトリ設定で、初めての貢献者の workflow は
  write 権限者の承認を経てから走るようにできる
- **`pull_request_target` を使わない。** fork のコードを checkout して実行しつつ secrets を
  持つため、最も危険な組み合わせになる

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
