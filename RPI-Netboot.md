# RPI4 Network Boot

There are not that many guides about how to setup network boot on your Pi, and those that do exist, lack a bit in the information department. They skip rather quickly through some questionalble setup, without much explanation about how this even work. 

This guide should provide a bit more comprehensive walk-though along with some information to get a clear picture of what is going on when you turn on the Pi. The guide will solely forcus on setting up the PXE server, prepare the Pi for network boot and populate the server with some images to boot from. The guide will asume that you have a router with an DHCP server supporting `Option 66`. It will cover what this is, and if your router does not support this, you will need to setup a DHCP server that does. Some opensource DNS servers like DNSMasq supports this. It can be installed stand-alone, or you can install something like Pihole which uses DNSMasq. 


## How does it work? 

You have a server that hosts all of the OS files, like a mirror of what is normally written to an sdcard. On this server there is a running instance of a TFTP server that points to the location of the boot files along with an NFS server that points to the location of the main system files. 

In your routers DHCP configuration, you can _(if supported)_ add what is called an `Option 66`. It's basically just a field that can hold an ip address of the TFTP server hosting the boot files. When the RPI boots up in network mode, it will get this ip address from the DHCP server and contact it asking for the required boot files, download them into memory and boot the kernel. During boot the kernel will find a reference in it's kernel parameters _(that we have added)_ for a root filesystem via NFS. At this point the TFTP connection is done and the system will now mount and use the remote NFS system folder to use as the filesystem root. 

It may sound somewhat complex, but it's actually really simple, which will be clear ones the setup is done. The reason why both TFTP and NFS is required is that TFTP is an exstremly simple and light protocol. It's build to serve files that are beging requested and nothing more, which means that it cannot really function as a filesystem. NFS on the other hand is a large and fully functional network filesystem, but this also means that it is not well suided to incoporate into a small EEPROM. So instead TFTP is used to provide the kernel for the initional boot and once it's booted, the kernel can take over using it's own NFS kernel module to access the remaining system. 


## Prepare the RPI

Before you can network boot the RPI you first need to change it's boot order. It may or may not already work, but it's more than likely that it currently is setup to toggle between SDCard and USB boot. 

1. Use the RPI Imager to write Rasbian to a Micro-SDcard and boot from it. 
2. In the terminal launch `raspi-config`. Select `Advanced Options`->`Boot Order` and then `Network Boot`. 
3. Go down to `Finish` and let the Pi reboot. It must be allowed to reboot fully or the new configuration will not be written. 
4. Once the Pi has rebooted, you must find it's serial number. This can be found in `/proc/cpuinfo` in the section `Serial`. You need to write down the last 8 digits that will be required later in the guide. 

    ```sh
    grep Serial /proc/cpuinfo | tail -c 9
    ```
5. Shutdown the Pi and remove the sdcard. Now it's time to setup the server. 


## Setup the host directory

The TFTP and NFS servers need a location to host the files. In this guide we will simply use the location `/pxe/`. The TFTP server will also need to be allowed access to the boot files. We will create a special user for it rather than using the default tftp user. 

```sh
groupadd --system pxe
useradd --gid pxe --system --no-create-home pxe
```

Now install TFTP and NFS. In this guide we will be using `tftpd-hpa` but there are a few more. The configuration may differ though between them. If you are using Ubuntu/Debian, the follwing will install both servers. 

```sh
apt install nfs-server tftp_hpa
```

Setup TFTP to run as our `pxe` user and to use the `/pxe/` location. Edit: `/etc/default/tftpd-hpa` to look as follows. 

```
TFTP_USERNAME="pxe"
TFTP_DIRECTORY="/pxe"
TFTP_ADDRESS=":69"
TFTP_OPTIONS="--secure"
```

Now add the `/pxe/` location to the NFS `/etc/exports` file. 

```
/pxe    *(rw,sync,no_subtree_check,no_root_squash)
```

> Note: If this /pxe/ location is something else than a pure folder, f.eks. a bind mount between a host and something like an LXD container, you will need to add `fsid=[1-255]` to the options. You can use whatever number in this range, but each export must be unique. 

> Note: If you are using something like ZFS and want to have a dataset per OS folder, each OS folder must be added to the exports file. NFS does not allow access across filesystems. F.eks. if you have a dataset /pxe/ubuntu, the export `/pxe` will not allow access to `/pxe/ubuntu` unless you explicitly add that path to the export file. 

