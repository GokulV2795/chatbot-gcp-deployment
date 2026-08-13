#!/bin/bash
# One-time GCP setup: Artifact Registry, a minimal VM, and Workload Identity
# Federation so GitHub Actions can deploy without a long-lived key file.
#
# This is a REFERENCE script meant to be read and run command-by-command (or
# as a whole) by a human with the right permissions — it is not invoked
# automatically by any CI job. Fill in the variables below first.
set -euo pipefail

# --- Fill these in ---
PROJECT_ID="terraform-lab-504603"
REGION="us-central1"
ZONE="us-central1-a"
REPO_NAME="chatbot"
VM_NAME="chatbot-vm"
VM_MACHINE_TYPE="e2-small"        # 2 vCPU (burstable) / 2GB RAM. e2-micro (1GB) is cheaper
                                   # / free-tier eligible but tight for Next.js + FastAPI + Caddy.
GITHUB_ORG="GokulV2795"
GITHUB_REPO="chatbot-gcp-deployment"
GH_DEPLOY_SA="github-deployer"    # service account GitHub Actions impersonates
WIF_POOL="github-pool"            # reused an existing pool in this project if one's already there
WIF_PROVIDER="chatbot-provider"   # distinct provider so we don't touch other repos' trust config
# ---------------------

gcloud config set project "$PROJECT_ID"

# 1. Enable required APIs
gcloud services enable \
  compute.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  iamcredentials.googleapis.com \
  iap.googleapis.com

# 2. Artifact Registry repo for the two app images
gcloud artifacts repositories create "$REPO_NAME" \
  --repository-format=docker \
  --location="$REGION" \
  --description="OpenRouter chatbot images"

# 3. Service account GitHub Actions will impersonate (no JSON key needed)
gcloud iam service-accounts create "$GH_DEPLOY_SA" \
  --display-name="GitHub Actions deployer"

GH_SA_EMAIL="${GH_DEPLOY_SA}@${PROJECT_ID}.iam.gserviceaccount.com"

# Minimum roles: submit Cloud Builds, read/write the AR repo, and SSH to the
# VM over IAP (no public SSH port needed). storage.admin is broader than it
# looks: some projects' org policy blocks the Cloud Build default source
# bucket ([PROJECT]_cloudbuild) without it, which otherwise fails as
# "forbidden from accessing the bucket" on `gcloud builds submit`.
for ROLE in \
  roles/cloudbuild.builds.editor \
  roles/artifactregistry.writer \
  roles/iap.tunnelResourceAccessor \
  roles/compute.osLogin \
  roles/iam.serviceAccountUser \
  roles/storage.admin; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${GH_SA_EMAIL}" \
    --role="$ROLE"
done

# 4. Workload Identity Federation: let GitHub Actions impersonate GH_SA_EMAIL
#    using a short-lived OIDC token, scoped to this exact repo. Reuses an
#    existing pool of this name if the project already has one (e.g. from
#    other CI/CD in this project) — only fails loudly on unexpected errors.
gcloud iam workload-identity-pools create "$WIF_POOL" \
  --location=global \
  --display-name="GitHub Actions pool" \
  || gcloud iam workload-identity-pools describe "$WIF_POOL" --location=global >/dev/null

gcloud iam workload-identity-pools providers create-oidc "$WIF_PROVIDER" \
  --location=global \
  --workload-identity-pool="$WIF_POOL" \
  --display-name="GitHub OIDC provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository=='${GITHUB_ORG}/${GITHUB_REPO}'" \
  --issuer-uri="https://token.actions.githubusercontent.com"

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
WIF_POOL_ID="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL}"

gcloud iam service-accounts add-iam-policy-binding "$GH_SA_EMAIL" \
  --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/${WIF_POOL_ID}/attribute.repository/${GITHUB_ORG}/${GITHUB_REPO}"

echo "WORKLOAD_IDENTITY_PROVIDER = ${WIF_POOL_ID}/providers/${WIF_PROVIDER}"
echo "GCP_SERVICE_ACCOUNT        = ${GH_SA_EMAIL}"
echo "-> add these as repo variables (Settings > Secrets and variables > Actions > Variables)"

# 5. Firewall: HTTP/HTTPS open to the world, SSH only through IAP's range
gcloud compute firewall-rules create allow-http-https \
  --allow=tcp:80,tcp:443 \
  --target-tags=chatbot-vm \
  --direction=INGRESS \
  --source-ranges=0.0.0.0/0

gcloud compute firewall-rules create allow-iap-ssh \
  --allow=tcp:22 \
  --target-tags=chatbot-vm \
  --direction=INGRESS \
  --source-ranges=35.235.240.0/20

# 6. The VM itself. A dedicated (least-privilege) service account is attached
#    so the VM's own Docker daemon can pull from Artifact Registry without keys.
gcloud iam service-accounts create chatbot-vm-runtime \
  --display-name="Chatbot VM runtime"
VM_SA_EMAIL="chatbot-vm-runtime@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${VM_SA_EMAIL}" \
  --role=roles/artifactregistry.reader

gcloud compute instances create "$VM_NAME" \
  --zone="$ZONE" \
  --machine-type="$VM_MACHINE_TYPE" \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --tags=chatbot-vm \
  --service-account="$VM_SA_EMAIL" \
  --scopes=cloud-platform \
  --metadata-from-file=startup-script=infra/vm-startup.sh \
  --metadata=artifact-registry-region="$REGION" \
  --boot-disk-size=20GB
  # Gets an ephemeral external IP by default — Caddy on the VM terminates HTTP(S)
  # directly, no load balancer needed. Reserve a static IP instead if you want a
  # stable address for DNS (see README).

echo "VM created. Next: SSH in via 'gcloud compute ssh ${VM_NAME} --zone ${ZONE} --tunnel-through-iap',"
echo "copy docker-compose.yml, deploy/Caddyfile and a filled-in .env into /opt/chatbot, then run"
echo "'docker compose up -d' once by hand. After that, the deploy.yml workflow takes over."
