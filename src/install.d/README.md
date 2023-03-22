# Custom install files

Files within this folder will be executed by the installer once the installation is done. This allows you to make custom configurations to the installed system before rebooting into it. 

The installer will setup a complete chroot environment for the new system that can be accessed via the environment variable `$CHROOT`. 

The installer already comes with a few example scripts. 
