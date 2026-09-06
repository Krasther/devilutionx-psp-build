#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-source}"

command -v awk >/dev/null

# The complete Diablo UI is still rendered at 640x480 and then reduced to a
# 363x272 4:3 image on PSP. The 12px text baked into the six main-panel buttons
# ends up only ~7 physical pixels high, and long translations become especially
# hard to read. On PSP, leave those button backgrounds unlabeled at 640x480 and
# draw compact labels directly into the final 480x272 software surface instead.
MAINPANEL_CPP="$ROOT/Source/panels/mainpanel.cpp"
awk '
{
    sub(/\r$/, "", $0)

    if (index($0, "DrawButtonText(*pBtmBuff, text, { position, { (*PanelButton)[0].width(), 0 } }, UiFlags::ColorButtonface, spacing);") != 0) {
        print "#ifndef PSP"
        print
        print "#endif"
        normal_label++
        next
    }

    if (index($0, "DrawButtonText(out, text, { position + Displacement { 0, 2 }, { out.w(), 0 } }, UiFlags::ColorButtonpushed, spacing);") != 0) {
        print "#ifndef PSP"
        print
        print "#endif"
        pressed_label++
        next
    }

    print
}
END {
    if (normal_label != 1 || pressed_label != 1)
        exit 71
}
' "$MAINPANEL_CPP" > "$MAINPANEL_CPP.tmp"
mv "$MAINPANEL_CPP.tmp" "$MAINPANEL_CPP"

