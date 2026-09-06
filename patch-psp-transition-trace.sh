#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-source}"
INTERFAC_CPP="$ROOT/Source/interfac.cpp"

command -v awk >/dev/null
test -f "$ROOT/Source/utils/psp_debug_log.h"

# Trace the Cathedral -> Tristram transition (WM_DIABPREVLVL) closely enough to
# survive a hard PSP exit. Also log total and largest free memory blocks so an
# allocation peak can be distinguished from a logic/assert crash.
awk '
BEGIN { in_show = 0; in_prev = 0 }
{
    sub(/\r$/, "", $0)

    if ($0 == "#include \"utils/sdl_geometry.h\"") {
        print
        print "#include \"utils/psp_debug_log.h\""
        print "#ifdef PSP"
        print "#include <pspkernel.h>"
        print "#endif"
        include_added++
        next
    }

    if ($0 == "namespace {") {
        print
        if (helper_added == 0) {
            print "#ifdef PSP"
            print "void PspTraceTransition(const char *stage, interface_mode mode)"
            print "{"
            print "\tconst int playerLevel = MyPlayer != nullptr ? static_cast<int>(MyPlayer->plrlevel) : -1;"
            print "\tPspDebugLog(\"TRANS %s mode=%d curr=%d plr=%d type=%d free=%u max=%u\","
            print "\t    stage, static_cast<int>(mode), static_cast<int>(currlevel), playerLevel, static_cast<int>(leveltype),"
            print "\t    static_cast<unsigned>(sceKernelTotalFreeMemSize()), static_cast<unsigned>(sceKernelMaxFreeMemSize()));"
            print "}"
            print "#else"
            print "void PspTraceTransition(const char *, interface_mode) {}"
            print "#endif"
            print ""
            helper_added++
        }
        next
    }

    if ($0 == "void ShowProgress(interface_mode uMsg)") {
        print
        in_show = 1
        show_seen++
        next
    }

    if (in_show && $0 == "{") {
        print
        print "\tPspTraceTransition(\"ShowProgress ENTER\", uMsg);"
        show_enter++
        next
    }

    if (in_show && $0 == "\t\tinterface_msg_pump();") {
        print "\t\tPspTraceTransition(\"before interface_msg_pump\", uMsg);"
        print
        print "\t\tPspTraceTransition(\"after interface_msg_pump\", uMsg);"
        pump++
        next
    }

    if (in_show && $0 == "\t\tClearScreenBuffer();") {
        print "\t\tPspTraceTransition(\"before ClearScreenBuffer\", uMsg);"
        print
        print "\t\tPspTraceTransition(\"after ClearScreenBuffer\", uMsg);"
        clear++
        next
    }

    if (in_show && $0 == "\t\tscrollrt_draw_game_screen();") {
        print "\t\tPspTraceTransition(\"before scrollrt_draw_game_screen\", uMsg);"
        print
        print "\t\tPspTraceTransition(\"after scrollrt_draw_game_screen\", uMsg);"
        scroll++
        next
    }

    if (in_show && $0 == "\t\tBlackPalette();") {
        print "\t\tPspTraceTransition(\"before BlackPalette\", uMsg);"
        print
        print "\t\tPspTraceTransition(\"after BlackPalette\", uMsg);"
        black++
        next
    }

    if (in_show && $0 == "\t\tLoadCutsceneBackground(uMsg);") {
        print "\t\tPspTraceTransition(\"before LoadCutsceneBackground\", uMsg);"
        print
        print "\t\tPspTraceTransition(\"after LoadCutsceneBackground\", uMsg);"
        loadbg++
        next
    }

    if (in_show && $0 == "\t\tDrawCutsceneBackground();") {
        print "\t\tPspTraceTransition(\"before DrawCutsceneBackground\", uMsg);"
        print
        print "\t\tPspTraceTransition(\"after DrawCutsceneBackground\", uMsg);"
        drawbg++
        next
    }

    if (in_show && $0 == "\t\tFreeCutsceneBackground();") {
        print
        print "\t\tPspTraceTransition(\"after FreeCutsceneBackground\", uMsg);"
        freebg++
        next
    }

    if (in_show && $0 == "\t\tPaletteFadeIn(8);") {
        print "\t\tPspTraceTransition(\"before PaletteFadeIn\", uMsg);"
        print
        print "\t\tPspTraceTransition(\"after PaletteFadeIn\", uMsg);"
        fade++
        next
    }

    if (in_show && $0 == "\t\tsound_init();") {
        print "\t\tPspTraceTransition(\"before sound_init\", uMsg);"
        print
        print "\t\tPspTraceTransition(\"after sound_init\", uMsg);"
        sound++
        next
    }

    if (in_show && $0 == "\tcase WM_DIABPREVLVL:") {
        print
        print "\t\tPspTraceTransition(\"PREVLVL case ENTER\", uMsg);"
        in_prev = 1
        prev_enter++
        next
    }

    if (in_prev && $0 == "\t\t\tpfile_save_level();") {
        print "\t\t\tPspTraceTransition(\"before pfile_save_level\", uMsg);"
        print
        print "\t\t\tPspTraceTransition(\"after pfile_save_level\", uMsg);"
        save++
        next
    }

    if (in_prev && $0 == "\t\tFreeGameMem();") {
        print "\t\tPspTraceTransition(\"before FreeGameMem\", uMsg);"
        print
        print "\t\tPspTraceTransition(\"after FreeGameMem\", uMsg);"
        freegame++
        next
    }

    if (in_prev && $0 == "\t\tcurrlevel--;") {
        print
        print "\t\tPspTraceTransition(\"after currlevel--\", uMsg);"
        currdec++
        next
    }

    if (in_prev && $0 == "\t\tleveltype = GetLevelType(currlevel);") {
        print
        print "\t\tPspTraceTransition(\"after leveltype update\", uMsg);"
        typeupdate++
        next
    }

    if (in_prev && $0 == "\t\tLoadGameLevel(false, ENTRY_PREV);") {
        print "\t\tPspTraceTransition(\"before LoadGameLevel ENTRY_PREV\", uMsg);"
        print
        print "\t\tPspTraceTransition(\"after LoadGameLevel ENTRY_PREV\", uMsg);"
        loadlevel++
        next
    }

    if (in_prev && $0 == "\t\tbreak;") {
        print "\t\tPspTraceTransition(\"PREVLVL case EXIT\", uMsg);"
        print
        in_prev = 0
        prev_exit++
        next
    }

    print
}
END {
    if (include_added != 1 || helper_added != 1 || show_seen != 1 || show_enter != 1 || pump != 1 || clear != 1 || scroll != 1 || black != 1 || loadbg != 1 || drawbg != 1 || freebg != 1 || fade != 1 || sound != 1 || prev_enter != 1 || save != 1 || freegame != 1 || currdec != 1 || typeupdate != 1 || loadlevel != 1 || prev_exit != 1)
        exit 81
}
' "$INTERFAC_CPP" > "$INTERFAC_CPP.tmp"
mv "$INTERFAC_CPP.tmp" "$INTERFAC_CPP"

grep -q 'PspTraceTransition("before LoadCutsceneBackground"' "$INTERFAC_CPP"
grep -q 'PspTraceTransition("before LoadGameLevel ENTRY_PREV"' "$INTERFAC_CPP"
grep -q 'sceKernelTotalFreeMemSize' "$INTERFAC_CPP"

echo "PSP Cathedral-to-town transition trace applied successfully"
