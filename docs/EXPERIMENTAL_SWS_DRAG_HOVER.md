# Drag-hover window activation experiment

**Experimental, AI-assisted and not Windows-tested.** Based on the working release-baseline branch `experiment/sws-alt-tab-release-26100.8457.70.3`, which uses official ExplorerPatcher 26100.8457.70.3 plus the verified SWS Progman performance fix and period-matched taskbar DLLs. No changes to master.

The build-time script `scripts/Apply-SwsDragHover.ps1` patches the pinned SWS submodule after the existing Progman fix. It checks every text replacement has a unique source anchor and fails the build otherwise. Only three pinned SWS source files change at build time.

Behavior: if the left mouse button is held when SWS first appears, a transparent-to-mouse layered overlay remains visible. SWS polls cursor position every 25 ms and previews any application whose thumbnail is hovered by switching to/restoring its real window under the overlay. After at least one preview, releasing Alt simply closes SWS without committing a second window switch. Further Tab or mouse-wheel navigation disables hover previews and restores regular Alt+Tab selection. Escape closes the grid. A WH_MOUSE_LL wheel hook is attached only during drag mode and unhooked when SWS hides. The overlay NEVER accepts or consumes the actual file drop. Windows still handles file drops directly onto the real window.

Caveats: a held left button is a proxy for a drag; SWS does not inspect OLE/IDataObject to guarantee it is a file. The real cursor/drop effect depends on the native application behind the transparent overlay. A previewed app may activate and alter Win32 focus; test on Windows 11 build 26200.9711 using Illustrator and Explorer before relying on it. Also test Alt release after hover; multiple hover targets; Tab after hover; wheel after hover; Escape; no-drag normal Alt+Tab; and left-click selection in normal mode. If broken, reinstall the previously confirmed working build from `experiment/sws-alt-tab-release-26100.8457.70.3`.

A successful GitHub Actions build validates compilation only, not the Win32 interaction.
