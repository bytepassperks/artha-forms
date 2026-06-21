# Artha Forms — white-label + gated auto-update kit

Artha Forms is a thin white-label fork of [Formbricks](https://github.com/formbricks/formbricks)
that tracks upstream and ships under the Artha brand. This directory is the
**set-and-forget auto-update kit**, identical in spirit to the kits used by Artha
Accounting and Artha Automations.

## Files

| File | Purpose |
|---|---|
| `update.sh` | Weekly orchestrator: fetch upstream → trial-merge → verify-rebrand → merge → build → assemble slug → deploy → verify live → pin SHA. **Aborts before deploy on any conflict / drift / build failure — production is never touched on failure.** |
| `verify-rebrand.sh` | Asserts the Artha Forms brand is present (title, email from-name, en-US strings) and that **no user-visible "Formbricks" string** leaked back into any locale catalogue. Exit 1 stops the pipeline. |
| `build-slug.sh` | Assembles the Scalingo prebuilt deploy slug from a completed `pnpm build` (Next.js standalone + the runtime deps the trace misses + bundled Node + `run.sh`). |
| `run.sh` | Slug entrypoint: runs Prisma migrations, then boots the Next.js standalone server. |
| `VERSION` | The upstream Formbricks SHA currently deployed. Pinned automatically after each successful update. |

## Deploy model

Artha Forms deploys to Scalingo via the **prebuilt-slug buildpack**
(`bytepassperks/scalingo-prebuilt-buildpack#deploy`). The deploy archive contains
just `slug.tar.gz` + `Procfile`; the buildpack decompresses the slug at compile
time. This keeps the heavy Next.js monorepo build off Scalingo's builder (which
is Alpine/glibc-sensitive and memory-capped) and makes deploys fast and
deterministic.

## Brand layer (what `verify-rebrand.sh` guards)

- `apps/web/app/layout.tsx` — HTML `<title>` / metadata → **Artha Forms**
- `apps/web/modules/email/index.tsx` — transactional email from-name → **Artha Forms**
- `apps/web/locales/*.json` — all user-visible UI strings rebranded; **zero** "Formbricks" tokens
- `apps/web/public/favicon*` + logo assets → Artha mark

## Running an update manually

```bash
SCALINGO_API_TOKEN=… deploy/artha/update.sh
```

Requires `scalingo` CLI + `pnpm` on PATH and push rights to `bytepassperks/artha-forms`.
