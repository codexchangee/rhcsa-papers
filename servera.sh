#!/bin/bash

current_hostname=$(hostname)
new_hostname="machine1.exam.com"

if [ "$current_hostname" != "$new_hostname" ]; then
    echo "Changing hostname from $current_hostname to $new_hostname"
    hostnamectl set-hostname "$new_hostname"
    sed -i "s/$current_hostname/$new_hostname/g" /etc/hosts
    echo "Hostname changed to $new_hostname"
else
    echo "Hostname is already $new_hostname"
fi

# Root password
echo "Setting root password..."
echo "root:atenorth" | chpasswd

# Remove bzip2 if present
yum remove -y bzip2 || true

echo "Installing httpd..."
yum install -y httpd

echo "Starting and enabling httpd..."
systemctl start httpd
systemctl enable httpd


CONF_FILE="/etc/httpd/conf/httpd.conf"
BACKUP_FILE="/etc/httpd/conf/httpd.conf.bak"
cp "$CONF_FILE" "$BACKUP_FILE"
echo "Updating Listen directives from port 80 to 82 in all httpd configuration files..."
grep -rl "Listen 80" /etc/httpd | xargs sed -i 's/Listen 80/Listen 82/g'

echo "Restarting httpd service..."
systemctl restart httpd

if systemctl is-active --quiet httpd; then
    echo "Port successfully changed to 82 and httpd restarted."
else
    echo "Warning: httpd failed to restart. Reverting to backup..."
    cp "$BACKUP_FILE" "$CONF_FILE"
    systemctl restart httpd
fi


echo "Creating files in /var/www/html..."
mkdir -p /var/www/html
printf "Welcome to RHCSA Examination\n" > /var/www/html/file1
printf "Welcome to RHCSA Examination\n" > /var/www/html/file2
printf "Welcome to RHCSA Examination\n" > /var/www/html/file3
# set file1 to a non-httpd SELinux type (harmless if permissive)
chcon -t user_home_t /var/www/html/file1 || true

echo "Creating specified users..."
for username in remoteuser2 andrew simone; do
    id "$username" &>/dev/null || useradd "$username"
    echo "$username:atenorth" | chpasswd
done
echo "Users created."

echo "Checking if GUI is installed..."
if ! rpm -qa | grep -q "gnome-session"; then
    echo "GUI not found. Installing Server with GUI..."
    dnf groupinstall -y "Server with GUI" || yum groupinstall -y "Server with GUI" || true
else
    echo "GUI is already installed."
fi

echo "Configuring network to automatic (DHCP)..."
if command -v nmcli >/dev/null 2>&1; then
    nmcli -t -f NAME,TYPE connection show \
      | awk -F: '/:(ethernet|wifi|bridge|bond|vlan)$/{print $1}' \
      | while read -r conn; do
            [ -n "$conn" ] || continue
            nmcli connection modify "$conn" ipv4.method auto ipv4.addresses "" ipv4.gateway "" ipv4.dns "" || true
            nmcli connection modify "$conn" ipv6.method auto || true
            nmcli connection modify "$conn" connection.autoconnect yes || true
            nmcli connection up "$conn" || true
        done
else
    for ifcfg in /etc/sysconfig/network-scripts/ifcfg-*; do
        [ -f "$ifcfg" ] || continue
        sed -i -e 's/^BOOTPROTO=.*/BOOTPROTO=dhcp/' \
               -e 's/^ONBOOT=.*/ONBOOT=yes/' \
               -e '/^IPADDR/d;/^PREFIX/d;/^NETMASK/d;/^GATEWAY/d;/^DNS.*/d' "$ifcfg"
    done
    systemctl try-restart NetworkManager.service || systemctl try-restart network.service || true
fi

echo "Script completed successfully."
history -c || true
rm -- "$0" || true
echo "Rebooting the system..."
reboot
