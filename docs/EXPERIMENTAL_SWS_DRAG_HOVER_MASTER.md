# Drag-hover previews on the latest upstream ExplorerPatcher master

**AI-assisted experiment; compiled in CI but runtime behavior untested until a user tests it.**

## Baseline

This branch starts at upstream `valinet/ExplorerPatcher` master commit `0a88a6e0ef6b1752fea36e581cffff1097e862b0` (version 26100.8457.70.4), which is ten commits newer than official release 26100.8457.70.3. The pinned SWS submodule is unchanged at `083fa3b1449729e4ebae8d913558082400b359a8`.

The build applies the previously confirmed Progman SWS Alt+Tab latency fix, then drag-hover changes, to the pinned submodule at build time. Normal Alt+Tab remains unchanged whenever the left mouse button was not already held on opening. All original drag-hover features (mouse-pass-through grid, 25 ms hover polling, frozen thumbnail layout, repeatable slot hover, Alt release that does not select again, Tab/wheel override) are preserved.

## New focus-safe preview modification

A dragged object may leave keyboard focus/mouse capture with its OLE source. The previous implementation called `SwitchToThisWindow` when hovering each thumbnail. Windows can reject cross-process foreground activation, producing a flashing taskbar button rather than presenting the window.

Now previewing a thumbnail uses `ShowWindowAsync(SW_SHOWNOACTIVATE)` only for minimized windows and `SetWindowPos(HWND_TOP, SWP_NOACTIVATE | SWP_ASYNCWINDOWPOS | SWP_NOMOVE | SWP_NOSIZE)` to raise that window (or last active popup) **without stealing foreground focus**. SWS remains visually on top. The drag-hover index is recorded only if reordering was successfully queued.

A red crossed-circle cursor can still legitimately appear if the underlying target or area doesn't support the dragged file, or if the application's drag-drop route cannot be reached; no OLE drop-target proxy or fake drop-effect is introduced.

## Taskbar version isolation

This latest-source experiment **continues to pin** the known-good taskbar binaries from `ExplorerPatcher/ep_taskbar_releases` tag `v1.0.1.0` (June 10, 2026), rather than using the later `v1.0.3.0`. In the earlier user test, the main/master experimental build with v1.0.3.0 did not load the Windows 10 taskbar, while the official-release-source build with v1.0.1.0 did; neither source nor DLL version has yet been isolated as the cause. Holding the DLL version fixed lets us test the source update cleanly.

## Test plan and rollback

Download the GitHub Actions successful push-run artifact, then run `x64/ep_setup.exe` on a restorable Windows machine. Test: drag from desktop -> Win+D/Alt+Tab -> hover A, then B, then A, then B, avoiding actual mouse release until the final drop; verify no thumbnail shuffle, no taskbar button flashing, and whether the application is displayed beneath the grid. Release Alt after hovering A to verify no extra selection. Test a file drop into Illustrator and Explorer to assess native drop effect and any red-circle cursor. Test ordinary no-drag Alt+Tab and mouse-wheel override separately.

If anything regresses, reinstall the confirmed working [release-based branch](https://github.com/U-Type/ExplorerPatcher/tree/experiment/sws-alt-tab-release-26100.8457.70.3); previous experimental branches and master are unchanged. The experimental installer is unsigned and not an official distribution.
