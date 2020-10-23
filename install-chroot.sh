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

ip link | awk -F: '$0 !~ "lo|vir|^[^0-9]"{print $2a;getline}' | while read -r iface; do
    cat <<EOF > "/etc/network/interfaces.d/$iface"
auto $iface
iface $iface inet dhcp
EOF
done

useradd -m admin
usermod -aG sudo admin
echo "admin:admin123!" | chpasswd

echo "admin ALL=(root) NOPASSWD: /usr/bin/systemctl poweroff" \
    > /etc/sudoers.d/admin
chmod 0440 /etc/sudoers.d/admin

systemctl enable ssh.service

grub-mkconfig -o /boot/grub/grub.cfg
