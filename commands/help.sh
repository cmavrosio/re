#!/usr/bin/env bash
#
# re help - Explain how re works
#

cat << 'EOF'
┌─────────────────────────────────────────────────────────────────────────────┐
│                          re (ralph enhanced)                                │
│                    Autonomous AI Task Runner                                │
└─────────────────────────────────────────────────────────────────────────────┘

WHAT IT DOES
  re runs Claude in a loop to complete multi-step tasks autonomously.
  You define the task in plan.md, and re handles the rest:
  iteration, testing, progress tracking, and safety limits.

WORKFLOW
  1. re init          Create .ralph/ directory with templates
  2. Edit plan.md     Define task and completion criteria (or ask Claude)
  3. re start         Begin autonomous loop
  4. re watch         Monitor progress in real-time (another terminal)
  5. re pause         Gracefully stop the loop
  6. re resume        Continue from where it stopped
  7. re merge         Finalize session, sync to plan.md

KEY FILES (.ralph/)
  plan.md        Task definition with numbered completion criteria
  rules.md       Project guidelines Claude must follow (test commands, style, safety)
  state.md       Working copy with checkboxes (updated during iterations)
  config.yaml    Settings: max iterations, test command, model, etc.

COMPLETION CRITERIA FORMAT
  Tasks complete when ALL numbered checkboxes are checked:

  ## Completion Criteria
  - [ ] 0. First thing to do
  - [ ] 1. Second thing to do
  - [ ] 2. All tests pass: npm test

  Claude marks these as [x] when done. The loop continues until all are checked.

BACKLOG (blocked/future items)
  Items in ## Backlog are shown to Claude but NOT worked on:

  ## Backlog
  - [ ] BLOCKED: PDF export (needs: sample template)
  - [ ] FUTURE: Multi-language (waiting on i18n decision)
  - [ ] NEEDS_INPUT: Widgets (need: types from user)

  Move items to Completion Criteria when ready to implement.

SAFETY FEATURES
  • Max iterations limit (default: 50)
  • Max tokens limit (default: 500,000)
  • Circuit breaker: stops on repeated errors or no-progress loops
  • Auto-commit: saves progress every N iterations

COMMANDS
  re init       Initialize .ralph/ directory
  re plan       Show prompt for Claude to edit plan.md
  re start      Start new session and begin autonomous loop
  re status     Show current session status
  re watch      Live dashboard (run in separate terminal)
  re pause      Request graceful pause after current iteration
  re resume     Continue paused session
  re inject     Send guidance message to running session
  re abort      Stop session immediately
  re rollback   Undo to specific iteration
  re merge      Finalize session, sync to plan.md
  re config     View/edit configuration
  re help       Show this help

TIPS
  • Run 're watch' in a separate terminal to monitor progress
  • Use 're inject "focus on X"' to guide Claude mid-session
  • Check .ralph/logs/re.log for debugging
  • Criteria must be numbered (0., 1., 2.) for tracking to work

EOF
