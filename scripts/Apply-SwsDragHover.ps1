# Release-baseline experimental SWS drag-hover modifications. Run after Apply-SwsProgmanFix.ps1.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sws = Join-Path $root 'libs/sws'
$originals = @{}
$normalized = @{}
foreach ($name in @('SimpleWindowSwitcher/sws_WindowSwitcher.c',
                     'SimpleWindowSwitcher/sws_WindowSwitcher.h',
                     'SimpleWindowSwitcher/sws_def.h')) {
    $file = Join-Path $sws $name
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "SWS file missing: $file" }
    $raw = [IO.File]::ReadAllText($file)
    $originals[$name] = $raw.Contains("`r`n")
    $normalized[$name] = $raw.Replace("`r`n", "`n")
}
function Replace-Single([string]$name, [string]$old, [string]$new) {
    # On Windows a checked-out .ps1 may use CRLF here-strings. The SWS source
    # has already been normalized to LF; normalize both anchors as well.
    $old = $old.Replace("`r`n", "`n")
    $new = $new.Replace("`r`n", "`n")
    $text = [string]$script:normalized[$name]
    if (-not $text.Contains($old) -or $text.IndexOf($old) -ne $text.LastIndexOf($old)) {
        $line = (Get-PSCallStack | Select-Object -First 1).ScriptLineNumber
        throw "Expected unique SWS source anchor missing or ambiguous in $name (patch invocation line: $line; anchor starts: $($old.Substring(0, [Math]::Min(64, $old.Length))))"
    }
    $script:normalized[$name] = $text.Replace($old, $new)
}
# SimpleWindowSwitcher/sws_def.h: patch 1
$old = @'
#define SWS_WINDOWSWITCHER_TIMER_CLOSEHWND_DELAY 300
'@
$new = @'
#define SWS_WINDOWSWITCHER_TIMER_CLOSEHWND_DELAY 300
#define SWS_WINDOWSWITCHER_TIMER_DRAGHOVER 18
#define SWS_WINDOWSWITCHER_TIMER_DRAGHOVER_DELAY 25
#define SWS_WINDOWSWITCHER_DRAG_WHEEL_MSG (WM_APP + 8)
'@
Replace-Single 'SimpleWindowSwitcher/sws_def.h' $old $new
# SimpleWindowSwitcher/sws_WindowSwitcher.h: patch 2
$old = @'
    BOOL bIsMouseClicking;
'@
$new = @'
    BOOL bIsMouseClicking;
    BOOL bDragHoverMode;
    BOOL bDragHoverActivated;
    BOOL bDragNavigationExplicit;
    HWND hDragPreviewWnd;
    HWND hDragRestorePendingWnd;
    DWORD dwDragRestoreLastTick;
    INT iDragHoverIndex;
    HHOOK hDragWheelHook;
