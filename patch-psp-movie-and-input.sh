#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-source}"
command -v awk >/dev/null

# -----------------------------------------------------------------------------
# 1) Movies: the original SDL2 path temporarily uses a texture/logical size that
# matches the Smacker frame (e.g. 320x156), so SDL scales it to the window.
# Our PSP renderer keeps a 640x480 CPU canvas and a fixed 480x272 GPU texture,
# which otherwise leaves the raw 320x156 movie tiny in the top-left of the
# 640x480 canvas. Scale/center the movie into the 640x480 output surface first;
# the existing PSP final-present path then downsizes that whole canvas to 4:3.
# -----------------------------------------------------------------------------
SVID_CPP="$ROOT/Source/storm/storm_svid.cpp"
awk '
{
    sub(/\r$/, "", $0)

    if (index($0, "SDL_BlitSurface(SVidSurface.get(), nullptr, GetOutputSurface(), nullptr)") != 0) {
        original_if = $0
        getline l2; sub(/\r$/, "", l2)
        getline l3; sub(/\r$/, "", l3)
        getline l4; sub(/\r$/, "", l4)

        if (index(l2, "Log(\"{}\", SDL_GetError());") == 0)
            exit 61
        if (index(l3, "return false;") == 0 || l4 != "\t\t}")
            exit 62

        print "#ifdef PSP"
        print "\t\tSDL_Surface *outputSurface = GetOutputSurface();"
        print "\t\tif (SDL_FillRect(outputSurface, nullptr, SDL_MapRGB(outputSurface->format, 0, 0, 0)) < 0) {"
        print "\t\t\tLog(\"{}\", SDL_GetError());"
        print "\t\t\treturn false;"
        print "\t\t}"
        print "\t\tSDL_Rect outputRect;"
        print "\t\tif (IsLandscapeFit(SVidWidth, SVidHeight, outputSurface->w, outputSurface->h)) {"
        print "\t\t\toutputRect.w = outputSurface->w;"
        print "\t\t\toutputRect.h = static_cast<int>(SVidHeight * outputSurface->w / SVidWidth);"
        print "\t\t} else {"
        print "\t\t\toutputRect.w = static_cast<int>(SVidWidth * outputSurface->h / SVidHeight);"
        print "\t\t\toutputRect.h = outputSurface->h;"
        print "\t\t}"
        print "\t\toutputRect.x = (outputSurface->w - outputRect.w) / 2;"
        print "\t\toutputRect.y = (outputSurface->h - outputRect.h) / 2;"
        print "\t\tSDLSurfaceUniquePtr converted = SDLWrap::ConvertSurfaceFormat("
        print "\t\t    SVidSurface.get(), outputSurface->format->format, 0);"
        print "\t\tif (SDL_BlitScaled(converted.get(), nullptr, outputSurface, &outputRect) <= -1) {"
        print "\t\t\tLog(\"{}\", SDL_GetError());"
        print "\t\t\treturn false;"
        print "\t\t}"
        print "#else"
        print original_if
        print l2
        print l3
        print l4
        print "#endif"
        movie_block++
        next
    }

    print
}
END {
    if (movie_block != 1)
        exit 63
}
' "$SVID_CPP" > "$SVID_CPP.tmp"
mv "$SVID_CPP.tmp" "$SVID_CPP"

# -----------------------------------------------------------------------------
# 2) PSP hero-name editing.
# - The original PSP port intentionally enables PREFILL_PLAYER_NAME so a real
#   PSP can create a character even without a physical keyboard.
# - Preserve that fallback, but when actual SDL text input arrives (PPSSPP/USB
#   keyboard-like environments), replace the suggested name on the first input.
# - While an edit field is active, MenuAction_DELETE (controller X / PSP square
#   after SDL mapping) deletes one character instead of invoking menu deletion.
# -----------------------------------------------------------------------------
DIABLOUI_H="$ROOT/Source/DiabloUI/diabloui.h"
awk '
{
    sub(/\r$/, "", $0)
    print
    if (index($0, "void UiInitList(") == 1) {
        print "void UiReplaceTextOnNextInput();"
        decl++
    }
}
END {
    if (decl != 1)
        exit 65
}
' "$DIABLOUI_H" > "$DIABLOUI_H.tmp"
mv "$DIABLOUI_H.tmp" "$DIABLOUI_H"

