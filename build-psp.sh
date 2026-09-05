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

rm -rf source build package psp-cmake

git clone --branch psp https://github.com/dports/DevilutionX-PSP.git source

echo "PSPDEV=$PSPDEV"
test -f "$PSPDEV/psp/lib/libSDL2.a"
test -f "$PSPDEV/psp/lib/libSDL2main.a"
test -d "$PSPDEV/psp/include/SDL2"
test -f "$PSPDEV/psp/lib/libz.a"
test -f "$PSPDEV/psp/include/zlib.h"

mkdir -p "$GITHUB_WORKSPACE/psp-cmake/SDL2"
cat > "$GITHUB_WORKSPACE/psp-cmake/SDL2/SDL2Config.cmake" <<'EOF'
set(SDL2_FOUND TRUE)
set(SDL2_INCLUDE_DIRS "$ENV{PSPDEV}/psp/include/SDL2")
set(SDL2_LIBRARIES "$ENV{PSPDEV}/psp/lib/libSDL2.a")

if(NOT TARGET SDL2::SDL2)
  add_library(SDL2::SDL2 STATIC IMPORTED)
  set_target_properties(SDL2::SDL2 PROPERTIES
    IMPORTED_LOCATION "$ENV{PSPDEV}/psp/lib/libSDL2.a"
    INTERFACE_INCLUDE_DIRECTORIES "$ENV{PSPDEV}/psp/include/SDL2"
  )
endif()

if(NOT TARGET SDL2::SDL2main)
  add_library(SDL2::SDL2main STATIC IMPORTED)
  set_target_properties(SDL2::SDL2main PROPERTIES
    IMPORTED_LOCATION "$ENV{PSPDEV}/psp/lib/libSDL2main.a"
    INTERFACE_INCLUDE_DIRECTORIES "$ENV{PSPDEV}/psp/include/SDL2"
  )
endif()
EOF

psp-cmake -S source -B build \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DBUILD_PRX=1 \
  -DENC_PRX=1 \
  -DSDL2_DIR="$GITHUB_WORKSPACE/psp-cmake/SDL2" \
  -DZLIB_ROOT="$PSPDEV/psp" \
  -DZLIB_LIBRARY="$PSPDEV/psp/lib/libz.a" \
  -DZLIB_INCLUDE_DIR="$PSPDEV/psp/include"

cmake --build build -j "$(nproc)"

mkdir -p package/DevilutionX
find build -type f \( -name 'EBOOT.PBP' -o -name '*.prx' -o -name '*.mpq' \) \
  -print -exec cp -v {} package/DevilutionX/ \;

find source -maxdepth 3 -type f -name 'devilutionx.mpq' \
  -print -exec cp -v {} package/DevilutionX/ \; || true

printf 'Coloque seu DIABDAT.MPQ nesta pasta antes de copiar para PSP/GAME/DevilutionX/\n' \
  > package/DevilutionX/COLOQUE_O_DIABDAT_AQUI.txt

echo "=== Conteudo final do pacote ==="
find package -maxdepth 3 -type f -print
