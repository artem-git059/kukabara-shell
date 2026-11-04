# shellcheck shell=bash
# kukabara installer — sourced by install.sh in name order (see installer/README.md)

# ── Packages ─────────────────────────────────────────────────────────────────

# names on stdin → the ones the configured repositories have; the rest are skipped with a word
# (a few live only in CachyOS's repositories: on Arch Linux they are the AUR's, which we don't use)
available_only() {
  local pkg
  while IFS= read -r pkg; do
    if pkg_available "$pkg" || pkg_installed "$pkg"; then
      echo "$pkg"
    elif [[ "$DISTRO_FAMILY" == debian ]]; then
      warn "$(_ "$pkg is not in your repositories: skipped" "$pkg нет в ваших репозиториях: пропущен")"
    else
      warn "$(_ "$pkg is not in your repositories (CachyOS has it): skipped" "$pkg нет в ваших репозиториях (он есть в CachyOS): пропущен")"
    fi
  done
}

# names on stdin → minus what the user removed as extras (Settings → Programs → Extras writes
# $STATE_DIR/removed-packages.txt): an update never brings those back
not_removed() {
  local list="${STATE_DIR:-${XDG_STATE_HOME:-$HOME_DIR/.local/state}/angelos}/removed-packages.txt"
  if [[ -s "$list" ]]; then
    grep -vxF -f <(grep -Ev '^[[:space:]]*(#|$)' "$list") || true
  else
    cat
  fi
}

# Will ~/.config/nvim be the LazyVim config of this repository? (as install_configs decides)
nvim_will_be_ours() {
  [[ ! -e "$HOME_DIR/.config/nvim" ]] && return 0
  [[ -f "$MANIFEST" ]] && grep -q '  \.config/nvim/init\.lua$' "$MANIFEST"
}

# The author's repositories (CACHYOS_REPOS): on Arch Linux every package and app of the
# installer comes from pacman as on the author's CachyOS — without [cachyos] Helium, qView and
# LocalSend were "not in your repositories", without [multilib] Steam. Before the package list:
# available_only asks the repositories as they will be.
cachyos_repos() {
  local script="$ROOT/.config/quickshell/angelos/scripts/cachyos-repos.sh"
  [[ "$CACHYOS_REPOS" == 1 && "$DISTRO_ID" == arch && "$(uname -m)" == x86_64 ]] || return 0
  bash "$script" --check && return 0
  say "$(_ "Adding the author's repositories: [cachyos] (below Arch's: only what Arch lacks) and [multilib] — so every app installs with pacman" \
           'Подключаю репозитории автора: [cachyos] (ниже арчевых: только то, чего нет в Arch) и [multilib] — чтобы все программы ставились через pacman')"
  sudo ANGELOS_LANG="$UI" bash "$script" ||
    warn "$(_ "The CachyOS repositories were not added (scripts/cachyos-repos.sh): Helium, qView, LocalSend and Steam may be skipped" \
              'Репозитории CachyOS не подключились (scripts/cachyos-repos.sh): Helium, qView, LocalSend и Steam могут не поставиться')"
}

PKG_FAILED=()
# PACKAGES: what this run installs (packages/*.txt by the answers) — pacman_install and the
# summary before the start (review) count the same list
PACKAGES=()
wanted_packages() {
  local list_dir list packages=()
  list_dir="$(pkg_list_dir)"
  list="$list_dir/pacman.txt"
  mapfile -t packages < <(grep -Ev '^[[:space:]]*(#|$)' "$list")
  if [[ "$DESKTOP_SHELL" == angelos && -f "$list_dir/angelos.txt" ]]; then
    mapfile -t -O "${#packages[@]}" packages < <(grep -Ev '^[[:space:]]*(#|$)' "$list_dir/angelos.txt")
  fi
  if [[ "$INSTALL_SDDM" == 1 ]]; then
    mapfile -t -O "${#packages[@]}" packages < <(grep -Ev '^[[:space:]]*(#|$)' "$list_dir/sddm.txt")
  fi
  if [[ "$INSTALL_TOOLS" == 1 && -f "$list_dir/tools.txt" ]]; then
    mapfile -t -O "${#packages[@]}" packages < <(grep -Ev '^[[:space:]]*(#|$)' "$list_dir/tools.txt")
  fi
  # fish and its look (pure, fastfetch, eza, fzf…); CachyOS's own config package is skipped on Arch
  if [[ "$INSTALL_TOOLS" == 1 || "$FISH_DEFAULT" == 1 ]] && [[ -f "$list_dir/fish.txt" ]]; then
    mapfile -t -O "${#packages[@]}" packages < <(grep -Ev '^[[:space:]]*(#|$)' "$list_dir/fish.txt" | available_only)
  fi
  # what LazyVim needs (it installs its plugins itself on the first start) — only with our config
  if nvim_will_be_ours && [[ -f "$list_dir/nvim.txt" ]]; then
    mapfile -t -O "${#packages[@]}" packages < <(grep -Ev '^[[:space:]]*(#|$)' "$list_dir/nvim.txt")
  fi

  # what the user removed as extras stays removed
  mapfile -t PACKAGES < <(printf '%s\n' "${packages[@]}" | not_removed)
}

