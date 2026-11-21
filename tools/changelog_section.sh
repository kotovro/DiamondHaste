#!/usr/bin/env bash
# Prints the CHANGELOG.md section for a version ("0.1.0" or "Unreleased") without its heading.
# Fails if the section is missing or empty: a release must be described in CHANGELOG.md first.
set -euo pipefail
version="${1:?usage: changelog_section.sh <version|Unreleased>}"
file="$(dirname "$0")/../CHANGELOG.md"
section="$(awk -v v="$version" '
  /^## \[/ { if (found) exit; if (index($0, "## [" v "]") == 1) { found = 1; next } }
  found && /^\[[^]]+\]: / { exit }
  found { print }
' "$file")"
if [[ -z "${section//[[:space:]]/}" ]]; then
  echo "CHANGELOG.md has no section for [$version]" >&2
  exit 1
fi
printf '%s\n' "$section"
