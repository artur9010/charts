#!/usr/bin/env bash
# Diff the charts changed between two commits, for the renovate-changelog workflow.
# Writes, per changed chart, to <out>/<chart>/:
#   rendered.diff  diff of `helm template` output with the chart's default values
#   objects.diff   objects (kind/name) and images added/removed in that output
# and, when the chart's dependencies changed, for the upstream subcharts:
#   values.diff    upstream Chart.yaml, values.yaml, values.schema.json
#   docs.diff      upstream README/UPGRADING/CHANGELOG/MIGRATION files
#   templates.diff upstream templates
#   crds.diff      upstream CRDs
# Upstream subcharts are pulled with `helm pull` (their archives aren't committed)
# and unpacked under <out>/<chart>/src/{old,new}/.
#
# Usage: chart-diff.sh <base-rev> <head-rev> <out-dir>   (run from the repo root)
set -euo pipefail

base=$(git rev-parse "$1")
head=$(git rev-parse "$2")
out=$3
# Per-file cap, so one huge chart can't fill the model context
max_bytes=${MAX_BYTES:-300000}

mkdir -p "$out"
out=$(cd "$out" && pwd)

cap() {
  local f=$1 size
  size=$(wc -c <"$f")
  if [ "$size" -gt "$max_bytes" ]; then
    head -c "$max_bytes" "$f" >"$f.tmp"
    printf '\n\n[... truncated: %s of %s bytes shown ...]\n' "$max_bytes" "$size" >>"$f.tmp"
    mv "$f.tmp" "$f"
  fi
}

# Dependencies of a chart at a revision, one "name version repository" per line
deps() {
  git show "$1:charts/$2/Chart.yaml" 2>/dev/null |
    yq -N '.dependencies // [] | .[] | .name + " " + .version + " " + (.repository // "")'
}

# Pull the given dependencies into dest, then unpack nested subchart .tgz in place
pull() {
  local dest=$1 name version repo
  shift
  mkdir -p "$dest"
  for dep in "$@"; do
    read -r name version repo <<<"$dep"
    case "$repo" in
      oci://*) helm pull "$repo/$name" --version "$version" --untar --untardir "$dest" ;;
      http*) helm pull "$name" --repo "$repo" --version "$version" --untar --untardir "$dest" ;;
      *) echo "  skipping $name: unsupported repository '$repo'" ;;
    esac
  done
  while IFS= read -r -d '' tgz; do
    tar -xzf "$tgz" -C "$(dirname "$tgz")" && rm "$tgz"
  done < <(find "$dest" -path '*/charts/*.tgz' -print0)
}

render() {
  local rev=$1 chart=$2 dest=$3 dir
  dir=$(mktemp -d)
  git archive "$rev" "charts/$chart" | tar -x -C "$dir"
  if ! { helm dependency build "$dir/charts/$chart" >/dev/null &&
    helm template "$chart" "$dir/charts/$chart" >"$dest"; } 2>"$dest.err"; then
    rm -rf "$dir"
    return 1
  fi
  rm -rf "$dir" "$dest.err"
}

if ! command -v yq >/dev/null; then
  echo "yq (mikefarah/yq) is required" >&2
  exit 1
fi

mapfile -t charts < <(git diff --name-only "$base" "$head" -- 'charts/*' | cut -d/ -f2 | sort -u)
if [ "${#charts[@]}" -eq 0 ]; then
  echo "No charts changed between $base and $head."
  exit 0
fi

# `helm dependency build` needs every dependency repository added
n=0
while read -r repo; do
  helm repo add --force-update "dep$((n++))" "$repo" >/dev/null
done < <(for chart in "${charts[@]}"; do deps "$base" "$chart"; deps "$head" "$chart"; done |
  awk '$3 ~ /^http/ {print $3}' | sort -u)

for chart in "${charts[@]}"; do
  git cat-file -e "$head:charts/$chart/Chart.yaml" 2>/dev/null || continue
  echo "== $chart"
  dir="$out/$chart"
  mkdir -p "$dir"

  # Only the dependencies whose version changed
  mapfile -t old < <(comm -23 <(deps "$base" "$chart" | sort) <(deps "$head" "$chart" | sort))
  mapfile -t new < <(comm -13 <(deps "$base" "$chart" | sort) <(deps "$head" "$chart" | sort))
  if [ "${#old[@]}" -gt 0 ] || [ "${#new[@]}" -gt 0 ]; then
    pull "$dir/src/old" "${old[@]}"
    pull "$dir/src/new" "${new[@]}"

    # One diff per kind of file, at any depth (nested subcharts included), so the
    # big ones (CRDs, dashboards) can't push values changes past the cap
    : >"$dir/values.diff"; : >"$dir/docs.diff"; : >"$dir/templates.diff"; : >"$dir/crds.diff"
    while IFS= read -r f; do
      case "$f" in
        */tests/* | */unittests/* | */ci/*) continue ;;
        */Chart.yaml | */values.yaml | */values.schema.json) kind=values ;;
        */crds/*) kind=crds ;;
        */templates/*) kind=templates ;;
        *README* | *UPGRAD* | *CHANGELOG* | *MIGRAT*) kind=docs ;;
        *) continue ;;
      esac
      # diff exits 1 when files differ
      (cd "$dir/src" && diff -uN "old/$f" "new/$f") >>"$dir/$kind.diff" || [ $? -eq 1 ]
    done < <(cd "$dir/src" && { (cd old && find . -type f); (cd new && find . -type f); } | sed 's|^\./||' | sort -u)
    for kind in values docs templates crds; do
      cap "$dir/$kind.diff"
    done
  fi

  if render "$base" "$chart" "$dir/rendered.old.yaml" && render "$head" "$chart" "$dir/rendered.new.yaml"; then
    # Drop the chart/app version labels, they change on every bump and drown the real changes
    sed -i -E '/^\s*(helm\.sh\/chart|app\.kubernetes\.io\/version|chart):/d' "$dir"/rendered.{old,new}.yaml
    diff -u --label old --label new "$dir/rendered.old.yaml" "$dir/rendered.new.yaml" >"$dir/rendered.diff" || [ $? -eq 1 ]
    # Compact view: which objects and images were added/removed
    for side in old new; do
      {
        yq -N 'select(.kind) | "object " + .kind + "/" + .metadata.name' "$dir/rendered.$side.yaml"
        yq -N '.. | select(tag == "!!map" and has("image") and (.image | tag) == "!!str") | "image " + .image' "$dir/rendered.$side.yaml"
      } | sort -u >"$dir/objects.$side.txt"
    done
    diff -u --label old --label new "$dir/objects.old.txt" "$dir/objects.new.txt" >"$dir/objects.diff" || [ $? -eq 1 ]
    rm "$dir"/objects.{old,new}.txt
    rm "$dir/rendered.old.yaml" "$dir/rendered.new.yaml"
    cap "$dir/rendered.diff"
  else
    { echo "render failed:"; cat "$dir"/rendered.*.err; } >"$dir/rendered.log"
    rm -f "$dir"/rendered.*.yaml* && mv "$dir/rendered.log" "$dir/rendered.diff"
    echo "  render failed, see $dir/rendered.diff"
  fi

  (cd "$dir" && wc -c ./*.diff | sed 's/^/  /')
done
