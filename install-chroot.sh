#!/usr/bin/env bash

set -e

export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

blockdev="%%blockdev%%"

echo "grub-pc grub-pc/install_devices multiselect $blockdev" \
    | debconf-set-selections

apt-get install -y grub-pc

sed -e 's/#en_US/en_US/g' -e 's/#nl_BE/nl_BE/g' -i /etc/locale.gen

cat <<EOF > /etc/network/interfaces.d/lo
auto lo
iface lo inet loopback
EOF

useradd -m ike
usermod -aG sudo ike
echo "ike:123456" | chpasswd
chage -d 0 ike

grub-mkconfig -o /boot/grub/grub.cfg
