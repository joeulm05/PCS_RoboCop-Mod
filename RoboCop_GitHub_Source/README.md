# RoboCop for Police Chief Simulator — v1.0.1

Author: Joe "Gambit" Bradford

This release repairs the native perks after the September 20 game hotfix. It
includes Alex Murphy's $100 daily wage, maximum starting stats, 1,000% patrol
success, individual patrol death protection, and a 30-second gameplay timer.
The existing model, materials and hiring/assignment portraits are unchanged.

For players: extract the **full player ZIP**, close the game, and run
`Install_RoboCop.bat`. The source ZIP requires the player payload before it can
install anything. See `README.txt` for installation and compatibility details.

## What changed

The old helper checked one PE timestamp and image size, and the old installer
checked one executable SHA-256. An unrelated game rebuild disabled all native
perks, and the Lua timer was also gated on that failure.

The helper and installer now use the same C compatibility reader. It locates
function entries through the PE exception directory and verifies full normalized
function bodies, executable sections, chained function-segment boundaries, and
unique matches. It masks RIP-relative address displacements and direct-call
relocation operands, while retaining instruction bytes, field offsets and internal
branch structure. No fixed game RVA or whole-game hash decides compatibility.

The death, wage, success-parameter and completion functions match in both supplied
executables. The displaced trampoline instructions are checked during profile
generation. Thread suspension protects code installation; no function bytes are
written if preparation fails. A changed or ambiguous function is rejected.

Native hooks initialize when the script loads. Existing target GUIDs are retained
during upgrades, and identity refresh also runs after a map load to reduce the
unprotected interval for a saved patrol. Lua checks native hook integrity
periodically and preserves the specific failure
message. A native failure or worker update exception requests a game pause; a
native message box explains the protection failure when the DLL can load. The mod
does not promise an unconditional dispatch block if UE4SS, Lua, or the pause API
itself stops working. No mod can guarantee compatibility with arbitrary updates.

## Code and build

See [Source/README.md](Source/README.md) for the complete code map, native build,
profile generation and verification commands. The C, Lua, PowerShell, batch,
packaging and test source is included. Executable game files, saves, player logs,
credentials, cooked model/portrait assets and third-party runtime binaries are
excluded from the source download.

`Installer/manifest.json` records exact distributed payload hashes and the two
inspected game hashes for provenance. Those game hashes are diagnostic records,
not installation restrictions. `Source/Validation.json` records test results and
limits; Windows in-game execution remains to be confirmed by the author.

The installer checks the official UE4SS experimental release endpoint. If a newer
runtime is available, it verifies the official archive digest before installing
it. An unavailable endpoint produces an explicit bundled-runtime fallback. This
is not a RoboCop self-updater; updating this mod requires a new download.

## GitHub and Nexus

Follow `GitHub_Update_Instructions.txt` to replace the source in the existing
repository and upload the player ZIP as a new version on the existing Nexus page.
Publishing source does not exempt new Nexus files from security checks.

UE4SS upstream source and MIT license:
https://github.com/UE4SS-RE/RE-UE4SS

The pinned bundled UE4SS revision and download URL are in the manifest. Existing
settings and other mods are preserved. Neither third-party artwork nor the
RoboCop name/likeness is licensed by this source publication. No music is bundled.