'@
Replace-Single 'SimpleWindowSwitcher/sws_WindowSwitcher.h' $old $new
# SimpleWindowSwitcher/sws_WindowSwitcher.c: patch 3
$old = @'
static void WINAPI _sws_WindowSwitcher_Calculate(
'@
$new = @'
// Keep the normal switcher overlay interactive while a dragged file is held.
// The user releases Alt before dropping the file into the target application.
static sws_WindowSwitcher* g_swsDragWheelOwner = NULL;

static LRESULT CALLBACK _sws_WindowSwitcher_DragWheelHook(int code, WPARAM wParam, LPARAM lParam)
{
    sws_WindowSwitcher* sws = g_swsDragWheelOwner;
    if (code == HC_ACTION && wParam == WM_MOUSEWHEEL && sws &&
        sws->bDragHoverMode && IsWindowVisible(sws->hWnd) &&
        sws->dwOriginalScrollWheelBehavior != SWS_SCROLLWHEELBEHAVIOR_DISABLED)
    {
        const MSLLHOOKSTRUCT* m = (const MSLLHOOKSTRUCT*)lParam;
        if (m && PostMessageW(sws->hWnd, SWS_WINDOWSWITCHER_DRAG_WHEEL_MSG,
                              (WPARAM)(SHORT)HIWORD(m->mouseData), 0))
            return 1; // prevent the underlying app from also scrolling
    }
    return CallNextHookEx(sws ? sws->hDragWheelHook : NULL, code, wParam, lParam);
}

static void _sws_WindowSwitcher_EndDragHover(sws_WindowSwitcher* sws)
{
    if (!sws) return;
    KillTimer(sws->hWnd, SWS_WINDOWSWITCHER_TIMER_DRAGHOVER);
    if (sws->hDragWheelHook)
    {
        g_swsDragWheelOwner = NULL;
        UnhookWindowsHookEx(sws->hDragWheelHook);
        sws->hDragWheelHook = NULL;
    }
    sws->bDragHoverMode = FALSE;
    sws->bDragHoverActivated = FALSE;
    sws->bDragNavigationExplicit = FALSE;
    sws->hDragPreviewWnd = NULL;
    sws->iDragHoverIndex = -1;
    sws->hDragRestorePendingWnd = NULL;
    sws->dwDragRestoreLastTick = 0;
}

static void _sws_WindowSwitcher_StartDragHover(sws_WindowSwitcher* sws)
{
    if (!sws || !sws->bDragHoverMode) return;
    SetTimer(sws->hWnd, SWS_WINDOWSWITCHER_TIMER_DRAGHOVER,
             SWS_WINDOWSWITCHER_TIMER_DRAGHOVER_DELAY, NULL);
    if (!sws->hDragWheelHook && !g_swsDragWheelOwner)
    {
        HMODULE module = NULL;
        if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                               GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                               (LPCWSTR)_sws_WindowSwitcher_DragWheelHook, &module))
        {
            sws->hDragWheelHook = SetWindowsHookExW(WH_MOUSE_LL,
                _sws_WindowSwitcher_DragWheelHook, module, 0);
            if (sws->hDragWheelHook) g_swsDragWheelOwner = sws;
        }
    }
}

// A hovered thumbnail is the definitive selection at Alt release, even if
// its earlier no-activate Z-order preview was denied or still restoring.
// Check actual cursor position immediately; Win32 mouse messages can be
// intercepted by the drag source and the 25ms poll can lag behind release.
static INT _sws_WindowSwitcher_ResolveDragHoverIndex(sws_WindowSwitcher* sws)
{
    if (!sws) return -1;
    sws_WindowSwitcherLayoutWindow* list = sws->layout.pWindowList.pList;
    if (!list) return -1;
    POINT pt;
    if (!GetCursorPos(&pt) || !ScreenToClient(sws->hWnd, &pt))
        return -1;

    // Prefer the live image itself, then the surrounding thumbnail tile
    // (title and border), which is already what WM_MOUSEMOVE highlights.
    for (int pass = 0; pass < 2; ++pass)
    {
        for (unsigned int i = 0; i < sws->layout.pWindowList.cbSize; ++i)
        {
            RECT rc = pass == 0 ? list[i].rcThumbnail : list[i].rcWindow;
            if (PtInRect(&rc, pt) && IsWindow(list[i].hWnd))
                return (INT)i;
        }
    }
    return -1;
}

static void _sws_WindowSwitcher_CompleteDragHover(sws_WindowSwitcher* sws)
{
    if (!sws) return;
    sws_WindowSwitcherLayoutWindow* list = sws->layout.pWindowList.pList;
    if (!list || !sws->layout.pWindowList.cbSize)
    {
        ShowWindow(sws->hWnd, SW_HIDE);
        return;
    }

    INT index = _sws_WindowSwitcher_ResolveDragHoverIndex(sws);
    if (index < 0 && IsWindow(sws->hDragPreviewWnd))
    {
        // Preserve the most recent valid hover if Alt was released while
        // the pointer was passing through padding / empty grid space.
        for (unsigned int i = 0; i < sws->layout.pWindowList.cbSize; ++i)
        {
            if (list[i].hWnd == sws->hDragPreviewWnd)
            {
                index = (INT)i;
                break;
            }
        }
    }
    if (index >= 0)
    {
        sws->layout.iIndex = index;
        HWND target = list[index].hWnd;
        // Retain the working Win+D restore logic, but commit selection with
        // the SAME routine as a Tab/wheel selection, not SWP_NOACTIVATE.
        if (IsWindow(target) && IsIconic(target))
            ShowWindowAsync(target, SW_RESTORE);
        if (IsWindow(target))
        {
            HWND popup = sws_WindowHelpers_GetLastActivePopup(target);
            if (IsWindow(popup) && IsIconic(popup))
                ShowWindowAsync(popup, SW_RESTORE);
        }
    }

    // This path uses SwitchToThisWindow(..., TRUE) and then dismisses SWS.
    // It matches the selection path the user has confirmed always works.
    _sws_WindowSwitcher_SwitchToSelectedItemAndDismiss(sws);
}

