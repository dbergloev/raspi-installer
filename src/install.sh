#!/bin/bash -e

declare sysfsname=rpi-root
declare fwfsname=rpi-boot
declare mntpoint=/tmp/raspi
declare devsysfs
declare devfwfs
declare devsys=/dev/disk/by-label/$sysfsname
declare devfw=/dev/disk/by-label/$fwfsname
declare -a media locs
declare -i n=0 x=0 rs=1

##
# Setup cleanup on all possible mountpoints
#

locs[0]=$mntpoint/target/$sysfsname/boot/firmware
locs[1]=$mntpoint/target/$sysfsname/tmp/install.d
locs[2]=$mntpoint/target/$sysfsname/dev
locs[3]=$mntpoint/target/$sysfsname/proc
locs[4]=$mntpoint/target/$sysfsname/sys
locs[5]=$mntpoint/target/$fwfsname
locs[6]=$mntpoint/target/$sysfsname
locs[7]=$mntpoint/media

function cleanup {
    if sudo -n true > /dev/null 2>&1; then
        echo "Tearing down mount points"
        
        for n in "${!locs[@]}"; do
            if grep -q " ${locs[$n]} " /proc/mounts; then
                sudo umount -R "${locs[$n]}"
            fi
        done
    fi
}

trap cleanup EXIT

##
# Check environment
#

if [ ! -b $devsys ]; then
    echo "Missing $sysfsname partition" >&2; exit 1

elif [ ! -b $devfw ]; then
    echo "Missing $fwfsname partition" >&2; exit 1
    
else
    devsysfs=`blkid $devsys | grep -oe 'TYPE=[^ ]\+' | sed 's/^TYPE="\(.*\)"$/\1/'`
    devfwfs=`blkid $devfw | grep -oe 'TYPE=[^ ]\+' | sed 's/^TYPE="\(.*\)"$/\1/'`
    
    if [ -z "$devsysfs" ] || ! grep -qe "$devsysfs$" /proc/filesystems; then
        echo "Invalid filesystem on $sysfsname partition '$devsysfs'" >&2; exit 1
        
    elif [ -z "$devfwfs" ] || ! grep -qe "$devfwfs$" /proc/filesystems; then
        echo "Invalid filesystem on $fwfsname partition '$devfwfs'" >&2; exit 1
    fi
fi

if ! which rsync > /dev/null 2>&1; then
    rs=0
fi


##
# Find and display all installation media 
#

for file in ./*.{iso,img} ./*/*.{iso,img}; do
    if [ -f "$file" ]; then
        echo "[$n] `basename "$file"`"
        media[$n]="$file"
        n=$(($n + 1))
    fi
done

if [ $n -eq 0 ]; then
    echo "Could not find any OS Images" >&2; exit 1
fi


##
# User media selection
#

echo "[$n] Quit"
echo ""

while true; do
    echo -n "Select OS Image: "
    read x

    if ! ( echo "$x" | grep -qe '^[0-9]\+$' ) || [ $x -gt $n ]; then
        echo "Invalid selection" >&2; continue
        
    elif [ $x -eq $n ]; then
        exit 0
        
    elif ! sudo -n true > /dev/null 2>&1 && ! sudo true; then
        exit 1
    fi
    
    break
done


##
# Mounting installation media
#

echo "Setting up mount points"
sudo mkdir -p $mntpoint/{media,target/$fwfsname,target/$sysfsname}
sudo mount -o loop "${media[$x]}" $mntpoint/media
sudo mount $devfw $mntpoint/target/$fwfsname
sudo mount $devsys $mntpoint/target/$sysfsname

if [ ! -d $mntpoint/media/$fwfsname ] || [ ! -d $mntpoint/media/$sysfsname ]; then
    echo "Invalid OS Image" >&2; exit 1
fi


##
# Start installation
#

echo "Begin installation"

for dir in firmware system; do
    echo "Copying files to $dir"

    if [ $rs -eq 1 ]; then
        opt=`test "$dir" = "firmware" && echo "-rvD" || echo "-avl"`
    
        if ! sudo rsync $opt --delete $mntpoint/media/$dir/ $mntpoint/target/$dir/; then
            echo "Installation failed while copying files to $dir" >&2; exit 1
        fi
        
    else
        opt=`test "$dir" = "firmware" && echo "-rv" || echo "-av"`
        
        if ! sudo rm -rfv $mntpoint/target/$dir/*; then
            echo "Installation failed while copying files to $dir" >&2; exit 1
        
        elif ! sudo cp $opt $mntpoint/media/$dir/* $mntpoint/target/$dir/; then
            echo "Installation failed while copying files to $dir" >&2; exit 1
        fi
    fi
done

sudo sed -i "s/root=[^ \t]\+/root=LABEL=$sysfsname/" $mntpoint/target/$fwfsname/cmdline.txt
sudo sed -i "s/rootfstype=[^ \t]\+/rootfstype=$devsysfs/" $mntpoint/target/$fwfsname/cmdline.txt
sudo sed -i "s/^\([^ \t]\+\)[ \t]\+\(\/\)[ \t]\+\([^ \t]\+\)\(.*\)$/LABEL=$sysfsname \2 $devsysfs \4/" $mntpoint/target/$sysfsname/etc/fstab
sudo sed -i "s/^\([^ \t]\+\)[ \t]\+\(\/boot\/firmware\|\/boot\)[ \t]\+\([^ \t]\+\)\(.*\)$/LABEL=$fwfsname \2 $devfwfs \4/" $mntpoint/target/$sysfsname/etc/fstab

##
# Run additional install scripts
#

if [ -d ./install.d ]; then
    echo "Running additional install scripts"

    sudo mkdir -p $mntpoint/target/$sysfsname/{tmp/install.d,boot/firmware,dev,proc,sys}
    sudo mount --bind $mntpoint/target/$fwfsname $mntpoint/target/$sysfsname/boot/firmware 
    sudo mount --bind ./install.d $mntpoint/target/$sysfsname/tmp/install.d
    
    for dir in proc dev sys; do
        sudo mount --rbind /$dir $mntpoint/target/$sysfsname/$dir
        sudo mount --make-rslave $mntpoint/target/$sysfsname/$dir
    done
    
    n=0
    for script in ./install.d/*.sh; do
        if [ -x $script ]; then
            if ! CHROOT="$mntpoint/target/$sysfsname" $script; then
                n=$(($n + 1))
            fi
        fi
    done
    
    if [ $n -gt 0 ]; then
        echo "$n scripts failed to run properly" >&2; exit 1
    fi
fi
