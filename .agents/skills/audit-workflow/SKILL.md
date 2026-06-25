---
name: audit-workflow
description: Performs a comprehensive codebase audit focusing on Security, Accessibility, Usability, KISS (Keep It Simple, Stupid), and DRY (Don't Repeat Yourself).
---

# Codebase Audit Skill

## Purpose

When the user requests an "audit" or a "security/optimization pass", this skill defines the strict procedure you must follow to identify and refactor code smells, accessibility issues, and security vulnerabilities across the Migratron codebase.

## Audit Checklist

### 1. Security

- **Input Validation**: Check all `Read-Host` inputs and script `param()` blocks. Are paths sanitized before passing to `Test-Path` or `Join-Path`? Are regex patterns strict enough (e.g. `^([01][0-9]|2[0-3]):[0-5][0-9]$` instead of loose `\d{2}:\d{2}`)?
- **Data Leaks**: Ensure sensitive data (passwords, DPAPI keys) are not logged or stored in plaintext where they shouldn't be. Ensure `$env:TEMP` staging folders are strictly shredded using `finally` blocks or garbage collection.
- **Process Escalation**: Ensure scripts that require Administrator (`backup-profile.ps1`, `restore-profile.ps1`) call `Assert-AdminPrivileges` securely and correctly forward caller bound parameters.

### 2. Accessibility & Usability (UI)

- **Contrast**: `Write-Host` calls using `-ForegroundColor DarkGray` fail WCAG contrast ratios on black terminals. Prefer `Gray` or `Cyan`.
- **Clean Loops**: Interactive loops (`while ($true)`) must begin with `Clear-Host` and `Show-MenuHeader` to prevent the console from endlessly scrolling down and confusing the user.
- **Clear Prompts**: Ensure prompts have explicit bounds in their instructions, such as `[1-5, M, Q]`.

### 3. KISS & DRY

- **Don't Repeat Yourself (DRY)**: If multiple menu options or scripts execute the same logic (like loading configs or asserting admin), extract that logic to a central helper in `utils.ps1` or rely on the sub-script to assert it itself (e.g. stripping redundant `Assert-AdminPrivileges` from `migratron.ps1`).
- **Keep It Simple (KISS)**: Optimize I/O bottlenecks. For example, if a configuration JSON is read repeatedly in a loop, implement Global caching in `utils.ps1` (`$Global:CachedUsmtConfig`) to prevent redundant disk reads.

## Procedure

1. Create an `implementation_plan.md` listing the specific targets you found in the codebase matching these categories.
2. Present the plan to the user for approval.
3. Execute the changes safely using atomic replacements.
4. Follow the global "Definition of Done" (Format, Spellcheck, Changelog).
