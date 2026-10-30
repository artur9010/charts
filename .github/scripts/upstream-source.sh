#!/usr/bin/env bash
# Fetch the upstream source changes of every image and subchart bumped between two
# commits, for the renovate-changelog workflow. The review of a bump is mandatory, so
# anything that can't be resolved (unmapped image, missing tag, failed clone) exits
# non-zero instead of being skipped.
#
# Upstream repos come from .github/upstream-sources.yaml and are cloned to <out>/repos/.
# Each bump is written to <out>/<chart>/upstream/<repo>/part-NNN.txt: the commit list,
# the diffstat and the source diff (no vendored code, lockfiles or tests), split so one
# part fits in a single tool call. <out>/upstream.md lists the parts for the model.
#
# <manifest> and <manifest>.parts must be kept out of <out>: every part starts and ends
# with a random token listed there, and review-check.sh looks for those tokens in the
# tool output to prove that the model read the whole part.
#
# Usage: upstream-source.sh <base-rev> <head-rev> <out-dir> <manifest>   (from the repo root)
set -euo pipefail

base=$(git rev-parse "$1")
head=$(git rev-parse "$2")
out=$3
manifest=$4
map=.github/upstream-sources.yaml
# Parts are smaller than opencode's tool output limit (2000 lines, 50 KB)
part_bytes=${PART_BYTES:-40000}
part_lines=${PART_LINES:-1500}
# Upper limit per bump, the rest is reported as not reviewed in the PR comment
max_bytes=${MAX_SOURCE_BYTES:-1200000}

mkdir -p "$out"
: >"$manifest"
: >"$manifest.parts"
: >"$out/upstream.md"

# "repository<TAB>tag" of every image in a chart's values.yaml at a revision
images() {
  git show "$1:charts/$2/values.yaml" 2>/dev/null |
    yq -N '.. | select(tag == "!!map" and has("repository") and has("tag")) | .repository + "	" + (.tag | sub("@.*$"; ""))'
}

# "name<TAB>version" of every dependency of a chart at a revision
subcharts() {
  git show "$1:charts/$2/Chart.yaml" 2>/dev/null |
    yq -N '.dependencies // [] | .[] | .name + "	" + .version'
}

clone() {
  local repo=$1 dest="$out/repos/${1##*/}"
  [ -d "$dest" ] || git clone -q --filter=blob:none "https://github.com/$repo" "$dest"
}

# Print the git tag for a version, trying each candidate in turn
resolve_tag() {
  local repo=$1 candidate
  shift
  for candidate in "$@"; do
    if git -C "$out/repos/${repo##*/}" rev-parse -q --verify "refs/tags/$candidate" >/dev/null; then
      echo "$candidate"
      return
    fi
  done
  echo "error: no tag in $repo matches: $*" >&2
  return 1
}

