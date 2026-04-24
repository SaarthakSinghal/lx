[CmdletBinding()]
param(
    [string]$InstallDir = (Get-Location).Path,
    [string]$ProfilePath = $PROFILE,
    [switch]$SkipCurrentSessionLoad
)

$ErrorActionPreference = 'Stop'

$scriptName = 'lx.ps1'
$scriptRawUrl = 'https://raw.githubusercontent.com/saarthaksinghal/lx/main/lx.ps1'

function Write-InstallerStep {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    Write-Host "[lx installer] $Message" -ForegroundColor $Color
}

function Ensure-Directory {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        $null = New-Item -ItemType Directory -Path $Path -Force
    }
}

function Get-LocalLxSourcePath {
    param(
        [Parameter(Mandatory)]
        [string]$FileName
    )

    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        return $null
    }

    $candidate = Join-Path -Path $PSScriptRoot -ChildPath $FileName
    if (Test-Path -LiteralPath $candidate) {
        return (Resolve-Path -LiteralPath $candidate).ProviderPath
    }

    $null
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-InstallerStep -Message "PowerShell 7+ is recommended. Current version: $($PSVersionTable.PSVersion)." -Color Yellow
}

$resolvedInstallDir = [System.IO.Path]::GetFullPath($InstallDir)
$targetPath = Join-Path -Path $resolvedInstallDir -ChildPath $scriptName

Ensure-Directory -Path $resolvedInstallDir

$localSourcePath = Get-LocalLxSourcePath -FileName $scriptName
if ($localSourcePath) {
    Write-InstallerStep -Message "Installing lx from local source."
    Copy-Item -LiteralPath $localSourcePath -Destination $targetPath -Force
}
else {
    Write-InstallerStep -Message "Downloading lx from GitHub."
    Invoke-WebRequest -Uri $scriptRawUrl -OutFile $targetPath
}

if (-not $SkipCurrentSessionLoad) {
    . $targetPath
    Write-InstallerStep -Message "Attempted to load lx in the current PowerShell session."
}

$terminalIconsAvailable = $null -ne (Get-Command -Name Format-TerminalIcons -ErrorAction SilentlyContinue)
if (-not $terminalIconsAvailable) {
    Write-InstallerStep -Message "Optional: install Terminal-Icons for the best icon experience." -Color Yellow
    Write-Host "Install-Module Terminal-Icons -Scope CurrentUser" -ForegroundColor DarkGray
}

Write-Host ''
Write-InstallerStep -Message "lx installed successfully to $targetPath" -Color Green
Write-Host ''
Write-Host "Try:" -ForegroundColor Green
Write-Host "  lx" -ForegroundColor Gray
Write-Host "  lx -r" -ForegroundColor Gray
Write-Host "  lx -rs --tree" -ForegroundColor Gray
Write-Host ''
Write-Host "To load lx automatically in future sessions, add this line to `$PROFILE:" -ForegroundColor Magenta
Write-Host ''
Write-Host "  . '$targetPath'" -ForegroundColor Gray
Write-Host ''
