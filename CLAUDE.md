# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

**Backend** (`backend/`, FastAPI + Python 3.12):
```bash
pip install -r requirements-dev.txt   # includes pytest, ruff on top of runtime deps
uvicorn app.main:app --reload         # run locally, needs .env with OPENROUTER_API_KEY
pytest                                # all tests
pytest tests/test_health.py::test_health   # single test
ruff check .                          # lint
```

**Frontend** (`frontend/`, Next.js 15 App Router + TypeScript):
```bash
npm install
npm run dev      # local dev server, needs .env.local (see .env.local.example)
npm run build    # production build (also type-checks)
npm run lint
```

**Both together locally:**
```bash
docker compose -f docker-compose.dev.yml up --build
```

There is no top-level test/build command — backend and frontend are tested independently
(see `.github/workflows/ci.yml`, which runs both jobs on every push/PR to `main`).

## Architecture

Two independent apps composed at deploy time, not a monorepo build:

- `backend/app/` — FastAPI. `services/openrouter.py` streams from OpenRouter's
  OpenAI-compatible `/chat/completions` endpoint and re-yields plain text token deltas.
  `api/routes/chat.py` wraps that generator in an SSE response where each event's `data:`
  field is JSON-encoded (`json.dumps(token)`) so multi-line tokens (code blocks) survive
  SSE framing intact — the frontend must `JSON.parse` each `data:` line, not read it raw.
  Auth is a single optional dependency, `core/security.verify_shared_secret`, gated by the
  `APP_SHARED_SECRET` env var; it's a no-op when that var is empty.

- `frontend/lib/api.ts` — hand-rolled SSE client (`streamChat`) that parses that same
  framing: splits on `\n\n`, reads `event:`/`data:` lines, treats `event: error` as a
  thrown error and `event: done` as stream end. `components/ChatWindow.tsx` owns message
  state and appends streamed tokens to the last assistant message as they arrive.

- **Request path differs between environments.** Locally, `NEXT_PUBLIC_API_BASE_URL`
  points straight at the backend (`http://localhost:8000`). In production it's `/api`,
  and `deploy/Caddyfile` strips the `/api` prefix before proxying to the `backend`
  container — so a route added in `backend/app/api/routes/` is reachable at `/foo`
  locally but `/api/foo` through Caddy in prod. Don't hardcode either assumption.

- `NEXT_PUBLIC_*` frontend env vars are baked in at Docker **build** time (see
  `frontend/Dockerfile` ARGs and `cloudbuild.yaml`'s `_API_BASE_URL` substitution), not
  read at container start. Changing one requires a rebuild, not just a container restart.
  Because of this, anything under `NEXT_PUBLIC_*` (including
  `NEXT_PUBLIC_APP_SHARED_SECRET`) ends up readable in the shipped JS bundle — it is not a
  real secret, only a filter against non-browser traffic hitting the backend directly.

## Deployment shape

Single GCP VM running three containers via `docker-compose.yml` (production compose file,
lives on the VM, pulls prebuilt images — never builds on the VM):

```
Caddy (:80/:443) --/api/*--> backend:8000
                  --/*-----> frontend:3000
```

CI/CD: push to `main` → GitHub Actions `ci.yml` (lint/test) and `deploy.yml`. `deploy.yml`
has two jobs: `build` submits `cloudbuild.yaml` to Cloud Build (builds+pushes both images
to Artifact Registry, tagged `$SHORT_SHA` and `latest`), then `deploy` SSHes into the VM
over an IAP tunnel (no public SSH port) and runs `docker compose pull && up -d` with
`IMAGE_TAG` set to the short SHA. Auth to GCP is Workload Identity Federation (see
`infra/setup.sh`) — no downloaded service-account key.

`infra/setup.sh` and `infra/vm-startup.sh` are reference scripts, not automated — they're
meant to be read and run by a human once, not invoked by CI. The very first rollout to a
fresh VM is manual (copying `docker-compose.yml`, `deploy/Caddyfile`, `.env` into
`/opt/chatbot`); `deploy.yml` only ever re-runs `docker compose pull/up` after that and
never touches those three files again. Full walkthrough is in `README.md`.
