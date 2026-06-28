#!/usr/bin/env bash
# ============================================================================
# reseed.sh — 稼働中デプロイへ「種」(SOUL.md / config.yaml) を再投入する。
#
# ./data は make up（コンテナ起動）時に hermes イメージの s6 が uid 10000 所有・700 に
# 変える。そのためホストユーザーからは直接 cp できない（seed.sh は初回=ホスト所有時専用）。
# ここでは ./data の「現所有者」を引き継いで sudo install で上書きし、Hermes を再起動して
# 種を再読込させる。tree 全体の chown はしない＝ダウンタイム最小・所有の食い違いも作らない。
#
# ★ data/.env は絶対に触らない（鍵・/sethome が書いた行の保護）。
#
# 使い方:   scripts/reseed.sh        （= make reseed）
# ============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -e data ]]; then
  echo "ERROR: data/ が無い。初回は make init / make seed を先に実行すること。" >&2
  exit 1
fi

# ./data の現所有者(=コンテナ uid)を取得。親(リポジトリ直下)はホスト所有なので
# data/ が 700 でも stat はできる（GNU/BSD 両対応）。
uid="$(stat -c '%u' data 2>/dev/null || stat -f '%u' data)"
gid="$(stat -c '%g' data 2>/dev/null || stat -f '%g' data)"

echo "reseed: data/ 所有 uid=$uid gid=$gid を引き継いで SOUL.md / config.yaml を上書きする"

# install -o は coreutils の版によって数値 UID を名前として解決しようとし
# "invalid user 10000" で失敗する。名前解決を避け、cp で上書き → 数値指定が
# 確実な chown で所有者を合わせる（dst が新規なら root 所有になるのを chown で直す）。
reseed_file() {  # src dst
  local src="$1" dst="$2"
  sudo cp "$src" "$dst"
  sudo chown "$uid:$gid" "$dst"
  sudo chmod 644 "$dst"
  echo "seeded: $src -> $dst"
}

reseed_file prompts/SOUL.md    data/SOUL.md
reseed_file config/config.yaml data/config.yaml

# Hermes に種を再読込させる（SOUL.md は session 開始時に system prompt へ注入される）。
echo "restart: Hermes を再起動して種を再読込する"
docker compose restart hermes

echo
echo "完了。反映確認は make logs。data/.env は変更していない。"
