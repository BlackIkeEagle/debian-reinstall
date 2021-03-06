#!/usr/bin/env bash

set -e

echo -n "enter the admin user name: "
read -r admin_user

echo -n "enter the admin user's pass: "
read -r admin_pass

echo -n "enter the block device's name (sda,nvme1): "
read -r blockdev

echo -n "nvme disk or regular (nvme|regular): "
read -r nvmedisk

echo -n "check blocks (yes|no (default)): "
read -r checkblocks

if [[ "$admin_user" == "" ]]; then
    echo "no admin user given"
    exit 1
fi
if [[ "$admin_pass" == "" ]]; then
    echo "no admin pass given"
    exit 1
fi
if [[ "$blockdev" == "" ]]; then
    echo "no blockdev given"
    exit 1
fi
if [[ "$nvmedisk" == "" ]]; then
    echo "no nvmedisk given"
    exit 5
fi
if [[ "$checkblocks" == "" ]]; then
    checkblocks="no"
fi

if [[ "$nvmedisk" == "nvme" ]]; then
    partitionextra="p"
else
    partitionextra=""
fi

# create random string to append to the keyfile and hostname
randstring="$(date +%s | sha256sum | base64 | head -c 8)"

if [[ "$checkblocks" == "yes" ]]; then
    badblocks -c 10240 -s -w -t random -v /dev/"$blockdev"
fi

parted --script /dev/"$blockdev" \
    mklabel msdos \
    mkpart primary 0% 200MiB \
    set 1 boot on \
    mkpart primary 200MiB 4296MiB \
    mkpart primary 4296MiB 100%

bootpart=1
swappart=2
rootpart=3

mkfs.ext2 -L boot /dev/"${blockdev}${partitionextra}${bootpart}"

mkfs.ext4 -L ROOT /dev/"${blockdev}${partitionextra}${rootpart}"
rootmountoptions="rw,noatime,data=ordered,discard"
mount -o $rootmountoptions /dev/"${blockdev}${partitionextra}${rootpart}" /mnt

mkdir -p /mnt/boot
mount /dev/"${blockdev}${partitionextra}${bootpart}" /mnt/boot

pacman -Sy --noconfirm debootstrap debian-archive-keyring

debootstrap \
    --arch=amd64 \
    --variant=minbase \
    --include=linux-image-amd64,systemd,systemd-sysv,apparmor,ifupdown,isc-dhcp-client,less,tzdata,locales,localepurge,sudo,console-setup,kbd,openssh-server \
    buster \
    /mnt \
    http://deb.debian.org/debian

# generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# swap
mkswap -L swap /dev/"${blockdev}${partitionextra}${swappart}"

printf "\n/dev/%s  none  swap  defaults  0  0" "${blockdev}${partitionextra}${swappart}" \
    >> /mnt/etc/fstab

# enable ssh service
ln -sf /lib/systemd/system/ssh.service \
    /mnt/etc/systemd/system/multi-user.target.wants/ssh.service

# set timezone
ln -sf /usr/share/zoneinfo/Europe/Brussels /mnt/etc/localtime

# generate locales for en_US
echo "LANG=en_US.UTF-8" > /mnt/etc/default/locale

# keyboard
echo "KEYMAP=be-latin1" > /mnt/etc/default/keyboard

# set hostname
echo "debian-$randstring" > /mnt/etc/hostname
echo "127.0.1.1 debian-$randstring" >> /mnt/etc/hosts

# install grub-pc via chroot
sed -e "s/%%blockdev%%/\/dev\/${blockdev}/" \
    -e "s/%%admin_user%%/${admin_user}/" \
    -e "s/%%admin_pass%%/${admin_pass}/" \
    -i install-chroot.sh
arch-chroot /mnt /bin/bash < <(cat install-chroot.sh)
