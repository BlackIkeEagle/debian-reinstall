#!/usr/bin/env bash

set -e

export DEBIAN_FRONTEND=noninteractive

blockdev="%%blockdev%%"

echo "grub-pc grub-pc/install_devices $blockdev" \
    | debconf-set-selections

apt-get install -y grub-pc tzdata locales localepurge

sed -e 's/#en_US/en_US/g' -e 's/#nl_BE/nl_BE/g' -i /etc/locale.gen
locale-gen

useradd -m ike
usermod -aG sudo,wheel ike
echo "ike:123456" | chpasswd
chage -d 0 ike
