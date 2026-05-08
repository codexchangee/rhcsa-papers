#!/bin/bash

current_hostname=$(hostname)
new_hostname="primary.net2.example.com"

if [ "$current_hostname" != "$new_hostname" ]; then
    hostnamectl set-hostname "$new_hostname"
    sed -i "s/$current_hostname/$new_hostname/g" /etc/hosts
fi

echo "root:password" | chpasswd

echo "Creating specified users..."
for username in bammbamm; do
    id "$username" &>/dev/null || useradd "$username"
    echo "$username:atenorth" | chpasswd

if ! rpm -qa | grep -q "gnome-session"; then
    dnf group install "Server with GUI" -y --nobest
fi

echo -e "o\nn\np\n1\n\n+200M\nw" | fdisk /dev/sdb

partprobe

pvcreate /dev/sdb1
vgcreate myvg /dev/sdb1
lvcreate -L 100M -n home myvg

mkfs.ext4 /dev/myvg/home

mkdir -p /home
mount /dev/myvg/home /home

echo "/dev/myvg/home /home ext4 defaults 0 0" >> /etc/fstab

dnf reinstall kernel-core -y
dracut -f --regenerate-all
grub2-mkconfig -o /boot/grub2/grub.cfg

history -c
rm -- "$0"
reboot
