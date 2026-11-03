#!/usr/bin/env bash
# kukabara: smooth animations on the NVIDIA proprietary driver.
#
# Qt ≤ 6.11 turns the threaded render loop off on NVIDIA (QTBUG-95817) and Qt
# Quick falls back to the "basic" loop: a 16 ms timer, no vsync, and every
# window of the shell renders on the GUI thread one after another. Upstream
# fixed the real bug in qtbase change 723039 (Qt 6.12). This script rebuilds
# only Qt's wayland-egl client plugin for the installed Qt version with that
# change applied, into ~/.local/share/angelos/qt/<version>/plugins. bin/angelos
# puts it on QT_PLUGIN_PATH for the shell alone; system Qt is not touched.
#
#   qt-egl-fix.sh status   → one JSON line
#   qt-egl-fix.sh build    → progress lines, last line "OK <path>" or "ERR <reason>"
#   qt-egl-fix.sh remove
set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PATCH="$HERE/../patches/qtbase-723039-wayland-egl-threaded.patch"
BASE="${XDG_DATA_HOME:-$HOME/.local/share}/angelos/qt"
SUBDIR="src/plugins/platforms/wayland/plugins/hardwareintegration/wayland-egl"
FILES=(CMakeLists.txt main.cpp wayland-egl.json
  qwaylandeglclientbufferintegration.cpp qwaylandeglclientbufferintegration_p.h
  qwaylandeglinclude_p.h qwaylandeglwindow.cpp qwaylandeglwindow_p.h
  qwaylandglcontext.cpp qwaylandglcontext_p.h)
# pristine v6.11.2 sources (checked before patching; other versions must at least take the patch cleanly)
declare -A SHA_6_11_2=(
  [CMakeLists.txt]=bf33174686245852e4860caa62f3d21b6b853719e9c51daf99cdd7a6e310033d
  [main.cpp]=5729f159de9b695b667a05ec495d9e9dec6cc6ee1d56877add2668e0b5ddf124
  [wayland-egl.json]=5e95e4adbb17531a44460ba9740a63e914024dee2d56c3657f6925792d615ada
  [qwaylandeglclientbufferintegration.cpp]=b9017ef611722ab4cc9a2fef53b0da2239bd45c49a5bc978d351032e1f29bc7f
  [qwaylandeglclientbufferintegration_p.h]=91df58e80559dfcfded0a00dbe3c59c0b5387178301b42722dffe6e38d329987
  [qwaylandeglinclude_p.h]=f9e075e8d3b1ea59bddead67e597579f3ad92ffcb3ea41c5839c5813b71ea9fb
  [qwaylandeglwindow.cpp]=91c226e4bba9eee38ba8399693bf6a03d9df09399e4a040fd2b125072ed03ed5
  [qwaylandeglwindow_p.h]=e1ead2123d22930a91a7ed0e81e0e16f9b020db57f8a011cded476d66936b570
  [qwaylandglcontext.cpp]=339bbbd7e7cba3e2ec620f5b6d4f81fb48ac4c66655b791ebc44a38be78a2964
  [qwaylandglcontext_p.h]=562bba790524132bcb6ab3fb3e2444c357974ed7c486a9eaa27e7ed389eba6ab
)
PATCH_SHA=6605c84f97bdfb1df4be081a2f09efde587adc853123e685cd39326cb92ed64f

qt_version() {
  local q
  for q in /usr/lib/qt6/bin/qtpaths6 /usr/lib64/qt6/bin/qtpaths6 /usr/lib/qt6/bin/qtpaths "$(command -v qtpaths6 || true)"; do
    [[ -n "$q" && -x "$q" ]] && { "$q" --qt-version 2>/dev/null && return 0; }
  done
  return 1
}
nvidia() { [[ -d /sys/module/nvidia || -e /proc/driver/nvidia/version ]]; }
# 6.12+ carries the fix itself
needed_for() { local v="$1"; local mi="${v#6.}"; mi="${mi%%.*}"; [[ "$v" == 6.* && "$mi" =~ ^[0-9]+$ && "$mi" -lt 12 ]]; }
plugin_path() { printf '%s/%s/plugins/wayland-graphics-integration-client/libqt-plugin-wayland-egl.so' "$BASE" "$1"; }

status() {
  local v built=false need=false nv=false
  v="$(qt_version || echo "")"
  nvidia && nv=true
  [[ -n "$v" ]] && needed_for "$v" && need=true
  [[ -n "$v" && -f "$(plugin_path "$v")" ]] && built=true
  printf '{"qt":"%s","nvidia":%s,"needed":%s,"built":%s,"path":"%s"}\n' "$v" "$nv" "$need" "$built" "$([[ -n "$v" ]] && plugin_path "$v")"
}

fail() { echo "ERR $*"; exit 1; }

