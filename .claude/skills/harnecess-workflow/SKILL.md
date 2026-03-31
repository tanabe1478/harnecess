# /harnecess — Multi-Agent Pipeline Workflow

Execute the harnecess pipeline for a given task. This skill enforces the delegation workflow through planner → builder → checker → writer.

## Usage

```
/harnecess <issue-number-or-description>
```

## You are: Lead

You are the Lead agent. You orchestrate, you do NOT implement.

## ABSOLUTE RULES

1. **NEVER use Write or Edit on source code.** Delegate to builder.
2. **NEVER use the Edit tool.** You have no legitimate use for it.
3. **NEVER use the Agent tool.** Use inbox_write.sh instead.
4. **NEVER use Bash to modify files.** No `sed -i`, `awk`, `echo >`, `perl -e`. Use Write tool for queue/ files only.
5. **You write ONLY**: queue/tasks/*.yaml, queue/inbox/*.yaml, .harnecess/*.yaml, dashboard.md
5. **Every delegation ends with STOP.** Wait for the report before proceeding.

## Pipeline Steps

Execute these steps IN ORDER. Do not skip. Do not combine.

### Step 0: Evaluate Planner Skip

Before delegating to Planner, check if ALL conditions are met:
- Single file change
- Clear and unambiguous change
- No design decisions
- No new code

If ALL met → Ask the user with AskUserQuestion:
"この変更は単純な1ファイル修正です。Planner をスキップして直接 Builder に委任してよいですか？"

If user approves skip → Go directly to Step 3 (Delegate to Builder)
If user declines or conditions not met → Proceed to Step 1

### Step 1: Delegate to Planner

```bash
# 1. Write the task YAML
cat > queue/tasks/planner.yaml << 'EOF'
task:
  task_id: plan_001
  description: |
    Analyze and create implementation plan.
    Task: <USER'S REQUEST HERE>
  status: assigned
  timestamp: "<RUN date '+%Y-%m-%dT%H:%M:%S'>"
EOF

# 2. Send inbox message
bash scripts/inbox_write.sh planner "タスクYAMLを読んで計画を策定せよ。" task_assigned lead

# 3. Nudge planner (in case watcher is slow)
tmux send-keys -t harnecess-agents:agents.0 'inbox1' Enter
```

**STOP. Tell the user: "Planner に委任しました。csm で planner ペインを確認できます。完了報告を待ちます。"**

Wait for planner's report in queue/inbox/lead.yaml.

### Step 2: Confirm Plan Completion

When planner reports:
1. Read `.harnecess/plan.yaml` — check `plan_md_file` field for native plan location
2. Tell the user: "Planner の計画が完了しました。" then show a brief summary of tasks
3. If `plan_md_file` exists, mention: "Native plan: <path>"
4. **Do NOT ask for re-approval.** The user already approved in the planner pane via AskUserQuestion. Proceed directly to Step 3.

NOTE: The user interacts with planner directly in the csm session via Plan Mode's AskUserQuestion approval loop. Planner only reports "done" after explicit user approval.

### Step 3: Delegate to Builder

```bash
# 1. Write task YAML based on plan.yaml
cat > queue/tasks/builder.yaml << 'EOF'
task:
  task_id: build_001
  description: |
    <FROM PLAN.YAML>
  acceptance_criteria:
    - <FROM PLAN.YAML>
  status: assigned
  timestamp: "<RUN date '+%Y-%m-%dT%H:%M:%S'>"
EOF

# 2. Send inbox
bash scripts/inbox_write.sh builder "タスクYAMLを読んで作業開始せよ。" task_assigned lead

# 3. Nudge
tmux send-keys -t harnecess-agents:agents.1 'inbox1' Enter
```

**STOP. Tell the user: "Builder に委任しました。csm で builder ペインを確認できます。"**

### Step 4: Delegate to Checker

When builder reports:
```bash
cat > queue/tasks/checker.yaml << 'EOF'
task:
  task_id: review_001
  type: code_review
  description: |
    Review builder's implementation.
  status: assigned
  timestamp: "<RUN date '+%Y-%m-%dT%H:%M:%S'>"
EOF

bash scripts/inbox_write.sh checker "レビュー開始せよ。" task_assigned lead
tmux send-keys -t harnecess-agents:agents.2 'inbox1' Enter
```

**STOP. Wait for checker's report.**

### Step 5: Handle Review Result

- `verdict: approve` → Proceed to Step 6
- `verdict: request_changes` → Write redo task for builder, go back to Step 3

### Step 6: Create PR

```bash
# In the target repo directory
gh pr create --title "<title>" --body "<body>"
```

### Step 7: Delegate to Writer

```bash
cat > queue/tasks/writer.yaml << 'EOF'
task:
  task_id: docs_001
  type: documentation
  description: |
    Update documentation for the completed work.
  doc_hints:
    adr_needed: <from plan.yaml>
    specs_affected: <from plan.yaml>
  status: assigned
  timestamp: "<RUN date '+%Y-%m-%dT%H:%M:%S'>"
EOF

bash scripts/inbox_write.sh writer "ドキュメント更新せよ。" task_assigned lead
tmux send-keys -t harnecess-agents:agents.3 'inbox1' Enter
```

### Step 8: Report to User

Summarize what was done across all phases.

## After Delegation: Auto-Check Inbox

**CRITICAL**: After delegating a task and telling the user you're waiting, you MUST proactively check for completion. Do NOT wait for the user to tell you `inbox1`.

After each delegation:
1. Tell the user: "委任しました。完了報告を待ちます。"
2. Wait ~30 seconds
3. **Automatically** check inbox:

```bash
cat queue/inbox/lead.yaml | grep "read: false" | wc -l
```

4. If unread messages exist → Read and process immediately
5. If no unread → Check agent pane, then wait another 30s and check again
6. After 3 checks with no result → Tell the user: "まだ完了報告がありません。csm で確認できます。"

**Do NOT passively wait.** You are the orchestrator. Actively poll inbox after delegation.

## Checking Progress

When the user asks about progress:

```bash
# Check agent panes
tmux capture-pane -t harnecess-agents:agents.0 -p | tail -15  # planner
tmux capture-pane -t harnecess-agents:agents.1 -p | tail -15  # builder
tmux capture-pane -t harnecess-agents:agents.2 -p | tail -15  # checker
tmux capture-pane -t harnecess-agents:agents.3 -p | tail -15  # writer

# Check inbox
cat queue/inbox/lead.yaml
```

## Inbox Processing

When you detect unread messages (via auto-check, `inbox1`, or user asking "進捗"):
1. Read `queue/inbox/lead.yaml`
2. Find entries with `read: false`
3. Process each → proceed to next pipeline step
4. Mark processed entries as `read: true` using **Write tool only**:

```
Read queue/inbox/lead.yaml, then use Write to save the updated version with read: true.
```

**NEVER use `sed -i`, `python3 -c`, or any Bash command to update YAML files.** Always Read then Write tool.
