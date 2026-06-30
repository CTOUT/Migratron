# Changelog

All notable changes to Migratron will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

---

## [v1.6.0] — 2026-06-30

### Added

- **Native Auto-Updater** — Migratron now includes `scripts/update-migratron.ps1` to natively query GitHub for updates and safely pull them via Git.
- **Smart Agent Auto-Updating** — The Smart Background Agent now features a "Check for Updates" context menu item. Additionally, a new configuration property `agent.autoUpdate` (default: true) instructs the agent to silently check for and pull updates once every 24 hours while idle, and automatically restart itself if new code is detected.
- **Version Display** — The system tray agent now natively parses `migratron.ps1` to display the active Migratron version directly inside its context menu.

---

## [v1.5.0] — 2026-06-29

### Added

- **Smart Agent Manual Bypass** — Clicking "Backup Now" from the system tray agent now bypasses all idle-time suspension logic, forcing the backup to run immediately at normal priority.
- **Smart Agent Throttling Mode** — Added a new schema configuration `agent.actionOnUserActivity` with options `Suspend`, `Throttle`, and `Ignore`. The default is now `Throttle`, which lowers the backup CPU priority to `Idle` when the user returns to the PC, allowing backups to slowly trickle through to completion instead of freezing entirely and starving.

### Changed

- **Schema Enhancements** — Iterated over all configuration sections in `usmt-config-schema.json` to formally declare the `default` attribute for every single property, matching the shipping `usmt-config.json`. This ensures IDE tooltips properly display default values for properties like `excludePaths` and `gfsRetention`.

---

## [v1.4.1] — 2026-06-25

### Added

- **Audit Workflow Skill** — Created `.agents/skills/audit-workflow/SKILL.md` to formally codify the codebase audit procedure for Security, Accessibility, Usability, and KISS/DRY principles.

### Changed

- **Documentation** — Refined the Windows ADK installation instructions in the README to explicitly advise running `winget pin add --id Microsoft.WindowsADK` after a manual installation, preventing unexpected background updates to incompatible Insider versions. Also clarified that users may wish to leave other ADK features checked if they use them for external workflows.
- **Documentation** — Completely audited the `README.md` to formally document recent additions to the project architecture, including the Smart Background Agent (`migratron-agent.ps1`), the AI Workspace Customizations folder (`.agents/`), and the new interactive path management wizards (`manage-excludes.ps1`).
- **Accessibility Color Sweep** — Replaced all instances of `DarkGray` terminal output with `Gray` to adhere to WCAG contrast ratio guidelines on black terminals.
- **Config Caching (KISS)** — Implemented global caching for `Get-UsmtConfig` in `utils.ps1` to prevent redundant JSON parsing during deep interactive menu loops.
- **Redundant Privilege Checks (DRY)** — Stripped redundant `Assert-AdminPrivileges` calls from the main menu loop (`migratron.ps1`), centralizing elevation enforcement safely inside the respective module scripts.
- **Time Validation Security** — Strengthened the Regex bounds for user-provided Scheduled Task times from `^\d{2}:\d{2}$` to strict 24-hour validation `^([01][0-9]|2[0-3]):[0-5][0-9]$`.

---

## [v1.4.0] — 2026-06-25

---

## [v1.4.0] — 2026-06-25

### Added

- **Smart Service Layer** — Built `migratron-agent.ps1`, a lightweight background agent that intelligently polls user idle time using `GetLastInputInfo` and hooks into Windows `WM_QUERYENDSESSION` to guarantee zero-impact backups.
- **Process Suspension Hooks** — Integrated native `ntdll.dll` hooks into the agent to instantly suspend running USMT backups if the user returns to the keyboard, dropping CPU usage to 0% and resuming when idle.
- **Agent Context Menu** — Added a dynamic System Tray icon that reports live status (Idle, Running Backup, Paused) and tracks the last successful backup timestamp dynamically.
- **Workspace Customizations** — Introduced `.agents` folder for AI Agent Rules (`AGENTS.md`) and Skills (`SKILL.md`), formally codifying definition-of-done and release procedures.

### Changed

