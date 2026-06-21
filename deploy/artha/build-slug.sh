#!/usr/bin/env bash
# Assembles the Scalingo prebuilt deploy slug for Artha Forms.
#
# Formbricks is a pnpm monorepo whose Next.js standalone output does not trace
# every runtime dependency (Prisma engine, pg, pino, etc.). This script takes a
# completed `pnpm build` and lays out a self-contained slug that boots with the
# bundled Node binary + run.sh under Scalingo's prebuilt-slug buildpack.
#
# Prereq: `pnpm install && pnpm build` has already run in the repo root.
# Output: $OUT_DIR (default deploy/artha/_slug) ready to be tarred as slug.tar.gz
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$HERE/../.." && pwd)"
WEB="$SRC/apps/web"
NM="$SRC/node_modules"
SLUG="${OUT_DIR:-$HERE/_slug}"

[ -d "$WEB/.next/standalone" ] || { echo " !! $WEB/.next/standalone missing — run 'pnpm build' first" >&2; exit 1; }

rm -rf "$SLUG"; mkdir -p "$SLUG"

echo "==> base: standalone root"
cp -a "$WEB/.next/standalone/." "$SLUG/"

echo "==> config + root package.json"
cp -a "$WEB/next.config.mjs" "$SLUG/next.config.mjs"
cp -a "$WEB/package.json"    "$SLUG/package.json"
[ -f "$SRC/prisma.config.mjs" ] && cp -a "$SRC/prisma.config.mjs" "$SLUG/prisma.config.mjs" || true

echo "==> static + public"
mkdir -p "$SLUG/apps/web/.next"
cp -a "$WEB/.next/static" "$SLUG/apps/web/.next/static"
cp -a "$WEB/public"       "$SLUG/apps/web/public"

echo "==> packages/database runtime (migrations)"
mkdir -p "$SLUG/packages/database"
cp -a "$SRC/packages/database/package.json"  "$SLUG/packages/database/package.json"
cp -a "$SRC/packages/database/schema.prisma" "$SLUG/packages/database/schema.prisma"
cp -a "$SRC/packages/database/dist"          "$SLUG/packages/database/dist"
cp -a "$SRC/packages/database/generated"     "$SLUG/packages/database/generated"

copy_pkg () {
  local p="$1" src
  if [ ! -e "$NM/$p" ]; then echo "  WARN missing in repo node_modules: $p"; return 0; fi
  src="$(readlink -f "$NM/$p")"
  mkdir -p "$SLUG/node_modules/$(dirname "$p")"
  rm -rf "$SLUG/node_modules/$p"
  cp -a "$src" "$SLUG/node_modules/$p"
}

echo "==> overlay runtime node_modules the standalone trace misses"
PKGS="@noble/hashes @paralleldrive/cuid2 @prisma @standard-schema c12 confbox cross-spawn \
deepmerge-ts defu destr dotenv effect empathic exsolve fast-check foreground-child get-port-please \
giget graceful-fs grammex graphmatch isexe jiti ohash path-key pathe perfect-debounce pg pg-cloudflare \
pg-connection-string pg-int8 pg-pool pg-protocol pg-types pgpass pino pino-abstract-transport \
pino-opentelemetry-transport pkg-types postgres-array postgres-bytea postgres-date postgres-interval \
prisma proper-lockfile pure-rand rc9 remeda retry shebang-command shebang-regex signal-exit split2 \
std-env uuid valibot which zeptomatch zod otlp-logger"
for p in $PKGS; do copy_pkg "$p"; done

echo "==> .bin/prisma symlink"
mkdir -p "$SLUG/node_modules/.bin"
ln -sf ../prisma/build/index.js "$SLUG/node_modules/.bin/prisma"

echo "==> bundled Node binary + run.sh"
cp -a "$HERE/run.sh" "$SLUG/run.sh"; chmod +x "$SLUG/run.sh"
if [ -n "${NODE_BIN:-}" ] && [ -x "$NODE_BIN" ]; then
  cp -a "$NODE_BIN" "$SLUG/node"
else
  cp -a "$(command -v node)" "$SLUG/node"
fi
chmod +x "$SLUG/node"

echo "==> DONE. slug at $SLUG ($(du -sh "$SLUG" | cut -f1))"
