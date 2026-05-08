#!/bin/bash
set -euo pipefail

########################################
# Hostname Configuration
########################################

current_hostname=$(hostname)
new_hostname="machine2.exam.com"

if [ "$current_hostname" != "$new_hostname" ]; then
    echo "Changing hostname to $new_hostname"
    hostnamectl set-hostname "$new_hostname"

    sed -i "s/$current_hostname/$new_hostname/g" /etc/hosts || true
fi

########################################
# Root Password
########################################

echo "Setting root password..."
echo "root:password" | chpasswd

########################################
# Install GUI if Missing
########################################

echo "Checking GUI installation..."

if ! rpm -qa | grep -q "gnome-session"; then
    echo "Installing Server with GUI..."
    dnf groupinstall -y "Server with GUI" || true
else
    echo "GUI already installed."
fi

########################################
# Disk Partitioning
########################################

echo "Creating partition on /dev/sdb..."

if [ ! -b /dev/sdb1 ]; then

cat <<EOF | fdisk /dev/sdb
o
n
p
1

+200M
w
EOF

fi

partprobe || true
sleep 2

########################################
# LVM Configuration
########################################

echo "Creating Physical Volume..."

if ! pvs | grep -q "/dev/sdb1"; then
    pvcreate /dev/sdb1
fi

echo "Creating Volume Group..."

if ! vgs | grep -q "myvg"; then
    vgcreate myvg /dev/sdb1
fi

echo "Creating Logical Volume..."

if ! lvs | grep -q "home"; then
    lvcreate -L 100M -n home myvg
fi

########################################
# Filesystem Creation
########################################

echo "Creating ext4 filesystem..."

if ! blkid /dev/myvg/home | grep -q ext4; then
    mkfs.ext4 -F /dev/myvg/home
fi

########################################
# Mount Configuration
########################################

mkdir -p /home

if ! mount | grep -q "/home"; then
    mount /dev/myvg/home /home
fi

grep -q "/dev/myvg/home" /etc/fstab || \
echo "/dev/myvg/home /home ext4 defaults 0 0" >> /etc/fstab

########################################
# Kernel Reinstallation
########################################

echo "Reinstalling kernel-core..."

dnf reinstall -y kernel-core || true

echo "Regenerating initramfs..."

dracut -f --regenerate-all || true

echo "Updating grub configuration..."

grub2-mkconfig -o /boot/grub2/grub.cfg || true

########################################
# Cleanup
########################################

history -c || true

echo "====================================="
echo "serverb configuration completed"
echo "====================================="

# Optional reboot
# reboot
