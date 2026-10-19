# Experimental AI-assisted patch for ExplorerPatcher's pinned Simple Window Switcher.
# Run after git submodule update --init --recursive.
# Fail closed if the pinned upstream source changes.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sws = Join-Path $root 'libs/sws'
$target = Join-Path $sws 'SimpleWindowSwitcher/sws_WindowSwitcher.c'
$patch = Join-Path $root 'patches/sws_progman_validation.patch'

if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
    throw "SWS source not found: $target. Initialize submodules first."
}
if (-not (Test-Path -LiteralPath $patch -PathType Leaf)) {
    throw "SWS patch file not found: $patch"
}

$before = [System.IO.File]::ReadAllText($target)
$useCrLf = $before.Contains("`r`n")

& git -C $sws apply --check --ignore-whitespace $patch
if ($LASTEXITCODE -ne 0) {
    throw 'Patch does not match SWS source; refusing an unverified modification.'
}
& git -C $sws apply --ignore-whitespace $patch
if ($LASTEXITCODE -ne 0) {
    throw 'git apply failed; build stopped.'
}

# git apply --ignore-whitespace accepts CRLF preimages but can introduce
# LF-only lines. Restore the source file's original newline convention.
$after = [System.IO.File]::ReadAllText($target)
$after = $after.Replace("`r`n", "`n")
if ($useCrLf) {
    $after = $after.Replace("`n", "`r`n")
}
[System.IO.File]::WriteAllText(
    $target,
    $after,
    [System.Text.UTF8Encoding]::new($false)
)
if (-not $after.Contains('BOOL bIsValidWallpaperWindow = FALSE;')) {
    throw 'Source did not contain the expected patched validation.'
}
Write-Host 'Experimental SWS Progman fix applied to libs/sws source.'
