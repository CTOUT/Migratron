# Changelog

All notable changes to Migratron will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added

- **CSpell Configuration (`cspell.json`)** — Added spell-check configuration targeting en-GB with a full custom word list covering USMT terminology, PowerShell API names, and Migratron-specific identifiers.

### Changed

- **PowerShell 7 Compatibility (`scripts/utils.ps1`, `scripts/schedule-task.ps1`)** — Self-elevation and scheduled task registration now detect the current PowerShell host at runtime (`pwsh.exe` for PS 7+, `powershell.exe` for Windows PowerShell 5.1), ensuring elevated sessions and scheduled tasks always run in the same shell they were launched from.

- **Security Hardening (`scripts/utils.ps1`)** — `Assert-AdminPrivileges` now accepts caller-supplied bound parameters and builds the UAC elevation `ArgumentList` as a typed string array with single-quote-escaped values, preventing shell metacharacter injection during self-elevation.
- **Security Hardening (`migratron.ps1`)** — All `Assert-AdminPrivileges` calls now forward `$PSBoundParameters`. Interactive scheduled-task input validated against an allowlist (`Daily`, `AtLogon`, `OnIdle`) and HH:mm regex before being passed to child scripts.
- **Security Hardening (`scripts/backup-profile.ps1`)** — `additionalArgs` from config filtered through a strict USMT flag allowlist. `excludePaths` values XML-encoded via `SecurityElement::Escape()` before embedding in generated XML. Runtime warning added when `encrypt: false`. Staging and log paths moved from repo root to `$env:TEMP`.
- **Security Hardening (`scripts/restore-profile.ps1`)** — Added Zip Slip protection (all extracted paths verified within staging directory before proceeding). Same `additionalArgs` allowlist applied to LoadState. Staging and log paths moved to `$env:TEMP`.
- **Security Hardening (`scripts/schedule-task.ps1`)** — Replaced `-ExecutionPolicy Bypass` with `-ExecutionPolicy RemoteSigned` in the scheduled task action.
- **Security Hardening (`scripts/utils.ps1`)** — Replaced `-ExecutionPolicy Bypass` with `-ExecutionPolicy RemoteSigned` in self-elevation.
- **Documentation (`SECURITY.md`)** — Corrected stale `config-manifest.json` reference to `usmt-config.json` and `usmt-config.local.json`.
- **Documentation (`README.md`)** — Updated repository structure table to reflect current files; corrected `backup.compress` default; converted to en-GB spelling throughout.
- **Documentation (`CONTRIBUTING.md`)** — Updated stale file references (`config-manifest.json` → `usmt-config.json`); converted to en-GB spelling throughout.

### Removed

- **`Copilot Suggestions.md`** — Removed original planning/prompt document; MVP is fully implemented.

---

## [0.1.0] — 2026-06-22

### Added

- **Repository Initialisation** — Established directory layout, MIT licence, citation templates (`CITATION.cff`), standard `.gitignore`, `.gitattributes`, `.markdownlint.json`, and `llms.txt`.
- **USMT-Based Architecture** — Transitioned Migratron from a simple file copying utility into a robust Windows User State Migration Tool (USMT) wrapper.
- **System Audit Module (`scripts/scan-system.ps1`)** — Added support to scan for USMT binaries, rule XML validation, OneDrive paths, and local backup stores.
- **USMT Staging & Backup Module (`scripts/backup-profile.ps1`)** — Created an elevated driver to run `scanstate.exe` with standard rules (`MigApp.xml`, `MigUser.xml`), saving ZIPs directly into your OneDrive backup directories.
- **USMT Staging & Restore Module (`scripts/restore-profile.ps1`)** — Created an elevated restoration driver running `loadstate.exe` from local folders or extracted ZIP files.
- **Scheduled Task Integration (`scripts/schedule-task.ps1`)** — Added an elevated manager to register daily, logon, or idle triggers running in your user context.
- **Console Interface Wrapper (`migratron.ps1`)** — Central command line router featuring self-elevation prompts and an interactive console dashboard.
- **USMT Configuration Parameters (`scripts/usmt-config.json`)** — Dynamic manifest configuring file targets, retention counts, and task variables.
