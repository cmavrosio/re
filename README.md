# re & kori

**Autonomous AI software development powered by Claude.**

re executes structured work plans autonomously. kori breaks down complex projects into manageable tasks. Together, they turn high-level goals into working software.

```
You: "Build a multi-tenant SaaS with Stripe billing"
     ↓
kori: Breaks it into 34 executable tasks
     ↓
re:   Completes each task autonomously with Claude
     ↓
You:  Review working code, 41% done in 2 hours
```

---

## What This Is

**re** (Ralph Enhanced) implements the "Ralph Wiggum Technique" — an iterative AI development methodology where a loop feeds Claude structured tasks until completion. Named after The Simpsons character who persists despite setbacks.

**kori** is the planner that sits above re. It conducts requirements gathering, generates hierarchical task trees, and orchestrates re to execute each leaf task.

Together, they enable **autonomous software development** with human oversight at the planning stage and safety controls during execution.

---

## Quick Start

```bash
# Install
git clone https://github.com/cmavrosio/re.git
cd re && ./install.sh

# Plan and execute a project
cd my-project
kori init "Build a property management app with Next.js and Supabase"
kori discover     # Answer 5-10 questions
kori plan         # Generate 30+ tasks
kori nag          # Execute autonomously
kori blame        # Check progress
```

---

## The Two Tools

### kori — The Planner

kori transforms vague goals into executable task trees through three phases:

| Phase | Command | What Happens |
|-------|---------|--------------|
| **Discover** | `kori discover` | Claude asks clarifying questions about requirements, tech stack, constraints |
| **Plan** | `kori plan` | Claude generates a hierarchical task tree with 3-10 criteria per leaf |
| **Execute** | `kori nag` | kori feeds leaves to re one by one until complete |

```bash
$ kori blame

╭─────────────────────────────────────────────────────────────╮
│  KORI PROJECT STATUS                                        │
╰─────────────────────────────────────────────────────────────╯

  Progress: [████████████████░░░░░░░░░░░░░░░░░░░░░░░░] 41%

  ✓ Completed:   14
  ◐ In Progress: 1
  ○ Pending:     19
  Total:         34 leaves
```

### re — The Executor

re runs Claude in an autonomous loop with safety controls:

```
┌─────────────────────────────────────────────────────────┐
│  1. Build context (plan + state + changes + tests)      │
│  2. Call Claude with --dangerously-skip-permissions     │
│  3. Claude writes code, runs commands, makes progress   │
│  4. Analyze response for CRITERION_DONE signals         │
│  5. Run tests, check CI, update state                   │
│  6. Repeat until all criteria complete or limits hit    │
└─────────────────────────────────────────────────────────┘
```

**Safety features:**
- Circuit breaker (stops after 3 errors, 5 no-change iterations, or 3 test failures)
- Auto-commit every N iterations
- CI integration (waits for GitHub Actions)
- Token budget limits
- Human pause/abort anytime

---

## Commands

### kori

| Command | Description |
|---------|-------------|
| `kori init <goal>` | Initialize project with a goal |
| `kori init -f spec.md` | Initialize from a spec file |
| `kori discover` | Interactive Q&A for requirements |
| `kori plan` | Generate hierarchical task tree |
| `kori setup` | Generate setup instructions (env vars, secrets) |
| `kori nag` | Execute tasks via re (autonomous) |
| `kori blame` | Show project status overview |
| `kori status` | Show current progress |
| `kori tree` | Display full task tree |

### re

| Command | Description |
|---------|-------------|
| `re init` | Create .ralph/ directory |
| `re start` | Start new session from plan.md |
| `re resume` | Resume paused/crashed session |
| `re status` | Show session status |
| `re stop` | Gracefully stop after current iteration |
| `re abort` | Immediately abort |
| `re inject <msg>` | Add context for next iteration |
| `re merge` | Sync completed criteria to plan.md |
| `re rollback` | Undo auto-commits |

---

## Configuration

### re (`.ralph/config.yaml`)

```yaml
max_iterations: 100
max_tokens: 500000
auto_commit_interval: 5
auto_push: true
model: opus  # sonnet | opus | haiku

# Test command with CI integration
test_command: |
  npm test && {
    run_id=$(gh run list --workflow CI --limit 1 -q '.[0].databaseId');
    [ -z "$run_id" ] || gh run watch "$run_id" --exit-status;
  }
```

### kori (`.overseer/config.yaml`)

```yaml
max_depth: 5
min_criteria_per_leaf: 3
max_criteria_per_leaf: 10
discover_model: sonnet
plan_model: sonnet
```

---

## Example Session

```bash
$ cd ~/projects
$ mkdir my-saas && cd my-saas
$ git init

$ kori init "Build a multi-tenant property ordering system for restaurants"
✓ Project initialized

$ kori discover
╭─────────────────────────────────────────────────────────────╮
│  KORI - Project Discovery                                   │
╰─────────────────────────────────────────────────────────────╯

Q1: What authentication method should be used?
Your answer: Supabase Auth with email/password

Q2: What's the billing model?
Your answer: No billing, internal tool

Q3: Which roles need to be supported?
Your answer: Staff, Manager, Super Admin
...

✓ Requirements saved

$ kori plan
Building task tree...
  Nodes: 45
  Leaves: 34

$ kori nag
╭─────────────────────────────────────────────────────────────╮
│  Executing: Technology Stack Setup                          │
│  Leaf ID: tech-stack-setup                                  │
╰─────────────────────────────────────────────────────────────╯

info: Starting iteration 1
info: Calling Claude...
info: Marking criterion 0 as complete
...
✓ Leaf completed

╭─────────────────────────────────────────────────────────────╮
│  Executing: Environment Configuration                       │
│  Leaf ID: env-configuration                                 │
╰─────────────────────────────────────────────────────────────╯
...

# 2 hours later...

$ kori blame
Progress: [████████████████░░░░░░░░░░░░░░░░░░░░░░░░] 41%
✓ Completed: 14 leaves
```

---

## How It Works (Deep Dive)

See [How It Works](https://cmavrosio.github.io/re/how-it-works) for the full technical explanation.

---

## Etymology

In Cypriot Greek:
- **re** (ρε) — informal way to address a guy ("hey dude")
- **kori** (κόρη) — means "girl"

Like Lisa Simpson guiding Ralph Wiggum, kori plans the work and re executes it.

---

## Requirements

- [Babashka](https://babashka.org/) — `brew install borkdude/brew/babashka`
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) — `claude` command
- git, jq

---

## Safety Warning

**re runs Claude with `--dangerously-skip-permissions`**, giving Claude full access to execute commands, read/write files, and make network requests.

**Recommendations:**
- Only run in projects you trust
- Use git for easy rollback
- Review changes before pushing
- Keep sensitive credentials out of the project

---

## Credits

- [Geoffrey Huntley's "The Loop"](https://ghuntley.com/loop/) — original concept
- [frankbria/ralph-claude-code](https://github.com/frankbria/ralph-claude-code) — bash implementation
- Built entirely with [Claude Code](https://docs.anthropic.com/en/docs/claude-code)

## License

MIT
