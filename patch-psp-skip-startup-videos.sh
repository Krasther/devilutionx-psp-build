#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-source}"
command -v awk >/dev/null

# Diagnostic only: bypass startup movies on PSP so we can validate the title/menu,
# character creation and gameplay independently from the Smacker video path.
DIABLO_CPP="$ROOT/Source/diablo.cpp"
awk '
BEGIN { pending = 0 }
{
    sub(/\r$/, "", $0)
    print

    if ($0 == "void DiabloSplash()") {
        pending = 1
        next
    }

    if (pending == 1 && $0 == "{") {
        print "#ifdef PSP"
        print "\t// PSP diagnostic: skip startup movies while validating UI/gameplay."
        print "\treturn;"
        print "#endif"
        patched++
        pending = 0
    }
}
END { if (patched != 1) exit 51 }
' "$DIABLO_CPP" > "$DIABLO_CPP.tmp"
mv "$DIABLO_CPP.tmp" "$DIABLO_CPP"

# The main menu normally enters attract mode after 30 seconds and replays the
# Diablo intro. Make PlayIntro a no-op on PSP during this diagnostic build too.
MENU_CPP="$ROOT/Source/menu.cpp"
awk '
BEGIN { pending = 0 }
{
    sub(/\r$/, "", $0)
    print

    if ($0 == "void PlayIntro()") {
        pending = 1
        next
    }

    if (pending == 1 && $0 == "{") {
        print "#ifdef PSP"
        print "\t// PSP diagnostic: disable attract-mode movie replay."
        print "\treturn;"
        print "#endif"
        patched++
        pending = 0
    }
}
END { if (patched != 1) exit 52 }
' "$MENU_CPP" > "$MENU_CPP.tmp"
mv "$MENU_CPP.tmp" "$MENU_CPP"

grep -q 'PSP diagnostic: skip startup movies' "$DIABLO_CPP"
grep -q 'PSP diagnostic: disable attract-mode movie replay' "$MENU_CPP"

echo "PSP startup/attract movies disabled for diagnostic build"
