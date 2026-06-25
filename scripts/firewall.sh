#!/usr/bin/env bash
# ============================================================================
# firewall.sh — egress 牢（ホスト側 / Debian 12）
#
# TODO(prod): これは Linux 本番ホストで適用する締めの作業。macOS お試し中は未適用。
#   本番移行時に `make subnet` → `sudo make firewall SUBNET=...` を必ず実行すること。
#
# 目的: 自己改善エージェントのコンテナから、LAN(RFC1918) とホストへの通信を遮断する。
#       公開インターネット(Sakana API / Discord / Web Fetch)は許可する。
#
# 方式: Docker のフィルタ用チェイン DOCKER-USER に、Hermes 専用ネットワークの
#       subnet 発のトラフィックのうち RFC1918 宛を DROP するルールを入れる。
#       DNS と established/related は許可。
#
# 使い方:
#   1) compose を一度 up して専用ネットワークを作る
#   2) SUBNET を確認:
#        docker network inspect nerdhealth-agent_hermes-net \
#          -f '{{(index .IPAM.Config 0).Subnet}}'
#   3) その値を SUBNET= に入れて、root で実行:
#        sudo SUBNET=172.18.0.0/16 scripts/firewall.sh
#
# 永続化: Debian では iptables-persistent / nftables.service で保存する
#         （再起動・docker 再起動でルールが消えないよう運用に組み込む）。
#
# 注意: 将来 local LLM を別マシン(LAN 上)に置くときは、その 1 ホストだけ
#       DROP より前に ACCEPT 例外を入れる（例: -d 192.168.10.20/32 -j RETURN）。
# ============================================================================
set -euo pipefail

SUBNET="${SUBNET:?コンテナ subnet を SUBNET=... で指定（docker network inspect で確認）}"

# iptables 版（nftables バックエンドでも iptables-nft 経由で動く）
ipt() { iptables -w "$@"; }

# 既存の同等ルールを消してから入れ直す（冪等化）
flush_existing() {
  while ipt -C DOCKER-USER -s "$SUBNET" -d "$1" -j DROP 2>/dev/null; do
    ipt -D DOCKER-USER -s "$SUBNET" -d "$1" -j DROP
  done
}

# --- local LLM の例外（使うときだけコメント解除して IP を入れる） -----------
# ipt -C DOCKER-USER -s "$SUBNET" -d 192.168.10.20/32 -j RETURN 2>/dev/null || \
#   ipt -I DOCKER-USER 1 -s "$SUBNET" -d 192.168.10.20/32 -j RETURN

# --- DNS と established/related は許可（DROP より前に置く） ------------------
ipt -C DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN 2>/dev/null || \
  ipt -I DOCKER-USER 1 -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN

# --- RFC1918(LAN/ホスト) 宛を DROP -----------------------------------------
for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
  flush_existing "$net"
  ipt -A DOCKER-USER -s "$SUBNET" -d "$net" -j DROP
  echo "DROP: ${SUBNET} -> ${net}"
done

echo
echo "適用済み。確認:  iptables -L DOCKER-USER -n --line-numbers"
echo "テスト:  docker compose exec hermes sh -lc 'curl -m5 http://192.168.0.1 ; curl -m5 https://api.sakana.ai'"
echo "         （前者=失敗 / 後者=接続 が期待値）"
