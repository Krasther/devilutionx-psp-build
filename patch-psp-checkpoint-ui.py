#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "source")
interfac = root / "Source/interfac.cpp"
diablo = root / "Source/diablo.cpp"

# -----------------------------------------------------------------------------
# Persist the latest Cathedral -> Tristram checkpoint in a tiny file. The normal
# runtime log remains available, but this breadcrumb is designed for testing
# entirely on a real PSP: if the process dies, the next launch can show the last
# completed checkpoint directly in DevilutionX's own UI.
# -----------------------------------------------------------------------------
text = interfac.read_text(encoding="utf-8")
old_helper = '''#ifdef PSP
void PspTraceTransition(const char *stage, interface_mode mode)
{
\tconst int playerLevel = MyPlayer != nullptr ? static_cast<int>(MyPlayer->plrlevel) : -1;
\tPspDebugLog("TRANS %s mode=%d curr=%d plr=%d type=%d free=%u max=%u",
\t    stage, static_cast<int>(mode), static_cast<int>(currlevel), playerLevel, static_cast<int>(leveltype),
\t    static_cast<unsigned>(sceKernelTotalFreeMemSize()), static_cast<unsigned>(sceKernelMaxFreeMemSize()));
}
#else
void PspTraceTransition(const char *, interface_mode) {}
#endif
'''
new_helper = '''#ifdef PSP
constexpr const char *PspTransitionCheckpointPath = "ms0:/PSP/GAME/DevilutionX/transition.chk";

void PspTraceTransition(const char *stage, interface_mode mode)
{
\tconst int playerLevel = MyPlayer != nullptr ? static_cast<int>(MyPlayer->plrlevel) : -1;
\tconst unsigned freeMemory = static_cast<unsigned>(sceKernelTotalFreeMemSize());
\tconst unsigned maxBlock = static_cast<unsigned>(sceKernelMaxFreeMemSize());
\tPspDebugLog("TRANS %s mode=%d curr=%d plr=%d type=%d free=%u max=%u",
\t    stage, static_cast<int>(mode), static_cast<int>(currlevel), playerLevel, static_cast<int>(leveltype), freeMemory, maxBlock);

\tif (mode != WM_DIABPREVLVL)
\t\treturn;

\tstd::FILE *file = std::fopen(PspTransitionCheckpointPath, "w");
\tif (file == nullptr)
\t\tfile = std::fopen("transition.chk", "w");
\tif (file == nullptr)
\t\treturn;

\tstd::fprintf(file, "Etapa: %s\\nNivel: curr=%d player=%d type=%d\\nLivre: %u KB\\nMaior bloco: %u KB\\n",
\t    stage, static_cast<int>(currlevel), playerLevel, static_cast<int>(leveltype), freeMemory / 1024U, maxBlock / 1024U);
\tstd::fflush(file);
\tstd::fclose(file);
}

void PspClearTransitionCheckpoint(interface_mode mode)
{
\tif (mode != WM_DIABPREVLVL)
\t\treturn;
\tstd::remove(PspTransitionCheckpointPath);
\tstd::remove("transition.chk");
}
#else
void PspTraceTransition(const char *, interface_mode) {}
void PspClearTransitionCheckpoint(interface_mode) {}
#endif
'''
if text.count(old_helper) != 1:
    raise SystemExit("Could not locate generated PspTraceTransition helper")
text = text.replace(old_helper, new_helper, 1)

