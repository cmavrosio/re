---
layout: default
title: kori - Project Planner
---

# kori (Project Planner)

Hierarchical project planner that breaks down goals into executable task trees.

---

## How It Works

kori guides you through three phases:

1. **Discover**: Interactive Q&A to gather requirements
2. **Plan**: Autonomous task tree generation
3. **Nag**: Execute tasks via re

```
Goal → Discovery → Requirements → Task Tree → Execution
```

---

## Installation

kori is installed alongside re:

```bash
git clone https://github.com/yourusername/re.git
cd re && ./install.sh
```

---

## Commands

| Command | Description |
|---------|-------------|
| `kori init <goal>` | Initialize project with a high-level goal |
| `kori discover` | Interactive Q&A to gather requirements |
| `kori plan` | Build task tree from requirements |
| `kori setup` | Generate setup instructions (env vars, secrets) |
| `kori nag` | Start executing leaves via re |
| `kori status` | Show tree with progress |
| `kori next` | Show next actionable leaf |
| `kori tree` | Display the full task tree |

---

## Workflow

### 1. Initialize Project

```bash
kori init "Build an e-commerce platform with Stripe"
```

Or from a file:

```bash
kori init -f spec.md
```

This creates `.overseer/project.md` with your goal.

### 2. Discovery Phase

```bash
kori discover
```

Claude asks clarifying questions about:
- Technical stack and architecture
- Feature details and priorities
- Integration requirements
- Deployment and infrastructure

Answer the questions, and kori generates `.overseer/requirements.md`.

### 3. Planning Phase

```bash
kori plan
```

Claude autonomously builds a hierarchical task tree:

```
root
├── feature-auth
│   ├── task-user-model
│   ├── task-login-api
│   └── task-session-mgmt
├── feature-products
│   ├── task-product-model
│   └── task-catalog-api
└── feature-checkout
    ├── task-cart
    └── task-stripe-integration
```

Each leaf node has 3-10 specific, verifiable criteria.

### 4. Setup Instructions

```bash
kori setup
```

Generates `.overseer/setup.md` with:
- Required environment variables
- Where to find API keys
- Local development setup
- Supabase/Cloudflare/GitHub configuration

### 5. Execution

```bash
kori nag
```

kori selects the next leaf and creates a `plan.md` for re, then:
- Starts re to execute the task
- Monitors progress
- Moves to next leaf when complete

---

## Directory Structure

```
.overseer/
├── project.md        # Original goal/spec
├── requirements.md   # Gathered requirements
├── tree.yaml         # Hierarchical task tree
├── setup.md          # Setup instructions
├── state.yaml        # Current execution state
├── config.yaml       # kori configuration
└── logs/             # Execution logs
```

---

## Configuration

Create `.overseer/config.yaml`:

```yaml
# Maximum tree depth
max_depth: 5

# Criteria per leaf node
min_criteria_per_leaf: 3
max_criteria_per_leaf: 10

# Models for different phases
discover_model: sonnet
plan_model: sonnet
```

---

## Task Tree Format

`.overseer/tree.yaml`:

```yaml
nodes:
  root:
    title: "E-commerce Platform"
    description: |
      Full-featured e-commerce with Stripe
    status: pending
    children: [feature-auth, feature-products]

  feature-auth:
    title: "User Authentication"
    description: |
      Complete auth system with OAuth
    parent: root
    status: pending
    children: [task-user-model, task-login-api]

  task-user-model:
    title: "User Database Model"
    parent: feature-auth
    status: pending
    is_leaf: true
    criteria:
      - "Create users table with email, password_hash, created_at"
      - "Add unique constraint on email"
      - "Create Supabase migration file"
      - "Row Level Security policies configured"
      - "All tests pass"
```

---

## Example Session

```bash
$ mkdir my-saas && cd my-saas
$ git init

# Start with a goal
$ kori init "Build a multi-tenant SaaS for project management"

# Discovery - answer Claude's questions
$ kori discover
╭─────────────────────────────────────────────────────────────╮
│  KORI - Project Discovery                                   │
│  Claude will ask clarifying questions about your project    │
╰─────────────────────────────────────────────────────────────╯

Q1: What authentication method should be used?
    OAuth, email/password, or both?
Your answer: Both, with Google OAuth as primary

Q2: What is the billing model?
    Per-seat, usage-based, or flat rate?
Your answer: Per-seat with monthly billing via Stripe

...

✓ Claude has enough information to proceed!

# Generate task tree
$ kori plan
Building task tree...
Tree Statistics:
  Nodes: 24
  Leaves: 15

# Check setup requirements
$ kori setup
Setup guide saved to .overseer/setup.md

# Start execution
$ kori nag
Starting: task-database-schema
[re starts working...]
```

---

## Tips

### Writing Good Goals

**Good:**
> "Build a project management SaaS with team workspaces, Kanban boards,
> and Stripe billing. Use Next.js, Supabase, and deploy to Vercel."

**Too vague:**
> "Build a project management app"

### During Discovery

- Be specific about technical choices
- Mention integrations upfront
- Clarify MVP vs future features
- Specify deployment targets

### Tree Depth

- Depth 3-4: Small projects (1-2 weeks)
- Depth 4-5: Medium projects (1-2 months)
- Depth 5+: Large projects (complex systems)

---

## Name Origin

In Cypriot Greek:
- **re** (ρε) - informal way to address a guy
- **kori** (κόρη) - means "girl"

Like Lisa Simpson guiding Ralph Wiggum, kori plans the work and re executes it.

---

[Back to Home](/)
