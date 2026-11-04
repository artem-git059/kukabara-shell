# shellcheck shell=bash
# kukabara installer — sourced by install.sh in name order (see installer/README.md)

# ── The distribution's package manager ───────────────────────────────────────
# DISTRO_FAMILY: arch (Arch Linux, CachyOS: pacman) or debian (Debian testing/sid: apt).
# DISTRO_ID, DEBIAN_CODENAME and DISTRO_FAMILY are set by installer/steps/05-distro.sh;
# before it runs (and in the tests) the family is Arch's.
DISTRO_FAMILY="${DISTRO_FAMILY:-arch}"
DEBIAN_CODENAME="${DEBIAN_CODENAME:-}"

# pkg_available NAME… → 0 when the repositories (or the installed system) have every name
pkg_available() {
  local pkg
  for pkg in "$@"; do
    if [[ "$DISTRO_FAMILY" == debian ]]; then
      apt-cache show "$pkg" >/dev/null 2>&1 || dpkg-query -W "$pkg" >/dev/null 2>&1 || return 1
    else
      pacman -Si -- "$pkg" >/dev/null 2>&1 || pacman -Q -- "$pkg" >/dev/null 2>&1 || return 1
    fi
  done
}

# pkg_installed NAME… → 0 when every name is installed
pkg_installed() {
  local pkg
  for pkg in "$@"; do
    if [[ "$DISTRO_FAMILY" == debian ]]; then
      [[ "$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null || true)" == *"install ok installed"* ]] || return 1
    else
      pacman -Q -- "$pkg" >/dev/null 2>&1 || return 1
    fi
  done
}

# pkg_install_hint NAME… → the command that installs them, for the messages
pkg_install_hint() {
  if [[ "$DISTRO_FAMILY" == debian ]]; then
    printf 'sudo apt install %s' "$*"
  else
    printf 'sudo pacman -S %s' "$*"
  fi
}

# pkg_list_dir → where this distribution's package lists live (packages/debian on Debian)
pkg_list_dir() {
  if [[ "$DISTRO_FAMILY" == debian ]]; then
    printf '%s\n' "$ROOT/packages/debian"
  else
    printf '%s\n' "$ROOT/packages"
  fi
}