# What follows the packages on both distributions: the input group, Bluetooth's service, uinput.
packages_after() {
  # kukabara Meta tap reads the keyboards via evdev (issue #6); the group applies after re-login
  [[ "$DESKTOP_SHELL" == angelos ]] && ! id -nG "$(id -un)" | grep -qw input && sudo usermod -aG input "$(id -un)" || true
  # the same group may make a virtual mouse (mouse-coalesce in games): /dev/uinput is root's alone
  # unless a rule says so (Steam brings one; without Steam nothing did)
  # Bluetooth comes with kukabara (bluez) but a fresh system leaves its service off: the bar's
  # button said «the service is off»
  if [[ "$DESKTOP_SHELL" == angelos ]] && compgen -G '/sys/class/bluetooth/*' >/dev/null &&
     ! systemctl is-enabled bluetooth.service >/dev/null 2>&1; then
    sudo systemctl enable --now bluetooth.service >/dev/null 2>&1 || true
  fi
  local rule=/etc/udev/rules.d/70-angelos-uinput.rules
  if [[ "$DESKTOP_SHELL" == angelos && ! -f "$rule" ]]; then
    printf '# kukabara: the input group makes virtual input devices (mouse-coalesce)\nKERNEL=="uinput", SUBSYSTEM=="misc", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"\n' |
      sudo tee "$rule" >/dev/null && sudo udevadm control --reload 2>/dev/null && sudo udevadm trigger --name-match=uinput 2>/dev/null || true
  fi
}

