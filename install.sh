#!/usr/bin/env bash

set -e

#echo "*** WARNING ****************************************************"
#echo "* HAVE YOU PASSED IN THE PACKAGE FILES YOU WANT FOR INSTALL ?  *"
#echo "*** WARNING ****************************************************"

echo -n "enter the block device's name (sda,nvme1): "
read -r blockdev

echo -n "efi booting or legacy (efi|legacy): "
read -r boottype

echo -n "main filesystem (xfs|ext4|btrfs): "
read -r filesystem

echo -n "nvme disk or regular (nvme|regular): "
read -r nvmedisk

echo -n "check blocks (yes|no (default)): "
read -r checkblocks

if [[ "$blockdev" == "" ]]; then
    echo "no blockdev given"
    exit 1
fi
if [[ "$boottype" == "" ]]; then
    echo "no boottype given"
    exit 2
fi
if [[ "$filesystem" == "" ]]; then
    echo "no filesystem given"
    exit 4
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

if [[ "$boottype" == "efi" ]]; then
    if [[ "$checkblocks" == "yes" ]]; then
        badblocks -c 10240 -s -w -t random -v /dev/"$blockdev"
    fi

    parted --script /dev/"$blockdev" \
        mklabel gpt \
        mkpart ESP fat32 0% 200MiB \
        set 1 esp on \
        set 1 legacy_boot on \
        mkpart primary 200MiB 400MiB \
        mkpart primary 400MiB 4496MiB \
        mkpart primary 4496MiB 100%

    efipart=1
    bootpart=2
    swappart=3
    rootpart=4

    # EFI Partition
    mkfs.fat -F32 -n EFI /dev/"${blockdev}${partitionextra}${efipart}"
    mkfs.ext2 -L boot /dev/"${blockdev}${partitionextra}${bootpart}"
else
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
fi

#basepackagelist=("base-packages.txt")
if [[ "$filesystem" == "btrfs" ]]; then
    #basepackagelist+=("btrfs-packages.txt")

    # "ROOT"
    mkfs.btrfs -L ROOT /dev/"${blockdev}${partitionextra}${rootpart}"
    mount /dev/"${blockdev}${partitionextra}${rootpart}" /mnt
    mkdir -p /mnt/var
    mkdir -p /mnt/var/lib
    btrfs subvolume create /mnt/root
    btrfs subvolume create /mnt/home
    btrfs subvolume create /mnt/var/cache
    btrfs subvolume create /mnt/var/lib/docker
    btrfs subvolume list -p /mnt

    umount /mnt

    rootmountoptions="rw,noatime,nodiratime,ssd,space_cache,compress=lzo,subvol=root"

    mount -o $rootmountoptions /dev/"${blockdev}${partitionextra}${rootpart}" /mnt
    mkdir -p /mnt/home
    mount -o rw,noatime,nodiratime,ssd,space_cache,compress=lzo,subvol=home /dev/"${blockdev}${partitionextra}${rootpart}" /mnt/home
    mkdir -p /mnt/var/cache
    mount -o rw,noatime,nodiratime,ssd,space_cache,compress=lzo,subvol=var/cache /dev/"${blockdev}${partitionextra}${rootpart}" /mnt/var/cache
    mkdir -p /mnt/var/lib/docker
    mount -o rw,noatime,nodiratime,ssd,space_cache,compress=lzo,subvol=var/lib/docker /dev/"${blockdev}${partitionextra}${rootpart}" /mnt/var/lib/docker
elif [[ "$filesystem" == "xfs" ]]; then
    #basepackagelist+=("xfs-packages.txt")

    mkfs.xfs -L ROOT /dev/"${blockdev}${partitionextra}${rootpart}"
    rootmountoptions="rw,noatime,attr2,inode64,noquota,discard"
    mount -o $rootmountoptions /dev/"${blockdev}${partitionextra}${rootpart}" /mnt
elif [[ "$filesystem" == "ext4" ]]; then
    #basepackagelist+=("ext4-packages.txt")

    mkfs.ext4 -L ROOT /dev/"${blockdev}${partitionextra}${rootpart}"
    rootmountoptions="rw,noatime,data=ordered,discard"
    mount -o $rootmountoptions /dev/"${blockdev}${partitionextra}${rootpart}" /mnt
else
    echo "unsupported filesystem defined"
    exit 1
fi

bootloaderpackage=grub
if [[ "$boottype" == "efi" ]]; then
    bootloaderpackage="$bootloaderpackage efibootmgr"
    mkdir -p /mnt/boot
    mount /dev/"${blockdev}${partitionextra}${bootpart}" /mnt/boot
    mkdir -p /mnt/boot/efi
    mount /dev/"${blockdev}${partitionextra}${efipart}" /mnt/boot/efi
    mkdir -p /mnt/boot/efi/EFI/debian
else
    mkdir -p /mnt/boot
    mount /dev/"${blockdev}${partitionextra}${bootpart}" /mnt/boot
fi

pacman -Sy --noconfirm debootstrap debian-archive-keyring

debootstrap \
    --arch=amd64 \
    --variant=minbase \
    buster \
    /mnt \
    http://deb.debian.org/debian

# generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# swap
mkswap -L swap /dev/"${blockdev}${partitionextra}${swappart}"

printf "\n/dev/%s  none  swap  defaults  0  0" "${blockdev}${partitionextra}${swappart}" \
    >> /mnt/etc/fstab

# set timezone
ln -sf /usr/share/zoneinfo/Europe/Brussels /mnt/etc/localtime

# generate locales for en_US
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

# keyboard
echo "KEYMAP=be-latin1" > /mnt/etc/vconsole.conf

# set hostname
echo "debian-$randstring" > /mnt/etc/hostname
echo "127.0.1.1 debian-$randstring" >> /mnt/etc/hosts

# install grub-pc via chroot
sed -e "s/%%blockdev%%/\/dev\/${blockdev}/" -i install-chroot.sh
arch-chroot /mnt /bin/bash < <(cat install-chroot.sh)