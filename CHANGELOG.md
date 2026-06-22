# Changelog

All notable changes to Migratron will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added

- **Repository Initialisation** — Established directory layout, MIT license, citation templates (`CITATION.cff`), standard `.gitignore`, `.gitattributes`, `.markdownlint.json`, and `llms.txt`.
- **USMT-Based Architecture** — Transitioned Migratron from a simple file copying utility into a robust Windows User State Migration Tool (USMT) wrapper.
- **System Audit Module (`scripts/scan-system.ps1`)** — Added support to scan for USMT binaries, rule XML validation, OneDrive paths, and local backup stores.
- **USMT Staging & Backup Module (`scripts/backup-profile.ps1`)** — Created an elevated driver to run `scanstate.exe` with standard rules (`MigApp.xml`, `MigUser.xml`), saving ZIPs directly into your OneDrive backup directories.
- **USMT Staging & Restore Module (`scripts/restore-profile.ps1`)** — Created an elevated restoration driver running `loadstate.exe` from local folders or extracted ZIP files.
- **Scheduled Task Integration (`scripts/schedule-task.ps1`)** — Added an elevated manager to register daily, logon, or idle triggers running in your user context.
- **Console Interface Wrapper (`migratron.ps1`)** — Central command line router featuring self-elevation prompts and an interactive console dashboard.
- **USMT Configuration Parameters (`scripts/usmt-config.json`)** — Dynamic manifest configuring file targets, retention counts, and task variables.
