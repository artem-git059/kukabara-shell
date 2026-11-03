# kukabara: small things for fish (installed by install.sh; fish reads every file in conf.d,
# so your own config.fish stays yours). angelos-realm.fish next to it is written by kukabara
# itself (the terminal in hell).

# the installer's helpers and kukabara's `angelos` command live here
fish_add_path -g $HOME/.local/bin

status is-interactive; or exit

# n — the editor (Neovim with LazyVim: .config/nvim)
alias n nvim
