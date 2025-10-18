installer/
├── main.sh                      # Orchestrates the install
├── lib/
│   ├── utils.sh                 # ask, confirm, print_message, etc.
│   ├── disk.sh                  # disk detection, validation, unmount
│   ├── partitioning.sh          # calculates and creates partitions
│   ├── base.sh                  # base system install + chroot base config
│   ├── users.sh                 # username, password, sudo setup
│   └── timezone.sh              # timezone and locale config
├── optional/
│   ├── graphical.sh             # GUI/X11/dwm/i3/xfce setup
│   └── dotfiles.sh              # Copies your dotfiles
└── config/
    ├── xinitrc                  # Your custom .xinitrc
    ├── bashrc                   # Your custom .bashrc
    └── bash_profile             # Your .bash_profile

