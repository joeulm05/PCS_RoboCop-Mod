RoboCop for Police Chief Simulator — v1.0.1
Author: Joe "Gambit" Bradford

INSTALL OR UPDATE
1. Close Police Chief Simulator completely.
2. Extract the entire ZIP to a normal folder.
3. Double-click Install_RoboCop.bat and wait for SUCCESS.
4. Launch the game normally.

The installer finds Steam installations automatically. It asks for the game
executable only when there is no unique match. It installs the required UE4SS
experimental runtime and loader when needed, then the RoboCop model, portrait,
and gameplay files. Existing settings and other mods are preserved. Changed files
are backed up. You do not need hotkeys or edits to mods.txt.

FEATURES
Alex Murphy, maximum starting stats, $100 daily wages, the RoboCop model and
portraits, 1,000% patrol success, patrol death protection for Alex, and a
30-second patrol timer while gameplay is running. Pausing the game pauses that
timer. Other officers retain their normal individual death rules.

HOTFIX REPAIR
The previous helper disabled itself when the executable build identity changed.
This version checks the actual gameplay function bodies instead. It accepts the
previous executable and the author's September 20 hotfix executable. It also
recognizes matching functions when their locations or address references move.
A change to those functions still requires a compatibility update.

If protection cannot be verified after a future update, the mod requests a game
pause and displays a native warning when its helper can load. Do not resume patrols
with Alex in that state. The exact error is in:
PoliceChiefSimulator/Binaries/Win64/ue4ss/Mods/RoboCopGameplay/native_status.txt
The pause request is not a guarantee if UE4SS or the game's pause API also breaks.

VALIDATION
Both supplied game binaries pass native compatibility checks. Automated native
perk, Lua timer/lifecycle and installer tests passed. This package has not been
run inside Police Chief Simulator here. Before publishing it, confirm one patrol
on the hotfix build, a save/reload, and Alex's hiring/profile screens.

INSTALL LOCATIONS
PoliceChiefSimulator/Content/Paks/~mods/
PoliceChiefSimulator/Binaries/Win64/ue4ss/Mods/RoboCopGameplay/
PoliceChiefSimulator/Binaries/Win64/ue4ss/UE4SS.dll
PoliceChiefSimulator/Binaries/Win64/dwmapi.dll

No music is included. No game executable or save is included or modified.
