#!/bin/bash
set -euo pipefail

# --- Hostname ---
current_hostname=$(hostname)
new_hostname="machine1.exam.com"

if [ "$current_hostname" != "$new_hostname" ]; then
    echo "Changing hostname from $current_hostname to $new_hostname"
    hostnamectl set-hostname "$new_hostname"
    sed -i "s/$current_hostname/$new_hostname/g" /etc/hosts || true
    echo "Hostname changed to $new_hostname"
else
    echo "Hostname is already $new_hostname"
fi

# --- Root password (CHANGED) ---
echo "Setting root password..."
echo "root:atenorth" | chpasswd

# --- Remove bzip2 as before ---
yum remove -y bzip2 || true

# --- HTTPD install & port change ---
echo "Installing httpd..."
yum install -y httpd

echo "Starting and enabling httpd..."
systemctl start httpd
systemctl enable httpd

CONF_FILE="/etc/httpd/conf/httpd.conf"
BACKUP_FILE="/etc/httpd/conf/httpd.conf.bak"
cp -f "$CONF_FILE" "$BACKUP_FILE"
echo "Updating Listen directives from port 80 to 82 in all httpd configuration files..."
grep -rl "Listen 80" /etc/httpd || true
grep -rl "Listen 80" /etc/httpd | xargs sed -i 's/Listen 80/Listen 82/g' || true

echo "Restarting httpd service..."
systemctl restart httpd || true

if systemctl is-active --quiet httpd; then
    echo "Port successfully changed to 82 and httpd restarted."
else
    echo "Warning: httpd failed to restart. Reverting to backup..."
    cp -f "$BACKUP_FILE" "$CONF_FILE"
    systemctl restart httpd
fi

# --- Web files (CHANGED: add text) ---
echo "Creating files in /var/www/html..."
mkdir -p /var/www/html
for f in /var/www/html/file1 /var/www/html/file2 /var/www/html/file3; do
    printf "Welcome to RHCSA Examination\n" > "$f"
done
# Keep SELinux type tweak for file1
chcon -t user_home_t /var/www/html/file1 || true

# --- Create ONLY requested users with password 'atenorth' ---
echo "Creating specified users..."
for username in remoteuser12 andrew simone; do
    id "$username" &>/dev/null || useradd "$username"
    echo "$username:atenorth" | chpasswd
done
echo "Users created."

# --- GUI check ---
echo "Checking if GUI is installed..."
if ! rpm -qa | grep -q "gnome-session"; then
    echo "GUI not found. Installing Server with GUI..."
    dnf groupinstall -y "Server with GUI"
else
    echo "GUI is already installed."
fi

# --- Network to automatic (DHCP) ---
echo "Configuring network to automatic (DHCP)..."
if command -v nmcli >/dev/null 2>&1; then
    # Adjust all common connection types to automatic
    while IFS= read -r conn; do
        [ -n "$conn" ] || continue
        nmcli connection modify "$conn" ipv4.method auto ipv4.addresses "" ipv4.gateway "" ipv4.dns "" || true
        nmcli connection modify "$conn" ipv6.method auto || true
        nmcli connection modify "$conn" connection.autoconnect yes || true
        nmcli connection up "$conn" || true
    done < <(nmcli -t -f NAME,TYPE connection show | awk -F: '/:(ethernet|wifi|bridge|bond|vlan)$/ {print $1}')
else
    echo "nmcli not found; falling back to ifcfg files..."
    for ifcfg in /etc/sysconfig/network-scripts/ifcfg-*; do
        [ -f "$ifcfg" ] || continue
        sed -i -e 's/^BOOTPROTO=.*/BOOTPROTO=dhcp/' \
               -e 's/^ONBOOT=.*/ONBOOT=yes/' \
               -e '/^IPADDR/d' -e '/^PREFIX/d' -e '/^NETMASK/d' -e '/^GATEWAY/d' -e '/^DNS.*/d' "$ifcfg"
    done
    systemctl try-restart NetworkManager.service || systemctl try-restart network.service || true
fi

echo "Script completed successfully."

history -c || true
rm -- "$0" || true
echo "Rebooting the system..."
reboot
