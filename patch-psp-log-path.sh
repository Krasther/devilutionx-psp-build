#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-source}"
HEADER="$ROOT/Source/utils/psp_debug_log.h"

test -f "$HEADER"
command -v awk >/dev/null

# The PSP/PPSSPP process working directory is not guaranteed to be the game's
# PSP/GAME directory. Prefer an explicit Memory Stick path, while keeping the
# old relative path as a fallback for unusual environments.
awk '
{
    sub(/\r$/, "", $0)

    if ($0 == "\tstd::FILE *file = std::fopen(\"devilutionx.log\", \"a\");") {
        print "\tstd::FILE *file = std::fopen(\"ms0:/PSP/GAME/DevilutionX/devilutionx.log\", \"a\");"
        print "\tif (file == nullptr)"
        print "\t\tfile = std::fopen(\"devilutionx.log\", \"a\");"
        append_path++
        next
    }

    if ($0 == "\tstd::FILE *file = std::fopen(\"devilutionx.log\", \"w\");") {
        print "\tstd::FILE *file = std::fopen(\"ms0:/PSP/GAME/DevilutionX/devilutionx.log\", \"w\");"
        print "\tif (file == nullptr)"
        print "\t\tfile = std::fopen(\"devilutionx.log\", \"w\");"
        reset_path++
        next
    }

    print
}
END {
    if (append_path != 1 || reset_path != 1)
        exit 61
}
' "$HEADER" > "$HEADER.tmp"
mv "$HEADER.tmp" "$HEADER"

grep -q 'ms0:/PSP/GAME/DevilutionX/devilutionx.log' "$HEADER"
echo "PSP runtime trace path fixed to explicit Memory Stick location"
