# SWS Alt+Tab fix against official release 26100.8457.70.3

**AI-assisted experimental build, not an official ExplorerPatcher release.** Do not assume code signing or compatibility. Keep the official release installer to roll back.

## Baseline and diff

The parent commit is `db5ec1c83674ca1a691811be4117289426913440`, corresponding to [official ExplorerPatcher 26100.8457.70.3](https://github.com/valinet/ExplorerPatcher/releases/tag/26100.8457.70.3) (June 20, 2026), rather than the later development master used for the first experimental build. It retains the original `libs/sws` submodule at `083fa3b1449729e4ebae8d913558082400b359a8`.

The only C source change is the same `sws_WindowSwitcher.c` Progman/WorkerW desktop validation patch that removed the user's experienced 300–500 ms Alt+Tab delay in the first experiment. It is stored in `patches/sws_progman_validation.patch`, and `scripts/Apply-SwsProgmanFix.ps1` applies it during GitHub Actions (not as a submodule commit). The patch script checks the source hunk and fails closed if it does not match.

For better comparison with the official June 20 installer, the `Download ep_taskbar` workflow step selects [taskbar release v1.0.1.0](https://github.com/ExplorerPatcher/ep_taskbar_releases/releases/tag/v1.0.1.0) from June 10, 2026. The earlier experimental build had selected the latest, v1.0.3.0 from August 15, 2026. This is a *second controlled input difference* (taskbar dependency version), not a claim that it caused the problem. Other toolchain downloads are still the standard workflow inputs and can change over time.

## Build

The push to branch `experiment/sws-alt-tab-release-26100.8457.70.3` runs the fork's GitHub Actions **Build** workflow automatically. Download a successful **push** run's `ep_bin_multi_...` artifact from https://github.com/U-Type/ExplorerPatcher/actions. The x64 installer is `x64/ep_setup.exe` in the ZIP. For manual workflow dispatch set BOTH the branch selector and `ref` text field to `experiment/sws-alt-tab-release-26100.8457.70.3`, with configuration `Release`.

## Test and rollback

Test the Windows 10 (ExplorerPatcher) taskbar and whether `ep_taskbar.ge.dll` is loaded by explorer.exe on Windows 11 26200.9711. Also check that Alt+Tab remains fast with Simple Window Switcher show delay 0 ms. Preserve a known-good installer and restorable system. Reinstall the [official 26100.8457.70.3](https://github.com/valinet/ExplorerPatcher/releases/tag/26100.8457.70.3) installer if either feature regresses.
