# nerdhealth-agent — 運用ショートカット
#   docker compose のサービス名は hermes。compose プロジェクト名はこのディレクトリ名(nerdhealth-agent)。
#   使い方:  make            # ヘルプ
#            make seed / make up / make logs ...

COMPOSE := docker compose
SERVICE := hermes
NET     := nerdhealth-agent_hermes-net
UNIT_DIR := $(HOME)/.config/systemd/user

.DEFAULT_GOAL := help

.PHONY: help
help: ## このヘルプを表示
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

# --- ライフサイクル ---------------------------------------------------------
.PHONY: init
init: ## 初期化: host.env生成 + HDDバックアップ先作成 + seed（初回これ1つ・sudo不要）
	@if [ -f host.env ]; then \
	  echo "skip  : host.env は既存（編集して使う）"; \
	else \
	  cp host.env.example host.env; \
	  echo "create: host.env を作成（BACKUP_DIR / KEEP を実値に編集すること）"; \
	fi
	@. ./host.env; mkdir -p "$$BACKUP_DIR" && echo "ensure: $$BACKUP_DIR"
	scripts/seed.sh

.PHONY: seed
seed: ## 種(SOUL.md/config.yaml)を ./data へコピー（既存は上書きしない）
	scripts/seed.sh

.PHONY: up
up: ## 起動（バックグラウンド）
	$(COMPOSE) up -d

.PHONY: down
down: ## 停止・コンテナ削除（./data は残る）
	$(COMPOSE) down

.PHONY: restart
restart: ## 再起動
	$(COMPOSE) restart $(SERVICE)

.PHONY: ps
ps: ## 状態表示
	$(COMPOSE) ps

.PHONY: logs
logs: ## ログ追従（Ctrl-C で抜ける）
	$(COMPOSE) logs -f $(SERVICE)

.PHONY: pull
pull: ## イメージ更新（更新後は make up で再作成）
	$(COMPOSE) pull

# --- 操作 -------------------------------------------------------------------
.PHONY: setup
setup: ## 初回セットアップウィザード（Discord等の連携を有効化。1回だけ・対話）
	$(COMPOSE) run --rm $(SERVICE) setup

.PHONY: chat
chat: ## コンソールで Hermes と対話（ターミナルUI・Ctrl-C で抜ける）
	$(COMPOSE) exec $(SERVICE) hermes

.PHONY: shell
shell: ## コンテナ内シェルに入る
	$(COMPOSE) exec $(SERVICE) sh

.PHONY: hermes
hermes: ## 任意の hermes コマンド。例: make hermes ARGS="cron list"
	$(COMPOSE) exec $(SERVICE) hermes $(ARGS)

.PHONY: cron-list
cron-list: ## 登録済み cron ジョブ一覧
	$(COMPOSE) exec $(SERVICE) hermes cron list

# --- 安全境界 / バックアップ -----------------------------------------------
.PHONY: subnet
subnet: ## コンテナネットワークの subnet を表示（firewall 用）
	docker network inspect $(NET) -f '{{(index .IPAM.Config 0).Subnet}}'

.PHONY: firewall
firewall: ## egress 牢を適用。例: sudo make firewall SUBNET=172.18.0.0/16
	sudo SUBNET=$(SUBNET) scripts/firewall.sh

.PHONY: backup
backup: ## ./data をバックアップ（停止→tar→再開）
	scripts/backup.sh

.PHONY: restore
restore: ## バックアップから復元。例: make restore FILE=backups/xxx.tar.gz
	scripts/restore.sh $(FILE)

.PHONY: backup-timer
backup-timer: ## 夜間自動バックアップ(systemd user timer)を導入・有効化
	mkdir -p "$(UNIT_DIR)"
	sed 's|@WORKDIR@|$(CURDIR)|g' systemd/nerdhealth-backup.service > "$(UNIT_DIR)/nerdhealth-backup.service"
	cp systemd/nerdhealth-backup.timer "$(UNIT_DIR)/nerdhealth-backup.timer"
	systemctl --user daemon-reload
	systemctl --user enable --now nerdhealth-backup.timer
	@echo "ok: 確認は  systemctl --user list-timers | grep nerdhealth-backup"
	@echo "   未ログインでも動かすには一度だけ:  sudo loginctl enable-linger $$USER"
