#!/usr/bin/env bash
# ============================================================================
# seed.sh — リポジトリの「種」(SOUL.md / config.yaml) を ./data へ初回コピーする。
#
# ./data は /opt/data にマウントされ Hermes が読む。Hermes 自身が後から
# SOUL.md / config.yaml を編集して育てるため、**既に存在する場合は上書きしない**。
# 上書きしたいときは --force を付ける。
# ============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

mkdir -p data

copy_seed() {
  local src="$1" dst="$2"
  if [[ -f "$dst" && "$FORCE" -eq 0 ]]; then
    echo "skip  : $dst は既に存在（--force で上書き）"
  else
    cp "$src" "$dst"
    echo "seeded: $src -> $dst"
  fi
}

copy_seed prompts/SOUL.md     data/SOUL.md
copy_seed config/config.yaml  data/config.yaml

# 秘密の置き場は data/.env（Hermes がネイティブに読む）。テンプレを初回だけ置く。
# ★ --force でも data/.env は絶対に上書きしない（鍵や /sethome が書いた行を壊さないため）。
if [[ -f data/.env ]]; then
  echo "skip  : data/.env は既存（鍵保護のため --force でも上書きしない）"
else
  cp .env.example data/.env
  echo "seeded: .env.example -> data/.env（OPENAI_API_KEY 等を実値に編集すること）"
fi

echo
echo "完了。次に data/.env の OPENAI_API_KEY / DISCORD_* を実値に編集すること。"
echo "cron ジョブは config/cron/jobs.md を参照して登録する。"
