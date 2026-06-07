# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

This repository distributes Bible-specialized GGUF models as GitHub Release assets for [Theodia mobile app](https://theodia.app). It contains **no source code, no build system, and no tests**. The tracked files are `README.md`, `manifest.json`, `manifest.schema.json`, `scripts/release.sh`, `.claude/commands/process-model.md`, and `.gitignore`. The sharded model parts live under `dist/<id>/` (gitignored) and on the GitHub Release as assets — never in git.

## Full instructions: see README.md

All release-process documentation — sourcing, sharding, round-trip verification, manifest schema, tagging, GitHub Release creation, storage limits — lives in `README.md`. Read it before doing anything in this repo. Mistakes here break downloads for every user.

## How to do a release

The developer-facing flow is the `/process-model` slash command (`.claude/commands/process-model.md`). When invoked from Claude Code, it walks through the whole release:

- Auto-suggests `id` and `displayName` from the `.gguf` filename (asks for confirmation).
- Runs preflight (clean tree, no tag at HEAD, origin remote matches, monotonic semver).
- Prints a dry-run summary and waits for `yes`.
- Shards into `dist/<id>/`, verifies the round-trip, computes `totalSizeBytes` and `sha256`.
- Writes `manifest.json` and validates it against `manifest.schema.json`.
- Cross-checks that `parts[]` in the manifest matches the files on disk, and that the recorded `sha256` matches the file (catches copy-paste errors).
- Writes `RELEASE-NOTES.md` (paste-ready body for the GitHub Release).
- Commits, tags, and (after asking) pushes.

The non-interactive shell equivalent is `scripts/release.sh`. It does the same flow with `jq` + `shasum` + `git` instead of Claude. It's the source-of-truth for what `/process-model` does.

## Manifest schema (quick reference)

See `manifest.schema.json` for the authoritative schema. Required fields: `id`, `displayName`, `description`, `releaseOwner`, `releaseRepo`, `releaseTag`, `parts[]`, `totalSizeBytes`, `sourceUrl`. Optional: `sha256`, `sourceHash`. Don't add or rename fields without coordinating with the app.

`parts[]` paths are relative to the repo root and start with `dist/<id>/` (e.g. `dist/mobilellm-1b-q8-0/part-001`).

## Storage limits to remember

- GitHub rejects git blobs > 100 MB — `**/part-*` is in `.gitignore` (matches `dist/<id>/part-NNN` in any subdirectory), so the parts are never staged. Even if you force-added them, GitHub would reject them.
- GitHub Releases soft cap: ~2 GB per asset on free/org plans. Split into more parts if needed.
- Unauthenticated downloads are throttled at 60 requests/hour/IP. The app can use a GitHub PAT (Settings → Resources) to raise the limit to 5,000/hour.
