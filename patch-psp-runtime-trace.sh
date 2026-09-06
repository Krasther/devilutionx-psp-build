#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-source}"

command -v awk >/dev/null

# Tiny PSP-only trace helper. Open/flush/close on every line so the trace survives
# a crash or hard shutdown and can be copied straight from the Memory Stick.
cat > "$ROOT/Source/utils/psp_debug_log.h" <<'EOF'
#pragma once

#ifdef PSP
#include <cstdarg>
#include <cstdio>

inline void PspDebugLog(const char *format, ...)
{
	std::FILE *file = std::fopen("devilutionx.log", "a");
	if (file == nullptr)
		return;

	va_list args;
	va_start(args, format);
	std::vfprintf(file, format, args);
	va_end(args);
	std::fputc('\n', file);
	std::fflush(file);
	std::fclose(file);
}

inline void PspDebugLogReset()
{
	std::FILE *file = std::fopen("devilutionx.log", "w");
	if (file == nullptr)
		return;
	std::fputs("=== DevilutionX PSP runtime trace ===\n", file);
	std::fflush(file);
	std::fclose(file);
}
#else
inline void PspDebugLog(const char *, ...) {}
inline void PspDebugLogReset() {}
#endif
EOF

# diablo.cpp: trace the exact startup flow: splash logo -> Diablo intro -> title -> menu.
DIABLO_CPP="$ROOT/Source/diablo.cpp"
awk '
BEGIN { skip = 0 }
{
    sub(/\r$/, "", $0)

    if (skip > 0) {
        skip--
        next
    }

    if ($0 == "#include \"utils/paths.h\"") {
        print
        print "#include \"utils/psp_debug_log.h\""
        include_added++
        next
    }

    if ($0 == "\tApplicationInit();") {
        print
        print "\tPspDebugLogReset();"
        print "\tPspDebugLog(\"DiabloMain: ApplicationInit complete\");"
        reset_added++
        next
    }

    if ($0 == "void DiabloSplash()") {
        print
        getline n
        sub(/\r$/, "", n)
        print n
        print "\tPspDebugLog(\"DiabloSplash ENTER gbShowIntro=%d\", gbShowIntro ? 1 : 0);"
        splash_enter++
        next
    }

    if ($0 == "\tif (*sgOptions.StartUp.splash == StartUpSplash::LogoAndTitleDialog)") {
        getline movie
        sub(/\r$/, "", movie)
        if (index(movie, "play_movie(\"gendata\\\\logo.smk\", true);") == 0)
            exit 51
        print "\tif (*sgOptions.StartUp.splash == StartUpSplash::LogoAndTitleDialog) {"
        print "\t\tPspDebugLog(\"DiabloSplash: logo.smk BEGIN\");"
        print "\t\tplay_movie(\"gendata\\\\logo.smk\", true);"
        print "\t\tPspDebugLog(\"DiabloSplash: logo.smk END\");"
        print "\t}"
        logo_block++
        next
    }

    if ($0 == "\t\tif (gbIsHellfire)") {
        getline hellmovie
        getline els
        getline diabmovie
        sub(/\r$/, "", hellmovie)
        sub(/\r$/, "", els)
        sub(/\r$/, "", diabmovie)
        if (index(hellmovie, "play_movie(\"gendata\\\\Hellfire.smk\", true);") == 0 || els != "\t\telse" || index(diabmovie, "play_movie(\"gendata\\\\diablo1.smk\", true);") == 0) {
            print $0
            print hellmovie
            print els
            print diabmovie
            next
        }
        print "\t\tif (gbIsHellfire) {"
        print "\t\t\tPspDebugLog(\"DiabloSplash: Hellfire.smk BEGIN\");"
        print "\t\t\tplay_movie(\"gendata\\\\Hellfire.smk\", true);"
        print "\t\t\tPspDebugLog(\"DiabloSplash: Hellfire.smk END\");"
        print "\t\t} else {"
        print "\t\t\tPspDebugLog(\"DiabloSplash: diablo1.smk BEGIN\");"
        print "\t\t\tplay_movie(\"gendata\\\\diablo1.smk\", true);"
        print "\t\t\tPspDebugLog(\"DiabloSplash: diablo1.smk END\");"
        print "\t\t}"
        intro_block++
        next
    }

    if ($0 == "\tif (IsAnyOf(*sgOptions.StartUp.splash, StartUpSplash::TitleDialog, StartUpSplash::LogoAndTitleDialog))") {
        getline titlecall
        sub(/\r$/, "", titlecall)
        if (titlecall != "\t\tUiTitleDialog();")
            exit 52
        print "\tif (IsAnyOf(*sgOptions.StartUp.splash, StartUpSplash::TitleDialog, StartUpSplash::LogoAndTitleDialog)) {"
        print "\t\tPspDebugLog(\"DiabloSplash: UiTitleDialog BEGIN\");"
        print "\t\tUiTitleDialog();"
        print "\t\tPspDebugLog(\"DiabloSplash: UiTitleDialog END\");"
        print "\t}"
        print "\tPspDebugLog(\"DiabloSplash EXIT\");"
        title_block++
        next
    }

    print
}
END {
    if (include_added != 1 || reset_added != 1 || splash_enter != 1 || logo_block != 1 || intro_block != 1 || title_block != 1)
        exit 53
}
' "$DIABLO_CPP" > "$DIABLO_CPP.tmp"
mv "$DIABLO_CPP.tmp" "$DIABLO_CPP"

