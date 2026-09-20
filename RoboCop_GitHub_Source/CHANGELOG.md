# RoboCop changelog

## 1.0.1 — September 20, 2026

- Repairs native perk compatibility with the hotfix executable supplied by the author.
- Replaces the single-build lock with unique, full-body native function matching.
- Verifies the death, wage, success and completion functions before installing hooks.
- Checks the same function profiles in the installer and at game startup.
- Initializes hooks before the periodic worker scan, preserves target GUIDs on upgrade, and refreshes identity after map loads.
- Retains specific failure messages and periodically checks installed hook integrity.
- Requests a game pause and shows a native compatibility warning if protection fails.
- Preserves Alex Murphy's name, maximum starting stats, $100 daily wage, 1,000% patrol success, individual death protection and 30-second patrol timer.
- Includes the existing model, materials and portraits in the complete player package.
- Preserves automatic Steam discovery, UE4SS setup, backups and installation rollback.

Both supplied executables and the automated regression tests pass local checks.
Windows in-game validation is pending the author's final patrol test. Compatibility
with arbitrary future game updates is not guaranteed.
