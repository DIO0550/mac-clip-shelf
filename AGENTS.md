# AGENTS.md

## Project Instructions

- Communicate with the user in Japanese by default. Use another language only when the user explicitly asks for it or when quoting source text.
- If MCP servers or MCP tools are available for the task, use them.
- Use MCP or official integration tools for repository metadata, GitHub Issues/PRs, CI status, and other external system state instead of inferring those details from local files alone.
- If MCP is unavailable or cannot provide the needed information, fall back to local files, CLI commands, or user confirmation, and mention that limitation in the final report when it affects confidence or verification.
- For Xcode projects, run builds and tests through the Xcode MCP tools when available. Fall back to `xcodebuild` or local CLI commands only when Xcode MCP is unavailable or insufficient, and report that fallback in the final response.
- Before starting implementation work, create or switch to a task-specific branch from the appropriate base branch. Do not implement directly on `main` unless the user explicitly instructs you to do so.
- Keep implementation changes scoped to the current task and avoid unrelated refactors.
- Do not revert user changes unless the user explicitly asks for that.