# Draw a tiny but crisp 5x7 native-resolution bitmap font after the 640x480
# frame has been scaled to the PSP output surface. This avoids resampling the
# labels themselves and keeps them readable on the real 480x272 LCD.
DX_CPP="$ROOT/Source/engine/dx.cpp"
awk '
BEGIN { pending_overlay_call = 0 }
{
    sub(/\r$/, "", $0)

    if ($0 == "#include \"engine/dx.h\"") {
        print
        print "#ifdef PSP"
        print "#include \"control.h\""
        print "#include \"movie.h\""
        print "#endif"
        includes++
        next
    }

    if ($0 == "bool CanRenderDirectlyToOutputSurface()") {
        print "#ifdef PSP"
        print "constexpr int PspNativeSourceWidth = 640;"
        print "constexpr int PspNativeSourceHeight = 480;"
        print "constexpr int PspNativeOutputHeight = 272;"
        print "constexpr int PspNativeScaledWidth = 363;"
        print "constexpr int PspNativeScaledX = (480 - PspNativeScaledWidth) / 2;"
        print ""
        print "const uint8_t *PspNativeGlyph(char ch)"
        print "{"
        print "\tstatic constexpr uint8_t A[7] = { 0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11 };"
        print "\tstatic constexpr uint8_t E[7] = { 0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F };"
        print "\tstatic constexpr uint8_t G[7] = { 0x0F, 0x10, 0x10, 0x17, 0x11, 0x11, 0x0F };"
        print "\tstatic constexpr uint8_t I[7] = { 0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x1F };"
        print "\tstatic constexpr uint8_t M[7] = { 0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11 };"
        print "\tstatic constexpr uint8_t N[7] = { 0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11 };"
        print "\tstatic constexpr uint8_t P[7] = { 0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10 };"
        print "\tstatic constexpr uint8_t R[7] = { 0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11 };"
        print "\tstatic constexpr uint8_t S[7] = { 0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E };"
        print "\tstatic constexpr uint8_t U[7] = { 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E };"
        print "\tstatic constexpr uint8_t V[7] = { 0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04 };"
        print "\tswitch (ch) {"
        print "\tcase \047A\047: return A;"
        print "\tcase \047E\047: return E;"
        print "\tcase \047G\047: return G;"
        print "\tcase \047I\047: return I;"
        print "\tcase \047M\047: return M;"
        print "\tcase \047N\047: return N;"
        print "\tcase \047P\047: return P;"
        print "\tcase \047R\047: return R;"
        print "\tcase \047S\047: return S;"
        print "\tcase \047U\047: return U;"
        print "\tcase \047V\047: return V;"
        print "\tdefault: return nullptr;"
        print "\t}"
        print "}"
        print ""
        print "void PspNativePutPixel(SDL_Surface *surface, int x, int y, uint16_t color)"
        print "{"
        print "\tif (x < 0 || y < 0 || x >= surface->w || y >= surface->h)"
        print "\t\treturn;"
        print "\tauto *row = reinterpret_cast<uint16_t *>(static_cast<uint8_t *>(surface->pixels) + y * surface->pitch);"
        print "\trow[x] = color;"
        print "}"
        print ""
        print "void PspNativeDrawGlyph(SDL_Surface *surface, int x, int y, char ch, uint16_t color)"
        print "{"
        print "\tconst uint8_t *glyph = PspNativeGlyph(ch);"
        print "\tif (glyph == nullptr)"
        print "\t\treturn;"
        print "\tfor (int row = 0; row < 7; ++row) {"
        print "\t\tfor (int col = 0; col < 5; ++col) {"
        print "\t\t\tif ((glyph[row] & (1U << (4 - col))) != 0)"
        print "\t\t\t\tPspNativePutPixel(surface, x + col, y + row, color);"
        print "\t\t}"
        print "\t}"
        print "}"
        print ""
        print "int PspNativeTextWidth(const char *text)"
        print "{"
        print "\tint length = 0;"
        print "\twhile (text[length] != \047\\0\047)"
        print "\t\t++length;"
        print "\treturn length == 0 ? 0 : length * 6 - 1;"
        print "}"
        print ""
        print "SDL_Rect PspNativeScaleButtonRect(const SDL_Rect &button)"
        print "{"
        print "\tconst Rectangle &panel = GetMainPanel();"
        print "\tconst int sourceLeft = panel.position.x + button.x;"
        print "\tconst int sourceTop = panel.position.y + button.y;"
        print "\tconst int sourceRight = sourceLeft + button.w;"
        print "\tconst int sourceBottom = sourceTop + button.h;"
        print "\tconst int left = PspNativeScaledX + (sourceLeft * PspNativeScaledWidth + PspNativeSourceWidth / 2) / PspNativeSourceWidth;"
        print "\tconst int top = (sourceTop * PspNativeOutputHeight + PspNativeSourceHeight / 2) / PspNativeSourceHeight;"
        print "\tconst int right = PspNativeScaledX + (sourceRight * PspNativeScaledWidth + PspNativeSourceWidth / 2) / PspNativeSourceWidth;"
        print "\tconst int bottom = (sourceBottom * PspNativeOutputHeight + PspNativeSourceHeight / 2) / PspNativeSourceHeight;"
        print "\treturn SDL_Rect { left, top, right > left ? right - left : 1, bottom > top ? bottom - top : 1 };"
        print "}"
        print ""
        print "void PspNativeDrawButtonLabel(SDL_Surface *surface, const SDL_Rect &button, const char *text)"
        print "{"
        print "\tconst int width = PspNativeTextWidth(text);"
        print "\tconst int x = button.x + (button.w - width) / 2;"
        print "\tconst int y = button.y + (button.h - 7) / 2;"
        print "\tconst uint16_t shadow = static_cast<uint16_t>(SDL_MapRGB(surface->format, 18, 12, 5));"
        print "\tconst uint16_t face = static_cast<uint16_t>(SDL_MapRGB(surface->format, 220, 190, 105));"
        print "\tfor (int pass = 0; pass < 2; ++pass) {"
        print "\t\tint penX = x;"
        print "\t\tconst int offset = pass == 0 ? 1 : 0;"
        print "\t\tconst uint16_t color = pass == 0 ? shadow : face;"
        print "\t\tfor (const char *p = text; *p != \047\\0\047; ++p) {"
        print "\t\t\tPspNativeDrawGlyph(surface, penX + offset, y + offset, *p, color);"
        print "\t\t\tpenX += 6;"
        print "\t\t}"
        print "\t}"
        print "}"
        print ""
        print "void DrawPspNativePanelLabels(SDL_Surface *surface)"
        print "{"
        print "\tif (!pBtmBuff.has_value() || movie_playing || surface == nullptr || surface->format->BytesPerPixel != 2)"
        print "\t\treturn;"
        print "\tstatic constexpr const char *Labels[6] = { \"PERS\", \"MISS\", \"MAPA\", \"MENU\", \"INV\", \"MAG\" };"
        print "\tif (SDL_MUSTLOCK(surface) && SDL_LockSurface(surface) < 0)"
        print "\t\treturn;"
        print "\tfor (int i = 0; i < 6; ++i)"
        print "\t\tPspNativeDrawButtonLabel(surface, PspNativeScaleButtonRect(PanBtnPos[i]), Labels[i]);"
        print "\tif (SDL_MUSTLOCK(surface))"
        print "\t\tSDL_UnlockSurface(surface);"
        print "}"
        print "#endif"
        print ""
        print
        helpers++
        next
    }

    if (pending_overlay_call != 0) {
        print
        print "\t\tDrawPspNativePanelLabels(PspOutputSurface.get());"
        pending_overlay_call = 0
        overlay_call++
        next
    }

    if (index($0, "if (SDL_BlitScaled(surface, nullptr, PspOutputSurface.get(), &pspDstRect) < 0)") != 0) {
        print
        pending_overlay_call = 1
        next
    }

    print
}
END {
    if (includes != 1 || helpers != 1 || overlay_call != 1 || pending_overlay_call != 0)
        exit 72
}
' "$DX_CPP" > "$DX_CPP.tmp"
mv "$DX_CPP.tmp" "$DX_CPP"

grep -q 'DrawPspNativePanelLabels' "$DX_CPP"
grep -q 'static constexpr const char \*Labels\[6\]' "$DX_CPP"
grep -q '#ifndef PSP' "$MAINPANEL_CPP"

echo "PSP native-resolution main-panel labels patch applied successfully"
