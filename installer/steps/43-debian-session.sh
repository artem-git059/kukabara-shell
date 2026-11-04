# shellcheck shell=bash
# kukabara installer — sourced by install.sh in name order (see installer/README.md)

# ── The niri session on Debian ───────────────────────────────────────────────
# Debian testing/sid has quickshell but no niri (and no xwayland-satellite): the session's
# niri is angel-niri (step 42), and the launcher and the systemd user units that start it come
# from extras/debian. They live under /usr/local, which systemd's user unit path and SDDM's
# SessionDir both read. Only on Debian: Arch's niri package brings its own.

DEBIAN_SESSION=skipped
install_debian_session() {
  [[ "$DISTRO_FAMILY" == debian ]] || return 0
  # a config-only run (Settings → Updates, SKIP_PACKAGES=1) writes nothing under /usr/local
  [[ "$SKIP_PACKAGES" != 1 ]] || { say "$(_ 'SKIP_PACKAGES=1: the niri session files are left as they are' \
                                            'SKIP_PACKAGES=1: файлы сессии niri не трогаю')"; return 0; }
  local src="$ROOT/.config/quickshell/angelos/extras/debian" root="${SYSROOT:-}"
  if [[ ! -f "$src/niri-session" || ! -f "$src/niri.service" ]]; then
    warn "$(_ 'The Debian session files are missing from the repository; niri will not start from the login screen' \
             'Файлов сессии Debian нет в репозитории; niri не запустится с экрана входа')"
    return 0
  fi

  # unchanged files are not touched (the run may be an update)
  put() {
    local mode="$1" from="$2" to="$3"
    [[ -f "$to" ]] && cmp -s "$from" "$to" && return 0
    as_root install -D -m "$mode" "$from" "$to"
  }
  say "$(_ 'Installing the niri session (niri-session, systemd units, login entry)…' \
           'Установка сессии niri (niri-session, юниты systemd, пункт входа)…')"
  if ! put 0755 "$src/niri-session" "$root/usr/local/bin/niri-session" ||
     ! put 0644 "$src/niri.service" "$root/usr/local/lib/systemd/user/niri.service" ||
     ! put 0644 "$src/niri-shutdown.target" "$root/usr/local/lib/systemd/user/niri-shutdown.target" ||
     ! put 0644 "$src/niri.desktop" "$root/usr/local/share/wayland-sessions/niri.desktop"; then
    warn "$(_ 'The niri session files could not be installed (see above); the login screen will not start niri' \
             'Файлы сессии niri не поставились (см. выше); экран входа не запустит niri')"
    return 0
  fi
  DEBIAN_SESSION=installed
  [[ -n "$root" ]] || systemctl --user daemon-reload >/dev/null 2>&1 || true
}

# the steps of this file, in the order of the run (see step() in installer/lib/core.sh)
step 43 install_debian_session "the niri session (Debian)" "сессия niri (Debian)"
