#!/usr/bin/env bash
set -euo pipefail
set -x

command -v psp-gcc
command -v psp-cmake

rm -rf source build package

git clone --branch psp https://github.com/dports/DevilutionX-PSP.git source

# Build with the PSP port's own configuration inside the official PSPDEV image.
# Keep PSPDEV's packaged libraries except for fmt: the current PSPDEV image ships
# fmt 12, while this 2023 DevilutionX port expects its pinned fmt 9 API.
psp-cmake -S source -B build \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DBUILD_PRX=1 \
  -DENC_PRX=1 \
  -DDEVILUTIONX_SYSTEM_LIBFMT=OFF

cmake --build build -j "$(nproc)"

mkdir -p package/DevilutionX

# Collect the executable and any runtime files produced by the PSP build.
find build -type f \( -name 'EBOOT.PBP' -o -name '*.prx' -o -name 'devilutionx.mpq' \) \
  -print -exec cp -v {} package/DevilutionX/ \;

# Some source distributions may already contain devilutionx.mpq.
find source -maxdepth 4 -type f -name 'devilutionx.mpq' \
  -print -exec cp -v {} package/DevilutionX/ \; || true

printf 'Coloque seu DIABDAT.MPQ nesta pasta antes de copiar para PSP/GAME/DevilutionX/\n' \
  > package/DevilutionX/COLOQUE_O_DIABDAT_AQUI.txt

echo "=== Conteudo final do pacote ==="
find package -maxdepth 3 -type f -print

test -f package/DevilutionX/EBOOT.PBP
