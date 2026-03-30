# harnecess

Claude Code multi-agent development system. Lead, Planner, Builder, Checker, Writer agents collaborate via tmux sessions and file-based mailbox communication to plan, implement, review, and document code changes.

## Architecture

```
┌─ harnecess (lead session) ──────────────────────────────────────────┐
│  lead (Opus): User interaction, task delegation                     │
└─────────────────────────────────────────────────────────────────────┘
┌─ harnecess-agents (2x2 grid) ──────────────────────────────────────┐
│  planner (Opus)     │  builder (Opus)                               │
│  Plan Mode          │  Code implementation                          │
├─────────────────────┼───────────────────────────────────────────────┤
│  checker (Sonnet)   │  writer (Sonnet)                              │
│  Code review        │  Documentation                                │
└─────────────────────┴───────────────────────────────────────────────┘
```

## Quick Start

```bash
# Install
git clone https://github.com/tanabe1478/harnecess.git
cd harnecess
pip install -r requirements.txt
sudo ln -s "$(pwd)/harnecess" /usr/local/bin/harnecess

# Launch (target repo as argument)
harnecess start ~/workspace/my-project

# In the lead session, talk to Claude:
> Issue #42 を実装して
```

## Commands

```bash
harnecess start [target-repo]   # Launch all agents
harnecess stop                  # Kill all sessions
harnecess status                # Show agent status
```

## Sessions

| Alias | Session | Purpose |
|-------|---------|---------|
| `css` | harnecess | Lead — interact with Claude here |
| `csm` | harnecess-agents | Planner/Builder/Checker/Writer — observe |

Add to `~/.zshrc`:
```bash
alias css='tmux attach-session -t harnecess'
alias csm='tmux attach-session -t harnecess-agents'
```

## Pipeline

```
Phase 1: Plan      — Lead → Planner (Plan Mode, user observes in csm)
Phase 2: Implement — Lead → Builder (TDD, Opus)
Phase 3: Review    — Lead → Checker (code review)
Phase 4: PR        — Lead creates PR
Phase 5: Document  — Lead → Writer (ADR, specs, README)
```

## Agents

| Agent | Model | Mode | Role |
|-------|-------|------|------|
| lead | Opus | --permission-mode default | User interaction, orchestration |
| planner | Opus | --permission-mode plan | Issue analysis, plan.yaml creation |
| builder | Opus | --dangerously-skip-permissions | Code implementation (TDD) |
| checker | Sonnet | --dangerously-skip-permissions | Code review |
| writer | Sonnet | --dangerously-skip-permissions | Documentation |

## Requirements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)
- [GitHub CLI (gh)](https://cli.github.com/)
- tmux
- fswatch (`brew install fswatch` on macOS)
- git
- Python 3 + pyyaml (auto-setup via venv)

## References

- [Codified Context (arXiv:2602.20478)](https://arxiv.org/pdf/2602.20478) — 3-tier documentation

## License

MIT (see LICENSE)
