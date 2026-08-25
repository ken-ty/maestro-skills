#!/usr/bin/env bash
#
# push する前に、実機/仮想デバイスでの動作確認を手元で回す関門。
#
# 有効化: このファイルをリポジトリの hooks/pre-push に置き
#         git config core.hooksPath hooks
#
# 逃げ道: git push --no-verify
#   使ってよいのは「CI で確かめたい」ときだけ。落ちると分かっているものを通すために
#   使い始めると、関門が形骸化する。
#
# 前提: maestro スキルの references/setup.md を一度済ませてあること。
#       特に AVD は事前に作っておく（このフックは作らない。理由は pitfalls.md）。
set -euo pipefail

# ─── 設定 ────────────────────────────────────────────────────────────────
FLOWS_DIR="e2e/flows"                  # Maestro の Flow を置いているディレクトリ
ARTIFACT_ROOT=".artifacts/device-gate" # 証跡の置き場（.gitignore に入れること）
AVD_NAME="${DEVICE_GATE_AVD:-}"        # 事前に作った AVD 名。空ならエミュ自動起動をしない
TIMEOUT_SEC=600                        # 全体のタイムアウト
KEEP_GENERATIONS=10                    # 証跡を何世代残すか
MAX_ARTIFACT_MB=2048                   # 証跡の合計サイズ上限

# 動作確認を回す対象。ここに当たる変更が無い push はスキップする。
# ドキュメントだけの修正で数分待たされると --no-verify が日常化するため。
WATCH_PATTERN='^(lib/|src/|app/|ios/|android/|e2e/|pubspec\.yaml|package\.json|build\.gradle)'
# ─────────────────────────────────────────────────────────────────────────

zero='0000000000000000000000000000000000000000'
repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

# stdin は "<local_ref> <local_sha> <remote_ref> <remote_sha>" の並び。
ranges=()
while read -r _local_ref local_sha _remote_ref remote_sha; do
  [ "$local_sha" = "$zero" ] && continue          # ブランチ削除は検証しない
  if [ "$remote_sha" = "$zero" ]; then
    ranges+=("origin/main..$local_sha")           # 新しいブランチ
  else
    ranges+=("$remote_sha..$local_sha")
  fi
done
[ ${#ranges[@]} -eq 0 ] && exit 0

changed="$(for r in "${ranges[@]}"; do git diff --name-only "$r" 2>/dev/null || true; done | sort -u)"
if ! printf '%s\n' "$changed" | grep -qE "$WATCH_PATTERN"; then
  echo "device-gate: アプリのコードに変更が無いのでスキップします"
  exit 0
fi

# git がフックに渡す GIT_* を消す。これが残っていると、フックから起動した
# ビルドツールが「フック実行中のリポジトリ状態」を引き継いで誤動作する。
for v in $(env | sed -n 's/^\(GIT_[A-Z_]*\)=.*/\1/p'); do unset "$v"; done

# ─── 道具の場所 ──────────────────────────────────────────────────────────
export JAVA_HOME="${JAVA_HOME:-$(brew --prefix openjdk@17 2>/dev/null || true)}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$JAVA_HOME/bin:$HOME/.maestro/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

need() {
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "device-gate: $1 が見つかりません。セットアップは maestro スキルの references/setup.md" >&2
  return 1
}
need maestro || exit 1
need adb || exit 1

# ─── まず構文だけ検査する（デバイス不要・数秒） ──────────────────────────
# 壊れた Flow のためにエミュレータを起動して数分待つのは無駄なので、先に落とす。
# check-syntax は不正なコマンドを見つけると非 0 で終わる。
if ! maestro check-syntax "$FLOWS_DIR"; then
  echo "device-gate: Flow の構文が不正です。上の指摘を直してください" >&2
  exit 1
fi

# ─── デバイスを確保する ──────────────────────────────────────────────────
booted_android() { adb devices | awk 'NR>1 && $2=="device" {print $1; exit}'; }

device="$(booted_android)"

if [ -z "$device" ]; then
  if [ -z "$AVD_NAME" ]; then
    cat >&2 <<'MSG'
device-gate: 実機も起動中のエミュレータもありません。

  実機を繋ぐか、AVD を作って DEVICE_GATE_AVD に名前を渡してください:
    avdmanager list avd
    export DEVICE_GATE_AVD=<AVD名>

  AVD がまだ無い場合の作り方は maestro スキルの references/setup.md
MSG
    exit 1
  fi

  if ! avdmanager list avd 2>/dev/null | grep -q "Name: $AVD_NAME$"; then
    echo "device-gate: AVD '$AVD_NAME' がありません。references/setup.md の手順で作ってください" >&2
    exit 1
  fi

  echo "device-gate: エミュレータ '$AVD_NAME' を起動します"
  "$ANDROID_HOME/emulator/emulator" -avd "$AVD_NAME" \
    -no-window -no-audio -no-snapshot -no-boot-anim >/dev/null 2>&1 &
  emulator_pid=$!
  # このフックが起動したエミュレータは、このフックが片付ける。
  trap 'kill "$emulator_pid" 2>/dev/null || true' EXIT

  waited=0
  until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    sleep 3; waited=$((waited + 3))
    if [ "$waited" -ge 180 ]; then
      echo "device-gate: エミュレータが 180 秒で起動しませんでした" >&2
      exit 1
    fi
  done
  device="$(booted_android)"
fi

echo "device-gate: $device で動作確認します"

# ─── 回す ────────────────────────────────────────────────────────────────
out="$ARTIFACT_ROOT/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out"

# macOS には timeout(1) が無いので perl の alarm で代用する。
run_with_timeout() {
  local secs="$1"; shift
  perl -e 'my $s=shift; my $p=fork; if($p==0){exec @ARGV or exit 127}
           $SIG{ALRM}=sub{kill "TERM",$p; exit 124}; alarm $s; waitpid $p,0; exit $?>>8' "$secs" "$@"
}

# --flatten-debug-output は付けないこと。証跡が 1 つも出なくなる（pitfalls.md）。
status=0
run_with_timeout "$TIMEOUT_SEC" \
  maestro test "$FLOWS_DIR" \
    --udid "$device" \
    --test-output-dir "$out" \
    --format JUNIT --output "$out/report.xml" || status=$?

# ─── 証跡を始末する ──────────────────────────────────────────────────────
ls -dt "$ARTIFACT_ROOT"/*/ 2>/dev/null | tail -n "+$((KEEP_GENERATIONS + 1))" | xargs -r rm -rf
while [ "$(du -sm "$ARTIFACT_ROOT" 2>/dev/null | cut -f1 || echo 0)" -gt "$MAX_ARTIFACT_MB" ]; do
  oldest="$(ls -dt "$ARTIFACT_ROOT"/*/ 2>/dev/null | tail -1)"
  [ -z "$oldest" ] && break
  rm -rf "$oldest"
done

if [ "$status" -eq 124 ]; then
  echo "device-gate: ${TIMEOUT_SEC}s でタイムアウトしました。証跡: $out" >&2
  exit 1
elif [ "$status" -ne 0 ]; then
  echo "device-gate: 動作確認が失敗しました。証跡: $out" >&2
  echo "  失敗したステップの画面は $out/*/*/screenshots/ にあります" >&2
  exit "$status"
fi

echo "device-gate: 通りました。証跡: $out"
