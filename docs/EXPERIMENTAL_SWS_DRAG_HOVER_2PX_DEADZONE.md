# Drag-hover 2-pixel activation threshold

Based on previous successful Alt-release drag-hover build `71cde54ebdbc1c9f8236096382e29a51a7c66418`, ExplorerPatcher upstream master 26100.8457.70.4, and the previously verified Windows 10-style taskbar DLLs v1.0.1.0.

## Change

When SWS first becomes visible while the left mouse button is already held, it records the cursor's **screen position** and ignores mouse-based thumbnail selection until the pointer's distance from that opening position reaches **at least 2 pixels** (Euclidean distance). This avoids accidentally previewing a thumbnail merely because the switcher appears underneath a stationary dragged file.

The 25 ms drag-hover polling routine and ordinary `WM_MOUSEMOVE` handling use the same per-session cursor threshold, so even a synthetic initial `WM_MOUSEMOVE` won't highlight the tile. Once the threshold is reached, the cursor is permanently armed until the switcher closes; movement can then be as small as desired and normal drag-hover semantics apply.

On Alt release, when the cursor never crossed the threshold, SWS commits the default/keyboard-selected thumbnail rather than the tile currently beneath the cursor. It also checks for a qualifying last-moment movement at release before deciding, so a quick movement immediately before Alt release still selects the hovered thumbnail.

Normal Alt+Tab without a file, mouse-wheel/Tab override, minimized Win+D restoration, Alt-release reliability, frozen thumbnail order, and original monitor positions remain unchanged.

## Test

With the cursor held static above a thumbnail when the switcher appears, confirm no preview or hover highlight, then release Alt and verify standard Alt+Tab selection. Repeat with a one-pixel movement (still no activation), and move two pixels or more (hover preview should activate). Try moving diagonally, fast release immediately after movement, and A-B-A hovering once armed. Verify ordinary non-drag Alt+Tab remains unaffected.

The build is unsigned/experimental. A successful GitHub Actions run proves packaging only, not runtime behavior. Previous successful branch `experiment/sws-drag-hover-commit-on-alt-release` is retained for rollback.
