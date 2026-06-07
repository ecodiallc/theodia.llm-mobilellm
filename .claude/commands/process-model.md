---
allowed-tools: Read, Edit, Write, Bash(git:*), Bash(ls:*), Bash(shasum:*), Bash(stat:*), Bash(cat:*), Bash(split:*), Bash(rm:*), Bash(mv:*), Bash(mkdir:*), Bash(printf:*), Bash(find:*), Bash(echo:*), Bash(grep:*), Bash(sort:*), Bash(awk:*), Bash(sed:*), Bash(wc:*), Bash(du:*), Bash(python3:*)
description: Shard a local GGUF, write manifest.json, generate release notes, commit and tag
argument-hint: <sourceUrl> <path-to-model.gguf> [id] [displayName] [releaseTag] [--source-hash <hash>] [--part-size <bytes>]
---

# Process a new Theodia LLM model

You are taking a local `.gguf` file all the way through the sharding, manifest, and tagging steps of a Theodia model release. The developer still creates the GitHub Release from the web UI and attaches the part files (the app downloads from Releases, not git).

Read `@README.md` for the full picture. **Mistakes in this repo break downloads for every user.** The defensive checks below exist because every one of them has caused a real broken release in the past.

## Repo state at start

Git status: !`git status --porcelain 2>&1 || echo "(not a git repo)"`
Git branch: !`git branch --show-current 2>/dev/null || echo "(no branch)"`
HEAD: !`git rev-parse --short HEAD 2>/dev/null || echo "(no commits)"`
Existing dist: !`ls -la dist/ 2>/dev/null || echo "No dist/ yet"`
Existing manifest: @manifest.json
Existing schema: @manifest.schema.json

## Arguments

Required:

- `sourceUrl` — where the `.gguf` was downloaded from (Hugging Face model page, etc.). Recorded in `manifest.json` `sourceUrl`. *Hint:* copy the model page URL (e.g. `https://huggingface.co/<org>/<model>-GGUF`) — that's what `sourceUrl` is for.
- `path-to-model.gguf` — absolute or repo-relative path to the local `.gguf` file. *Hint:* use an absolute path if the file is outside the repo so the skill can re-shasum it across runs without ambiguity.

Optional:

- `id` — globally unique, lowercase, stable across versions. e.g. `mobilellm-1b-q8-0`. **If omitted, derive from the filename and ask the developer to confirm before using.** Never change an existing `id`; renaming breaks every install. *Hint:* only set this if the auto-derived value (see below) is wrong. The most common reason to override is a transform artifact like `1.7B` → `1-7b`.
- `displayName` — shown in the app's model picker. e.g. `MobileLLM 1B (Q8_0)`. **If omitted, derive from the filename and ask the developer to confirm.** *Hint:* override to rebrand (e.g. add "Bible-specialized"), or to add a known model family the filename omits.
- `releaseTag` — semver with `v` prefix, e.g. `v1.0.0`. Default `v1.0.0`. *Hint:* use a patch bump (`v1.0.0` → `v1.0.1`) to re-publish the same weights after a bad upload, minor (`v1.0` → `v1.1`) for revised weights, major (`v1` → `v2`) only on a new tokenizer or chat template.
- `--source-hash <hash>` — pinned HF commit/revision recorded in `sourceHash`. Omit the field entirely if not provided; don't write `""`. *Hint:* pass this to make the release reproducible — copy the commit hash from the HF model's "Files and versions" tab. Skipping is fine for the first release.
- `--part-size <bytes>` — override the default 1 GB (`1073741824`) part size. Use 100 MB (`104857600`) for very large GGUFs that would breach the per-asset soft cap. *Hint:* only needed if the model is >2 GB after sharding at the default. Smaller parts = more upload work, not faster downloads.

### Deriving `id` and `displayName` from the filename

Given `MobileLLM-1B-Q8_0.gguf`:

