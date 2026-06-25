# nerdhealth-agent

生活習慣改善（ストレートネック・首こり肩こり・脂肪肝・運動不足）を **継続** するための、
自分専用 AI コーチ **nerdhealth-agent**。Discord で毎日伴走し、週次でログを振り返ってメニューを見直す。
中身のエンジンは Hermes Agent。

- **エージェント本体**: [Hermes Agent](https://hermes-agent.nousresearch.com/)（Nous Research / `nousresearch/hermes-agent`）。
  記憶・スキル・cron を自前で持ち、使いながら自分で workflow を組み立て改善する「育つエージェント」。
- **このリポジトリ**: Hermes 本体ではなく **「Hermes を運用する設定」** を管理する。
- **方針**: 問診項目や SQLite スキーマを人間が事前設計せず、最小限（種＋お金＋安全境界＋インフラ）だけ決めて
  あとは Hermes に委ね、週次レビューで軌道修正する＝**「種を蒔いて放つ」**。

設計の経緯と判断は `memo.txt`（初期構想）と計画ファイルを参照。

## 構成

| 要素 | 内容 |
|---|---|
| LLM | **Sakana Fugu**（定額・OpenAI 互換 `https://api.sakana.ai/v1`、model `fugu`）。`config/config.yaml` の custom provider で接続 |
| 対話面 | **Discord のみ**（Obsidian/Notion へは出さない） |
| 記憶・記録 | Hermes が所有。定性=native メモリ(markdown) / 定量=Hermes が自分で作る SQLite。すべて `./data` |
| 日々 | 夕方・夜の cron 催促（未完了なら声かけ、「あとで」→再催促、「休む」→受容して翌日へ） |
| 週次 | cron が SQLite を集計し「今週こんなにやったよ」サマリを Discord へ＋必要ならメニュー見直し |
| 安全境界 | egress 牢（LAN/ホスト遮断）+ `cap_drop` + `no-new-privileges` + リソース制限 |

```
nerdhealth-agent/
├── Makefile             # 運用ショートカット（引数なし make でヘルプ）
├── compose.yml          # Hermes サービス定義
├── .env.example         # 秘密のひな形（cp して .env を作る）
├── prompts/SOUL.md      # ★種：コーチの役割・関わり方・記録方針・ガードレール
├── config/
│   ├── config.yaml      # provider:custom / base_url / model:fugu の種
│   └── cron/jobs.md     # cron は基本 Hermes が自分で作る／これは再現用の fallback
├── scripts/
│   ├── seed.sh          # 種を ./data へ初回コピー（既存は上書きしない）
│   ├── backup.sh        # ./data を安全に退避（SQLite 整合性に配慮）
│   ├── restore.sh
│   └── firewall.sh      # egress 牢（ホスト側 iptables/nftables）
└── data/                # ← /opt/data の実体。git 管理しない（記憶/SQLite/鍵/cron）
```

## セットアップ（Debian 12 / Mac mini 上）

コマンドは Makefile に集約してある（引数なしの `make` でヘルプ）。

```bash
# 1) 秘密と種を用意
cp .env.example .env
$EDITOR .env          # Sakana の API キー、ダッシュボード Basic 認証を設定
make seed             # prompts/SOUL.md と config/config.yaml を ./data へ

# 2) 起動（context_length 64k が Fugu に受理されるかログで確認）
make up
make logs

# 3) Discord を接続（対話・1回だけ。トークンは ./data に永続）
make connect

# 4) スケジュール（催促・週次サマリ）は Hermes 自身に作らせる
#    Discord でこう頼むだけ：
#      「毎日18時と20時半に、まだ運動してなければ催促して。日曜20時に週次サマリを送って」
#    → Hermes が cronjob ツールで自分で登録・調整する。
make cron-list        # 登録状況の確認
#    ※決定的に再現したい場合だけ config/cron/jobs.md の hermes cron create を使う

# 5) egress 牢（root で）
make subnet                          # コンテナの subnet を確認
sudo make firewall SUBNET=<上の値>   # 例: sudo make firewall SUBNET=172.18.0.0/16

# 6) 日次バックアップを host cron に登録
#    0 4 * * *  cd /path/to/nerdhealth-agent && make backup >> backups/backup.log 2>&1
```

## 動作確認（end-to-end）

1. Discord で 1 通送って応答が返る → Sakana Fugu に OpenAI 互換経由で到達できている。
2. 夕方 cron を手動発火し催促が来る。「やった」と返信 → `./data` の SQLite に記録されることを確認。
   「あとで」「今日は休む」で再催促/受容の振る舞いを確認。
3. 週次サマリ cron を手動発火 → Discord に前向きサマリが届く。
4. egress テスト: `docker compose exec hermes sh -lc 'curl -m5 http://192.168.0.1; curl -m5 https://api.sakana.ai'`
   → 前者失敗 / 後者接続。
5. `scripts/backup.sh` → `scripts/restore.sh <tar.gz>` の往復で `./data` が復元できる。

## 運用メモ

- **`./data` は唯一の資産**。失うと全履歴が消える。`backup.sh` を必ず回す。
- イメージは本番では `:latest` をやめて具体バージョンに固定する。
- `cap_drop: ALL` で起動に失敗したら、ログを見て不足 cap だけ `cap_add` で戻す。
- 将来 local LLM を別マシンに用意する場合: `config/config.yaml` の `base_url` を差し替え、
  `firewall.sh` でそのホスト 1 台だけ egress 例外許可する。
