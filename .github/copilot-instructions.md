# GitHub Copilot Instructions

## General Standards

- **Language & Spelling**: Enforce UK English (`en-GB`) across all documentation and comments.
- **Error Handling**: For PowerShell scripts, enforce `$ErrorActionPreference = 'Stop'` and use modern PS7 syntax.
- **Code Style & Formatting**: Follow `.editorconfig`, `.prettierrc`, and `.markdownlint.json` rules.
- **Security & Hygiene**: Never hardcode secrets, credentials, or absolute local user paths. Use environment variables and portable path helpers (`Join-Path`, `$HOME`).