static void _sws_WindowSwitcher_PollDragHover(sws_WindowSwitcher* sws)
{
    if (!sws || !sws->bDragHoverMode || !IsWindowVisible(sws->hWnd)) return;

    // OLE drag sources can keep mouse/keyboard capture: use async key and
    // cursor state rather than relying on WM_MOUSEMOVE/WM_KEYUP.
    if (!(GetAsyncKeyState(VK_MENU) & 0x8000) && !sws->bWasControl)
    {
        if (!sws->bDragNavigationExplicit)
            _sws_WindowSwitcher_CompleteDragHover(sws); // commit cursor-selected window
        else
            _sws_WindowSwitcher_SwitchToSelectedItemAndDismiss(sws);
        return;
    }
    // Explicit Tab or wheel input restores normal Alt+Tab selection.
    if (sws->bDragNavigationExplicit || !(GetAsyncKeyState(VK_LBUTTON) & 0x8000))
        return;

    POINT pt;
    if (!GetCursorPos(&pt) || !ScreenToClient(sws->hWnd, &pt)) return;
    sws_WindowSwitcherLayoutWindow* list = sws->layout.pWindowList.pList;
    if (!list) return;
    for (unsigned int i = 0; i < sws->layout.pWindowList.cbSize; i++)
    {
        if (!PtInRect(&list[i].rcThumbnail, pt)) continue;
        // Track the ORIGINAL thumbnail slot, not the current MRU position.
        // Re-entering a slot after hovering elsewhere activates it again.
        if (sws->iDragHoverIndex == (int)i) return;
        HWND target = list[i].hWnd;
        if (!IsWindow(target) || target == sws->hWnd ||
            (sws->layout.bIncludeWallpaper && target == sws->layout.hWndWallpaper))
        {
            sws->iDragHoverIndex = -1;
            return;
        }

        sws->iDragHoverIndex = (int)i;
        sws->hDragPreviewWnd = target;
        sws->bDragHoverActivated = TRUE; // set before focus-loss notification
        sws->layout.iIndex = (int)i;
        sws->cwIndex = (int)i;
        sws->cwMask = SWS_WINDOWFLAG_IS_ON_WINDOW | SWS_WINDOWFLAG_IS_ON_THUMBNAIL;
        HWND popup = sws_WindowHelpers_GetLastActivePopup(target);
        SwitchToThisWindow(IsWindow(popup) && IsWindowVisible(popup) ? popup : target, TRUE);

        if (sws->dwTheme == SWS_WINDOWSWITCHER_THEME_NONE)
            sws_WindowSwitcher_Paint(sws, SWS_WINDOWSWITCHER_PAINTFLAGS_REDRAWENTIRE);
        else
            RedrawWindow(sws->hWnd, NULL, NULL, RDW_INVALIDATE | RDW_INTERNALPAINT);
        return;
    }
    // A thumbnail can also be re-entered after crossing empty grid space.
    sws->iDragHoverIndex = -1;
}

