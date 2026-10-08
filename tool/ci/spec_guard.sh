#!/usr/bin/env bash
# PR-8: a pull request that changes how vault_core writes bytes (crypto,
# format, keys, records, the HLC string) must update docs/format/SPEC.md in
# the same PR. The vectors are enforced separately: vectors_test fails if the
# generator's output moves.
#
# A refactor that provably keeps every byte can say so with the
# `no-format-change` label (NO_FORMAT_CHANGE=true).
#
# Usage: tool/ci/spec_guard.sh <base-sha>   (compares <base-sha>...HEAD)
set -euo pipefail

base="${1:?base sha}"
changed="$(git diff --name-only "$base"...HEAD)"

format_code="$(printf '%s\n' "$changed" | grep -E \
  '^packages/vault_core/lib/src/(crypto|format|keys|model)/|^packages/vault_core/lib/src/sync/hlc\.dart$' \
  || true)"

if [[ -z "$format_code" ]]; then
  echo "No format code changed."
  exit 0
fi

if printf '%s\n' "$changed" | grep -qx 'docs/format/SPEC.md'; then
  echo "Format code changed, and so did docs/format/SPEC.md."
  exit 0
fi

if [[ "${NO_FORMAT_CHANGE:-false}" == "true" ]]; then
  echo "Format code changed without a SPEC change; labelled no-format-change."
  exit 0
fi

echo "::error::These files define the vault format, but docs/format/SPEC.md didn't change:"
printf '  %s\n' $format_code
echo "Update SPEC.md (and the vectors) in this PR, or label it no-format-change if every byte stays the same."
exit 1
