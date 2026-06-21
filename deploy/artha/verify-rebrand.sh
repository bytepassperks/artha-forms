#!/usr/bin/env bash
# Asserts the Artha Forms white-label layer is intact in the working tree.
#
# Run after merging upstream Formbricks commits: if upstream overwrote any
# branded file (or reintroduced a user-visible "Formbricks" string), an
# assertion fails LOUDLY here so the pipeline stops instead of shipping a
# half-branded build. Exit 0 = rebrand intact.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"

fail=0
need() {
  # need <file> <grep-pattern> <human description>
  local file="$1" pat="$2" desc="$3"
  if [ ! -f "$file" ]; then
    printf ' !! MISSING FILE: %s (%s)\n' "$file" "$desc" >&2; fail=1; return
  fi
  if ! grep -qF "$pat" "$file"; then
    printf ' !! REBRAND DRIFT: %s no longer contains "%s" (%s)\n' "$file" "$pat" "$desc" >&2; fail=1
  fi
}
forbid_count() {
  # forbid_count <file> <forbidden-pattern> <human description>
  # fails if the forbidden token appears in a user-visible strings file
  local file="$1" pat="$2" desc="$3"
  [ -f "$file" ] || return 0
  local n; n="$(grep -cF "$pat" "$file" || true)"
  if [ "$n" -ne 0 ]; then
    printf ' !! LEAK: %s contains %s user-visible "%s" string(s) (%s)\n' "$file" "$n" "$pat" "$desc" >&2; fail=1
  fi
}

# ── Brand identity must be present ────────────────────────────────────────────
need "apps/web/app/layout.tsx"            'Artha Forms'  "HTML <title> / metadata"
need "apps/web/modules/email/index.tsx"   'Artha Forms'  "transactional email from-name"
need "apps/web/locales/en-US.json"        'Artha Forms'  "English UI strings"

# ── No upstream brand may leak into the user-visible string catalogues ────────
for loc in apps/web/locales/*.json; do
  forbid_count "$loc" 'Formbricks' "locale $(basename "$loc")"
done

# ── Deploy plumbing the slug build depends on ─────────────────────────────────
need "deploy/artha/build-slug.sh" 'next.config' "slug assembler"

if [ "$fail" -ne 0 ]; then
  printf '\n !! Rebrand verification FAILED — re-apply the Artha Forms rebrand layer before shipping. Production untouched.\n' >&2
  exit 1
fi
printf '==> rebrand verification OK — Artha Forms branding intact, no user-visible Formbricks leaks.\n'
