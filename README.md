# OpenRouter Chatbot

A minimal chat app powered by [OpenRouter](https://openrouter.ai): FastAPI backend that
streams completions from any OpenRouter model, Next.js frontend with a claude.ai-style
chat UI, deployed to a single low-cost GCP VM with CI/CD via GitHub Actions + Cloud Build.

## Architecture

```
GitHub push (main)
  -> GitHub Actions "build" job -> Cloud Build -> images pushed to Artifact Registry
  -> GitHub Actions "deploy" job -> SSH (IAP tunnel) -> VM: docker compose pull && up -d

Single VM (Debian 12, e2-small):
  Caddy (:80/:443) --/api/*--> backend (FastAPI, :8000) --> OpenRouter API
                    --/*-----> frontend (Next.js, :3000)
```

One VM, three containers (Caddy, frontend, backend). No load balancer, no Kubernetes —
Cloud Build only compiles images, it never runs the app.

```
backend/            FastAPI app (streams OpenRouter chat completions over SSE)
frontend/            Next.js 15 app router UI
deploy/Caddyfile     Reverse proxy config used on the VM
infra/               One-time GCP setup scripts (Artifact Registry, VM, WIF)
cloudbuild.yaml       Builds + pushes both images
docker-compose.yml    Production compose file (pulls prebuilt images) — lives on the VM
docker-compose.dev.yml Local dev compose file (builds from source)
.github/workflows/    ci.yml (lint/test) and deploy.yml (build + roll out)
```

## Local development

Requires Python 3.12+, Node 20+, and an [OpenRouter API key](https://openrouter.ai/keys).

```bash
cp .env.example .env          # fill in OPENROUTER_API_KEY at minimum
```

**Backend:**

```bash
cd backend
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements-dev.txt
uvicorn app.main:app --reload
```

**Frontend** (separate terminal):

```bash
cd frontend
cp .env.local.example .env.local
npm install
npm run dev
```

Open http://localhost:3000.

**Or via Docker Compose** (both services, no hot reload):

```bash
docker compose -f docker-compose.dev.yml up --build
```

### Tests & linting

```bash
cd backend && pytest && ruff check .
cd frontend && npm run lint && npm run build
```

Both run automatically in `.github/workflows/ci.yml` on every push/PR to `main`.

## Deploying to GCP

You said you already have a GCP project and OpenRouter key — here's the rest.

### 1. One-time GCP setup

Edit the variables at the top of [infra/setup.sh](infra/setup.sh) (project ID, region,
GitHub org/repo, etc.), then run it section by section (it's a reference script, not
meant to be blindly executed):

```bash
bash infra/setup.sh
```

This creates:
- An Artifact Registry Docker repo
- A `github-deployer` service account + Workload Identity Federation, so GitHub Actions
  authenticates with short-lived tokens instead of a downloaded JSON key
- The VM (`e2-small` by default — 2 vCPU / 2GB RAM; see the cost note below) with a
  dedicated runtime service account that can pull from Artifact Registry with no key file
- Firewall rules: 80/443 open to the world, port 22 restricted to Google's IAP range only
  (no public SSH)

The script prints a `WORKLOAD_IDENTITY_PROVIDER` and `GCP_SERVICE_ACCOUNT` value at the
end — you need both for step 2.

### 2. GitHub repo configuration

Under **Settings > Secrets and variables > Actions > Variables**, add:

| Variable | Example |
|---|---|
| `GCP_PROJECT_ID` | `your-gcp-project-id` |
| `GCP_REGION` | `us-central1` |
| `GCP_ZONE` | `us-central1-a` |
| `ARTIFACT_REGISTRY_REPO` | `chatbot` |
| `VM_NAME` | `chatbot-vm` |
| `WORKLOAD_IDENTITY_PROVIDER` | printed by `infra/setup.sh` |
| `GCP_SERVICE_ACCOUNT` | printed by `infra/setup.sh` |

No `GCP_SA_KEY` secret needed — that's the point of Workload Identity Federation.

### 3. Bootstrap the VM once by hand

The very first deploy has to be manual because the VM needs `docker-compose.yml`,
`deploy/Caddyfile`, and a real `.env` (with your `OPENROUTER_API_KEY`) in `/opt/chatbot`
before `docker compose up` means anything. After this, GitHub Actions' `deploy` job
re-runs `docker compose pull && up -d` on every push to `main` — it doesn't touch these
files again.

```bash
gcloud compute ssh chatbot-vm --zone us-central1-a --tunnel-through-iap

# on the VM:
sudo mkdir -p /opt/chatbot/deploy
exit

# from your machine:
gcloud compute scp docker-compose.yml chatbot-vm:/tmp/ --zone us-central1-a --tunnel-through-iap
gcloud compute scp deploy/Caddyfile chatbot-vm:/tmp/Caddyfile --zone us-central1-a --tunnel-through-iap
gcloud compute scp .env chatbot-vm:/tmp/ --zone us-central1-a --tunnel-through-iap

gcloud compute ssh chatbot-vm --zone us-central1-a --tunnel-through-iap
# on the VM:
sudo mv /tmp/docker-compose.yml /opt/chatbot/
sudo mv /tmp/Caddyfile /opt/chatbot/deploy/
sudo mv /tmp/.env /opt/chatbot/
cd /opt/chatbot
sudo docker compose pull
sudo docker compose up -d
```

Point a DNS `A` record at the VM's external IP and set `DOMAIN=your.domain.com` in the
VM's `.env` (then `docker compose up -d` again) to get automatic HTTPS from Caddy. Without
a domain it just serves plain HTTP on the IP.

### 4. Ship changes

From then on, `git push` to `main` is the whole deploy:

```
push -> ci.yml (lint/test) -> deploy.yml build job (Cloud Build) -> deploy.yml deploy job (SSH + compose)
```

Watch progress under the repo's **Actions** tab.

## Configuration reference

See [.env.example](.env.example) for every variable. The two you must set:

- `OPENROUTER_API_KEY` — from https://openrouter.ai/keys
- `OPENROUTER_MODEL` — any model slug from https://openrouter.ai/models (default:
  `anthropic/claude-haiku-4.5`)

`APP_SHARED_SECRET` is optional defense-in-depth: the backend port is never published to
the internet directly (only Caddy is, and it only proxies `/api/*` to it), so this mainly
guards against something else on the VM's Docker network reaching `/chat`. Because
`NEXT_PUBLIC_APP_SHARED_SECRET` ends up in the shipped JS bundle, it does **not** hide the
key from real visitors — don't rely on it as your only access control if that matters to you.

## Cost note

`e2-small` (2 vCPU burstable, 2GB RAM) runs a few dollars a month at sustained-use pricing
and comfortably fits Caddy + Next.js (standalone) + FastAPI. `e2-micro` (1GB RAM, free-tier
eligible in `us-west1`/`us-central1`/`us-east1`) can work too but is tight — add a swap
file if you go that route.
