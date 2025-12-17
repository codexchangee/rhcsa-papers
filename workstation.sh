#!/bin/bash
set -u

bash <<'WRAP'
#####################################
# CONFIG
#####################################
WORK_URL="https://raw.githubusercontent.com/codexchangee/rhcsa-papers/main/workstations.sh"
SERVERA_URL="https://raw.githubusercontent.com/codexchangee/rhcsa-papers/main/servera.sh"
SERVERB_URL="https://raw.githubusercontent.com/codexchangee/rhcsa-papers/main/serverb.sh"

HOST_A="servera"
HOST_B="serverb"

TMPDIR="$(mktemp -d /tmp/runall.XXXX)"
trap 'echo "Cleaning $TMPDIR"; rm -rf "$TMPDIR"' EXIT

#####################################
echo "[run-all] Downloading workstation script..."
#####################################
curl -fsSL "$WORK_URL" -o "$TMPDIR/work.orig" \
  || { echo "Failed to download workstation script"; exit 1; }

#####################################
echo "[run-all] Neutralizing reboot and self-delete..."
#####################################
sed -e 's/^[[:space:]]*reboot/# reboot disabled/' \
    -e 's/^[[:space:]]*shutdown -r.*/# shutdown disabled/' \
    "$TMPDIR/work.orig" > "$TMPDIR/work.safe"

chmod +x "$TMPDIR/work.safe"

#####################################
echo "[run-all] Running workstation script (safe)..."
#####################################
sudo bash "$TMPDIR/work.safe" \
  2>&1 | tee "$TMPDIR/workstation.log" \
  || echo "[run-all] workstation finished with non-zero status"

#####################################
echo "[run-all] Running servera script on $HOST_A..."
#####################################
ssh -o StrictHostKeyChecking=no root@"$HOST_A" \
  'bash -s' < <(curl -fsSL "$SERVERA_URL") \
  2>&1 | tee "$TMPDIR/servera.log" \
  || echo "[run-all] servera finished with errors"

#####################################
echo "[run-all] Running serverb script on $HOST_B..."
#####################################
ssh -o StrictHostKeyChecking=no root@"$HOST_B" \
  'bash -s' < <(curl -fsSL "$SERVERB_URL") \
  2>&1 | tee "$TMPDIR/serverb.log" \
  || echo "[run-all] serverb finished with errors"

#####################################
echo "[run-all] ALL TASKS TRIGGERED"
#####################################
WRAP

exit 0
