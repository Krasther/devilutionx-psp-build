#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Expected block not found in {path}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


# DevilutionX's UI is fundamentally 640x480. The PSP fork originally changed
# the internal resolution to 480x272, which crops the 640x480 UI and can crash
# code paths that assume the vanilla UI fits. Keep the logical game/UI at
# 640x480 and scale it down only at the final SDL renderer stage.
replace_once(
    "source/CMake/platforms/psp_defs.cmake",
    "set(DEFAULT_WIDTH 480)\nset(DEFAULT_HEIGHT 272)",
    "set(DEFAULT_WIDTH 640)\nset(DEFAULT_HEIGHT 480)",
)

# Expose a second PSP texture. PSP's SDL/GU backend limits a single texture to
# 512x512, so a 640x480 renderer surface must be uploaded in two horizontal
# tiles (512x480 + 128x480).
replace_once(
    "source/Source/utils/display.h",
    "#ifndef USE_SDL1\nextern SDLTextureUniquePtr texture;\n#endif",
    "#ifndef USE_SDL1\nextern SDLTextureUniquePtr texture;\n#ifdef PSP\nextern SDLTextureUniquePtr texture2;\n#endif\n#endif",
)

replace_once(
    "source/Source/engine/dx.cpp",
    "#ifndef USE_SDL1\nSDLTextureUniquePtr texture;\n#endif",
    "#ifndef USE_SDL1\nSDLTextureUniquePtr texture;\n#ifdef PSP\nSDLTextureUniquePtr texture2;\n#endif\n#endif",
)

replace_once(
    "source/Source/engine/dx.cpp",
    "\ttexture = nullptr;\n\tif (*sgOptions.Graphics.upscale)",
    "\ttexture = nullptr;\n#ifdef PSP\n\ttexture2 = nullptr;\n#endif\n\tif (*sgOptions.Graphics.upscale)",
)

# Upload the CPU renderer surface to one or two PSP-safe textures. The second
# tile starts 512 pixels into each row while retaining the full source pitch.
replace_once(
    "source/Source/engine/dx.cpp",
    "\t\tif (SDL_UpdateTexture(texture.get(), nullptr, surface->pixels, surface->pitch) <= -1) { // pitch is 2560\n\t\t\tErrSdl();\n\t\t}",
    "#ifdef PSP\n\t\tif (texture2) {\n\t\t\tconstexpr int FirstTextureWidth = 512;\n\t\t\tconst auto *pixels = static_cast<const unsigned char *>(surface->pixels);\n\t\t\tif (SDL_UpdateTexture(texture.get(), nullptr, pixels, surface->pitch) <= -1)\n\t\t\t\tErrSdl();\n\t\t\tconst size_t rightOffset = FirstTextureWidth * surface->format->BytesPerPixel;\n\t\t\tif (SDL_UpdateTexture(texture2.get(), nullptr, pixels + rightOffset, surface->pitch) <= -1)\n\t\t\t\tErrSdl();\n\t\t} else\n#endif\n\t\tif (SDL_UpdateTexture(texture.get(), nullptr, surface->pixels, surface->pitch) <= -1) {\n\t\t\tErrSdl();\n\t\t}",
)

replace_once(
    "source/Source/engine/dx.cpp",
    "\t\tif (SDL_RenderCopy(renderer, texture.get(), nullptr, nullptr) <= -1) {\n\t\t\tErrSdl();\n\t\t}",
    "#ifdef PSP\n\t\tif (texture2) {\n\t\t\tconstexpr int FirstTextureWidth = 512;\n\t\t\tSDL_Rect leftDst { 0, 0, FirstTextureWidth, gnScreenHeight };\n\t\t\tSDL_Rect rightDst { FirstTextureWidth, 0, gnScreenWidth - FirstTextureWidth, gnScreenHeight };\n\t\t\tif (SDL_RenderCopy(renderer, texture.get(), nullptr, &leftDst) <= -1)\n\t\t\t\tErrSdl();\n\t\t\tif (SDL_RenderCopy(renderer, texture2.get(), nullptr, &rightDst) <= -1)\n\t\t\t\tErrSdl();\n\t\t} else\n#endif\n\t\tif (SDL_RenderCopy(renderer, texture.get(), nullptr, nullptr) <= -1) {\n\t\t\tErrSdl();\n\t\t}",
)

# Create a 512-wide first tile and only allocate a second tile when needed.
replace_once(
    "source/Source/utils/display.cpp",
    "void ReinitializeTexture()\n{\n\tif (texture)\n\t\ttexture.reset();\n\n\tif (renderer == nullptr)",
    "void ReinitializeTexture()\n{\n\tif (texture)\n\t\ttexture.reset();\n#ifdef PSP\n\tif (texture2)\n\t\ttexture2.reset();\n#endif\n\n\tif (renderer == nullptr)",
)

replace_once(
    "source/Source/utils/display.cpp",
    "#ifdef PSP\n\ttexture = SDLWrap::CreateTexture(renderer, SDL_PIXELFORMAT_ABGR1555, SDL_TEXTUREACCESS_STREAMING, gnScreenWidth, gnScreenHeight);\n#else\n\ttexture = SDLWrap::CreateTexture(renderer, SDL_PIXELFORMAT_RGB888, SDL_TEXTUREACCESS_STREAMING, gnScreenWidth, gnScreenHeight);\n#endif",
    "#ifdef PSP\n\tconstexpr int PspTextureMaxWidth = 512;\n\tconst int firstTextureWidth = std::min<int>(gnScreenWidth, PspTextureMaxWidth);\n\ttexture = SDLWrap::CreateTexture(renderer, SDL_PIXELFORMAT_ABGR1555, SDL_TEXTUREACCESS_STREAMING, firstTextureWidth, gnScreenHeight);\n\tif (gnScreenWidth > firstTextureWidth) {\n\t\ttexture2 = SDLWrap::CreateTexture(renderer, SDL_PIXELFORMAT_ABGR1555, SDL_TEXTUREACCESS_STREAMING, gnScreenWidth - firstTextureWidth, gnScreenHeight);\n\t}\n#else\n\ttexture = SDLWrap::CreateTexture(renderer, SDL_PIXELFORMAT_RGB888, SDL_TEXTUREACCESS_STREAMING, gnScreenWidth, gnScreenHeight);\n#endif",
)

replace_once(
    "source/Source/utils/display.cpp",
    "#else\n\tif (texture)\n\t\ttexture.reset();\n\n\tFreeRenderer();",
    "#else\n\tif (texture)\n\t\ttexture.reset();\n#ifdef PSP\n\tif (texture2)\n\t\ttexture2.reset();\n#endif\n\n\tFreeRenderer();",
)

print("PSP tiled-texture video patch applied successfully")
