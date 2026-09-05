#!/usr/bin/env bash
set -euo pipefail
set -x

sudo apt-get update
sudo apt-get install -y \
  cmake \
  curl \
  g++ \
  git \
  lcov \
  libgtest-dev \
  libgmock-dev \
  libfmt-dev \
  libsdl2-dev \
  libsodium-dev \
  libpng-dev \
  libbz2-dev \
  wget \
  gettext

rm -rf source build package

git clone --branch psp https://github.com/dports/DevilutionX-PSP.git source

# Follow the PSP port's own GitHub Actions build procedure.
# setup-psptoolchain (from build.yml) provides psp-cmake and the PSP SDK.
# Build the SDL2 revision pinned by DevilutionX itself instead of requiring
# a separately installed PSP SDL2 package.
psp-cmake -S source -B build \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DBUILD_PRX=1 \
  -DENC_PRX=1 \
  -DDEVILUTIONX_SYSTEM_SDL2=OFF

cmake --build build -j "$(nproc)"

mkdir -p package/DevilutionX

# The PSP port generates EBOOT.PBP inside the CMake build tree.
find build -type f \( -name 'EBOOT.PBP' -o -name '*.prx' -o -name 'devilutionx.mpq' \) \
  -print -exec cp -v {} package/DevilutionX/ \;

# Some source distributions may already contain devilutionx.mpq.
find source -maxdepth 4 -type f -name 'devilutionx.mpq' \
  -print -exec cp -v {} package/DevilutionX/ \; || true

printf 'Coloque seu DIABDAT.MPQ nesta pasta antes de copiar para PSP/GAME/DevilutionX/\n' \
  > package/DevilutionX/COLOQUE_O_DIABDAT_AQUI.txt

echo "=== Conteudo final do pacote ==="
find package -maxdepth 3 -type f -print

# Fail clearly if the PSP executable was not produced.
test -f package/DevilutionX/EBOOT.PBP
