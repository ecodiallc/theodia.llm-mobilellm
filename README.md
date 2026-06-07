# Theodia LLM Model

This repo distributes Bible-specialized GGUF model as **GitHub Release assets** for the [Theodia mobile app](https://theodia.app). Models are not committed as git blobs — they are sharded into parts, attached to a tagged GitHub Release, and the app downloads them by combining the manifest in this repo with the release assets on GitHub.

There is no source code, no build system, and no test suite. The tracked files are `README.md` (this file), `manifest.json`, `manifest.schema.json`, and `.gitignore`. Everything large is in Releases.

> **First time?** Use the `/process-model` skill from Claude Code — it walks you through the whole flow, derives the `id` and `displayName` from the filename, validates `manifest.json` against the schema, and generates a paste-ready release body. The shell-only equivalent is `scripts/release.sh`. This README is the reference for both.

---

## TL;DR — set up a new LLM release from start to finish

**Before you start:** clone this repo, put your downloaded `.gguf` somewhere on disk, and have a GitHub account that can push to the org you'll release under (default `ecodiallc`). The full reference for each step is below this section.

```bash
# 1. Create the GitHub repo (one-time, do this from github.com or `gh`)
gh repo create ecodiallc/theodia.llm-<your-model> --public --description "Bible-specialized LLMs for Theodia"

# 2. Clone it locally and copy the bootstrap files in
gh repo clone ecodiallc/theodia.llm-<your-model>
cd theodia.llm-<your-model>
# (commit README.md, manifest.schema.json, scripts/, .claude/, .gitignore
#  from this template repo into your new one)

# 3. Open Claude Code in this directory and run the skill
claude
> /process-model https://huggingface.co/<org>/<model>-GGUF /path/to/your.gguf
```

The skill will:

- Suggest an `id` and `displayName` (you confirm).
- Show a dry-run summary and wait for `yes`.
- Shard the `.gguf` into `dist/<id>/`, verify the round-trip, compute `sha256` and `totalSizeBytes`.
- Write `manifest.json` and validate it against `manifest.schema.json`.
- Cross-check that `parts[]` matches the files on disk, and re-verify the `sha256`.
- Write `RELEASE-NOTES.md` (a paste-ready body for the GitHub Release).
- Commit, tag, and (after asking) push.

**What the skill does NOT do** (you do these by hand):

1. **Create the GitHub repo** — the skill can't create remote resources. Use `gh repo create` (see step 1 above) or the GitHub web UI. The skill's preflight runs `git init` if you forgot to clone first, but creating the GitHub remote is on you.
2. **Add the `origin` remote** — if you cloned an existing repo this is already done. If you used `git init` from the skill, the skill will prompt for `owner/repo` and offer to add the remote.
3. **Create the GitHub Release** — the skill commits and pushes the tag, but the Release itself (with the part files attached as assets) is created on github.com. Open the URL the skill prints, paste the contents of `RELEASE-NOTES.md` into the body, drag every `dist/<id>/part-NNN` file into the assets box, and publish.

**If you'd rather not use Claude Code**, `scripts/release.sh` does the same flow from a plain shell:

```bash
scripts/release.sh \
  https://huggingface.co/<org>/<model>-GGUF \
  /path/to/your.gguf
```

---

## What you'll produce

A single tag like `v1.0.0` on this repo whose GitHub Release contains:

1. A `manifest.json` committed in this repo describing the model.
2. N part files uploaded from `dist/<id>/part-001`, `dist/<id>/part-002`, … on disk. GitHub flattens uploads, so the assets are stored at the root of the Release as `part-001`, `part-002`, … — and that flat name is what `manifest.json`'s `parts[]` lists. The app reads each entry verbatim and uses it as the download URL suffix.

The Theodia app reads the manifest, downloads the parts in order, concatenates them, and verifies the resulting `.gguf` against `manifest.json`'s `sha256`.

---

## How it works (start here if it's your first time)

```
[your .gguf]  →  split into 1 GB parts in dist/<id>/  →  shasum the whole thing
                                                      ↓
                                       write manifest.json (parts, sizes, sha256)
                                                      ↓
                       commit manifest.json to main → tag vX.Y.Z → push
                                                      ↓
                          attach dist/<id>/part-NNN files to the GitHub Release
                            (GitHub stores them flat as part-001, part-002, …)
                                                      ↓
                          [Theodia app] downloads parts in order, concatenates,
                                       verifies sha256, loads the .gguf
```

Two things to internalize before you start:

- **GitHub rejects git blobs larger than 100 MB.** That is why we split the model. We split it into *parts* and attach them as *Release assets*, which have a much higher size limit (1 GB).
- **The app downloads from the Release, not from git.** If you forget to attach a part, the download fails for every user.

---

## End-to-end release process

### 1. Pick and source the model

Before you shard anything, record **where the GGUF came from** so future maintainers (and your future self) can reproduce the build. A Bible-specialized repo is only as trustworthy as its source.

1. **Choose the base model and quantization.** Q4_K_M is a good size/quality default; Q8_0 is heavier but higher fidelity. Pick before you download — you can't un-pick.
2. **Download from a known source.** Hugging Face is the usual source. Note the full model page URL and, if shown, the file's revision / commit hash. The model page for the example below is `https://huggingface.co/pjh64/MobileLLM_1B-GGUF`.
3. **Record the source in the release.** Both places:
   - The `manifest.json` `sourceUrl` / `sourceHash` fields (machine-readable, ships with the release).
   - The GitHub Release body, under `### Source` (human-readable, copy-paste friendly).

   The HF page URL is enough for most cases. The commit hash is gold-standard — pin it if you can; omit the field otherwise.

You'll capture this into `manifest.json` in step 5 and the release body in step 8.

### 2. Shard the GGUF

Pick a part size. **1 GB is a good default** (`1073741824` bytes). Smaller is also fine — `104857600` (100 MB) matches GitHub's git-blob limit, but you get fewer, larger parts to upload.

The `/process-model` skill and `scripts/release.sh` write parts to `dist/<id>/` to keep them out of the way of the rest of the repo. From a manual shell:

```bash
mkdir -p dist/mobilellm-1b-q8-0
split -b 1073741824 MobileLLM-1B-Q8_0.gguf dist/mobilellm-1b-q8-0/part-
```

This produces files named `dist/mobilellm-1b-q8-0/part-aa`, `dist/mobilellm-1b-q8-0/part-ab`, etc. Rename them to zero-padded ordinals so they sort in the order the app will concatenate them:

```bash
i=1
for f in dist/mobilellm-1b-q8-0/part-aa dist/mobilellm-1b-q8-0/part-ab ...; do
  printf -v n "%03d" $i
  mv "$f" "dist/mobilellm-1b-q8-0/part-$n"
  i=$((i+1))
done
```

You should end up with `dist/mobilellm-1b-q8-0/part-001`, `dist/mobilellm-1b-q8-0/part-002`, …

The on-disk names have a `dist/<id>/` prefix, but the manifest stores just `part-001`, `part-002`, … — that's the asset name GitHub uses once the upload is flattened. Putting a `dist/<id>/` prefix in the manifest produces 404s on download.

### 3. Verify the round-trip

The app will concatenate these parts back into the original file. Confirm locally that they reassemble identically before you upload anything:

```bash
cat dist/mobilellm-1b-q8-0/part-* > roundtrip.gguf
shasum -a 256 MobileLLM-1B-Q8_0.gguf roundtrip.gguf   # hashes MUST match
```

If the hashes don't match, the model will fail to load on every user's device. Re-run the split and check your concatenation order.

### 4. Compute the SHA-256

Compute the SHA-256 of the **full, unsharded** `.gguf` (what `cat dist/<id>/part-*` produces). The app uses this to verify the download:

```bash
shasum -a 256 MobileLLM-1B-Q8_0.gguf
# -> <hex-hash>  MobileLLM-1B-Q8_0.gguf
```

Copy the hex hash (no filename) into `manifest.json`. Verification is optional — if you'd rather skip it, omit the `sha256` field entirely (don't set it to `""`).