# Write one bump as numbered parts and record them in the manifest
write_parts() {
  local chart=$1 repo=$2 old=$3 new=$4 name=${2##*/} git_dir dir all commits files total kept
  git_dir="$out/repos/$name"
  dir="$out/$chart/upstream/$name"
  mkdir -p "$dir"
  all=$(mktemp)

  commits=$(git -C "$git_dir" rev-list --no-merges --count "$old..$new")
  files=$(git -C "$git_dir" diff --name-only "$old" "$new" | wc -l)
  {
    echo "# $repo $old..$new: $commits commits, $files files changed"
    echo
    echo "## Commits"
    git -C "$git_dir" log --no-merges --format='%h %s' "$old..$new"
    echo
    echo "## Changed files (all)"
    git -C "$git_dir" diff --stat=120 "$old" "$new"
    echo
    echo "## Source diff (no vendored code, lockfiles or tests)"
    git -C "$git_dir" diff "$old" "$new" -- . \
      ':(exclude,glob)**/vendor/**' ':(exclude,glob)**/node_modules/**' ':(exclude,glob)**/testdata/**' \
      ':(exclude,glob)**/test/**' ':(exclude,glob)**/tests/**' ':(exclude,glob)**/*_test.go' \
      ':(exclude,glob)**/go.sum' ':(exclude,glob)**/package-lock.json' ':(exclude,glob)**/yarn.lock' \
      ':(exclude,glob)**/pnpm-lock.yaml' ':(exclude,glob)**/*.pb.go' ':(exclude,glob)**/*.snap'
  } >"$all"

  total=$(wc -c <"$all")
  kept=$(head -c "$max_bytes" "$all" | wc -c)
  # Long lines are cut (minified files), a part must never exceed one tool output
  head -c "$max_bytes" "$all" | cut -c1-4000 | LC_ALL=C awk -v dir="$dir" -v max_bytes="$part_bytes" -v max_lines="$part_lines" '
    function part() { return sprintf("%s/part-%03d.txt", dir, n) }
    NR == 1 || bytes + length($0) + 1 > max_bytes || lines >= max_lines {
      if (NR > 1) close(part())
      n++; bytes = 0; lines = 0
    }
    { print > part(); bytes += length($0) + 1; lines++ }'
  rm "$all"

  local part start end tmp
  for part in "$dir"/part-*.txt; do
    start=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
    end=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
    tmp=$(mktemp)
    { echo "<<< part start $start"; cat "$part"; echo; echo "<<< part end $end"; } >"$tmp"
    mv "$tmp" "$part"
    chmod 644 "$part"
    printf '%s\t%s\t%s\n' "${part#"$out"/}" "$start" "$end" >>"$manifest.parts"
    echo "- \`${part#"$out"/}\`" >>"$out/upstream.md"
  done
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$chart" "$repo" "$old" "$new" "$commits" "$files" "$kept" "$total" >>"$manifest"
  echo "  $repo $old..$new: $commits commits, $files files, $kept of $total bytes"
}

review_image() {
  local chart=$1 image=$2 old=$3 new=$4 repo old_tag new_tag
  repo=$(IMAGE=$image yq -r '.images[strenv(IMAGE)].repo // ""' "$map")
  if [ -z "$repo" ]; then
    echo "error: image $image of chart $chart is not in $map" >&2
    return 1
  fi
  clone "$repo"
  old_tag=$(resolve_tag "$repo" "$old" "v$old")
  new_tag=$(resolve_tag "$repo" "$new" "v$new")
  write_parts "$chart" "$repo" "$old_tag" "$new_tag"
}

review_subchart() {
  local chart=$1 name=$2 old=$3 new=$4 repo template old_tag new_tag
  repo=$(NAME=$name yq -r '.subcharts[strenv(NAME)].repo // ""' "$map")
  template=$(NAME=$name yq -r '.subcharts[strenv(NAME)].tag // ""' "$map")
  if [ -z "$repo" ] || [ -z "$template" ]; then
    echo "error: subchart $name of chart $chart is not in $map" >&2
    return 1
  fi
  clone "$repo"
  old_tag=$(resolve_tag "$repo" "${template//\{version\}/$old}")
  new_tag=$(resolve_tag "$repo" "${template//\{version\}/$new}")
  write_parts "$chart" "$repo" "$old_tag" "$new_tag"
}

# Pair the old and new version of each key in two "key<TAB>version" lists and print
# "key<TAB>old<TAB>new" for the changed ones. A key only in the new list (a renamed image
# or a new subchart) has no old version to diff against, so it can't be reviewed.
changed() {
  local tab added
  tab=$(printf '\t')
  added=$(join -t "$tab" -v2 <(sort -u "$1") <(sort -u "$2") | cut -f1)
  if [ -n "$added" ]; then
    echo "error: no previous version to compare for: $added" >&2
    return 1
  fi
  join -t "$tab" <(sort -u "$1") <(sort -u "$2") | awk -F'\t' '$2 != $3'
}

mapfile -t charts < <(git diff --name-only "$base" "$head" -- 'charts/*' | cut -d/ -f2 | sort -u)
for chart in "${charts[@]}"; do
  git cat-file -e "$head:charts/$chart/Chart.yaml" 2>/dev/null || continue
  echo "== $chart"
  before=$(mktemp)
  after=$(mktemp)

  images "$base" "$chart" >"$before"
  images "$head" "$chart" >"$after"
  # Assigned first, a process substitution would hide a failure of `changed`
  list=$(changed "$before" "$after")
  while IFS=$'\t' read -r image old new; do
    [ -z "$image" ] || review_image "$chart" "$image" "$old" "$new"
  done <<<"$list"

  subcharts "$base" "$chart" >"$before"
  subcharts "$head" "$chart" >"$after"
  list=$(changed "$before" "$after")
  while IFS=$'\t' read -r name old new; do
    [ -z "$name" ] || review_subchart "$chart" "$name" "$old" "$new"
  done <<<"$list"

  rm "$before" "$after"
done
