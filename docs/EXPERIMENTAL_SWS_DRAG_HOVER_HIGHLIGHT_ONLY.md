# Simple Window Switcher: highlight-only file drag mode

This test branch builds on `experiment/sws-drag-hover-two-pixel-deadzone` (`4159a1c6ed4c6aff7d7b46edea015248b69a8e36`) and retains upstream ExplorerPatcher 26100.8457.70.4, the proven SWS Progman latency fix, frozen thumbnail order and known-good ep_taskbar v1.0.1.0 binaries.

While dragging a file, Alt+Tab keeps SWS on top but does not bring applications forward or restore minimized windows. After the pre-existing 2-pixel mouse movement threshold, a 25 ms timer polls `GetCursorPos` to update only the hovered thumbnail's visual highlight and selected index. It works independently of `WM_MOUSEMOVE`, which is ignored during an active drag because Windows' OLE drag source may intercept or delay it. The same frozen thumbnail rectangles are used to resolve the selection at Alt release. No file drop is accepted on the overlay; the mouse button remains held until the user drops into the activated application.

Releasing Alt calls the same normal SWS switching function used by Tab/wheel, including restoring a minimized target if necessary. Tab/wheel deliberately navigate using the existing SWS selection path. Ordinary non-drag Alt+Tab remains unchanged.

The red crossed-circle cursor can still legitimately appear while the dragged file is over SWS; it simply means SWS does not accept that file drop. It should not affect polling-based thumbnail highlighting. This does not simulate or forward drops.

Test: drag file, show switcher with stationary cursor (no hover), move 2+ pixels and hover A/B/A, verify only the frame changes (no application emerges), then release Alt over A and verify A becomes foreground (including Win+D-minimized windows). Also test across monitors, rapid movement just before Alt release, Tab/wheel, and ordinary Alt+Tab. CI compilation does not verify real Windows drag routing.