- `id` → lowercase, replace `.` and `_` with `-`, then strip any non-`[a-z0-9-]` chars → `mobilellm-1b-q8-0`. **Note:** this naive transform can drop the dot in tokens like `1.7B` (`1-7b`). If that happens, mention the discrepancy in the confirmation prompt and let the developer override.
- `displayName` → split on `-` and `_`, restore `.` and case, wrap the quantization token in parens → `MobileLLM 1B (Q8_0)`.

Show the derived values, then ask: "Use `id: mobilellm-1b-q8-0` and `displayName: MobileLLM 1B (Q8_0)`? [Y/n / edit]". If the developer wants to edit, ask for each one separately.

If the user did not provide required arguments (`sourceUrl` or the `.gguf` path), ask for them **explicitly** before proceeding. Don't guess the source URL or the path.

## Workflow

### 1. Preflight

Run all of these. If any fails, **stop and tell the developer what to fix** — do not proceed.

1. **Initialize git if needed.** If `.git/` does not exist in the current directory, run `git init` and set the default branch to `main` (`git init -b main` if available, else `git init && git checkout -b main 2>/dev/null || true`). Note in the dry-run summary that this happened. **If the working tree has untracked files after the init (e.g. `README.md`, `manifest.json`, `manifest.schema.json` that were already in the directory), do not fail the dirty-tree check; instead, tell the developer "I just initialized a fresh repo. The existing files in this directory are now untracked. To continue, run `git add . && git commit -m 'initial repo'` yourself and re-run /process-model, or tell me to make the initial commit."**
2. **Working tree clean.** `git status --porcelain` is empty. Exceptions:
   - On a repo that we just initialized in step 1, untracked files in the directory (e.g. `README.md`, `manifest.json`, `manifest.schema.json`) are expected — the developer hasn't committed them yet. Stop with the message described in step 1 and wait for them to make the initial commit and re-run.
   - Otherwise, untracked `dist/` part files and untracked `manifest.json` / `RELEASE-NOTES.md` from a prior in-progress run mean the developer should clean up before continuing.
3. **HEAD is not already at the requested tag.** `git tag --points-at HEAD | grep -qx <releaseTag>` should be false. If true, the developer is trying to re-release the same commit — confirm intent.
4. **`origin` remote exists and matches `releaseOwner`/`releaseRepo`.** `git remote get-url origin` should resolve to `git@github.com:<releaseOwner>/<releaseRepo>.git` (or the https form). If `releaseOwner`/`releaseRepo` are not yet known, ask the developer; default `releaseOwner: ecodiallc`. The `releaseRepo` is the GitHub repo name — if ambiguous, infer from the local repo's directory name. **If the repo was just initialized, no `origin` exists yet — that's expected; the developer will add it before the push step (or you can prompt them to add it now).**
5. **Monotonic semver bump for the same `id`.** List every existing tag (`git tag --list 'v*' --sort=-version:refname`); if any tag is `≥` the requested `<releaseTag>`, warn. The warning is non-fatal — there are legitimate reasons to republish (bad upload, hot-fix) — but the developer must type `yes` to confirm.
6. **Tools on PATH.** `split`, `shasum`, `git`, `python3` (used for sha256 reverify and semver comparison).
7. **Source `.gguf` is a regular file.** `ls -la <path>` and `file <path>` if available.
8. **Schema file exists.** `@manifest.schema.json` should be present. If it's not, the developer needs to commit the schema first. (If you just ran `git init` in step 1, the schema is there as a working-tree file but uncommitted — that's fine for this step, the next stage will commit it.)

### 2. Dry-run summary

Print a one-screen summary, then **wait for `yes`**:

```
Source URL      : <sourceUrl>
File            : <path-to-model.gguf>  (<bytes>)
id              : <id>
displayName     : <displayName>
releaseTag      : <releaseTag>
sourceHash      : <hash, or "(omitted)">
part size       : <bytes>  (~<N> parts expected)
destination     : dist/<id>/
git repo        : <status — "initialized (no remote yet)" if preflight ran `git init`, otherwise existing>
origin          : <remote URL, or "(none — add before push)">
I will:
  - split the .gguf into N parts of <size> bytes
  - verify the round-trip shasum matches the original
  - write manifest.json and RELEASE-NOTES.md
  - delete the original .gguf and roundtrip.gguf
  - commit manifest.json and RELEASE-NOTES.md
  - tag <releaseTag> and push to origin
Continue? [y/N]
```

