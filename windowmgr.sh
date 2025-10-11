
    pacman -Syyu

Install the `gcc` compiler

    pacman -S gcc

Now we proceed to install important packages;

    libx11 libxinerama libxft git

## Installing and compiling suckless

On your `/home/user` shouln't be any directoy yet, maybe just a couple of hidden files you can see by typing `ls -a` like `.bashrc` but nothing relevant. If so, all linux distros have a hidden config folder on this path, so we must create it

    mkdir .config

Now you `cd` on this new directoy, here we will store all our config files from most of our programs.

    git clone https://git.suckless.org/dwm 

inside `/dwm` theres a file `config.def.h` edit the file with a code inside. you need to find the following line and edit;

     #define MODKEY Mod1Mask

change the number `1` for a `4`; 

      #define MODKEY Mod4Mask
      
then continue downloading the rest

    git clone https://git.suckless.org/dmenu 
    git clone https://git.suckless.org/st

Next thing is to `cd` into each generated directories and do the following;

    make install

Once you finished compiling those three folders want to exit from the `.config` folder and create the starting file;

    cd
    echo "exec dwm" >> ~/.xinitrc

### Installing the last packages

    pacman -S xorg xorg-xinit ttf-dejavu ttf-font-awesome alsa-utils alsa-utils-runit 

### Making ALSA service start after rebooting

    ln -s /etc/runit/sv/alsa /etc/runit/runsvdir/default/

### Initiating suckless by default

    vim ~/.bash_profile

Paste the following script inside the file;

    if [[ -z $DISPLAY ]] && [[ $(tty) = /dev/tty1 ]]; then
        startx
    fi

Now reboot and enjoy!