- **Schedule Task Logic** — Upgraded `schedule-task.ps1` and `migratron.ps1` to natively support installing and running the new Smart Agent, ensuring conflicting scheduled tasks are automatically purged.
- **Agent Schema Settings** — Added the `agent` configuration block to `usmt-config.json` with controls for idle thresholds and tray icon visibility.

### Fixed

- **Uncompressed Backup Discovery** — Fixed an issue where `Get-LastBackupTime` failed to detect uncompressed folder backups by updating the filter to match `migratron-store-*`.

---

## [v1.3.0] — 2026-06-24

### Added

- **Interactive Discovery Wizard Dashboard** — Upgraded the AppData discovery tool into an interactive, paginated terminal dashboard featuring active status indicators and OSC 8 clickable path hyperlinks.
- **In-Wizard Exclusions** — Users can now natively include (`i <id>`), exclude (`e <id>`), or remove (`r <id>`) paths directly within the discovery wizard loop.
- **Global Microsoft Bloat Exclusions** — Added `<unconditionalExclude>` rules to `ExcludeCommon.xml` permanently blocking massively bloated Microsoft telemetry and client caches (e.g., `OneDrive`, `Edge`, `Olk`, `Office`, `Copilot`), saving ~30GB per backup.
- **Manage Custom Exclusions Menu** — Added `manage-excludes.ps1` and `Option 7` to the interactive CLI to manage custom `excludePaths` in `usmt-config.local.json`.

---

## [v1.2.0] — 2026-06-24

### Added

- **Interactive Verification Loop** — Added a `while` loop to the `[3] Verify Backup Archive` menu choice, allowing sequential verification of multiple archives without returning to the root menu.
- **Custom Backup Output Directory** — Added `[4] Set Backup Output Directory` to the configuration dashboard, allowing users to select between Corporate OneDrive, Consumer OneDrive, or arbitrary custom paths.
- **Verify Menu UI Refresh** — Added `Clear-Host` and `Show-MenuHeader` to the verify loop to keep the dashboard uncluttered during repetitive verifications.

### Changed

- **Codebase Refactoring (DRY & KISS)** — Abstracted ZIP extraction (`Expand-SecureArchive`) and DPAPI encryption key handling (`Write-UsmtKeyFile`) into central `utils.ps1` helpers, significantly shrinking and simplifying `backup-profile`, `restore-profile`, and `verify-backup`.
- **Password Fallback Limit** — Verification module restricts manual password guesses to a single attempt before cleanly returning to the backup selection list.

### Fixed

- **Zip-Slip Staging Cleanup Vulnerability** — Secured the verification module's `usmtutils` block with strict `try...finally` boundaries to ensure that fully decrypted staging directories (`$env:TEMP`) are forcefully shredded even if the user forcibly aborts execution (`Ctrl+C`) or an unexpected terminating error occurs.
- **Double-Enter Verification Bug** — Removed redundant `Read-Host "Press Enter"` prompts when cancelling a backup verification selection, ensuring immediate return to the parent menu.
- **Verification Syntax Error** — Fixed an isolated syntax parsing exception caused by a stray bracket in the retention pruning block of `backup-profile.ps1`.

---

## [v1.1.0] — 2026-06-24

### Added

- **Secure Archive Encryption** — Implemented AES_256 encryption via native USMT flags when `encrypt: true`. Supported plain-text passwords and Windows DPAPI encoded SecureStrings via the new `encryptionKeyEncoded` parameter.
- **Advanced GFS Retention Policy** — Introduced Grandfather-Father-Son rotation scheme (dailies, weeklies, monthlies) as an alternative to simple rolling retention, allowing long-term historical snapshots for disaster recovery.
- **Archive Contents Viewer** — Built an interactive HTML manifest viewer generation script (`generate-viewer.ps1`) that parses the raw USMT manifest and outputs a searchable, filterable HTML report of captured settings and files.
- **Interactive CLI Enhancements** — Overhauled the console menu (`migratron.ps1`) into nested submenus. Added interactive menus to manage scheduled tasks, toggle backup retention types (Simple vs GFS), manage encryption keys (including SecureString DPAPI encoding), and configure counts. Added a global `[Q] Quit` hotkey.
- **Include Paths Mode (`backup.includePaths`)** — Added explicit local capture paths (e.g., `AppData\LocalLow`) via auto-generated `IncludeCustom.xml` using `<unconditionalInclude>` rules.
- **Interactive Deletion** — Added `-InteractiveDelete` to `list-backups.ps1`, allowing users to select and delete specific backup folders by number.
- **Password Confirmation** — Added a continuous matching loop when setting or toggling encryption keys to prevent typos from breaking the configuration.
- **Key Validation** — Added a `[6] Verify Current Encryption Key` option to the menu (visible when a key is set) allowing users to safely verify their stored key matches their expectations.
- **Encoding Prompt** — Turning on encryption when no key is set now actively prompts the user to choose their preferred encoding format (Plaintext vs DPAPI) before requesting the password.

