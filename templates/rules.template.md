# Rules

Guidelines for Claude to follow during autonomous execution.

## Testing

- Run tests after every code change
- Test command: `[YOUR TEST COMMAND]`
- Never skip failing tests - fix them

## Code Style

- Follow existing code patterns in the codebase
- Keep changes minimal and focused
- Don't refactor unrelated code

## Safety

- Never delete data without confirmation
- Never modify production configs
- Never commit secrets or credentials

## Project-Specific

<!-- Add your project-specific rules here -->
<!-- Examples:
- Always use TypeScript strict mode
- API responses must include error handling
- Database queries must use parameterized statements
- All new endpoints need integration tests
-->
