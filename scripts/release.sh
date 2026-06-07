#!/usr/bin/env bash
#
# scripts/release.sh — non-Claude wrapper for the Theodia model release flow.
#
# This is a deliberately simple shell version of the /process-model skill. The
# skill is the source of truth; this script exists for re-runs from a clean
# clone or for non-interactive use.
#
# Usage:
#   scripts/release.sh <sourceUrl> <path-to-model.gguf> [id] [displayName] [releaseTag] [description]
#
# Required: sourceUrl, path-to-model.gguf
# Optional: id (derived if absent), displayName (derived if absent),
#           releaseTag (default v1.0.0), description (default "")
#
# Requires: bash, git, split, shasum, jq, python3. Optional: jsonschema (pip3
# install jsonschema) — the schema check is skipped if missing.

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
note() { echo "==> $*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require_cmd git
require_cmd split
require_cmd shasum
require_cmd jq
require_cmd python3

# --- Args ---
[[ $# -ge 2 ]] || die "usage: $0 <sourceUrl> <path-to-model.gguf> [id] [displayName] [releaseTag] [description]"

sourceUrl=$1
gguf_path=$2
id=${3:-}
display_name=${4:-}
release_tag=${5:-v1.0.0}
description=${6:-}

[[ -f "$gguf_path" ]] || die "gguf not found: $gguf_path"
[[ "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]] || die "releaseTag must be semver with v prefix, got: $release_tag"

# --- Derive id / displayName from filename if not provided ---
filename=$(basename "$gguf_path" .gguf)
if [[ -z $id ]]; then
  id=$(printf '%s' "$filename" | tr '[:upper:]' '[:lower:]' | tr '._' '-' | tr -cd 'a-z0-9-')
  note "derived id: $id"
fi
if [[ -z $display_name ]]; then
  # Split filename on - and _, restore case, wrap last token (quant) in parens if it looks like one.
  # Best-effort only — the developer should review.
  display_name=$(printf '%s' "$filename" | sed -E 's/[-_]/ /g; s/Q(8_?0|K(_M)?)/(\0)/g; s/[\(](.*)[\)]/(\1)/g')
  note "derived displayName: $display_name (please review before publishing)"
fi

# --- Preflight ---
git_initialized=0
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  note "no .git/ found in $(pwd) — initializing a fresh repo"
  if git init -b main >/dev/null 2>&1; then
    :
  else
    # Older git that doesn't support `init -b`. Create the default branch as main.
    git init >/dev/null 2>&1
    git symbolic-ref HEAD refs/heads/main >/dev/null 2>&1 || true
  fi
  git_initialized=1
fi

[[ -z "$(git status --porcelain)" ]] || die "working tree not clean — commit or stash first
   (untracked files are fine on a brand-new repo that we just initialized;
   commit them with: git add . && git commit -m 'initial repo' and re-run)"
git rev-parse --verify HEAD >/dev/null
if git tag --points-at HEAD | grep -qx "$release_tag"; then
  die "HEAD is already at tag $release_tag"
fi
[[ -f manifest.schema.json ]] || die "manifest.schema.json not found in repo root"

# Check for origin remote. After a fresh `git init`, no remote exists; the
# developer must add it before the push step. We only fail if a release_tag is
# already present but the remote is missing — a fresh repo with no tags is fine.
origin_url=$(git remote get-url origin 2>/dev/null || true)
if [[ -z $origin_url ]] && [[ $git_initialized -eq 0 ]] && [[ -n $(git tag --list 'v*' 2>/dev/null) ]]; then
  die "no origin remote — add one with: git remote add origin <url>"
fi

# Find existing tags for the same id. Heuristic: tags whose number portion is
# semver. We compare by stripping the v prefix and using sort -V.
existing_tag=$(git tag --list 'v*' --sort=-version:refname | head -n1 || true)
if [[ -n $existing_tag ]]; then
  if printf '%s\n%s\n' "$existing_tag" "$release_tag" | sort -V | tail -n1 | grep -qx "$release_tag"; then
    note "warning: $release_tag is not a strict bump from $existing_tag (existing tag for this id is newer or equal)"
    read -r -p "Continue anyway? [y/N] " ans
    [[ $ans =~ ^[Yy]$ ]] || exit 1
  fi
fi

# --- Dry-run summary ---
gguf_bytes=$(stat -f%z "$gguf_path" 2>/dev/null || stat -c%s "$gguf_path")
part_size=1073741824
expected_parts=$(( (gguf_bytes + part_size - 1) / part_size ))

if [[ $git_initialized -eq 1 ]]; then
  git_repo_status="initialized in this run (no commits yet)"
else
  git_repo_status="existing"
fi
origin_display=${origin_url:-(none — will ask)}

cat <<EOF
Source URL      : $sourceUrl
File            : $gguf_path  ($gguf_bytes bytes)
id              : $id
displayName     : $display_name
releaseTag      : $release_tag
part size       : $part_size  (~$expected_parts parts expected)
destination     : dist/$id/
git repo        : $git_repo_status
origin          : $origin_display
I will:
  - split the .gguf into ~$expected_parts parts
  - verify the round-trip shasum
  - write manifest.json and RELEASE-NOTES.md
  - delete the original .gguf and roundtrip.gguf
  - commit manifest.json and RELEASE-NOTES.md
  - tag $release_tag and push to origin
Continue? [y/N]
EOF
read -r ans
[[ $ans =~ ^[Yy]$ ]] || exit 1

# --- Shard ---
note "sharding $gguf_path"
mkdir -p "dist/$id"
split -b $part_size "$gguf_path" "dist/$id/part-"

# Renumber to zero-padded ordinals.
i=1
for f in "dist/$id/part-aa" "dist/$id/part-ab" "dist/$id/part-ac" "dist/$id/part-ad" \
         "dist/$id/part-ae" "dist/$id/part-af" "dist/$id/part-ag" "dist/$id/part-ah" \
         "dist/$id/part-ai" "dist/$id/part-aj" "dist/$id/part-ak" "dist/$id/part-al" \
         "dist/$id/part-am" "dist/$id/part-an" "dist/$id/part-ao" "dist/$id/part-ap"; do
  [[ -f "$f" ]] || continue
  printf -v n "%03d" $i
  mv "$f" "dist/$id/part-$n"
  i=$((i+1))
done

# --- Round-trip verify ---
note "verifying round-trip"
cat "dist/$id/part-"* > roundtrip.gguf
shasum -a 256 "$gguf_path" roundtrip.gguf
original_hash=$(shasum -a 256 "$gguf_path" | awk '{print $1}')
roundtrip_hash=$(shasum -a 256 roundtrip.gguf | awk '{print $1}')
[[ "$original_hash" == "$roundtrip_hash" ]] || die "round-trip hash mismatch: $original_hash vs $roundtrip_hash"

# --- Build parts array and totalSizeBytes ---
# parts[] stores asset names (basename only), not the on-disk dist/<id>/ path.
# GitHub flattens uploads, so the asset name on the Release is just part-NNN.
# Use a while-read loop (not `mapfile`, which is bash 4+) so the script runs on
# macOS's stock bash 3.2 as well.
parts=()
while IFS= read -r f; do
  parts+=("$(basename "$f")")
done < <(ls "dist/$id/part-"* | sort)
parts_json=$(printf '%s\n' "${parts[@]}" | jq -R . | jq -s .)
total_size_bytes=$(ls -l "dist/$id/part-"* | awk '{sum += $5} END {print sum}')

# --- Resolve releaseOwner / releaseRepo from origin remote ---
# If we just initialized the repo, no origin exists yet. Ask the developer for
# the GitHub owner/repo and offer to add it as a remote.
if [[ -z $origin_url ]]; then
  read -r -p "no origin remote — enter the GitHub owner (e.g. ecodiallc): " release_owner
  read -r -p "enter the repo name (e.g. theodia.llm-mobilellm): " release_repo
  [[ -n $release_owner && -n $release_repo ]] || die "owner and repo are required"
  read -r -p "add remote origin as git@github.com:$release_owner/$release_repo.git? [Y/n] " ans
  if [[ ! $ans =~ ^[Nn]$ ]]; then
    git remote add origin "git@github.com:$release_owner/$release_repo.git"
    note "added origin remote"
  fi
  origin_url="git@github.com:$release_owner/$release_repo.git"
fi
# Try to extract owner/repo. Supports git@github.com:owner/repo.git and https://github.com/owner/repo(.git).
release_owner=$(printf '%s' "$origin_url" | sed -E 's#^(git@github\.com:|https://github\.com/)([^/]+)/.*$#\2#')
release_repo=$(printf '%s' "$origin_url" | sed -E 's#^(git@github\.com:[^/]+/|[^/]+/[^/]+/|.*/)([^/]+)(\.git)?$#\2#')
[[ -n $release_owner && -n $release_repo ]] || die "could not parse owner/repo from origin: $origin_url"

# --- Write manifest.json ---
note "writing manifest.json"
manifest=$(jq -n \
  --arg id "$id" \
  --arg displayName "$display_name" \
  --arg description "$description" \
  --arg releaseOwner "$release_owner" \
  --arg releaseRepo "$release_repo" \
  --arg releaseTag "$release_tag" \
  --argjson parts "$parts_json" \
  --argjson totalSizeBytes "$total_size_bytes" \
  --arg sha256 "$original_hash" \
  --arg sourceUrl "$sourceUrl" \
  '{id: $id, displayName: $displayName, description: $description,
    releaseOwner: $releaseOwner, releaseRepo: $releaseRepo, releaseTag: $releaseTag,
    parts: $parts, totalSizeBytes: $totalSizeBytes, sha256: $sha256, sourceUrl: $sourceUrl}')
echo "$manifest" | jq . > manifest.json

# --- Validate against schema (best-effort) ---
if python3 -c 'import jsonschema' 2>/dev/null; then
  python3 -c "
import json, jsonschema
m = json.load(open('manifest.json'))
s = json.load(open('manifest.schema.json'))
jsonschema.validate(m, s)
print('schema OK')
"
else
  note "jsonschema not installed; skipping schema check"
fi

# --- Cross-check: parts[] in manifest matches disk ---
python3 -c "
import json, os, sys
m = json.load(open('manifest.json'))
on_disk = sorted(f for f in os.listdir('dist/$id') if f.startswith('part-'))
in_manifest = sorted(os.path.basename(p) for p in m['parts'])
assert on_disk == in_manifest, f'mismatch: disk {on_disk} != manifest {in_manifest}'
print(f'{len(on_disk)} parts match disk')
"

# --- Write RELEASE-NOTES.md ---
note "writing RELEASE-NOTES.md"
{
  echo "## $display_name"
  echo
  [[ -n $description ]] && { echo "$description"; echo; }
  echo "### Source"
  echo
  echo "- URL: $sourceUrl"
  echo "- Pinned revision: (not pinned)"
  echo
  echo "### Manifest"
  echo
  echo '```json'
  cat manifest.json
  echo
  echo '```'
  echo
  echo "### Notes"
  echo
  echo "- ${#parts[@]} parts in \`dist/$id/\` (each ~$part_size bytes, last part smaller)."
  echo "- Total size: $total_size_bytes bytes."
  echo "- SHA-256 of concatenated file: \`$original_hash\` (verified after download)."
} > RELEASE-NOTES.md

cat RELEASE-NOTES.md
echo
note "RELEASE-NOTES.md written"

# --- Cleanup ---
note "cleaning up original .gguf and roundtrip.gguf"
rm "$gguf_path" roundtrip.gguf

# --- Commit + tag ---
note "committing manifest.json and RELEASE-NOTES.md"
git add manifest.json RELEASE-NOTES.md
git commit -m "Release $id at $release_tag"
git tag "$release_tag"

read -r -p "Push tag $release_tag to origin? [y/N] " ans
[[ $ans =~ ^[Yy]$ ]] || { note "not pushing. Run: git push origin $release_tag"; exit 0; }
git push origin "$release_tag"

cat <<EOF

Done. To finish the release:
  1. Open GitHub → Releases → Draft a new release with tag $release_tag.
  2. Title: $display_name
  3. Body: paste the contents of RELEASE-NOTES.md
  4. Attach every dist/$id/part-NNN file as a release asset.
  5. Publish.
EOF
