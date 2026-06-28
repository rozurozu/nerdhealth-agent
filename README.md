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
├── .env.example         # 秘密のひな形（cp して data/.env を作る）
├── host.env.example     # ホスト固有パスのひな形（cp→host.env：BACKUP_DIR/KEEP 等。秘密は書かない）
├── prompts/SOUL.md      # ★種：コーチの役割・関わり方・記録方針・ガードレール
├── config/
│   ├── config.yaml      # provider:custom / base_url / model:fugu の種
│   └── cron/jobs.md     # cron は基本 Hermes が自分で作る／これは再現用の fallback
├── scripts/
│   ├── seed.sh          # 種を ./data へ初回コピー（既存は上書きしない）
│   ├── backup.sh        # ./data を安全に退避（SQLite 整合性に配慮）
│   ├── restore.sh
│   └── firewall.sh      # egress 牢（ホスト側 iptables/nftables）
├── systemd/             # 夜間バックアップ user timer の雛形（make backup-timer で導入）
└── data/                # ← /opt/data の実体。git 管理しない（記憶/SQLite/鍵/cron）
```

## デプロイ（Ubuntu mac mini・常時稼働 / SSD・HDD）

常時稼働の実機向けの正式手順。SSD と HDD を役割分担する。

**置き場の考え方**

- **live data は SSD**（`/opt/nerdhealth-agent/data`）。中身は SQLite（`state.db`/`kanban.db`）＋記憶＋鍵で
  数十 MB と小さく、SQLite のランダム I/O は回転 HDD が最も苦手。容量も食わないので SSD に置く。
  食事画像などのメディアは**その場で処理して消す**方針なので `data/` は今後も育たない。
- **バックアップは HDD**（`/mnt/hdd/nerdhealth-agent/backups`）。育つ・冷たい・連番という HDD 向きのデータ。
- **symlink は使わない**。`data/` が SSD のリポジトリ直下にある以上、compose の `./data:/opt/data` が
  実体を直接指す。symlink は壊れ・権限・bind-mount 追従という故障モードを足すだけ。HDD へ向けるのは
  backups だけで、それは `host.env` の `BACKUP_DIR`（パス文字列）で指す。

```
SSD  /opt/nerdhealth-agent/          ← git clone（コード/設定・所有は運用ユーザー）
       ├─ data/      →(bind)→ /opt/data   live data・SQLite（symlink無し）
       ├─ data/.env                        秘密（Hermes が読む）
       └─ host.env                         ホスト固有パス: BACKUP_DIR / KEEP / BACKUP_MOUNT
HDD  /mnt/hdd/nerdhealth-agent/
       └─ backups/                          ← make backup / 夜間 timer の退避先（既定30世代）
```

**初回セットアップ（ゼロから起動まで）**

```bash
# 1) 置き場を用意（root 所有の /opt と /mnt/hdd を運用ユーザーに譲る）。HDD は事前に ext4 + fstab 済み前提。
sudo mkdir -p /opt/nerdhealth-agent /mnt/hdd/nerdhealth-agent
sudo chown -R "$USER:$USER" /opt/nerdhealth-agent /mnt/hdd/nerdhealth-agent

# 2) docker グループに入る（未加入なら）→ 反映に一度ログインし直す
sudo usermod -aG docker "$USER"

# 3) clone → 初期化（host.env 生成・HDDバックアップ先作成・data/ seed を一発で）
git clone <repo-url> /opt/nerdhealth-agent
cd /opt/nerdhealth-agent
make init

# 4) パス（host.env）と秘密（data/.env）を実値に編集 → 起動
$EDITOR host.env       # BACKUP_DIR / BACKUP_MOUNT / KEEP（既定でよければ触らなくてよい）
$EDITOR data/.env      # OPENAI_API_KEY(=Sakana) / DISCORD_* / ダッシュボード Basic 認証
make up
make logs

# 5) 夜間バックアップを自動化（任意・推奨）
sudo loginctl enable-linger "$USER"   # 未ログインでも timer を動かす（唯一の sudo）
make backup-timer                     # ~/.config/systemd/user に user timer を導入・有効化
```

**3つの env ファイルの役割（混同しない）**

| ファイル | 用途 | 読む人 |
|---|---|---|
| `data/.env` | **秘密**（APIキー・Discord トークン等） | Hermes（ネイティブに読む） |
| `host.env` | **ホスト固有パス**（BACKUP_DIR / KEEP / BACKUP_MOUNT）。**秘密は書かない** | make / scripts |
| `.env.example` | `data/.env` のひな形 | `make seed` / `make init` がコピー |

> `host.env` をあえて `.env` と名付けないのは、リポジトリ直下の `.env` を docker compose が変数展開で
> 自動的に読むため。秘密の源を `data/.env` 1 本に絞る方針と混同しないよう名前を分けている。

**バックアップ運用**

- 手動: `make backup`（停止→tar→再開で SQLite 整合性を確保） ／ 復元: `make restore FILE=/mnt/hdd/nerdhealth-agent/backups/hermes-data-*.tar.gz`
- 保持世代は `host.env` の `KEEP`（既定 **30**）。新しい順にこの数だけ残し古いものは自動削除。容量は HDD 的に誤差。
- **マウントガード**: `BACKUP_MOUNT`（既定 `/mnt/hdd`）が未マウントなら backup を中止する。HDD が外れた状態で
  OS ディスク側へ書き「退避したつもり」になる事故を防ぐ。
- **off-box 退避**: HDD はこの機体の中。機体ごと壊れると道連れなので、重要なら別所へ
  `rsync -a /mnt/hdd/nerdhealth-agent/backups/ user@host:/backups/` を併用する。

**初回 `make up` 後の確認（uid）**

`./data` 配下はコンテナ内ユーザーの uid で所有される。`ls -ln data/` で uid を確認し、ホストの自分の uid と
ズレていて `make backup` の tar が一部を読めない場合だけ手当する（その backup を `sudo` で回す等）。
多くは uid 1000 同士で一致し無問題。

## セットアップ（手元お試し / Debian 12・Mac mini 上）

> 実機の常時稼働はひとつ上の「デプロイ」節を参照。ここは手元で素早く動作確認するための最小手順。
> コマンドは Makefile に集約してある（引数なしの `make` でヘルプ）。

```bash
# 1) 種と秘密を用意（秘密は data/.env に置く＝Hermesがネイティブに読む唯一の場所）
make seed                  # SOUL.md / config.yaml に加え、data/.env テンプレも初回コピー
$EDITOR data/.env          # OPENAI_API_KEY(=Sakanaキー) / DISCORD_* / ダッシュボードBasic認証 を実値に

