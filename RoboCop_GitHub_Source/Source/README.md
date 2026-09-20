# RoboCop source v1.0.1

Author: Joe "Gambit" Bradford

## Source map

| File | Purpose |
| --- | --- |
| `Install_RoboCop.bat` | Readable 64-bit PowerShell launcher |
| `Installer/Discovery.ps1` | Steam and executable discovery |
| `Installer/Core.ps1` | Verified staging, backups, installation and rollback |
| `Installer/Compatibility.ps1` | Loads the verified helper for a read-only executable check |
| `Installer/Runtime.ps1` | Official UE4SS experimental selection and verified downloads |
| `Installer/manifest.json` | Payload hashes and diagnostic build provenance |
| `Payload/RoboCopGameplay/Scripts/main.lua` | Identity, name/stats, target GUIDs, timer and failure pause |
| `Source/Native/robocop.c` | File checker, target storage, hook installation and integrity reporting |
| `Source/Native/gameplay.h` | Wage, success and individual death rules |
| `Source/Native/compatibility.h` | Bounds-checked PE reader and unique full-body matcher |
| `Source/Native/profiles.h` | Compiled normalized function profiles |
| `Source/Native/profiles.json` | Reviewable profile data |
| `Source/Native/build_manifest.h` | Release version; replaces the obsolete build lock |
| `Source/Tools/make_profiles.py` | Generate profiles after inspecting native functions |
| `Source/Tools/check_game.py` | Compile and run the same read-only checker offline |
| `Source/Tools/build_release.py` | Assemble verified runtime/assets plus compiled gameplay |
| `Source/Tests/` | Native, Lua, installer, discovery and runtime tests |

## Build the native helper

Use Zig 0.16.0. From the repository root on Windows, run:

```bat
Source\Native\build_native.bat
```

Equivalent command:

```text
zig cc -target x86_64-windows-gnu -shared -O2 -Wall -Wextra Source/Native/robocop.c -o Payload/RoboCopGameplay/robocop_native.dll -lpsapi -luser32
```

The helper exports `robocop_init`, `robocop_refresh`, `robocop_alert` and
`robocop_check_file`. It does not require UE4SS link libraries or an Unreal SDK.
Only the in-game initialization export installs hooks. The installer invokes only
the file-check export, which maps the game executable read-only. It does not run
or modify the game executable. The DLL is pinned once in-game hooks are installed;
a complete game restart is required after replacing it.

## Reassemble the player download

Python 3.11 or later is sufficient for packaging. Put a complete v1.0.1 player ZIP
(or the original RC4 player ZIP with identical cooked assets and runtime) outside
the source checkout, then run:

```text
python Source/Tools/build_release.py --payload-from ../RoboCop_Nexus_v1.0.1.zip --output ../RoboCop_Rebuilt_v1.0.1.zip
```

The builder extracts only the required model, portrait and runtime members. It
verifies their hashes against the manifest, records the locally compiled helper
and Lua hashes, and packages an explicit directory allowlist. It excludes game
executables, saves, private logs, nested ZIPs, debug symbols and build products.
Cooked assets are required inputs; this source package does not recreate their
original Blender/Unreal authoring projects.

## Compatibility and tests

Install developer dependencies with Python:

```text
python -m pip install ziglang==0.16.0 pefile capstone lupa
python Source/Tests/test_compatibility.py --game path/to/PoliceChiefSimulator-Win64-Shipping.exe
python Source/Tests/test_lifecycle.py
python Source/Tests/test_patrol.py
python Source/Tools/check_game.py path/to/PoliceChiefSimulator-Win64-Shipping.exe
```

The C rule tests use the same gameplay callbacks as the shipped helper:

```text
zig cc -O2 -I Source/Native Source/Tests/test_gameplay.c -o gameplay_test.exe
```

Run the resulting `gameplay_test.exe`. On Linux choose a native output name such
as `gameplay_test` instead. These tests use fake officers and mission data, not a
running game. They demonstrate callback behavior; they do not establish that a
future game still invokes the same functions for every death path.

PowerShell tests:

```text
powershell -NoProfile -File Source/Tests/test_discovery.ps1
powershell -NoProfile -File Source/Tests/test_runtime.ps1
powershell -NoProfile -File Source/Tests/test_installer.ps1
powershell -NoProfile -File Source/Tests/test_release.ps1 -GameExe path/to/PoliceChiefSimulator-Win64-Shipping.exe
```

The last test needs a complete assembled player package. It copies the supplied
executable into a temporary game layout and uses the bundled runtime deterministically.
On Windows it exercises the actual native file-check bridge. On Linux it compiles
the same compatibility reader into a native test library. No test starts the game.

`make_profiles.py` has inspected function ranges for the two supplied builds. It
is a developer tool, not a generic automatic acceptance mechanism. For a new
function implementation, inspect its ABI, fields, call paths and displaced
instructions before changing the profiles. Never wildcard structure offsets or
accept multiple matching functions just to make a check pass.

## Verification limits

Local tests ran on Linux with PowerShell 7.4.13, Lua through Lupa, and Zig 0.16.0.
Both actual supplied executables passed the same compatibility reader. Synthetic
cases test relocation, duplicate matches, body mutations and malformed PE data.
The Windows DLL was cross-compiled and its imports/exports inspected. Windows
PowerShell 5.1 loading, live thread suspension, game pause behavior and real
patrol completion were not executed here. The author must perform the final
in-game test before advertising that validation as complete.

The included GitHub workflow can run the synthetic tests on Windows after upload;
it does not contain the copyrighted game executable and cannot run the game.
