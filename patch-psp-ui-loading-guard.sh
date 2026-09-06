#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-source}"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])

# Expose the existing interfac.cpp loading-state flag through a tiny public
# accessor. This lets the final PSP presentation path avoid drawing native HUD
# labels over cutscene/loading screens while keeping those labels during normal
# gameplay.
header = root / "Source/interfac.h"
text = header.read_text()
needle = "void CompleteProgress();\nvoid ShowProgress(interface_mode uMsg);"
replacement = "void CompleteProgress();\nbool IsProgressScreenActive();\nvoid ShowProgress(interface_mode uMsg);"
if text.count(needle) != 1:
    raise SystemExit("interfac.h marker mismatch")
header.write_text(text.replace(needle, replacement, 1))

cpp = root / "Source/interfac.cpp"
text = cpp.read_text()
needle = "void RegisterCustomEvents()\n{"
replacement = "bool IsProgressScreenActive()\n{\n\treturn IsProgress;\n}\n\nvoid RegisterCustomEvents()\n{"
if text.count(needle) != 1:
    raise SystemExit("interfac.cpp marker mismatch")
cpp.write_text(text.replace(needle, replacement, 1))

dx = root / "Source/engine/dx.cpp"
text = dx.read_text()
include_marker = '#include "engine/dx.h"\n'
if text.count(include_marker) != 1:
    raise SystemExit("dx include marker mismatch")
if '#include "interfac.h"' not in text:
    text = text.replace(include_marker, include_marker + '#ifdef PSP\n#include "interfac.h"\n#endif\n', 1)

old = "if (!pBtmBuff.has_value() || movie_playing || surface == nullptr || surface->format->BytesPerPixel != 2)"
new = "if (!pBtmBuff.has_value() || movie_playing || IsProgressScreenActive() || surface == nullptr || surface->format->BytesPerPixel != 2)"
if text.count(old) != 1:
    raise SystemExit("native label guard marker mismatch")
text = text.replace(old, new, 1)
dx.write_text(text)
PY

grep -q 'bool IsProgressScreenActive();' "$ROOT/Source/interfac.h"
grep -q 'return IsProgress;' "$ROOT/Source/interfac.cpp"
grep -q 'movie_playing || IsProgressScreenActive()' "$ROOT/Source/engine/dx.cpp"

echo "PSP native HUD labels are now suppressed during level loading"
