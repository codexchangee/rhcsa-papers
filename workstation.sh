#!/bin/bash
set -euo pipefail

# ====== CONFIG ======
REPO_URL="${REPO_URL:-https://github.com/codexchangee/rhcsa-papers.git}"
BRANCH="${BRANCH:-main}"
HTML_DIR="/var/www/html"

# Remote hosts (change if needed)
SERVERA_HOST="${SERVERA_HOST:-servera}"
SERVERB_HOST="${SERVERB_HOST:-serverb}"
SERVER_SSH_USER="${SERVER_SSH_USER:-root}"

# ====== Helpers ======
pkg_mgr() {
  if command -v dnf >/dev/null 2>&1; then
    echo dnf
  else
    echo yum
  fi
}

need_pkg() {
  local pkg="$1"
  if ! rpm -q "$pkg" >/dev/null 2>&1; then
    $PKG -y install "$pkg"
  fi
}

safe_systemctl_enable_now() {
  local svc="$1"
  systemctl enable --now "$svc" 2>/dev/null || systemctl enable "$svc" || true
  systemctl start "$svc" 2>/dev/null || true
}

# ====== Start ======
PKG="$(pkg_mgr)"

echo "[1/7] Installing required packages..."
need_pkg git
need_pkg httpd
need_pkg nfs-utils
need_pkg firewalld || true

echo "[2/7] (Optional) Ensure firewalld is running..."
safe_systemctl_enable_now firewalld || true

echo "[3/7] Cloning repo: $REPO_URL (branch: $BRANCH)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
if git ls-remote "$REPO_URL" &>/dev/null; then
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$WORKDIR/repo"
else
  echo "ERROR: Repo is private or unreachable: $REPO_URL"
  exit 1
fi

echo "[4/7] Deploying HTML to $HTML_DIR..."
mkdir -p "$HTML_DIR"
# Copy html/ folder contents if present; otherwise copy *.html from repo root
if [ -d "$WORKDIR/repo/html" ]; then
  find "$WORKDIR/repo/html" -type f -name "*.html" -exec cp -f {} "$HTML_DIR"/ \;
else
  echo "No html/ directory found; checking for root-level *.html files..."
  find "$WORKDIR/repo" -maxdepth 1 -type f -name "*.html" -exec cp -f {} "$HTML_DIR"/ \; || true
fi

# Ensure index.html exists
if [ ! -f "$HTML_DIR/index.html" ]; then
  cat > "$HTML_DIR/index.html" <<'EOF'
<!doctype html>
<html><head><meta charset="utf-8"><title>Site</title></head>
<body>
<h1>Site Deployed</h1>
<p>No index.html was present in the repo, so this placeholder was created.</p>
</body></html>
EOF
fi

# Optional: set ownership for Apache
if id apache &>/dev/null; then
  chown -R apache:apache "$HTML_DIR"
fi

echo "[5/7] Enabling and starting httpd..."
safe_systemctl_enable_now httpd

echo "[6/7] NFS server configuration (as in your earlier script)..."
safe_systemctl_enable_now rpcbind
safe_systemctl_enable_now nfs-server

# Temporarily set SELinux permissive if command exists (optional, mirrors your script)
if command -v setenforce >/dev/null 2>&1; then
  setenforce 0 || true
fi

# Open firewall for NFS (ignore if firewalld isn’t present)
if systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --add-service=nfs || true
  firewall-cmd --permanent --add-service=mountd || true
  firewall-cmd --permanent --add-service=rpc-bind || true
  firewall-cmd --reload || true
fi

mkdir -p /ourhome/remoteuserx
chmod 777 /ourhome/remoteuserx

# Avoid duplicate export line
grep -qE '^[[:space:]]*/ourhome/remoteuserx[[:space:]]' /etc/exports \
  || echo "/ourhome/remoteuserx *(rw,sync)" >> /etc/exports

exportfs -rv || true
systemctl restart nfs-server || true
systemctl restart rpcbind || true

echo "[7/7] Running server scripts on servera and serverb over SSH..."

# Ensure scripts exist in repo
if [ ! -f "$WORKDIR/repo/servera.sh" ] || [ ! -f "$WORKDIR/repo/serverb.sh" ]; then
  echo "ERROR: servera.sh and/or serverb.sh not found in the repo root."
  echo "Place them at: rhcsa-papers/servera.sh and rhcsa-papers/serverb.sh"
  exit 1
fi

# Make sure they are executable locally (optional)
chmod +x "$WORKDIR/repo/servera.sh" "$WORKDIR/repo/serverb.sh" || true

run_remote() {
  local host="$1"
  local script_path="$2"
  echo "==> Executing $(basename "$script_path") on $host..."
  # Copy and run atomically so host keeps a copy
  scp -q -o StrictHostKeyChecking=no "$script_path" "${SERVER_SSH_USER}@${host}:/root/remote_run.sh"
  ssh -o StrictHostKeyChecking=no "${SERVER_SSH_USER}@${host}" "chmod +x /root/remote_run.sh && /root/remote_run.sh"
}

# Execute
run_remote "$SERVERA_HOST" "$WORKDIR/repo/servera.sh"
run_remote "$SERVERB_HOST" "$WORKDIR/repo/serverb.sh"

echo "All done"
