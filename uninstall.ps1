#Requires -Version 5.1
<#
.SYNOPSIS
  Remove the Grok Build desktop app wrapper (launcher, icon, shortcuts).

.DESCRIPTION
  Does not uninstall the official Grok CLI, auth.json, or config.toml.
#>
[CmdletBinding()]
param(
    [switch]$AlsoRemoveCli
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$UserGrok = Join-Path $env:USERPROFILE '.grok'
$paths = @(
    (Join-Path $UserGrok 'GrokBuild.exe'),
    (Join-Path $UserGrok 'GrokBuild.build.exe'),
    (Join-Path $UserGrok 'SetShortcutAppId.exe'),
    (Join-Path $UserGrok 'SetShortcutAppId.build.exe'),
    (Join-Path $UserGrok 'grok-build.ico'),
    (Join-Path $UserGrok 'grok-build.png'),
    (Join-Path $UserGrok 'grok-build-app-install.json'),
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Grok Build.lnk'),
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Grok Build.lnk'),
    (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Grok Build.lnk')
)

Get-Process GrokBuild -ErrorAction SilentlyContinue | Stop-Process -Force
foreach ($p in $paths) {
    if (Test-Path $p) {
        Remove-Item -Force $p
        Write-Host "Removed $p"
    }
}

if ($AlsoRemoveCli) {
    $cli = Join-Path $UserGrok 'bin\grok.exe'
    if (Test-Path $cli) {
        Remove-Item -Force $cli
        Write-Host "Removed $cli"
    }
}

Write-Host 'Uninstall complete. Official Grok CLI config/auth left in place unless -AlsoRemoveCli.'