# 2) 起動（Bot が数秒で Discord にオンライン。ログで context_length 64k が通るか確認）
make up
make logs
#    ※ 以降 data/.env を直したら反映は `make restart` でよい（down/up 不要）

# 3) スケジュール（催促・週次サマリ）は Hermes 自身に作らせる
#    Discord でこう頼むだけ：
#      「毎日18時と20時半に、まだ運動してなければ催促して。日曜20時に週次サマリを送って」
#    → Hermes が cronjob ツールで自分で登録・調整する。
make cron-list        # 登録状況の確認
#    ※決定的に再現したい場合だけ config/cron/jobs.md の hermes cron create を使う

# 4) egress 牢（root で。※Linux ホスト専用。macOS のお試しでは効かないので省略可）
make subnet                          # コンテナの subnet を確認
sudo make firewall SUBNET=<上の値>   # 例: sudo make firewall SUBNET=172.18.0.0/16

# 5) 日次バックアップを host cron に登録
#    0 4 * * *  cd /path/to/nerdhealth-agent && make backup >> backups/backup.log 2>&1
```

## Discord セットアップ（つまずきポイント）

[Developer Portal](https://discord.com/developers/applications) でアプリ＋Bot を作る。要点はこの4つ：

1. **Bot Token を使う**（Webhook URL ではない）。Bot ページ → Reset Token で取得し `.env` の
   `DISCORD_BOT_TOKEN` に。Webhook は一方通行で会話できない。
2. **Privileged Intents を ON**（Bot ページ → Privileged Gateway Intents）。
   - **Message Content Intent** … 必須。OFF だと `PrivilegedIntentsRequired` で接続失敗＝オフラインになる。
   - Server Members Intent … 通常は不要。intent エラーが続くときだけ ON。
3. **招待スコープは `bot` + `applications.commands` の両方**（OAuth2 → URL Generator）。
   - `applications.commands` が無いと `/sethome` などのスラッシュコマンドが**候補にすら出ない**。
   - Bot Permissions は **View Channels / Send Messages / Read Message History** を付ける
     （Read Message History は会話文脈の読み取り用。推奨）。
   - 生成 URL で自分のサーバーに認可。スコープを足したら `make restart` でコマンド再登録。
4. **`.env` の必須2つ**：`DISCORD_BOT_TOKEN` と `DISCORD_ALLOWED_USERS`（自分の User ID。
   未設定だと安全策で全員拒否）。

**会話の作法**：サーバーのチャンネルでは既定で **@mention したときだけ応答**する
（`DISCORD_REQUIRE_MENTION=true`）。**DM は mention 不要で常に応答**。
proactive（催促・週次サマリ）の投稿先は、対象チャンネルで **`/sethome`** を打つと設定される。

**「1チャンネルで mention 無しに会話／他は無視」にする推奨2点セット**（`.env`）：
- `DISCORD_REQUIRE_MENTION=false` … mention 不要で会話
- `DISCORD_ALLOWED_CHANNELS=<そのチャンネルID>` … 応答をそのチャンネルだけに限定
  （`false` だけだと全チャンネルで暴発するので**セットで必須**）。設定後 `make restart`。

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
- `cap_drop: ALL` で起動に失敗したら、ログを見て不足 cap だけ `cap_add` で戻す。
- 将来 local LLM を別マシンに用意する場合: `config/config.yaml` の `base_url` を差し替え、
  `firewall.sh` でそのホスト 1 台だけ egress 例外許可する。

## 本番（Linux ホスト）移行 TODO

いまは macOS でのお試し構成。常時稼働の Linux 本番ホストへ移すときに **セキュリティを締め直す**。
コード中の該当箇所は `grep -rn "TODO(prod)" .` で一覧できる。

- [ ] **cap を締める** — `compose.yml` の `cap_drop: ALL` ＋最小 `cap_add` を有効化し、起動ログで検証。
      （お試しでコメントアウトしていたら必ず戻す）
- [ ] **egress 牢を適用** — `make subnet` → `sudo make firewall SUBNET=...`（LAN/ホスト遮断。macOS では効かない）
- [ ] **イメージタグ固定** — `:latest` をやめて具体バージョン（例 `:v2026.4.16`）に。
- [ ] **read_only 検討** — `/tmp` `/run` を tmpfs にして root FS を読み取り専用にできるか検証。
- [ ] **常時稼働の担保** — スリープ無効・電源/ネット常時・`restart: unless-stopped`・OS 起動時自動起動。
- [ ] **日次バックアップ** — `make backup-timer`（systemd user timer・夜間04:00）を有効化＋`sudo loginctl enable-linger $USER`。
