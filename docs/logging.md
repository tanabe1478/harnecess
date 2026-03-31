# Logging

## Overview

harnecess は `harnecess stop` 時にセッション全体のログを保存する。
ログは JSONL 形式で構造化されており、`jq` で分析・フィルタリングが可能。

## 保存タイミング

`harnecess stop` 実行時に自動保存。手動保存の仕組みはない。

## ディレクトリ構造

```
logs/sessions/<session-id>/
├── session.jsonl              # 構造化ログ（JSONL）
├── lead.transcript.txt        # lead ペインの生出力
├── planner.transcript.txt     # planner ペインの生出力
├── builder.transcript.txt     # builder ペインの生出力
├── checker.transcript.txt     # checker ペインの生出力
├── writer.transcript.txt      # writer ペインの生出力
├── queue/                     # queue 状態のスナップショット
│   ├── inbox/                 # 各エージェントの受信箱
│   ├── tasks/                 # タスク定義
│   └── reports/               # 完了レポート
├── plan.yaml                  # 計画ファイル（存在する場合）
└── dashboard.md               # ダッシュボード
```

session-id の形式: `YYYY-MM-DD-<uuid8桁>` (例: `2026-03-31-a1b2c3d4`)

## JSONL エントリ形式

### session.stop

セッション終了時のメタデータ。

```json
{
  "type": "session.stop",
  "time": "2026-03-31T10:00:00Z",
  "session_id": "2026-03-31-a1b2c3d4",
  "agents": ["lead", "planner", "builder", "checker", "writer"]
}
```

### agent.transcript

各エージェントのトランスクリプト情報。

```json
{
  "type": "agent.transcript",
  "time": "2026-03-31T10:00:00Z",
  "session_id": "2026-03-31-a1b2c3d4",
  "agent": "builder",
  "model": "opus",
  "transcript_file": "builder.transcript.txt",
  "line_count": 342
}
```

### snapshot.queue

キューファイルのスナップショット。

```json
{
  "type": "snapshot.queue",
  "time": "2026-03-31T10:00:00Z",
  "session_id": "2026-03-31-a1b2c3d4",
  "files": [
    "queue/inbox/lead.yaml",
    "queue/inbox/builder.yaml",
    "queue/tasks/builder.yaml",
    "queue/reports/builder_report.yaml"
  ]
}
```

### snapshot.plan

計画ファイルのスナップショット。

```json
{
  "type": "snapshot.plan",
  "time": "2026-03-31T10:00:00Z",
  "session_id": "2026-03-31-a1b2c3d4",
  "file": "plan.yaml"
}
```

## jq クエリ例

```bash
# 特定セッションの全エントリ
jq '.' logs/sessions/2026-03-31-a1b2c3d4/session.jsonl

# builder のトランスクリプト情報
jq 'select(.agent == "builder")' logs/sessions/*/session.jsonl

# 全セッションのエージェント一覧（agent名, model, 行数）
jq 'select(.type == "agent.transcript") | {agent, model, line_count}' logs/sessions/*/session.jsonl

# 行数が多い（＝作業量が多い）エージェントを抽出
jq 'select(.type == "agent.transcript" and .line_count > 100) | {session_id, agent, line_count}' logs/sessions/*/session.jsonl

# plan.yaml が保存されたセッションだけ
jq 'select(.type == "snapshot.plan")' logs/sessions/*/session.jsonl

# 特定日のセッション一覧
ls logs/sessions/ | grep "2026-03-31"
```

## トランスクリプトファイル

`*.transcript.txt` は tmux の `capture-pane` で取得した生のペイン出力。
Claude Code の入出力、ツール呼び出し、エラーメッセージ等がそのまま含まれる。

改善分析に使う場合:
- エージェントがどの順序でツールを呼んだか
- ユーザーとの対話内容（lead, planner）
- エラーや差し戻しの発生箇所
- 各エージェントの作業時間の推定（行数から概算）

## gitignore

`logs/` は `.gitignore` に含まれており、リポジトリにはコミットされない。

## 参考

ログ形式は [entireio/cli](https://github.com/entireio/cli) の JSONL ログシステムを参考にしている。
