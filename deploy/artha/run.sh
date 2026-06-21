#!/usr/bin/env bash
set -e
# Self-contained: the Node 22 binary is bundled in the slug at /app/node.
export PATH="/app:$PATH"
export NODE_ENV=production
export HOSTNAME=0.0.0.0
# DATABASE_URL must include sslaccept=accept_invalid_certs for Scalingo self-signed cert
echo "[artha-forms] node: $(node --version 2>&1) at $(command -v node)"
echo "[artha-forms] running DB migrations..."
node packages/database/dist/scripts/apply-migrations.js || echo "[artha-forms] migrations step returned non-zero (may be already applied)"
echo "[artha-forms] starting Next.js standalone server on port ${PORT:-3000}..."
exec node apps/web/server.js