### 5. Write `manifest.json`

Create `manifest.json` at the repo root:

```json
{
  "id": "mobilellm-1b-q8-0",
  "displayName": "MobileLLM 1B (Q8_0)",
  "description": "1B-parameter Bible-specialized model, Q8_0 quantization. ~1.11 GB on device.",
  "releaseOwner": "ecodiallc",
  "releaseRepo": "theodia.llm-mobilellm",
  "releaseTag": "v1.0.0",
  "parts": [
    "part-001",
    "part-002"
  ],
  "totalSizeBytes": 1190000000,
  "sha256": "<sha256-of-concatenated-file>",
  "sourceUrl": "https://huggingface.co/pjh64/MobileLLM_1B-GGUF",
  "sourceHash": "<commit-or-revision-hash-from-hf>"
}
```

`manifest.schema.json` at the repo root defines the full schema. The skill (and the shell script, if `jsonschema` is installed) validate `manifest.json` against it after every write — typos in `id`, wrong part paths, or a missing `sourceUrl` will be caught automatically.

**Schema notes:**

| Field | Rule |
|---|---|
| `id` | Globally unique, lowercase, **stable across versions**. Renaming `id` breaks every existing install. Pattern: `^[a-z0-9][a-z0-9.-]*$`. |
| `displayName` | The name shown in the app's model picker. |
| `description` | 1–2 sentences for the picker UI. |
| `releaseOwner` | GitHub org/user that owns the release repo (e.g. `ecodiallc`). |
| `releaseRepo` | This repo's name on GitHub. |
| `releaseTag` | Semver with a `v` prefix, matching the git tag you push. |
| `parts` | **Every** part, in **strict concatenation order**. Each entry is the asset name as stored on the GitHub Release (e.g. `part-001`). GitHub flattens uploads, so the on-disk `dist/<id>/` prefix is dropped on the way to the Release and must NOT appear here — the app uses each entry verbatim as a download URL suffix. |
| `totalSizeBytes` | The **sum of every part's byte size**, not the size of any individual file. This drives the download progress bar. |
| `sha256` | Hash of the concatenated file, not of any individual part. Omit the field if unset. |
| `sourceUrl` | URL the original GGUF was downloaded from (Hugging Face model page). Required. |
| `sourceHash` | Commit / revision hash pinned at the HF repo, if available. Optional but recommended. |

