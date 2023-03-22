#!/bin/bash

echo -n "Create new user? [y/n]: "
read answer

if [ "${answer,}" != "y" ]; then
    exit 0
fi

while true; do
    echo -n "Username: "
    read name

    if [ -z "$name" ]; then
        echo "Skipping..."; exit 0
        
    elif grep -qe "^$name:" $CHROOT/etc/passwd; then
        echo "User already exists" >&2; continue
    
    elif echo "$name" | grep -qe '^[A-Za-z][A-Za-z0-9]*$'; then
        break
    fi
    
    echo "Invalid username" >&2
done

##
# Running the code directly in chroot will not work with user input. 
# Instead write it to a tmp file and run the file. 
#
cat <<EOF | sudo tee $CHROOT/tmp/run.sh >/dev/null
#!/bin/bash

if id -nu 1000 > /dev/null 2>&1; then
    echo "Removing default user account"

    if which deluser > /dev/null 2>&1; then
        deluser --remove-home $(id -nu 1000)
        
    else
        userdel -r $(id -nu 1000)
    fi
fi

if which adduser > /dev/null 2>&1; then
    adduser --uid 1000 --gid 100 $name
    
else
    useradd --uid 1000 --gid 100 $name
    passwd $name
fi

usermod -aG wheel $name > /dev/null 2>&1
usermod -aG sudo $name > /dev/null 2>&1
EOF

sudo chmod +x $CHROOT/tmp/run.sh
sudo chroot $CHROOT /bin/bash -c '/tmp/run.sh'
sudo rm $CHROOT/tmp/run.sh

