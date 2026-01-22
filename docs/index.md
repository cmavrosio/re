---
layout: default
title: Home
---

# re & kori

**Autonomous AI software development powered by Claude.**

re executes structured work plans autonomously. kori breaks down complex projects into manageable tasks. Together, they turn high-level goals into working software.

---

## Quick Start

```bash
# Install
git clone https://github.com/cmavrosio/re.git
cd re && ./install.sh

# Plan and execute a project
cd my-project
kori init "Build a property management app"
kori discover     # Answer questions
kori plan         # Generate tasks
kori nag          # Execute autonomously
kori blame        # Check progress
```

---

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│                        kori                              │
│         (breaks goals into hierarchical tasks)          │
└────────────────────────┬────────────────────────────────┘
                         │ generates plan.md
                         ▼
┌─────────────────────────────────────────────────────────┐
│                         re                               │
│         (executes each task autonomously)               │
│                                                          │
│  context → Claude → analyze → test → repeat             │
└─────────────────────────────────────────────────────────┘
```

**The loop:**
1. Build context (plan + state + changes + tests)
2. Call Claude with full project context
3. Claude writes code, runs commands
4. Analyze for completion signals
5. Run tests, update state
6. Repeat until done

---

## Real Results

Built a property ordering system:
- **Stack**: Next.js + Supabase + TypeScript
- **Features**: Multi-tenant, RLS, role-based access
- **Progress**: 41% complete (14/34 tasks) in ~2 hours
- **Code**: ~12,000 lines, working app

```bash
$ kori blame

Progress: [████████████████░░░░░░░░░░░░░░░░░░░░░░░░] 41%

✓ Completed:   14
◐ In Progress: 1
○ Pending:     19
```

---

## Safety Features

- **Circuit Breaker** — Stops after 3 errors or 5 no-change iterations
- **CI Integration** — Waits for GitHub Actions to pass
- **Auto-commit** — Preserves work every N iterations
- **Test Validation** — Runs your test suite after each iteration
- **Human Override** — Pause/abort anytime

---

## Documentation

| Page | Description |
|------|-------------|
| [re Documentation](re) | Task executor commands and config |
| [kori Documentation](kori) | Project planner commands and workflow |
| [How It Works](how-it-works) | Deep dive into architecture |
| [X Thread](x-thread) | Ready-to-post social content |

---

## Etymology

In Cypriot Greek:
- **re** (ρε) — informal way to address a guy
- **kori** (κόρη) — means "girl"

Like Lisa Simpson guiding Ralph Wiggum, kori plans the work and re executes it.

---

## Links

- [GitHub Repository](https://github.com/cmavrosio/re)
- [Original Concept: Geoffrey Huntley's "The Loop"](https://ghuntley.com/loop/)
