#!/usr/bin/env bash
# Check an opencode session against the manifest from upstream-source.sh, and write the
# "Sources checked" section of the PR comment from the session's actual tool calls, so
# it can't list anything the model didn't do.
#
# A part counts as read only when a single, non-truncated tool output holds both its
# start and end tokens. Unread parts are printed to stdout and the exit code is 1.
#
# Usage: review-check.sh <session.json> <manifest> <sources.md>
set -euo pipefail

session=$1
manifest=$2
sources=$3

missing=0
while IFS=$'\t' read -r part start end; do
  if ! jq -e --arg start "$start" --arg end "$end" '
    any(.messages[].parts[]; .type == "tool" and .state.metadata.truncated != true
      and (.state | tostring | contains($start) and contains($end)))' "$session" >/dev/null; then
    echo "$part"
    missing=1
  fi
done <"$manifest.parts"

{
  echo "### Sources checked"
  while IFS=$'\t' read -r chart repo old new commits files kept total; do
    line="- github: [$repo, between tags $old and $new](https://github.com/$repo/compare/$old...$new) ($chart: $commits commits, $files files)"
    if [ "$kept" -lt "$total" ]; then
      line="$line, ⚠️ only the first $((kept / 1000)) KB of $((total / 1000)) KB were reviewed"
    fi
    echo "$line"
  done <"$manifest"
  while IFS=$'\t' read -r chart name old new reason; do
    echo "- ⚠️ source not available: $name $old -> $new ($chart): $reason"
  done <"$manifest.missing"
  # Repos the model cloned on its own, e.g. for a GitHub Actions bump
  jq -r '.messages[].parts[] | select(.type == "tool" and .tool == "bash" and .state.status == "completed")
    | .state.input.command // "" | capture("git clone .*https://github\\.com/(?<repo>[^ ]+)").repo? // empty
    | sub("\\.git$"; "") | "- github: cloned " + .' "$session" | sort -u |
    grep -vFf <(cut -f2 "$manifest" | sed 's/^/- github: cloned /') || true
  jq -r '.messages[].parts[] | select(.type == "tool" and .state.status == "completed")
    | if .tool == "exa_web_search_exa" then "- web search: " + .state.input.query
      elif .tool == "exa_web_fetch_exa" then .state.input.urls[]? | "- web page: " + .
      else empty end' "$session"
} >"$sources"

exit "$missing"
