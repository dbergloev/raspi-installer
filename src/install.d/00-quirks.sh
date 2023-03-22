#!/bin/bash

##
# Disable UAS for JMicron USB/Sata adapters
#
# These controllers will not work on UAS.
# This will force them to stay on the usb-storage driver. 
#
sudo sed -i 's/^\(.*\)$/\1 usb-storage.quirks=152d:0578:u/' $CHROOT/boot/firmware/cmdline.txt

