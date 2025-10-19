installer/
├── install.sh                  # Orchestrates the install
├── lib/
│   ├── utils.sh                # Helper functions (ask, confirm, etc.)
│   ├── disk.sh                 # Disk detection, validation, etc.
│   ├── partitioning.sh         # Partition logic
│   ├── base.sh                 # Base system install + chroot base config
│   ├── users.sh                # User setup (username, password, etc.)
│   └── timezone.sh             # Timezone & locale config
├── optional/
│   ├── graphical.sh            # Optional: GUI/X11/i3/dwm setup
│   └── dotfiles.sh             # Optional: Copy your dotfiles
└── config/
    ├── xinitrc                 # Custom .xinitrc file
    ├── bashrc                  # Custom .bashrc file
    └── bash_profile            # Custom .bash_profile file