# Arch Linux and CachyOS: pacman -Syu, the author's repositories, the OCR packs.
arch_install() {
  local pkg code
  command -v pacman >/dev/null 2>&1 || { warn "$(_ 'pacman not found; skipping system packages' 'pacman не найден; системные пакеты пропущены')"; return 0; }
  cachyos_repos

  wanted_packages
  local -a packages=("${PACKAGES[@]}")

  # OCR language packs follow the chosen keyboard layouts.
  for code in "${KB_LIST[@]}"; do
    pkg="${KB_TESS[$code]:-}"
    [[ -n "$pkg" ]] || continue
    if pkg_available "tesseract-data-$pkg"; then
      packages+=("tesseract-data-$pkg")
    else
      warn "$(_ "No OCR language pack for '$code' (tesseract-data-$pkg)" "Нет языкового пакета OCR для '$code' (tesseract-data-$pkg)")"
    fi
  done

  # how much this is, before it starts (what's missing with its dependencies; the system's own
  # upgrade comes on top): the apps, voice input and the like are the wizard's, one by one later
  local mb
  mb="$(pacman -Sp --needed --print-format '%s' "${packages[@]}" 2>/dev/null | awk '{s+=$1} END {printf "%d", s/1048576}')"
  [[ "${mb:-0}" -gt 0 ]] && say "$(_ "kukabara's packages: about $mb MB to download" "Пакеты kukabara: скачается около $mb МБ")"
  # -Syu, not -S: Arch does not support partial upgrades, and with a stale
  # package database a plain -S fails with 404s halfway through.
  say "$(_ 'Updating the system and installing packages (pacman -Syu)…' \
           'Обновление системы и установка пакетов (pacman -Syu)…')"
  # without a terminal nobody answers pacman: its question read EOF, the transaction aborted and
  # set -e ended the whole installer without a word (no configs, no fish, no login screen)
  local noconfirm=()
  ((INTERACTIVE)) || noconfirm=(--noconfirm)
  if ! sudo pacman -Syu --needed "${noconfirm[@]}" "${packages[@]}"; then
    # one name the repositories don't have, a conflict answered "N", a mirror hiccup: pacman
    # drops the whole list. The system is upgraded already (or not: -Syu again below), so the
    # packages go one by one — what can be installed is, the rest is named in the summary.
    warn "$(_ 'pacman did not install the list in one go: one by one now (what fails is listed at the end)' \
              'pacman не поставил список одним разом: ставлю по одному (что не встанет — покажу в конце)')"
    sudo pacman -Syu --noconfirm || true
    for pkg in "${packages[@]}"; do
      pacman -Q -- "$pkg" >/dev/null 2>&1 && continue
      sudo pacman -S --needed --noconfirm -- "$pkg" >/dev/null 2>&1 || PKG_FAILED+=("$pkg")
    done
    ((${#PKG_FAILED[@]})) &&
      warn "$(_ "Not installed: ${PKG_FAILED[*]}  →  sudo pacman -S ${PKG_FAILED[*]}  (it says why)" \
                "Не поставились: ${PKG_FAILED[*]}  →  sudo pacman -S ${PKG_FAILED[*]}  (он скажет почему)")"
  fi
}

# Debian testing/sid: apt-get update + full-upgrade, then the list. Debian's own rules apply:
# no partial upgrade either, and a conffile question must not stop an unattended run.
debian_install() {
  local pkg code
  command -v apt-get >/dev/null 2>&1 || { warn "$(_ 'apt-get not found; skipping system packages' 'apt-get не найден; системные пакеты пропущены')"; return 0; }
  wanted_packages
  local -a packages=("${PACKAGES[@]}")

  # OCR language packs follow the chosen keyboard layouts (Debian: tesseract-ocr-rus, …).
  for code in "${KB_LIST[@]}"; do
    pkg="${KB_TESS[$code]:-}"
    [[ -n "$pkg" ]] || continue
    if pkg_available "tesseract-ocr-$pkg"; then
      packages+=("tesseract-ocr-$pkg")
    else
      warn "$(_ "No OCR language pack for '$code' (tesseract-ocr-$pkg)" "Нет языкового пакета OCR для '$code' (tesseract-ocr-$pkg)")"
    fi
  done

  say "$(_ 'Updating the system and installing packages (apt full-upgrade)…' \
           'Обновление системы и установка пакетов (apt full-upgrade)…')"
  # -y always: without a terminal nobody answers apt, and its question read EOF ended the run;
  # keeping the old conffiles leaves the user's own configuration alone
  local -a apt=(apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
  ((INTERACTIVE)) || export DEBIAN_FRONTEND=noninteractive
  sudo "${apt[@]}" update || warn "$(_ 'apt-get update failed: installing from the package lists already here' \
                                        'apt-get update не удался: ставлю по уже имеющимся спискам пакетов')"
  if ! sudo "${apt[@]}" full-upgrade || ! sudo "${apt[@]}" install "${packages[@]}"; then
    # one unavailable name, a held package, a mirror hiccup: apt drops the whole list. The system
    # is upgraded already, so the packages go one by one — the rest is named in the summary.
    warn "$(_ 'apt did not install the list in one go: one by one now (what fails is listed at the end)' \
              'apt не поставил список одним разом: ставлю по одному (что не встанет — покажу в конце)')"
    sudo "${apt[@]}" full-upgrade || true
    for pkg in "${packages[@]}"; do
      pkg_installed "$pkg" && continue
      sudo "${apt[@]}" install "$pkg" >/dev/null 2>&1 || PKG_FAILED+=("$pkg")
    done
    ((${#PKG_FAILED[@]})) &&
      warn "$(_ "Not installed: ${PKG_FAILED[*]}  →  sudo apt install ${PKG_FAILED[*]}  (it says why)" \
                "Не поставились: ${PKG_FAILED[*]}  →  sudo apt install ${PKG_FAILED[*]}  (он скажет почему)")"
  fi
}

# the step install.sh calls (its name stays pacman_install: the billboard and the music hang on it)
pacman_install() {
  [[ "$SKIP_PACKAGES" == 1 ]] && { say "$(_ 'SKIP_PACKAGES=1: packages skipped' 'SKIP_PACKAGES=1: пакеты пропущены')"; return 0; }
  command -v sudo >/dev/null 2>&1 || die "$(_ 'sudo is required to install packages' 'Для установки пакетов нужен sudo')"
  if [[ "$DISTRO_FAMILY" == debian ]]; then debian_install; else arch_install; fi
  packages_after
}

# kukabara is tested on Quickshell 0.3.2: an older one (a stale mirror, a pinned package)
# runs without its crash fixes, older than 0.3.0 not at all. The shell's own
# scripts/qs-version.sh decides, the shell asks it too (Settings → System).
QS_STATE=""
quickshell_check() {
  [[ "$DESKTOP_SHELL" == angelos ]] || return 0
  local script="$ROOT/.config/quickshell/angelos/scripts/qs-version.sh" state found want
  [[ -f "$script" ]] || return 0
  read -r state found want < <(sh "$script" 2>/dev/null || true) || true
  QS_STATE="$state"
  case "$state" in
    old) warn "$(_ "Quickshell $found is older than $want: kukabara runs, but without its crash fixes — update the quickshell package" \
                   "Quickshell $found старее $want: kukabara запустится, но без исправлений падений — обнови пакет quickshell")" ;;
    too-old) warn "$(_ "Quickshell $found is too old for kukabara (needs $want): update the quickshell package, then log in again" \
                       "Quickshell $found слишком старый для kukabara (нужен $want): обнови пакет quickshell и перезайди")" ;;
    missing) warn "$(_ 'Quickshell is not installed: kukabara needs the quickshell package' \
                       'Quickshell не установлен: kukabara нужен пакет quickshell')" ;;
  esac
  return 0
}

# the steps of this file, in the order of the run (see step() in installer/lib/core.sh)
if [[ "$DISTRO_FAMILY" == debian ]]; then
  step 10 pacman_install "packages (apt full-upgrade)" "пакеты (apt full-upgrade)"
else
  step 10 pacman_install "packages (pacman -Syu)" "пакеты (pacman -Syu)"
fi
step 15 quickshell_check "Quickshell version" "версия Quickshell"
