#!/bin/bash
# Compute Engine startup script (runs on every boot). Installs Docker, prepares
# the /opt/chatbot deploy directory, and configures Artifact Registry auth so
# `docker compose pull` works using the VM's attached service account
# (no key files on disk).
#
# This does NOT start the app on first boot — it only installs prerequisites.
# The first deploy (copying docker-compose.yml / deploy/Caddyfile / .env and
# running `docker compose up -d`) is a one-time manual step; after that,
# GitHub Actions' `deploy` job takes over via SSH. See README.md.
set -euo pipefail

if ! command -v docker &>/dev/null; then
  apt-get update
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

REGION="$(curl -s -H 'Metadata-Flavor: Google' \
  'http://metadata.google.internal/computeMetadata/v1/instance/attributes/artifact-registry-region' || echo us-central1)"
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

mkdir -p /opt/chatbot
chown -R "$(logname 2>/dev/null || echo root)" /opt/chatbot