Don't forget to reload the configurations from above. 

```sh
systemctl restart tftpd-hpa
exportfs -r
```


## Setup a boot location

Now that we have a fully working server ready to serve files to the Pi, we need something that the Pi can boot. Let's start by creating a folder for the OS. 

```sh
mkdir -p /pxe/debian/{boot,root}

chgrp pxe /pxe/debian/boot
chmod 2775 /pxe/debian/boot
```

Like mentioned before, TFTP need to be able to access the boot files, so we change the group of that location to the pxe group. The `[2]775` in the permissions will make sure that anything created in that folder keeps the same group, so that TFTP does not end up loosing permissions during a system update or something. 

> The `pxe` group is ONLY for the boot location. The root partition and all of it's files must preserve their original owners and permissions. Otherwise you may end up with a broken system. 

Now you need the Raspian SDCard that you created ealier, or create a new. Just make sure that when you create an SDcard with the RPI Imager, that you first boot from that sdcard on the Pi so to let it run it's first-time boot and pre-configuration. Then plug the sdcard into your server. It's time to copy the content to our newly created folders. 

```sh
mount /dev/disk/by-label/bootfs /mnt
cp -a /mnt/* /pxe/debian/boot/
umount /mnt

mount /dev/disk/by-label/rootfs /mnt
cp -a /mnt/* /pxe/debian/root/
umount /mnt
```

We need to make a few changes to the copied system. The `boot` location contains a `cmdline.txt` that contains a few parameters for the kernel to tell it how to boot. Right now it will tell the kernel to use the UUID of `/dev/disk/by-label/rootfs` as the root filesystem and we must change this to use the NFS share instead. 

Open the file `/pxe/debian/boot/cmdline` and remove `root`, `rootfstype` and `fsck.repair`. Now instead add the following to the remaining line in the file. 

```
root=/dev/nfs nfsroot=xxx.xxx.xxx.xxx:/pxe/debian/root ip=dhcp
```

Replace `xxx.xxx.xxx.xxx` with the ip address of your server. This will tell the kernel to use `/pxe/debian/root` on your server via NFS as the root filesystem during boot. 

Lastly we must make some changes to the `fstab` as well, since it to is using the partitions from your sdcard, which must be replaced with the NFS locations. So open the file `/pxe/debian/root/etc/fstab` and change the lines containting the `/` and `/boot` mount points to look like this. 

```
xxx.xxx.xxx.xxx:/pxe/debian/root  /      nfs  defaults,noatime  0  1
xxx.xxx.xxx.xxx:/pxe/debian/boot  /boot  nfs  defaults          0  2
```


## Link TFTP to a boot location

This is where we are. We have a server that is hosting files from `/pxe/debian/` via TFTP and NFS. The job of the DHCP server in this case is to provide the Pi with an IP address to that server via the `Option 66`, but besides that IP the Pi has no idea where on this server the files are placed. So what it will do is request some files like the kernel and cmdline.txt file from a subfolder named after the last 8 digits of it's serial number. In other words it will request something like `8df703b6/cmdline.txt` that the TFTP server will translate to `/pxe/8df703b6/cmdline.txt` because `/pxe/` is setup to be it's root folder. However the boot files are in `/pxe/debian/boot/` and not in `/pxe/8df703b6/` so this will not work. The name `8df703b6` is also not very productive as you will quicly forget which one it belongs to if you have more than one Pi in your house. Also it's not that great to have the boot folder and root folder seperated like that, especially if you are hosting multiple operating system to switch between. Keeping boot and root in the same sub folder is preferable. 

We can fix this using symbolic links. We can also use symbolic links to help keep track of the serial numbers and which Pi each belong to. 

```sh
ln -s ./mypi-pxe 8df703b6
ln -s ./debian/boot mypi-pxe
```

If we list the directory now:

```
8df703b6 -> ./mypi-pxe
mypi-pxe -> ./debian/boot
debian/
```

Now when the Pi request `/pxe/8df703b6/cmdline.txt` it will be translated into `/pxe/mypi-pxe/cmdline.txt` which in turn is translated into `/pxe/debian/boot/cmdline.txt`. At the same time we can always keep track of any serial number just by checking it's target name. We can also quickly switch between multiple operating systems by simply changing the target of `mypi-pxe`.
