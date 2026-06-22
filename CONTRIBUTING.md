# Contributing to Migratron

Thanks for your interest in contributing. This document covers the development workflow and pre-commit checklist.

A [pull request template](.github/pull_request_template.md) is pre-filled when you open a PR on GitHub — it mirrors the checklist below.

---

## Pre-commit Checklist

### Script / Toolkit changes (`migratron.ps1`, `scripts/*.ps1`)

- [ ] PowerShell scripts are fully compatible with Windows PowerShell 5.1 and PowerShell 7+
- [ ] No hardcoded user paths — use environment variables (`$env:USERPROFILE`, `$env:APPDATA`, etc.) or resolve paths through the manifest resolver
- [ ] Scripts use standard `Write-Output`, `Write-Warning`, `Write-Error` via log wrappers, and respect `-DryRun` parameters
- [ ] Added help documentation inline inside PowerShell scripts
- [ ] `CHANGELOG.md` updated under `[Unreleased] → Added / Changed / Fixed`
- [ ] `README.md` updated if user-facing behaviour or commands change

### Manifest changes (`scripts/config-manifest.json`)

- [ ] New items follow the JSON Schema under `schemas/manifest-schema.json`
- [ ] Environment variables in paths are correctly formatted (e.g. `$HOME`, `$APPDATA`, `$LOCALAPPDATA`)
- [ ] Commands, file paths, and registry keys verified against a real Windows installation
- [ ] Sensitive items (like SSH keys, credentials) are marked as optional and include warnings

### Repository / docs changes

- [ ] `README.md` Repository Structure section reflects any new/removed files
- [ ] `CHANGELOG.md` updated
- [ ] `TODO.md` updated if a tracked item is completed or a new one is added

---

## Changelog Format

Follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Add entries under `## [Unreleased]`.

```markdown
## [Unreleased]

### Added

- Short description of new feature

### Changed

- Short description of change to existing behaviour

### Fixed

- Short description of bug fix
```

---

## Cutting a Release

1. Ensure `CHANGELOG.md` `[Unreleased]` section is complete
2. Rename `[Unreleased]` to `[vX.Y.Z] — YYYY-MM-DD`
3. Add a new empty `[Unreleased]` section above it
4. Update the diff links at the bottom of `CHANGELOG.md`
5. Commit: `chore: prepare release vX.Y.Z`
6. Tag: `git tag vX.Y.Z -m "<release notes>"`
7. Push: `git push && git push --tags`
