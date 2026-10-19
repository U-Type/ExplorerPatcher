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
    INT iDragHoverIndex;
    HHOOK hDragWheelHook;
'@
Replace-Single 'SimpleWindowSwitcher/sws_WindowSwitcher.h' $old $new
# SimpleWindowSwitcher/sws_WindowSwitcher.c: patch 3
$old = @'
static void WINAPI _sws_WindowSwitcher_Calculate(
'@
$new = @'
// The overlay does not accept files. A layered WS_EX_TRANSPARENT window keeps
// its visual preview, while drag/drop hit testing reaches the window beneath.
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

static void _sws_WindowSwitcher_SetDragPassthrough(sws_WindowSwitcher* sws, BOOL enabled)
{
    if (!sws || !sws->hWnd) return;
    LONG_PTR oldStyle = GetWindowLongPtrW(sws->hWnd, GWL_EXSTYLE);
    LONG_PTR style = enabled ? (oldStyle | WS_EX_TRANSPARENT) : (oldStyle & ~WS_EX_TRANSPARENT);
    if (style != oldStyle)
    {
        SetWindowLongPtrW(sws->hWnd, GWL_EXSTYLE, style);
        SetWindowPos(sws->hWnd, NULL, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
    }
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
    _sws_WindowSwitcher_SetDragPassthrough(sws, FALSE);
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

static void _sws_WindowSwitcher_PollDragHover(sws_WindowSwitcher* sws)
{
    if (!sws || !sws->bDragHoverMode || !IsWindowVisible(sws->hWnd)) return;

    // OLE drag sources can keep mouse/keyboard capture: use async key and
    // cursor state rather than relying on WM_MOUSEMOVE/WM_KEYUP.
    if (!(GetAsyncKeyState(VK_MENU) & 0x8000) && !sws->bWasControl)
    {
        if (sws->bDragHoverActivated && !sws->bDragNavigationExplicit)
            ShowWindow(sws->hWnd, SW_HIDE); // do not commit an extra Alt+Tab
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
    }
'@
Replace-Single 'SimpleWindowSwitcher/sws_WindowSwitcher.c' $old $new
# SimpleWindowSwitcher/sws_WindowSwitcher.c: patch 5
$old = @'
    SetWindowPos(_this->hWnd, 0, _this->layout.iX, _this->layout.iY, _this->layout.iWidth, _this->layout.iHeight, SWP_NOZORDER);
    ShowWindow(_this->hWnd, SW_SHOW);
'@
$new = @'
    _sws_WindowSwitcher_SetDragPassthrough(_this, _this->bDragHoverMode);
    SetWindowPos(_this->hWnd, 0, _this->layout.iX, _this->layout.iY, _this->layout.iWidth, _this->layout.iHeight, SWP_NOZORDER);
    ShowWindow(_this->hWnd, SW_SHOW);
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
            if (_this->bDragHoverMode && _this->bDragHoverActivated &&
                !_this->bDragNavigationExplicit)
                ShowWindow(hWnd, SW_HIDE);
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
        if (_this->bDragHoverMode && _this->bDragHoverActivated &&
            !_this->bDragNavigationExplicit)
            ShowWindow(hWnd, SW_HIDE);
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

foreach ($name in $normalized.Keys) {
    $content = [string]$normalized[$name]
    if ($originals[$name]) { $content = $content.Replace("`n", "`r`n") }
    [IO.File]::WriteAllText((Join-Path $sws $name), $content, [Text.UTF8Encoding]::new($false))
}
if (-not $normalized['SimpleWindowSwitcher/sws_WindowSwitcher.c'].Contains('_sws_WindowSwitcher_PollDragHover')) {
    throw 'Expected drag-hover marker missing'
}
Write-Host 'Experimental SWS drag-hover modifications applied.'
