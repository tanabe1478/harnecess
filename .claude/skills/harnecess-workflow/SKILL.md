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
1. Read `.harnecess/plan.yaml`
2. Tell the user: "Planner の計画が完了しました。plan.yaml の内容:" then show a brief summary
3. **Do NOT ask for re-approval.** The user already approved in the planner pane. Proceed directly to Step 3.

NOTE: The user interacts with planner directly in the csm session. Planner only reports "done" after the user has approved. You do NOT need to re-ask.

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

## Checking Progress

When the user asks about progress or when you receive an inbox notification:

```bash
# Check agent status
tmux capture-pane -t harnecess-agents:agents.0 -p | tail -15  # planner
tmux capture-pane -t harnecess-agents:agents.1 -p | tail -15  # builder
tmux capture-pane -t harnecess-agents:agents.2 -p | tail -15  # checker
tmux capture-pane -t harnecess-agents:agents.3 -p | tail -15  # writer

# Check inbox for reports
cat queue/inbox/lead.yaml
```

## Inbox Processing

When you see `inbox1` or the user says "進捗":
1. Read `queue/inbox/lead.yaml`
2. Find entries with `read: false`
3. Process each → proceed to next pipeline step
4. Mark processed entries as `read: true` using **Write tool** (not sed):

```
Read queue/inbox/lead.yaml, then use Write to save the updated version with read: true.
```

**NEVER use `sed -i` to update YAML files.** Always Read then Write.
