#!/usr/bin/env bash

set -e

blockdev="%%blockdev%%"

echo "grub-pc grub-pc/install_devices $blockdev" \
    | debconf-set-selections

apt-get install -y grub-pc
