#!/usr/bin/env bash
set -euo pipefail
set -x

command -v psp-gcc
command -v psp-cmake

rm -rf source build package

git clone --branch psp https://github.com/dports/DevilutionX-PSP.git source

# The official PSPDEV runtime image is Alpine and intentionally minimal.
# Install only the host build dependencies needed by DevilutionX's own SMPQ
# helper, then build SMPQ so CMake can generate the required devilutionx.mpq.
apk add --no-cache build-base curl zlib-dev bzip2-dev
sed -i 's/^sudo cmake/cmake/' source/tools/build_and_install_smpq.sh
sh source/tools/build_and_install_smpq.sh
command -v smpq

# Build with the PSP port's own configuration inside the official PSPDEV image.
# Keep PSPDEV's packaged libraries except for fmt: the current PSPDEV image ships
# fmt 12, while this 2023 DevilutionX port expects its pinned fmt 9 API.
psp-cmake -S source -B build \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DBUILD_PRX=1 \
  -DENC_PRX=1 \
  -DBUILD_ASSETS_MPQ=ON \
  -DDEVILUTIONX_SYSTEM_LIBFMT=OFF

cmake --build build -j "$(nproc)"

mkdir -p package/DevilutionX

# Collect the executable and runtime files produced by the PSP build.
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
test -f package/DevilutionX/devilutionx.mpq