static void WINAPI _sws_WindowSwitcher_Calculate(
'@
Replace-Single 'SimpleWindowSwitcher/sws_WindowSwitcher.c' $old $new
# SimpleWindowSwitcher/sws_WindowSwitcher.c: patch 4
$old = @'
static void WINAPI _sws_WindowSwitcher_Show(sws_WindowSwitcher* _this)
{
'@
$new = @'
static void WINAPI _sws_WindowSwitcher_Show(sws_WindowSwitcher* _this)
{
    // Freeze the snapshot once the drag overlay is up. Hover previews generate
    // foreground/shell events which otherwise rebuild and move the grid.
    if (_this->bDragHoverMode && IsWindowVisible(_this->hWnd))
        return;

    // Only an already-held mouse button enables drag-hover mode.
    if (!IsWindowVisible(_this->hWnd))
    {
        _this->bDragHoverMode = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;
        _this->bDragHoverActivated = FALSE;
        _this->bDragNavigationExplicit = FALSE;
        _this->hDragPreviewWnd = NULL;
        _this->iDragHoverIndex = -1;
        _this->hDragRestorePendingWnd = NULL;
        _this->dwDragRestoreLastTick = 0;
    }
'@
Replace-Single 'SimpleWindowSwitcher/sws_WindowSwitcher.c' $old $new
# SimpleWindowSwitcher/sws_WindowSwitcher.c: patch 6
$old = @'
    if (uMsg == WM_TIMER && wParam == SWS_WINDOWSWITCHER_TIMER_ASYNCKEYCHECK)
    {
        if (!_this->bWasControl && !(GetAsyncKeyState(VK_MENU) & 0x8000))
        {
            _sws_WindowSwitcher_SwitchToSelectedItemAndDismiss(_this);
            KillTimer(hWnd, SWS_WINDOWSWITCHER_TIMER_ASYNCKEYCHECK);
            return 0;
        }
    }
'@
$new = @'
    if (uMsg == WM_TIMER && wParam == SWS_WINDOWSWITCHER_TIMER_DRAGHOVER)
    {
        _sws_WindowSwitcher_PollDragHover(_this);
        return 0;
    }
    else if (uMsg == SWS_WINDOWSWITCHER_DRAG_WHEEL_MSG)
    {
        if (_this->bDragHoverMode && IsWindowVisible(hWnd))
            PostMessageW(hWnd, WM_MOUSEWHEEL, MAKEWPARAM(0, (WORD)(SHORT)wParam), 0);
        return 0;
    }
    else if (uMsg == WM_TIMER && wParam == SWS_WINDOWSWITCHER_TIMER_ASYNCKEYCHECK)
    {
        if (!_this->bWasControl && !(GetAsyncKeyState(VK_MENU) & 0x8000))
        {
            if (_this->bDragHoverMode && !_this->bDragNavigationExplicit)
                _sws_WindowSwitcher_CompleteDragHover(_this);
            else
                _sws_WindowSwitcher_SwitchToSelectedItemAndDismiss(_this);
            KillTimer(hWnd, SWS_WINDOWSWITCHER_TIMER_ASYNCKEYCHECK);
            return 0;
        }
    }
'@
Replace-Single 'SimpleWindowSwitcher/sws_WindowSwitcher.c' $old $new
# SimpleWindowSwitcher/sws_WindowSwitcher.c: patch 7
$old = @'
    else if (uMsg == WM_DESTROY)
    {
        PostQuitMessage(0);
'@
$new = @'
    else if (uMsg == WM_DESTROY)
    {
        _sws_WindowSwitcher_EndDragHover(_this);
        PostQuitMessage(0);
'@
Replace-Single 'SimpleWindowSwitcher/sws_WindowSwitcher.c' $old $new
# SimpleWindowSwitcher/sws_WindowSwitcher.c: patch 8
$old = @'
        if (wParam == FALSE)
        {
            //ResetEvent(_this->hFlashAnimationSignal);
'@
$new = @'
        if (wParam == FALSE)
        {
            _sws_WindowSwitcher_EndDragHover(_this);
            //ResetEvent(_this->hFlashAnimationSignal);
'@
Replace-Single 'SimpleWindowSwitcher/sws_WindowSwitcher.c' $old $new
# SimpleWindowSwitcher/sws_WindowSwitcher.c: patch 9
$old = @'
            //SetWindowPos(_this->hWnd, 0, _this->layout.iX, _this->layout.iY, _this->layout.iWidth, _this->layout.iHeight, SWP_NOZORDER);
            _this->dwOriginalScrollWheelBehavior = _this->dwScrollWheelBehavior;
'@
$new = @'
            //SetWindowPos(_this->hWnd, 0, _this->layout.iX, _this->layout.iY, _this->layout.iWidth, _this->layout.iHeight, SWP_NOZORDER);
            _this->dwOriginalScrollWheelBehavior = _this->dwScrollWheelBehavior;
            _sws_WindowSwitcher_StartDragHover(_this);
'@
Replace-Single 'SimpleWindowSwitcher/sws_WindowSwitcher.c' $old $new
# SimpleWindowSwitcher/sws_WindowSwitcher.c: patch 10
$old = @'
    else if ((uMsg == WM_KEYUP && wParam == VK_ESCAPE) || uMsg == WM_KILLFOCUS || (uMsg == WM_ACTIVATE && wParam == WA_INACTIVE))
    {
        _this->bWasControl = FALSE;
'@
$new = @'
    else if ((uMsg == WM_KEYUP && wParam == VK_ESCAPE) || uMsg == WM_KILLFOCUS || (uMsg == WM_ACTIVATE && wParam == WA_INACTIVE))
    {
        if (_this->bDragHoverMode && uMsg != WM_KEYUP) return 0;
        _this->bWasControl = FALSE;
'@
Replace-Single 'SimpleWindowSwitcher/sws_WindowSwitcher.c' $old $new
# SimpleWindowSwitcher/sws_WindowSwitcher.c: patch 11
$old = @'
        _sws_WindowSwitcher_SwitchToSelectedItemAndDismiss(_this);
        return 0;
    }
    else if (uMsg == WM_HOTKEY || uMsg == WM_KEYDOWN
'@
$new = @'
        if (_this->bDragHoverMode && !_this->bDragNavigationExplicit)
            _sws_WindowSwitcher_CompleteDragHover(_this);
        else
            _sws_WindowSwitcher_SwitchToSelectedItemAndDismiss(_this);
        return 0;
    }
    else if (uMsg == WM_HOTKEY || uMsg == WM_KEYDOWN
'@
Replace-Single 'SimpleWindowSwitcher/sws_WindowSwitcher.c' $old $new
# SimpleWindowSwitcher/sws_WindowSwitcher.c: patch 12
$old = @'
            else
            {
                int direction = SWS_WINDOWSWITCHERLAYOUT_COMPUTE_DIRECTION_INITIAL;
'@
$new = @'
            else
            {
                if (_this->bDragHoverMode &&
                    (uMsg == WM_MOUSEWHEEL ||
                     ((uMsg == WM_KEYDOWN || uMsg == WM_SYSKEYDOWN) && wParam == VK_TAB) ||
                     (uMsg == WM_HOTKEY && (LOWORD(lParam) & MOD_ALT))))
                    _this->bDragNavigationExplicit = TRUE;
                int direction = SWS_WINDOWSWITCHERLAYOUT_COMPUTE_DIRECTION_INITIAL;
'@
Replace-Single 'SimpleWindowSwitcher/sws_WindowSwitcher.c' $old $new
# SimpleWindowSwitcher/sws_WindowSwitcher.c: patch 13 (suppress automatic
# shell event-triggered re-enumeration during a drag preview).
$old = @'
            if (IsWindowVisible(_this->hWnd))
            {
                sws_window* pHWNDList = _this->pHWNDList.pList;
'@
$new = @'
            if (IsWindowVisible(_this->hWnd) && !_this->bDragHoverMode)
            {
                sws_window* pHWNDList = _this->pHWNDList.pList;
'@
Replace-Single 'SimpleWindowSwitcher/sws_WindowSwitcher.c' $old $new

# SimpleWindowSwitcher/sws_WindowSwitcher.c: patch 14
$old = @'
            if (IsWindowVisible(_this->hWnd) && (HWND)lParam != _this->hWnd && sws_WindowHelpers_IsAltTabWindow((HWND)lParam))
'@
$new = @'
            if (IsWindowVisible(_this->hWnd) && !_this->bDragHoverMode &&
                (HWND)lParam != _this->hWnd && sws_WindowHelpers_IsAltTabWindow((HWND)lParam))
'@
Replace-Single 'SimpleWindowSwitcher/sws_WindowSwitcher.c' $old $new

# SimpleWindowSwitcher/sws_WindowSwitcher.c: patch 15
$old = @'
                if (!pWindowList[_this->layout.iIndex].hThumbnail)
'@
$new = @'
                if (!pWindowList[_this->layout.iIndex].hThumbnail && !_this->bDragHoverMode)
'@
Replace-Single 'SimpleWindowSwitcher/sws_WindowSwitcher.c' $old $new

# SimpleWindowSwitcher/sws_WindowSwitcher.c: patch 16 (foreground-safe previews).
# Avoid taskbar flashing when a drag's OLE source owns focus/capture.
$old = @'
        sws->iDragHoverIndex = (int)i;
        sws->hDragPreviewWnd = target;
        sws->bDragHoverActivated = TRUE; // set before focus-loss notification
        sws->layout.iIndex = (int)i;
        sws->cwIndex = (int)i;
        sws->cwMask = SWS_WINDOWFLAG_IS_ON_WINDOW | SWS_WINDOWFLAG_IS_ON_THUMBNAIL;
        HWND popup = sws_WindowHelpers_GetLastActivePopup(target);
        SwitchToThisWindow(IsWindow(popup) && IsWindowVisible(popup) ? popup : target, TRUE);
'@
$new = @'
        // Win+D can leave windows minimized and raise the desktop. Restore
        // first, then on a later poll reapply normal-window Z ordering.
        HWND popup = sws_WindowHelpers_GetLastActivePopup(target);
        HWND preview = (IsWindow(popup) && IsWindowVisible(popup)) ? popup : target;
        BOOL minimized = IsIconic(target) || (preview != target && IsIconic(preview));
        if (minimized)
        {
            DWORD tick = GetTickCount();
            if (sws->hDragRestorePendingWnd != target ||
                (DWORD)(tick - sws->dwDragRestoreLastTick) >= 200)
            {
                sws->hDragRestorePendingWnd = target;
                sws->dwDragRestoreLastTick = tick;
                if (IsIconic(target))
                    ShowWindowAsync(target, SW_RESTORE);
                if (preview != target && IsIconic(preview))
                    ShowWindowAsync(preview, SW_RESTORE);
            }
            // Keep this choice even if Alt is released while restore is pending.
            sws->hDragPreviewWnd = target;
            sws->bDragHoverActivated = TRUE;
            sws->layout.iIndex = (int)i;
            return;
        }
        sws->hDragRestorePendingWnd = NULL;
        sws->dwDragRestoreLastTick = 0;

        // No mouse pass-through is needed: files are dropped after Alt release.
        // Keep the restored app on its original monitor underneath SWS.
        UINT flags = SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_ASYNCWINDOWPOS;
        BOOL raised = SetWindowPos(target, HWND_TOP, 0, 0, 0, 0, flags);
        if (preview != target)
            raised = SetWindowPos(preview, HWND_TOP, 0, 0, 0, 0, flags) && raised;
        if (!raised)
            return;

        sws->iDragHoverIndex = (int)i;
        sws->hDragPreviewWnd = target;
        sws->bDragHoverActivated = TRUE;
        sws->layout.iIndex = (int)i;
        sws->cwIndex = (int)i;
        sws->cwMask = SWS_WINDOWFLAG_IS_ON_WINDOW | SWS_WINDOWFLAG_IS_ON_THUMBNAIL;
'@
Replace-Single 'SimpleWindowSwitcher/sws_WindowSwitcher.c' $old $new

foreach ($name in $normalized.Keys) {
    $content = [string]$normalized[$name]
    if ($originals[$name]) { $content = $content.Replace("`n", "`r`n") }
    [IO.File]::WriteAllText((Join-Path $sws $name), $content, [Text.UTF8Encoding]::new($false))
}
if (-not $normalized['SimpleWindowSwitcher/sws_WindowSwitcher.c'].Contains('_sws_WindowSwitcher_PollDragHover')) {
    throw 'Expected drag-hover marker missing'
}
Write-Host 'Experimental SWS drag-hover modifications applied.'
