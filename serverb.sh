#!/bin/bash

current_hostname=$(hostname)
new_hostname="machine2.exam.com"

if [ "$current_hostname" != "$new_hostname" ]; then
    hostnamectl set-hostname "$new_hostname"
    sed -i "s/$current_hostname/$new_hostname/g" /etc/hosts
fi

echo "root:password" | chpasswd

if ! rpm -qa | grep -q "gnome-session"; then
    dnf groupinstall "Server with GUI" -y
fi

echo -e "o\nn\np\n1\n\n+200M\nw" | fdisk /dev/vdb

partprobe

pvcreate /dev/vdb1
vgcreate myvg /dev/vdb1
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
