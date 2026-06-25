# cron ジョブ定義（種）

Hermes の cron は `~/.hermes/cron/jobs.json`（= `/opt/data/cron/jobs.json`）に保存される。

**基本は Hermes 自身に作らせる**（`SOUL.md` にその意図を蒔いてある）。Discord で
「毎日18時と20時半に未完了なら催促して。日曜20時に週次サマリを送って」と頼めば、
Hermes が `cronjob` ツールで自分で登録・調整する。`make cron-list` で確認できる。

以下の `hermes cron create` は **決定的に再現したいとき / 手で確実に入れたいとき** の代替手段。
（`make hermes ARGS="cron create ..."` でも同じ）。

> スケジュールは自然言語(`every 2h` / `at 18:00`)か cron 式が使える。
> 配信先は `discord`(ホームチャンネル) か `discord:#チャンネル名`。
> 制約: **cron 実行の中から新しい cron は作れない**（暴走防止）。だから「あとで」の再催促は
> 動的リマインドではなく、下の **複数チェックポイント** で実現する。

## 1. 夕方の催促チェックポイント

```bash
hermes cron create "at 18:00" \
  "今日まだ運動/ストレッチが記録されていなければ、ユーザーに軽く催促して。'まだやってない？いつやる？' のように。\
今日すでに完了済み、または本人が今日は休むと言っている場合は、何もしないで静かにしていて。" \
  --deliver discord
```

## 2. 夜の催促チェックポイント（再催促）

```bash
hermes cron create "at 20:30" \
  "夕方の声かけのフォロー。今日まだ未完了で、本人が休むと言っていなければ、もう一度だけ優しく催促して。\
'あとで'と言われていたら、いつやるか軽く確認して。完了済み/休む宣言済みなら静かにしていて。" \
  --deliver discord
```

## 3. 週次サマリ＋メニュー見直し

```bash
hermes cron create "sun at 20:00" \
  "今週の活動を SQLite から集計し、前向きなサマリを Discord に届けて。運動回数/ストレッチ回数/歩数の合計、\
先週との比較、頑張れた点。マンネリや行き詰まりが見えたら、ストレートネック・首肩こり・脂肪肝・筋力に効く\
メニューを Web で調べて見直しを提案して。" \
  --deliver discord
```

（週次だけ重いので、必要なら登録後に `model: fugu-ultra` へ寄せる。定額プランが ultra を含むか要確認。）

---

## 将来の最適化: pre-script で「完了済みなら起こさない」

毎チェックポイントで LLM を起こすとトークンを使う。SQLite のスキーマが安定したら、
`/opt/data/scripts/check_today.py` を置き、`{"wakeAgent": false}` を返して完了日の催促を抑止できる。
スキーマは Hermes が自分で作るため、**スキーマ確定後** に導入する（今は agent 判断に任せる）。

```python
# 例（スキーマ確定後に実装）: ~/.hermes/scripts/check_today.py
import json, sqlite3, datetime
# db = sqlite3.connect("/opt/data/<hermesが作ったDBパス>")
# done = db.execute("SELECT 1 FROM activity_log WHERE date = ? AND (exercised=1 OR skipped=1)",
#                    (datetime.date.today().isoformat(),)).fetchone()
# print(json.dumps({"wakeAgent": done is None}))
```
登録時に `--script check_today.py` を付ける（pre-script は `/opt/data/scripts/` に置く）。
