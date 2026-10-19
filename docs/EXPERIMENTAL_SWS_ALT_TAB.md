# Experimental Simple Window Switcher Alt+Tab latency fix

> **AI-assisted experiment — not an official fix.** This branch attempts to address delayed Alt+Tab activation and a desktop repaint on Windows 11, especially 24H2 and later. Source inspection supports the hypothesis, but the fix has **not been compiled or benchmarked on a Windows PC** by the assistant. It **may not work** and might introduce regressions. Keep a known-good ExplorerPatcher installer.

## What changed

ExplorerPatcher includes the original [valinet/sws](https://github.com/valinet/sws) as a pinned Git submodule at `libs/sws`. Editing a nominal path beneath that submodule in the parent repo would **not** change the compiled source.

This fork stores a code diff at [patches/sws_progman_validation.patch](../patches/sws_progman_validation.patch) and an idempotence-checking *build-time* application script at [scripts/Apply-SwsProgmanFix.ps1](../scripts/Apply-SwsProgmanFix.ps1). Its [GitHub Actions build](../.github/workflows/build.yml) applies the patch after checkout and before compilation, and fails if it cannot apply. The upstream submodule pointer remains unchanged.

On Windows 11 24H2+, the SWS desktop discovery function can correctly return a Progman window with a SHELLDLL_DefView child. The switcher activation code previously rejected the desktop unless the window class compared as WorkerW, and could resend synchronous wallpaper initialization messages to Explorer. The patch checks the actual Win32 class name and accepts a valid Progman shell desktop or WorkerW. Existing recovery code stays in place.

## Build with GitHub Actions (recommended)

1. Open **https://github.com/U-Type/ExplorerPatcher/actions**. If GitHub prompts you to enable Actions on this fork, review the workflow and enable it.
2. Select the **Build** workflow. The push to the experimental branch should trigger a run. If not, choose **Run workflow**, select `fix/sws-progman-alt-tab-latency` as the branch, set the required `ref` field to the same branch name, and choose `Release` for configuration.
3. Select the workflow run and verify **Apply experimental SWS Progman Alt+Tab fix** and **Build ExplorerPatcher** both succeeded.
4. Scroll to **Artifacts**, download the `ep_bin_multi_...` ZIP from that experimental-branch run, extract it, and locate the 64-bit installer `x64/ep_setup.exe` in the archived build output. Do not download the upstream release installer for this experiment: it contains none of these changes.
5. Only run the newly built installer on a test machine or restorable Windows system. It can restart Explorer. Do not install an unverified build on an irreplaceable work setup.

A successful patch step is not sufficient: the entire build must succeed. If there is no workflow run, check whether GitHub Actions is enabled for forked repositories.

## Local source build (Windows)

GitHub Actions uses the upstream project's build recipe and is the preferred option. For local work, install Git, Visual Studio C++ tools, a suitable Windows SDK, and dependencies from the upstream [Compiling wiki](https://github.com/valinet/ExplorerPatcher/wiki/Compiling). Then run in PowerShell:

~~~powershell
git clone --branch fix/sws-progman-alt-tab-latency https://github.com/U-Type/ExplorerPatcher.git
cd ExplorerPatcher
git submodule update --init --recursive
pwsh -NoProfile -File .\scripts\Apply-SwsProgmanFix.ps1
~~~

Follow the upstream compiling guide afterward. The existing GitHub workflow also applies a separate Windows SDK compatibility fix; consult that step for an equivalent local build. Do not run the experimental patch helper twice without resetting the submodule; it intentionally fails if the fix was already applied.

## Compare before and after on Windows

1. Record the Windows build using Win+R -> `winver` and your ExplorerPatcher version.
2. Preserve a known-good official installer; export relevant settings, and preferably test in a VM or a restorable Windows installation.
3. On the current unmodified setup, set Simple Window Switcher **Show Delay = 0 ms**. Observe 20 repeated Alt+Tab activations, with 2 windows and then with 10–20 windows. Note desktop flickering and approximate time to display. Compare the Windows 10 switcher.
4. Install the experimental build. Choose ExplorerPatcher Properties -> Window switcher -> Simple Window Switcher, set **Show Delay = 0 ms**, and repeat the same operations, including holding Alt, quick two-window toggles, and multiple monitors if applicable. Try desktop-in-list on and off.
5. If the bug remains or there are regressions, reinstall the previous known-good official ExplorerPatcher release. The standard Windows 10 switcher is a reasonable fallback.

The source has `WindowSwitcher::Show` timing output; its first interval includes both wallpaper validation *and* window enumeration. It cannot distinguish them without additional timestamps. A perceived wallpaper refresh does not prove that explorer.exe actually restarted.

## Boundaries

- **No Windows build or performance result is claimed.** GitHub Actions is the first build-validation step.
- The patch is stored and applied in the **ExplorerPatcher fork**, not in a new SWS fork or upstream valinet repositories.
- This is not a signed or official distribution and is not a replacement for the maintainers' releases.