replacements = [
    (
        '''\tif (!HeadlessMode) {\n\t\tassert(ghMainWnd);\n\n\t\tif (RenderDirectlyToOutputSurface && PalSurface != nullptr) {''',
        '''\tPspTraceTransition("after level case switch", uMsg);\n\tif (!HeadlessMode) {\n\t\tassert(ghMainWnd);\n\n\t\tPspTraceTransition("before final progress render", uMsg);\n\t\tif (RenderDirectlyToOutputSurface && PalSurface != nullptr) {'''
    ),
    (
        '''\t\tPaletteFadeOut(8);''',
        '''\t\tPspTraceTransition("before PaletteFadeOut", uMsg);\n\t\tPaletteFadeOut(8);\n\t\tPspTraceTransition("after PaletteFadeOut", uMsg);'''
    ),
    (
        '''\tpreviousHandler = SetEventHandler(previousHandler);''',
        '''\tPspTraceTransition("before restore event handler", uMsg);\n\tpreviousHandler = SetEventHandler(previousHandler);\n\tPspTraceTransition("after restore event handler", uMsg);'''
    ),
    (
        '''\tIsProgress = false;''',
        '''\tIsProgress = false;\n\tPspTraceTransition("after IsProgress false", uMsg);'''
    ),
    (
        '''\tNetSendCmdLocParam2(true, CMD_PLAYER_JOINLEVEL, myPlayer.position.tile, myPlayer.plrlevel, myPlayer.plrIsOnSetLevel ? 1 : 0);''',
        '''\tPspTraceTransition("before PLAYER_JOINLEVEL", uMsg);\n\tNetSendCmdLocParam2(true, CMD_PLAYER_JOINLEVEL, myPlayer.position.tile, myPlayer.plrlevel, myPlayer.plrIsOnSetLevel ? 1 : 0);\n\tPspTraceTransition("after PLAYER_JOINLEVEL", uMsg);'''
    ),
    (
        '''\tplrmsg_delay(false);''',
        '''\tplrmsg_delay(false);\n\tPspTraceTransition("after plrmsg_delay false", uMsg);'''
    ),
    (
        '''\tgbSomebodyWonGameKludge = false;\n}\n\n} // namespace devilution''',
        '''\tgbSomebodyWonGameKludge = false;\n\tPspTraceTransition("ShowProgress COMPLETE", uMsg);\n\tPspClearTransitionCheckpoint(uMsg);\n}\n\n} // namespace devilution'''
    ),
]
for old, new in replacements:
    if text.count(old) != 1:
        raise SystemExit(f"Expected exactly one interfac.cpp marker, got {text.count(old)}: {old[:60]!r}")
    text = text.replace(old, new, 1)
interfac.write_text(text, encoding="utf-8")

# -----------------------------------------------------------------------------
# On the next launch, after DiabloInit() has initialized the UI, show the saved
# breadcrumb using DevilutionX's own OK dialog. This avoids needing a PC, USB
# connection, or text-file viewer on the PSP. Reading the breadcrumb deletes it;
# a new transition will create a fresh one if it crashes again.
# -----------------------------------------------------------------------------
text = diablo.read_text(encoding="utf-8")
include_marker = '#include "DiabloUI/diabloui.h"\n'
if text.count(include_marker) != 1:
    raise SystemExit("Could not locate diabloui include")
text = text.replace(include_marker, include_marker + '#include "DiabloUI/dialogs.h"\n', 1)

func_marker = 'void DiabloInit()\n{\n'
if text.count(func_marker) != 1:
    raise SystemExit("Could not locate DiabloInit")
show_func = r'''#ifdef PSP
void PspShowPreviousTransitionCheckpoint()
{
	constexpr const char *AbsolutePath = "ms0:/PSP/GAME/DevilutionX/transition.chk";
	std::FILE *file = std::fopen(AbsolutePath, "r");
	if (file == nullptr)
		file = std::fopen("transition.chk", "r");
	if (file == nullptr)
		return;

	char message[512] = {};
	const size_t bytesRead = std::fread(message, 1, sizeof(message) - 1, file);
	message[bytesRead] = '\0';
	std::fclose(file);

	std::remove(AbsolutePath);
	std::remove("transition.chk");

	if (bytesRead == 0)
		return;

	std::vector<std::unique_ptr<UiItemBase>> emptyBackground;
	UiErrorOkDialog("PSP CRASH TRACE", message, emptyBackground);
}
#else
void PspShowPreviousTransitionCheckpoint() {}
#endif

'''
text = text.replace(func_marker, show_func + func_marker, 1)

call_marker = '\tDiabloInit();\n'
if text.count(call_marker) != 1:
    raise SystemExit(f"Expected one DiabloInit call, got {text.count(call_marker)}")
text = text.replace(call_marker, call_marker + '\tPspShowPreviousTransitionCheckpoint();\n', 1)
diablo.write_text(text, encoding="utf-8")

print("PSP on-device crash checkpoint display patch applied successfully")
