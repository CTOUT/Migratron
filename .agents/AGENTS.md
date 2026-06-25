# Migratron Project Rules

## Definition of Done

Before marking any task, feature, or bugfix as "completed", you MUST autonomously execute the following checklist without waiting for the user to ask:

1. **Format**: Run `npm run format` to ensure code style consistency across all JSON, Markdown, and JS files.
2. **Spellcheck**: Run `npm run spellcheck`. If technical terms fail, you must add them to `cspell.json` and rerun until it passes cleanly.
3. **Documentation**: Update `CHANGELOG.md` under the `[Unreleased]` header with a clear, concise description of your changes. Update `TODO.md` to check off or remove any completed items.
4. **Walkthrough**: Update or create a `walkthrough.md` artifact showing the user what was achieved.