# movie.cpp: trace each play_movie call and whether the lower-level player starts/returns.
MOVIE_CPP="$ROOT/Source/movie.cpp"
awk '
{
    sub(/\r$/, "", $0)

    if ($0 == "#include \"utils/display.h\"") {
        print
        print "#include \"utils/psp_debug_log.h\""
        include_added++
        next
    }

    if ($0 == "void play_movie(const char *pszMovie, bool userCanClose)") {
        print
        getline n
        sub(/\r$/, "", n)
        print n
        print "\tPspDebugLog(\"play_movie BEGIN file=%s userCanClose=%d loop_movie=%d\", pszMovie, userCanClose ? 1 : 0, loop_movie ? 1 : 0);"
        enter_added++
        next
    }

    if ($0 == "\tif (SVidPlayBegin(pszMovie, loop_movie ? 0x100C0808 : 0x10280808)) {") {
        print "\tconst bool pspSvidStarted = SVidPlayBegin(pszMovie, loop_movie ? 0x100C0808 : 0x10280808);"
        print "\tPspDebugLog(\"play_movie: SVidPlayBegin returned %d file=%s\", pspSvidStarted ? 1 : 0, pszMovie);"
        print "\tif (pspSvidStarted) {"
        begin_added++
        next
    }

    if ($0 == "\tsound_disable_music(false);") {
        print "\tPspDebugLog(\"play_movie: playback loop exited file=%s\", pszMovie);"
        print
        loop_exit++
        next
    }

    if ($0 == "\tInitBackbufferState();") {
        print
        print "\tPspDebugLog(\"play_movie END file=%s\", pszMovie);"
        end_added++
        next
    }

    print
}
END {
    if (include_added != 1 || enter_added != 1 || begin_added != 1 || loop_exit != 1 || end_added != 1)
        exit 54
}
' "$MOVIE_CPP" > "$MOVIE_CPP.tmp"
mv "$MOVIE_CPP.tmp" "$MOVIE_CPP"

# storm_svid.cpp: trace loop flags and frame-end behavior inside the Smacker decoder.
SVID_CPP="$ROOT/Source/storm/storm_svid.cpp"
awk '
{
    sub(/\r$/, "", $0)

    if ($0 == "#include \"utils/log.hpp\"") {
        print
        print "#include \"utils/psp_debug_log.h\""
        include_added++
        next
    }

    if ($0 == "\tif (Smacker_GetCurrentFrameNum(SVidHandle) >= Smacker_GetNumFrames(SVidHandle)) {") {
        print
        print "\t\tPspDebugLog(\"SVidLoadNextFrame: reached end current=%u total=%u loop=%d\", static_cast<unsigned>(Smacker_GetCurrentFrameNum(SVidHandle)), static_cast<unsigned>(Smacker_GetNumFrames(SVidHandle)), SVidLoop ? 1 : 0);"
        frame_end++
        next
    }

    if ($0 == "\t\tSmacker_Rewind(SVidHandle);") {
        print "\t\tPspDebugLog(\"SVidLoadNextFrame: REWIND\");"
        print
        rewind_added++
        next
    }

    if ($0 == "bool SVidPlayBegin(const char *filename, int flags)") {
        print
        getline n
        sub(/\r$/, "", n)
        print n
        print "\tPspDebugLog(\"SVidPlayBegin ENTER file=%s flags=0x%08X\", filename, static_cast<unsigned>(flags));"
        begin_enter++
        next
    }

    if ($0 == "\t// 0x8 // Non-interlaced") {
        print "\tPspDebugLog(\"SVidPlayBegin: SVidLoop=%d\", SVidLoop ? 1 : 0);"
        print
        loop_flag++
        next
    }

    if ($0 == "\tSmacker_GetFrameSize(SVidHandle, SVidWidth, SVidHeight);") {
        print
        print "\tPspDebugLog(\"SVidPlayBegin: size=%ux%u frames=%u\", static_cast<unsigned>(SVidWidth), static_cast<unsigned>(SVidHeight), static_cast<unsigned>(Smacker_GetNumFrames(SVidHandle)));"
        size_added++
        next
    }

    if ($0 == "void SVidPlayEnd()") {
        print
        getline n
        sub(/\r$/, "", n)
        print n
        print "\tPspDebugLog(\"SVidPlayEnd ENTER current=%u total=%u loop=%d\", SVidHandle.isValid ? static_cast<unsigned>(Smacker_GetCurrentFrameNum(SVidHandle)) : 0U, SVidHandle.isValid ? static_cast<unsigned>(Smacker_GetNumFrames(SVidHandle)) : 0U, SVidLoop ? 1 : 0);"
        end_enter++
        next
    }

    print
}
END {
    if (include_added != 1 || frame_end != 1 || rewind_added != 1 || begin_enter != 1 || loop_flag != 1 || size_added != 1 || end_enter != 1)
        exit 55
}
' "$SVID_CPP" > "$SVID_CPP.tmp"
mv "$SVID_CPP.tmp" "$SVID_CPP"

