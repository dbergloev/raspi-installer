#!/bin/bash

echo -n "Do you want to set a hostname? [y/n]: "
read answer

if [ "${answer,}" != "y" ]; then
    exit 0
fi

while true; do
    echo -n "Hostname: "
    read name

    if [ -z "$name" ]; then
        echo "Skipping..."; exit 0
    
    elif echo "$name" | grep -qe '^[A-Za-z][A-Za-z0-9_]*$'; then
        break
    fi
    
    echo "Invalid hostname" >&2
done

echo $name | sudo tee $CHROOT/etc/hostname >/dev/null

if ! grep -qe '^127.0.1.1[ \t]' $CHROOT/etc/hosts; then
    echo "127.0.1.1 $name" | sudo tee -a $CHROOT/etc/hosts >/dev/null

else
    sudo sed -i "s/^127.0.1.1[ \t].*$/127.0.1.1 $name/" $CHROOT/etc/hosts
fi