Do not start step 3 until the developer types `yes` (or `y`).

### 3. Shard the GGUF

```bash
mkdir -p dist/<id>
split -b <part-size> <path-to-model.gguf> dist/<id>/part-
```

`split` writes `dist/<id>/part-aa`, `dist/<id>/part-ab`, … Renumber to zero-padded ordinals:

```bash
i=1
for f in dist/<id>/part-aa dist/<id>/part-ab ...; do
  printf -v n "%03d" $i
  mv "$f" "dist/<id>/part-$n"
  i=$((i+1))
done
```

After the loop, confirm `ls dist/<id>/` shows `part-001`, `part-002`, … with no gaps.

### 4. Verify the round-trip

```bash
cat dist/<id>/part-* > roundtrip.gguf
shasum -a 256 <path-to-model.gguf> roundtrip.gguf
```

If the two hashes don't match: **stop**, `rm -rf dist/<id>/ roundtrip.gguf`, and tell the developer to re-run. Do not proceed to a broken release.

### 5. Compute SHA-256 for the manifest

```bash
shasum -a 256 <path-to-model.gguf>
```

Capture the hex hash. This is the `sha256` field in `manifest.json`.

### 6. Compute `totalSizeBytes`

```bash
ls -l dist/<id>/part-* | awk '{sum += $5} END {print sum}'
```

This is `totalSizeBytes` — the sum of every part, **not** the size of the parts list or any single file. The progress bar uses it as 100%.

### 7. Write or update `manifest.json`

If `manifest.json` does not exist, create it. If it does and its `id` matches the new release, update in place (preserve `id`); if `id` is different, the developer is shipping a new model — confirm before overwriting.

`parts` stores the **asset name as it will live on the GitHub Release** (e.g. `part-001`), not the on-disk `dist/<id>/part-001` path. GitHub flattens uploads, so the on-disk prefix is dropped on the way to the Release. The app reads each entry verbatim and uses it as the download URL suffix — including any prefix would 404.

Fields:

```json
{
  "id": "<id>",
  "displayName": "<displayName>",
  "description": "<1-2 sentence description, ask the developer if not provided>",
  "releaseOwner": "<releaseOwner>",
  "releaseRepo": "<releaseRepo>",
  "releaseTag": "<releaseTag>",
  "parts": ["part-001", "part-002", "..."],
  "totalSizeBytes": <sum>,
  "sha256": "<hex hash>",
  "sourceUrl": "<sourceUrl>",
  "sourceHash": "<pinned HF commit/revision hash, omit field if not provided>"
}
```

Notes:

- `parts` must be every part, in concatenation order, with the asset name as it will appear on the Release (basename only).
- `totalSizeBytes` is the **sum** of part sizes — verify with `ls -l dist/<id>/part-* | awk`.
- `sha256` is the hash of the **concatenated** file, same as the original `.gguf`. Not the hash of individual parts.
- `sourceUrl` is required. `sourceHash` is optional — if absent, **omit the field** (do not write `""`).
- If updating an existing `manifest.json` for the same `id`, only the `parts`, `totalSizeBytes`, `sha256`, `releaseTag`, and source fields should change.

### 8. Verify the manifest

Three checks, all required, any failure is a hard stop.

**8a. Schema.** Validate against `manifest.schema.json`:

```bash
python3 -c "
import json, sys
try:
    import jsonschema
except ImportError:
    print('jsonschema not installed; skipping schema check (install with: pip3 install jsonschema)')
    sys.exit(0)
m = json.load(open('manifest.json'))
s = json.load(open('manifest.schema.json'))
jsonschema.validate(m, s)
print('schema OK')
"
```

If `jsonschema` is unavailable, the skill should warn and continue, not block.

**8b. parts[] matches disk.** For every entry in `manifest.json`'s `parts[]`, the file must exist; for every `dist/<id>/part-*` on disk, an entry must exist. Mismatch is a hard stop.

