# RPI Installer

The easiest way to install an OS to a Pi is to use the Pi Imager to write the OS to an sdcard. There is also the option to setup netboot or even network installation over the internet. But there may be situations where this is not so simple. For an example if you do USB boot to a HDD/SSD, with custom partition layout. Whatever the case, some times the Imager may not be the best option for you. This installer let's you create a USB disk or sdcard that can be used as an installer containing one or more images to choose from. At the same time you can also add custom configurations that will setup your Pi to your liking and have that automatically applied every time you install an OS. This makes it fast and simple to re-install/switch OS whenever required. 


## Network Boot

You may also want to look into local [Network Boot](RPI-Netboot.md)


## Setup installation media

To get started you will need a RPI OS. The easiest way is to write one to an sdcard using the RPI Imager. Once this is done, you can use the sdcard as the installation media as is or copy the partitions to a usb disk. This media is what you will boot into whenever you want to install something to a Pi, so whatever medium is easiest for your setup. The installer can also install directly on to an sdcard if that is what you are using as boot device on the Pi. 

Download the `src` folder of this repo onto the installation media. The location does not mater, something like `/root/installer/` is a perfect option. 


## Create installation images

You will need an image to install to your RPI. This installer works with anything that be mounted with the installation media OS, like an `ISO` image or an `IMG` containing something like `SquashFS`. The only requirement is that the image contains two folders, `rpi-boot` for the boot/firmware files and `rpi-root` for the root filesystem. 

You can write an image to an sdcard or use the one you created for the installation media. It may be a good idea to do an initial boot on the sdcard first, to let the OS run it's pre-configurations before copying the content elsewhere. 

Now just copy the content of the sdcard to a folder. 

```sh
mkdir -p image/{rpi-boot,rpi-root}

mount /dev/disk/by-label/bootfs /mnt
cp -a /mnt/* image/rpi-boot/
umount /mnt

mount /dev/disk/by-label/rootfs /mnt
cp -a /mnt/* image/rpi-root/
umount /mnt
```

Then create an image. 

```sh
mksquashfs image/ debian.img
```

Copy the image to your installation media `/root/installer/`. You can place it in the installation root or create a sub-folder for multiple images. 


## Installation

To use the installer, boot your RPI with your installation media. Remember that RPI does not have any boot select options, so it will boot whatever you have set it's priority to be. You may need to remove your primary boot device and plug it back in once the installer has been booted. 

The installer can be used on any partion layout and device. The requirement is that the partition for boot/firmware has a label `rpi-boot` and the root partition has a label `rpi-root`. You can easily change the labels on existing partitions. 

```sh
fatlabel /dev/sdx1 rpi-boot
e2label /dev/sdx2 rpi-root
```

> Note: This is only a one-time setup. These labels will be remembered and will not be required to be changed the next time you run the installer.

Just replace `sdx1` and `sdx2` with your device names. 

Now simply launch the installer. 

```sh
/root/installer/install.sh
```

You should now see something like this, and you are good to go.

```
[0] debian.img
[1] Quit

Select OS Image: 
```