### Changed

- **Immediate Encryption Toggle** — `[3] Toggle Encryption` in the menu now instantly inverts the boolean setting without prompting `y/n`.

### Fixed

- **Encryption Key Encoding Bugs** — Fixed an issue where PowerShell's `Out-File` injected UTF-8 BOMs and CRLF terminators into the temporary encryption key file, causing USMT decryption verification (Return Code 37) to fail. Now uses `[System.IO.File]::WriteAllText` with `UTF8NoBOM`.
- **Config Cleanup** — When an encryption key is explicitly cleared, Migratron now ensures that `encryptionKeyEncoded` is also scrubbed from `usmt-config.local.json` and immediately defaults `encrypt` to `$false`.

---

## [v1.0.0] — 2026-06-23

### Added

- Standardized repository configurations (.editorconfig, Prettier)
- Automated CSpell dictionaries and validation workflows
- Automated GitHub Release workflows

### Added

- **CSpell Configuration (`cspell.json`)** — Added spell-check configuration targeting en-GB with a full custom word list covering USMT terminology, PowerShell API names, and Migratron-specific identifiers.
- **Secondary Drive Audit (`scripts/scan-system.ps1`)** — Scan now enumerates all fixed local drives except the system drive (`C:`) and warns about any drive not covered by `excludePaths`. Helps users of any machine configuration identify drives that USMT may scan unexpectedly (e.g. secondary data drives, cloud sync caches, game libraries), with an actionable message directing them to add the drive to `usmt-config.local.json`.
- **User Scope Control (`usmt.userScope`)** — New config property (`"current"` or `"all"`, default `"current"`) controls which user profiles ScanState captures. `"current"` limits the backup to the user running the script (using `/ue:*\*` and `/ui:DOMAIN\USERNAME`); `"all"` captures every profile on the machine for multi-user scenarios. The effective scope is logged during backup and displayed in the system scan audit.
- **Named User List (`usmt.users[]`)** — New config array for explicitly naming which user accounts to capture (e.g. `["Alice"]` or `["DOMAIN\\Alice", "DOMAIN\\Bob"]`). When non-empty, takes precedence over `userScope`. Each entry becomes a `/ui:` argument; unqualified names are auto-prefixed with `$env:USERDOMAIN`. Displayed in the scan audit and logged during backup.
- **Standalone Restore Binaries** — `backup-profile.ps1` now automatically syncs a copy of the USMT executables (including `usmtutils.exe`) directly into a `USMT-Binaries/` directory within the backup output path. This ensures users can perform restores or manual extractions on new machines instantly via OneDrive, completely removing the requirement to download and install the Windows ADK on the destination PC.

### Added

- **List Backups Command (`scripts/list-backups.ps1`)** — Added a dedicated `[2] List Existing Backups` option to the main interactive menu in `migratron.ps1` (and a new `-List` switch) which parses and displays all compressed and uncompressed backup stores with their sizes and timestamps.

### Fixed

- **Silent Scheduled Tasks (`scripts/schedule-task.ps1`)** — Automated tasks now execute PowerShell with `-WindowStyle Hidden`, preventing the console window from popping up and stealing focus during the daily background run.
- **Smart Binary Sync (`scripts/backup-profile.ps1`)** — The USMT binary sync to OneDrive is now strictly differential. It checks the `LastWriteTime` of the local ADK against the OneDrive copy. If they are identical, it skips the 30MB copy to save network bandwidth. If the local ADK is newer, it explicitly deletes the OneDrive copy first to prevent orphaned DLLs before syncing the fresh binaries.
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
