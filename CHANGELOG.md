# Changelog

All notable changes to Migratron will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added

- **CSpell Configuration (`cspell.json`)** — Added spell-check configuration targeting en-GB with a full custom word list covering USMT terminology, PowerShell API names, and Migratron-specific identifiers.
- **Secondary Drive Audit (`scripts/scan-system.ps1`)** — Scan now enumerates all fixed local drives except the system drive (`C:`) and warns about any drive not covered by `excludePaths`. Helps users of any machine configuration identify drives that USMT may scan unexpectedly (e.g. secondary data drives, cloud sync caches, game libraries), with an actionable message directing them to add the drive to `usmt-config.local.json`.
- **User Scope Control (`usmt.userScope`)** — New config property (`"current"` or `"all"`, default `"current"`) controls which user profiles ScanState captures. `"current"` limits the backup to the user running the script (using `/ue:*\*` and `/ui:DOMAIN\USERNAME`); `"all"` captures every profile on the machine for multi-user scenarios. The effective scope is logged during backup and displayed in the system scan audit.
- **Named User List (`usmt.users[]`)** — New config array for explicitly naming which user accounts to capture (e.g. `["Alice"]` or `["DOMAIN\\Alice", "DOMAIN\\Bob"]`). When non-empty, takes precedence over `userScope`. Each entry becomes a `/ui:` argument; unqualified names are auto-prefixed with `$env:USERDOMAIN`. Displayed in the scan audit and logged during backup.
- **Standalone Restore Binaries** — `backup-profile.ps1` now automatically syncs a copy of the USMT executables (including `usmtutils.exe`) directly into a `USMT-Binaries/` directory within the backup output path. This ensures users can perform restores or manual extractions on new machines instantly via OneDrive, completely removing the requirement to download and install the Windows ADK on the destination PC.

### Added

- **List Backups Command (`scripts/list-backups.ps1`)** — Added a dedicated `[2] List Existing Backups` option to the main interactive menu in `migratron.ps1` (and a new `-List` switch) which parses and displays all compressed and uncompressed backup stores with their sizes and timestamps.

### Fixed

- **Retention of Uncompressed Backups (`scripts/backup-profile.ps1`)** — Fixed a bug where the backup retention policy would ignore uncompressed backups (when `compress: false`). It now correctly identifies both `.zip` archives and raw uncompressed folders, sorting and pruning them together accurately based on the `retentionCount` limit.

### Changed

- **Dynamic Architecture Detection (`scripts/utils.ps1`)** — `Find-UsmtPath` now dynamically detects the host OS architecture (`$env:PROCESSOR_ARCHITECTURE`) and preferentially resolves the native USMT binaries (`amd64`, `arm64`, or `x86`). This ensures ARM64 devices run native ARM64 USMT binaries rather than falling back to amd64 emulation. The standalone backup copies will also sync the correct native architecture.
- **Config Backup (`scripts/backup-profile.ps1`)** — `usmt-config.json` and `usmt-config.local.json` are now automatically copied into the backup staging folder alongside the `USMT-XML/` directory and `scanstate.log`. This ensures your exact Migratron schedule, users, and exclusion overrides are preserved and can be easily restored onto a new machine.
- **USMT Log Verbosity (`usmt-config.json`)** — Default `/v:13` (full debug dump, ~85k lines) reduced to `/v:1` (errors and warnings only) to dramatically shrink the `scanstate.log` file (from ~30MB+ to under 1MB). Override to `/v:5` (status) or `/v:13` in `usmt-config.local.json` when troubleshooting.
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
