RoboCop for Police Chief Simulator - Installer 1.0.0-RC4
Author: Joe "Gambit" Bradford

INSTALL
1. Close Police Chief Simulator completely.
2. Extract this ZIP into a fresh folder. A OneDrive Desktop is supported.
3. Double-click Install_RoboCop.bat and wait for SUCCESS.
4. Launch the game normally.

A single detected Steam installation installs automatically. If none or multiple
are found, select PoliceChiefSimulator.exe from the game folder, or the shipping
executable inside PoliceChiefSimulator/Binaries/Win64. No typed path, hotkey,
Unreal Editor, Python, or manual mods.txt edit is needed.

EXACT DESTINATIONS
Relative to the game's PoliceChiefSimulator subfolder:
  Content/Paks/~mods/                         Six model and portrait files
  Binaries/Win64/ue4ss/Mods/RoboCopGameplay/   Gameplay scripts and native helper
  Binaries/Win64/ue4ss/UE4SS.dll              Experimental UE4SS runtime
  Binaries/Win64/dwmapi.dll                   UE4SS loader

The installer creates missing destination folders. It does not replace ~mods
or the entire UE4SS Mods folder. Other mods and game Paks are preserved.

UE4SS INSTALLATION AND UPDATES
RC4 bundles the official basic experimental build 3.0.1-1136-g35d1795d, checked
against upstream release metadata on September 20, 2026. It also checks the
UE4SS-RE/RE-UE4SS experimental release on GitHub each time it runs. It selects
the newest basic experimental ZIP by publication date, excluding developer builds.

If upstream has a newer archive, the installer downloads it from the official
release, verifies its size and published SHA-256, and extracts only the runtime,
loader, default settings and license. Optional upstream example/cheat mods are
not installed. An unexpected address, missing digest or corrupt download stops
before modifying the game.

The installed UE4SS.dll and dwmapi.dll are compared by content hash. Matching
files are retained; older, missing or different files are backed up and replaced.
An existing UE4SS-settings.ini and other mods are retained. Missing settings
receive the official defaults. A partial runtime installation is repaired.

If the upstream check cannot be reached, the installer explicitly reports that
it is using the bundled experimental build and cannot confirm the online latest.
It does not claim that an offline version check succeeded.

Legacy flat installations are migrated to Win64/ue4ss. Nonconflicting legacy
mods and configuration files are copied into that folder. The old Win64/UE4SS.dll
is backed up and removed, leaving one active runtime. Original legacy Mods and
settings stay in place as inactive copies. Nested copies take priority if both
locations contain a file. Conflicting load lists, explicit RoboCop disable entries,
or custom mod-location overrides stop with a specific explanation before changes.

ONEDRIVE FIX
RC3 incorrectly rejected the OneDrive Desktop's reparse-point attribute while
checking read-only package files. RC4 verifies their contents and copies those
contents into ordinary temporary files. It does not reject the package's parent
folder or copy its cloud/link attributes into the installed mod. A cloud file
must be readable; Windows may hydrate it from OneDrive when the installer reads it.
Checks against redirected installation destinations remain in place.

BACKUPS AND FAILURES
Replaced files are backed up in:
  PoliceChiefSimulator/RoboCop_Installer_Backups/<timestamp>/
receipt.json identifies each original and destination. ue4ss-runtime.json records
the selected runtime version, source archive, hash and online-check status.
An interrupted copy reported as an error triggers automatic restoration, including
previous runtime and loader files. Keep the backup if power loss or forced process
termination interrupts installation. Save files and the original game executable
are never modified. Back up saves separately before testing mods.

The installer backs up and removes duplicate copies of the same six RoboCop asset
filenames found under Content/Paks. Differently named conflicting mods cannot be
detected automatically. Installer and detection log paths are printed on failure.

GAMEPLAY INCLUDED
- RoboCop's 6 ft 4 in model and materials.
- The selected RoboCop portrait asset used by hiring, profiles and the board.
- Alex Murphy name and maximum stats for the matching worker.
- $100 daily wage while the gameplay mod is running.
- 1,000% patrol success for a party containing Murphy.
- Native death protection for Murphy, not every accompanying officer.
- Approximately 30 seconds of unpaused gameplay before requesting normal patrol
  resolution; native departure and return travel prerequisites still apply.

The matching worker must enter the hiring pool. First-batch appearance in a new
game is not guaranteed. The portrait replaces Worker_02_M's shared asset.
No dispatch music, AutoFax or AutoDoors is included. Gameplay remains v0.4.3;
this revision changes installation and the bundled UE4SS runtime.

COMPATIBILITY
The native helper is specific to the supported game SHA-256 in manifest.json.
Different game builds are rejected before installation. Its native hook guards
also check the executable's timestamp, image size and function bytes at runtime.
Do not use Restart All Mods or hot reload with its pinned native helper; restart
the full game after installing or changing RoboCop. Updating UE4SS preserves
other mod files but cannot guarantee every third-party mod's compatibility with
future experimental releases.

UNINSTALL
Close the game. Remove ue4ss/Mods/RoboCopGameplay and only the six RoboCop files
listed in Payload/Paks from Content/Paks/~mods. Keep UE4SS if other mods use it.
Use receipt.json and its original-file backups to revert an installer update.
Do not remove the normal PoliceChiefSimulator-Windows game containers.
Removing RoboCop does not undo name/stat changes already saved in a savegame.

SOURCE AND VALIDATION
Readable BAT, PowerShell, Lua and native C source is included. Code comments are
limited to the mod title and author. Third-party settings retain upstream text.
The separate source ZIP is ready to publish to GitHub; no repository is published
by this installer. See Source/README.md for build and source-publication details.

16 installation scenarios passed under PowerShell 7.4.13 on Linux, covering fresh
installations, matching/older/partial runtimes, legacy migration, loader repair,
linked package sources, other-mod/settings/load-list preservation, repeat installs,
corrupt payload rejection, supported game checks, duplicate Paks and rollback.
Discovery and runtime-updater tests also passed. Live upstream metadata, download,
archive digest and extracted binary hash were checked. Full release assets passed
fresh install, reinstall and outdated-runtime upgrade checks in isolated fixtures.
The fixture tests do not execute the game. Windows PowerShell 5.1, OneDrive cloud
hydration, the picker and double-click/game-launch behavior remain unverified here.
The source ZIP includes a Windows 5.1/7 CI workflow; it has not been run here.
