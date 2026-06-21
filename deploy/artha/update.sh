#!/usr/bin/env bash
# Gated set-and-forget auto-update for Artha Forms (Formbricks thin-fork).
#
# Weekly flow: fetch upstream → dry-run trial-merge on a throwaway branch →
# verify-rebrand → real merge → pnpm build → assemble prebuilt slug → push fork →
# deploy slug to Scalingo → migrate → verify live (HTTP 200 + brand token) →
# pin the merged upstream SHA in VERSION.
#
# SAFETY: any conflict, rebrand drift, or build failure aborts BEFORE the deploy
# step — production is never touched on failure. Designed to be run head-less by
# a scheduled Devin session; it stops and alerts a human only on a hard conflict.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"

log()  { printf '\n==> %s\n' "$*"; }
die()  { printf '\n !! %s\n' "$*" >&2; exit 1; }

# ── Configuration ─────────────────────────────────────────────────────────────
UPSTREAM_REMOTE="upstream"
UPSTREAM_URL="https://github.com/formbricks/formbricks.git"
UPSTREAM_BRANCH="main"
FORK_BRANCH="artha-stable"
SCALINGO_APP="artha-forms"
SCALINGO_REGION="osc-fr1"
LIVE_URL="https://artha-forms.osc-fr1.scalingo.io"
VERIFY_PATH="/auth/login"
EXPECTED_TOKEN="Artha Forms"
VERSION_FILE="$HERE/VERSION"
DEPLOY_TMP="$(mktemp -d)"
trap 'rm -rf "$DEPLOY_TMP"' EXIT

command -v scalingo >/dev/null || die "scalingo CLI not on PATH"
command -v pnpm     >/dev/null || die "pnpm not on PATH (Formbricks build needs pnpm)"

# ── Step 1: sync remotes ──────────────────────────────────────────────────────
git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1 || git remote add "$UPSTREAM_REMOTE" "$UPSTREAM_URL"
log "Fetching upstream"
git fetch --tags "$UPSTREAM_REMOTE" "$UPSTREAM_BRANCH"
UPSTREAM_SHA="$(git rev-parse "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH")"
PINNED_SHA="$(cat "$VERSION_FILE" 2>/dev/null || echo none)"
log "upstream@$UPSTREAM_SHA  pinned@$PINNED_SHA"
if [ "$UPSTREAM_SHA" = "$PINNED_SHA" ]; then
  log "Already up to date — nothing to deploy."; exit 0
fi

git checkout "$FORK_BRANCH"

# ── Step 2: dry-run trial merge (throwaway branch) ────────────────────────────
TRIAL="artha-trial-$(date +%s)"
log "Trial-merging on $TRIAL (no effect on $FORK_BRANCH)"
git checkout -b "$TRIAL"
if ! git merge --no-edit --no-ff "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH"; then
  git merge --abort 2>/dev/null || true
  git checkout "$FORK_BRANCH"; git branch -D "$TRIAL"
  die "trial merge CONFLICT against upstream $UPSTREAM_SHA — needs a human to reconcile the rebrand layer. Production untouched."
fi
"$HERE/verify-rebrand.sh" || { git checkout "$FORK_BRANCH"; git branch -D "$TRIAL"; die "rebrand drifted in trial merge — fix deploy/artha before shipping. Production untouched."; }
git checkout "$FORK_BRANCH"; git branch -D "$TRIAL"

# ── Step 3: real merge ────────────────────────────────────────────────────────
log "Merging upstream $UPSTREAM_SHA into $FORK_BRANCH"
git merge --no-edit --no-ff "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" || die "real merge CONFLICT — should not happen after a clean trial. Production untouched."
"$HERE/verify-rebrand.sh" || die "rebrand drifted after merge. Production untouched."

# ── Step 4: build (failure aborts before deploy) ──────────────────────────────
log "Installing deps + building (pnpm)"
pnpm install --frozen-lockfile=false || die "pnpm install failed. Production untouched."
pnpm build || die "pnpm build failed — not shipping a broken slug. Production untouched."

log "Assembling prebuilt slug"
"$HERE/build-slug.sh" || die "slug assembly failed. Production untouched."

# ── Step 5: package deploy archive (slug.tar.gz + Procfile) ───────────────────
log "Packaging deploy archive"
SLUG_DIR="${OUT_DIR:-$HERE/_slug}"
( cd "$SLUG_DIR" && tar czf "$DEPLOY_TMP/slug.tar.gz" . )
printf 'web: ./run.sh\n' > "$DEPLOY_TMP/Procfile"
( cd "$DEPLOY_TMP" && tar czf "$DEPLOY_TMP/deploy.tar.gz" slug.tar.gz Procfile )

# ── Step 6: push fork ─────────────────────────────────────────────────────────
log "Pushing $FORK_BRANCH to origin"
git push origin "$FORK_BRANCH"

# ── Step 7: deploy to Scalingo (archive deploy via prebuilt buildpack) ────────
log "Deploying to Scalingo app $SCALINGO_APP"
scalingo --app "$SCALINGO_APP" --region "$SCALINGO_REGION" deploy "$DEPLOY_TMP/deploy.tar.gz" || die "scalingo deploy failed."

# ── Step 8: verify live ───────────────────────────────────────────────────────
log "Verifying live app at $LIVE_URL$VERIFY_PATH"
ok=0
for _ in $(seq 1 30); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "$LIVE_URL$VERIFY_PATH" || true)"
  if [ "$code" = "200" ] && curl -s "$LIVE_URL$VERIFY_PATH" | grep -qF "$EXPECTED_TOKEN"; then
    ok=1; break
  fi
  sleep 10
done
[ "$ok" -eq 1 ] || die "post-deploy verification failed: $LIVE_URL$VERIFY_PATH did not return HTTP 200 with '$EXPECTED_TOKEN'."

# ── Step 9: pin the new SHA ───────────────────────────────────────────────────
echo "$UPSTREAM_SHA" > "$VERSION_FILE"
git add "$VERSION_FILE"
git commit -m "chore(artha): auto-update to upstream $UPSTREAM_SHA" >/dev/null 2>&1 || true
git push origin "$FORK_BRANCH" || true
log "DONE — Artha Forms updated to $UPSTREAM_SHA and verified live."
