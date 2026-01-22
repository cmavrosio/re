#!/usr/bin/env bash
#
# kori help - Show help
#

cat << 'EOF'
kori - Hierarchical project planner for re

Kori (Κόρη) guides Ralph through complex projects by breaking them
down into manageable tasks. Like Lisa Simpson guiding Ralph Wiggum,
kori plans while re executes.

WORKFLOW:

  ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
  │   1. DISCOVER   │ ──▶ │    2. PLAN      │ ──▶ │    3. NAG       │
  │   (interactive) │     │   (autonomous)  │     │   (autonomous)  │
  │                 │     │                 │     │                 │
  │ Claude asks Qs  │     │ Build tree      │     │ Nag re to work  │
  │ Human answers   │     │ Refine nodes    │     │ one leaf at a   │
  │ → requirements  │     │ → tree.yaml     │     │ time → done!    │
  └─────────────────┘     └─────────────────┘     └─────────────────┘

COMMANDS:

  kori init <goal>    Initialize project with high-level goal
  kori discover       Interactive Q&A to gather requirements
  kori plan           Build task tree (autonomous)
  kori nag            Nag re to execute (autonomous)
  kori status         Show project progress
  kori tree           Display task tree
  kori next           Show next actionable leaf

QUICK START:

  $ kori init "Build a CRM system"
  $ kori discover      # Answer Claude's questions
  $ kori plan          # Claude builds task tree
  $ kori nag           # Nag re to execute all leaves

TREE STRUCTURE:

                    [Project Root]
                         │
         ┌───────────────┼───────────────┐
         │               │               │
    [Feature A]    [Feature B]    [Feature C]
         │               │
    ┌────┴────┐     ┌────┴────┐
    │         │     │         │
  [Leaf 1] [Leaf 2] [Leaf 3] [Leaf 4]

  Leaves become plan.md files for re to execute.

FILES:

  .overseer/
  ├── project.md       # Initial goal
  ├── requirements.md  # Discovery output
  ├── tree.yaml        # Task hierarchy
  ├── state.yaml       # Execution state
  └── config.yaml      # Settings

For more: https://github.com/cmavrosio/re
EOF
