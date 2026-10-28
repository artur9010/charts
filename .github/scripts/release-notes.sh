#!/usr/bin/env bash
# Release notes for one chart, for the release workflow. Lists only the commits on
# master's first-parent history (merged PRs and direct pushes) that touched
# charts/<chart>/ since the chart's previous <chart>-* tag.
# Writes, when <chart>-<version> is not tagged yet:
#   <out>/<chart>.changes.yaml  Artifact Hub `artifacthub.io/changes` list
#   <out>/<chart>.md            GitHub Release body
# PR titles become the changelog entries, so keep them descriptive.
#
# Usage: release-notes.sh <chart> <out-dir> [rev]   (run from the repo root)
#   FORCE=1 also writes notes when the tag already exists (to preview a past release)
set -euo pipefail

chart=$1
out=$2
rev=$(git rev-parse "${3:-HEAD}")
repo_url=https://github.com/${GITHUB_REPOSITORY:-artur9010/charts}

version=$(git show "$rev:charts/$chart/Chart.yaml" | yq -r '.version')
description=$(git show "$rev:charts/$chart/Chart.yaml" | yq -r '.description // ""')
tag=$chart-$version

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null && [ -z "${FORCE:-}" ]; then
  echo "$tag already released, skipping" >&2
  exit 0
fi

# previous release of this chart; none means the whole history
prev=$(git describe --tags --abbrev=0 --match "$chart-*" --exclude "$tag" "$rev" 2>/dev/null || true)
range=${prev:+$prev..}$rev

# Artifact Hub kinds: added, changed, deprecated, removed, fixed, security
kind() {
  local t
  t=$(tr '[:upper:]' '[:lower:]' <<<"$1")
  case $t in
    *security* | *cve-*) echo security ;;
    feat* | add*) echo added ;;
    fix*) echo fixed ;;
    remove*) echo removed ;;
    deprecat*) echo deprecated ;;
    *) echo changed ;;
  esac
}

mkdir -p "$out"
changes=$out/$chart.changes.yaml
notes=$out/$chart.md
echo '[]' >"$changes"
bullets=

# fields separated by \x1f, records by \x1e
while IFS=$'\x1f' read -r -d $'\x1e' sha parents subject body; do
  sha=${sha#$'\n'}
  if [[ $parents == *" "* && $subject =~ ^Merge\ pull\ request\ \#([0-9]+) ]]; then
    # GitHub merge commit: the PR title is the first body line
    num=${BASH_REMATCH[1]}
    title=$(grep -m1 -v '^[[:space:]]*$' <<<"$body" || echo "$subject")
    link_name="PR #$num"
    link_url=$repo_url/pull/$num
  elif [[ $subject =~ \(\#([0-9]+)\)$ ]]; then
    # squash merge: "<title> (#N)"
    num=${BASH_REMATCH[1]}
    title=${subject% (#*)}
    link_name="PR #$num"
    link_url=$repo_url/pull/$num
  else
    title=$subject
    link_name="Commit ${sha:0:7}"
    link_url=$repo_url/commit/$sha
  fi
  K=$(kind "$title") D=$title N=$link_name U=$link_url \
    yq -i '. += [{"kind": strenv(K), "description": strenv(D), "links": [{"name": strenv(N), "url": strenv(U)}]}]' "$changes"
  bullets+="- $title ([$link_name]($link_url))"$'\n'
done < <(git log --first-parent --format='%H%x1f%P%x1f%s%x1f%b%x1e' "$range" -- "charts/$chart/")

if [ -z "$bullets" ]; then
  bullets="- No changes in charts/$chart/"$'\n'
  echo '[{"kind": "changed", "description": "No changes"}]' | yq -P >"$changes"
fi

{
  [ -n "$description" ] && printf '%s\n\n' "$description"
  printf '## Changes\n\n%s' "$bullets"
  [ -n "$prev" ] && printf '\n**Full Changelog**: %s/compare/%s...%s\n' "$repo_url" "$prev" "$tag"
  true
} >"$notes"

echo "Wrote $changes and $notes ($tag, since ${prev:-the beginning})" >&2
