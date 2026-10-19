# Drag-hover: commit cursor-selected window on Alt release

This experiment fixes the Alt-release reliability issue reported after the successful minimized-window restore changes. It is based on `experiment/sws-drag-hover-minimized-restore` (commit `d52660a549a8d9a7b4397b04c6071026b2de1783`) and therefore preserves upstream ExplorerPatcher master 26100.8457.70.4, pinned `ep_taskbar` v1.0.1.0 binaries, the SWS Progman latency fix, the frozen thumbnail grid and repeatable hover previews. Fork master and earlier branches are untouched.

## Root cause

The prior drag-hover `_sws_WindowSwitcher_CompleteDragHover` hid the grid, then called `SetWindowPos(HWND_TOP, SWP_NOACTIVATE)`. That does not guarantee the target becomes the active foreground window. Keyboard Tab and wheel selected the same item using SWS's established `_sws_WindowSwitcher_SwitchToSelectedItemAndDismiss` route, which calls `SwitchToThisWindow(..., TRUE)`, and worked reliably on the user's PC.

The prior Alt-release guard also required `bDragHoverActivated`. During async Win+D restoration a thumbnail could be visibly highlighted via `WM_MOUSEMOVE` yet never set that flag before Alt was released, leaving a stale Alt+Tab selection.

## New behavior

1. On releasing Alt in drag mode, *unless the user explicitly navigated with Tab/wheel*, synchronously resolve the thumbnail under the current cursor from SWS's frozen `rcThumbnail` (then `rcWindow`) hit rectangles, not from a stale hover-poll result.
2. Map that thumbnail to the frozen `HWND` list, set `layout.iIndex`, and request `ShowWindowAsync(SW_RESTORE)` for minimized windows and active popups.
3. Commit selection via the **same** `_sws_WindowSwitcher_SwitchToSelectedItemAndDismiss` function used by keyboard selection, which activates the window and hides the grid. Do not use no-activate Z-order positioning for the final choice.
4. If the cursor is off a thumbnail, fall back to the last hovered window if still valid, then to SWS's normal selection. Deliberate Tab/wheel still uses its existing selection flow.
5. Preserve the original drag; the actual file drop occurs after Alt release, potentially on another monitor. No OLE drop forwarding or mouse pass-through is introduced.

## Test

On Windows 11 with 2+ monitors, select a file on desktop and keep LMB down, Alt+Tab, hover a thumbnail until highlighted; release Alt and verify that exact application's real window is foreground. Repeat with immediately minimized-by-Win+D applications and previously covered/restored ones. Then test A -> B -> A and release Alt; test mouse moved quickly to B immediately before Alt release; test Tab/wheel after hover to ensure intentional keyboard selection overrides mouse. Also verify a normal non-drag Alt+Tab, Windows 10-style taskbar and unchanged thumbnail positions.

Successful CI build confirms compilation, not the Windows drag/foreground behavior. For rollback use the successful prior branch `experiment/sws-drag-hover-minimized-restore` or earlier release-baseline build.
