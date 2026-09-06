#!/usr/bin/env bash
set -euo pipefail
set -x

command -v psp-gcc
command -v psp-cmake
command -v awk
command -v sed
command -v msgfmt

rm -rf source build package

git clone --branch psp https://github.com/dports/DevilutionX-PSP.git source

# The upstream PSP branch renders internally at 480x272, but DevilutionX's
# vanilla UI assumes a complete 640x480 canvas in several code paths. Keep the
# game/UI logical framebuffer at 640x480, then explicitly downscale the finished
# frame to a native 480x272 PSP output surface before uploading it to the GPU.
bash patch-psp-video.sh source

# The 640x480 -> 363x272 reduction makes the tiny bottom-panel labels especially
# hard to read on the real PSP. Remove those baked labels on PSP and redraw short
# Portuguese labels directly at native 480x272 resolution after the frame scale.
bash patch-psp-ui-legibility.sh source

# The in-game loading screen keeps the main-panel resources alive while it draws
# the cutscene/progress frame. Suppress our native PSP HUD-label overlay while
# that loading state is active so PERS/MISS/MAPA/MENU/INV/MAG cannot leak into it.
bash patch-psp-ui-loading-guard.sh source

# Restore the original movie presentation semantics on top of the fixed PSP
# output path, and make the hero-name edit field usable in PPSSPP/controller
# environments without removing the PSP port's generated-name fallback.
bash patch-psp-movie-and-input.sh source

# Keep the normal Blizzard -> Diablo intro -> title -> main menu flow intact,
# but add a crash-safe trace file (devilutionx.log) so we can see exactly where
# the PSP/PPSSPP path repeats or stops.
bash patch-psp-runtime-trace.sh source

# PPSSPP/PSP does not guarantee that a relative fopen() resolves beside the
# EBOOT. Point the diagnostic trace explicitly at the Memory Stick game folder,
# with the relative path retained only as a fallback.
bash patch-psp-log-path.sh source

# Trace the level-loading path on real hardware. In particular, log every major
# stage of WM_DIABPREVLVL (Cathedral -> Tristram) plus PSP free-memory figures so
# a hard exit can be pinned to the exact allocation/load step.
bash patch-psp-transition-trace.sh source

# Persist the latest Cathedral -> Tristram checkpoint and, after a hard PSP exit,
# show it in an in-game dialog on the next launch. This lets real-hardware tests
# be diagnosed without connecting the Memory Stick to a PC to retrieve the log.
python3 patch-psp-checkpoint-ui.py source

# Match the PSP fork's own build path. Without host smpq, DevilutionX copies its
# runtime UI/font/data files into build/assets and loads them directly at runtime.
# Keep PSPDEV's packaged libraries except for fmt: the current PSPDEV image ships
# fmt 12, while this 2023 DevilutionX port expects its pinned fmt 9 API.
psp-cmake -S source -B build \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DBUILD_PRX=1 \
  -DENC_PRX=1 \
  -DDEVILUTIONX_SYSTEM_LIBFMT=OFF

cmake --build build -j "$(nproc)"

# The PSP loose-assets build does not guarantee that Gettext catalogs are
# generated. Compile the Brazilian Portuguese catalog from the exact same PSP
# source tree and place it at the asset root expected by LanguageInitialize().
mkdir -p build/assets
msgfmt source/Translations/pt_BR.po -o build/assets/pt_BR.mo
test -s build/assets/pt_BR.mo

mkdir -p package/DevilutionX

# PSP executable/module.
find build -type f \( -name 'EBOOT.PBP' -o -name '*.prx' \) \
  -print -exec cp -v {} package/DevilutionX/ \;

# Critical runtime assets. The upstream PSP workflow uploads the whole build
# directory; these files are required when devilutionx.mpq is not generated.
test -d build/assets
cp -a build/assets package/DevilutionX/assets

# If a future environment happens to generate the packed asset archive, include
# it as well. The loose assets above remain the expected fallback for this fork.
find build -maxdepth 2 -type f -name 'devilutionx.mpq' \
  -print -exec cp -v {} package/DevilutionX/ \; || true

# Keep saves/config beside the EBOOT and force the complete vanilla UI canvas.
# The patched PSP presentation path scales this 640x480 frame to a 363x272 4:3
# image centered inside the physical 480x272 display.
cat > package/DevilutionX/diablo.ini <<'EOF'
[Graphics]
Width=640
Height=480
Fullscreen=1
Fit to Screen=0
Upscale=1
Scaling Quality=0
Integer Scaling=0
Vertical Sync=0
EOF

printf 'Coloque seu DIABDAT.MPQ nesta pasta antes de copiar para PSP/GAME/DevilutionX/\n' \
  > package/DevilutionX/COLOQUE_O_DIABDAT_AQUI.txt

printf 'Este build grava o ultimo checkpoint da transicao e o mostra na proxima abertura se o PSP fechar o jogo.\n' \
  > package/DevilutionX/LEIA_LOG_DIAGNOSTICO.txt

echo "=== Conteudo final do pacote ==="
find package -maxdepth 5 -type f -print

test -f package/DevilutionX/EBOOT.PBP
test -f package/DevilutionX/devilutionx.prx
test -s package/DevilutionX/diablo.ini
test -d package/DevilutionX/assets
test -n "$(find package/DevilutionX/assets -type f -print -quit)"
test -s package/DevilutionX/assets/pt_BR.mo
