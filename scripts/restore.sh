#!/usr/bin/env bash
# ============================================================================
# restore.sh — backup.sh が作った tar.gz から ./data を復元する。
#
# 使い方:   scripts/restore.sh backups/hermes-data-YYYYmmdd-HHMMSS.tar.gz
#
# 既存の ./data は data.bak-<時刻> に退避してから復元する（誤操作の保険）。
# ============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

ARCHIVE="${1:-}"
if [[ -z "$ARCHIVE" || ! -f "$ARCHIVE" ]]; then
  echo "usage: scripts/restore.sh <backup.tar.gz>" >&2
  echo "available:" >&2
  ls -1t backups/hermes-data-*.tar.gz 2>/dev/null >&2 || true
  exit 1
fi

# 安全のため停止
if docker compose ps --status running 2>/dev/null | grep -q hermes; then
  echo "stopping hermes..."
  docker compose stop hermes
fi

if [[ -d data ]]; then
  BAK="data.bak-$(date +%Y%m%d-%H%M%S)"
  echo "moving existing data -> ${BAK}"
  mv data "$BAK"
fi

echo "restoring from ${ARCHIVE} ..."
tar xzf "$ARCHIVE"          # アーカイブは data/ を含む構成

echo "done. 'docker compose up -d' で再開できる。"
