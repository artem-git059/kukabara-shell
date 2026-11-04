# shellcheck shell=bash
# kukabara installer — sourced by install.sh in name order (see installer/README.md)

# ── The distribution ─────────────────────────────────────────────────────────

# Arch Linux and CachyOS (pacman), and Debian testing/sid on amd64 (apt): every package comes
# from the distribution's own repositories. Others — even Arch-based or Debian-based ones with
# repositories of their own — are refused before anything changes. DOTFILES_OS_RELEASE: another
# file, for tests.
DISTRO_ID=""
DEBIAN_CODENAME=""
DISTRO_FAMILY=arch
check_distro() {
  local file="${DOTFILES_OS_RELEASE:-/etc/os-release}" id="" like="" name="" codename="" arch
  [[ -r "$file" ]] && { id=$(sed -n 's/^ID=//p' "$file" | tr -d '"'); like=$(sed -n 's/^ID_LIKE=//p' "$file" | tr -d '"');
                        name=$(sed -n 's/^PRETTY_NAME=//p' "$file" | tr -d '"');
                        codename=$(sed -n 's/^VERSION_CODENAME=//p' "$file" | tr -d '"'); }
  DISTRO_ID="$id"
  DEBIAN_CODENAME="$codename"
  arch="$(uname -m)"
  case "$id" in arch|cachyos) return 0 ;; esac
  # Debian testing (forky) and unstable (sid): quickshell is there, niri is not (angel-niri is).
  # Debian stable and the derivatives keep their own mix of packages: refused before anything
  # changes, as Arch-based distributions other than Arch/CachyOS are.
  if [[ "$id" == debian && ( "$codename" == forky || "$codename" == sid ) ]]; then
    if [[ "$arch" != x86_64 ]]; then
      [[ "${DOTFILES_FORCE_DISTRO:-0}" == 1 ]] && { DISTRO_FAMILY=debian
        warn "$(_ "Debian testing/sid on $arch is not supported; going on because DOTFILES_FORCE_DISTRO=1" \
                 "Debian testing/sid на $arch не поддерживается; продолжаю, потому что DOTFILES_FORCE_DISTRO=1")"; return 0; }
      die "$(_ "Only Debian testing/sid on amd64 is supported (this is $arch). Nothing was changed." \
               "Поддерживается только Debian testing/sid на amd64 (а здесь $arch). Ничего не изменено.")"
    fi
    DISTRO_FAMILY=debian
    return 0
  fi
  # configs only (SKIP_PACKAGES=1, as Settings → Updates runs it): nothing comes from the
  # distribution's repositories, so its own repositories don't matter. Updates of a system
  # installed with DOTFILES_FORCE_DISTRO=1 (Arch Linux ARM, EndeavourOS…) get here
  if [[ "$SKIP_PACKAGES" == 1 ]]; then
    [[ "$id" == debian ]] && DISTRO_FAMILY=debian
    warn "$(_ "${name:-This system} is not Arch Linux, CachyOS or Debian testing/sid; going on: SKIP_PACKAGES=1 installs no packages, only the configs" \
             "${name:-Эта система} — не Arch Linux, не CachyOS и не Debian testing/sid; продолжаю: SKIP_PACKAGES=1 ставит только конфиги, без пакетов")"
    return 0
  fi
  [[ "${DOTFILES_FORCE_DISTRO:-0}" == 1 ]] && { [[ "$id" == debian ]] && DISTRO_FAMILY=debian
    warn "$(_ "${name:-This system} is not supported; going on because DOTFILES_FORCE_DISTRO=1" \
             "${name:-Эта система} не поддерживается; продолжаю, потому что DOTFILES_FORCE_DISTRO=1")"; return 0; }
  if [[ "$id" == debian ]]; then
    die "$(_ "${name:-This Debian} is not Debian testing/sid: only forky and sid are supported (quickshell is there; stable's packages are older). DOTFILES_FORCE_DISTRO=1 runs it anyway, at your own risk." \
             "${name:-Этот Debian} — не testing/sid: поддерживаются только forky и sid (там есть quickshell; в stable пакеты старее). DOTFILES_FORCE_DISTRO=1 — запустить всё равно, на свой риск.")"
  fi
  if [[ " $like " == *" debian "* ]]; then
    die "$(_ "${name:-This system} is based on Debian, but only Debian testing/sid is supported: its own repositories may differ. DOTFILES_FORCE_DISTRO=1 runs it anyway, at your own risk." \
             "${name:-Эта система} основана на Debian, но поддерживается только Debian testing/sid: её репозитории могут отличаться. DOTFILES_FORCE_DISTRO=1 — запустить всё равно, на свой риск.")"
  fi
  if [[ " $like " == *" arch "* ]]; then
    die "$(_ "${name:-This system} is based on Arch, but only Arch Linux and CachyOS are supported: its own repositories may differ. DOTFILES_FORCE_DISTRO=1 runs it anyway, at your own risk." \
             "${name:-Эта система} основана на Arch, но поддерживаются только Arch Linux и CachyOS: её репозитории могут отличаться. DOTFILES_FORCE_DISTRO=1 — запустить всё равно, на свой риск.")"
  fi
  die "$(_ "Only Arch Linux, CachyOS and Debian testing/sid are supported (this is ${name:-${id:-an unknown system}}). Nothing was changed." \
           "Поддерживаются только Arch Linux, CachyOS и Debian testing/sid (а здесь ${name:-${id:-неизвестная система}}). Ничего не изменено.")"
}
check_distro

# Debian has no niri, xwayland-satellite or the author's Arch app catalog: the session comes
# from angel-niri, the apps from the setup wizard's own list, the gaming edition and the
# CachyOS repositories are Arch's. SKIP_PACKAGES=1 (Settings → Updates) keeps them off too.
if [[ "$DISTRO_FAMILY" == debian ]]; then
  INSTALL_APPS=0
  INSTALL_GAMING=0
  CACHYOS_REPOS=0
  ANGEL_NIRI=1
fi

[[ "$STAMP" =~ ^[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] || die "DOTFILES_STAMP must look like 20260101-120000 (got: $STAMP)"
[[ "$VALIDATE_NIRI" == 0 || "$VALIDATE_NIRI" == 1 ]] || die "VALIDATE_NIRI must be 0 or 1"
[[ -z "${GITHUB_LOGIN:-}" || "$GITHUB_LOGIN" == 0 || "$GITHUB_LOGIN" == 1 ]] || die "GITHUB_LOGIN must be 0 or 1"
