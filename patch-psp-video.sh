#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-source}"

command -v awk >/dev/null
command -v sed >/dev/null

# PSP build defaults: keep the full vanilla Diablo logical framebuffer/UI.
PSP_DEFS="$ROOT/CMake/platforms/psp_defs.cmake"
grep -q 'set(DEFAULT_WIDTH 480)' "$PSP_DEFS"
grep -q 'set(DEFAULT_HEIGHT 272)' "$PSP_DEFS"
sed -i 's/set(DEFAULT_WIDTH 480)/set(DEFAULT_WIDTH 640)/' "$PSP_DEFS"
sed -i 's/set(DEFAULT_HEIGHT 272)/set(DEFAULT_HEIGHT 480)/' "$PSP_DEFS"

# Declare the second GPU texture used only by PSP.
DISPLAY_H="$ROOT/Source/utils/display.h"
awk '
{
    sub(/\r$/, "", $0)
    print
    if ($0 == "extern SDLTextureUniquePtr texture;") {
        print "#ifdef PSP"
        print "extern SDLTextureUniquePtr texture2;"
        print "#endif"
        count++
    }
}
END { if (count != 1) exit 41 }
' "$DISPLAY_H" > "$DISPLAY_H.tmp"
mv "$DISPLAY_H.tmp" "$DISPLAY_H"

# dx.cpp: own the second texture, upload the 640-wide CPU surface in two tiles,
# and render those tiles side by side into the 640x480 logical renderer.
DX_CPP="$ROOT/Source/engine/dx.cpp"
awk '
BEGIN { skip = 0 }
{
    sub(/\r$/, "", $0)

    if (skip > 0) {
        skip--
        next
    }

    if ($0 == "SDLTextureUniquePtr texture;") {
        print
        print "#ifdef PSP"
        print "SDLTextureUniquePtr texture2;"
        print "#endif"
        decl++
        next
    }

    if ($0 ~ /^[[:space:]]*texture = nullptr;$/) {
        print
        print "#ifdef PSP"
        print "\ttexture2 = nullptr;"
        print "#endif"
        cleanup++
        next
    }

    if (index($0, "if (SDL_UpdateTexture(texture.get(), nullptr, surface->pixels, surface->pitch) <= -1)") != 0) {
        print "#ifdef PSP"
        print "\t\tif (texture2) {"
        print "\t\t\tconstexpr int FirstTextureWidth = 512;"
        print "\t\t\tconst auto *pixels = static_cast<const unsigned char *>(surface->pixels);"
        print "\t\t\tif (SDL_UpdateTexture(texture.get(), nullptr, pixels, surface->pitch) <= -1)"
        print "\t\t\t\tErrSdl();"
        print "\t\t\tconst int rightOffset = FirstTextureWidth * surface->format->BytesPerPixel;"
        print "\t\t\tif (SDL_UpdateTexture(texture2.get(), nullptr, pixels + rightOffset, surface->pitch) <= -1)"
        print "\t\t\t\tErrSdl();"
        print "\t\t} else"
        print "#endif"
        print "\t\tif (SDL_UpdateTexture(texture.get(), nullptr, surface->pixels, surface->pitch) <= -1) {"
        print "\t\t\tErrSdl();"
        print "\t\t}"
        upload++
        skip = 2
        next
    }

    if (index($0, "if (SDL_RenderCopy(renderer, texture.get(), nullptr, nullptr) <= -1)") != 0) {
        print "#ifdef PSP"
        print "\t\tif (texture2) {"
        print "\t\t\tconstexpr int FirstTextureWidth = 512;"
        print "\t\t\tSDL_Rect leftDst { 0, 0, FirstTextureWidth, gnScreenHeight };"
        print "\t\t\tSDL_Rect rightDst { FirstTextureWidth, 0, gnScreenWidth - FirstTextureWidth, gnScreenHeight };"
        print "\t\t\tif (SDL_RenderCopy(renderer, texture.get(), nullptr, &leftDst) <= -1)"
        print "\t\t\t\tErrSdl();"
        print "\t\t\tif (SDL_RenderCopy(renderer, texture2.get(), nullptr, &rightDst) <= -1)"
        print "\t\t\t\tErrSdl();"
        print "\t\t} else"
        print "#endif"
        print "\t\tif (SDL_RenderCopy(renderer, texture.get(), nullptr, nullptr) <= -1) {"
        print "\t\t\tErrSdl();"
        print "\t\t}"
        render++
        skip = 2
        next
    }

    print
}
END {
    if (decl != 1 || cleanup != 1 || upload != 1 || render != 1)
        exit 42
}
' "$DX_CPP" > "$DX_CPP.tmp"
mv "$DX_CPP.tmp" "$DX_CPP"

# display.cpp: a single PSP texture may not exceed 512x512. Allocate a 512x480
# first tile and a 128x480 second tile when the logical framebuffer is 640x480.
DISPLAY_CPP="$ROOT/Source/utils/display.cpp"
awk '
{
    sub(/\r$/, "", $0)

    if ($0 ~ /^[[:space:]]*texture\.reset\(\);$/) {
        print
        print "#ifdef PSP"
        print "\tif (texture2)"
        print "\t\ttexture2.reset();"
        print "#endif"
        resets++
        next
    }

    if (index($0, "texture = SDLWrap::CreateTexture(renderer, SDL_PIXELFORMAT_ABGR1555, SDL_TEXTUREACCESS_STREAMING, gnScreenWidth, gnScreenHeight);") != 0) {
        print "\tconstexpr int PspTextureMaxWidth = 512;"
        print "\tconst int firstTextureWidth = std::min<int>(gnScreenWidth, PspTextureMaxWidth);"
        print "\ttexture = SDLWrap::CreateTexture(renderer, SDL_PIXELFORMAT_ABGR1555, SDL_TEXTUREACCESS_STREAMING, firstTextureWidth, gnScreenHeight);"
        print "\tif (gnScreenWidth > firstTextureWidth) {"
        print "\t\ttexture2 = SDLWrap::CreateTexture(renderer, SDL_PIXELFORMAT_ABGR1555, SDL_TEXTUREACCESS_STREAMING, gnScreenWidth - firstTextureWidth, gnScreenHeight);"
        print "\t}"
        create++
        next
    }

    print
}
END {
    if (resets != 2 || create != 1)
        exit 43
}
' "$DISPLAY_CPP" > "$DISPLAY_CPP.tmp"
mv "$DISPLAY_CPP.tmp" "$DISPLAY_CPP"

# Final sanity checks.
grep -q 'set(DEFAULT_WIDTH 640)' "$PSP_DEFS"
grep -q 'set(DEFAULT_HEIGHT 480)' "$PSP_DEFS"
grep -q 'SDLTextureUniquePtr texture2;' "$DISPLAY_H"
grep -q 'FirstTextureWidth = 512' "$DX_CPP"
grep -q 'PspTextureMaxWidth = 512' "$DISPLAY_CPP"

echo "PSP 640x480 tiled-texture patch applied successfully"
