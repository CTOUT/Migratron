---
name: release-workflow
description: Orchestrates the semantic version bump, changelog update, and git tagging for a new release.
---

# Release Workflow Skill

## Purpose

When the user asks to "Release" a new version or cut a release, this skill defines the exact procedure you must follow to bump versions, format, commit, and tag the repository correctly.

## Procedure

1. **Determine Version Bump**: Review the changes in `CHANGELOG.md` under `[Unreleased]` and determine the correct Semantic Version bump (Major, Minor, or Patch) based on the latest tagged version.
2. **Update Version**: Run the script `scripts/update-version.ps1 -Version <new_version>` (e.g., `-Version 1.4.0`) to seamlessly update all configurations and scripts.
3. **Update Changelog**: Change the `[Unreleased]` header in `CHANGELOG.md` to `[<new_version>] - <YYYY-MM-DD>` and add a new blank `[Unreleased]` section at the top.
4. **Format & Spellcheck**: Run `npm run format` and `npm run spellcheck` to ensure the new changelog and version updates are fully compliant.
5. **Commit**: Stage all files and commit to git: `git commit -am "chore: release v<new_version>"`
6. **Tag**: Tag the release commit: `git tag v<new_version>`
7. **Notify**: Inform the user that the release has been successfully staged and tagged locally, and remind them to push the tags if necessary (`git push --tags`).
