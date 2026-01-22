---
layout: default
title: re - Task Executor
---

# re (Ralph Enhanced)

Autonomous AI task runner that executes structured work plans using Claude Code.

---

## How It Works

re implements the "Ralph Wiggum Technique" - a continuous iteration loop that:

1. **Builds context** from your plan, current state, and recent changes
2. **Calls Claude** with full project context
3. **Analyzes response** for completion signals and progress
4. **Runs tests** to validate changes
5. **Updates state** and decides whether to continue
6. **Repeats** until all criteria are complete or limits are reached

---

## Installation

```bash
git clone https://github.com/yourusername/re.git
cd re && ./install.sh
```

This installs `re` to `~/.local/bin/re`.

---

## Commands

### Core Commands

| Command | Description |
|---------|-------------|
| `re start` | Start a new session from plan.md |
| `re resume` | Resume a paused session |
| `re stop` | Gracefully stop after current iteration |
| `re abort` | Immediately abort the session |
| `re status` | Show current session status |

### Utility Commands

| Command | Description |
|---------|-------------|
| `re init` | Create .ralph directory with templates |
| `re config` | Show current configuration |
| `re rollback` | Undo recent auto-commits |
| `re health` | Show circuit breaker status |
| `re inject <message>` | Add urgent context for next iteration |

---

## Configuration

Create `.ralph/config.yaml`:

```yaml
# Maximum iterations before auto-abort
max_iterations: 100

# Maximum tokens before auto-abort
max_tokens: 500000

# Auto-commit every N iterations (0 to disable)
auto_commit_interval: 5

# Test command to run after each iteration
test_command: "npm test"

# Claude model to use (sonnet, opus, haiku)
model: sonnet

# Auto-push after commits
auto_push: false

# Session mode: stateless, hybrid
session_mode: hybrid

# Refresh session every N iterations (hybrid mode)
refresh_interval: 5
```

---

## Plan Format

Create `.ralph/plan.md`:

```markdown
# Feature Name

Brief description of what needs to be built.

## Context

Any relevant background information, constraints, or requirements.

## Criteria

1. First specific, verifiable outcome
2. Second specific outcome
3. Third outcome
4. All tests pass
```

### Criteria Best Practices

- Make each criterion independently verifiable
- Use specific, measurable language
- Include a "tests pass" criterion for testable features
- Order by logical dependency
- Aim for 5-15 criteria per plan

---

## State Management

re tracks state in `.ralph/state.md`:

```markdown
---
status: running
iteration: 15
session: abc123
---

# Current Task

## Criteria

- [x] 1. First criterion (completed)
- [x] 2. Second criterion (completed)
- [ ] 3. Third criterion (in progress)
- [ ] 4. Fourth criterion (pending)
```

---

## Circuit Breaker

The circuit breaker prevents runaway loops by monitoring:

| Metric | Default Threshold | Description |
|--------|-------------------|-------------|
| Consecutive errors | 3 | Claude execution failures |
| No-change iterations | 5 | Iterations without git changes |
| Test-only loops | 3 | Iterations only running tests |
| Test failures | 3 | CI or test command failures |

When tripped, the session pauses for human intervention.

Check status with:

```bash
re health
```

---

## Steering

### Rules File

Create `.ralph/rules.md` to provide persistent guidance:

```markdown
# Rules

- Use TypeScript for all new files
- Follow existing code patterns
- Write tests for new functionality
- Keep functions under 50 lines
```

### Urgent Injection

Add one-time context for the next iteration:

```bash
re inject "Focus on fixing the authentication bug first"
```

Or edit `.ralph/urgent.md` directly.

---

## CI Integration

Configure test commands to include CI checks:

```yaml
test_command: "npm test && { run_id=$(gh run list --workflow CI --limit 1 --json databaseId -q '.[0].databaseId'); [ -z \"$run_id\" ] || gh run watch \"$run_id\" --exit-status; }"
```

This will:
1. Run local tests
2. Wait for CI to complete
3. Fail if CI fails (triggering fix attempts)

---

## Iteration Compression

For long-running sessions, re compresses old iterations using Claude Haiku to save context space:

```yaml
compress_iterations: true
compression_threshold: 10
```

---

## Example Session

```bash
$ cd my-project
$ re init
Created .ralph/plan.md
Created .ralph/config.yaml

$ vim .ralph/plan.md  # Edit your plan

$ re start
info: Parsing plan.md...
info: Creating state.md...
success: Session abc123 started

info: Starting iteration 1
info: Calling Claude...
info: Analyzing response...
info: Running tests...
info: Marking criterion 1 as complete

────────────────────────────────────
 Next: 2. Implement user authentication
 Progress: 1/5 criteria
────────────────────────────────────

info: Starting iteration 2
...

success: All criteria complete!
```

---

## Troubleshooting

### Session won't start

```bash
# Check for existing session
re status

# Reset if needed
rm -rf .ralph/state.md .ralph/health.yaml
```

### Claude not making progress

```bash
# Inject guidance
re inject "The issue is in src/auth.ts line 45"

# Or check rules
cat .ralph/rules.md
```

### Too many iterations

```bash
# Check circuit breaker
re health

# Pause and review
re stop
```

---

[Back to Home](/)
