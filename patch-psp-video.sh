#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-source}"

command -v awk >/dev/null
command -v sed >/dev/null

# Keep the complete vanilla Diablo logical framebuffer/UI. The PSP output stage
# added below downsizes this 640x480 frame to the physical 480x272 display.
PSP_DEFS="$ROOT/CMake/platforms/psp_defs.cmake"
grep -q 'set(DEFAULT_WIDTH 480)' "$PSP_DEFS"
grep -q 'set(DEFAULT_HEIGHT 272)' "$PSP_DEFS"
sed -i 's/set(DEFAULT_WIDTH 480)/set(DEFAULT_WIDTH 640)/' "$PSP_DEFS"
sed -i 's/set(DEFAULT_HEIGHT 272)/set(DEFAULT_HEIGHT 480)/' "$PSP_DEFS"

# dx.cpp: keep rendering into the normal 640x480 CPU surface, then on PSP
# explicitly downscale the completed frame to a native 480x272 staging surface.
# Preserve 4:3 aspect ratio: 640x480 -> 363x272, centered with side bars.
DX_CPP="$ROOT/Source/engine/dx.cpp"
awk '
BEGIN { skip = 0 }
{
    sub(/\r$/, "", $0)

    if (skip > 0) {
        skip--
        next
    }

    if ($0 == "SDLSurfaceUniquePtr PinnedPalSurface;") {
        print
        print "#ifdef PSP"
        print "SDLSurfaceUniquePtr PspOutputSurface;"
        print "#endif"
        staging_decl++
        next
    }

    if ($0 ~ /^[[:space:]]*RendererTextureSurface = nullptr;$/) {
        print
        print "#ifdef PSP"
        print "\tPspOutputSurface = nullptr;"
        print "#endif"
        staging_cleanup++
        next
    }

    if (index($0, "if (SDL_UpdateTexture(texture.get(), nullptr, surface->pixels, surface->pitch) <= -1)") != 0) {
        print "#ifdef PSP"
        print "\t\tconstexpr int PspOutputWidth = 480;"
        print "\t\tconstexpr int PspOutputHeight = 272;"
        print "\t\tconstexpr int PspScaledWidth = 363;"
        print "\t\tconstexpr int PspScaledX = (PspOutputWidth - PspScaledWidth) / 2;"
        print "\t\tif (PspOutputSurface == nullptr) {"
        print "\t\t\tPspOutputSurface = SDLWrap::CreateRGBSurfaceWithFormat("
        print "\t\t\t    0, PspOutputWidth, PspOutputHeight, surface->format->BitsPerPixel, surface->format->format);"
        print "\t\t}"
        print "\t\tif (SDL_FillRect(PspOutputSurface.get(), nullptr, SDL_MapRGB(PspOutputSurface->format, 0, 0, 0)) < 0)"
        print "\t\t\tErrSdl();"
        print "\t\tSDL_Rect pspDstRect { PspScaledX, 0, PspScaledWidth, PspOutputHeight };"
        print "\t\tif (SDL_BlitScaled(surface, nullptr, PspOutputSurface.get(), &pspDstRect) < 0)"
        print "\t\t\tErrSdl();"
        print "\t\tif (SDL_UpdateTexture(texture.get(), nullptr, PspOutputSurface->pixels, PspOutputSurface->pitch) <= -1) {"
        print "\t\t\tErrSdl();"
        print "\t\t}"
        print "#else"
        print "\t\tif (SDL_UpdateTexture(texture.get(), nullptr, surface->pixels, surface->pitch) <= -1) {"
        print "\t\t\tErrSdl();"
        print "\t\t}"
        print "#endif"
        upload++
        skip = 2
        next
    }

    print
}
END {
    if (staging_decl != 1 || staging_cleanup != 1 || upload != 1)
        exit 42
}
' "$DX_CPP" > "$DX_CPP.tmp"
mv "$DX_CPP.tmp" "$DX_CPP"

