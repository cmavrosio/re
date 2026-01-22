---
layout: default
title: How It Works - Deep Dive
---

# How re & kori Work: A Deep Dive

This document explains the technical architecture and design decisions behind re and kori — tools for autonomous AI software development.

---

## The Problem

AI coding assistants are powerful but require constant human interaction. Every change needs approval. Every command needs confirmation. This creates a bottleneck: the human becomes the slowest part of the development process.

**What if we could give Claude a structured task and let it work autonomously until done?**

That's what re and kori do.

---

## The Ralph Wiggum Technique

The core idea is simple: **put Claude in a loop**.

```python
while not task_complete:
    context = build_context(plan, state, recent_changes)
    response = claude(context)
    state = analyze_response(response)
    run_tests()
```

Named after the Simpsons character who persists despite setbacks, this technique embraces iteration. Claude might not get it right the first time, but given enough attempts with good feedback, it converges on a solution.

### Why It Works

1. **Structured Tasks** — Breaking work into numbered criteria gives Claude clear goals
2. **Rich Context** — Each iteration includes the plan, current state, recent changes, and test results
3. **Progress Signals** — Claude outputs `CRITERION_DONE: N` to mark completion
4. **Safety Rails** — Circuit breakers prevent infinite loops

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                          kori                                │
│         (breaks goals into hierarchical task trees)          │
│                                                              │
│   init → discover → plan → nag (orchestrates re)            │
└──────────────────────────┬──────────────────────────────────┘
                           │ generates plan.md for each leaf
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                           re                                 │
│              (executes a single task plan)                   │
│                                                              │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐ │
│  │ Context  │ → │  Claude  │ → │ Analyzer │ → │ Decision │ │
│  │ Builder  │   │   API    │   │          │   │  Maker   │ │
│  └──────────┘   └──────────┘   └──────────┘   └──────────┘ │
│       ↑                                            │        │
│       └────────────────────────────────────────────┘        │
│                     (loop until done)                        │
└─────────────────────────────────────────────────────────────┘
```

---

## kori: The Planner

### Phase 1: Discovery

```bash
kori discover
```

kori uses Claude to conduct a structured interview:

1. Read the project goal from `.overseer/project.md`
2. Claude generates 1-3 clarifying questions as JSON
3. User answers via terminal
4. Repeat until Claude has enough information
5. Generate `requirements.md` with structured requirements

The key insight: **Claude asks better questions than humans think to ask**. It probes for technical constraints, edge cases, and architectural decisions.

### Phase 2: Planning

```bash
kori plan
```

Claude generates a hierarchical YAML task tree:

```yaml
nodes:
  root:
    title: "Property Ordering App"
    children: [setup, database, auth, features, deployment]

  auth:
    title: "Authentication System"
    parent: root
    children: [auth-supabase, auth-middleware, auth-session]

  auth-supabase:
    title: "Supabase Auth Integration"
    parent: auth
    is_leaf: true
    criteria:
      - "Supabase client configured with environment variables"
      - "Login page with email/password form"
      - "Registration with email verification"
      - "Password reset flow implemented"
      - "Auth state persisted across page refreshes"
```

Each leaf has 3-10 specific, verifiable criteria — perfect size for re to execute.

### Phase 3: Execution

```bash
kori nag
```

kori orchestrates re:

1. Find next pending leaf (prioritizing in-progress ones)
2. Generate `plan.md` from leaf criteria
3. Call `re start` or `re resume`
4. Wait for completion
5. Mark leaf done, move to next
6. Repeat until all leaves complete

---

## re: The Executor

### The Iteration Loop

Each iteration:

```bash
# 1. Build context
context = plan + state + rules + recent_changes + test_results

# 2. Call Claude
response = claude --dangerously-skip-permissions < context

# 3. Analyze response
signals = extract_signals(response)  # CRITERION_DONE, errors, etc.

# 4. Update state
mark_criteria_complete(signals.criteria_done)

# 5. Run tests
test_results = run_tests()

# 6. Update health
circuit_breaker.update(success, has_changes, tests_passed)