```bash
python3 -c "
import json, os, sys
m = json.load(open('manifest.json'))
on_disk = sorted(f for f in os.listdir('dist/<id>') if f.startswith('part-'))
in_manifest = sorted(os.path.basename(p) for p in m['parts'])
if on_disk != in_manifest:
    print(f'MISMATCH: on disk {on_disk} != manifest {in_manifest}', file=sys.stderr)
    sys.exit(1)
print(f'{len(on_disk)} parts match')
"
```

**8c. SHA-256 reverify.** Re-run `shasum -a 256 <path-to-model.gguf>` and assert it equals the manifest's `sha256`. Catches copy-paste errors during step 7.

```bash
computed=$(shasum -a 256 <path-to-model.gguf> | awk '{print $1}')
recorded=$(python3 -c "import json; print(json.load(open('manifest.json'))['sha256'])")
[ "$computed" = "$recorded" ] || { echo "sha256 mismatch: $computed vs $recorded"; exit 1; }
```

### 9. Generate `RELEASE-NOTES.md`

Write `RELEASE-NOTES.md` at the repo root. The developer copy-pastes this into the GitHub Release body.

```markdown
## <displayName>

<description>

### Source

- URL: <sourceUrl>
- Pinned revision: <sourceHash or "(not pinned)">

### Manifest

```json
<full manifest.json block>
```

### Notes

- <N> parts in `dist/<id>/` (largest <size>, last part smaller).
- Total size: <totalSizeBytes> bytes (~<GB>).
- SHA-256 of concatenated file: `<sha256>` (verified after download).
```

Print the path to stdout.

### 10. Clean up local files

```bash
rm <path-to-model.gguf> roundtrip.gguf
```

`dist/<id>/` stays on disk — the developer attaches those files to the GitHub Release.

### 11. Commit and tag

Do **not** commit anything under `dist/`. `.gitignore` already excludes `**/part-*` (matches `dist/<id>/part-NNN` in any subdirectory). Only commit `manifest.json` and `RELEASE-NOTES.md`:

```bash
git add manifest.json RELEASE-NOTES.md
git commit -m "Release <id> at <releaseTag>"
git tag <releaseTag>
git push origin <releaseTag>
```

`git push` is allowed because the developer explicitly invoked this skill, but ask before pushing if they want to inspect the commit first.

### 12. Hand off to the developer

Print, in plain text:

1. The `dist/<id>/` directory contains `<N>` part files ready to upload.
2. Open GitHub → Releases → **Draft a new release** with tag `<releaseTag>`.
3. Title: `<displayName>`.
4. Body: paste the contents of `RELEASE-NOTES.md` (printed above).
5. **Attach every `dist/<id>/part-NNN` file** as a release asset. This is the critical step — the app downloads from the Release, not from git. GitHub will store the assets flat as `part-001`, `part-002`, etc., which is what `manifest.json`'s `parts[]` lists.
6. After publishing, run the `verify` skill to spot-check the release is reachable.

## Semver guidance (mention if it's a re-release of an existing `id`)

- **Major** (`v1 → v2`) — new tokenizer, chat template, or training run; incompatible with previous app versions.
- **Minor** (`v1.0 → v1.1`) — revised weights / vocabulary; app will re-download.
- **Patch** (`v1.0.0 → v1.0.1`) — republish the same weights after a bad upload.

## Rules

- `id` must never change across versions of the same model. Renaming `id` breaks every existing install.
- `parts` order in `manifest.json` must match concatenation order. The cross-check in step 8b enforces this.
- `totalSizeBytes` must be the sum of part sizes — not a single part, not the array length.
- `sha256` is the hash of the concatenated file, same as the original `.gguf`. The reverify in step 8c enforces this.
- Never commit anything under `dist/` or any `**/part-*` file. `.gitignore` excludes them. Don't force-add.
- If the round-trip verification fails, abort and clean up. Do not publish a broken release.
- If any preflight check fails, abort. Do not start step 2.
- The dry-run summary must get a `yes` before step 3.
