# Context for Iteration {{ITERATION}}

## Current Task

{{TASK}}

{{#RULES}}
## Rules

{{RULES}}
{{/RULES}}

## Completion Criteria

{{CRITERIA}}

## Progress Summary

{{SUMMARY}}

## Recent Activity

{{RECENT_ITERATIONS}}

## Current Changes

{{DIFF}}

## Test Results

{{TEST_RESULTS}}

{{#URGENT}}
## URGENT

{{URGENT}}
{{/URGENT}}

{{#BACKLOG}}
## Backlog (DO NOT work on these)

These items need more input or are blocked. For reference only:

{{BACKLOG}}
{{/BACKLOG}}

{{#DOCS}}
## Documentation Requirements

{{DOCS}}
{{/DOCS}}

---

## Instructions

Work on ONE task at a time. Pick the next unchecked `[ ]` criterion from the list above.

**Workflow for each iteration:**
1. Pick the next unchecked criterion (highest priority / lowest number)
2. Complete that task
3. **Update any affected documentation:**
   - Update comments/docstrings if function signatures changed
   - Update README or docs if public API changed
   - Update type definitions if interfaces changed
   - Check the Documentation Requirements section above for project-specific files
4. Verify your changes work (run tests/lint if applicable)
5. Output the signal below and STOP

**IMPORTANT: After completing ONE task, output this and STOP immediately:**

```
CRITERION_DONE: <number>
```

Do NOT continue to the next task. STOP and wait for context refresh.

**Other signals:**

When ALL criteria are complete:
```
TASK_COMPLETE
```

If you are stuck and need human help:
```
STUCK: <reason>
```