DIABLOUI_CPP="$ROOT/Source/DiabloUI/diabloui.cpp"
awk '
BEGIN { after_textinput_case = 0 }
{
    sub(/\r$/, "", $0)

    if ($0 == "bool allowEmptyTextInput = false;") {
        print
        print "#ifdef PSP"
        print "bool replaceTextOnNextInput = false;"
        print "#endif"
        flag_decl++
        next
    }

    if ($0 == "void UiRenderListItems()") {
        print "void UiReplaceTextOnNextInput()"
        print "{"
        print "#ifdef PSP"
        print "\treplaceTextOnNextInput = true;"
        print "#endif"
        print "}"
        print ""
        print
        setter++
        next
    }

    if ($0 == "\tcase MenuAction_DELETE:") {
        print
        print "#ifdef PSP"
        print "\t\tif (textInputActive && UiTextInput != nullptr && UiTextInput[0] != '\''\\0'\'') {"
        print "\t\t\tUiTextInput[FindLastUtf8Symbols(UiTextInput)] = '\''\\0'\'';"
        print "\t\t\treplaceTextOnNextInput = false;"
        print "\t\t\treturn true;"
        print "\t\t}"
        print "#endif"
        delete_added++
        next
    }

    if ($0 == "\t\tcase SDL_TEXTINPUT:") {
        print
        after_textinput_case = 1
        next
    }

    if (after_textinput_case == 1 && $0 == "\t\t\tif (textInputActive) {") {
        print
        print "#ifdef PSP"
        print "\t\t\t\tif (replaceTextOnNextInput) {"
        print "\t\t\t\t\tUiTextInput[0] = '\''\\0'\'';"
        print "\t\t\t\t\treplaceTextOnNextInput = false;"
        print "\t\t\t\t}"
        print "#endif"
        replace_added++
        after_textinput_case = 0
        next
    }

    print
}
END {
    if (flag_decl != 1 || setter != 1 || delete_added != 1 || replace_added != 1)
        exit 66
}
' "$DIABLOUI_CPP" > "$DIABLOUI_CPP.tmp"
mv "$DIABLOUI_CPP.tmp" "$DIABLOUI_CPP"

SELHERO_CPP="$ROOT/Source/DiabloUI/hero/selhero.cpp"
awk '
{
    sub(/\r$/, "", $0)
    print
    if ($0 == "\tUiInitList(nullptr, SelheroNameSelect, SelheroNameEsc, vecSelDlgItems);") {
        print "#ifdef PSP"
        print "\tUiReplaceTextOnNextInput();"
        print "#endif"
        hook++
    }
}
END {
    if (hook != 1)
        exit 67
}
' "$SELHERO_CPP" > "$SELHERO_CPP.tmp"
mv "$SELHERO_CPP.tmp" "$SELHERO_CPP"

# Sanity checks.
grep -q 'SDL_BlitScaled(converted.get(), nullptr, outputSurface, &outputRect)' "$SVID_CPP"
grep -q 'void UiReplaceTextOnNextInput();' "$DIABLOUI_H"
grep -q 'replaceTextOnNextInput = true' "$DIABLOUI_CPP"
grep -q 'UiTextInput\[FindLastUtf8Symbols(UiTextInput)\]' "$DIABLOUI_CPP"
grep -q 'UiReplaceTextOnNextInput();' "$SELHERO_CPP"

echo "PSP movie sizing and hero-name input patch applied successfully"
