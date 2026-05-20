# AGENTS.md

## Project Instructions

- Communicate with the user in Japanese by default. Use another language only when the user explicitly asks for it or when quoting source text.
- Use MCP servers and MCP tools when they are available and relevant.
- Prefer MCP or official integration tools for repository metadata, GitHub Issues/PRs, CI status, and other external system state instead of inferring those details from local files alone.
- If MCP is unavailable or cannot provide the needed information, fall back to local files, CLI commands, or user confirmation, and mention that limitation in the final report when it affects confidence or verification.
- Keep implementation changes scoped to the current task and avoid unrelated refactors.
- Do not revert user changes unless the user explicitly asks for that.