### 6. Clean up local files

After the round-trip verifies, delete the original `.gguf` and `roundtrip.gguf` (the `.gitignore` already excludes them). The sharded parts under `dist/<id>/` stay on disk — they will be attached to the release next. `dist/<id>/part-*` is ignored by `.gitignore`, so the directory can stay in the working tree without being committed.

### 7. Commit the manifest and tag the release

**Do not commit anything under `dist/`.** `.gitignore` excludes `**/part-*` (which matches `dist/<id>/part-001` and friends), and even if you force-added them, GitHub rejects git blobs > 100 MB. Only commit `manifest.json` and `RELEASE-NOTES.md`:

```bash
git add manifest.json RELEASE-NOTES.md
git commit -m "Release mobilellm-1b-q8-0 at v1.0.0"
git tag v1.0.0
git push origin v1.0.0
```

**Semver meaning for model:**

- **Major** (`v1 → v2`) — new tokenizer, chat template, or training run; incompatible with previous app versions.
- **Minor** (`v1.0 → v1.1`) — revised weights / vocabulary; the app will re-download.
- **Patch** (`v1.0.0 → v1.0.1`) — republish the same weights after a bad upload.

### 8. Create the GitHub Release

On GitHub: **Releases → Draft a new release**.

- **Tag:** the one you just pushed (e.g. `v1.0.0`).
- **Title:** the model display name, e.g. `MobileLLM 1B (Q8_0)`.
- **Body:** paste the contents of `RELEASE-NOTES.md` (the skill or `scripts/release.sh` generates this for you; it has `### Source`, `### Manifest`, and `### Notes` sections). If you don't have a `RELEASE-NOTES.md`, include a `### Manifest` section with the full `manifest.json` block, a `### Source` line with the source URL (and pinned revision hash, if you have one), and a short `### Notes` section listing the number of parts and confirming SHA-256 verification.
- **Assets:** drag every `dist/<id>/part-NNN` file into the release assets box.
- Click **Publish release.**

> **Critical:** the app downloads release assets, not git-tracked blobs. If a part isn't attached to the release, the download will fail for every user.

---

## Storage and rate limits

- GitHub Releases soft cap: **~2 GB per asset** on free/org plans. If a model approaches this, split into more parts or multiple releases.
- Unauthenticated downloads are throttled at **60 requests/hour/IP**. The app can use a GitHub PAT (configured in Theodia's Settings → Resources) to raise the limit to **5,000/hour**.

---

## Files in this repo

- `README.md` — this document.
- `manifest.json` — the current model's metadata; the only file the app reads from git.
- `manifest.schema.json` — JSON Schema for `manifest.json`. Validated automatically by `/process-model` and `scripts/release.sh` after every write.
- `scripts/release.sh` — non-interactive shell wrapper around the same flow (for re-runs from a clean clone).
- `.claude/commands/process-model.md` — the `/process-model` skill that drives the flow from Claude Code.
- `.gitignore` — excludes the unsharded `.gguf`, the round-trip verification file, and macOS resource forks. Also matches `**/part-*` (covers `dist/<id>/part-001`, etc.).

Everything else (the part files) lives on the GitHub Release, not in git.