build() {
  local v tool
  v="$(qt_version)" || fail "qtpaths6 not found (qt6-base)"
  needed_for "$v" || { echo "» Qt $v already has the fix — nothing to build"; echo "OK -"; return 0; }
  for tool in cmake c++ pkg-config curl patch sha256sum; do
    command -v "$tool" >/dev/null || fail "missing tool: $tool"
  done
  command -v ninja >/dev/null || command -v make >/dev/null || fail "missing tool: ninja or make"
  [[ "$(sha256sum "$PATCH" | cut -d' ' -f1)" == "$PATCH_SHA" ]] || fail "patch file was modified"
  [[ -d "/usr/include/qt6/QtWaylandClient/$v/QtWaylandClient/private" ]] || fail "Qt private headers for $v not found"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/angelos-qt-egl.XXXXXX")"
  trap 'rm -rf -- "${tmp:-}"' EXIT
  mkdir -p "$tmp/src"
  echo "» Qt $v: downloading the wayland-egl plugin sources (github.com/qt/qtbase, tag v$v)"
  local f want got
  for f in "${FILES[@]}"; do
    curl -fsSL --proto '=https' --max-time 60 -o "$tmp/src/$f" \
      "https://raw.githubusercontent.com/qt/qtbase/v$v/$SUBDIR/$f" || fail "download failed: $f"
    if [[ "$v" == 6.11.2 ]]; then
      want="${SHA_6_11_2[$f]}"; got="$(sha256sum "$tmp/src/$f" | cut -d' ' -f1)"
      [[ "$got" == "$want" ]] || fail "checksum mismatch: $f"
    fi
  done
  [[ "$v" == 6.11.2 ]] && echo "» checksums OK" || echo "» Qt $v: no pinned checksums, relying on the patch applying cleanly"
  echo "» applying qtbase change 723039 (QTBUG-95817)"
  # the patch is written against the qtbase tree; strip the directory part
  (cd "$tmp/src" && patch -p8 --batch --quiet --no-backup-if-mismatch <"$PATCH") || fail "patch does not apply to Qt $v"
  cat >"$tmp/src/angelos.cmake" <<'EOF'
cmake_minimum_required(VERSION 3.22)
project(angelos_wayland_egl LANGUAGES CXX)
set(CMAKE_AUTOMOC ON)
set(CMAKE_CXX_STANDARD 17)
find_package(Qt6 ${QTVER} EXACT REQUIRED COMPONENTS Core Gui OpenGL WaylandClient)
find_package(Qt6 REQUIRED COMPONENTS CorePrivate GuiPrivate OpenGLPrivate WaylandClientPrivate)
find_package(PkgConfig REQUIRED)
pkg_check_modules(WL REQUIRED IMPORTED_TARGET wayland-client wayland-egl egl)
qt_add_plugin(QWaylandEglClientBufferPlugin SHARED
    OUTPUT_NAME qt-plugin-wayland-egl
    PLUGIN_TYPE wayland-graphics-integration-client
    CLASS_NAME QWaylandEglClientBufferPlugin)
target_sources(QWaylandEglClientBufferPlugin PRIVATE
    main.cpp qwaylandeglclientbufferintegration.cpp qwaylandeglwindow.cpp qwaylandglcontext.cpp)
target_compile_definitions(QWaylandEglClientBufferPlugin PRIVATE QT_NO_CAST_FROM_ASCII)
if(NOT QT_FEATURE_egl_x11)
  target_compile_definitions(QWaylandEglClientBufferPlugin PRIVATE QT_EGL_NO_X11)
endif()
target_link_libraries(QWaylandEglClientBufferPlugin PRIVATE ${CMAKE_DL_LIBS}
    Qt6::Core Qt6::Gui Qt6::OpenGLPrivate Qt6::WaylandClientPrivate Qt6::GuiPrivate Qt6::CorePrivate PkgConfig::WL)
EOF
  mv "$tmp/src/CMakeLists.txt" "$tmp/src/CMakeLists.qt.txt"
  mv "$tmp/src/angelos.cmake" "$tmp/src/CMakeLists.txt"
  echo "» configuring"
  local gen=()
  command -v ninja >/dev/null && gen=(-G Ninja)
  cmake -S "$tmp/src" -B "$tmp/build" "${gen[@]}" -DCMAKE_BUILD_TYPE=Release -DQTVER="$v" >"$tmp/cmake.log" 2>&1 \
    || { tail -5 "$tmp/cmake.log"; fail "cmake configure failed"; }
  echo "» compiling"
  cmake --build "$tmp/build" -j"$(nproc)" >"$tmp/build.log" 2>&1 || { tail -8 "$tmp/build.log"; fail "compile failed"; }
  local out dest
  out="$tmp/build/libqt-plugin-wayland-egl.so"
  [[ -f "$out" ]] || fail "build produced no plugin"
  dest="$(plugin_path "$v")"
  mkdir -p "$(dirname "$dest")"
  install -m 0644 "$out" "$dest.new" && mv -f "$dest.new" "$dest"
  printf '%s\n' "$v" >"$BASE/$v/qt-version"
  echo "» installed: $dest"
  echo "OK $dest"
}

case "${1:-status}" in
  status) status ;;
  build) build ;;
  remove) v="$(qt_version || true)"; [[ -n "$v" ]] && rm -rf -- "${BASE:?}/$v"; echo "OK removed" ;;
  *) echo "usage: $0 status|build|remove" >&2; exit 2 ;;
esac