# title.cpp: verify whether control ever reaches and exits the title screen.
TITLE_CPP="$ROOT/Source/DiabloUI/title.cpp"
awk '
{
    sub(/\r$/, "", $0)

    if ($0 == "#include \"utils/language.h\"") {
        print
        print "#include \"utils/psp_debug_log.h\""
        include_added++
        next
    }

    if ($0 == "void UiTitleDialog()") {
        print
        getline n
        sub(/\r$/, "", n)
        print n
        print "\tPspDebugLog(\"UiTitleDialog ENTER\");"
        enter_added++
        next
    }

    if ($0 == "\tTitleFree();") {
        print
        print "\tPspDebugLog(\"UiTitleDialog EXIT\");"
        exit_added++
        next
    }

    print
}
END {
    if (include_added != 1 || enter_added != 1 || exit_added != 1)
        exit 56
}
' "$TITLE_CPP" > "$TITLE_CPP.tmp"
mv "$TITLE_CPP.tmp" "$TITLE_CPP"

# menu.cpp: identify entry to the menu and any attract-mode replay request.
MENU_CPP="$ROOT/Source/menu.cpp"
awk '
{
    sub(/\r$/, "", $0)

    if ($0 == "#include \"utils/language.h\"") {
        print
        print "#include \"utils/psp_debug_log.h\""
        include_added++
        next
    }

    if ($0 == "void PlayIntro()") {
        print
        getline n
        sub(/\r$/, "", n)
        print n
        print "\tPspDebugLog(\"PlayIntro ATTRACT ENTER\");"
        playintro_enter++
        next
    }

    if ($0 == "void mainmenu_loop()") {
        print
        getline n
        sub(/\r$/, "", n)
        print n
        print "\tPspDebugLog(\"mainmenu_loop ENTER\");"
        main_enter++
        next
    }

    if ($0 == "\t\telse if (!UiMainMenuDialog(gszProductName, &menu, 30))") {
        print
        ui_dialog_seen++
        next
    }

    if ($0 == "\t\t\tapp_fatal(_(\"Unable to display mainmenu\"));") {
        print
        print "\t\tPspDebugLog(\"mainmenu_loop: selection=%d\", static_cast<int>(menu));"
        selection_added++
        next
    }

    print
}
END {
    if (include_added != 1 || playintro_enter != 1 || main_enter != 1 || ui_dialog_seen != 1 || selection_added != 1)
        exit 57
}
' "$MENU_CPP" > "$MENU_CPP.tmp"
mv "$MENU_CPP.tmp" "$MENU_CPP"

# Sanity checks: this diagnostic must preserve the actual startup movies.
grep -q 'play_movie("gendata\\\\logo.smk", true);' "$DIABLO_CPP"
grep -q 'play_movie("gendata\\\\diablo1.smk", true);' "$DIABLO_CPP"
grep -q 'UiTitleDialog();' "$DIABLO_CPP"
grep -q 'PspDebugLogReset' "$DIABLO_CPP"
grep -q 'SVidLoadNextFrame: reached end' "$SVID_CPP"
grep -q 'mainmenu_loop ENTER' "$MENU_CPP"

echo "PSP runtime trace instrumentation applied successfully"
