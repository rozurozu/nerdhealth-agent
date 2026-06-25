#!/usr/bin/env bash
# ============================================================================
# backup.sh — /opt/data(= ./data) を安全に退避する。
#
# 価値が貯まるのは ./data（SQLite + 育った記憶 + 鍵 + cron）。失うと全履歴が消える。
# 稼働中に丸ごと tar すると SQLite の書き込み途中を掴む恐れがあるため、
# コンテナを一時停止 → tar → 再開 する（数秒のダウンタイムで整合性を確保）。
#
# 使い方:   scripts/backup.sh            # ./backups/ に作る
#           BACKUP_DIR=/mnt/x scripts/backup.sh
# cron 例:  0 4 * * *  cd /path/to/nerdhealth-agent && scripts/backup.sh >> backups/backup.log 2>&1
# ============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

BACKUP_DIR="${BACKUP_DIR:-./backups}"
KEEP="${KEEP:-14}"                       # 直近何世代を残すか
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${BACKUP_DIR}/hermes-data-${STAMP}.tar.gz"

mkdir -p "$BACKUP_DIR"

# 稼働中なら一時停止（停止できなくても続行：その場合は WAL を含めて取得する）
PAUSED=0
if docker compose ps --status running 2>/dev/null | grep -q hermes; then
  echo "pausing hermes for a consistent snapshot..."
  docker compose stop hermes
  PAUSED=1
fi

echo "creating ${OUT} ..."
tar czf "$OUT" data

if [[ "$PAUSED" -eq 1 ]]; then
  echo "restarting hermes..."
  docker compose start hermes
fi

# 古い世代を掃除
ls -1t "${BACKUP_DIR}"/hermes-data-*.tar.gz 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -f

echo "done: ${OUT}"
echo "（任意）off-box へ: rsync -a ${OUT} user@host:/backups/"