# display.cpp: GPU texture and renderer logical output are always native PSP
# resolution. RendererTextureSurface remains gnScreenWidth x gnScreenHeight
# (640x480), so the game/UI itself never sees the reduced output resolution.
DISPLAY_CPP="$ROOT/Source/utils/display.cpp"
awk '
{
    sub(/\r$/, "", $0)

    if (index($0, "texture = SDLWrap::CreateTexture(renderer, SDL_PIXELFORMAT_ABGR1555, SDL_TEXTUREACCESS_STREAMING, gnScreenWidth, gnScreenHeight);") != 0) {
        print "\ttexture = SDLWrap::CreateTexture(renderer, SDL_PIXELFORMAT_ABGR1555, SDL_TEXTUREACCESS_STREAMING, 480, 272);"
        create++
        next
    }

    if ($0 ~ /^[[:space:]]*if \(SDL_RenderSetLogicalSize\(renderer, gnScreenWidth, gnScreenHeight\) <= -1\) \{$/) {
        print "#ifdef PSP"
        print "\t\tif (SDL_RenderSetLogicalSize(renderer, 480, 272) <= -1) {"
        print "#else"
        print "\t\tif (SDL_RenderSetLogicalSize(renderer, gnScreenWidth, gnScreenHeight) <= -1) {"
        print "#endif"
        logical++
        next
    }

    print
}
END {
    if (create != 1 || logical != 1)
        exit 43
}
' "$DISPLAY_CPP" > "$DISPLAY_CPP.tmp"
mv "$DISPLAY_CPP.tmp" "$DISPLAY_CPP"

# storm_svid.cpp: movie playback in the original PSP fork recreates a GPU
# texture using the movie/game dimensions. With a 640-wide logical frame that
# would hit the PSP SDL 512x512 texture limit again. Keep movie GPU output native.
SVID_CPP="$ROOT/Source/storm/storm_svid.cpp"
awk '
{
    sub(/\r$/, "", $0)

    if (index($0, "texture = SDLWrap::CreateTexture(renderer, SDL_PIXELFORMAT_ABGR1555, SDL_TEXTUREACCESS_STREAMING, renderWidth, renderHeight);") != 0) {
        print "\t\ttexture = SDLWrap::CreateTexture(renderer, SDL_PIXELFORMAT_ABGR1555, SDL_TEXTUREACCESS_STREAMING, 480, 272);"
        movie_create++
        next
    }

    if (index($0, "texture = SDLWrap::CreateTexture(renderer, SDL_PIXELFORMAT_ABGR1555, SDL_TEXTUREACCESS_STREAMING, gnScreenWidth, gnScreenHeight);") != 0) {
        print "\t\ttexture = SDLWrap::CreateTexture(renderer, SDL_PIXELFORMAT_ABGR1555, SDL_TEXTUREACCESS_STREAMING, 480, 272);"
        restore_create++
        next
    }

    if ($0 ~ /^[[:space:]]*if \(SDL_RenderSetLogicalSize\(renderer, renderWidth, renderHeight\) <= -1\) \{$/) {
        print "#ifdef PSP"
        print "\t\tif (SDL_RenderSetLogicalSize(renderer, 480, 272) <= -1) {"
        print "#else"
        print "\t\tif (SDL_RenderSetLogicalSize(renderer, renderWidth, renderHeight) <= -1) {"
        print "#endif"
        movie_logical++
        next
    }

    if ($0 ~ /^[[:space:]]*if \(renderer != nullptr && SDL_RenderSetLogicalSize\(renderer, gnScreenWidth, gnScreenHeight\) <= -1\) \{$/) {
        print "#ifdef PSP"
        print "\t\tif (renderer != nullptr && SDL_RenderSetLogicalSize(renderer, 480, 272) <= -1) {"
        print "#else"
        print "\t\tif (renderer != nullptr && SDL_RenderSetLogicalSize(renderer, gnScreenWidth, gnScreenHeight) <= -1) {"
        print "#endif"
        restore_logical++
        next
    }

    print
}
END {
    if (movie_create != 1 || restore_create != 1 || movie_logical != 1 || restore_logical != 1)
        exit 44
}
' "$SVID_CPP" > "$SVID_CPP.tmp"
mv "$SVID_CPP.tmp" "$SVID_CPP"

# Final sanity checks.
grep -q 'set(DEFAULT_WIDTH 640)' "$PSP_DEFS"
grep -q 'set(DEFAULT_HEIGHT 480)' "$PSP_DEFS"
grep -q 'PspOutputSurface' "$DX_CPP"
grep -q 'PspScaledWidth = 363' "$DX_CPP"
grep -q 'ABGR1555, SDL_TEXTUREACCESS_STREAMING, 480, 272' "$DISPLAY_CPP"
grep -q 'ABGR1555, SDL_TEXTUREACCESS_STREAMING, 480, 272' "$SVID_CPP"

echo "PSP 640x480 -> 480x272 software-output scaling patch applied successfully"
