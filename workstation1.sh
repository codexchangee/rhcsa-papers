#!/bin/bash
set -Eeuo pipefail

REPO_URL="https://github.com/codexchangee/rhcsa-papers.git"
BRANCH="main"

SSH_USER="root"
SERVERA="servera.lab.example.com"
SERVERB="serverb.lab.example.com"

fatal() {
  echo "❌ ERROR: $1"
  exit 1
}

run_remote() {
  local host="$1"
  local script="$2"

  echo "=============================="
  echo " Running $(basename "$script") on $host"
  echo "=============================="

  scp -o StrictHostKeyChecking=no \
      "$script" "$SSH_USER@$host:/root/remote_run.sh" \
      || fatal "SCP failed for $host"

  ssh -o StrictHostKeyChecking=no \
      "$SSH_USER@$host" \
      "chmod +x /root/remote_run.sh && /root/remote_run.sh" \
      || fatal "Execution failed on $host"

  echo "✅ $host completed"
}

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$WORKDIR/repo" \
  || fatal "Git clone failed"

chmod +x "$WORKDIR/repo/servera.sh" "$WORKDIR/repo/serverb.sh"

run_remote "$SERVERA" "$WORKDIR/repo/servera.sh"
run_remote "$SERVERB" "$WORKDIR/repo/serverb.sh"

echo "🎉 BOTH NODES CONFIGURED SUCCESSFULLY"
