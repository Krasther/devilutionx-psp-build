#!/usr/bin/env bash
set -euo pipefail
set -x

command -v psp-gcc
command -v psp-cmake
command -v awk
command -v sed

rm -rf source build package

git clone --branch psp https://github.com/dports/DevilutionX-PSP.git source

# The upstream PSP branch renders internally at 480x272, but DevilutionX's
# vanilla UI is 640x480 and code paths below 480p can crop or crash. Keep the
# logical UI at 640x480 and split the final PSP GPU upload into two textures so
# neither exceeds the PSP backend's 512x512 texture limit.
bash patch-psp-video.sh source

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

# Keep saves/config beside the EBOOT and force the logical Diablo/UI resolution
# to 640x480. The patched PSP renderer scales this complete 4:3 frame down to
# the physical 480x272 display using two GPU-safe texture tiles.
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

echo "=== Conteudo final do pacote ==="
find package -maxdepth 5 -type f -print

test -f package/DevilutionX/EBOOT.PBP
test -f package/DevilutionX/devilutionx.prx
test -s package/DevilutionX/diablo.ini
test -d package/DevilutionX/assets
test -n "$(find package/DevilutionX/assets -type f -print -quit)"
