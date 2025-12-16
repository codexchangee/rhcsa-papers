#!/bin/bash
set -Eeuo pipefail

################ CONFIG ################
REPO_URL="https://github.com/codexchangee/rhcsa-papers.git"
BRANCH="main"

SSH_USER="root"
SERVERA="servera.lab.example.com"
SERVERB="serverb.lab.example.com"

################ FUNCTIONS ################
fatal() { echo "❌ $1"; exit 1; }

wait_for_host() {
  local h="$1"
  echo "⏳ Waiting for $h..."
  until ssh -o BatchMode=yes -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        "$SSH_USER@$h" "echo UP" &>/dev/null
  do
    sleep 5
  done
  echo "✅ $h is back online"
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

  # reboot-safe execution
  ssh -o StrictHostKeyChecking=no \
      "$SSH_USER@$host" \
      "chmod +x /root/remote_run.sh && /root/remote_run.sh || true"

  echo "➡ Script triggered on $host"
}

################ START ################
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$WORKDIR/repo" \
  || fatal "Git clone failed"

[ -f "$WORKDIR/repo/servera.sh" ] || fatal "servera.sh missing"
[ -f "$WORKDIR/repo/serverb.sh" ] || fatal "serverb.sh missing"

chmod +x "$WORKDIR/repo/servera.sh" "$WORKDIR/repo/serverb.sh"

# ---- NODE 1 ----
run_remote "$SERVERA" "$WORKDIR/repo/servera.sh"
wait_for_host "$SERVERA"

# ---- NODE 2 ----
run_remote "$SERVERB" "$WORKDIR/repo/serverb.sh"
wait_for_host "$SERVERB"

echo "🎉 BOTH NODES CONFIGURED SUCCESSFULLY"
