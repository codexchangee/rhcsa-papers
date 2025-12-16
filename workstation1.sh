#!/bin/bash
set -Eeuo pipefail

################################
# CONFIGURATION
################################
REPO_URL="https://github.com/codexchangee/rhcsa-papers.git"
BRANCH="main"

HTML_DIR="/var/www/html"

SSH_USER="root"
SERVERA_HOST="servera.lab.example.com"
SERVERB_HOST="serverb.lab.example.com"

################################
# FUNCTIONS
################################
pkg_mgr() {
  command -v dnf >/dev/null 2>&1 && echo dnf || echo yum
}

need_pkg() {
  rpm -q "$1" &>/dev/null || $PKG -y install "$1"
}

enable_now() {
  systemctl enable --now "$1" &>/dev/null || true
}

fatal() {
  echo "❌ ERROR: $1"
  exit 1
}

wait_for_host() {
  local host="$1"
  echo "⏳ Waiting for $host to come back online..."

  until ssh -o BatchMode=yes \
            -o ConnectTimeout=5 \
            -o StrictHostKeyChecking=no \
            "$SSH_USER@$host" "echo ONLINE" &>/dev/null
  do
    sleep 5
  done

  echo "✅ $host is online"
}

run_remote() {
  local host="$1"
  local script="$2"

  echo "======================================"
  echo " Running $(basename "$script") on $host"
  echo "======================================"

  ssh -o BatchMode=yes -o StrictHostKeyChecking=no \
      "$SSH_USER@$host" "echo SSH_OK" \
      || fatal "SSH failed for $host"

  scp -o StrictHostKeyChecking=no \
      "$script" "$SSH_USER@$host:/root/remote_run.sh" \
      || fatal "SCP failed for $host"

  ssh -o StrictHostKeyChecking=no \
      "$SSH_USER@$host" \
      "chmod +x /root/remote_run.sh && /root/remote_run.sh" \
      || true   # reboot will kill SSH, this is EXPECTED

  echo "➡ Script triggered on $host"
}

################################
# START
################################
PKG="$(pkg_mgr)"

echo "[1/7] Installing base packages..."
need_pkg git
need_pkg httpd
need_pkg nfs-utils
need_pkg firewalld || true

echo "[2/7] Enabling services..."
enable_now firewalld
enable_now httpd

echo "[3/7] Cloning repository..."
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$WORKDIR/repo" \
  || fatal "Git clone failed"

echo "[4/7] Deploying HTML..."
mkdir -p "$HTML_DIR"

if [ -d "$WORKDIR/repo/html" ]; then
  cp -f "$WORKDIR/repo/html/"*.html "$HTML_DIR"/
else
  cp -f "$WORKDIR/repo/"*.html "$HTML_DIR"/ || true
fi

[ -f "$HTML_DIR/index.html" ] || echo "<h1>RHCSA / RHCE Exam</h1>" > "$HTML_DIR/index.html"
chown -R apache:apache "$HTML_DIR" || true

echo "[5/7] NFS configuration..."
enable_now rpcbind
enable_now nfs-server

setenforce 0 || true

if systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --add-service=nfs || true
  firewall-cmd --permanent --add-service=mountd || true
  firewall-cmd --permanent --add-service=rpc-bind || true
  firewall-cmd --reload || true
fi

mkdir -p /ourhome/remoteuser2
chmod 777 /ourhome/remoteuser2

grep -q "/ourhome/remoteuser2" /etc/exports \
  || echo "/ourhome/remoteuser2 *(rw,sync)" >> /etc/exports

exportfs -rv

echo "[6/7] Validating node scripts..."
[ -f "$WORKDIR/repo/servera.sh" ] || fatal "servera.sh missing"
[ -f "$WORKDIR/repo/serverb.sh" ] || fatal "serverb.sh missing"

chmod +x "$WORKDIR/repo/servera.sh" "$WORKDIR/repo/serverb.sh"

echo "[7/7] Executing node scripts..."

# ---- NODE 1 ----
run_remote "$SERVERA_HOST" "$WORKDIR/repo/servera.sh"
wait_for_host "$SERVERA_HOST"

# ---- NODE 2 ----
run_remote "$SERVERB_HOST" "$WORKDIR/repo/serverb.sh"
wait_for_host "$SERVERB_HOST"

echo "ALL NODES CONFIGURED SUCCESSFULLY"
