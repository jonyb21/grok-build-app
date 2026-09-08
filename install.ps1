#Requires -Version 5.1
<#
.SYNOPSIS
  Install the Grok Build Windows desktop app (launcher, designed icon, shortcuts).

.DESCRIPTION
  AI-agent entry point. Idempotent. Does not redistribute grok.exe.
  Installs the official Grok CLI from x.ai if missing, then builds and
  registers the custom Grok Build app wrapper.

.PARAMETER SkipCli
  Do not install or update the official Grok CLI.

.PARAMETER NoPin
  Do not attempt to pin the shortcut to the taskbar.

.PARAMETER NoShortcuts
  Build the launcher and icon only; skip Desktop / Start Menu shortcuts.
#>
[CmdletBinding()]
param(
    [switch]$SkipCli,
    [switch]$NoPin,
    [switch]$NoShortcuts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Step([string]$Message) {
    Write-Host "==> $Message"
}

function Get-RepoRoot {
    $here = $PSScriptRoot
    if (-not $here) { $here = (Get-Location).Path }
    if (Test-Path (Join-Path $here 'src\GrokBuildLauncher.cs')) { return $here }
    $parent = Split-Path -Parent $here
    if (Test-Path (Join-Path $parent 'src\GrokBuildLauncher.cs')) { return $parent }
    throw "Could not find repo root from $here (expected src\GrokBuildLauncher.cs)."
}

function Find-Csc {
    $candidates = @(
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    throw "csc.exe not found. Install .NET Framework 4.x developer tools (comes with Windows)."
}

function New-IcoFromPng {
    param(
        [Parameter(Mandatory = $true)][string]$PngPath,
        [Parameter(Mandatory = $true)][string]$IcoPath,
        [int[]]$Sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
    )
    Add-Type -AssemblyName System.Drawing
    $src = [System.Drawing.Bitmap]::FromFile($PngPath)
    try {
        $frames = New-Object 'System.Collections.Generic.List[byte[]]'
        foreach ($sz in $Sizes) {
            $bmp = New-Object System.Drawing.Bitmap $sz, $sz, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $g.Clear([System.Drawing.Color]::Transparent)
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $g.DrawImage($src, 0, 0, $sz, $sz)
            } finally {
                $g.Dispose()
            }
            $ms = New-Object System.IO.MemoryStream
            $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
            $frames.Add($ms.ToArray())
            $bmp.Dispose()
            $ms.Dispose()
        }
    } finally {
        $src.Dispose()
    }

    $fs = [System.IO.File]::Open($IcoPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    $bw = New-Object System.IO.BinaryWriter $fs
    try {
        $bw.Write([int16]0)
        $bw.Write([int16]1)
        $bw.Write([int16]$frames.Count)
        $offset = 6 + (16 * $frames.Count)
        for ($i = 0; $i -lt $frames.Count; $i++) {
            $sz = $Sizes[$i]
            $bw.Write([byte]($(if ($sz -lt 256) { $sz } else { 0 })))
            $bw.Write([byte]($(if ($sz -lt 256) { $sz } else { 0 })))
            $bw.Write([byte]0)
            $bw.Write([byte]0)
            $bw.Write([int16]1)
            $bw.Write([int16]32)
            $bw.Write([int32]$frames[$i].Length)
            $bw.Write([int32]$offset)
            $offset += $frames[$i].Length
        }
        foreach ($data in $frames) { $bw.Write($data) }
    } finally {
        $bw.Dispose()
        $fs.Dispose()
    }
}

function Ensure-UserPath([string]$Dir) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $userPath) { $userPath = '' }
    $parts = @($userPath -split ';' | Where-Object { $_ -and $_.Trim() })
    $already = $false
    foreach ($p in $parts) {
        if ([string]::Equals($p.TrimEnd('\'), $Dir.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
            $already = $true
            break
        }
    }
    if (-not $already) {
        $newPath = if ($userPath.Trim()) { "$userPath;$Dir" } else { $Dir }
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Write-Step "Added $Dir to user PATH"
    }
    if ($env:Path -notlike "*$Dir*") {
        $env:Path = "$Dir;$env:Path"
    }
}

function Install-OfficialGrokCli {
    $grokExe = Join-Path $env:USERPROFILE '.grok\bin\grok.exe'
    if (Test-Path $grokExe) {
        Write-Step "Grok CLI already present: $grokExe"
        return $grokExe
    }
    Write-Step 'Installing official Grok CLI from x.ai'
    $installer = Join-Path $env:TEMP "grok-cli-install-$(Get-Random).ps1"
    try {
        Invoke-WebRequest -Uri 'https://x.ai/cli/install.ps1' -OutFile $installer -UseBasicParsing
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer
    } finally {
        if (Test-Path $installer) { Remove-Item -Force $installer -ErrorAction SilentlyContinue }
    }
    $env:Path = "$(Join-Path $env:USERPROFILE '.grok\bin');$env:Path"
    if (-not (Test-Path $grokExe)) {
        throw "Official Grok CLI installer finished but $grokExe is missing."
    }
    return $grokExe
}

function New-GrokShortcut {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$Icon,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $w = New-Object -ComObject WScript.Shell
    $s = $w.CreateShortcut($Path)
    $s.TargetPath = $Target
    $s.WorkingDirectory = $WorkingDirectory
    $s.WindowStyle = 1
    $s.Description = 'Grok Build'
    $s.IconLocation = "$Icon,0"
    $s.Save()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($s) | Out-Null
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($w) | Out-Null
}

function Try-PinTaskbar([string]$ShortcutPath) {
    $pinCs = @'
using System;
using System.Runtime.InteropServices;
public static class GrokTaskbarPin {
    [ComImport, Guid("90AA3A4E-1CBA-4233-B8BB-535773D48449")]
    private class TaskbandPin { }
    [ComImport, Guid("0DD79AE2-D156-45D4-9EEB-3B549769E940")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPinnedList3 {
        void Method03(); void Method04(); void Method05(); void Method06();
        void Method07(); void Method08(); void Method09(); void Method10();
        void Method11(); void Method12(); void Method13(); void Method14();
        void Method15();
        [PreserveSig] int Modify(IntPtr unpin, IntPtr pin, int caller);
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHParseDisplayName(string name, IntPtr bindCtx, out IntPtr pidl, uint sfgaoIn, IntPtr psfgaoOut);
    [DllImport("ole32.dll")]
    private static extern void CoTaskMemFree(IntPtr p);
    public static int PinShortcut(string shortcutPath) {
        IntPtr pidl;
        int hr = SHParseDisplayName(shortcutPath, IntPtr.Zero, out pidl, 0, IntPtr.Zero);
        if (hr != 0 || pidl == IntPtr.Zero) return hr == 0 ? -1 : hr;
        try {
            var list = (IPinnedList3)new TaskbandPin();
            return list.Modify(IntPtr.Zero, pidl, int.MaxValue);
        } finally { CoTaskMemFree(pidl); }
    }
}
'@
    try {
        Add-Type -TypeDefinition $pinCs -Language CSharp -ErrorAction Stop
        $hr = [GrokTaskbarPin]::PinShortcut($ShortcutPath)
        return ('0x{0:X8}' -f $hr)
    } catch {
        return "pin-failed: $($_.Exception.Message)"
    }
}

function Refresh-IconCache {
    $shell32 = @'
using System;
using System.Runtime.InteropServices;
public static class GrokIconCache {
  [DllImport("shell32.dll")] public static extern void SHChangeNotify(int e, uint f, IntPtr a, IntPtr b);
}
'@
    try {
        Add-Type -TypeDefinition $shell32 -Language CSharp -ErrorAction SilentlyContinue
        [GrokIconCache]::SHChangeNotify(0x08000000, 0x1000, [IntPtr]::Zero, [IntPtr]::Zero)
    } catch { }
}

# --- main ---
$os = [System.Environment]::OSVersion.Platform
if ($os -ne [System.PlatformID]::Win32NT) {
    throw "This desktop app installer is Windows-only. On macOS/Linux install the CLI with: curl -fsSL https://x.ai/cli/install.sh | bash"
}

$RepoRoot = Get-RepoRoot
$UserGrok = Join-Path $env:USERPROFILE '.grok'
$UserBin  = Join-Path $UserGrok 'bin'
$PngSrc   = Join-Path $RepoRoot 'assets\grok-build-app-icon.png'
$CsLaunch = Join-Path $RepoRoot 'src\GrokBuildLauncher.cs'
$CsAppId  = Join-Path $RepoRoot 'src\SetShortcutAppId.cs'
$PngDst   = Join-Path $UserGrok 'grok-build.png'
$IcoDst   = Join-Path $UserGrok 'grok-build.ico'
$ExeDst   = Join-Path $UserGrok 'GrokBuild.exe'
$AppIdExe = Join-Path $UserGrok 'SetShortcutAppId.exe'
$GrokExe  = Join-Path $UserBin 'grok.exe'
$DesktopLnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Grok Build.lnk'
$StartLnk   = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Grok Build.lnk'
$ReportPath = Join-Path $UserGrok 'grok-build-app-install.json'

if (-not (Test-Path $PngSrc)) { throw "Missing designed icon: $PngSrc" }
if (-not (Test-Path $CsLaunch)) { throw "Missing launcher source: $CsLaunch" }
if (-not (Test-Path $CsAppId)) { throw "Missing AppId helper source: $CsAppId" }

New-Item -ItemType Directory -Force -Path $UserGrok, $UserBin | Out-Null

$cliInstalledNow = $false
if (-not $SkipCli) {
    if (-not (Test-Path $GrokExe)) {
        $GrokExe = Install-OfficialGrokCli
        $cliInstalledNow = $true
    } else {
        Write-Step "Grok CLI already present: $GrokExe"
    }
    Ensure-UserPath $UserBin
} elseif (-not (Test-Path $GrokExe)) {
    throw "Grok CLI not found at $GrokExe and -SkipCli was set."
}

Write-Step 'Installing designed app icon'
Copy-Item -Force $PngSrc $PngDst
New-IcoFromPng -PngPath $PngDst -IcoPath $IcoDst
Write-Step "ICO written: $IcoDst ($((Get-Item $IcoDst).Length) bytes)"

Write-Step 'Building GrokBuild.exe'
$csc = Find-Csc
$tmpExe = Join-Path $UserGrok 'GrokBuild.build.exe'
if (Test-Path $tmpExe) { Remove-Item -Force $tmpExe }
& $csc /nologo /target:winexe /optimize+ /win32icon:$IcoDst /out:$tmpExe $CsLaunch
if ($LASTEXITCODE -ne 0) { throw "csc failed building GrokBuild.exe (exit $LASTEXITCODE)" }
$relaunchNeeded = $false
try {
    Copy-Item -Force $tmpExe $ExeDst
    Remove-Item -Force $tmpExe -ErrorAction SilentlyContinue
} catch {
    $relaunchNeeded = $true
    Write-Step "GrokBuild.exe is in use; left new binary at $tmpExe (relaunch the app to pick it up)"
}
$tmpAppId = Join-Path $UserGrok 'SetShortcutAppId.build.exe'
& $csc /nologo /target:exe /optimize+ /out:$tmpAppId $CsAppId
if ($LASTEXITCODE -ne 0) { throw "csc failed building SetShortcutAppId.exe (exit $LASTEXITCODE)" }
try {
    Copy-Item -Force $tmpAppId $AppIdExe
    Remove-Item -Force $tmpAppId -ErrorAction SilentlyContinue
} catch {
    $AppIdExe = $tmpAppId
}

$shortcuts = @()
if (-not $NoShortcuts) {
    Write-Step 'Creating Desktop and Start Menu shortcuts'
    New-GrokShortcut -Path $DesktopLnk -Target $ExeDst -Icon $IcoDst -WorkingDirectory $env:USERPROFILE
    New-GrokShortcut -Path $StartLnk -Target $ExeDst -Icon $IcoDst -WorkingDirectory $env:USERPROFILE
    if (Test-Path $AppIdExe) {
        & $AppIdExe $DesktopLnk 'xAI.GrokBuild' | Out-Null
        & $AppIdExe $StartLnk 'xAI.GrokBuild' | Out-Null
    }
    $shortcuts = @($DesktopLnk, $StartLnk)
}

$pinResult = 'skipped'
if (-not $NoPin -and -not $NoShortcuts -and (Test-Path $DesktopLnk)) {
    Write-Step 'Pinning to taskbar (best-effort)'
    $pinResult = Try-PinTaskbar $DesktopLnk
    $classicPin = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Grok Build.lnk'
    $classicDir = Split-Path -Parent $classicPin
    if (Test-Path $classicDir) {
        Copy-Item -Force $DesktopLnk $classicPin
    }
}

Refresh-IconCache

$grokVersion = $null
try { $grokVersion = (& $GrokExe --version 2>$null | Out-String).Trim() } catch { $grokVersion = 'unreadable' }

$authPath = Join-Path $UserGrok 'auth.json'
$loginNeeded = -not (Test-Path $authPath)

$report = [ordered]@{
    ok                 = $true
    package            = 'grok-build-app'
    version            = '1.0.0'
    hostname           = $env:COMPUTERNAME
    user               = $env:USERNAME
    repo_root          = $RepoRoot
    grok_cli           = $GrokExe
    grok_cli_version   = $grokVersion
    grok_cli_installed = $cliInstalledNow
    grokbuild_exe      = $(if ($relaunchNeeded) { $tmpExe } else { $ExeDst })
    relaunch_needed    = $relaunchNeeded
    icon_png           = $PngDst
    icon_ico           = $IcoDst
    shortcuts          = $shortcuts
    taskbar_pin        = $pinResult
    login_needed       = $loginNeeded
    report_path        = $ReportPath
}
$report | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 $ReportPath

Write-Host ''
Write-Host 'Grok Build app installed.'
Write-Host ("  CLI:      {0} ({1})" -f $GrokExe, $grokVersion)
Write-Host ("  App:      {0}" -f $(if ($relaunchNeeded) { $tmpExe } else { $ExeDst }))
Write-Host ("  Icon:     {0}" -f $IcoDst)
foreach ($s in $shortcuts) { Write-Host ("  Shortcut: {0}" -f $s) }
Write-Host ("  Pin:      {0}" -f $pinResult)
if ($loginNeeded) {
    Write-Host '  Login:    needed — launch Grok Build once so the user can sign in at grok.com'
} else {
    Write-Host '  Login:    auth.json already present'
}
if ($relaunchNeeded) {
    Write-Host ("  Relaunch: GrokBuild.exe was in use; new binary is {0}" -f $tmpExe)
}
Write-Host ("  Report:   {0}" -f $ReportPath)
