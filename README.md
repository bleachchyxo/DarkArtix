DarkArtix
=========

A minimal Artix Linux setup built around runit, dwm, st, and dmenu.

DarkArtix is a collection of scripts and configuration files for installing
and setting up my preferred Artix Linux environment. It uses runit instead
of systemd and a minimal suckless-based graphical environment.

Features
--------

- Artix Linux
- runit
- dwm
- st
- dmenu
- Xorg
- NetworkManager
- ALSA
- dunst
- Custom shell configuration
- Automated disk partitioning and base-system installation

Installation
------------

Requirements

- An Artix Linux ISO using runit
- A USB flash drive or other installation media
- An internet connection
- A target disk

WARNING: install.sh will erase the selected disk.

1. Boot the Artix Linux ISO.

2. Clone the repository:

   git clone https://github.com/bleachchyxo/DarkArtix.git
   cd DarkArtix

3. Run the installer:

   sudo ./install.sh

4. Follow the prompts to select the disk, timezone, hostname,
   username, and passwords.

5. When installation finishes, reboot and remove the installation media.

Environment Setup
-----------------

After booting into the newly installed Artix system, clone the repository
again if necessary and run:

   sudo ./setup-environment.sh

The script installs Xorg and the required packages, builds dwm, st, and
dmenu, configures ALSA and Xinit, and installs the included configuration
files.

After the environment setup is complete, reboot or run:

   startx

Architecture
------------

DarkArtix is split into two stages:

    Artix ISO
        |
        v
    install.sh
        |
        v
    Base Artix + runit
        |
        v
    setup-environment.sh
        |
        v
    Xorg + dwm + st + dmenu
        |
        v
    DarkArtix desktop

Repository Structure
--------------------

    .
    ├── install.sh
    ├── setup-environment.sh
    ├── Files/
    │   └── xinitrc
    └── README.md

Notes
-----

This project is primarily intended for my own Artix Linux installation
workflow. Hardware compatibility and configuration may vary between
systems.

The installer is destructive: always verify the selected disk before
continuing.

License
-------

See the LICENSE file for licensing information.