# 7. Decide
if all_complete: exit(success)
if circuit_breaker.tripped: exit(pause)
continue_to_next_iteration()
```

### Context Building

The context sent to Claude includes:

1. **Task Description** — What to accomplish
2. **Criteria Checklist** — What's done, what's pending
3. **Recent Changes** — Git diff of uncommitted work
4. **Test Results** — Output from last test run
5. **Rules** — Project-specific guidelines
6. **Iteration History** — Compressed summaries of previous iterations

For long sessions, older iterations are compressed using Claude Haiku to save tokens.

### Signal Detection

Claude's response is analyzed for:

- `CRITERION_DONE: N` — Marks criterion N as complete
- `TASK_COMPLETE` — All criteria finished
- `BLOCKED: reason` — Can't proceed without help
- Error patterns — Compilation failures, test errors

### Circuit Breaker

The circuit breaker tracks health metrics:

| Metric | Threshold | Meaning |
|--------|-----------|---------|
| `consecutive_errors` | 3 | Claude execution failed |
| `consecutive_no_change` | 5 | No git changes for N iterations |
| `consecutive_test_only` | 3 | Only running tests, no code |
| `consecutive_test_failures` | 3 | Tests/CI failing |

When any threshold is exceeded, the session pauses for human intervention.

### CI Integration

re can wait for CI pipelines:

```yaml
test_command: |
  npm test && {
    run_id=$(gh run list --workflow CI --limit 1 -q '.[0].databaseId');
    [ -z "$run_id" ] || gh run watch "$run_id" --exit-status;
  }
```

This ensures Claude's changes pass not just local tests but the full CI pipeline before continuing.

---

## Session Modes

### Stateless Mode

Each iteration starts a fresh Claude session:

- **Pros**: Full control, predictable context
- **Cons**: More tokens, no conversation memory

### Hybrid Mode (Default)

Reuse Claude sessions with periodic refreshes:

- **Pros**: Fewer tokens, maintains conversation context
- **Cons**: Context can drift

Refresh triggers:
- Every N iterations (configurable)
- When `rules.md` changes
- When `urgent.md` injection exists
- Optionally after each criterion

---

## File Structure

```
.ralph/                      # re's working directory
├── plan.md                  # Task definition (input)
├── state.md                 # Current progress (managed)
├── config.yaml              # Configuration
├── rules.md                 # Guidelines for Claude
├── urgent.md                # One-time injection
├── health.yaml              # Circuit breaker state
├── context/
│   ├── current.md           # Context sent to Claude
│   ├── iterations/          # Per-iteration records
│   └── summary.md           # Compressed history
├── tests/
│   ├── latest.md            # Last test results
│   └── baseline.md          # Initial test state
└── archive/                 # Completed sessions

.overseer/                   # kori's working directory
├── project.md               # Original goal
├── requirements.md          # Discovered requirements
├── tree.yaml                # Hierarchical task tree
├── setup.md                 # Setup instructions
├── state.yaml               # Execution progress
└── config.yaml              # Configuration
```

---

## Why Bash + Clojure?

The tools are built with:

- **Bash** — Orchestration, file operations, CLI interface
- **Babashka (Clojure)** — Complex logic, YAML/JSON parsing, decision making

This combination provides:

1. **Portability** — Bash runs everywhere
2. **Expressiveness** — Clojure for complex data manipulation
3. **Fast startup** — Babashka is instant (no JVM startup)
4. **Easy installation** — Single binary dependency

---

## Safety Considerations

### What Could Go Wrong

Running Claude with `--dangerously-skip-permissions` means it can:

- Execute any bash command
- Read/write any file
- Install packages
- Make network requests
- Delete files

### Mitigations

1. **Git** — All changes are tracked, easy rollback
2. **Auto-commit** — Work preserved at intervals
3. **Circuit breaker** — Stops runaway loops
4. **Test validation** — Catches regressions
5. **Human oversight** — Pause/abort anytime

### Recommendations

- Run in isolated projects
- Keep credentials out of the directory
- Review changes before pushing
- Use disposable environments for untrusted code

---

## Future Directions

Potential improvements:

1. **Parallel leaf execution** — Run independent leaves concurrently
2. **Smarter scheduling** — Prioritize based on dependencies
3. **Cost tracking** — Per-task API cost reporting
4. **Rollback per-leaf** — Undo a specific leaf's changes
5. **Web UI** — Visual progress monitoring

---

## Conclusion

re and kori demonstrate that **autonomous AI development is practical today**. The key ingredients:

1. **Structured tasks** — Clear goals with verifiable criteria
2. **Rich context** — Claude sees the full picture each iteration
3. **Safety rails** — Circuit breakers prevent disasters
4. **Human oversight** — Planning phase catches requirements issues

The result: Claude can build a 34-task SaaS app with 41% completion in 2 hours, with humans only involved in the initial planning phase.

---

[Back to Home](/)
